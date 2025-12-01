import Foundation

public struct EnumTagCounts {
    public let numTags: UInt32
    public let numTagBytes: UInt32
}

public func getEnumTagCounts(payloadSize: UInt64, emptyCases: UInt32, payloadCases: UInt32) -> EnumTagCounts {
    var numTags = payloadCases

    if emptyCases > 0 {
        if payloadSize >= 4 {
            numTags += 1
        } else {
            let bits = UInt32(payloadSize * 8)
            let casesPerTagBitValue: UInt32 = 1 << bits
            numTags += ((emptyCases + (casesPerTagBitValue - 1)) >> bits)
        }
    }

    let numTagBytes: UInt32 = numTags <= 1 ? 0 :
        numTags < 256 ? 1 :
        numTags < 65536 ? 2 : 4
    
    return EnumTagCounts(numTags: numTags, numTagBytes: numTagBytes)
}
