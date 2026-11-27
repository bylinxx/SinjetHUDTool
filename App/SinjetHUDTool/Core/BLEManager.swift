import CoreBluetooth
import Foundation

protocol BLEManagerDelegate: AnyObject {
    func bleManager(_ manager: BLEManager, didUpdateState state: BLEConnectionState)
    func bleManager(_ manager: BLEManager, didUpdateDiscovered devices: [DiscoveredHUD])
    func bleManager(_ manager: BLEManager, didBecomeReady peripheralName: String, moduleType: Int, maxWriteLength: Int, writeWithResponse: Bool)
    func bleManager(_ manager: BLEManager, didDisconnect reason: String?)
    func bleManager(_ manager: BLEManager, didReceiveFrame payload: Data)
    func bleManager(_ manager: BLEManager, didLog direction: LogDirection, summary: String, hex: String)
}

/// 极致轻量 CoreBluetooth 引擎（零定位、连接即停扫、按需定时器、三档流控 + 背压）
final class BLEManager: NSObject {
    static let serviceFFE0 = CBUUID(string: "FFE0")
    static let charFFE1 = CBUUID(string: "FFE1")
    static let charFFE2 = CBUUID(string: "FFE2")

    static let serviceFF00 = CBUUID(string: "FF00")
    static let charFF01 = CBUUID(string: "FF01")
    static let charFF02 = CBUUID(string: "FF02")

    static let allowedNames: Set<String> = ["Sinjet", "ChanganMazda", "ChanganHUD"]

    weak var delegate: BLEManagerDelegate?

    private let bleQueue = DispatchQueue(label: "com.sinjet.hudtool.ble", qos: .userInitiated)
    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?

    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var discoveredByID: [UUID: DiscoveredHUD] = [:]

    private let rxParser = FrameRxParser()

    private(set) var connectionState: BLEConnectionState = .idle
    private var currentModuleType: Int = 1
    private var currentMaxWriteLength: Int = 20
    private var useWriteWithResponse: Bool = false
    private var mcuRxRate: UInt32 = 800
    private var speedMode: TransferSpeedMode = .balanced

    // 待发字节队列（支持低功耗按需调度）
    private var pendingBytes = Data()
    private var txTimer: DispatchSourceTimer?
    private var awaitingWriteResponse: Bool = false
    private var writeResponseDeadline: Date?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - 外部控制接口

    func updateSpeedMode(_ mode: TransferSpeedMode) {
        bleQueue.async {
            self.speedMode = mode
            self.rescheduleTimerIfNeeded()
        }
    }

    func updateMCURxRate(_ rate: UInt32) {
        bleQueue.async {
            self.mcuRxRate = rate
            self.rescheduleTimerIfNeeded()
        }
    }

    func startScan() {
        bleQueue.async {
            guard self.centralManager.state == .poweredOn else {
                self.notifyState(self.mappedCentralState(self.centralManager.state))
                return
            }
            self.discoveredByID.removeAll()
            self.peripheralsByID.removeAll()

            // 1. 先找回系统已连接的 Sinjet (moduleType = 4)
            let connected = self.centralManager.retrieveConnectedPeripherals(withServices: [Self.serviceFFE0])
            for p in connected {
                let name = p.name ?? ""
                if name == "Sinjet" || Self.allowedNames.contains(name) {
                    let modType = (name == "Sinjet") ? 4 : 1
                    self.peripheralsByID[p.identifier] = p
                    self.discoveredByID[p.identifier] = DiscoveredHUD(
                        id: p.identifier,
                        name: name.isEmpty ? "Sinjet" : name,
                        rssi: -45,
                        moduleType: modType,
                        isSystemConnected: true
                    )
                }
            }
            self.publishDiscoveredList()

            // 2. 低功耗扫描（关闭重复广播回调 AllowDuplicates = false）
            self.notifyState(.scanning)
            self.centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            self.emitLog(.info, summary: "开始扫描信界 HUD 蓝牙设备", hex: "")
        }
    }

    func stopScan() {
        bleQueue.async {
            if self.centralManager.isScanning {
                self.centralManager.stopScan()
            }
            if self.connectionState == .scanning {
                self.notifyState(.idle)
            }
        }
    }

