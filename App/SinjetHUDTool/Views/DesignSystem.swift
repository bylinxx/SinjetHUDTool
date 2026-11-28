import SwiftUI
import UIKit

// MARK: - 统一车载美学设计组件

enum HUDDesign {
    static let cardCornerRadius: CGFloat = 16
    static let innerCornerRadius: CGFloat = 12
    static let pageHorizontalPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 18

    static let cockpitGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.10, blue: 0.18),
            Color(red: 0.09, green: 0.16, blue: 0.28)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let connectedHeroGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.14, blue: 0.26),
            Color(red: 0.07, green: 0.27, blue: 0.46)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.48, blue: 0.95),
            Color(red: 0.15, green: 0.64, blue: 0.98)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// 统一卡片容器（自适应浅/深色模式）
struct HUDCard<Content: View>: View {
    var borderColor: Color? = nil
    var borderWidth: CGFloat = 1
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: HUDDesign.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HUDDesign.cardCornerRadius, style: .continuous)
                .stroke(borderColor ?? Color.primary.opacity(0.06), lineWidth: borderWidth)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

/// 统一图标徽章
struct HUDIconBadge: View {
    let systemImage: String
    var color: Color = .accentColor
    var size: CGFloat = 34
    var iconFont: Font = .subheadline.weight(.semibold)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(iconFont)
                .foregroundColor(color)
        }
    }
}

/// 统一状态胶囊标签
struct HUDStatusPill: View {
    let text: String
    let color: Color
    var showDot: Bool = true
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            } else if showDot {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}

/// 统一分区标题头
struct HUDSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 2)
    }
}

extension HUDSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

/// 统一键值行
struct HUDInfoRow: View {
    let title: String
    let value: String
    var monospaced: Bool = false
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline.weight(.medium))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

/// 导航栏右侧紧凑连接状态胶囊
struct HUDToolbarConnectionPill: View {
    let state: BLEConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(state.isConnected ? "已连接" : state.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundColor(dotColor)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(dotColor.opacity(0.13))
        .clipShape(Capsule())
    }

    private var dotColor: Color {
        switch state {
        case .ready: return .green
        case .scanning, .connecting, .discovering: return .orange
        case .poweredOff, .unauthorized: return .red
        case .idle: return .secondary
        }
    }
}

/// 信号强度 4 格指示器
struct HUDSignalBars: View {
    let rssi: Int

    private var level: Int {
        if rssi >= -60 { return 4 }
        if rssi >= -72 { return 3 }
        if rssi >= -84 { return 2 }
        return 1
    }

    private var activeColor: Color {
        switch level {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(idx <= level ? activeColor : Color(.tertiarySystemFill))
                    .frame(width: 3, height: CGFloat(4 + idx * 3))
            }
        }
    }
}

/// 通用滚动隐藏键盘兼容修饰器
extension View {
    @ViewBuilder
    func hudDismissKeyboardOnScroll() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
