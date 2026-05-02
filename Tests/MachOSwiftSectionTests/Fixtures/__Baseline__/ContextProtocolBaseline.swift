// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// The `parent` accessor returns a `SymbolOrElement<ContextWrapper>?`
// we don't embed as a literal; the companion Suite verifies the
// method produces cross-reader-consistent results at runtime against
// the presence flag recorded here.

enum ContextProtocolBaseline {
    static let registeredTestMethodNames: Set<String> = ["parent"]

    struct Entry {
        let hasParent: Bool
    }

    static let structTest = Entry(
    hasParent: true
    )
}
