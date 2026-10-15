import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable @_spi(Internals) import SwiftInspection

/// The private declarations a name reads (evolution proposal
/// `private-declarations`): the whole tree but a declaring function's or
/// closure's signature and a position-based local type's address.
///
/// The manglings are real. The `SwiftUI` ones are type descriptor symbols of
/// macOS 27.2's SwiftUI. The `Shapes` ones come from compiling, with
/// `swiftc -c -Onone -parse-as-library -module-name Shapes`, a file that
/// declares — among the shapes named in each test — `private struct
/// PrivateArgument {}`, `private struct PrivateGeneric<Element> {}` and
/// `private struct PrivateHolder`; its private discriminator is
/// `_C01776A4525D5700C9CAB18498B5F7E5`.
@Suite(ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct PrivateDeclarationsTests {
    private static let shapesDiscriminator = "_C01776A4525D5700C9CAB18498B5F7E5"

    private static func privateDeclarations(of mangledName: String) throws -> [PrivateDeclaration] {
        try demangleAsNodeTransient(mangledName).privateDeclarations
    }

    // MARK: - Declarations and their contexts

    @Test func privateTypeReadsItself() throws {
        #expect(try Self.privateDeclarations(of: "$s6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVMn") == [
            PrivateDeclaration(name: "PrivateArgument", discriminator: Self.shapesDiscriminator),
        ])
    }

    /// `private func hidden()` of a private type carries no discriminator of
    /// its own: the type's is the one read.
    @Test func typeInAMethodOfAPrivateTypeReadsTheType() throws {
        // InPrivateMethodOfPrivateType #1 in Shapes.(PrivateHolder in _C017…).hidden() -> Any
        #expect(try Self.privateDeclarations(of: "$s6Shapes13PrivateHolder33_C01776A4525D5700C9CAB18498B5F7E5LLV6hiddenypyF02Inb8MethodOfB4TypeL_VMn") == [
            PrivateDeclaration(name: "PrivateHolder", discriminator: Self.shapesDiscriminator),
        ])
    }

    /// A type declared in a constrained extension of a private type sits
    /// under an `extension` node, whose parent is its second child: the
    /// extended type is read.
    @Test func typeInAConstrainedExtensionReadsTheExtendedType() throws {
        // (extension in Shapes):Shapes.(PrivateGeneric in _C017…)<A where A == Swift.Int>.InConstrainedExtension
        #expect(try Self.privateDeclarations(of: "$s6Shapes14PrivateGeneric33_C01776A4525D5700C9CAB18498B5F7E5LLVAASiRszlE22InConstrainedExtensionVMn") == [
            PrivateDeclaration(name: "PrivateGeneric", discriminator: Self.shapesDiscriminator),
        ])
    }

    @Test func specializedTypeReadsItsGenericArguments() throws {
        // [Shapes.(PrivateArgument in _C017…)]
        #expect(try Self.privateDeclarations(of: "$sSay6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVGD") == [
            PrivateDeclaration(name: "PrivateArgument", discriminator: Self.shapesDiscriminator),
        ])
    }

    @Test func declarationsAreReadInOrderAndOnce() throws {
        // [Shapes.(PrivateArgument in _C017…) : Shapes.(PrivateHolder in _C017…)]
        #expect(try Self.privateDeclarations(of: "$sSDy6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVAA13PrivateHolder33_C01776A4525D5700C9CAB18498B5F7E5LLVGD") == [
            PrivateDeclaration(name: "PrivateArgument", discriminator: Self.shapesDiscriminator),
            PrivateDeclaration(name: "PrivateHolder", discriminator: Self.shapesDiscriminator),
        ])
        // [Shapes.(PrivateArgument in _C017…) : Shapes.(PrivateArgument in _C017…)]
        #expect(try Self.privateDeclarations(of: "$sSDy6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVADGD") == [
            PrivateDeclaration(name: "PrivateArgument", discriminator: Self.shapesDiscriminator),
        ])
    }

    // MARK: - Local types

    /// A local type whose function is not private reads nothing, though the
    /// function's signature names a type of the module.
    @Test func localTypeOfANonPrivateMethodReadsNothing() throws {
        // Visitor #1 in SwiftUI.TableDataSource.performDrop(to: SwiftUI.DropCoordinator<Foundation.IndexPath>) -> ()
        #expect(try Self.privateDeclarations(of: "$s7SwiftUI15TableDataSourceV11performDrop2toyAA0G11CoordinatorVy10Foundation9IndexPathVG_tF7VisitorL_VMn").isEmpty)
    }

    /// The method a local type is declared in is read when it is private —
    /// the method's discriminator, under the method's name, not the type's.
    @Test func localTypeOfAPrivateMethodReadsTheMethod() throws {
        // IndexingWrappingGenerator #1 in closure #1 () -> () in SwiftUI.AccessibilityRotorInfo.(readEntryList in _030667BF…)((SwiftUI.AccessibilityRotorEntryList) -> ()) -> ()
        #expect(try Self.privateDeclarations(of: "$s7SwiftUI22AccessibilityRotorInfoV13readEntryList33_030667BFE09FD674B7612731735E240ELLyyyAA0cdgH0VXEFyyXEfU_25IndexingWrappingGeneratorL_VMn") == [
            PrivateDeclaration(name: "readEntryList", discriminator: "_030667BFE09FD674B7612731735E240E"),
        ])
    }

    /// The private type in a private method's signature is not read; the
    /// method is.
    @Test func privateTypeInAMethodSignatureIsNotRead() throws {
        // InPrivateSignature #1 in Shapes.Holder.(takes in _C017…)(Shapes.(PrivateArgument in _C017…)) -> Any
        #expect(try Self.privateDeclarations(of: "$s6Shapes6HolderV5takes33_C01776A4525D5700C9CAB18498B5F7E5LLyypAA15PrivateArgumentAELLVF02InL9SignatureL_VMn") == [
            PrivateDeclaration(name: "takes", discriminator: Self.shapesDiscriminator),
        ])
    }

    @Test func privateTypeInAClosureSignatureIsNotRead() throws {
        // InClosureSignature #1 in closure #1 (Shapes.(PrivateArgument in _C017…)) -> Any in Shapes.Holder.closure() -> Any
        #expect(try Self.privateDeclarations(of: "$s6Shapes6HolderV7closureypyFypAA15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVcfU_18InClosureSignatureL_VMn").isEmpty)
    }

    /// A private initializer's or subscript's mangled private name carries a
    /// discriminator and no name; the declaration's kind stands in for one.
    @Test func privateInitializerAndSubscriptAreNamedByTheirKind() throws {
        // InPrivateInitializer #1 in Shapes.Holder.(in _C017…).init(argument: Swift.Int) -> Shapes.Holder
        #expect(try Self.privateDeclarations(of: "$s6Shapes6HolderV8argumentACSi_tc33_C01776A4525D5700C9CAB18498B5F7E5Llfc20InPrivateInitializerL_VMn") == [
            PrivateDeclaration(name: "init", discriminator: Self.shapesDiscriminator),
        ])
        // InPrivateSubscript #1 in Shapes.Holder.subscript.getter : (Swift.Int) -> Any
        #expect(try Self.privateDeclarations(of: "$s6Shapes6HolderVyypSic33_C01776A4525D5700C9CAB18498B5F7E5Llig18InPrivateSubscriptL_VMn") == [
            PrivateDeclaration(name: "subscript", discriminator: Self.shapesDiscriminator),
        ])
    }

    /// `Holder.(Visitor in $1a2b3c)`: the shape of a private name, the
    /// address of the anonymous context wrapping the type.
    @Test func positionBasedAddressIsNoDiscriminator() {
        let holder = Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "M"),
            Node.create(kind: .identifier, text: "Holder"),
        ])
        let visitor = Node.create(kind: .type, child: Node.create(kind: .structure, children: [
            holder,
            Node.create(kind: .privateDeclName, children: [
                Node.create(kind: .identifier, text: "$1a2b3c"),
                Node.create(kind: .identifier, text: "Visitor"),
            ]),
        ]))

        #expect(visitor.localTypeNaming == .positionBased)
        #expect(visitor.privateDeclarations.isEmpty)
        #expect(NodeReference(interning: visitor).privateDeclarations.isEmpty)
    }

    // MARK: - Names built from descriptors

    /// What `SymbolicDemangler` names each local type of the fixture: only
    /// `Hidden`, declared in the private `hiddenValues()`, reads a private
    /// declaration, and where nothing names the functions every name is
    /// position-based and reads none.
    @Test(arguments: [LocalTypeFixture.Variant.unstripped, .stripped])
    func localTypesBuiltFromDescriptorsReadOnlyTheirPrivateMethod(variant: LocalTypeFixture.Variant) throws {
        let machOFile = try LocalTypeFixture.machOFile(variant)
        var privateDeclarationsByTypeName: [String: [PrivateDeclaration]] = [:]
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            let descriptor = typeContextDescriptor.asContextDescriptorWrapper
            guard try LocalTypeFixture.isDeclaredInABody(descriptor, in: machOFile.context) else { continue }
            let typeName = try #require(try descriptor.namedContextDescriptor?.name(in: machOFile.context))
            let node = try SymbolicDemangler.demangleContext(for: descriptor, in: machOFile.context)
            privateDeclarationsByTypeName[typeName, default: []] += node.privateDeclarations
        }

        #expect(privateDeclarationsByTypeName.count > 10)
        for (typeName, privateDeclarations) in privateDeclarationsByTypeName where !(typeName == "Hidden" && variant == .unstripped) {
            #expect(privateDeclarations.isEmpty, "\(typeName) reads \(privateDeclarations)")
        }
        if variant == .unstripped {
            let hidden = try #require(privateDeclarationsByTypeName["Hidden"])
            #expect(hidden.map(\.name) == ["hiddenValues"])
            #expect(hidden.allSatisfy { $0.discriminator.hasPrefix("_") && $0.discriminator.count == 33 })
        }
    }
}
