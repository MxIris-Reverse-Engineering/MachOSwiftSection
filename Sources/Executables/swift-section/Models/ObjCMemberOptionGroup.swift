import ArgumentParser

/// The ObjC member recovery's one user-facing knob, on `interface` alone.
///
/// The recovery itself always runs all three evidence tiers; this decides
/// whether the third — a tie made from the member's NAME, with no symbol
/// behind it — is printed as a keyword. `dump` needs no flag: it names every
/// tie's evidence, so it renders that tier always and says what it rests on.
/// `snapshot` records none of these facts at all.
struct ObjCMemberOptionGroup: ParsableArguments, Sendable {
    @Flag(name: .customLong("infer-objc-overrides"), help: "Also mark as `override` an ObjC method that overrides an ancestor's but whose IMP references no Swift symbol — the optimizer inlined the body into the thunk (`viewDidHide`, `encodeWithCoder:` in an OS framework) — by attributing it to the one member of the class whose name is the importer's spelling of its selector. Name evidence only, and a .swiftinterface has nowhere to say so, hence off by default; `dump` always shows these ties and marks them `(selector name, no symbol evidence)`. Never adds an `@objc(name)`: a method no ancestor implements is left alone.")
    var infersOverridesFromSelectorNames: Bool = false
}
