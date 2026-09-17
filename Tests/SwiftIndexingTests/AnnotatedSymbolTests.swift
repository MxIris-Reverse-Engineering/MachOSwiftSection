import Demangling
import MachOResolving
import MachOSymbols
import SwiftDeclaration
import Testing

/// Pins the one hazard `AnnotatedSymbol` carries: its `@dynamicMemberLookup`
/// forwards `DemangledSymbol.offset` — the symbol's own byte offset in the
/// image — while every payload it carries means something else entirely. A
/// specialization declaring an accessor named `offset` would shadow the
/// forwarded one silently, with no diagnostic, and the two values are not
/// interchangeable: the predecessor type stored its witness-table offset under
/// exactly that name, which is why every builder had to reach through `base`
/// to read the real symbol offset.
///
/// The two offsets below are deliberately different values, so a shadowing
/// regression cannot pass by coincidence.
@Suite
struct AnnotatedSymbolTests {
    private static let symbolName = "_$s15SymbolTestsCore3FooC3baryyF"
    private static let symbolOffset = 0x4321
    private static let witnessTableOffset = 0x18

    private func makeDemangledSymbol() throws -> DemangledSymbol {
        let node = try demangleAsNodeTransient(Self.symbolName)
        return DemangledSymbol(
            symbol: Symbol(offset: Self.symbolOffset, name: Self.symbolName, isExternal: false),
            demangledNode: NodeReference(interning: node)
        )
    }

    @Test func annotationDoesNotShadowTheForwardedSymbolOffset() throws {
        let base = try makeDemangledSymbol()
        let annotated = AnnotatedSymbol(base: base, protocolWitnessTableOffset: Self.witnessTableOffset)

        #expect(annotated.offset == Self.symbolOffset)
        #expect(annotated.offset == base.offset)
        #expect(annotated.protocolWitnessTableOffset == Self.witnessTableOffset)
        #expect(annotated.payload?.rawValue == Self.witnessTableOffset)
    }

    @Test func aSymbolWithNoAnnotationStillForwardsItsOwnOffset() throws {
        let base = try makeDemangledSymbol()
        let annotated: [MemberSymbol] = [base].mapToAnnotatedSymbols()

        #expect(annotated.count == 1)
        #expect(annotated[0].offset == Self.symbolOffset)
        #expect(annotated[0].protocolWitnessTableOffset == nil)
        #expect(annotated[0].payload == nil)
    }
}
