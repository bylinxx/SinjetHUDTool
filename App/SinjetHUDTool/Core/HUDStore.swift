import Foundation
import UIKit

/// 中央状态与全量协议处理器（严格对齐逆向实证协议 ID 0x01/0x03/0x04/0x05/0x06/0x08/0x3A/0x3F）
@MainActor
final class HUDStore: ObservableObject {
    // MARK: - BLE 与设备概览
    @Published var connectionState: BLEConnectionState = .idle
    @Published var discoveredDevices: [DiscoveredHUD] = []
    @Published var connectedDeviceName: String = ""
    @Published var deviceInfo = HUDDeviceInfo()
    @Published var keepScreenAwake: Bool = false {
        didSet { updateIdleTimer() }
    }
    @Published var enableRawProtocolLog: Bool = true
    @Published var logs: [ProtocolLogEntry] = []

    // MARK: - 车辆数据与 TPMS
    @Published var liveMetrics = VehicleLiveMetrics()
    @Published var bodyGear = BodyAndGearState()
    @Published var obdProtocol: UInt8?
    @Published var vin: String = ""
    @Published var supportedPIDCount: Int = 0
    @Published var latestPIDValues: [UInt8: Data] = [:]
    @Published var faultCodes: [String] = []
    @Published var lastFaultActionMessage: String = ""
    @Published var quickCheck = QuickCheckSummary()
    @Published var vehicleSettings = VehicleSettingsState()
    @Published var tpms = TPMSState()

    // MARK: - HUD 控制与蓝牙控车
    @Published var axelaCalibration = AxelaPanelCalibration()
    @Published var btRemotePassword: String = ""
    @Published var btRemoteStatusMessage: String = ""
    @Published var btRemoteAllowSetPassword: Bool = false

    // MARK: - `.pak` 固件刷机
    @Published var speedMode: TransferSpeedMode = .balanced {
        didSet { bleManager.updateSpeedMode(speedMode) }
    }
    @Published var autoThrottleEnabled: Bool = true
    @Published var manifestURLString: String = UserDefaults.standard.string(forKey: "manifestURLString") ?? "" {
        didSet {
            UserDefaults.standard.set(manifestURLString, forKey: "manifestURLString")
        }
    }
    @Published var remoteManifest: RemoteUpdateManifest?
    @Published var loadedPakReport: PakValidationReport?
    @Published var upgradePhase: FirmwareUpgradePhase = .idle
    @Published var upgradeTelemetry = UpgradeTelemetry()

    // MARK: - 私有协议状态
    private let bleManager = BLEManager()
    private let maxLogEntries = 250

    private var currentAppPage: HUDAppPage = .homeGeneral
    private var hasSentAppInitOK = false
    private var lastHeartbeatTime: Date = .distantPast
    private var statusPollStep: Int = 0
    private var mcuUpgradeMethod: Int = 0 // 0=未识别, 1=旧版0x37-0x39, 2=新版0x3A
    private var heartbeatTimer: Timer?

    private var vinPart0: String?
    private var vinPart1: String?
    private var supportedPIDSet = Set<UInt8>()
    private var pendingFaultCodes: [String] = []

    // 昂克赛拉按键三态（顺序 up, down, ok）
    private var axelaUpState: UInt8 = 0
    private var axelaDownState: UInt8 = 0
    private var axelaOkState: UInt8 = 0

    // 刷机内部缓冲与重传滑窗
    private var loadedPakData: Data?
    private var lastRequestedOffset: UInt32?
    private var maxRequestedOffset: UInt32 = 0
    private var recentRetransmitFlags: [Bool] = []
    private var lastAutoThrottleAt: Date = .distantPast
    private var throughputWindowStart: Date?
    private var throughputWindowBytes: Int = 0

    init() {
        bleManager.delegate = self
        bleManager.updateSpeedMode(speedMode)
    }

    // MARK: - BLE 连接操作

    func startScan() {
        bleManager.startScan()
    }

    func stopScan() {
        bleManager.stopScan()
    }

    func connect(to device: DiscoveredHUD) {
        bleManager.connect(deviceID: device.id)
    }

