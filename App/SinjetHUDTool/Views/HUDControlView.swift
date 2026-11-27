import SwiftUI

struct HUDControlView: View {
    @EnvironmentObject private var store: HUDStore

    @State private var openCaliDraft: Double = 0
    @State private var closeCaliDraft: Double = 0
    @State private var newBTPwdInput: String = ""
    @State private var showClearFaultAlert = false

    var body: some View {
        NavigationView {
            List {
                axelaOSDSection
                axelaPanelSection
                convenienceSettingsSection
                btRemoteSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("HUD 控制")
            .onAppear {
                openCaliDraft = Double(store.axelaCalibration.openCurrent)
                closeCaliDraft = Double(store.axelaCalibration.closeCurrent)
            }
            .onChange(of: store.axelaCalibration.openCurrent) { val in
                openCaliDraft = Double(val)
            }
            .onChange(of: store.axelaCalibration.closeCurrent) { val in
                closeCaliDraft = Double(val)
            }
            .alert("确认清除故障码？", isPresented: $showClearFaultAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    store.clearFaultCodes()
                }
            } message: {
                Text("将发送清除故障码指令 (03 06 00)。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - HUD OSD 按键遥控

    private var axelaOSDSection: some View {
        Section(
            header: Text("HUD OSD 遥控 (ID 0x06 / 0x00)"),
            footer: Text("支持短按切换与长按进入/退出菜单（按下发送 1、抬起发送 0）。")
        ) {
            HStack(spacing: 12) {
                HoldableHUDButton(
                    title: "上",
                    systemImage: "chevron.up",
                    disabled: !store.connectionState.isConnected,
                    onPressChanged: { pressed in
                        store.setAxelaButtonPressed(.up, pressed: pressed)
                    },
                    onTapFallback: {
                        store.pulseAxelaButton(.up, label: "上-单击")
                    }
                )
                HoldableHUDButton(
                    title: "OK",
                    systemImage: "checkmark.circle",
                    disabled: !store.connectionState.isConnected,
                    onPressChanged: { pressed in
                        store.setAxelaButtonPressed(.ok, pressed: pressed)
                    },
                    onTapFallback: {
                        store.pulseAxelaButton(.ok, label: "OK-单击")
                    }
                )
                HoldableHUDButton(
                    title: "下",
                    systemImage: "chevron.down",
                    disabled: !store.connectionState.isConnected,
                    onPressChanged: { pressed in
                        store.setAxelaButtonPressed(.down, pressed: pressed)
                    },
                    onTapFallback: {
                        store.pulseAxelaButton(.down, label: "下-单击")
                    }
                )
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 面板开合测试、升降微调与标定读写

    private var axelaPanelSection: some View {
        Section(header: Text("HUD 翻盖面板测试与标定 (ID 0x06)")) {
            HStack(spacing: 12) {
                Button {
                    store.testAxelaPanelOpen()
                } label: {
                    Label("打开测试 (06 03)", systemImage: "arrow.up.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.connectionState.isConnected)

                Button {
                    store.testAxelaPanelClose()
                } label: {
                    Label("关闭测试 (06 05)", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)
            }

            HStack(spacing: 12) {
                Button {
                    store.pulseAxelaButton(.up, label: "面板上调")
                } label: {
                    Label("角度上调一步", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)

                Button {
                    store.pulseAxelaButton(.down, label: "面板下调")
                } label: {
                    Label("角度下调一步", systemImage: "minus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)
            }

            // 翻盖打开标定值（有符号 int8）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("翻盖打开标定值")
                        .font(.subheadline)
                    Spacer()
                    if store.axelaCalibration.hasOpenRange {
                        Text("\(Int(openCaliDraft))  [\(store.axelaCalibration.openMin) ~ \(store.axelaCalibration.openMax)]")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else {
                        Text("等待 HUD 上报标定范围")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Slider(
                    value: $openCaliDraft,
                    in: Double(store.axelaCalibration.openMin)...Double(max(store.axelaCalibration.openMin + 1, store.axelaCalibration.openMax)),
                    step: 1
                )
                .disabled(!store.connectionState.isConnected || !store.axelaCalibration.hasOpenRange)

                Button("写入打开标定值 (06 02)") {
                    store.sendAxelaOpenCalibration(Int(openCaliDraft))
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected || !store.axelaCalibration.hasOpenRange)
            }
            .padding(.vertical, 4)

            // 翻盖关闭标定值（有符号 int8）
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("翻盖关闭标定值")
                        .font(.subheadline)
                    Spacer()
                    if store.axelaCalibration.hasCloseRange {
                        Text("\(Int(closeCaliDraft))  [\(store.axelaCalibration.closeMin) ~ \(store.axelaCalibration.closeMax)]")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else {
                        Text("等待 HUD 上报标定范围")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Slider(
                    value: $closeCaliDraft,
                    in: Double(store.axelaCalibration.closeMin)...Double(max(store.axelaCalibration.closeMin + 1, store.axelaCalibration.closeMax)),
                    step: 1
                )
                .disabled(!store.connectionState.isConnected || !store.axelaCalibration.hasCloseRange)

                Button("写入关闭标定值 (06 04)") {
                    store.sendAxelaCloseCalibration(Int(closeCaliDraft))
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected || !store.axelaCalibration.hasCloseRange)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 车辆便捷设置与快捷诊断

    private var convenienceSettingsSection: some View {
        Section(header: Text("车辆便捷设置与诊断 (ID 0x03)")) {
            Toggle("左前车窗一键联动", isOn: Binding(
                get: { store.vehicleSettings.frontLeftWindow },
                set: { store.sendWindowSettings(frontLeft: $0, frontRight: store.vehicleSettings.frontRightWindow, rear: store.vehicleSettings.rearWindow) }
            ))
            .disabled(!store.connectionState.isConnected)

            Toggle("右前车窗一键联动", isOn: Binding(
                get: { store.vehicleSettings.frontRightWindow },
                set: { store.sendWindowSettings(frontLeft: store.vehicleSettings.frontLeftWindow, frontRight: $0, rear: store.vehicleSettings.rearWindow) }
            ))
            .disabled(!store.connectionState.isConnected)

            Toggle("后排车窗一键联动", isOn: Binding(
                get: { store.vehicleSettings.rearWindow },
                set: { store.sendWindowSettings(frontLeft: store.vehicleSettings.frontLeftWindow, frontRight: store.vehicleSettings.frontRightWindow, rear: $0) }
            ))
            .disabled(!store.connectionState.isConnected)

            Toggle("挂 P 挡自动解锁", isOn: Binding(
                get: { store.vehicleSettings.unlockOnP },
                set: { store.sendLockUnlockSettings(unlockOnP: $0, lockOnD: store.vehicleSettings.lockOnD) }
            ))
            .disabled(!store.connectionState.isConnected)

            Toggle("挂 D 挡自动落锁", isOn: Binding(
                get: { store.vehicleSettings.lockOnD },
                set: { store.sendLockUnlockSettings(unlockOnP: store.vehicleSettings.unlockOnP, lockOnD: $0) }
            ))
            .disabled(!store.connectionState.isConnected)

            HStack(spacing: 12) {
                Button("同步时间") {
                    store.syncTimeNow()
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)

                Button("快捷车检") {
                    store.startQuickCheck()
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)

                Button("清故障码", role: .destructive) {
                    showClearFaultAlert = true
                }
                .buttonStyle(.bordered)
                .disabled(!store.connectionState.isConnected)
            }
        }
    }

    // MARK: - 蓝牙控车 (可选，ID 0x05)

    private var btRemoteSection: some View {
        Section(header: Text("蓝牙控车 (ID 0x05 · 需车辆加装模块)")) {
            DisclosureGroup("展开蓝牙控车指令") {
                HStack {
                    TextField("8 位控车密码", text: $store.btRemotePassword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.subheadline.monospaced())
                    Button("校验") {
                        store.verifyBTRemotePassword()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!store.connectionState.isConnected)
                }

                if !store.btRemoteStatusMessage.isEmpty {
                    Text(store.btRemoteStatusMessage)
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(BTRemoteAction.allCases) { action in
                        Button(action.title) {
                            store.sendBTRemoteAction(action)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .disabled(!store.connectionState.isConnected)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    TextField("新 8 位密码", text: $newBTPwdInput)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.caption.monospaced())
                    Button("请求改密") {
                        store.requestBTRemoteSetPassword()
                    }
                    .font(.caption)
                    .disabled(!store.connectionState.isConnected)
                    Button("写入") {
                        store.setBTRemoteNewPassword(newBTPwdInput)
                    }
                    .font(.caption)
                    .disabled(!store.connectionState.isConnected || newBTPwdInput.utf8.count != 8)
                }
            }
        }
    }
}

/// 基于原生 ButtonStyle 跟踪按下/抬起状态，List 滚动取消手势或页面切换时保证安全回弹释放 (0x00)
private struct HoldableHUDButton: View {
    let title: String
    let systemImage: String
    let disabled: Bool
    let onPressChanged: (Bool) -> Void
    let onTapFallback: () -> Void

    @State private var isCurrentlyPressed = false
    @State private var lastPressEventAt: Date = .distantPast

    var body: some View {
        Button {
            if !disabled && Date().timeIntervalSince(lastPressEventAt) > 0.1 {
                onTapFallback()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(HoldPressTrackingStyle(disabled: disabled) { pressed in
            guard pressed != isCurrentlyPressed else { return }
            isCurrentlyPressed = pressed
            lastPressEventAt = Date()
            onPressChanged(pressed)
        })
        .disabled(disabled)
        .onChange(of: disabled) { nowDisabled in
            if nowDisabled, isCurrentlyPressed {
                isCurrentlyPressed = false
                lastPressEventAt = Date()
                onPressChanged(false)
            }
        }
        .onDisappear {
            if isCurrentlyPressed {
                isCurrentlyPressed = false
                lastPressEventAt = Date()
                onPressChanged(false)
            }
        }
    }
}

private struct HoldPressTrackingStyle: ButtonStyle {
    let disabled: Bool
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        let active = configuration.isPressed && !disabled
        configuration.label
            .background(active ? Color.accentColor : Color.accentColor.opacity(0.14))
            .foregroundColor(active ? .white : (disabled ? .secondary : .accentColor))
            .cornerRadius(10)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.5 : 1)
            .onChange(of: configuration.isPressed) { pressed in
                onPressChanged(pressed && !disabled)
            }
    }
}
