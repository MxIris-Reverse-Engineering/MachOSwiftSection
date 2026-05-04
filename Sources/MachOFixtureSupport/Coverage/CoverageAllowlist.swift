import Foundation

/// Why a `(typeName, memberName)` pair is allowed to skip cross-reader fixture coverage.
package enum SentinelReason: Hashable {
    /// The type is allocated by the Swift runtime at type-load time and is
    /// never serialized into the fixture's Mach-O image. Covered via
    /// `InProcessMetadataPicker` + single-reader assertions instead.
    case runtimeOnly(detail: String)

    /// SymbolTestsCore currently lacks a sample that surfaces this metadata
    /// shape. Should be eliminated by extending the fixture (Phase B).
    case needsFixtureExtension(detail: String)

    /// Pure raw-value enum / marker protocol / pure-data utility. Sentinel
    /// status is intended to be permanent. Future follow-ups may pin
    /// `rawValue` literals as a deeper assertion.
    case pureDataUtility(detail: String)
}

/// Either a legacy "scanner-saw-it-but-it-shouldn't-count" exemption (kept as-is
/// from PR #85) or a typed sentinel with a reason.
package enum AllowlistKind: Hashable {
    case legacyExempt(reason: String)
    case sentinel(SentinelReason)
}

/// A single entry exempting one (typeName, memberName) pair from coverage requirements.
package struct CoverageAllowlistEntry: Hashable, CustomStringConvertible {
    package let key: MethodKey
    package let kind: AllowlistKind

    package init(typeName: String, memberName: String, reason: String) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .legacyExempt(reason: reason)
    }

    package init(typeName: String, memberName: String, sentinel: SentinelReason) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .sentinel(sentinel)
    }

    package var description: String {
        switch kind {
        case .legacyExempt(let reason):
            return "\(key)  // legacyExempt: \(reason)"
        case .sentinel(let reason):
            return "\(key)  // sentinel: \(reason)"
        }
    }
}
