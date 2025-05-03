import Foundation
@_spi(Support) import MachOKit

extension FileHandle {
    func readString(
        offset: UInt64
    ) -> String? {
        var data: [UInt8] = []
        var offset = offset

        while true {
            let value: UInt8 = read(offset: offset)
            if value == 0 {
                break
            }
            offset += 1
            data.append(value)
        }

        if let string = String(bytes: data, encoding: .ascii), string.isAsciiString() {
            return string
        }

        return data.reduce("0x") { (result, val: UInt8) -> String in
            return result + String(format: "%02x", val)
        }
    }
}
