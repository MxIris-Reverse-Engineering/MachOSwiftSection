import Foundation

/// Tiny helper providing the few literal forms that SwiftSyntaxBuilder's
/// `\(literal:)` does NOT produce in the form we want for ABI baselines.
///
/// Specifically: integers via `\(literal:)` come out as decimal Swift literals,
/// but baseline files emit offsets/sizes/flags as hex (`0x...`) for parity with
/// `otool` / Hopper output. Use these helpers with `\(raw:)` in the
/// SwiftSyntaxBuilder source string.
///
/// For everything else — strings, bools, decimal ints, arrays of strings,
/// optionals — use `\(literal:)` directly; SwiftSyntaxBuilder handles escaping.
package enum BaselineEmitter {
    /// Emit `0x<lowercase-hex>` for any binary integer (sign-extends to UInt64).
    package static func hex<T: BinaryInteger>(_ value: T) -> String {
        let unsigned = UInt64(truncatingIfNeeded: value)
        return "0x\(String(unsigned, radix: 16))"
    }

    /// Emit `[0x..., 0x..., ...]` for an array of binary integers.
    package static func hexArray<T: BinaryInteger>(_ values: [T]) -> String {
        "[\(values.map(hex).joined(separator: ", "))]"
    }
}
