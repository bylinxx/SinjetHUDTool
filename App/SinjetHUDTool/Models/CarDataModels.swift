import Foundation

// MARK: - 连接与设备信息

enum BLEConnectionState: String {
    case poweredOff = "蓝牙未开启"
    case unauthorized = "未授权蓝牙"
    case idle = "未连接"
    case scanning = "正在扫描..."
    case connecting = "正在连接..."
    case discovering = "发现服务中..."
    case ready = "已连接"

    var isConnected: Bool {
        self == .ready
    }
}

struct DiscoveredHUD: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let moduleType: Int
    let isSystemConnected: Bool

    var moduleTypeDescription: String {
        switch moduleType {
        case 1: return "标准透传 (Type 1)"
        case 2: return "Sinjet 无厂商数据 (Type 2)"
        case 3: return "双特征/写确认 (Type 3)"
        case 4: return "Sinjet HM 模组 (Type 4)"
        default: return "未知 (Type \(moduleType))"
        }
    }
}

struct HUDDeviceInfo {
    var mcuMagic: String = ""
    var mcuVersion: UInt32 = 0
    var isBootloaderMode: Bool = false
    var mcuUUID: String = ""
    var distributorCode: String = ""
    var bleModuleType: Int = 1
    var hudHardwareModuleType: UInt8 = 0
    var mcuRxRate: UInt32 = 800
    var maxWriteLength: Int = 20
    var writeWithResponse: Bool = false
    var mcuInitOK: Bool = false
    var pcbVersion: UInt8?
    var storageOpenAD: UInt16?
    var nowOpenAD: UInt16?
    var lastErrorMessage: String = ""

    var versionDisplay: String {
        if isBootloaderMode { return "Bootloader (-1)" }
        if mcuVersion == 0 { return "--" }
        return String(mcuVersion)
    }

    var supportsAxelaOSD: Bool {
        hudHardwareModuleType == 3
    }
}

// MARK: - 车辆数据 (ID 0x03)

struct VehicleLiveMetrics {
    var voltage: Double?          // V
    var rpm: Int?                 // RPM
    var idleRpm: Int?             // 怠速 RPM (speed == 0 && rpm > 0)
    var speed: Int?               // km/h
    var coolantTemp: Int?         // ℃ (0xFF 无效)
    var mileage: Int?             // km
    var fuelConsumption: Double?  // L/100km (原厂 be16 / 100)
    var fuelLevelPercent: Int?    // %
    var voltageAlarmFlag: UInt8 = 0
    var coolantAlarmFlag: UInt8 = 0
    var lastUpdated: Date?
}

struct BodyAndGearState {
    var frontLeftDoorOpen: Bool = false
    var frontRightDoorOpen: Bool = false
    var rearLeftDoorOpen: Bool = false
    var rearRightDoorOpen: Bool = false
    var trunkOpen: Bool = false
    var handbrakeOn: Bool = false
    var driverSeatbeltUnbuckled: Bool = false
    var gearModeRaw: UInt8 = 0
    var gearNumberRaw: UInt8 = 0
    var hasReceived: Bool = false

    var gearDisplay: String {
        guard hasReceived else { return "--" }
        switch gearModeRaw {
        case 1: return "P"
        case 2: return "R"
        case 3: return "N"
        case 4: return gearNumberRaw > 0 ? "D\(gearNumberRaw)" : "D"
        case 5: return gearNumberRaw > 0 ? "S\(gearNumberRaw)" : "S"
        case 6: return gearNumberRaw > 0 ? "M\(gearNumberRaw)" : "M"
        case 9: return gearNumberRaw > 0 ? "L\(gearNumberRaw)" : "L"
        default: return "--"
        }
    }
}

struct QuickCheckSummary {
    var isRunning: Bool = false
    var isCompleted: Bool = false
    var faultCount: Int = 0
    var voltage: Double?
    var throttlePercent: Double?
    var coolantTemp: Int?
    var catalystTemps: [Int] = []  // 4路三元催化器温度 ℃
    var primaryCatalystTemp: Int?
    var lastUpdated: Date?
}

struct AxelaPanelCalibration {
    var openCurrent: Int = 0
    var openMin: Int = -50
    var openMax: Int = 50
    var hasOpenRange: Bool = false

