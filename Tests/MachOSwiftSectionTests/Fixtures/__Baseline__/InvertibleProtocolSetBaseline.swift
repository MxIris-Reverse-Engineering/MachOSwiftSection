// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// InvertibleProtocolSet has no live SymbolTestsCore source (the
// Copyable/Escapable bits are encoded inline on type generic
// signatures), so the baseline embeds synthetic raw values that
// exercise each branch (none / copyable-only / escapable-only / both).

enum InvertibleProtocolSetBaseline {
    static let registeredTestMethodNames: Set<String> = ["copyable", "escapable", "hasCopyable", "hasEscapable", "init(rawValue:)", "rawValue"]

    struct Entry {
        let rawValue: UInt16
        let hasCopyable: Bool
        let hasEscapable: Bool
    }

    static let none = Entry(
    rawValue: 0x0,
    hasCopyable: false,
    hasEscapable: false
    )

    static let copyableOnly = Entry(
    rawValue: 0x1,
    hasCopyable: true,
    hasEscapable: false
    )

    static let escapableOnly = Entry(
    rawValue: 0x2,
    hasCopyable: false,
    hasEscapable: true
    )

    static let both = Entry(
    rawValue: 0x3,
    hasCopyable: true,
    hasEscapable: true
    )
}
