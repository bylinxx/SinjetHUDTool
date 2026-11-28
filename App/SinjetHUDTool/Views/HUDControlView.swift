import SwiftUI
import UIKit

struct HUDControlView: View {
    @EnvironmentObject private var store: HUDStore

    @State private var openCaliDraft: Double = 0
    @State private var closeCaliDraft: Double = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: HUDDesign.sectionSpacing) {
                    axelaOSDSection
                    hudThemeSection
                    axelaPanelSection
                    hudTimeSection
                }
                .padding(.horizontal, HUDDesign.pageHorizontalPadding)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HUD 操控")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HUDToolbarConnectionPill(state: store.connectionState)
                }
            }
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
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - HUD OSD 按键遥控

    private var axelaOSDSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "OSD 菜单遥控", subtitle: "支持短按切换与长按进入 / 退出菜单")

            HUDCard {
                HStack(spacing: 12) {
                    HoldableHUDButton(
                        title: "上",
                        systemImage: "chevron.up",
                        prominent: false,
                        disabled: !store.connectionState.isConnected,
                        onPressChanged: { pressed in
                            store.setAxelaButtonPressed(.up, pressed: pressed)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)

                    HoldableHUDButton(
                        title: "确认 OK",
                        systemImage: "checkmark.circle.fill",
                        prominent: true,
                        disabled: !store.connectionState.isConnected,
                        onPressChanged: { pressed in
                            store.setAxelaButtonPressed(.ok, pressed: pressed)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)

                    HoldableHUDButton(
                        title: "下",
                        systemImage: "chevron.down",
                        prominent: false,
                        disabled: !store.connectionState.isConnected,
                        onPressChanged: { pressed in
                            store.setAxelaButtonPressed(.down, pressed: pressed)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 68)
                }

                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("按下实时下发按键状态、抬起自动释放，避免菜单重复触发。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - HUD 主题切换（上一套 / 下一套）

    private var hudThemeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "HUD 主题切换", subtitle: "通过通用指令顺序切换上下套显示主题")

            HUDCard(spacing: 10) {
                HStack(spacing: 12) {
                    panelActionCard(
                        title: "上一套主题",
                        subtitle: "向前切换样式",
                        systemImage: "chevron.left.circle.fill",
                        tint: .secondary,
                        prominent: false
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.stepTheme(next: false)
                    }

                    panelActionCard(
                        title: "下一套主题",
                        subtitle: "向后切换样式",
                        systemImage: "chevron.right.circle.fill",
                        tint: .accentColor,
                        prominent: true
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.stepTheme(next: true)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("使用原厂标准切主题指令（08 01 05），兼容原厂与自制固件。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 面板开合测试、升降微调与标定读写

    private var axelaPanelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "翻盖成像板控制与标定", subtitle: "电动翻屏测试、实时仰角微调与限位记忆")

            HUDCard(spacing: 14) {
                // 1. 电动开合测试双大卡
                HStack(spacing: 12) {
                    panelActionCard(
                        title: "升起测试",
                        subtitle: "展开透明成像板",
                        systemImage: "arrow.up.to.line",
                        tint: .accentColor,
                        prominent: true
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.testAxelaPanelOpen()
                    }

                    panelActionCard(
                        title: "收回测试",
                        subtitle: "闭合归位收纳",
                        systemImage: "arrow.down.to.line",
                        tint: .secondary,
                        prominent: false
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.testAxelaPanelClose()
                    }
                }

                // 2. 仰角微调条
                HStack(spacing: 12) {
                    HUDIconBadge(systemImage: "slider.horizontal.3", color: .cyan, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时仰角微调")
                            .font(.subheadline.weight(.semibold))
                        Text("按当前坐姿微调投影高低")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.pulseAxelaButton(.down, label: "面板下调")
                        } label: {
                            Image(systemName: "minus")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.connectionState.isConnected)
                        .accessibilityLabel("角度下调一步")

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.pulseAxelaButton(.up, label: "面板上调")
                        } label: {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.connectionState.isConnected)
                        .accessibilityLabel("角度上调一步")
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // 3. 翻盖升起限位标定
                calibrationControlCard(
                    title: "升起限位标定",
                    subtitle: "调整着车自动展开后的默认仰角",
                    systemImage: "angle",
                    accent: .blue,
                    draft: $openCaliDraft,
                    current: store.axelaCalibration.openCurrent,
                    minVal: store.axelaCalibration.openMin,
                    maxVal: store.axelaCalibration.openMax,
                    hasRange: store.axelaCalibration.hasOpenRange,
                    onApply: { store.sendAxelaOpenCalibration(Int(openCaliDraft)) }
                )

                // 4. 翻盖收回限位标定
                calibrationControlCard(
                    title: "收回限位标定",
                    subtitle: "调整熄火自动闭合后的终点位置",
                    systemImage: "rectangle.compress.vertical",
                    accent: .indigo,
                    draft: $closeCaliDraft,
                    current: store.axelaCalibration.closeCurrent,
                    minVal: store.axelaCalibration.closeMin,
                    maxVal: store.axelaCalibration.closeMax,
                    hasRange: store.axelaCalibration.hasCloseRange,
                    onApply: { store.sendAxelaCloseCalibration(Int(closeCaliDraft)) }
                )

                Text("日常使用若开合顺畅、视野居中，无需修改限位标定。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func panelActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isDisabled = !store.connectionState.isConnected
        return Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isDisabled ? .secondary : (prominent ? .white : .primary))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isDisabled ? .secondary : (prominent ? .white : .primary))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isDisabled ? .secondary.opacity(0.7) : (prominent ? .white.opacity(0.85) : .secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isDisabled
                            ? AnyShapeStyle(Color(.tertiarySystemFill))
                            : (prominent ? AnyShapeStyle(HUDDesign.accentGradient) : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(prominent || isDisabled ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func calibrationControlCard(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        draft: Binding<Double>,
        current: Int,
        minVal: Int,
        maxVal: Int,
        hasRange: Bool,
        onApply: @escaping () -> Void
    ) -> some View {
        let isEditable = store.connectionState.isConnected && hasRange
        let draftInt = Int(draft.wrappedValue)
        let isModified = hasRange && draftInt != current
        let upper = max(minVal + 1, maxVal)

        return VStack(alignment: .leading, spacing: 10) {
            // 标题 + 当前值徽章
            HStack(alignment: .center, spacing: 10) {
                HUDIconBadge(
                    systemImage: systemImage,
                    color: isEditable ? accent : .secondary,
                    size: 32,
                    iconFont: .subheadline.weight(.semibold)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasRange {
                    Text(draftInt > 0 ? "+\(draftInt)" : "\(draftInt)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundColor(isModified ? accent : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isModified ? accent.opacity(0.14) : Color(.secondarySystemFill))
                        )
                } else {
                    Text(store.connectionState.isConnected ? "待车机上报" : "未连接")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                }
            }

            // 滑块 + 起止刻度 + 精细加减
            HStack(spacing: 8) {
                Button {
                    draft.wrappedValue = Double(max(minVal, draftInt - 1))
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(isEditable && draftInt > minVal ? accent : Color(.quaternaryLabel))
                }
                .buttonStyle(.plain)
                .disabled(!isEditable || draftInt <= minVal)

                VStack(spacing: 2) {
                    Slider(
                        value: draft,
                        in: Double(minVal)...Double(upper),
                        step: 1
                    )
                    .tint(accent)
                    .disabled(!isEditable)

                    HStack {
                        Text("\(minVal)")
                        Spacer()
                        Text("车机当前 \(current > 0 ? "+\(current)" : "\(current)")")
                        Spacer()
                        Text("+\(maxVal)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                }

                Button {
                    draft.wrappedValue = Double(min(maxVal, draftInt + 1))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(isEditable && draftInt < maxVal ? accent : Color(.quaternaryLabel))
                }
                .buttonStyle(.plain)
                .disabled(!isEditable || draftInt >= maxVal)
            }

            // 操作栏
            HStack(spacing: 10) {
                if isModified {
                    Button("还原") {
                        draft.wrappedValue = Double(current)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onApply()
                } label: {
                    Label(isModified ? "写入新标定" : "写入标定", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(isModified ? accent : .secondary)
                .controlSize(.small)
                .disabled(!isEditable)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isModified ? accent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - HUD 时钟同步

    private var hudTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "HUD 时钟校准")

            HUDCard(padding: 14) {
                HStack(spacing: 12) {
                    HUDIconBadge(systemImage: "clock.arrow.2.circlepath", color: .blue, size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("同步手机时间")
                            .font(.subheadline.weight(.semibold))
                        Text("将当前系统日期与时间精准写入 HUD")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("立即同步") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.syncTimeNow()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!store.connectionState.isConnected)
                }
            }
        }
    }
}

/// 基于原生 UIControl 直接跟踪 touchDown / touchUpInside / touchUpOutside / touchCancel，
/// 严格对齐原厂 AxelaSettingGestureViewController（按下发 1、抬起发 0，绝不补发 2 导致双重点击）
private struct HoldableHUDButton: UIViewRepresentable {
    let title: String
    let systemImage: String
    let prominent: Bool
    let disabled: Bool
    let onPressChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPressChanged: onPressChanged)
    }

    func makeUIView(context: Context) -> HUDKeyControl {
        let control = HUDKeyControl(title: title, systemImage: systemImage, prominent: prominent)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .vertical)
        control.onPressStateChanged = { [weak coordinator = context.coordinator] pressed in
            coordinator?.handlePressChange(pressed)
        }
        control.isEnabled = !disabled
        return control
    }

    func updateUIView(_ uiView: HUDKeyControl, context: Context) {
        context.coordinator.onPressChanged = onPressChanged
        uiView.update(title: title, systemImage: systemImage, prominent: prominent, disabled: disabled)
    }

    static func dismantleUIView(_ uiView: HUDKeyControl, coordinator: Coordinator) {
        uiView.releaseIfNeeded()
    }

    final class Coordinator {
        var onPressChanged: (Bool) -> Void

        init(onPressChanged: @escaping (Bool) -> Void) {
            self.onPressChanged = onPressChanged
        }

        func handlePressChange(_ pressed: Bool) {
            onPressChanged(pressed)
        }
    }
}

private final class HUDKeyControl: UIControl {
    var onPressStateChanged: ((Bool) -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var isKeyPressed = false
    private var isProminent = false
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 68)
    }

    init(title: String, systemImage: String, prominent: Bool) {
        self.isProminent = prominent
        super.init(frame: .zero)
        isExclusiveTouch = true
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = 1

        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .caption1).withBoldWeight()
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])

        addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
        addTarget(self, action: #selector(handleTouchEnd), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        update(title: title, systemImage: systemImage, prominent: prominent, disabled: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, systemImage: String, prominent: Bool, disabled: Bool) {
        self.isProminent = prominent
        titleLabel.text = title
        iconView.image = UIImage(systemName: systemImage)
        isEnabled = !disabled
        if disabled {
            releaseIfNeeded()
        }
        refreshAppearance()
    }

    func releaseIfNeeded() {
        guard isKeyPressed else { return }
        isKeyPressed = false
        animateScale(pressed: false)
        refreshAppearance()
        onPressStateChanged?(false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            releaseIfNeeded()
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        refreshAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshAppearance()
    }

    @objc private func handleTouchDown() {
        guard isEnabled, !isKeyPressed else { return }
        isKeyPressed = true
        feedback.impactOccurred()
        animateScale(pressed: true)
        refreshAppearance()
        onPressStateChanged?(true)
    }

    @objc private func handleTouchEnd() {
        releaseIfNeeded()
    }

    private func animateScale(pressed: Bool) {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.transform = pressed ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
        }
    }

    private func refreshAppearance() {
        let accent = tintColor ?? .systemBlue
        if !isEnabled {
            backgroundColor = UIColor.tertiarySystemFill
            layer.borderColor = UIColor.clear.cgColor
            iconView.tintColor = .secondaryLabel
            titleLabel.textColor = .secondaryLabel
            alpha = 0.55
        } else if isKeyPressed {
            backgroundColor = accent
            layer.borderColor = accent.cgColor
            iconView.tintColor = .white
            titleLabel.textColor = .white
            alpha = 1.0
        } else if isProminent {
            backgroundColor = accent.withAlphaComponent(0.16)
            layer.borderColor = accent.withAlphaComponent(0.35).cgColor
            iconView.tintColor = accent
            titleLabel.textColor = accent
            alpha = 1.0
        } else {
            backgroundColor = UIColor.tertiarySystemGroupedBackground
            layer.borderColor = UIColor.label.withAlphaComponent(0.08).cgColor
            iconView.tintColor = .label
            titleLabel.textColor = .label
            alpha = 1.0
        }
    }
}

private extension UIFont {
    func withBoldWeight() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
