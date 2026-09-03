/// The module names the compiler gives C-imported declarations, as the
/// runtime spells them in module context descriptors: `__C` for
/// Objective-C / C declarations and `__C_Synthesized` for the wrappers it
/// synthesizes around them.
///
/// These are ABI facts, so they live here rather than being borrowed from
/// the demangler's `objcModule` / `cModule` constants — the ABI model does
/// not depend on `Demangling` (evolution proposal `self-contained-abi-layer`).
enum CImportedModuleNames {
    static let objectiveC = "__C"
    static let cSynthesized = "__C_Synthesized"
}
