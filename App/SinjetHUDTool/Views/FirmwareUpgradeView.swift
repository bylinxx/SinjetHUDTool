import SwiftUI
import UniformTypeIdentifiers

struct FirmwareUpgradeView: View {
    @EnvironmentObject private var store: HUDStore

    @State private var showFileImporter = false
    @State private var showStartFlashConfirm = false
    @State private var showRebootConfirm = false
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        NavigationView {
            List {
                hudTargetSection
                sourceSection
                if let report = store.loadedPakReport {
                    precheckReportSection(report)
                }
                speedControlSection
                transferProgressSection
            }
            .listStyle(.insetGrouped)
            .dismissKeyboardOnScrollCompat()
            .navigationTitle("固件刷机 (.pak)")
            .toolbar {
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
                Text("将下发 3A 30 01 00 指令。HUD 将立即断开蓝牙并重启刷写，请保持车辆供电直至重启完成。")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 已连接 HUD 信息

    private var hudTargetSection: some View {
        Section(header: Text("当前连接的 HUD 目标")) {
            HStack {
                Text("模块型号 / 版本")
                    .foregroundColor(.secondary)
                Spacer()
                if store.connectionState.isConnected {
                    Text("\(store.deviceInfo.mcuMagic.isEmpty ? "读取中" : store.deviceInfo.mcuMagic) · \(store.deviceInfo.versionDisplay)")
                        .font(.subheadline.bold().monospaced())
                } else {
                    Text("未连接")
                        .foregroundColor(.orange)
                }
            }
            HStack {
                Text("透传能力")
                    .foregroundColor(.secondary)
                Spacer()
                Text("mcuRxRate \(store.deviceInfo.mcuRxRate) B/s · MTU \(store.deviceInfo.maxWriteLength)B")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 固件获取源

    private var sourceSection: some View {
        let trimmedURL = store.manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return Section(header: Text("选择固件来源")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("远程更新清单 JSON URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("请输入更新清单 JSON URL (https://...)", text: $store.manifestURLString)
                    .focused($isURLFieldFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit {
                        isURLFieldFocused = false
                    }
                    .font(.caption.monospaced())
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("清空") {
                        isURLFieldFocused = false
                        store.manifestURLString = ""
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(trimmedURL.isEmpty || store.upgradePhase.isBusy)

                    Spacer()

                    Button("拉取并预检") {
                        isURLFieldFocused = false
                        Task {
                            await store.fetchRemoteManifestAndDownload()
                        }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .disabled(store.upgradePhase.isBusy || trimmedURL.isEmpty)
                }
            }
            .padding(.vertical, 4)

            if let manifest = store.remoteManifest {
                VStack(alignment: .leading, spacing: 3) {
                    Text("清单信息：v\(manifest.vcode)（\(manifest.date)）")
                        .font(.caption.bold())
                    if !manifest.changed.isEmpty {
                        Text(manifest.changed)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                isURLFieldFocused = false
                showFileImporter = true
            } label: {
                Label("从「文件」App 导入本地 .pak 固件", systemImage: "folder.badge.plus")
            }
            .disabled(store.upgradePhase.isBusy)
        }
    }

    // MARK: - 本地 21 记录完整性预检报告

    private func precheckReportSection(_ report: PakValidationReport) -> some View {
        let blocker = store.upgradePrecheckBlocker()
        return Section(header: Text(".pak 本地完整性与安全预检")) {
            HStack {
                Image(systemName: report.isStructurallyValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundColor(report.isStructurallyValid ? .green : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.fileName)
                        .font(.subheadline.bold())
                    Text(String(format: "%.2f KB (%d B)", Double(report.fileSize) / 1024.0, report.fileSize))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            reportRow("内嵌模块 (#SW_MODULE#)", report.swModules.isEmpty ? "未检出" : report.swModules.joined(separator: ", "))
            reportRow("头部版本 / #SW_DATE#", "\(report.fileVersion) / \(report.swDates.joined(separator: ", "))")
            reportRow("子记录数", "\(report.recordCount) 条")
            reportRow(
                "校验结果",
                "MD5错 \(report.md5ErrorCount) · 头错 \(report.headerErrorCount) · 块错 \(report.blockErrorCount)" +
                (report.placeholderBlockCount > 0 ? " (含原厂0xFE占位 \(report.placeholderBlockCount))" : "")
            )
            reportRow("整包 MD5", report.wholeFileMD5, monospaced: true)

            if let err = report.structuralError {
                Text("结构错误：\(err)")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let blocker {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(blocker)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("型号匹配、版本号合规且 21 记录校验全通过，允许刷机")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private func reportRow(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(size: 10, design: .monospaced) : .caption.bold())
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 三档速率与自动降速控制

    private var speedControlSection: some View {
        Section(
            header: Text("发包速率与自动保护"),
            footer: Text(store.speedMode.subtitle)
        ) {
            Picker("刷机速率", selection: $store.speedMode) {
                ForEach(TransferSpeedMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("重传自动平滑降速（推荐开启）", isOn: $store.autoThrottleEnabled)
                .font(.subheadline)

            if !store.upgradeTelemetry.autoThrottleNotice.isEmpty {
                Text(store.upgradeTelemetry.autoThrottleNotice)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - 传输状态、遥测与主操作按钮

    private var transferProgressSection: some View {
        Section(header: Text("传输进度与控制 (ID 0x3A Pull 模式)")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.upgradePhase.title)
                    .font(.subheadline.bold())

                ProgressView(value: store.upgradeTelemetry.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text(String(format: "%.1f%% (%d / %d B)",
                                store.upgradeTelemetry.progress * 100.0,
                                store.upgradeTelemetry.bytesSentOffset,
                                store.upgradeTelemetry.totalBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    if let eta = store.upgradeTelemetry.estimatedRemainingSeconds {
                        Text("剩余约 \(formatSeconds(eta))")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    telemetryBadge("实测速率", String(format: "%.2f KB/s", store.upgradeTelemetry.throughputBytesPerSec / 1024.0))
                    telemetryBadge("重传计数", "\(store.upgradeTelemetry.totalRetransmits)")
                    telemetryBadge("分段MD5", "\(store.upgradeTelemetry.rangeMD5Requests)")
                }
            }
            .padding(.vertical, 4)

            switch store.upgradePhase {
            case .readyToReboot(let readyVer):
                Button {
                    showRebootConfirm = true
                } label: {
                    Label("立即升级并重启 HUD (版本 \(readyVer))", systemImage: "bolt.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!store.connectionState.isConnected)

            case .handshaking, .transferring:
                Button(role: .destructive) {
                    store.abortFirmwareTransfer()
                } label: {
                    Label("中止传输", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

            default:
                Button {
                    showStartFlashConfirm = true
                } label: {
                    Label("开始安全传输固件", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.upgradePrecheckBlocker() != nil || store.upgradePhase.isBusy)
            }
        }
    }

    private func telemetryBadge(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold().monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    private func formatSeconds(_ totalSec: Int) -> String {
        let m = totalSec / 60
        let s = totalSec % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
}

private extension View {
    @ViewBuilder
    func dismissKeyboardOnScrollCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