    func disconnect() {
        bleManager.disconnect()
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - 常规 HUD 指令发送

    func syncTimeNow() {
        bleManager.sendPayload(HUDCommands.syncTime(), summary: "同步当前时间 (01 07)")
    }

    func refreshDeviceInfo() {
        guard connectionState.isConnected else { return }
        bleManager.sendPayload(HUDCommands.reqMCUMagic(), summary: "查询 MCU Magic (3A 10)")
        bleManager.sendPayload(HUDCommands.reqMCUVersionSimple(), summary: "查询 MCU 版本 (3A 12)")
        bleManager.sendPayload(HUDCommands.reqMCUUUID(), summary: "查询 MCU UUID (3A 14)")
    }

    func setAppPage(_ page: HUDAppPage) {
        currentAppPage = page
        guard connectionState.isConnected else { return }
        bleManager.sendPayload(HUDCommands.appPageNow(page), summary: "切换页面 0x\(String(format: "%02X", page.rawValue)) (03 0D)")
    }

    func startQuickCheck() {
        guard connectionState.isConnected else { return }
        quickCheck.isRunning = true
        quickCheck.isCompleted = false
        setAppPage(.quickCheck)
        bleManager.sendPayload(HUDCommands.startQuickCheck(), summary: "启动快捷车检 (03 0E)")
    }

    func requestFaultCodesPage() {
        guard connectionState.isConnected else { return }
        setAppPage(.faultCodes)
    }

    func clearFaultCodes() {
        guard connectionState.isConnected else { return }
        lastFaultActionMessage = "正在请求清除故障码..."
        bleManager.sendPayload(HUDCommands.clearFaultCodes(), summary: "清除故障码 (03 06)")
    }

    func sendWindowSettings(frontLeft: Bool, frontRight: Bool, rear: Bool) {
        vehicleSettings.frontLeftWindow = frontLeft
        vehicleSettings.frontRightWindow = frontRight
        vehicleSettings.rearWindow = rear
        vehicleSettings.hasWindowState = true
        bleManager.sendPayload(
            HUDCommands.windowControlSetting(frontLeft: frontLeft, frontRight: frontRight, rear: rear),
            summary: "车窗设置 FL=\(frontLeft ? 1 : 0) FR=\(frontRight ? 1 : 0) R=\(rear ? 1 : 0) (03 20)"
        )
    }

    func sendLockUnlockSettings(unlockOnP: Bool, lockOnD: Bool) {
        vehicleSettings.unlockOnP = unlockOnP
        vehicleSettings.lockOnD = lockOnD
        vehicleSettings.hasLockState = true
        bleManager.sendPayload(
            HUDCommands.lockUnlockSetting(unlockOnP: unlockOnP, lockOnD: lockOnD),
            summary: "锁车设置 P解锁=\(unlockOnP ? 1 : 0) D落锁=\(lockOnD ? 1 : 0) (03 21)"
        )
    }

    // MARK: - TPMS 控制

    func startTPMSPair(for tire: TirePosition) {
        tpms.pairingTire = tire
        tpms.pairingMessage = "已请求 \(tire.title) 配对，请对该轮放气或充气..."
        bleManager.sendPayload(HUDCommands.tpmsStartPair(tire: tire), summary: "TPMS 配对 \(tire.shortName) (04 00)")
    }

    func setTPMSHighPressureAlarm(_ value: UInt8) {
        tpms.highPressureAlarm = value
        bleManager.sendPayload(HUDCommands.tpmsSetHighPressureAlarm(value), summary: "TPMS 高压阈值=\(value) (04 01)")
    }

    func setTPMSLowPressureAlarm(_ value: UInt8) {
        tpms.lowPressureAlarm = value
        bleManager.sendPayload(HUDCommands.tpmsSetLowPressureAlarm(value), summary: "TPMS 低压阈值=\(value) (04 02)")
    }

    func setTPMSHighTempAlarm(_ value: UInt8) {
        tpms.highTempAlarm = value
        bleManager.sendPayload(HUDCommands.tpmsSetHighTempAlarm(value), summary: "TPMS 高温阈值=\(value) (04 03)")
    }

    // MARK: - 昂克赛拉 HUD OSD 按键与面板控制 (ID 0x06)

    enum AxelaButtonKey {
        case up, ok, down
    }

    func setAxelaButtonPressed(_ key: AxelaButtonKey, pressed: Bool) {
        let state: UInt8 = pressed ? 0x01 : 0x00
        switch key {
        case .up: axelaUpState = state
        case .down: axelaDownState = state
        case .ok: axelaOkState = state
        }
        sendCurrentAxelaButtonState(label: pressed ? "按下" : "抬起")
    }

    /// 单击脉冲（发 0x02 后本地立即清零，防止 MCU 轮询 06 00 重复触发）
    func pulseAxelaButton(_ key: AxelaButtonKey, label: String = "单击") {
        let up: UInt8 = (key == .up) ? 0x02 : 0x00
        let down: UInt8 = (key == .down) ? 0x02 : 0x00
        let ok: UInt8 = (key == .ok) ? 0x02 : 0x00
        axelaUpState = 0
        axelaDownState = 0
        axelaOkState = 0
        bleManager.sendPayload(
            HUDCommands.axelaButton(up: up, down: down, ok: ok),
            summary: "HUD 按键[\(label)] U=\(up) D=\(down) OK=\(ok) (06 00)"
        )
    }

    private func sendCurrentAxelaButtonState(label: String) {
        bleManager.sendPayload(
            HUDCommands.axelaButton(up: axelaUpState, down: axelaDownState, ok: axelaOkState),
            summary: "HUD 按键[\(label)] U=\(axelaUpState) D=\(axelaDownState) OK=\(axelaOkState) (06 00)"
        )
    }

    func testAxelaPanelOpen() {
        bleManager.sendPayload(HUDCommands.axelaTestAngleOpen(), summary: "面板打开测试 (06 03)")
    }

    func testAxelaPanelClose() {
        bleManager.sendPayload(HUDCommands.axelaTestAngleClose(), summary: "面板关闭测试 (06 05)")
    }

    func sendAxelaOpenCalibration(_ value: Int) {
        let clamped = max(axelaCalibration.openMin, min(axelaCalibration.openMax, value))
        axelaCalibration.openCurrent = clamped
        let signed = Int8(clamping: clamped)
        bleManager.sendPayload(HUDCommands.axelaPanelOpenCali(signed), summary: "写入翻盖打开标定=\(signed) (06 02)")
    }

    func sendAxelaCloseCalibration(_ value: Int) {
        let clamped = max(axelaCalibration.closeMin, min(axelaCalibration.closeMax, value))
        axelaCalibration.closeCurrent = clamped
        let signed = Int8(clamping: clamped)
        bleManager.sendPayload(HUDCommands.axelaPanelCloseCali(signed), summary: "写入翻盖关闭标定=\(signed) (06 04)")
    }

    // MARK: - 蓝牙控车 (ID 0x05)

    func sendBTRemoteAction(_ action: BTRemoteAction) {
        bleManager.sendPayload(
            HUDCommands.btRemoteControl(action: action, password8: btRemotePassword),
            summary: "蓝牙控车: \(action.title) (05)"
        )
    }

    func verifyBTRemotePassword() {
        guard let payload = HUDCommands.btRemoteVerifyPassword(btRemotePassword) else {
            btRemoteStatusMessage = "密码需为 8 位 ASCII 字符"
            return
        }
        bleManager.sendPayload(payload, summary: "蓝牙控车校验密码 (05 A0)")
    }

    func requestBTRemoteSetPassword() {
        bleManager.sendPayload(HUDCommands.btRemoteRequestSetPassword(), summary: "请求设置控车密码 (05 A1)")
    }

    func setBTRemoteNewPassword(_ newPwd: String) {
        guard let payload = HUDCommands.btRemoteSetNewPassword(newPwd) else {
            btRemoteStatusMessage = "新密码需为 8 位 ASCII 字符"
            return
        }
        bleManager.sendPayload(payload, summary: "下发新控车密码 (05 A2)")
    }

    // MARK: - `.pak` 固件加载、远程清单拉取与刷机控制

    func loadLocalPak(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            remoteManifest = nil
            validateAndStagePak(data: data, fileName: name)
        } catch {
            upgradePhase = .failed("读取本地文件失败：\(error.localizedDescription)")
            appendLog(.error, summary: "读取本地 .pak 失败：\(error.localizedDescription)", hex: "")
        }
    }

