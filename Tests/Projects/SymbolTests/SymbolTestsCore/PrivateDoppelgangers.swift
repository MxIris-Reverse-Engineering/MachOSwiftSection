// This file and `PrivateDoppelgangersSecondFile.swift` each declare a
// top-level `private struct PrivateDoppelganger` with the same base name.
// The compiler tells them apart only by the per-file private discriminator
// (`(PrivateDoppelganger in _XXXX...)`), which `DemangleOptions.interface`
// deliberately strips — so the two types collide on the printed-name key of
// `SymbolIndexStore`'s member indexes and only the interned context node can
// attribute their member symbols to the right declaration (issue #115: the
// dump path merged both types' initializers and methods into each).
//
// `@_optimize(none)` keeps the members' unspecialized symbols (Release
// otherwise leaves only a `Tf4nd_n` signature-specialized init thunk, which
// the member indexes do not classify); the anchor boxes an instance as `Any`
// so the metadata accessor — and with it the nominal type descriptor and
// field descriptor — survives optimization.

private struct PrivateDoppelganger {
    var alphaStorage: Int64

    @_optimize(none)
    @inline(never)
    init(alphaSeed: Int64) {
        self.alphaStorage = alphaSeed
    }

    @_optimize(none)
    @inline(never)
    func alphaOnlyMethod() -> Int64 {
        alphaStorage &+ 1
    }
}

public enum PrivateDoppelgangerFirstFileAnchors {
    @inline(never)
    public static func materializeFirstDoppelganger() -> Any {
        let doppelganger = PrivateDoppelganger(alphaSeed: 41)
        _ = doppelganger.alphaOnlyMethod()
        return doppelganger
    }
}

// MARK: - Protocol half of the same-named-private-type pair

// `SwiftDeclarationIndexer.unifyExtensionContainers` attaches a protocol's
// symbol-scan extension block to its declaration, so the interface renders the
// block trailing the protocol (evolution proposal 0007). Keying that
// attachment on the discriminator-stripped printed name merged the two
// declarations below into one: the losing bucket was first flagged
// `isAttachedToProtocolDefinition` (which removes it from the top-level
// extensions block) and then overwritten out of
// `defaultImplementationExtensions` by the winner's assignment — its members
// disappeared from the output entirely, and which bucket lost depended on
// dictionary iteration order.
//
// This file's default implementations are `alpha*`; the second file's are
// `beta*`, so a regression shows up as one set missing or rendering under the
// other file's declaration.

private protocol PrivateDoppelgangerProtocol {
    var seedValue: Int64 { get }
}

extension PrivateDoppelgangerProtocol {
    @_optimize(none)
    @inline(never)
    var alphaDefaultProperty: Int64 { seedValue &+ 3 }

    @_optimize(none)
    @inline(never)
    func alphaDefaultMethod() -> Int64 { seedValue &* 3 }
}

private struct AlphaProtocolWitness: PrivateDoppelgangerProtocol {
    var seedValue: Int64
}

// MARK: - Class half of the same-named-private-type pair

// `final` recovery (evolution proposal 0006) decides the keyword from vtable
// accessor evidence looked up by type name. Under the discriminator-stripped
// name both declarations shared one bucket, so this file's NON-final
// `sharedStoredProperty` supplied vtable evidence that denied `final` to the
// second file's genuinely final property of the same name.

private class PrivateDoppelgangerClass {
    var alphaOnlyStoredProperty: Int64

    @_optimize(none)
    @inline(never)
    init(alphaSeed: Int64) {
        self.alphaOnlyStoredProperty = alphaSeed &+ 1
    }

    /// Non-final here, `final` in the second file, under the same stripped
    /// name — the shape `final` recovery would misread if its symbol lookups
    /// were not node-matched. NOTE: this pair pins non-regression, not a
    /// reproduction: a `private` class emits neither `Tq` method-descriptor
    /// symbols nor stored-property accessor symbols, so neither side can
    /// actually supply the other with false negative evidence, and Swift
    /// rejects a same-named `internal`/`private` pair outright (`invalid
    /// redeclaration`). See `ReviewAdjudications.md`.
    @_optimize(none)
    @inline(never)
    func sharedNameMethod() -> Int64 {
        alphaOnlyStoredProperty &+ 1
    }

    @_optimize(none)
    @inline(never)
    func alphaClassMethod() -> Int64 {
        alphaOnlyStoredProperty &* 2
    }
}

extension PrivateDoppelgangerFirstFileAnchors {
    @inline(never)
    public static func materializeFirstProtocolWitness() -> Any {
        let witness = AlphaProtocolWitness(seedValue: 7)
        _ = witness.alphaDefaultProperty
        _ = witness.alphaDefaultMethod()
        return witness
    }

    @inline(never)
    public static func materializeFirstDoppelgangerClass() -> Any {
        let instance = PrivateDoppelgangerClass(alphaSeed: 5)
        _ = instance.alphaClassMethod()
        _ = instance.sharedNameMethod()
        return instance
    }
}
