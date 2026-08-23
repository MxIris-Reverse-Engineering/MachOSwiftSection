import Foundation
import Testing
import Demangling
import MachOSymbols
@testable import MachOSwiftSection
import SwiftDeclaration

/// Pins `FunctionDefinition.isOverride` across all three
/// `MethodDescriptorWrapper` cases — most of all `.methodDefaultOverride`,
/// which the historical `??`-chain form silently never honored: `??` is
/// right-associative, so with a non-nil descriptor
/// `a?.isMethodOverride ?? a?.isMethodDefaultOverride ?? false` always took
/// the left side (`.some(false)` for a default-override wrapper) and the
/// second predicate was dead code. Downstream that lost the `override`
/// keyword AND defeated the export-status override exemption (evolution
/// proposal 0008), producing a false `// not exported`.
///
/// Descriptors are built from zeroed layouts — the predicates dispatch on
/// the wrapper CASE alone and never resolve the pointers.
@Suite
struct OverrideRecoveryPredicateTests {
    private func makeFunctionDefinition(methodDescriptor: MethodDescriptorWrapper?) throws -> FunctionDefinition {
        let symbolName = "_$s15SymbolTestsCore3FooC3baryyF"
        let node = try demangleAsNode(symbolName)
        let nodeReference = NodeReference(interning: node)
        let demangledSymbol = DemangledSymbol(symbol: Symbol(offset: 0, name: symbolName, isExternal: false), demangledNode: nodeReference)
        return FunctionDefinition(
            node: nodeReference,
            name: "bar",
            kind: .function,
            symbol: demangledSymbol,
            isGlobalOrStatic: false,
            methodDescriptor: methodDescriptor,
            offset: nil,
            vtableOffset: nil
        )
    }

    @Test func defaultOverrideWrapperIsOverride() throws {
        let descriptor = MethodDefaultOverrideDescriptor(
            layout: .init(
                replacement: .init(relativeOffsetPlusIndirect: 0),
                original: .init(relativeOffsetPlusIndirect: 0),
                implementation: .init(relativeOffset: 0)
            ),
            offset: 0
        )
        let function = try makeFunctionDefinition(methodDescriptor: .methodDefaultOverride(descriptor))
        #expect(function.isOverride)
    }

    @Test func overrideWrapperIsOverride() throws {
        let descriptor = MethodOverrideDescriptor(
            layout: .init(
                class: .init(relativeOffsetPlusIndirect: 0),
                method: .init(relativeOffsetPlusIndirect: 0),
                implementation: .init(relativeOffset: 0)
            ),
            offset: 0
        )
        let function = try makeFunctionDefinition(methodDescriptor: .methodOverride(descriptor))
        #expect(function.isOverride)
    }

    @Test func missingDescriptorIsNotOverride() throws {
        let function = try makeFunctionDefinition(methodDescriptor: nil)
        #expect(!function.isOverride)
    }
}
