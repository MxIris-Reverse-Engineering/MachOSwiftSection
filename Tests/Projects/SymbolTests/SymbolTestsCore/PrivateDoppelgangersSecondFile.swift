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
