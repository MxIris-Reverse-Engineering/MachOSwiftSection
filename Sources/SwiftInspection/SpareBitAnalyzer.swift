import Foundation

// MARK: - Analysis Result

public enum SpareBitAnalyzer {
    /// Structured result of spare bit analysis.
    public struct Analysis: CustomStringConvertible, Sendable {
        /// Per-byte analysis entry.
        public struct ByteEntry: CustomStringConvertible, Sendable {
            public let absoluteOffset: Int
            public let byte: UInt8
            public let spareBitCount: Int
            public let spareBitIndices: [Int]

            public var isAllSpare: Bool { byte == 0xFF }
            public var isAllUsed: Bool { byte == 0 }

            public var interpretation: String {
                if isAllUsed {
                    return "None (Used)"
                } else if isAllSpare {
                    return "All 8 bits"
                } else {
                    var parts: [String] = []
                    if (byte & 0xF0) == 0xF0 { parts.append("High 4") }
                    if (byte & 0x0F) == 0x0F { parts.append("Low 4") }
                    if parts.isEmpty {
                        return "Bits: " + spareBitIndices.map(String.init).joined(separator: ",")
                    } else {
                        return parts.joined(separator: ", ")
                    }
                }
            }

            public var description: String {
                let hex = String(format: "0x%02X", byte)
                let binary = toBinaryString(byte)
                return String(format: "  +%02d  | %@ |     %@      | %@", absoluteOffset, hex, binary, interpretation)
            }
        }

        /// A contiguous region of spare bits.
        public struct Region: CustomStringConvertible, Sendable {
            public let range: Range<Int>
            public let bitCount: Int
            public let bytes: [UInt8]

            public var maxTagValue: String {
                if bitCount >= 64 {
                    return "UInt64.max"
                } else {
                    let val = (UInt64(1) << bitCount) - 1
                    let numberFormatter = NumberFormatter()
                    numberFormatter.numberStyle = .decimal
                    return numberFormatter.string(from: NSNumber(value: val)) ?? "\(val)"
                }
            }

            public var description: String {
                "Spare Region: Offset \(range), Capacity: \(bitCount) bits (Max Tag: \(maxTagValue))"
            }
        }

        public let startOffset: Int
        public let rawBytes: [UInt8]
        public let entries: [ByteEntry]
        public let regions: [Region]
        public let totalSpareBits: Int

        public var description: String {
            var output = "Spare Bits Analysis (Little Endian Memory)\n"
            output += "Input Offset: \(startOffset)\n"
            output += "Input Bytes (Hex): \(rawBytes.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
            output += "Total Spare Bits: \(totalSpareBits)\n"
            for entry in entries {
                output += "\(entry)\n"
            }
            for region in regions {
                output += ">>> \(region)\n"
            }
            return output
        }
    }

    // MARK: - Structured Analysis

    /// Analyze spare bits and return a structured result.
    public static func analyze(bytes: [UInt8], startOffset: Int) -> Analysis {
        var entries: [Analysis.ByteEntry] = []
        var regions: [Analysis.Region] = []
        var totalSpareBits = 0

        var currentRegionStartOffset: Int? = nil
        var currentRegionBitsCount = 0
        var currentRegionBytes: [UInt8] = []

        for (index, byte) in bytes.enumerated() {
            let absoluteOffset = startOffset + index

            var spareBitIndices: [Int] = []
            for i in 0 ..< 8 {
                if (byte & (1 << i)) != 0 { spareBitIndices.append(i) }
            }

            let entry = Analysis.ByteEntry(
                absoluteOffset: absoluteOffset,
                byte: byte,
                spareBitCount: byte.nonzeroBitCount,
                spareBitIndices: spareBitIndices
            )
            entries.append(entry)
            totalSpareBits += byte.nonzeroBitCount

            if byte != 0 {
                if currentRegionStartOffset == nil {
                    currentRegionStartOffset = absoluteOffset
                }
                currentRegionBitsCount += byte.nonzeroBitCount
                currentRegionBytes.append(byte)
            } else {
                if let start = currentRegionStartOffset {
                    regions.append(Analysis.Region(
                        range: start ..< absoluteOffset,
                        bitCount: currentRegionBitsCount,
                        bytes: currentRegionBytes
                    ))
                    currentRegionStartOffset = nil
                    currentRegionBitsCount = 0
                    currentRegionBytes = []
                }
            }
        }

        if let start = currentRegionStartOffset {
            regions.append(Analysis.Region(
                range: start ..< (startOffset + bytes.count),
                bitCount: currentRegionBitsCount,
                bytes: currentRegionBytes
            ))
        }

        return Analysis(
            startOffset: startOffset,
            rawBytes: bytes,
            entries: entries,
            regions: regions,
            totalSpareBits: totalSpareBits
        )
    }

    // MARK: - Legacy Print-Based Analysis

    /// Print spare bit analysis to stdout (backward-compatible).
    public static func printAnalysis(bytes: [UInt8], startOffset: Int) {
        let analysis = analyze(bytes: bytes, startOffset: startOffset)

        print("=== Spare Bits Analysis (Little Endian Memory) ===")
        print("Input Offset: \(analysis.startOffset)")
        print("Input Bytes (Hex): \(analysis.rawBytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("-------------------------------------------------------------")
        print("Offset | Hex  | Binary (MSB->LSB) | Spare Bits (1=Spare)")
        print("-------|------|-------------------|--------------------------")

        for entry in analysis.entries {
            print(entry.description)
        }

        for region in analysis.regions {
            print("------------------------------------------------------")
            print(">>> Found Spare Region: Offset \(region.range)")
            print(">>> Capacity: \(region.bitCount) bits (Max Tag: \(region.maxTagValue))")
            print("------------------------------------------------------")
        }

        print("=============================================================")
    }
}

private func toBinaryString(_ byte: UInt8) -> String {
    let binary = String(byte, radix: 2)
    let padding = String(repeating: "0", count: 8 - binary.count)
    return padding + binary
}
