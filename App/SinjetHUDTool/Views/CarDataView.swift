import SwiftUI

struct CarDataView: View {
    @EnvironmentObject private var store: HUDStore
    @State private var showClearFaultConfirm = false
    @State private var highPressureInput: Int = 30
    @State private var lowPressureInput: Int = 18
    @State private var highTempInput: Int = 65
    @State private var showTPMSThresholdSettings = false

    private let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: HUDDesign.sectionSpacing) {
                    cockpitHeroCard
                    secondaryMetricsSection
                    autoStartStopSection
                    bodyStatusSection
                    tpmsSection
                    quickCheckSection
                    faultCodeSection
                    vehicleIdentitySection
                }
                .padding(.horizontal, HUDDesign.pageHorizontalPadding)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("车辆数据")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HUDToolbarConnectionPill(state: store.connectionState)
                }
            }
            .onAppear {
                syncThresholdInputsFromStore()
                if store.connectionState.isConnected && !store.upgradePhase.isBusy {
                    store.queryAutoStartStop()
                }
            }
            .onChange(of: store.tpms.highPressureAlarm) { _ in syncThresholdInputsFromStore() }
            .onChange(of: store.tpms.lowPressureAlarm) { _ in syncThresholdInputsFromStore() }
            .onChange(of: store.tpms.highTempAlarm) { _ in syncThresholdInputsFromStore() }
            .alert("确认清除故障码？", isPresented: $showClearFaultConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认清除", role: .destructive) {
                    store.clearFaultCodes()
                }
            } message: {
                Text("将向 OBD 发送清除故障码指令。建议车辆通电熄火或怠速安全状态下操作。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 顶部实时驾驶舱仪表卡（车速 / 转速 / 档位）

    private var cockpitHeroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(HUDDesign.cockpitGradient)

            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 160, height: 160)
                .blur(radius: 36)
                .offset(x: 40, y: -45)

            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    // 车速主读数
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时车速")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.65))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(store.liveMetrics.speed.map { "\($0)" } ?? "--")
                                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.7)
                            Text("km/h")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.cyan.opacity(0.9))
                        }
                    }

                    Spacer()

                    // 档位醒目徽章
                    VStack(spacing: 4) {
                        Text("档位")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.6))
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 64, height: 58)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.cyan.opacity(0.45), lineWidth: 1.2)
                                )
                            Text(store.bodyGear.gearDisplay)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }

                // 转速与里程底部条
                HStack(spacing: 12) {
                    cockpitMiniStat(
                        icon: "speedometer",
                        label: "发动机转速",
                        value: store.liveMetrics.rpm.map { "\($0) RPM" } ?? "-- RPM",
                        extra: store.liveMetrics.idleRpm.map { "怠速 \($0)" }
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: 28)

                    cockpitMiniStat(
                        icon: "map.fill",
                        label: "本次里程",
                        value: store.liveMetrics.mileage.map { "\($0) km" } ?? "-- km",
                        extra: nil
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private func cockpitMiniStat(icon: String, label: String, value: String, extra: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.cyan.opacity(0.85))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 5) {
                    Text(value)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundColor(.white)
                    if let extra {
                        Text(extra)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 实时工况指标四宫格

    private var secondaryMetricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "实时工况")

            LazyVGrid(columns: twoColumns, spacing: 12) {
                metricTile(
                    title: "电瓶电压",
                    value: store.liveMetrics.voltage.map { String(format: "%.2f", $0) } ?? "--",
                    unit: "V",
                    icon: "battery.100",
                    tint: .green,
                    alert: store.liveMetrics.voltageAlarmFlag != 0
                )

                metricTile(
                    title: "冷却液水温",
                    value: store.liveMetrics.coolantTemp.map { "\($0)" } ?? "--",
                    unit: "℃",
                    icon: "thermometer",
                    tint: .orange,
                    alert: store.liveMetrics.coolantAlarmFlag != 0
                )

                fuelMetricTile

                metricTile(
                    title: "瞬时 / 平均油耗",
                    value: store.liveMetrics.fuelConsumption.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "L/100km",
                    icon: "drop.fill",
                    tint: .indigo,
                    alert: false
                )
            }
        }
    }

    private func metricTile(
        title: String,
        value: String,
        unit: String,
        icon: String,
        tint: Color,
        alert: Bool
    ) -> some View {
        HUDCard(
            borderColor: alert ? Color.red.opacity(0.65) : nil,
            borderWidth: alert ? 1.5 : 1,
            padding: 14,
            spacing: 12
        ) {
            HStack {
                HUDIconBadge(systemImage: icon, color: alert ? .red : tint, size: 30, iconFont: .caption.weight(.bold))
                Spacer()
                if alert {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundColor(alert ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(unit)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Color.clear
                    .frame(height: 5)
                    .padding(.top, 2)
            }
        }
    }

    private var fuelMetricTile: some View {
        let percent = store.liveMetrics.fuelLevelPercent
        let isLowFuel = (percent ?? 100) <= 15
        let accent: Color = isLowFuel ? .orange : .blue

        return HUDCard(
            borderColor: isLowFuel ? Color.orange.opacity(0.55) : nil,
            padding: 14,
            spacing: 12
        ) {
            HStack {
                HUDIconBadge(systemImage: "fuelpump.fill", color: accent, size: 30, iconFont: .caption.weight(.bold))
                Spacer()
                if isLowFuel && percent != nil {
                    Text("偏低")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("剩余油量")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percent.map { "\($0)" } ?? "--")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundColor(isLowFuel && percent != nil ? .orange : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("%")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(accent)
                            .frame(width: geo.size.width * CGFloat(min(max(percent ?? 0, 0), 100)) / 100.0)
                    }
                }
                .frame(height: 5)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - 车辆功能设置（自动关闭发动机启停）

    private var autoStartStopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "车辆功能设置") {
                HStack(spacing: 8) {
                    if store.autoStartStop.capability == .probing || store.autoStartStop.isPending {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else if store.connectionState.isConnected {
                        Button("同步") {
                            store.queryAutoStartStop()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(store.upgradePhase.isBusy)
                    }
                    HUDStatusPill(text: autoStartStopBadgeText, color: autoStartStopStatusColor)
                }
            }

            HUDCard {
                HStack(spacing: 12) {
                    HUDIconBadge(
                        systemImage: "power",
                        color: store.autoStartStop.isEnabled ? .green : .blue,
                        size: 38,
                        iconFont: .headline.weight(.semibold)
                    )

                    Toggle(isOn: Binding(
                        get: { store.autoStartStop.isEnabled },
                        set: { store.setAutoStartStop(enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动关闭发动机启停")
                                .font(.subheadline.weight(.semibold))
                            Text(store.autoStartStop.statusMessage)
                                .font(.caption)
                                .foregroundColor(autoStartStopStatusColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(!store.connectionState.isConnected || !store.autoStartStop.isSynced || store.upgradePhase.isBusy)
                }
            }
        }
    }

    private var autoStartStopStatusColor: Color {
        guard store.connectionState.isConnected else { return .secondary }
        switch store.autoStartStop.capability {
        case .synced: return store.autoStartStop.isEnabled ? .green : .blue
        case .probing: return .blue
        case .unsupported: return .orange
        case .unknown: return .secondary
        }
    }

    private var autoStartStopBadgeText: String {
        guard store.connectionState.isConnected else { return "未连接" }
        switch store.autoStartStop.capability {
        case .synced: return store.autoStartStop.isEnabled ? "车机已开启" : "车机已关闭"
        case .probing: return "同步中"
        case .unsupported: return "固件不支持"
        case .unknown: return "待同步"
        }
    }

    // MARK: - 车身与安全状态

    private var bodyStatusSection: some View {
        let hasWarning = store.bodyGear.hasReceived && (
            store.bodyGear.frontLeftDoorOpen ||
            store.bodyGear.frontRightDoorOpen ||
            store.bodyGear.rearLeftDoorOpen ||
            store.bodyGear.rearRightDoorOpen ||
            store.bodyGear.trunkOpen ||
            store.bodyGear.driverSeatbeltUnbuckled
        )

        return VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "车身与安全状态") {
                if store.bodyGear.hasReceived {
                    HUDStatusPill(
                        text: hasWarning ? "有提醒项" : "状态正常",
                        color: hasWarning ? .orange : .green
                    )
                }
            }

            HUDCard {
                if !store.bodyGear.hasReceived {
                    HStack(spacing: 10) {
                        HUDIconBadge(systemImage: "car.fill", color: .secondary, size: 32)
                        Text("等待 HUD 上报车门、手刹与安全带状态...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    LazyVGrid(columns: twoColumns, spacing: 8) {
                        statusChip("左前门", active: store.bodyGear.frontLeftDoorOpen, activeText: "未关", normalText: "已关")
                        statusChip("右前门", active: store.bodyGear.frontRightDoorOpen, activeText: "未关", normalText: "已关")
                        statusChip("左后门", active: store.bodyGear.rearLeftDoorOpen, activeText: "未关", normalText: "已关")
                        statusChip("右后门", active: store.bodyGear.rearRightDoorOpen, activeText: "未关", normalText: "已关")
                        statusChip("后备箱", active: store.bodyGear.trunkOpen, activeText: "开启", normalText: "已关")
                        statusChip("手刹", active: store.bodyGear.handbrakeOn, activeText: "已拉起", normalText: "已松开")
                        statusChip("主驾安全带", active: store.bodyGear.driverSeatbeltUnbuckled, activeText: "未系", normalText: "已系")
                    }
                }
            }
        }
    }

    private func statusChip(_ label: String, active: Bool, activeText: String, normalText: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(active ? .orange : .green)
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(active ? activeText : normalText)
                .font(.caption.weight(.bold))
                .foregroundColor(active ? .orange : .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background((active ? Color.orange : Color.green).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - TPMS 四轮胎压监测

    private var tpmsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "TPMS 胎压监测")

            HUDCard {
                LazyVGrid(columns: twoColumns, spacing: 10) {
                    ForEach(store.tpms.tires) { tire in
                        tireCard(tire)
                    }
                }

                if !store.tpms.pairingMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text(store.tpms.pairingMessage)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if store.connectionState.isConnected {
                    Divider()

                    DisclosureGroup("报警阈值设置", isExpanded: $showTPMSThresholdSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            tpmsThresholdRow(
                                title: "高压阈值",
                                readback: store.tpms.highPressureAlarm,
                                value: $highPressureInput
                            ) {
                                store.setTPMSHighPressureAlarm(UInt8(highPressureInput))
                            }

                            Divider()

                            tpmsThresholdRow(
                                title: "低压阈值",
                                readback: store.tpms.lowPressureAlarm,
                                value: $lowPressureInput
                            ) {
                                store.setTPMSLowPressureAlarm(UInt8(lowPressureInput))
                            }

                            Divider()

                            tpmsThresholdRow(
                                title: "高温阈值",
                                readback: store.tpms.highTempAlarm,
                                value: $highTempInput
                            ) {
                                store.setTPMSHighTempAlarm(UInt8(highTempInput))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline.weight(.medium))
                    .tint(.secondary)
                }
            }
        }
    }

    private func tireCard(_ tire: TireData) -> some View {
        let color = tireColor(tire.alertLevel)
        let accentTint: Color = tire.alertLevel == .normal ? (tire.hasData ? .green : .secondary) : color

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tire.position.shortName)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
                Text(tire.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(accentTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(tire.pressureDisplay)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundColor(color)

            HStack {
                Label(tire.temperatureDisplay, systemImage: "thermometer")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                if store.connectionState.isConnected {
                    Button("配对") {
                        store.startTPMSPair(for: tire.position)
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tire.alertLevel == .normal ? Color.clear : color.opacity(0.45), lineWidth: 1.2)
        )
    }

    private func tpmsThresholdRow(
        title: String,
        readback: UInt8?,
        value: Binding<Int>,
        onApply: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                if let r = readback {
                    Text(String(format: "当前回读 %d (0x%02X)", r, r))
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Stepper("\(value.wrappedValue) (0x\(String(format: "%02X", value.wrappedValue)))", value: value, in: 1...255)
                    .font(.caption.monospacedDigit())
                Button("下发") {
                    onApply()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func tireColor(_ level: TireAlertLevel) -> Color {
        switch level {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func syncThresholdInputsFromStore() {
        if let h = store.tpms.highPressureAlarm { highPressureInput = Int(h) }
        if let l = store.tpms.lowPressureAlarm { lowPressureInput = Int(l) }
        if let t = store.tpms.highTempAlarm { highTempInput = Int(t) }
    }

    // MARK: - 车况快捷体检

    private var quickCheckSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "车况快捷体检")

            HUDCard {
                Button {
                    store.startQuickCheck()
                } label: {
                    HStack(spacing: 8) {
                        if store.quickCheck.isRunning {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "waveform.path.ecg")
                        }
                        Text(store.quickCheck.isRunning ? "车检进行中..." : "开始快捷车检")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(!store.connectionState.isConnected)

                if store.quickCheck.lastUpdated != nil {
                    Divider()

                    VStack(spacing: 8) {
                        HUDInfoRow(
                            title: "故障码计数",
                            value: "\(store.quickCheck.faultCount)",
                            valueColor: store.quickCheck.faultCount > 0 ? .red : .green
                        )
                        if let v = store.quickCheck.voltage {
                            HUDInfoRow(title: "体检电压", value: String(format: "%.2f V", v))
                        }
                        if let th = store.quickCheck.throttlePercent {
                            HUDInfoRow(title: "节气门开度", value: String(format: "%.1f %%", th))
                        }
                        if let ct = store.quickCheck.coolantTemp {
                            HUDInfoRow(title: "体检水温", value: "\(ct) ℃")
                        }
                        if !store.quickCheck.catalystTemps.isEmpty {
                            let temps = store.quickCheck.catalystTemps.map { "\($0)℃" }.joined(separator: " / ")
                            HUDInfoRow(title: "三元催化器温度", value: temps)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 故障码 (DTC)

    private var faultCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "故障码诊断 (DTC)") {
                if !store.faultCodes.isEmpty {
                    HUDStatusPill(text: "\(store.faultCodes.count) 条故障", color: .red)
                }
            }

            HUDCard {
                HStack(spacing: 10) {
                    Button {
                        store.requestFaultCodesPage()
                    } label: {
                        Label("读取故障码", systemImage: "wrench.and.screwdriver.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.connectionState.isConnected)

                    Button(role: .destructive) {
                        showClearFaultConfirm = true
                    } label: {
                        Label("清除故障码", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.connectionState.isConnected)
                }

                if !store.lastFaultActionMessage.isEmpty {
                    Text(store.lastFaultActionMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if store.faultCodes.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("暂无故障码")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.faultCodes, id: \.self) { dtc in
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(dtc)
                                    .font(.headline.monospaced())
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 车辆识别与 OBD 信息

    private var vehicleIdentitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "车辆识别与 OBD")

            HUDCard {
                VStack(spacing: 10) {
                    HUDInfoRow(
                        title: "车架号 (VIN)",
                        value: store.vin.isEmpty ? "--" : store.vin,
                        monospaced: true
                    )
                    Divider()
                    HUDInfoRow(
                        title: "OBD 协议号",
                        value: store.obdProtocol.map { String(format: "0x%02X (%d)", $0, $0) } ?? "--"
                    )
                    Divider()
                    HUDInfoRow(
                        title: "已上报支持 PID 数",
                        value: "\(store.supportedPIDCount)"
                    )
                }
            }
        }
    }
}
