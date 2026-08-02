import Foundation
import Testing
import SwiftDeclarationRendering

/// Pins the `nestedFieldOffsetExpansionDepthLimit` invariant.
///
/// The live limit is the `package`-visible constant in
/// `SwiftDeclarationRendering` (`FieldLayoutRenderer.swift`) — the single
/// source of truth shared by the dump and interface paths since the field
/// engine moved out of `SwiftDump`. (`SwiftDump.TypedDumper` briefly kept a
/// dead duplicate that this test used to pin instead; it has been deleted.)
///
/// `RuntimeFieldLayoutBackend.walkNestedExpandedFieldOffsets` truncates its
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
@Suite("Nested field-offset expansion depth limit")
struct NestedFieldOffsetExpansionDepthLimitTests {
    @Test("nestedFieldOffsetExpansionDepthLimit pins to 16")
    func limitIsSixteen() {
        #expect(nestedFieldOffsetExpansionDepthLimit == 16)
    }

    /// Defensive: the limit must be strictly positive — a zero or negative
    /// value would short-circuit the very first call and silently disable
    /// nested field-offset expansion in every rendering path.
    @Test("nestedFieldOffsetExpansionDepthLimit is strictly positive")
    func limitIsStrictlyPositive() {
        #expect(nestedFieldOffsetExpansionDepthLimit > 0)
    }
}
