// The second half of the same-named-private-type pair — see
// `PrivateDoppelgangers.swift` for the full rationale and the
// optimization-survival tricks. This file's `PrivateDoppelganger` carries a
// different private discriminator and deliberately different members
// (`beta*` against the first file's `alpha*`), so a member-attribution
// regression (issue #115) is visible as `beta*` members appearing under the
// first file's declaration or vice versa.

private struct PrivateDoppelganger {
    var betaStorage: Int64

    @_optimize(none)
    @inline(never)
    init(betaSeed: Int64) {
        self.betaStorage = betaSeed
    }

    @_optimize(none)
    @inline(never)
    func betaOnlyMethod() -> Int64 {
        betaStorage &* 2
    }
}

public enum PrivateDoppelgangerSecondFileAnchors {
    @inline(never)
    public static func materializeSecondDoppelganger() -> Any {
        let doppelganger = PrivateDoppelganger(betaSeed: 21)
        _ = doppelganger.betaOnlyMethod()
        return doppelganger
    }
}

// MARK: - Protocol half of the same-named-private-type pair

// The second half of the same-named `private protocol` pair — see
// `PrivateDoppelgangers.swift` for the full rationale. This declaration
// carries a different private discriminator and deliberately different default
// implementations (`beta*` against the first file's `alpha*`).

private protocol PrivateDoppelgangerProtocol {
    var seedValue: Int64 { get }
}

extension PrivateDoppelgangerProtocol {
    @_optimize(none)
    @inline(never)
    var betaDefaultProperty: Int64 { seedValue &- 3 }

    @_optimize(none)
    @inline(never)
    func betaDefaultMethod() -> Int64 { seedValue &* 5 }
}

private struct BetaProtocolWitness: PrivateDoppelgangerProtocol {
    var seedValue: Int64
}

// MARK: - Class half of the same-named-private-type pair

// The second half of the same-named `private class` pair. `sharedStoredProperty`
// is declared `final` HERE and non-final in the first file: under the
// discriminator-stripped name lookup the first file's vtable accessor evidence
// landed in this type's bucket and stripped the `final` keyword from the
// rendered output.

private class PrivateDoppelgangerClass {
    var betaOnlyStoredProperty: Int64

    @_optimize(none)
    @inline(never)
    init(betaSeed: Int64) {
        self.betaOnlyStoredProperty = betaSeed &- 1
    }

    /// Declared `final` HERE and non-final in the first file. `final` recovery
    /// (evolution proposal 0006) must see NO vtable evidence for this name in
    /// THIS type's own bucket — a name-only lookup merged the first file's
    /// non-final namesake in and stripped the keyword.
    @_optimize(none)
    @inline(never)
    final func sharedNameMethod() -> Int64 {
        betaOnlyStoredProperty &- 1
    }

    @_optimize(none)
    @inline(never)
    func betaClassMethod() -> Int64 {
        betaOnlyStoredProperty &* 3
    }
}

extension PrivateDoppelgangerSecondFileAnchors {
    @inline(never)
    public static func materializeSecondProtocolWitness() -> Any {
        let witness = BetaProtocolWitness(seedValue: 9)
        _ = witness.betaDefaultProperty
        _ = witness.betaDefaultMethod()
        return witness
    }

    @inline(never)
    public static func materializeSecondDoppelgangerClass() -> Any {
        let instance = PrivateDoppelgangerClass(betaSeed: 3)
        _ = instance.betaClassMethod()
        _ = instance.sharedNameMethod()
        return instance
    }
}
