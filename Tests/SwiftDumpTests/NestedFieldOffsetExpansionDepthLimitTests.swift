import Foundation
import Testing
@testable import SwiftDump

/// Pins the `nestedFieldOffsetExpansionDepthLimit` invariant.
///
/// `TypedDumper.walkNestedExpandedFieldOffsets` silently truncates its
/// expansion once `depth >= nestedFieldOffsetExpansionDepthLimit` and emits
/// an `os_log` warning. The limit value is hard-coded as a contract: real
/// Swift nesting rarely exceeds 3-4 layers, so 16 is the generous bound.
/// Changing the value here without also updating:
///
/// 1. The corresponding doc comment on `nestedFieldOffsetExpansionDepthLimit`.
/// 2. The `os_log` message format that names the limit value.
/// 3. The matching invariant in `SwiftInterfaceTests`
///    (`TypeDefinition.nestedSpecializationDepthLimit`).
///
/// would let the silent-truncation hazard reappear under a different number.
/// This test is the trip-wire that catches that drift.
@Suite("TypedDumper nested field-offset expansion depth limit")
struct NestedFieldOffsetExpansionDepthLimitTests {
    @Test("nestedFieldOffsetExpansionDepthLimit pins to 16")
    func limitIsSixteen() {
        #expect(nestedFieldOffsetExpansionDepthLimit == 16)
    }

    /// Defensive: the limit must be strictly positive — a zero or negative
    /// value would short-circuit the very first call and silently disable
    /// nested field-offset expansion across every TypedDumper conformer.
    @Test("nestedFieldOffsetExpansionDepthLimit is strictly positive")
    func limitIsStrictlyPositive() {
        #expect(nestedFieldOffsetExpansionDepthLimit > 0)
    }
}