    func connect(deviceID: UUID) {
        bleQueue.async {
            guard let peripheral = self.peripheralsByID[deviceID],
                  let info = self.discoveredByID[deviceID] else { return }

            if self.centralManager.isScanning {
                self.centralManager.stopScan()
            }
            if let existing = self.activePeripheral, existing.identifier != peripheral.identifier {
                self.centralManager.cancelPeripheralConnection(existing)
            }

            self.resetLinkState()
            self.activePeripheral = peripheral
            self.currentModuleType = info.moduleType
            peripheral.delegate = self
            self.notifyState(.connecting)
            self.emitLog(.info, summary: "正在连接 \(info.name) (Type \(info.moduleType))", hex: "")
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    func disconnect() {
        bleQueue.async {
            if self.centralManager.isScanning {
                self.centralManager.stopScan()
            }
            if let peripheral = self.activePeripheral {
                self.centralManager.cancelPeripheralConnection(peripheral)
            } else {
                self.resetLinkState()
                self.notifyState(.idle)
            }
        }
    }

    func clearPendingWrites() {
        bleQueue.async {
            self.pendingBytes.removeAll(keepingCapacity: false)
            self.awaitingWriteResponse = false
            self.writeResponseDeadline = nil
            self.stopTxTimer()
        }
    }

    /// 封装并入队发送指令
    func sendPayload(_ payload: Data, summary: String, suppressLog: Bool = false) {
        let frame = FrameCodec.encode(payload: payload)
        bleQueue.async {
            guard self.connectionState == .ready,
                  self.activePeripheral != nil,
                  self.writeCharacteristic != nil else {
                return
            }
            self.pendingBytes.append(frame)
            if !suppressLog {
                self.emitLog(.tx, summary: summary, hex: frame.hexSpacedString)
            }
            self.ensureTxTimerRunning()
            // 尝试立即触发一轮发送降低交互延迟
            self.pumpTxQueue()
        }
    }

    // MARK: - 内部流控与发送调度

    private func currentFlowParams() -> (intervalMs: Int, chunkLimit: Int, packetsPerTick: Int) {
        switch speedMode {
        case .safe:
            // 完全对齐原厂写线程参数
            let chunk = (mcuRxRate < 5000 || currentModuleType == 3) ? 20 : currentMaxWriteLength
            let burst = (currentModuleType == 2 || currentModuleType == 3) ? 4 : 1
            return (25, max(20, min(chunk, currentMaxWriteLength)), burst)
        case .balanced:
            if mcuRxRate >= 5000 {
                let chunk = min(currentMaxWriteLength, 100)
                return (12, max(20, chunk), 2)
            } else {
                return (14, 20, 2)
            }
        case .fast:
            let chunk = min(currentMaxWriteLength, 210)
            return (7, max(20, chunk), 4)
        }
    }

    private func ensureTxTimerRunning() {
        guard txTimer == nil else { return }
        let params = currentFlowParams()
        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(params.intervalMs),
            repeating: .milliseconds(params.intervalMs),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.pumpTxQueue()
        }
        txTimer = timer
        timer.resume()
    }

    private func rescheduleTimerIfNeeded() {
        guard txTimer != nil else { return }
        stopTxTimer()
        if !pendingBytes.isEmpty {
            ensureTxTimerRunning()
        }
    }

    private func stopTxTimer() {
        txTimer?.cancel()
        txTimer = nil
    }

    private func pumpTxQueue() {
        guard connectionState == .ready,
              let peripheral = activePeripheral,
              let writeChar = writeCharacteristic else {
            stopTxTimer()
            return
        }

        if pendingBytes.isEmpty {
            stopTxTimer()
            return
        }

        // WriteWithResponse 等待上次应答（带 250ms 超时兜底）
        if useWriteWithResponse {
            if awaitingWriteResponse {
                if let deadline = writeResponseDeadline, Date() < deadline {
                    return
                }
                awaitingWriteResponse = false
            }
            let params = currentFlowParams()
            let count = min(params.chunkLimit, pendingBytes.count)
            let chunk = pendingBytes.prefix(count)
            pendingBytes.removeFirst(count)
            awaitingWriteResponse = true
            writeResponseDeadline = Date().addingTimeInterval(0.25)
            peripheral.writeValue(Data(chunk), for: writeChar, type: .withResponse)
            if pendingBytes.isEmpty {
                stopTxTimer()
            }
            return
        }

        // WriteWithoutResponse 结合系统背压
        let params = currentFlowParams()
        var sentPackets = 0
        while sentPackets < params.packetsPerTick && !pendingBytes.isEmpty {
            if speedMode != .safe && !peripheral.canSendWriteWithoutResponse {
                // 等待 peripheralIsReady(toSendWriteWithoutResponse:) 唤醒
                return
            }
            let count = min(params.chunkLimit, pendingBytes.count)
            let chunk = pendingBytes.prefix(count)
            pendingBytes.removeFirst(count)
            peripheral.writeValue(Data(chunk), for: writeChar, type: .withoutResponse)
            sentPackets += 1
        }

        if pendingBytes.isEmpty {
            stopTxTimer()
        }
    }

    // MARK: - 状态与辅助方法

    private func resetLinkState() {
        stopTxTimer()
        pendingBytes.removeAll(keepingCapacity: false)
        awaitingWriteResponse = false
        writeResponseDeadline = nil
        notifyCharacteristic = nil
        writeCharacteristic = nil
        rxParser.reset()
        useWriteWithResponse = false
        currentMaxWriteLength = 20
        mcuRxRate = 800
    }

    private func notifyState(_ state: BLEConnectionState) {
        connectionState = state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didUpdateState: state)
        }
    }

    private func publishDiscoveredList() {
        let sorted = discoveredByID.values.sorted { lhs, rhs in
            if lhs.isSystemConnected != rhs.isSystemConnected {
                return lhs.isSystemConnected
            }
            return lhs.rssi > rhs.rssi
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didUpdateDiscovered: sorted)
        }
    }

    private func emitLog(_ direction: LogDirection, summary: String, hex: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didLog: direction, summary: summary, hex: hex)
        }
    }

    private func mappedCentralState(_ state: CBManagerState) -> BLEConnectionState {
        switch state {
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .poweredOn: return connectionState == .ready ? .ready : .idle
        default: return .idle
        }
    }

    /// 完全对齐 `BLEService` 实证 `moduleType` 判定逻辑
    private func determineModuleType(localName: String, advertisementData: [String: Any]) -> Int {
        var modType = 1
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        if localName == "Sinjet" {
            if let data = mfgData, data.count >= 2,
               data[data.startIndex] == 0x48, data[data.startIndex + 1] == 0x4D {
                // 'H', 'M'
                modType = 4
            } else if mfgData == nil || mfgData?.isEmpty == true {
                modType = 2
            }
        }

        if let data = mfgData, data.count >= 5 {
            let prefix = Array(data.prefix(5))
            // "HC-08" = 0x48, 0x43, 0x2D, 0x30, 0x38
            if prefix == [0x48, 0x43, 0x2D, 0x30, 0x38] {
                modType = 1
            }
        }
        return modType
    }

    private func finalizeCharacteristicSetupIfReady(for peripheral: CBPeripheral) {
        guard let notifyChar = notifyCharacteristic, let writeChar = writeCharacteristic else { return }
        guard connectionState != .ready else { return }

        // 决定写模式（修正原厂属性位问题，兼顾 FF02 强制写确认）
        if writeChar.uuid == Self.charFF02 {
            useWriteWithResponse = true
            currentModuleType = 3
        } else if writeChar.properties.contains(.writeWithoutResponse) {
            useWriteWithResponse = false
        } else if writeChar.properties.contains(.write) {
            useWriteWithResponse = true
            currentModuleType = 3
        } else {
            useWriteWithResponse = false
        }

        let writeType: CBCharacteristicWriteType = useWriteWithResponse ? .withResponse : .withoutResponse
        let mtuMax = peripheral.maximumWriteValueLength(for: writeType)
        currentMaxWriteLength = max(20, mtuMax)

        if !notifyChar.isNotifying {
            peripheral.setNotifyValue(true, for: notifyChar)
        }

        notifyState(.ready)
        let name = peripheral.name ?? "Sinjet HUD"
        let modType = currentModuleType
        let maxLen = currentMaxWriteLength
        let withResp = useWriteWithResponse

        emitLog(
            .info,
            summary: "通道就绪：Write=\(writeChar.uuid.uuidString) Notify=\(notifyChar.uuid.uuidString) MTU=\(maxLen)B \(withResp ? "WithResp" : "WithoutResp") Type=\(modType)",
            hex: ""
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(
                self,
                didBecomeReady: name,
                moduleType: modType,
                maxWriteLength: maxLen,
                writeWithResponse: withResp
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            resetLinkState()
            activePeripheral = nil
            notifyState(mappedCentralState(central.state))
        } else if connectionState == .poweredOff || connectionState == .unauthorized {
            notifyState(.idle)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard !localName.isEmpty else { return }

        let matched = Self.allowedNames.contains(localName) ||
            Self.allowedNames.contains { localName.localizedCaseInsensitiveContains($0) }
        guard matched else { return }

        let modType = determineModuleType(localName: localName, advertisementData: advertisementData)
        peripheralsByID[peripheral.identifier] = peripheral
        discoveredByID[peripheral.identifier] = DiscoveredHUD(
            id: peripheral.identifier,
            name: localName,
            rssi: RSSI.intValue,
            moduleType: modType,
            isSystemConnected: false
        )
        publishDiscoveredList()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if central.isScanning {
            central.stopScan()
        }
        notifyState(.discovering)
        emitLog(.info, summary: "已建立蓝牙链路，正在发现服务 FFE0 / FF00", hex: "")
        peripheral.discoverServices([Self.serviceFFE0, Self.serviceFF00])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resetLinkState()
        activePeripheral = nil
        notifyState(.idle)
        let msg = error?.localizedDescription ?? "连接失败"
        emitLog(.error, summary: "连接失败：\(msg)", hex: "")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didDisconnect: msg)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetLinkState()
        activePeripheral = nil
        notifyState(.idle)
        let msg = error?.localizedDescription
        emitLog(.warn, summary: msg == nil ? "蓝牙已断开" : "蓝牙断开：\(msg!)", hex: "")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.bleManager(self, didDisconnect: msg)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            emitLog(.error, summary: "发现服务失败：\(error.localizedDescription)", hex: "")
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            emitLog(.error, summary: "未找到 FFE0 或 FF00 服务", hex: "")
            return
        }

        // 优先主分支 FFE0，其次备用分支 FF00
        if let ffe0 = services.first(where: { $0.uuid == Self.serviceFFE0 }) {
            peripheral.discoverCharacteristics([Self.charFFE1, Self.charFFE2], for: ffe0)
        } else if let ff00 = services.first(where: { $0.uuid == Self.serviceFF00 }) {
            peripheral.discoverCharacteristics([Self.charFF01, Self.charFF02], for: ff00)
        } else {
            emitLog(.error, summary: "设备不支持信界透传服务", hex: "")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            emitLog(.error, summary: "发现特征失败：\(error.localizedDescription)", hex: "")
            return
        }
        guard let chars = service.characteristics else { return }

        if service.uuid == Self.serviceFFE0 {
            let ffe1 = chars.first(where: { $0.uuid == Self.charFFE1 })
            let ffe2 = chars.first(where: { $0.uuid == Self.charFFE2 })
            notifyCharacteristic = ffe1
            if let ffe2 {
                writeCharacteristic = ffe2
                currentModuleType = 3
            } else {
                writeCharacteristic = ffe1
            }
        } else if service.uuid == Self.serviceFF00 {
            notifyCharacteristic = chars.first(where: { $0.uuid == Self.charFF01 })
            writeCharacteristic = chars.first(where: { $0.uuid == Self.charFF02 })
            if writeCharacteristic != nil {
                currentModuleType = 3
            }
        }

        finalizeCharacteristicSetupIfReady(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            emitLog(.error, summary: "读取通知数据异常：\(error.localizedDescription)", hex: "")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        let frames = rxParser.feed(data)
        guard !frames.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for frame in frames {
                self.delegate?.bleManager(self, didReceiveFrame: frame)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        awaitingWriteResponse = false
        writeResponseDeadline = nil
        if let error {
            emitLog(.error, summary: "写特征确认失败：\(error.localizedDescription)", hex: "")
        }
        pumpTxQueue()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pumpTxQueue()
    }
}