    func fetchRemoteManifestAndDownload() async {
        let trimmed = manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let manifestURL = URL(string: trimmed),
              let scheme = manifestURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            upgradePhase = .failed("请输入有效的 http/https 更新清单 URL")
            return
        }

        upgradePhase = .fetchingManifest
        appendLog(.info, summary: "拉取更新清单：\(trimmed)", hex: "")

        do {
            var req = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
            req.setValue("SinjetHUDTool/1.0", forHTTPHeaderField: "User-Agent")
            let (jsonData, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "清单 HTTP \(http.statusCode)"])
            }

            let manifest = try JSONDecoder().decode(RemoteUpdateManifest.self, from: jsonData)
            remoteManifest = manifest
            appendLog(.info, summary: "清单解析成功：vcode=\(manifest.vcode) md5=\(manifest.md5)", hex: "")

            guard let pakURL = URL(string: manifest.url) else {
                throw NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "清单内固件 URL 无效"])
            }

            upgradePhase = .downloadingPak
            var pakReq = URLRequest(url: pakURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
            pakReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let (pakData, pakResp) = try await URLSession.shared.data(for: pakReq)
            if let http = pakResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "固件下载 HTTP \(http.statusCode)"])
            }

            let actualMD5 = PakValidator.md5LowerHex(pakData)
            if actualMD5 != manifest.md5.lowercased() {
                throw NSError(
                    domain: "MD5",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "下载文件 MD5 不一致 (期望 \(manifest.md5.prefix(8))..., 实得 \(actualMD5.prefix(8))...)"]
                )
            }

            validateAndStagePak(data: pakData, fileName: pakURL.lastPathComponent)
        } catch {
            upgradePhase = .failed(error.localizedDescription)
            appendLog(.error, summary: "远程拉取失败：\(error.localizedDescription)", hex: "")
        }
    }

    private func validateAndStagePak(data: Data, fileName: String) {
        Task.detached(priority: .userInitiated) {
            let report = PakValidator.validate(data: data, fileName: fileName)
            await MainActor.run {
                self.loadedPakData = data
                self.loadedPakReport = report
                self.resetUpgradeTelemetry(totalBytes: data.count)
                if report.isStructurallyValid {
                    self.upgradePhase = .validatedReady
                    self.appendLog(
                        .info,
                        summary: ".pak 预检通过：\(fileName) (\(report.recordCount) 记录, 模块=\(report.primaryModule ?? "-"), 版本=\(report.fileVersion))",
                        hex: ""
                    )
                } else {
                    let reason = report.structuralError ?? "校验异常 (MD5错=\(report.md5ErrorCount), 头错=\(report.headerErrorCount), 块错=\(report.blockErrorCount))"
                    self.upgradePhase = .failed(reason)
                    self.appendLog(.error, summary: ".pak 预检未通过：\(reason)", hex: "")
                }
            }
        }
    }

    /// 刷前硬性安全门槛校验（返回 nil 代表完全可刷）
    func upgradePrecheckBlocker() -> String? {
        guard connectionState.isConnected else { return "请先蓝牙连接 HUD" }
        guard !deviceInfo.mcuMagic.isEmpty else { return "尚未读取到 HUD 模块型号 (Magic)" }
        guard deviceInfo.mcuMagic != "FFFFFFFF" else { return "HUD 上报非法 Magic (FFFFFFFF)" }
        guard let report = loadedPakReport, loadedPakData != nil else { return "尚未加载 .pak 固件" }
        guard report.isStructurallyValid else { return "固件本地完整性预检未通过" }
        guard report.swModules.contains(deviceInfo.mcuMagic) else {
            return "型号不匹配：HUD 为 \(deviceInfo.mcuMagic)，固件为 \(report.swModules.joined(separator: "/"))"
        }
        if !deviceInfo.isBootloaderMode && deviceInfo.mcuVersion > 0 && report.fileVersion <= deviceInfo.mcuVersion {
            return "版本号必须高于本机当前版本（本机 \(deviceInfo.mcuVersion)，固件 \(report.fileVersion)）"
        }
        return nil
    }

    func startFirmwareTransfer() {
        if let blocker = upgradePrecheckBlocker() {
            upgradePhase = .failed(blocker)
            return
        }
        guard let data = loadedPakData, let report = loadedPakReport else { return }

        resetUpgradeTelemetry(totalBytes: data.count)
        upgradeTelemetry.startedAt = Date()
        throughputWindowStart = Date()
        throughputWindowBytes = 0
        upgradePhase = .handshaking
        updateIdleTimer()

        sendUpgradeMetadata(data: data, report: report)
    }

    func abortFirmwareTransfer() {
        bleManager.clearPendingWrites()
        if loadedPakReport?.isStructurallyValid == true {
            upgradePhase = .validatedReady
        } else {
            upgradePhase = .idle
        }
        updateIdleTimer()
        appendLog(.warn, summary: "用户已中止固件传输", hex: "")
    }

    /// 发送 `3A 30 01 00` 触发 HUD 立即重启并刷写
    func confirmRebootAndFlash() {
        guard connectionState.isConnected else { return }
        bleManager.sendPayload(HUDCommands.reqMCUStartUpgrade(immediate: true), summary: "触发 HUD 立即升级并重启 (3A 30 01 00)")
        deviceInfo.mcuVersion = 0
        upgradePhase = .rebootTriggered
        updateIdleTimer()
    }

    private func sendUpgradeMetadata(data: Data, report: PakValidationReport) {
        let payload = HUDCommands.sendUpgradeFileMD5(
            fileSize: UInt32(data.count),
            md5LowerHex32: report.wholeFileMD5,
            fileVersion: report.fileVersion
        )
        bleManager.sendPayload(
            payload,
            summary: "通告 .pak 元数据 size=\(data.count) ver=\(report.fileVersion) (3A 16)"
        )
    }

    private func resetUpgradeTelemetry(totalBytes: Int) {
        upgradeTelemetry = UpgradeTelemetry(totalBytes: totalBytes)
        lastRequestedOffset = nil
        maxRequestedOffset = 0
        recentRetransmitFlags.removeAll()
        throughputWindowStart = nil
        throughputWindowBytes = 0
    }

    // MARK: - 心跳与步进状态轮询

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onHeartbeatTick()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func onHeartbeatTick() {
        guard connectionState.isConnected else { return }
        // 刷机传输期间避免无关轮询抢占 UART 带宽，仅维持必要心跳
        if Date().timeIntervalSince(lastHeartbeatTime) >= 3.0 {
            lastHeartbeatTime = Date()
            bleManager.sendPayload(HUDCommands.heartbeat(), summary: "心跳保活 (03 AA)", suppressLog: upgradePhase == .transferring)
        }
        if !upgradePhase.isBusy {
            runStatusPollStep()
        }
    }

    /// 对齐 `BLEDataProc.reqStatusStepProc` (`0 -> 1 -> 2 -> 0`)
    private func runStatusPollStep() {
        defer { statusPollStep = (statusPollStep + 1) % 3 }
        guard statusPollStep == 0 else { return }

        if mcuUpgradeMethod == 0 {
            bleManager.sendPayload(HUDCommands.reqMCUVersionSimple(), summary: "探测新版 MCU 版本 (3A 12)", suppressLog: true)
            bleManager.sendPayload(HUDCommands.reqMCUVersionLegacy(), summary: "探测旧版 MCU 版本 (37 12)", suppressLog: true)
        } else if mcuUpgradeMethod == 2 {
            if deviceInfo.mcuMagic.isEmpty {
                bleManager.sendPayload(HUDCommands.reqMCUMagic(), summary: "查询 MCU Magic (3A 10)")
            } else if deviceInfo.mcuVersion == 0 && !deviceInfo.isBootloaderMode {
                bleManager.sendPayload(HUDCommands.reqMCUVersionSimple(), summary: "查询 MCU 版本 (3A 12)")
            } else if !deviceInfo.isBootloaderMode && deviceInfo.mcuUUID.isEmpty {
                bleManager.sendPayload(HUDCommands.reqMCUUUID(), summary: "查询 MCU UUID (3A 14)")
            }
        }
    }

    // MARK: - 全量 RX 帧分发 (对齐 `BLEDataProc.dealBTMsg:`)

    private func handleReceivedFrame(_ payload: Data) {
        guard let msgID = payload.first else { return }

        // 首次收到任意合法帧 -> 发 APP Init OK
        if !hasSentAppInitOK {
            hasSentAppInitOK = true
            bleManager.sendPayload(HUDCommands.appInitOK(), summary: "APP 初始化完成握手 (03 00 01)")
        }

        if Date().timeIntervalSince(lastHeartbeatTime) >= 3.0 {
            lastHeartbeatTime = Date()
            bleManager.sendPayload(HUDCommands.heartbeat(), summary: "心跳保活 (03 AA)", suppressLog: upgradePhase == .transferring)
        }

        if !upgradePhase.isBusy {
            runStatusPollStep()
        }

        let body = payload.dropFirst()
        switch msgID {
        case 0x01:
            handleID01(Data(body))
        case 0x03:
            handleID03(Data(body))
        case 0x04:
            handleID04(Data(body))
        case 0x05:
            handleID05(Data(body))
        case 0x06:
            handleID06(Data(body))
        case 0x08:
            handleID08(Data(body))
        case 0x37, 0x38, 0x39:
            mcuUpgradeMethod = 1
            appendLog(.rx, summary: "旧版升级协议帧 0x\(String(format: "%02X", msgID))", hex: payload.hexSpacedString)
        case 0x3A:
            mcuUpgradeMethod = 2
            handleID3A(payload)
        case 0x3F:
            handleID3F(payload)
        default:
            break
        }
    }

    // MARK: - ID 0x01 时间同步请求

    private func handleID01(_ msg: Data) {
        guard msg.count >= 2, msg[0] == 0x07, msg[1] == 0x00 else { return }
        appendLog(.rx, summary: "HUD 请求同步时间 (01 07 00)", hex: msg.hexSpacedString)
        syncTimeNow()
    }

    // MARK: - ID 0x03 核心 OBD / 车身 / 车检 / 故障码 / 设置回读

    private func handleID03(_ msg: Data) {
        guard let subCmd = msg.first else { return }
        switch subCmd {
        case 0x00:
            if msg.count >= 2 && msg[1] == 0x01 {
                deviceInfo.mcuInitOK = true
                appendLog(.rx, summary: "MCU 初始化完成 (03 00 01)", hex: msg.hexSpacedString)
            }
        case 0x01:
            if msg.count >= 2 {
                deviceInfo.hudHardwareModuleType = msg[1]
                appendLog(.rx, summary: "HUD 硬件类型 = \(msg[1])\(msg[1] == 3 ? " (支持 OSD 遥控)" : "")", hex: msg.hexSpacedString)
            }
        case 0x02:
            if msg.count >= 2 {
                obdProtocol = msg[1]
            }
        case 0x03:
            if msg.count >= 3 {
                let segment = msg[1]
                let text = String(decoding: msg.dropFirst(2), as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet.controlCharacters.union(.whitespaces))
                if segment == 0 {
                    vinPart0 = text
                } else if segment == 1 {
                    vinPart1 = text
                }
                if let p0 = vinPart0, let p1 = vinPart1 {
                    vin = p0 + p1
                } else if let p0 = vinPart0 {
                    vin = p0
                }
            }
        case 0x06:
            guard msg.count >= 3 else { return }
            let mask = msg[1]
            let gear = msg[2]
            bodyGear.frontLeftDoorOpen = (mask & 0x01) != 0
            bodyGear.frontRightDoorOpen = (mask & 0x02) != 0
            bodyGear.rearLeftDoorOpen = (mask & 0x04) != 0
            bodyGear.rearRightDoorOpen = (mask & 0x08) != 0
            bodyGear.handbrakeOn = (mask & 0x10) != 0
            bodyGear.trunkOpen = (mask & 0x20) != 0
            bodyGear.driverSeatbeltUnbuckled = (mask & 0x80) == 0
            bodyGear.gearModeRaw = gear >> 4
            bodyGear.gearNumberRaw = gear & 0x0F
            bodyGear.hasReceived = true
        case 0x08:
            guard msg.count >= 3 else { return }
            let pid = msg[1]
            latestPIDValues[pid] = Data(msg.dropFirst(2))
        case 0x09...0x0E:
            guard msg.count >= 5 else { return }
            let basePID = Int(subCmd - 0x09) * 32 + 1
            for byteIdx in 0..<4 {
                let b = msg[1 + byteIdx]
                for bit in 0..<8 {
                    if (b & (0x80 >> bit)) != 0 {
                        let pid = basePID + byteIdx * 8 + bit
                        if pid <= 255 {
                            supportedPIDSet.insert(UInt8(pid))
                        }
                    }
                }
            }
            supportedPIDCount = supportedPIDSet.count
        case 0x0F:
            guard msg.count >= 2 else { return }
            quickCheck.isRunning = (msg[1] == 0x00)
            quickCheck.isCompleted = (msg[1] == 0x01)
            appendLog(.rx, summary: msg[1] == 0x01 ? "快捷车检完成 (03 0F 01)" : "快捷车检进行中 (03 0F 00)", hex: msg.hexSpacedString)
        case 0x10:
            guard msg.count >= 13,
                  let voltRaw = msg.readUInt16BE(at: 1),
                  let rpmRaw = msg.readUInt16BE(at: 3),
                  let milesRaw = msg.readUInt16BE(at: 7),
                  let oilRaw = msg.readUInt16BE(at: 9) else { return }
            let speed = Int(msg[5])
            let rpm = Int(rpmRaw >> 2)
            let coolantByte = msg[6]
            let fuelRaw = msg[11]
            let alarms = msg[12]

            liveMetrics.voltage = Double(voltRaw) / 1000.0
            liveMetrics.rpm = rpm
            liveMetrics.speed = speed
            if speed == 0 && rpm > 0 {
                liveMetrics.idleRpm = rpm
            }
            liveMetrics.coolantTemp = (coolantByte == 0xFF) ? nil : (Int(coolantByte) - 40)
            liveMetrics.mileage = Int(milesRaw)
            liveMetrics.fuelConsumption = Double(oilRaw) / 100.0
            liveMetrics.fuelLevelPercent = Int((Double(fuelRaw) * 100.0 / 255.0).rounded())
            liveMetrics.voltageAlarmFlag = alarms >> 4
            liveMetrics.coolantAlarmFlag = alarms & 0x0F
            liveMetrics.lastUpdated = Date()
        case 0x12:
            guard msg.count >= 2 else { return }
            let flag = msg[1]
            if flag == 0xFF {
                pendingFaultCodes.removeAll()
                appendLog(.rx, summary: "开始接收故障码列表 (03 12 FF)", hex: msg.hexSpacedString)
            } else if flag == 0x00 {
                faultCodes = pendingFaultCodes
                lastFaultActionMessage = faultCodes.isEmpty ? "当前无故障码" : "共读取到 \(faultCodes.count) 条故障码"
                appendLog(.rx, summary: "故障码接收完成：\(faultCodes.count) 条", hex: msg.hexSpacedString)
            } else if msg.count >= 4 {
                var idx = 2
                while idx + 1 < msg.count {
                    let b0 = msg[idx]
                    let b1 = msg[idx + 1]
                    let dtc = decodeSAEJ2012(b0: b0, b1: b1)
                    if !pendingFaultCodes.contains(dtc) {
                        pendingFaultCodes.append(dtc)
                    }
                    idx += 2
                }
            }
        case 0x13:
            guard msg.count >= 2 else { return }
            if msg[1] != 0 {
                faultCodes.removeAll()
                pendingFaultCodes.removeAll()
                lastFaultActionMessage = "清除故障码成功"
                appendLog(.rx, summary: "清除故障码成功 (03 13)", hex: msg.hexSpacedString)
            } else {
                lastFaultActionMessage = "清除故障码失败"
                appendLog(.warn, summary: "清除故障码失败 (03 13 00)", hex: msg.hexSpacedString)
            }
        case 0x1A:
            guard msg.count >= 15,
                  let faultNum = msg.readUInt16BE(at: 1),
                  let voltRaw = msg.readUInt16BE(at: 3) else { return }
            let throttle = Double(msg[5]) * 100.0 / 255.0
            let coolant = Int(msg[6]) - 40
            var cats: [Int] = []
            for offset in [7, 9, 11, 13] {
                if let raw = msg.readUInt16BE(at: offset), raw != 0xFFFF {
                    cats.append(Int(raw) / 10 - 40)
                }
            }
            let primaryCat = cats.first(where: { $0 < 300 || $0 > 800 }) ?? cats.first

            quickCheck.faultCount = Int(faultNum)
            quickCheck.voltage = Double(voltRaw) / 1000.0
            quickCheck.throttlePercent = throttle
            quickCheck.coolantTemp = coolant
            quickCheck.catalystTemps = cats
            quickCheck.primaryCatalystTemp = primaryCat
            quickCheck.lastUpdated = Date()
            appendLog(.rx, summary: "收到车况体检汇总 (03 1A)：故障=\(faultNum) 节气门=\(String(format: "%.1f%%", throttle))", hex: msg.hexSpacedString)
        case 0x20:
            guard msg.count >= 4 else { return }
            vehicleSettings.frontLeftWindow = msg[1] != 0
            vehicleSettings.frontRightWindow = msg[2] != 0
            vehicleSettings.rearWindow = msg[3] != 0
            vehicleSettings.hasWindowState = true
            appendLog(.rx, summary: "回读车窗设置 (03 20)", hex: msg.hexSpacedString)
        case 0x21:
            guard msg.count >= 2 else { return }
            vehicleSettings.unlockOnP = (msg[1] & 0xF0) != 0
            vehicleSettings.lockOnD = (msg[1] & 0x0F) != 0
            vehicleSettings.hasLockState = true
            appendLog(.rx, summary: "回读 P/D 锁车设置 (03 21)", hex: msg.hexSpacedString)
        default:
            break
        }
    }

    private func decodeSAEJ2012(b0: UInt8, b1: UInt8) -> String {
        let prefixes = ["P", "C", "B", "U"]
        let p = prefixes[Int((b0 >> 6) & 0x03)]
        let d1 = (b0 >> 4) & 0x03
        let d2 = b0 & 0x0F
        let d3 = (b1 >> 4) & 0x0F
        let d4 = b1 & 0x0F
        return String(format: "%@%X%X%X%X", p, d1, d2, d3, d4)
    }

    // MARK: - ID 0x04 TPMS

    private func handleID04(_ msg: Data) {
        guard let subCmd = msg.first, subCmd <= 0x04 else { return }
        switch subCmd {
        case 0x00:
            guard msg.count >= 2 else { return }
            let tireIdx = Int((msg[1] >> 4) & 0x0F)
            let pairState = msg[1] & 0x0F
            let tire = TirePosition(rawValue: min(tireIdx, 3)) ?? .rearRight
            switch pairState {
            case 0:
                tpms.pairingTire = tire
                tpms.pairingMessage = "正在配对 \(tire.title)，请放气或充气..."
            case 1:
                tpms.pairingTire = nil
                tpms.pairingMessage = "\(tire.title) 配对成功"
            case 2:
                tpms.pairingTire = nil
                tpms.pairingMessage = "\(tire.title) 配对失败或超时退出"
            default:
                tpms.pairingTire = nil
                tpms.pairingMessage = ""
            }
            appendLog(.rx, summary: "TPMS 配对状态 \(tire.shortName) state=\(pairState)", hex: msg.hexSpacedString)
        case 0x01:
            if msg.count >= 2 { tpms.highPressureAlarm = msg[1] }
        case 0x02:
            if msg.count >= 2 { tpms.lowPressureAlarm = msg[1] }
        case 0x03:
            if msg.count >= 2 { tpms.highTempAlarm = msg[1] }
        case 0x04:
            guard msg.count >= 5 else { return }
            let idx = min(Int(msg[1]), 3)
            var tire = tpms.tires[idx]
            tire.pressureRawBCD = msg[2]
            tire.temperatureRaw = msg[3]
            tire.statusMask = msg[4]
            tire.hasData = true
            tpms.tires[idx] = tire
            if tire.supportsPair {
                tpms.supportsPairing = true
            }
        default:
            break
        }
    }

    // MARK: - ID 0x05 蓝牙控车

    private func handleID05(_ msg: Data) {
        guard let subCmd = msg.first else { return }
        switch subCmd {
        case 0xA0:
            if msg.count >= 2 {
                btRemoteStatusMessage = (msg[1] == 0) ? "控车密码校验成功" : "控车密码校验失败"
            }
        case 0xA1:
            if msg.count >= 2 {
                btRemoteAllowSetPassword = (msg[1] == 0)
                btRemoteStatusMessage = (msg[1] == 0) ? "允许设置新控车密码" : "当前不允许修改控车密码"
            }
        case 0xA2:
            if msg.count >= 2 {
                if msg[1] == 0 {
                    if msg.count >= 10 {
                        btRemotePassword = String(decoding: msg[2..<10], as: UTF8.self)
                    }
                    btRemoteStatusMessage = "新控车密码设置成功"
                } else {
                    btRemoteStatusMessage = "新控车密码设置失败"
                }
            }
        case 0xA3:
            btRemoteStatusMessage = "蓝牙控车模块就绪"
            if btRemotePassword.utf8.count == 8 {
                verifyBTRemotePassword()
            }
        case 0xE2:
            if msg.count >= 3 {
                let code = msg[2]
                btRemoteStatusMessage = (code == 7 || code == 8) ? "密码校验错误 (E2:\(code))" : "蓝牙控车执行错误 (E2:\(code))"
            }
        default:
            break
        }
        appendLog(.rx, summary: "蓝牙控车响应 0x\(String(format: "%02X", subCmd))", hex: msg.hexSpacedString)
    }

    // MARK: - ID 0x06 昂克赛拉面板校准 / 硬件信息 / MCU 错误日志

    private func handleID06(_ msg: Data) {
        guard let subCmd = msg.first else { return }
        switch subCmd {
        case 0x00:
            // MCU 轮询昂克赛拉按键状态
            sendCurrentAxelaButtonState(label: "应答轮询")
        case 0x02:
            guard msg.count >= 4 else { return }
            let cur = Int(Int8(bitPattern: msg[1]))
            let minV = Int(Int8(bitPattern: msg[2]))
            let maxV = Int(Int8(bitPattern: msg[3]))
            axelaCalibration.openCurrent = cur
            axelaCalibration.openMin = min(minV, maxV)
            axelaCalibration.openMax = max(minV, maxV)
            axelaCalibration.hasOpenRange = true
            appendLog(.rx, summary: "翻盖打开校准：当前=\(cur) 范围=[\(minV), \(maxV)]", hex: msg.hexSpacedString)
        case 0x04:
            guard msg.count >= 4 else { return }
            let cur = Int(Int8(bitPattern: msg[1]))
            let minV = Int(Int8(bitPattern: msg[2]))
            let maxV = Int(Int8(bitPattern: msg[3]))
            axelaCalibration.closeCurrent = cur
            axelaCalibration.closeMin = min(minV, maxV)
            axelaCalibration.closeMax = max(minV, maxV)
            axelaCalibration.hasCloseRange = true
            appendLog(.rx, summary: "翻盖关闭校准：当前=\(cur) 范围=[\(minV), \(maxV)]", hex: msg.hexSpacedString)
        case 0xAA:
            guard msg.count >= 12 else { return }
            deviceInfo.pcbVersion = msg[1]
            deviceInfo.storageOpenAD = msg.readUInt16LE(at: 6)
            deviceInfo.nowOpenAD = msg.readUInt16LE(at: 10)
            appendLog(.rx, summary: "硬件信息(AA)：PCB=\(msg[1]) OpenAD=\(deviceInfo.nowOpenAD ?? 0)", hex: msg.hexSpacedString)
        case 0xAB:
            guard msg.count >= 6 else { return }
            deviceInfo.pcbVersion = msg[1]
            deviceInfo.storageOpenAD = msg.readUInt16LE(at: 2)
            deviceInfo.nowOpenAD = msg.readUInt16LE(at: 4)
            appendLog(.rx, summary: "硬件信息(AB)：PCB=\(msg[1]) OpenAD=\(deviceInfo.nowOpenAD ?? 0)", hex: msg.hexSpacedString)
        case 0xAC:
            guard msg.count >= 2 else { return }
            let rawBytes = msg.dropFirst().prefix { $0 != 0 }
            let errText = String(decoding: rawBytes, as: UTF8.self)
            deviceInfo.lastErrorMessage = errText
            appendLog(.warn, summary: "MCU 错误日志：\(errText)", hex: msg.hexSpacedString)
            bleManager.sendPayload(HUDCommands.mcuErrorMsgAck(), summary: "应答 MCU 错误日志 (06 AC 00)")
        default:
            break
        }
    }

    // MARK: - ID 0x08 TTS 播报完成

    private func handleID08(_ msg: Data) {
        if msg.count >= 2 && msg[0] == 0x0A && msg[1] == 0x01 {
            appendLog(.rx, summary: "MCU TTS 播报完成 (08 0A 01)", hex: msg.hexSpacedString)
        }
    }

    // MARK: - ID 0x3F 经销商代码

    private func handleID3F(_ payload: Data) {
        guard payload.count >= 3, payload[1] == 0x10 else { return }
        let code = String(decoding: payload.dropFirst(2), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.controlCharacters.union(.whitespaces))
        deviceInfo.distributorCode = code
        appendLog(.rx, summary: "经销商代码：\(code)", hex: payload.hexSpacedString)
    }

    // MARK: - ID 0x3A 新版 `.pak` 固件协议与 Pull 状态机 (`MCUUpgradeSimple`)

    private func handleID3A(_ payload: Data) {
        guard payload.count >= 2 else { return }
        let subCmd = payload[1]

        switch subCmd {
        case 0x11:
            // Magic (payload[2..9]) + mcuRxRate (payload[10..13] u32 LE)
            guard payload.count >= 10 else { return }
            if payload[2] == 0xFF {
                deviceInfo.mcuMagic = "FFFFFFFF"
                appendLog(.error, summary: "MCU Magic 非法 (FFFFFFFF)", hex: payload.hexSpacedString)
            } else {
                let magicBytes = payload[2..<10].prefix { $0 != 0 }
                deviceInfo.mcuMagic = String(decoding: magicBytes, as: UTF8.self)
            }

            var rate: UInt32 = 800
            if payload.count >= 14, let rawRate = payload.readUInt32LE(at: 10), rawRate > 0 {
                rate = min(rawRate, 5000)
            }
            deviceInfo.mcuRxRate = rate
            bleManager.updateMCURxRate(rate)
            appendLog(.rx, summary: "MCU Magic=\(deviceInfo.mcuMagic), RxRate=\(rate) B/s (3A 11)", hex: payload.hexSpacedString)

        case 0x13:
            // 当前版本号 payload[2..9] (8B ASCII 十进制，任一 0xFF 视为 Bootloader 模式)
            guard payload.count >= 10 else { return }
            let slice = payload[2..<10]
            if slice.contains(0xFF) {
                deviceInfo.isBootloaderMode = true
                deviceInfo.mcuVersion = 0xFFFFFFFF
                appendLog(.warn, summary: "MCU 当前处于 Bootloader 模式 (3A 13)", hex: payload.hexSpacedString)
            } else {
                deviceInfo.isBootloaderMode = false
                let verStr = String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                deviceInfo.mcuVersion = UInt32(verStr) ?? 0
                appendLog(.rx, summary: "MCU 当前版本=\(deviceInfo.mcuVersion) (3A 13)", hex: payload.hexSpacedString)
            }

        case 0x15:
            guard payload.count >= 3 else { return }
            deviceInfo.mcuUUID = payload.dropFirst(2).map { String(format: "%02x", $0) }.joined()
            appendLog(.rx, summary: "MCU UUID=\(deviceInfo.mcuUUID) (3A 15)", hex: payload.hexSpacedString)

        case 0x17:
            // MCU 请求整包元数据
            guard let data = loadedPakData, let report = loadedPakReport,
                  upgradePhase == .handshaking || upgradePhase == .transferring else { return }
            appendLog(.rx, summary: "MCU 请求 .pak 元数据 (3A 17)", hex: payload.hexSpacedString)
            sendUpgradeMetadata(data: data, report: report)

        case 0x19:
            // MCU 请求区间 MD5: offset (payload[2..5]), dataSize (payload[6..9])
            guard payload.count >= 10,
                  let data = loadedPakData,
                  upgradePhase == .handshaking || upgradePhase == .transferring,
                  let offset = payload.readUInt32LE(at: 2),
                  let dataSize = payload.readUInt32LE(at: 6) else { return }
            let start = Int(offset)
            let end = min(data.count, start + Int(dataSize))
            guard start >= 0, start <= end else { return }
            let subSlice = data.subdata(in: start..<end)
            let rangeMD5 = PakValidator.md5LowerHex(subSlice)
            upgradeTelemetry.rangeMD5Requests += 1
            let resp = HUDCommands.sendUpgradeRangeMD5(offset: offset, dataSize: UInt32(subSlice.count), md5LowerHex32: rangeMD5)
            bleManager.sendPayload(resp, summary: "回复区间 MD5 off=\(offset) len=\(subSlice.count) (3A 18)")

        case 0x21:
            // MCU 拉取/重传分片: Magic(payload[2..9]), offset(payload[10..13]), length(payload[14..15])
            guard payload.count >= 16,
                  let data = loadedPakData,
                  let report = loadedPakReport,
                  upgradePhase == .handshaking || upgradePhase == .transferring,
                  let offset = payload.readUInt32LE(at: 10),
                  let reqLen = payload.readUInt16LE(at: 14) else { return }

            let reqMagic = String(decoding: payload[2..<10].prefix { $0 != 0 }, as: UTF8.self)
            if !reqMagic.isEmpty && !report.swModules.contains(reqMagic) {
                bleManager.clearPendingWrites()
                upgradePhase = .failed("传输中止：HUD 请求模块 \(reqMagic) 与本地固件不匹配")
                updateIdleTimer()
                return
            }

            if upgradePhase != .transferring {
                upgradePhase = .transferring
            }

            // 统计重传并触发自动降速保险
            let isRetransmit: Bool
            if let lastOff = lastRequestedOffset, offset == lastOff {
                isRetransmit = true
                upgradeTelemetry.consecutiveSameOffsetRetransmits += 1
            } else if offset < maxRequestedOffset {
                isRetransmit = true
                upgradeTelemetry.consecutiveSameOffsetRetransmits = 1
            } else {
                isRetransmit = false
                upgradeTelemetry.consecutiveSameOffsetRetransmits = 0
                maxRequestedOffset = offset
            }
            lastRequestedOffset = offset

            if isRetransmit {
                upgradeTelemetry.totalRetransmits += 1
            }
            recentRetransmitFlags.append(isRetransmit)
            if recentRetransmitFlags.count > 20 {
                recentRetransmitFlags.removeFirst()
            }
            evaluateAutoThrottleIfNeeded()

            // 计算切片（严格遵守 200B 硬上限）
            let start = Int(offset)
            guard start < data.count else { return }
            let sendLen = min(Int(reqLen), data.count - start, 200)
            let chunk = data.subdata(in: start..<(start + sendLen))

            upgradeTelemetry.dataRequests += 1
            upgradeTelemetry.bytesSentOffset = max(upgradeTelemetry.bytesSentOffset, start + sendLen)

            // 统计实测吞吐率
            throughputWindowBytes += sendLen
            let now = Date()
            if let winStart = throughputWindowStart {
                let elapsed = now.timeIntervalSince(winStart)
                if elapsed >= 1.0 {
                    upgradeTelemetry.throughputBytesPerSec = Double(throughputWindowBytes) / elapsed
                    throughputWindowStart = now
                    throughputWindowBytes = 0
                }
            } else {
                throughputWindowStart = now
            }

            let resp = HUDCommands.sendUpgradeFileChunk(offset: offset, slice: chunk)
            bleManager.sendPayload(resp, summary: "3A 20 off=\(offset) len=\(sendLen)", suppressLog: true)

        case 0x23:
            guard payload.count >= 6, let sec = payload.readInt32LE(at: 2) else { return }
            upgradeTelemetry.estimatedRemainingSeconds = max(0, Int(sec))

        case 0x31:
            guard payload.count >= 7, let readyVersion = payload.readUInt32LE(at: 3) else { return }
            if deviceInfo.isBootloaderMode || readyVersion > deviceInfo.mcuVersion {
                upgradeTelemetry.bytesSentOffset = upgradeTelemetry.totalBytes
                upgradePhase = .readyToReboot(readyVersion: readyVersion)
                appendLog(.info, summary: "固件传输与校验全部完成！就绪版本=\(readyVersion) (3A 31)", hex: payload.hexSpacedString)
            }

        default:
            appendLog(.rx, summary: "未知 0x3A 子命令 0x\(String(format: "%02X", subCmd))", hex: payload.hexSpacedString)
        }
    }

    private func evaluateAutoThrottleIfNeeded() {
        guard autoThrottleEnabled else { return }
        let recentCount = recentRetransmitFlags.filter { $0 }.count
        let shouldStepDown = upgradeTelemetry.consecutiveSameOffsetRetransmits >= 2 || recentCount >= 3
        guard shouldStepDown,
              Date().timeIntervalSince(lastAutoThrottleAt) >= 2.0,
              let lower = speedMode.steppedDown else {
            return
        }

        let prev = speedMode
        speedMode = lower
        lastAutoThrottleAt = Date()
        recentRetransmitFlags.removeAll()
        upgradeTelemetry.consecutiveSameOffsetRetransmits = 0
        upgradeTelemetry.autoThrottleNotice = "检测到重传，已自动降速：\(prev.rawValue) → \(lower.rawValue)"
        appendLog(.warn, summary: upgradeTelemetry.autoThrottleNotice, hex: "")
    }

    // MARK: - 通用辅助

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake || upgradePhase.isBusy
    }

    private func appendLog(_ direction: LogDirection, summary: String, hex: String) {
        guard enableRawProtocolLog || direction == .error || direction == .warn else { return }
        logs.append(ProtocolLogEntry(timestamp: Date(), direction: direction, summary: summary, hexBytes: hex))
        if logs.count > maxLogEntries {
            logs.removeFirst(logs.count - maxLogEntries)
        }
    }
}

