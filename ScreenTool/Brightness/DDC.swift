import Foundation

/// VESA DDC/CI message encoding shared by the Intel and Apple Silicon transports.
enum DDC {
    static let brightness: UInt8 = 0x10
    static let monitorAddress: UInt8 = 0x6E  // 8-bit write address (7-bit 0x37)
    static let hostAddress: UInt8 = 0x51
    static let replyLength = 11

    /// Set VCP Feature, starting with the host address byte.
    static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        withChecksum([hostAddress, 0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Get VCP Feature, starting with the host address byte.
    static func getVCP(_ code: UInt8) -> [UInt8] {
        withChecksum([hostAddress, 0x82, 0x01, code])
    }

    /// Parses a Get VCP Feature reply: `6E 88 02 result code type maxHi maxLo curHi curLo checksum`.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: Int, maximum: Int)? {
        guard reply.count >= replyLength,
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == code,
              reply[10] == reply[0..<10].reduce(0x50, ^) else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return (current, maximum)
    }

    private static func withChecksum(_ message: [UInt8]) -> [UInt8] {
        message + [message.reduce(monitorAddress, ^)]
    }
}

/// Brightness over DDC/CI, independent of how bytes reach the monitor.
final class DDCBrightness: BrightnessControl {
    typealias Transport = (_ write: [UInt8], _ replyLength: Int) -> [UInt8]?

    let kind = "DDC"
    let minimumWriteInterval: TimeInterval = 0.05
    private let transport: Transport
    private var maximum: Int

    /// Probes the monitor; nil when it does not answer a Brightness query.
    init?(transport: @escaping Transport) {
        self.transport = transport
        maximum = 100
        guard let reply = query() else { return nil }
        maximum = reply.maximum
    }

    func read() -> Double? {
        query().map { Double($0.current) / Double($0.maximum) }
    }

    func write(_ value: Double) -> Bool {
        let raw = UInt16((min(max(value, 0), 1) * Double(maximum)).rounded())
        return transport(DDC.setVCP(DDC.brightness, value: raw), 0) != nil
    }

    private func query() -> (current: Int, maximum: Int)? {
        for _ in 0..<3 {
            if let reply = transport(DDC.getVCP(DDC.brightness), DDC.replyLength),
               let parsed = DDC.parseReply(reply, code: DDC.brightness) {
                return parsed
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }
}