    var closeCurrent: Int = 0
    var closeMin: Int = -50
    var closeMax: Int = 50
    var hasCloseRange: Bool = false
}

// MARK: - TPMS 胎压监测 (ID 0x04)

enum TirePosition: Int, CaseIterable, Identifiable {
    case frontLeft = 0
    case frontRight = 1
    case rearLeft = 2
    case rearRight = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .frontLeft: return "左前轮 (FL)"
        case .frontRight: return "右前轮 (FR)"
        case .rearLeft: return "左后轮 (RL)"
        case .rearRight: return "右后轮 (RR)"
        }
    }

    var shortName: String {
        switch self {
        case .frontLeft: return "左前"
        case .frontRight: return "右前"
        case .rearLeft: return "左后"
        case .rearRight: return "右后"
        }
    }

    var pairCommandParam: UInt8 {
        UInt8(rawValue << 4)
    }
}

enum TireAlertLevel {
    case normal
    case warning
    case critical
}

struct TireData: Identifiable {
    let position: TirePosition
    var pressureRawBCD: UInt8 = 0
    var temperatureRaw: UInt8 = 0xFF
    var statusMask: UInt8 = 0
    var hasData: Bool = false

    var id: Int { position.rawValue }

    var sensorFailed: Bool { (statusMask & 0x80) != 0 }
    var supportsPair: Bool { (statusMask & 0x40) != 0 }
    var lowPressure: Bool { (statusMask & 0x20) != 0 }
    var highPressure: Bool { (statusMask & 0x10) != 0 }
    var highTemperature: Bool { (statusMask & 0x08) != 0 }
    var lowBattery: Bool { (statusMask & 0x04) != 0 }
    var fastLeak: Bool { (statusMask & 0x02) != 0 }
    var slowLeak: Bool { (statusMask & 0x01) != 0 }

    var pressureDisplay: String {
        guard hasData, !sensorFailed else { return "-.- Bar" }
        let high = pressureRawBCD >> 4
        let low = pressureRawBCD & 0x0F
        return "\(high).\(low) Bar"
    }

    var temperatureDisplay: String {
        guard hasData, !sensorFailed, temperatureRaw != 0xFF else { return "-- ℃" }
        return "\(Int(temperatureRaw) - 40) ℃"
    }

    var alertLevel: TireAlertLevel {
        guard hasData else { return .normal }
        if sensorFailed || lowPressure || highPressure || highTemperature {
            return .critical
        }
        if lowBattery || fastLeak || slowLeak {
            return .warning
        }
        return .normal
    }

    var statusText: String {
        guard hasData else { return "等待数据" }
        if sensorFailed { return "传感器失效" }
        var tags: [String] = []
        if lowPressure { tags.append("欠压") }
        if highPressure { tags.append("过压") }
        if highTemperature { tags.append("高温") }
        if fastLeak { tags.append("快漏") }
        if slowLeak { tags.append("慢漏") }
        if lowBattery { tags.append("低电") }
        return tags.isEmpty ? "正常" : tags.joined(separator: " / ")
    }
}

struct TPMSState {
    var tires: [TireData] = TirePosition.allCases.map { TireData(position: $0) }
    var supportsPairing: Bool = false
    var pairingTire: TirePosition?
    var pairingMessage: String = ""
    var highPressureAlarm: UInt8?
    var lowPressureAlarm: UInt8?
    var highTempAlarm: UInt8?
}

// MARK: - 自动关闭发动机启停 (ID 0x08 / 0x01 / 0x07)

enum HUDFeatureSyncCapability: Equatable {
    case unknown
    case probing
    case synced
    case unsupported
}

struct HUDAutoStartStopState {
    var capability: HUDFeatureSyncCapability = .unknown
    var isEnabled: Bool = false
    var isPending: Bool = false
    var statusMessage: String = "连接车机后自动读取当前启停开关状态"

    var isSynced: Bool {
        capability == .synced
    }
}

enum HUDAppPage: UInt8, CaseIterable {
    case realtimeOBD = 0x01
    case faultCodes = 0x02
    case quickCheck = 0x03
    case homeGeneral = 0x04
}

