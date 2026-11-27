import CryptoKit
import Foundation

/// `.pak` 固件本地完整性校验器（与 `repack_pak_version.py` 规则 100% 一致）
enum PakValidator {
    static let expectedMagic: UInt32 = 0x84236066

    static func md5LowerHex(_ data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func validate(data: Data, fileName: String) -> PakValidationReport {
        let wholeMD5 = md5LowerHex(data)
        let bytes = [UInt8](data)
        let totalLen = bytes.count

        guard totalLen >= 16 else {
            return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: "文件长度不足 16 字节")
        }

        let fileVersion = data.readUInt32LE(at: 8) ?? 0
        var pos = 0
        var records: [PakRecordSummary] = []
        var versionSet = Set<UInt32>()
        var md5ErrCount = 0
        var hdrErrCount = 0
        var blkErrCount = 0
        var placeholderCount = 0
        var recordIdx = 0

        while pos < totalLen {
            if pos + 4 <= totalLen &&
                bytes[pos] == 0xFF && bytes[pos + 1] == 0xFF &&
                bytes[pos + 2] == 0xFF && bytes[pos + 3] == 0xFF {
                break
            }

            guard pos + 14 <= totalLen else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: String(format: "偏移 0x%06X 处记录头截断", pos))
            }

            guard let sizeU32 = data.readUInt32LE(at: pos),
                  let magic = data.readUInt32LE(at: pos + 4),
                  let ver = data.readUInt32LE(at: pos + 8) else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: String(format: "偏移 0x%06X 无法读取头字段", pos))
            }

            guard magic == expectedMagic else {
                return makeErrorReport(
                    fileName: fileName,
                    fileSize: totalLen,
                    wholeMD5: wholeMD5,
                    error: String(format: "偏移 0x%06X Magic 异常: 0x%08X (应为 0x%08X)", pos, magic, expectedMagic)
                )
            }

            let size = Int(sizeU32)
            let nameLen = Int(bytes[pos + 12])
            let nameStart = pos + 13
            let nameEnd = nameStart + nameLen
            guard nameEnd < totalLen else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: String(format: "偏移 0x%06X 文件名越界", pos))
            }
            guard bytes[nameEnd] == 0 else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: String(format: "偏移 0x%06X 文件名缺少 NUL 结束符", pos))
            }

            let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .ascii) ?? "record_\(recordIdx)"
            let md5Off = nameEnd + 1
            guard md5Off + 33 <= totalLen else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: "记录 \(name) MD5 字段截断")
            }
            guard bytes[md5Off + 32] == 0 else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: "记录 \(name) MD5 缺少 NUL 结束符")
            }

            let expectedMD5 = (String(bytes: bytes[md5Off..<(md5Off + 32)], encoding: .ascii) ?? "").lowercased()
            let csumOff = md5Off + 33
            let n4k = (size + 0xFFF) / 0x1000
            let pstart = csumOff + 1 + n4k
            let pend = pos + size

            guard pstart <= pend, pend <= totalLen else {
                return makeErrorReport(fileName: fileName, fileSize: totalLen, wholeMD5: wholeMD5, error: "记录 \(name) 载荷边界越界 (end=\(pend), total=\(totalLen))")
            }

            // 1. 子记录载荷 MD5
            let payloadSlice = data.subdata(in: pstart..<pend)
            let actualMD5 = md5LowerHex(payloadSlice)
            if actualMD5 != expectedMD5 {
                md5ErrCount += 1
            }

            // 2. 头部校验和 (sum & 0xFF, 0xFF -> 0x00)
            var rawHS: UInt8 = 0
            for idx in pos..<csumOff {
                rawHS = rawHS &+ bytes[idx]
            }
            let expectedHS: UInt8 = (rawHS == 0xFF) ? 0x00 : rawHS
            let headerOK = (bytes[csumOff] == expectedHS)
            if !headerOK {
                hdrErrCount += 1
            }

            // 3. 每 4KB 块校验和（兼容原厂 0xFE 占位符，其余不一致记为错误）
            var recBlkErrors = 0
            var recPlaceholders = 0
            for i in 0..<n4k {
                let s = (i == 0) ? pstart : (pos + i * 0x1000)
                let e = min(pend, pos + (i + 1) * 0x1000)
                var rawBS: UInt8 = 0
                if s < e {
                    for idx in s..<e {
                        rawBS = rawBS &+ bytes[idx]
                    }
                }
                let expectedBS: UInt8 = (rawBS == 0xFF) ? 0x00 : rawBS
                let gotBS = bytes[csumOff + 1 + i]
                if gotBS != expectedBS {
                    if gotBS == 0xFE {
                        recPlaceholders += 1
                        placeholderCount += 1
                    } else {
                        recBlkErrors += 1
                        blkErrCount += 1
                    }
                }
            }

            versionSet.insert(ver)
            records.append(
                PakRecordSummary(
                    id: recordIdx,
                    name: name,
                    offset: pos,
                    size: size,
                    version: ver,
                    expectedMD5: expectedMD5,
                    actualMD5: actualMD5,
                    headerChecksumOK: headerOK,
                    blockCount: n4k,
                    blockErrorCount: recBlkErrors,
                    placeholderBlockCount: recPlaceholders
                )
            )

            recordIdx += 1
            pos = ((pos + size + 0xFFF) / 0x1000) * 0x1000
        }

        // 提取 #SW_MODULE# 与 #SW_DATE#
        let asciiText = String(decoding: data, as: UTF8.self)
        let swModules = extractMatches(in: asciiText, pattern: "#SW_MODULE#(HUD[A-Z0-9_]{2,24})")
        let swDates = extractMatches(in: asciiText, pattern: "#SW_DATE#([0-9]{8})")

        return PakValidationReport(
            fileName: fileName,
            fileSize: totalLen,
            wholeFileMD5: wholeMD5,
            fileVersion: fileVersion,
            recordCount: records.count,
            headerVersions: versionSet.sorted(),
            swModules: swModules,
            swDates: swDates,
            records: records,
            md5ErrorCount: md5ErrCount,
            headerErrorCount: hdrErrCount,
            blockErrorCount: blkErrCount,
            placeholderBlockCount: placeholderCount,
            structuralError: records.isEmpty ? "未找到任何有效的 .pak 子记录" : nil
        )
    }

    private static func makeErrorReport(fileName: String, fileSize: Int, wholeMD5: String, error: String) -> PakValidationReport {
        PakValidationReport(
            fileName: fileName,
            fileSize: fileSize,
            wholeFileMD5: wholeMD5,
            fileVersion: 0,
            recordCount: 0,
            headerVersions: [],
            swModules: [],
            swDates: [],
            records: [],
            md5ErrorCount: 0,
            headerErrorCount: 0,
            blockErrorCount: 0,
            placeholderBlockCount: 0,
            structuralError: error
        )
    }

    private static func extractMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var results = Set<String>()
        for match in regex.matches(in: text, options: [], range: range) {
            if match.numberOfRanges >= 2 {
                let capture = nsText.substring(with: match.range(at: 1))
                results.insert(capture)
            }
        }
        return results.sorted()
    }
}
