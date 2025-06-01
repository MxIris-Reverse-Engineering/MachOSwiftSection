import Foundation

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

    var stripManglePrefix: String {
        guard isStartWithManglePrefix else { return self }
        return replacingOccurrences(of: "_$s", with: "")
    }

    var insertManglePrefix: String {
        guard !isStartWithManglePrefix else { return self }
        return "_$s" + self
    }

    var isStartWithManglePrefix: Bool {
        hasPrefix("_$s") || hasPrefix("$s")
    }

    var stripProtocolMangleType: String {
        replacingOccurrences(of: "_p", with: "")
    }

    var stripDuplicateProtocolMangleType: String {
        replacingOccurrences(of: "_p_p", with: "_p")
    }
}
