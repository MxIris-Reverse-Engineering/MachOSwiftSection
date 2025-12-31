import Foundation

enum SpareBitAnalyzer {
    static func analyze(bytes: [UInt8], startOffset: Int) {
        print("=== Spare Bits Analysis (Little Endian Memory) ===")
        print("Input Offset: \(startOffset)")
        print("Input Bytes (Hex): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("-------------------------------------------------------------")
        print("Offset | Hex  | Binary (MSB->LSB) | Spare Bits (1=Spare)")
        print("-------|------|-------------------|--------------------------")

        var currentStartOffset: Int? = nil
        var currentBitsCount = 0
        var currentBytes: [UInt8] = []

        for (index, byte) in bytes.enumerated() {
            let absoluteOffset = startOffset + index
            let hex = String(format: "%02X", byte)
            let binary = toBinaryString(byte)

            var interpretation = ""
            if byte == 0 {
                interpretation = "None (Used)"
            } else if byte == 0xFF {
                interpretation = "All 8 bits"
            } else {
                var parts: [String] = []
                if (byte & 0xF0) == 0xF0 { parts.append("High 4") }
                if (byte & 0x0F) == 0x0F { parts.append("Low 4") }
                if parts.isEmpty {
                    var bits: [Int] = []
                    for i in 0 ..< 8 {
                        if (byte & (1 << i)) != 0 { bits.append(i) }
                    }
                    interpretation = "Bits: " + bits.map(String.init).joined(separator: ",")
                } else {
                    interpretation = parts.joined(separator: ", ")
                }
            }

            print(String(format: "  +%02d  | 0x%@ |     %@      | %@", absoluteOffset, hex, binary, interpretation))

            if byte != 0 {
                if currentStartOffset == nil {
                    currentStartOffset = absoluteOffset
                }
                currentBitsCount += byte.nonzeroBitCount
                currentBytes.append(byte)
            } else {
                if let start = currentStartOffset {
                    let end = absoluteOffset
                    printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
                    currentStartOffset = nil
                    currentBitsCount = 0
                    currentBytes = []
                }
            }
        }

        if let start = currentStartOffset {
            let end = startOffset + bytes.count
            printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
        }
        print("=============================================================")
    }

    private static func toBinaryString(_ byte: UInt8) -> String {
        let binary = String(byte, radix: 2)
        let padding = String(repeating: "0", count: 8 - binary.count)
        return padding + binary
    }

    private static func printRegionSummary(range: Range<Int>, bits: Int, bytes: [UInt8]) {
        let maxTag: String
        if bits >= 64 {
            maxTag = "UInt64.max"
        } else {
            let val = (UInt64(1) << bits) - 1
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            maxTag = numberFormatter.string(from: NSNumber(value: val)) ?? "\(val)"
        }

        print("------------------------------------------------------")
        print(">>> Found Spare Region: Offset \(range)")
        print(">>> Capacity: \(bits) bits (Max Tag: \(maxTag))")
        print("------------------------------------------------------")
    }
}
