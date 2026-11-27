import Foundation

enum LogDirection: String {
    case tx = "TX"
    case rx = "RX"
    case info = "SYS"
    case warn = "WARN"
    case error = "ERR"
}

struct ProtocolLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: LogDirection
    let summary: String
    let hexBytes: String

    var timeString: String {
        Self.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

extension Data {
    var hexSpacedString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
