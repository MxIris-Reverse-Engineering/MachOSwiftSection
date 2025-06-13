import Foundation

extension String {
    var hasLazyPrefix: Bool {
        hasPrefix("$__lazy_storage_$_")
    }

    var stripLazyPrefix: String {
        replacingOccurrences(of: "$__lazy_storage_$_", with: "")
    }

    var hasWeakPrefix: Bool {
        hasPrefix("weak ")
    }

    var stripWeakPrefix: String {
        replacingOccurrences(of: "weak ", with: "")
    }

    var insertBracketIfNeeded: String {
        if hasPrefix("("), hasSuffix(")") {
            return self
        } else {
            return "(\(self))"
        }
    }
}
extension String? {
    var valueOrEmpty: String {
        self ?? ""
    }
}
