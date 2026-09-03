import Testing
import Demangling
@testable import MachOSwiftSection

/// The ABI layer keeps its own mangling-prefix check so that it does not
/// depend on the demangler for one prefix test (evolution proposal
/// `self-contained-abi-layer`). This pins it to the demangler's verdict.
@Suite
struct ManglingPrefixTests {
    @Test(arguments: [
        "_T0Si", "_$SSi", "_$sSi", "_$eSi", "$SSi", "$sSi", "$eSi", "@__swiftmacro_33main4fooV",
        "Si", "_Si", "$", "_$", "", "T0Si", "swiftmacro_", "__C", "_$t", "$x",
    ])
    func agreesWithTheDemangler(_ string: String) {
        #expect(string.hasSwiftManglingPrefix == string.isSwiftSymbol)
        #expect(string.strippingSwiftManglingPrefix == string.stripManglePrefix)
    }
}
