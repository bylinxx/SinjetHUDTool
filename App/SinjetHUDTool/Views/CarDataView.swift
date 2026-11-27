import SwiftUI

struct CarDataView: View {
    @EnvironmentObject private var store: HUDStore
    @State private var showClearFaultConfirm = false
    @State private var highPressureInput: Int = 30
    @State private var lowPressureInput: Int = 18
    @State private var highTempInput: Int = 65

    private let metricColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationView {
            List {
                liveMetricsSection
                bodyAndGearSection
                tpmsSection
                quickCheckSection
                faultCodeSection
                vehicleIdentitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("车辆数据")
            .onAppear {
                syncThresholdInputsFromStore()
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
                Text("将向 OBD 发送清除故障码指令 (03 06 00)。建议车辆通电熄火或怠速安全状态下操作。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 实时核心仪表

    private var liveMetricsSection: some View {
        Section(header: Text("实时仪表 (ID 0x03 / 0x10)")) {
            LazyVGrid(columns: metricColumns, spacing: 10) {
                metricCard(
                    title: "车速",
                    value: store.liveMetrics.speed.map { "\($0)" } ?? "--",
                    unit: "km/h",
                    alert: false
                )
                metricCard(
                    title: "转速",
                    value: store.liveMetrics.rpm.map { "\($0)" } ?? "--",
                    unit: store.liveMetrics.idleRpm.map { "RPM (怠速 \($0))" } ?? "RPM",
                    alert: false
                )
                metricCard(
                    title: "档位",
                    value: store.bodyGear.gearDisplay,
                    unit: "实时档位",
                    alert: false
                )
                metricCard(
                    title: "电瓶电压",
                    value: store.liveMetrics.voltage.map { String(format: "%.2f", $0) } ?? "--",
                    unit: "V",
                    alert: store.liveMetrics.voltageAlarmFlag != 0
                )
                metricCard(
                    title: "冷却液水温",
                    value: store.liveMetrics.coolantTemp.map { "\($0)" } ?? "--",
                    unit: "℃",
                    alert: store.liveMetrics.coolantAlarmFlag != 0
                )
                metricCard(
                    title: "剩余油量",
                    value: store.liveMetrics.fuelLevelPercent.map { "\($0)" } ?? "--",
                    unit: "%",
                    alert: false
                )
                metricCard(
                    title: "瞬时/平均油耗",
                    value: store.liveMetrics.fuelConsumption.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "L/100km",
                    alert: false
                )
                metricCard(
                    title: "本次里程",
                    value: store.liveMetrics.mileage.map { "\($0)" } ?? "--",
                    unit: "km",
                    alert: false
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func metricCard(title: String, value: String, unit: String, alert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if alert {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundColor(alert ? .red : .primary)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(alert ? Color.red.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: - 车身状态

    private var bodyAndGearSection: some View {
        Section(header: Text("车身与安全状态 (ID 0x03 / 0x06)")) {
            if !store.bodyGear.hasReceived {
                Text("等待 HUD 上报车身状态...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: metricColumns, spacing: 8) {
                    statusChip("左前门", active: store.bodyGear.frontLeftDoorOpen, activeText: "未关", normalText: "已关")
                    statusChip("右前门", active: store.bodyGear.frontRightDoorOpen, activeText: "未关", normalText: "已关")
                    statusChip("左后门", active: store.bodyGear.rearLeftDoorOpen, activeText: "未关", normalText: "已关")
                    statusChip("右后门", active: store.bodyGear.rearRightDoorOpen, activeText: "未关", normalText: "已关")
                    statusChip("后备箱", active: store.bodyGear.trunkOpen, activeText: "开启", normalText: "已关")
                    statusChip("手刹", active: store.bodyGear.handbrakeOn, activeText: "已拉起", normalText: "已松开")
                    statusChip("主驾安全带", active: store.bodyGear.driverSeatbeltUnbuckled, activeText: "未系", normalText: "已系")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func statusChip(_ label: String, active: Bool, activeText: String, normalText: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(active ? activeText : normalText)
                .font(.caption.bold())
                .foregroundColor(active ? .orange : .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((active ? Color.orange : Color.green).opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - TPMS 四轮胎压监测

    private var tpmsSection: some View {
        Section(header: Text("TPMS 胎压监测 (ID 0x04)")) {
            LazyVGrid(columns: metricColumns, spacing: 10) {
                ForEach(store.tpms.tires) { tire in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(tire.position.title)
                                .font(.caption.bold())
                            Spacer()
                            Circle()
                                .fill(tireColor(tire.alertLevel))
                                .frame(width: 8, height: 8)
                        }
                        Text(tire.pressureDisplay)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundColor(tireColor(tire.alertLevel))
                        HStack {
                            Text(tire.temperatureDisplay)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(tire.statusText)
                                .font(.caption2.bold())
                                .foregroundColor(tireColor(tire.alertLevel))
                        }
                        if store.connectionState.isConnected {
                            Button("配对") {
                                store.startTPMSPair(for: tire.position)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tireColor(tire.alertLevel).opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
            }
            .padding(.vertical, 4)

            if !store.tpms.pairingMessage.isEmpty {
                Text(store.tpms.pairingMessage)
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            if store.connectionState.isConnected {
                DisclosureGroup("报警阈值设置（实验性）") {
                    Text("原厂 App 未开放此设置界面，实车修改前请先核对下方 HUD 回读的原始字节（判断为十进制或 BCD/偏移编码）。")
                        .font(.caption2)
                        .foregroundColor(.orange)

                    if let h = store.tpms.highPressureAlarm {
                        Text(String(format: "当前回读高压原始值：%d (0x%02X)", h, h))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Stepper("高压阈值：\(highPressureInput) (0x\(String(format: "%02X", highPressureInput)))", value: $highPressureInput, in: 1...255)
                        .font(.caption)
                    Button("下发高压阈值 (04 01)") {
                        store.setTPMSHighPressureAlarm(UInt8(highPressureInput))
                    }
                    .font(.caption)

                    if let l = store.tpms.lowPressureAlarm {
                        Text(String(format: "当前回读低压原始值：%d (0x%02X)", l, l))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Stepper("低压阈值：\(lowPressureInput) (0x\(String(format: "%02X", lowPressureInput)))", value: $lowPressureInput, in: 1...255)
                        .font(.caption)
                    Button("下发低压阈值 (04 02)") {
                        store.setTPMSLowPressureAlarm(UInt8(lowPressureInput))
                    }
                    .font(.caption)

                    if let t = store.tpms.highTempAlarm {
                        Text(String(format: "当前回读高温原始值：%d (0x%02X)", t, t))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Stepper("高温阈值：\(highTempInput) (0x\(String(format: "%02X", highTempInput)))", value: $highTempInput, in: 1...255)
                        .font(.caption)
                    Button("下发高温阈值 (04 03)") {
                        store.setTPMSHighTempAlarm(UInt8(highTempInput))
                    }
                    .font(.caption)
                }
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

    // MARK: - 快捷车检

    private var quickCheckSection: some View {
        Section(header: Text("车况体检汇总 (ID 0x03 / 0x1A)")) {
            Button {
                store.startQuickCheck()
            } label: {
                HStack {
                    Label(store.quickCheck.isRunning ? "车检进行中..." : "开始快捷车检", systemImage: "stethoscope")
                    Spacer()
                    if store.quickCheck.isRunning {
                        ProgressView()
                    }
                }
            }
            .disabled(!store.connectionState.isConnected)

            if store.quickCheck.lastUpdated != nil {
                row("故障码计数", "\(store.quickCheck.faultCount)")
                if let v = store.quickCheck.voltage {
                    row("体检电压", String(format: "%.2f V", v))
                }
                if let th = store.quickCheck.throttlePercent {
                    row("节气门开度", String(format: "%.1f %%", th))
                }
                if let ct = store.quickCheck.coolantTemp {
                    row("体检水温", "\(ct) ℃")
                }
                if !store.quickCheck.catalystTemps.isEmpty {
                    let temps = store.quickCheck.catalystTemps.map { "\($0)℃" }.joined(separator: " / ")
                    row("三元催化器温度", temps)
                }
            }
        }
    }

    // MARK: - 故障码 (DTC)

    private var faultCodeSection: some View {
        Section(header: Text("故障码读取与清除 (ID 0x03 / 0x12 & 0x13)")) {
            HStack {
                Button("读取故障码") {
                    store.requestFaultCodesPage()
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)

                Spacer()

                Button("清除故障码", role: .destructive) {
                    showClearFaultConfirm = true
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
                Text("暂无故障码")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(store.faultCodes, id: \.self) { dtc in
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(dtc)
                            .font(.headline.monospaced())
                    }
                }
            }
        }
    }

    // MARK: - VIN 与 OBD 信息

    private var vehicleIdentitySection: some View {
        Section(header: Text("车辆识别与 OBD")) {
            row("车架号 (VIN)", store.vin.isEmpty ? "--" : store.vin, monospaced: true)
            row("OBD 协议号", store.obdProtocol.map { String(format: "0x%02X (%d)", $0, $0) } ?? "--")
            row("已上报支持 PID 数", "\(store.supportedPIDCount)")
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
        }
    }
}
