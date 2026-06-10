import Foundation
import Testing
@_spi(Support) import SwiftInterface

/// Pins the `nestedSpecializationDepthLimit` invariant.
///
/// `TypeDefinition.deriveNestedSpecializedTypeChildren` silently truncates a
/// subtree once `depth >= nestedSpecializationDepthLimit` and emits an
/// `os_log` warning. The limit value is hard-coded as a contract: real Swift
/// nesting rarely exceeds 3-4 layers, so 16 is the generous bound. Changing
/// the value here without also updating:
///
/// 1. The corresponding doc comment on `TypeDefinition.nestedSpecializationDepthLimit`.
/// 2. The `os_log` message format that names the limit value.
/// 3. The matching invariant in `SwiftDumpTests`
///    (`nestedFieldOffsetExpansionDepthLimit`).
///
/// would let the silent-truncation hazard reappear under a different number.
/// This test is the trip-wire that catches that drift.
@Suite("TypeDefinition nested specialization depth limit")
struct NestedSpecializationDepthLimitTests {
    @Test("nestedSpecializationDepthLimit pins to 16")
    func limitIsSixteen() {
        #expect(TypeDefinition.nestedSpecializationDepthLimit == 16)
    }

    /// Defensive: the limit must be strictly positive — a zero or negative
    /// value would short-circuit the very first call and silently disable
    /// nested specialization derivation across the board.
    @Test("nestedSpecializationDepthLimit is strictly positive")
    func limitIsStrictlyPositive() {
        #expect(TypeDefinition.nestedSpecializationDepthLimit > 0)
    }
}
