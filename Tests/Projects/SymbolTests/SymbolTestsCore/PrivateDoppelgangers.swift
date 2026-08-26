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
