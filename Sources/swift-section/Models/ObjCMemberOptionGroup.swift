import ArgumentParser
import SwiftInspection

/// The ObjC member recovery's one user-facing knob, shared by `dump` and
/// `interface` (both print the `override` / `@objc` facts the recovery
/// gives; `snapshot` records none of them).
struct ObjCMemberOptionGroup: ParsableArguments, Sendable {
    @Flag(name: .customLong("infer-objc-overrides"), help: "Also mark as `override` an ObjC method that overrides an ancestor's but whose IMP references no Swift symbol — the optimizer inlined the body into the thunk (`viewDidHide`, `encodeWithCoder:` in an OS framework) — by attributing it to the one member of the class whose name is the importer's spelling of its selector. Name evidence only, so off by default; the dump marks members tied this way `(selector name, no symbol evidence)`. Never adds an `@objc(name)`: a method no ancestor implements is left alone.")
    var infersOverridesFromSelectorNames: Bool = false

    /// The options to register for the image, or to hand the indexer.
    var recoveryOptions: ObjCMemberRecoveryOptions {
        ObjCMemberRecoveryOptions(infersOverridesFromSelectorNames: infersOverridesFromSelectorNames)
    }
}
