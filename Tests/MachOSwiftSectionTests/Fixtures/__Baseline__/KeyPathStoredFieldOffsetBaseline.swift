// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The two stored shapes a property descriptor produces: an offset
// the binary states outright, and one that only names where in the
// metadata the real offset lives.

enum KeyPathStoredFieldOffsetBaseline {
    static let registeredTestMethodNames: Set<String> = ["kind", "rawValue", "staticFieldOffset"]

    struct Entry {
        let kindDescription: String
        let rawValue: UInt32
        let staticFieldOffset: UInt32?
    }

    static let inlineStoredOffset = Entry(
    kindDescription: "inline",
    rawValue: 0x0,
    staticFieldOffset: 0x0
    )

    static let unresolvedFieldOffset = Entry(
    kindDescription: "unresolvedFieldOffset",
    rawValue: 0x20,
    staticFieldOffset: nil
    )

    /// Synthesized: no fixture property lands on the out-of-line case
    /// (it needs an offset above 0x7FFFFC), but it is a static offset
    /// like the inline one and must report as such.
    static let synthesizedOutOfLine = Entry(
    kindDescription: "outOfLine",
    rawValue: 0x800000,
    staticFieldOffset: 0x800000
    )

    /// Synthesized: the shape a class with a resilient superclass
    /// gets. Like `unresolvedFieldOffset`, it has no static offset.
    static let synthesizedUnresolvedIndirectOffset = Entry(
    kindDescription: "unresolvedIndirectOffset",
    rawValue: 0x40,
    staticFieldOffset: nil
    )
}
