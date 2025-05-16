import Foundation

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
