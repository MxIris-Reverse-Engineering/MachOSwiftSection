import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable @_spi(Internals) import SwiftInspection
@testable import SwiftDeclarationRendering

/// The runtime names a local type through its anonymous contexts' addresses
/// (`AnonymousContext("$<address>", …)` for the type's own, each closure's
/// and the function's). A name that comes from the runtime has to read like
/// the one built from the descriptors (evolution proposal
/// `local-type-context-names`): the compiler's spelling where the image
/// records it, the same position-based name where it does not. Dropping
/// every anonymous context instead, as `RuntimeTypeNameDemangling` did, read
/// both of `Holder`'s `Visitor`s as `Holder.Visitor`.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct RuntimeTypeNameLocalTypeTests {
    @Test(arguments: LocalTypeFixture.Variant.allCases)
    func runtimeNameOfALocalTypeIsItsDescriptorBuiltName(variant: LocalTypeFixture.Variant) throws {
        let machOImage = try LocalTypeFixture.loadedImage(variant)
        var runtimeNames: [String] = []
        for descriptor in try machOImage.swift.typeContextDescriptors {
            let contextDescriptor = descriptor.asContextDescriptorWrapper
            // A generic type's accessor wants its arguments.
            guard try LocalTypeFixture.isDeclaredInABody(contextDescriptor, in: machOImage.context),
                  !descriptor.contextDescriptor.layout.flags.isGeneric,
                  let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machOImage.context)
            else { continue }
            let metatype = unsafeBitCast(UInt(try accessor(request: .init()).value.address), to: Any.Type.self)
            let descriptorBuiltNode = try SymbolicDemangler.demangleContext(for: contextDescriptor, in: machOImage.context)

            let runtimeNode = try #require(RuntimeTypeNameDemangling.node(forMetatype: metatype))

            let runtimeName = Self.printedName(of: runtimeNode)
            #expect(runtimeName == Self.printedName(of: descriptorBuiltNode))
            #expect(runtimeNode.first(of: .anonymousContext) == nil, "\(runtimeName)")
            runtimeNames.append(runtimeName)
        }
        // Every local type but the generic `IndexWrappingVisitor`, no two alike.
        #expect(runtimeNames.count == 19)
        #expect(Set(runtimeNames).count == runtimeNames.count, "\(runtimeNames.sorted())")
        if variant != .stripped {
            let expectedNames = LocalTypeFixture.compilerSpelledNames(of: variant).filter { !$0.hasPrefix("IndexWrappingVisitor ") }
            #expect(runtimeNames.filter { !LocalTypeFixture.isCompilerSpelledHiddenName($0, of: variant) }.sorted() == expectedNames.sorted())
        }
    }

    private static func printedName(of node: Node) -> String {
        var nominal = node
        while nominal.kind == .global || nominal.kind == .type || nominal.kind == .typeMangling, let child = nominal.children.first {
            nominal = child
        }
        return nominal.print(using: .default)
    }
}
