import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var store: HUDStore

    var body: some View {
        NavigationView {
            List {
                statusSection
                if !store.connectionState.isConnected {
                    scanSection
                } else {
                    deviceOverviewSection
                    quickActionsSection
                }
                rawLogSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sinjet HUD")
        }
        .navigationViewStyle(.stack)
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.connectionState.isConnected ? store.connectedDeviceName : store.connectionState.rawValue)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if store.connectionState.isConnected {
                    Button("断开", role: .destructive) {
                        store.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else if store.connectionState == .scanning {
                    Button("停止") {
                        store.stopScan()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("扫描") {
                        store.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.connectionState == .poweredOff || store.connectionState == .unauthorized)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var scanSection: some View {
        Section(header: Text("发现的 HUD 设备")) {
            if store.discoveredDevices.isEmpty {
                Text(store.connectionState == .scanning ? "正在搜索附近信界 HUD..." : "点击右上「扫描」搜索 HUD，连接后将自动停止扫描省电")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.discoveredDevices) { device in
                    Button {
                        store.connect(to: device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if device.isSystemConnected {
                                        Text("系统已连")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.18))
                                            .foregroundColor(.green)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(device.moduleTypeDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var deviceOverviewSection: some View {
        Section(header: Text("设备概览")) {
            infoRow("MCU 模块型号 (Magic)", value: store.deviceInfo.mcuMagic.isEmpty ? "读取中..." : store.deviceInfo.mcuMagic)
            infoRow("当前固件版本", value: store.deviceInfo.versionDisplay)
            infoRow("设备 UUID", value: store.deviceInfo.mcuUUID.isEmpty ? "--" : store.deviceInfo.mcuUUID, monospaced: true)
            if !store.deviceInfo.distributorCode.isEmpty {
                infoRow("经销商代码", value: store.deviceInfo.distributorCode)
            }
            infoRow(
                "BLE 链路",
                value: "Type \(store.deviceInfo.bleModuleType) · MTU \(store.deviceInfo.maxWriteLength)B · \(store.deviceInfo.writeWithResponse ? "WithResp" : "NoResp")"
            )
            infoRow("MCU 声明接收速率", value: "\(store.deviceInfo.mcuRxRate) B/s")
            if let pcb = store.deviceInfo.pcbVersion {
                let openAD = store.deviceInfo.nowOpenAD.map(String.init) ?? "--"
                let savedAD = store.deviceInfo.storageOpenAD.map(String.init) ?? "--"
                infoRow("硬件 PCB / 翻盖 AD", value: "PCB v\(pcb) · 当前 \(openAD) / 标定 \(savedAD)")
            }
            if !store.deviceInfo.lastErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCU 上报错误日志")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(store.deviceInfo.lastErrorMessage)
                        .font(.caption.monospaced())
                        .foregroundColor(.primary)
                }
            }
        }
    }

    private var quickActionsSection: some View {
        Section(header: Text("常用操作")) {
            Button {
                store.syncTimeNow()
            } label: {
                Label("一键同步手机时间到 HUD", systemImage: "clock.arrow.circlepath")
            }

            Button {
                store.refreshDeviceInfo()
            } label: {
                Label("重新读取型号 / 版本 / UUID", systemImage: "arrow.clockwise")
            }

            Toggle(isOn: $store.keepScreenAwake) {
                Label("保持屏幕常亮（防息屏）", systemImage: "sun.max")
            }
        }
    }

    private var rawLogSection: some View {
        Section(
            header: HStack {
                Text("原始通信日志 (\(store.logs.count))")
                Spacer()
                Button("清空") {
                    store.clearLogs()
                }
                .font(.caption)
            }
        ) {
            Toggle("记录常规帧日志", isOn: $store.enableRawProtocolLog)
                .font(.subheadline)

            if store.logs.isEmpty {
                Text("暂无通信日志")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.logs.reversed().prefix(80)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.direction.rawValue)
                                .font(.caption2.bold().monospaced())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(logBadgeColor(entry.direction).opacity(0.18))
                                .foregroundColor(logBadgeColor(entry.direction))
                                .cornerRadius(4)
                            Text(entry.timeString)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Text(entry.summary)
                            .font(.caption)
                            .foregroundColor(.primary)
                        if !entry.hexBytes.isEmpty {
                            Text(entry.hexBytes)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func infoRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private var statusColor: Color {
        switch store.connectionState {
        case .ready: return .green
        case .scanning, .connecting, .discovering: return .orange
        case .poweredOff, .unauthorized: return .red
        case .idle: return .gray
        }
    }

    private var statusSubtitle: String {
        switch store.connectionState {
        case .ready:
            return "低功耗链路运行中（已停扫 · 无 GPS / 无语音）"
        case .poweredOff:
            return "请在系统设置中打开蓝牙"
        case .unauthorized:
            return "请在系统设置中授予蓝牙权限"
        default:
            return "仅使用原生 CoreBluetooth，零后台常驻耗电"
        }
    }

    private func logBadgeColor(_ dir: LogDirection) -> Color {
        switch dir {
        case .tx: return .blue
        case .rx: return .green
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
