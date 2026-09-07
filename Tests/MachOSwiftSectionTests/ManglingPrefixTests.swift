import Testing
import Demangling
@testable import MachOSwiftSection

/// The ABI layer keeps its own mangling-prefix check and its own copies of
/// the C-imported module names so that it does not depend on the demangler
/// for them (evolution proposal `self-contained-abi-layer`). This pins both
/// to the demangler's own values: a drift in the prefix list would
/// misclassify symbols, a drift in the module names would make every
/// `isCImportedContextDescriptor` answer `false` for the `__C` module.
@Suite
struct ManglingPrefixTests {
    @Test func cImportedModuleNamesMatchTheDemangler() {
        #expect(CImportedModuleNames.objectiveC == objcModule)
        #expect(CImportedModuleNames.cSynthesized == cModule)
    }

    @Test(arguments: [
        "_T0Si", "_$SSi", "_$sSi", "_$eSi", "$SSi", "$sSi", "$eSi", "@__swiftmacro_33main4fooV",
        "Si", "_Si", "$", "_$", "", "T0Si", "swiftmacro_", "__C", "_$t", "$x",
    ])
    func agreesWithTheDemangler(_ string: String) {
        #expect(string.hasSwiftManglingPrefix == string.isSwiftSymbol)
        #expect(string.strippingSwiftManglingPrefix == string.stripManglePrefix)
    }
}
