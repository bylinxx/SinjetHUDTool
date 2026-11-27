import Foundation

enum TransferSpeedMode: String, CaseIterable, Identifiable {
    case safe = "保守"
    case balanced = "平衡"
    case fast = "高速"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .safe: return "原厂 25ms / 20B 兼容档"
        case .balanced: return "背压流控 + 12-14ms 推荐档"
        case .fast: return "背压大包 + 7ms 极速档"
        }
    }

    var steppedDown: TransferSpeedMode? {
        switch self {
        case .fast: return .balanced
        case .balanced: return .safe
        case .safe: return nil
        }
    }
}

struct RemoteUpdateManifest: Codable, Equatable {
    let vcode: UInt32
    let vname: String
    let date: String
    let changed: String
    let md5: String
    let url: String
    let invalid_code: Int?
    let force: Int?
}

struct PakRecordSummary: Identifiable {
    let id: Int
    let name: String
    let offset: Int
    let size: Int
    let version: UInt32
    let expectedMD5: String
    let actualMD5: String
    let headerChecksumOK: Bool
    let blockCount: Int
    let blockErrorCount: Int
    let placeholderBlockCount: Int

    var isValid: Bool {
        expectedMD5 == actualMD5 && headerChecksumOK && blockErrorCount == 0
    }
}

struct PakValidationReport {
    let fileName: String
    let fileSize: Int
    let wholeFileMD5: String
    let fileVersion: UInt32
    let recordCount: Int
    let headerVersions: [UInt32]
    let swModules: [String]
    let swDates: [String]
    let records: [PakRecordSummary]
    let md5ErrorCount: Int
    let headerErrorCount: Int
    let blockErrorCount: Int
    let placeholderBlockCount: Int
    let structuralError: String?

    var primaryModule: String? { swModules.first }
    var primarySWDate: String? { swDates.first }

    var isStructurallyValid: Bool {
        structuralError == nil &&
        recordCount > 0 &&
        md5ErrorCount == 0 &&
        headerErrorCount == 0 &&
        blockErrorCount == 0 &&
        !swModules.isEmpty &&
        fileVersion > 0
    }
}

enum FirmwareUpgradePhase: Equatable {
    case idle
    case fetchingManifest
    case downloadingPak
    case validatedReady
    case handshaking
    case transferring
    case readyToReboot(readyVersion: UInt32)
    case rebootTriggered
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "待选择固件"
        case .fetchingManifest: return "正在拉取更新清单..."
        case .downloadingPak: return "正在下载 .pak 固件..."
        case .validatedReady: return "本地预检通过，可开始传输"
        case .handshaking: return "已发送元数据，等待 HUD 拉取..."
        case .transferring: return "正在高速传输固件..."
        case .readyToReboot(let ver): return "传输校验完成（就绪版本 \(ver)）"
        case .rebootTriggered: return "已下发重启刷写指令，请等待 HUD 重启"
        case .failed(let msg): return "失败：\(msg)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .fetchingManifest, .downloadingPak, .handshaking, .transferring:
            return true
        default:
            return false
        }
    }
}

struct UpgradeTelemetry {
    var bytesSentOffset: Int = 0
    var totalBytes: Int = 0
    var estimatedRemainingSeconds: Int?
    var throughputBytesPerSec: Double = 0
    var totalRetransmits: Int = 0
    var consecutiveSameOffsetRetransmits: Int = 0
    var rangeMD5Requests: Int = 0
    var dataRequests: Int = 0
    var autoThrottleNotice: String = ""
    var startedAt: Date?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(bytesSentOffset) / Double(totalBytes), 0), 1)
    }
}
