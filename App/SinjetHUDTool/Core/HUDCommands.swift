import Foundation

/// 全部实证 HUD 控制与升级指令集（返回未封装 `FF 55` 的原始 PAYLOAD）
enum HUDCommands {
    // MARK: - ID 0x01 时间同步

    /// `sendTimeToHUD` (9B): [0x01, 0x07, H, M, S, year_lo, year_hi, month, day]
    static func syncTime(_ date: Date = Date(), calendar: Calendar = .current) -> Data {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(comps.year ?? 2026)
        let bytes: [UInt8] = [
            0x01,
            0x07,
            UInt8(comps.hour ?? 0),
            UInt8(comps.minute ?? 0),
            UInt8(comps.second ?? 0),
            UInt8(year & 0xFF),
            UInt8((year >> 8) & 0xFF),
            UInt8(comps.month ?? 1),
            UInt8(comps.day ?? 1)
        ]
        return Data(bytes)
    }

    // MARK: - ID 0x03 握手 / 心跳 / 页面 / 车检 / 故障码 / 便捷设置

    static func appInitOK() -> Data {
        Data([0x03, 0x00, 0x01])
    }

    static func heartbeat() -> Data {
        Data([0x03, 0xAA, 0x00])
    }

    static func appPageNow(_ page: HUDAppPage) -> Data {
        Data([0x03, 0x0D, page.rawValue])
    }

    static func startQuickCheck() -> Data {
        Data([0x03, 0x0E, 0x00])
    }

    static func clearFaultCodes() -> Data {
        Data([0x03, 0x06, 0x00])
    }

    // MARK: - ID 0x04 TPMS

    static func tpmsStartPair(tire: TirePosition) -> Data {
        Data([0x04, 0x00, tire.pairCommandParam])
    }

    static func tpmsSetHighPressureAlarm(_ value: UInt8) -> Data {
        Data([0x04, 0x01, value])
    }

    static func tpmsSetLowPressureAlarm(_ value: UInt8) -> Data {
        Data([0x04, 0x02, value])
    }

    static func tpmsSetHighTempAlarm(_ value: UInt8) -> Data {
        Data([0x04, 0x03, value])
    }

    // MARK: - ID 0x06 昂克赛拉 HUD 专属控制

    /// 字段顺序严格为: up -> down -> ok；三态: 0=松开, 1=按住, 2=单击脉冲
    static func axelaButton(up: UInt8, down: UInt8, ok: UInt8) -> Data {
        Data([0x06, 0x00, up, down, ok])
    }

    static func axelaPanelOpenCali(_ value: Int8) -> Data {
        Data([0x06, 0x02, UInt8(bitPattern: value)])
    }

    static func axelaTestAngleOpen() -> Data {
        Data([0x06, 0x03])
    }

    static func axelaPanelCloseCali(_ value: Int8) -> Data {
        Data([0x06, 0x04, UInt8(bitPattern: value)])
    }

    static func axelaTestAngleClose() -> Data {
        Data([0x06, 0x05])
    }

    static func mcuErrorMsgAck() -> Data {
        Data([0x06, 0xAC, 0x00])
    }

    // MARK: - ID 0x08 主题步进切换

    /// 通用步进切主题（兼容全部原厂与其他车型 HUD：next=true -> 下一个，false -> 上一个）
    static func stepTheme(next: Bool) -> Data {
        Data([0x08, 0x01, 0x05, next ? 0x01 : 0x00])
    }

    // MARK: - ID 0x08 / 0x01 / 0x07 自动关闭发动机启停 (i-Stop)

    /// 查询当前「自动关闭发动机启停」开关状态（原厂/其他车型静默忽略）
    static func queryAutoStartStop() -> Data {
        Data([0x08, 0x01, 0x07, 0xFF])
    }

    /// 设置「自动关闭发动机启停」开关（true=开启自动关闭启停，false=关闭）
    static func setAutoStartStop(enabled: Bool) -> Data {
        Data([0x08, 0x01, 0x07, enabled ? 0x01 : 0x00])
    }

    // MARK: - ID 0x37 / 0x3A 固件查询与新版 `.pak` 刷机

    static func reqMCUVersionLegacy() -> Data {
        Data([0x37, 0x12])
    }

    static func reqMCUMagic() -> Data {
        Data([0x3A, 0x10])
    }

    static func reqMCUVersionSimple() -> Data {
        Data([0x3A, 0x12])
    }

    static func reqMCUUUID() -> Data {
        Data([0x3A, 0x14])
    }

    /// 42B: [0x3A, 0x16, fileSize(u32 LE), md5LowerASCII(32B), fileVersion(u32 LE)]
    static func sendUpgradeFileMD5(fileSize: UInt32, md5LowerHex32: String, fileVersion: UInt32) -> Data {
        var data = Data(capacity: 42)
        data.append(contentsOf: [0x3A, 0x16])
        data.appendUInt32LE(fileSize)
        let md5Bytes = Array(md5LowerHex32.lowercased().utf8.prefix(32))
        data.append(contentsOf: md5Bytes)
        if md5Bytes.count < 32 {
            data.append(contentsOf: repeatElement(UInt8(0x30), count: 32 - md5Bytes.count))
        }
        data.appendUInt32LE(fileVersion)
        return data
    }

    /// 42B: [0x3A, 0x18, offset(u32 LE), dataSize(u32 LE), rangeMD5LowerASCII(32B)]
    static func sendUpgradeRangeMD5(offset: UInt32, dataSize: UInt32, md5LowerHex32: String) -> Data {
        var data = Data(capacity: 42)
        data.append(contentsOf: [0x3A, 0x18])
        data.appendUInt32LE(offset)
        data.appendUInt32LE(dataSize)
        let md5Bytes = Array(md5LowerHex32.lowercased().utf8.prefix(32))
        data.append(contentsOf: md5Bytes)
        if md5Bytes.count < 32 {
            data.append(contentsOf: repeatElement(UInt8(0x30), count: 32 - md5Bytes.count))
        }
        return data
    }

    /// 6 + N (N <= 200): [0x3A, 0x20, offset(u32 LE), slice...]
    static func sendUpgradeFileChunk(offset: UInt32, slice: Data) -> Data {
        let clamped = slice.prefix(200)
        var data = Data(capacity: 6 + clamped.count)
        data.append(contentsOf: [0x3A, 0x20])
        data.appendUInt32LE(offset)
        data.append(clamped)
        return data
    }

    /// immediate == true -> [0x3A, 0x30, 0x01, 0x00] (立即升级并重启)
    /// immediate == false -> [0x3A, 0x30, 0x01, 0x01] (保持/查询状态)
    static func reqMCUStartUpgrade(immediate: Bool) -> Data {
        Data([0x3A, 0x30, 0x01, immediate ? 0x00 : 0x01])
    }
}

extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let b0 = UInt16(self[startIndex + offset])
        let b1 = UInt16(self[startIndex + offset + 1])
        return (b0 << 8) | b1
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let b0 = UInt16(self[startIndex + offset])
        let b1 = UInt16(self[startIndex + offset + 1])
        return b0 | (b1 << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let b0 = UInt32(self[startIndex + offset])
        let b1 = UInt32(self[startIndex + offset + 1])
        let b2 = UInt32(self[startIndex + offset + 2])
        let b3 = UInt32(self[startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    func readInt32LE(at offset: Int) -> Int32? {
        guard let u = readUInt32LE(at: offset) else { return nil }
        return Int32(bitPattern: u)
    }
}
