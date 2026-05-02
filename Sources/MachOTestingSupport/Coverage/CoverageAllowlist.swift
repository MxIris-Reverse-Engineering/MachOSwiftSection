import Foundation

/// A single entry exempting one (typeName, memberName) pair from coverage requirements.
/// Each entry MUST carry a human-readable reason.
package struct CoverageAllowlistEntry: Hashable, CustomStringConvertible {
    package let key: MethodKey
    package let reason: String

    package init(typeName: String, memberName: String, reason: String) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.reason = reason
    }

    package var description: String {
        "\(key)  // \(reason)"
    }
}