// MARK: - BLEManagerDelegate

extension HUDStore: BLEManagerDelegate {
    nonisolated func bleManager(_ manager: BLEManager, didUpdateState state: BLEConnectionState) {
        Task { @MainActor in
            self.connectionState = state
        }
    }

    nonisolated func bleManager(_ manager: BLEManager, didUpdateDiscovered devices: [DiscoveredHUD]) {
        Task { @MainActor in
            self.discoveredDevices = devices
        }
    }

    nonisolated func bleManager(_ manager: BLEManager, didBecomeReady peripheralName: String, moduleType: Int, maxWriteLength: Int, writeWithResponse: Bool) {
        Task { @MainActor in
            self.connectionState = .ready
            self.connectedDeviceName = peripheralName
            self.deviceInfo = HUDDeviceInfo(
                bleModuleType: moduleType,
                maxWriteLength: maxWriteLength,
                writeWithResponse: writeWithResponse
            )
            self.hasSentAppInitOK = false
            self.statusPollStep = 0
            self.mcuUpgradeMethod = 0
            self.lastHeartbeatTime = .distantPast
            self.vinPart0 = nil
            self.vinPart1 = nil
            self.vin = ""
            if self.upgradePhase == .rebootTriggered {
                self.upgradePhase = (self.loadedPakReport?.isStructurallyValid == true) ? .validatedReady : .idle
            }

            // 建连握手：对时 + 上报页面 + 立即探测版本与 Magic
            self.syncTimeNow()
            self.setAppPage(self.currentAppPage)
            self.bleManager.sendPayload(HUDCommands.reqMCUMagic(), summary: "查询 MCU Magic (3A 10)")
            self.bleManager.sendPayload(HUDCommands.reqMCUVersionSimple(), summary: "查询 MCU 版本 (3A 12)")
            self.startHeartbeatTimer()
        }
    }

    nonisolated func bleManager(_ manager: BLEManager, didDisconnect reason: String?) {
        Task { @MainActor in
            self.stopHeartbeatTimer()
            self.connectedDeviceName = ""
            self.hasSentAppInitOK = false
            self.mcuUpgradeMethod = 0
            if self.upgradePhase == .handshaking || self.upgradePhase == .transferring {
                self.upgradePhase = .failed("蓝牙断开，传输中断（重连后可利用断点续传重试）")
            }
            self.updateIdleTimer()
        }
    }

    nonisolated func bleManager(_ manager: BLEManager, didReceiveFrame payload: Data) {
        Task { @MainActor in
            self.handleReceivedFrame(payload)
        }
    }

    nonisolated func bleManager(_ manager: BLEManager, didLog direction: LogDirection, summary: String, hex: String) {
        Task { @MainActor in
            self.appendLog(direction, summary: summary, hex: hex)
        }
    }
}
