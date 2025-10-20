import Foundation

extension String {
    package var hasLazyPrefix: Bool {
        hasPrefix("$__lazy_storage_$_")
    }

    package var stripLazyPrefix: String {
        replacingOccurrences(of: "$__lazy_storage_$_", with: "")
    }

    package var hasWeakPrefix: Bool {
        hasPrefix("weak ")
    }

    package var stripWeakPrefix: String {
        replacingOccurrences(of: "weak ", with: "")
    }

    package var insertBracketIfNeeded: String {
        if hasPrefix("("), hasSuffix(")") {
            return self
        } else {
            return "(\(self))"
        }
    }
}
extension String? {
    package var valueOrEmpty: String {
        self ?? ""
    }
}

extension String {
    package var insertSubFunctionPrefix: String {
        "sub_" + self
    }
}
