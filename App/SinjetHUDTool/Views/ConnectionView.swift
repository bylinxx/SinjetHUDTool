import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var store: HUDStore
    @State private var isLogExpanded: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: HUDDesign.sectionSpacing) {
                    heroConnectionCard

                    if !store.connectionState.isConnected {
                        discoveredDevicesCard
                    } else {
                        quickActionsCard
                        deviceOverviewCard
                    }

                    protocolLogCard
                }
                .padding(.horizontal, HUDDesign.pageHorizontalPadding)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sinjet HUD")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 顶部连接主视觉卡

    private var heroConnectionCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(store.connectionState.isConnected ? HUDDesign.connectedHeroGradient : HUDDesign.cockpitGradient)

            // 装饰光晕
            Circle()
                .fill(statusColor.opacity(store.connectionState.isConnected ? 0.28 : 0.16))
                .frame(width: 170, height: 170)
                .blur(radius: 36)
                .offset(x: 45, y: -55)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    // 状态光环图标
                    ZStack {
                        Circle()
                            .stroke(statusColor.opacity(0.30), lineWidth: 1.5)
                            .frame(width: 54, height: 54)
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 44, height: 44)
                        if store.connectionState == .scanning || store.connectionState == .connecting || store.connectionState == .discovering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: store.connectionState.isConnected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(store.connectionState.isConnected ? .green : .white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.connectionState.isConnected ? store.connectedDeviceName : store.connectionState.rawValue)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let subtitle = statusSubtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 4)
                }

                // 已连接时显示核心摘要胶囊
                if store.connectionState.isConnected {
                    HStack(spacing: 8) {
                        heroMetaChip(
                            icon: "cpu",
                            text: store.deviceInfo.mcuMagic.isEmpty ? "读取型号中" : store.deviceInfo.mcuMagic
                        )
                        heroMetaChip(
                            icon: "tag.fill",
                            text: "v\(store.deviceInfo.versionDisplay)"
                        )
                        heroMetaChip(
                            icon: "bolt.fill",
                            text: "MTU \(store.deviceInfo.maxWriteLength)B"
                        )
                        Spacer()
                    }
                }

                // 主操作按钮
                HStack(spacing: 10) {
                    if store.connectionState.isConnected {
                        Button {
                            store.disconnect()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                Text("断开连接")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.14))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if store.connectionState == .scanning {
                        Button {
                            store.stopScan()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                Text("停止扫描")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.orange.opacity(0.88))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        let scanDisabled = store.connectionState == .poweredOff || store.connectionState == .unauthorized
                        Button {
                            store.startScan()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("搜索附近 HUD")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(scanDisabled ? AnyShapeStyle(Color.white.opacity(0.16)) : AnyShapeStyle(HUDDesign.accentGradient))
                            .foregroundColor(scanDisabled ? .white.opacity(0.45) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(scanDisabled)
                    }
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private func heroMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.14))
        .clipShape(Capsule())
    }

    // MARK: - 发现的设备列表

    private var discoveredDevicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "附近的 HUD 设备") {
                if store.connectionState == .scanning {
                    HUDStatusPill(text: "扫描中", color: .orange)
                } else if !store.discoveredDevices.isEmpty {
                    Text("\(store.discoveredDevices.count) 台")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }

            HUDCard(padding: store.discoveredDevices.isEmpty ? 20 : 12) {
                if store.discoveredDevices.isEmpty {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.10))
                                .frame(width: 52, height: 52)
                            Image(systemName: store.connectionState == .scanning ? "dot.radiowaves.left.and.right" : "car.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        Text(store.connectionState == .scanning ? "正在搜索附近 HUD..." : "尚未发现 HUD 设备")
                            .font(.subheadline.weight(.semibold))
                        if store.connectionState == .scanning {
                            Text("请确保车辆已通电且 HUD 已开启")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.discoveredDevices.enumerated()), id: \.element.id) { index, device in
                            Button {
                                store.connect(to: device)
                            } label: {
                                HStack(spacing: 12) {
                                    HUDIconBadge(
                                        systemImage: "dot.radiowaves.left.and.right",
                                        color: device.isSystemConnected ? .green : .accentColor,
                                        size: 38
                                    )

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(device.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            if device.isSystemConnected {
                                                Text("系统已连")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.16))
                                                    .foregroundColor(.green)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(device.moduleTypeDescription)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        HUDSignalBars(rssi: device.rssi)
                                        Text("\(device.rssi) dBm")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(Color(.tertiaryLabel))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < store.discoveredDevices.count - 1 {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 常用快捷操作

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "快捷操作")

            HStack(spacing: 12) {
                quickActionTile(
                    title: "同步手机时间",
                    icon: "clock.arrow.2.circlepath",
                    color: .blue
                ) {
                    store.syncTimeNow()
                }

                quickActionTile(
                    title: "刷新设备信息",
                    icon: "arrow.clockwise",
                    color: .indigo
                ) {
                    store.refreshDeviceInfo()
                }
            }

            HUDCard(padding: 14) {
                Toggle(isOn: $store.keepScreenAwake) {
                    HStack(spacing: 12) {
                        HUDIconBadge(systemImage: "sun.max.fill", color: .orange, size: 34)
                        Text("保持屏幕常亮")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func quickActionTile(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HUDIconBadge(systemImage: icon, color: color, size: 36)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: HUDDesign.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HUDDesign.cardCornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 设备硬件详情

    private var deviceOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "设备概览")

            HUDCard {
                // 顶部双重点指标
                HStack(spacing: 10) {
                    highlightInfoBox(
                        label: "MCU 型号",
                        value: store.deviceInfo.mcuMagic.isEmpty ? "读取中..." : store.deviceInfo.mcuMagic,
                        icon: "cpu",
                        color: .blue
                    )
                    highlightInfoBox(
                        label: "固件版本",
                        value: store.deviceInfo.versionDisplay,
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                }

                Divider()

                VStack(spacing: 10) {
                    HUDInfoRow(
                        title: "设备 UUID",
                        value: store.deviceInfo.mcuUUID.isEmpty ? "--" : store.deviceInfo.mcuUUID,
                        monospaced: true
                    )

                    if !store.deviceInfo.distributorCode.isEmpty {
                        HUDInfoRow(title: "经销商代码", value: store.deviceInfo.distributorCode)
                    }

                    HUDInfoRow(
                        title: "BLE 链路",
                        value: "Type \(store.deviceInfo.bleModuleType) · MTU \(store.deviceInfo.maxWriteLength)B · \(store.deviceInfo.writeWithResponse ? "WithResp" : "NoResp")"
                    )

                    HUDInfoRow(
                        title: "MCU 接收速率",
                        value: "\(store.deviceInfo.mcuRxRate) B/s"
                    )

                    if let pcb = store.deviceInfo.pcbVersion {
                        let openAD = store.deviceInfo.nowOpenAD.map(String.init) ?? "--"
                        let savedAD = store.deviceInfo.storageOpenAD.map(String.init) ?? "--"
                        HUDInfoRow(
                            title: "硬件 PCB / 翻盖 AD",
                            value: "PCB v\(pcb) · 当前 \(openAD) / 标定 \(savedAD)"
                        )
                    }
                }

                if !store.deviceInfo.lastErrorMessage.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MCU 上报错误日志")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                            Text(store.deviceInfo.lastErrorMessage)
                                .font(.caption2.monospaced())
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func highlightInfoBox(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 原始通信日志（可折叠）

    private var protocolLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "开发者诊断日志") {
                if !store.logs.isEmpty {
                    Button("清空") {
                        store.clearLogs()
                    }
                    .font(.caption.weight(.medium))
                }
            }

            HUDCard(padding: 14) {
                DisclosureGroup(isExpanded: $isLogExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().padding(.top, 4)

                        Toggle("记录常规帧日志", isOn: $store.enableRawProtocolLog)
                            .font(.subheadline)
                            .tint(.green)

                        if store.logs.isEmpty {
                            Text("暂无通信日志")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(store.logs.reversed().prefix(80)) { entry in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(entry.direction.rawValue)
                                                .font(.caption2.bold().monospaced())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(logBadgeColor(entry.direction).opacity(0.16))
                                                .foregroundColor(logBadgeColor(entry.direction))
                                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        HUDIconBadge(systemImage: "terminal.fill", color: .secondary, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原始通信帧记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("\(store.logs.count) 条记录")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .tint(.secondary)
            }
        }
    }

    // MARK: - 辅助计算

    private var statusColor: Color {
        switch store.connectionState {
        case .ready: return .green
        case .scanning, .connecting, .discovering: return .orange
        case .poweredOff, .unauthorized: return .red
        case .idle: return .blue
        }
    }

    private var statusSubtitle: String? {
        switch store.connectionState {
        case .poweredOff:
            return "请在系统设置中打开蓝牙"
        case .unauthorized:
            return "请在系统设置中授予蓝牙权限"
        default:
            return nil
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
