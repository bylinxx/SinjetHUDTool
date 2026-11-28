import SwiftUI
import UniformTypeIdentifiers

struct FirmwareUpgradeView: View {
    @EnvironmentObject private var store: HUDStore

    @State private var showFileImporter = false
    @State private var showStartFlashConfirm = false
    @State private var showRebootConfirm = false
    @State private var showRemoteURLInput = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: HUDDesign.sectionSpacing) {
                    hudTargetHeroCard
                    sourceSection
                    if let report = store.loadedPakReport {
                        precheckReportSection(report)
                    }
                    speedControlSection
                    transferProgressSection
                }
                .padding(.horizontal, HUDDesign.pageHorizontalPadding)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .hudDismissKeyboardOnScroll()
            .navigationTitle("固件刷机")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HUDToolbarConnectionPill(state: store.connectionState)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        isURLFieldFocused = false
                    }
                }
            }
            .onDisappear {
                isURLFieldFocused = false
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    store.loadLocalPak(from: url)
                }
            }
            .alert("确认开始传输固件？", isPresented: $showStartFlashConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认传输") {
                    store.startFirmwareTransfer()
                }
            } message: {
                let targetVer = store.loadedPakReport.map { String($0.fileVersion) } ?? "-"
                Text(
                    "目标 HUD：\(store.deviceInfo.mcuMagic)（当前版本 \(store.deviceInfo.versionDisplay)）\n" +
                    "固件版本：\(targetVer)\n\n" +
                    "请确保车辆挂 P 挡怠速着车供电、手机电量充足并保持 App 位于前台，切勿熄火或断电。"
                )
            }
            .alert("确认立即重启并刷写 HUD？", isPresented: $showRebootConfirm) {
                Button("取消", role: .cancel) {}
                Button("立即升级并重启", role: .destructive) {
                    store.confirmRebootAndFlash()
                }
            } message: {
                Text("将下发安全刷写重启指令。HUD 将立即断开蓝牙并重启刷写，请保持车辆供电直至重启完成。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 目标 HUD 状态头卡

    private var hudTargetHeroCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(store.connectionState.isConnected ? HUDDesign.connectedHeroGradient : HUDDesign.cockpitGradient)

            Circle()
                .fill((store.connectionState.isConnected ? Color.green : Color.orange).opacity(0.22))
                .frame(width: 140, height: 140)
                .blur(radius: 32)
                .offset(x: 35, y: -40)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "cpu")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("目标 HUD 设备")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.68))
                        if store.connectionState.isConnected {
                            Text("\(store.deviceInfo.mcuMagic.isEmpty ? "读取型号中..." : store.deviceInfo.mcuMagic) · v\(store.deviceInfo.versionDisplay)")
                                .font(.headline.weight(.bold).monospaced())
                                .foregroundColor(.white)
                        } else {
                            Text("未连接车机")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    targetChip(icon: "speedometer", text: "接收速率 \(store.deviceInfo.mcuRxRate) B/s")
                    targetChip(icon: "arrow.left.arrow.right", text: "MTU \(store.deviceInfo.maxWriteLength)B")
                    Spacer()
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 5)
    }

    private func targetChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundColor(.white.opacity(0.88))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - 步骤 1：选择固件来源

    private var sourceSection: some View {
        let trimmedURL = store.manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "1. 选择固件包 (.pak)", subtitle: "支持从本地文件导入或远程更新清单下载")

            HUDCard {
                // 主推荐操作：本地导入 .pak
                Button {
                    isURLFieldFocused = false
                    showFileImporter = true
                } label: {
                    HStack(spacing: 12) {
                        HUDIconBadge(systemImage: "folder.badge.plus", color: .accentColor, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("从「文件」App 导入本地 .pak 固件")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("自动完成 21 记录完整性、MD5 与型号安全预检")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.upgradePhase.isBusy)

                // 远程清单拉取（可展开）
                DisclosureGroup(isExpanded: $showRemoteURLInput) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("输入更新清单 JSON URL (https://...)", text: $store.manifestURLString)
                            .focused($isURLFieldFocused)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .onSubmit {
                                isURLFieldFocused = false
                            }
                            .font(.caption.monospaced())
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        HStack(spacing: 10) {
                            Button("清空") {
                                isURLFieldFocused = false
                                store.manifestURLString = ""
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .disabled(trimmedURL.isEmpty || store.upgradePhase.isBusy)

                            Spacer()

                            Button {
                                isURLFieldFocused = false
                                Task {
                                    await store.fetchRemoteManifestAndDownload()
                                }
                            } label: {
                                Label("拉取并预检", systemImage: "arrow.down.circle.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.upgradePhase.isBusy || trimmedURL.isEmpty)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 10) {
                        HUDIconBadge(systemImage: "link", color: .indigo, size: 30, iconFont: .caption.weight(.bold))
                        Text("通过远程更新清单 URL 拉取")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                }
                .tint(.secondary)

                if let manifest = store.remoteManifest {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("远端清单：v\(manifest.vcode)（\(manifest.date)）")
                            .font(.caption.weight(.bold))
                        if !manifest.changed.isEmpty {
                            Text(manifest.changed)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - 完整性预检报告卡

    private func precheckReportSection(_ report: PakValidationReport) -> some View {
        let blocker = store.upgradePrecheckBlocker()
        let passedAll = report.isStructurallyValid && blocker == nil

        return VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "固件完整性与安全预检") {
                HUDStatusPill(
                    text: passedAll ? "校验通过" : (report.isStructurallyValid ? "待确认条件" : "包异常"),
                    color: passedAll ? .green : (report.isStructurallyValid ? .orange : .red)
                )
            }

            HUDCard(
                borderColor: passedAll ? Color.green.opacity(0.45) : Color.orange.opacity(0.45),
                borderWidth: 1.2
            ) {
                HStack(spacing: 12) {
                    HUDIconBadge(
                        systemImage: report.isStructurallyValid ? "checkmark.seal.fill" : "xmark.octagon.fill",
                        color: report.isStructurallyValid ? .green : .red,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.fileName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                        Text(String(format: "%.2f KB (%d B) · %d 条子记录", Double(report.fileSize) / 1024.0, report.fileSize, report.recordCount))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                VStack(spacing: 8) {
                    HUDInfoRow(
                        title: "内嵌模块",
                        value: report.swModules.isEmpty ? "未检出" : report.swModules.joined(separator: ", "),
                        monospaced: true
                    )
                    HUDInfoRow(
                        title: "头部版本 / 日期",
                        value: "\(report.fileVersion) / \(report.swDates.joined(separator: ", "))",
                        monospaced: true
                    )
                    HUDInfoRow(
                        title: "校验明细",
                        value: "MD5错 \(report.md5ErrorCount) · 头错 \(report.headerErrorCount) · 块错 \(report.blockErrorCount)" +
                            (report.placeholderBlockCount > 0 ? " (含占位 \(report.placeholderBlockCount))" : "")
                    )
                    HUDInfoRow(
                        title: "整包 MD5",
                        value: report.wholeFileMD5,
                        monospaced: true
                    )
                }

                if let err = report.structuralError {
                    statusBanner(icon: "xmark.octagon.fill", text: "结构错误：\(err)", color: .red)
                }

                if let blocker {
                    statusBanner(icon: "exclamationmark.triangle.fill", text: blocker, color: .orange)
                } else {
                    statusBanner(icon: "checkmark.circle.fill", text: "型号匹配、版本号合规且 21 记录校验全通过，允许安全刷机", color: .green)
                }
            }
        }
    }

    private func statusBanner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 步骤 2：发包速率与自动保护

    private var speedControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "2. 传输策略与保护")

            HUDCard {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("刷机速率", selection: $store.speedMode) {
                        ForEach(TransferSpeedMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(store.speedMode.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                Toggle(isOn: $store.autoThrottleEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("重传自动平滑降速")
                            .font(.subheadline.weight(.medium))
                        Text("遇到丢包重传时自动切至更稳妥档位（推荐开启）")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if !store.upgradeTelemetry.autoThrottleNotice.isEmpty {
                    statusBanner(
                        icon: "exclamationmark.triangle.fill",
                        text: store.upgradeTelemetry.autoThrottleNotice,
                        color: .orange
                    )
                }
            }
        }
    }

    // MARK: - 步骤 3：传输进度与控制

    private var transferProgressSection: some View {
        let progress = store.upgradeTelemetry.progress

        return VStack(alignment: .leading, spacing: 10) {
            HUDSectionHeader(title: "3. 传输进度与刷写控制")

            HUDCard {
                // 状态 + 百分比大字
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.upgradePhase.title)
                            .font(.subheadline.weight(.semibold))
                        Text(String(format: "%d / %d B", store.upgradeTelemetry.bytesSentOffset, store.upgradeTelemetry.totalBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", progress * 100.0))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundColor(progressAccentColor)
                }

                // 渐变进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(progressAccentColor)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)))
                            .animation(.easeInOut(duration: 0.25), value: progress)
                    }
                }
                .frame(height: 9)

                if let eta = store.upgradeTelemetry.estimatedRemainingSeconds {
                    HStack {
                        Spacer()
                        Label("预计剩余 \(formatSeconds(eta))", systemImage: "timer")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                // 3 格遥测统计
                HStack(spacing: 10) {
                    telemetryTile(
                        label: "实测速率",
                        value: String(format: "%.2f KB/s", store.upgradeTelemetry.throughputBytesPerSec / 1024.0)
                    )
                    telemetryTile(
                        label: "重传计数",
                        value: "\(store.upgradeTelemetry.totalRetransmits)"
                    )
                    telemetryTile(
                        label: "分段校验",
                        value: "\(store.upgradeTelemetry.rangeMD5Requests)"
                    )
                }

                Divider()

                // 主控制按钮
                switch store.upgradePhase {
                case .readyToReboot(let readyVer):
                    Button {
                        showRebootConfirm = true
                    } label: {
                        Label("立即升级并重启 HUD (v\(readyVer))", systemImage: "bolt.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!store.connectionState.isConnected)

                case .handshaking, .transferring:
                    Button(role: .destructive) {
                        store.abortFirmwareTransfer()
                    } label: {
                        Label("中止传输", systemImage: "stop.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                default:
                    Button {
                        showStartFlashConfirm = true
                    } label: {
                        Label("开始安全传输固件", systemImage: "arrow.up.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.upgradePrecheckBlocker() != nil || store.upgradePhase.isBusy)
                }
            }
        }
    }

    private var progressAccentColor: Color {
        switch store.upgradePhase {
        case .readyToReboot, .rebootTriggered:
            return .green
        case .failed:
            return .red
        default:
            return .accentColor
        }
    }

    private func telemetryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatSeconds(_ totalSec: Int) -> String {
        let m = totalSec / 60
        let s = totalSec % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}
