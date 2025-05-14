import Foundation

extension String {
    var hexData: Data { .init(hexa) }

    var hexBytes: [UInt8] { .init(hexa) }

    private var hexa: UnfoldSequence<UInt8, Index> {
        sequence(state: startIndex) { startIndex in
            guard startIndex < self.endIndex else { return nil }
            let endIndex = self.index(startIndex, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return UInt8(self[startIndex ..< endIndex], radix: 16)
        }
    }

    func toCharPointer() -> UnsafePointer<Int8> {
        let strPtr: UnsafePointer<Int8> = withCString { (ptr: UnsafePointer<Int8>) -> UnsafePointer<Int8> in
            return ptr
        }
        return strPtr
    }

    func removingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }

    func removingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        return String(dropLast(suffix.count))
    }

    func isAsciiString() -> Bool {
        return range(of: ".*[^A-Za-z0-9_$ ].*", options: .regularExpression) == nil
    }

    func toPointer() -> UnsafePointer<UInt8>? {
        guard let data = data(using: String.Encoding.utf8) else { return nil }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        let stream = OutputStream(toBuffer: buffer, capacity: data.count)

        stream.open()
        data.withUnsafeBytes { (bp: UnsafeRawBufferPointer) in
            if let sp: UnsafePointer<UInt8> = bp.baseAddress?.bindMemory(to: UInt8.self, capacity: MemoryLayout<Any>.stride) {
                stream.write(sp, maxLength: data.count)
            }
        }

        stream.close()

        return UnsafePointer<UInt8>(buffer)
    }
}

extension String {
    init?(cString data: Data) {
        guard !data.isEmpty else { return nil }
        let string: String? = data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else { return nil }
            let ptr = baseAddress.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        guard let string else {
            return nil
        }
        self = string
    }
}

extension String {
    var countedString: String {
        guard !isEmpty else { return "" }
        return "\(count)\(self)"
    }

    var stripProtocolDescriptorMangle: String {
        replacingOccurrences(of: "Mp", with: "")
    }

    var stripNominalTypeDescriptorMangle: String {
        replacingOccurrences(of: "Mn", with: "")
    }

    var stripTypeManglePrefix: String {
        guard hasPrefix("_$s") else { return self }
        return replacingOccurrences(of: "_$s", with: "")
    }

    var insertManglePrefix: String {
        guard !hasPrefix("_$s") else { return self }
        return "_$s" + self
    }

    var stripProtocolMangleType: String {
        replacingOccurrences(of: "_p", with: "")
    }

    var stripDuplicateProtocolMangleType: String {
        replacingOccurrences(of: "_p_p", with: "_p")
    }
}
