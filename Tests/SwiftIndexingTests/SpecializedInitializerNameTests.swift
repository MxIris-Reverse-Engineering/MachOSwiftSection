import Foundation
import Testing
import Demangling
import MachOResolving
import MachOSymbols
import SwiftDeclaration

/// `StandInMemberSymbolBuilder.specializedInitializerName(of:)`: the name of
/// the initializing entry point a function signature specialization
/// specializes, read off the specialization's own name. Swift 6.4's
/// whole-module optimization leaves an internal class's initializer only as
/// such a specialization (`ThunkOnlyObjCMemberTests` covers the image); these
/// pin the name on its own, whatever the compiler at hand emits.
@Suite
struct SpecializedInitializerNameTests {
    private static let initializingEntryPointName = "_$s22ThunkOnlyMemberFixture017InitializingEntryB6HolderC6valuesACSaySSG_tcfc"

    private func demangledSymbol(named name: String) throws -> DemangledSymbol {
        DemangledSymbol(symbol: Symbol(offset: 0, name: name, isExternal: false), demangledNode: NodeReference(interning: try demangleAsNode(name)))
    }

    @Test func aSpecializationReadsBackToItsInitializingEntryPoint() throws {
        let specialization = try demangledSymbol(named: Self.initializingEntryPointName + "Tf4gn_n")
        #expect(StandInMemberSymbolBuilder.specializedInitializerName(of: specialization) == Self.initializingEntryPointName)
    }

    /// The last `Tf` suffix belongs to the outer specialization; the name
    /// before it ends in another specialization, not in `fc`.
    @Test func aSpecializationOfASpecializationReadsBackToo() throws {
        let specialization = try demangledSymbol(named: Self.initializingEntryPointName + "Tf4gn_nTf4n_g")
        #expect(StandInMemberSymbolBuilder.specializedInitializerName(of: specialization) == Self.initializingEntryPointName)
    }

    @Test func anythingElseHasNone() throws {
        // The initializing entry point itself.
        #expect(StandInMemberSymbolBuilder.specializedInitializerName(of: try demangledSymbol(named: Self.initializingEntryPointName)) == nil)
        // A method's specialization.
        #expect(StandInMemberSymbolBuilder.specializedInitializerName(of: try demangledSymbol(named: "_$s15SymbolTestsCore3FooC3baryyFTf4n_n")) == nil)
    }
}
