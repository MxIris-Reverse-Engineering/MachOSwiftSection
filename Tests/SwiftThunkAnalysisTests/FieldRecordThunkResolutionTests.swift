#if THUNK_ANALYSIS

import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import SwiftThunkAnalysis
@testable import MachOTestingSupport

/// Kind-9 *field records* resolved offline through the same reader, pinned
/// on the fixture — a standalone dylib, so no shared-cache stub and no OS
/// drift: the thunk's calls bind by name and the expected types are what
/// the fixture source declares (`NoncopyableFieldHolderTest.resource` is a
/// `NoncopyableResourceTest`, `boxedInteger` a
/// `NoncopyableGenericBoxTest<Int>`).
// The resolver is scoped to each test's task (`AccessorThunkResolution.taskResolver`),
// never installed process-wide: suites run in parallel, and a process-wide
// install turned every snapshot suite's kind-9 placeholders into real types
// for as long as it lasted.
@Suite(.serialized)
final class FieldRecordThunkResolutionTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private struct ResolvedField {
        let owner: String
        let name: String
        let text: String
    }

    private func resolvedAccessorFields() throws -> [ResolvedField] {
        var resolved: [ResolvedField] = []
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile) else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            let ownerName = try SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default)
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile),
                      typeNode.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                let resolvedNode = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout)
                resolved.append(ResolvedField(owner: ownerName, name: try record.fieldName(in: machOFile), text: resolvedNode.print(using: .default)))
            }
        }
        return resolved
    }

    @Test func resolvesTheFixturesNoncopyableFieldsToTheirDeclaredTypes() throws {
        let fields = try AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver()) {
            try resolvedAccessorFields()
        }
        for field in fields { print("\(field.owner).\(field.name): \(field.text)") }
        #expect(!fields.isEmpty, "the fixture's AccessorFunctionReferences namespace is expected to carry kind-9 field records")

        func text(of name: String) -> String? { fields.first { $0.name == name }?.text }
        #expect(text(of: "resource") == "SymbolTestsCore.AccessorFunctionReferences.NoncopyableResourceTest")
        #expect(text(of: "boxedInteger") == "SymbolTestsCore.AccessorFunctionReferences.NoncopyableGenericBoxTest<Swift.Int>")
        #expect(fields.allSatisfy { !$0.text.contains("accessor function at") }, "some field is still an unread reference")
    }

    /// Without a resolver the reference stays, exactly as the snapshots pin.
    @Test func withoutAResolverTheReferencesStay() throws {
        let fields = try resolvedAccessorFields()
        #expect(!fields.isEmpty)
        #expect(fields.allSatisfy { $0.text.contains("accessor function at") })
    }
}

#endif
