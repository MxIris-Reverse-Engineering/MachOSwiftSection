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

    var insertManglePrefix: String {
        guard !hasSwiftManglingPrefix else { return self }
        return "_$s" + self
    }

    var stripProtocolMangleType: String {
        replacingOccurrences(of: "_p", with: "")
    }

    var stripDuplicateProtocolMangleType: String {
        replacingOccurrences(of: "_p_p", with: "_p")
    }

    /// Length of the Swift mangling prefix the string starts with, `0` for
    /// none.
    ///
    /// The same prefix list as `Demangling.getManglingPrefixLength` (and
    /// `MachOSymbols`' byte-level `nameBytesHaveSwiftManglingPrefix`), kept
    /// local so the ABI model does not depend on the demangler for a prefix
    /// check; `ManglingPrefixTests` pins `hasSwiftManglingPrefix` /
    /// `strippingSwiftManglingPrefix` equal to the demangler's answers (and
    /// `CImportedModuleNames` equal to its module-name constants).
    var swiftManglingPrefixLength: Int {
        let utf8Bytes = utf8
        if utf8Bytes.starts(with: "_T0".utf8) || utf8Bytes.starts(with: "_$S".utf8) || utf8Bytes.starts(with: "_$s".utf8) || utf8Bytes.starts(with: "_$e".utf8) {
            return 3
        } else if utf8Bytes.starts(with: "$S".utf8) || utf8Bytes.starts(with: "$s".utf8) || utf8Bytes.starts(with: "$e".utf8) {
            return 2
        } else if utf8Bytes.starts(with: "@__swiftmacro_".utf8) {
            return 14
        }
        return 0
    }

    /// Whether the string starts with a Swift mangling prefix.
    var hasSwiftManglingPrefix: Bool {
        swiftManglingPrefixLength > 0
    }

    /// The string without its Swift mangling prefix; unchanged when it has
    /// none.
    var strippingSwiftManglingPrefix: String {
        // One prefix scan, not two: `hasSwiftManglingPrefix` would compute
        // the same length and throw it away.
        let prefixLength = swiftManglingPrefixLength
        guard prefixLength > 0 else { return self }
        return String(dropFirst(prefixLength))
    }
}
