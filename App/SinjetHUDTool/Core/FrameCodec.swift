import Foundation

/// 原厂 `BLEDataProc` 帧编解码器
/// 帧格式: [0xFF, 0x55, LEN, PAYLOAD[0..<LEN], CHECKSUM]
/// CHECKSUM = (LEN + sum(PAYLOAD)) & 0xFF
struct FrameCodec {
    static let maxRxPayloadLength = 0xA0 // 160 bytes (实证于 antProc:)

    /// 封装发送帧
    static func encode(payload: Data) -> Data {
        precondition(payload.count <= 255, "Payload exceeds 1-byte LEN limit")
        let lenByte = UInt8(payload.count)
        var checksum: UInt8 = lenByte
        for b in payload {
            checksum = checksum &+ b
        }

        var frame = Data(capacity: payload.count + 4)
        frame.append(0xFF)
        frame.append(0x55)
        frame.append(lenByte)
        frame.append(payload)
        frame.append(checksum)
        return frame
    }

    static func encode(bytes: [UInt8]) -> Data {
        encode(payload: Data(bytes))
    }
}

/// 逐字节 RX 拆包状态机（完全对应 `BLEDataProc.antProc:`）
final class FrameRxParser {
    private enum State {
        case waitFF
        case wait55
        case waitLength
        case collecting
    }

    private var state: State = .waitFF
    private var expectedLength: Int = 0
    private var runningCRC: UInt8 = 0
    private var buffer: [UInt8] = []

    init() {
        buffer.reserveCapacity(FrameCodec.maxRxPayloadLength)
    }

    func reset() {
        state = .waitFF
        expectedLength = 0
        runningCRC = 0
        buffer.removeAll(keepingCapacity: true)
    }

    /// 喂入 BLE 通知收到的原始字节，返回本次解析出的所有完整合法 Payload（含首字节消息 ID）
    func feed(_ data: Data) -> [Data] {
        var frames: [Data] = []
        for byte in data {
            switch state {
            case .waitFF:
                if byte == 0xFF {
                    state = .wait55
                }
            case .wait55:
                if byte == 0x55 {
                    state = .waitLength
                } else if byte == 0xFF {
                    state = .wait55
                } else {
                    state = .waitFF
                }
            case .waitLength:
                let length = Int(byte)
                if length <= FrameCodec.maxRxPayloadLength {
                    expectedLength = length
                    runningCRC = byte
                    buffer.removeAll(keepingCapacity: true)
                    state = .collecting
                } else {
                    state = .waitFF
                }
            case .collecting:
                if buffer.count < expectedLength {
                    buffer.append(byte)
                    runningCRC = runningCRC &+ byte
                } else {
                    // 校验末字节
                    if byte == runningCRC, !buffer.isEmpty {
                        frames.append(Data(buffer))
                    }
                    reset()
                }
            }
        }
        return frames
    }
}
