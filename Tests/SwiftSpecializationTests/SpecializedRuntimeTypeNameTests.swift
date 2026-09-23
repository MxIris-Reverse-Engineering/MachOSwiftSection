@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport

// MARK: - Fixtures
//
// The compiler parents every outermost `private` / `fileprivate` type on an
// anonymous context descriptor, so the runtime treats its identity as unstable
// (`IRGenModule::getAddrOfParentContextDescriptor`). A specialized definition's
// bound name comes from the runtime (`_mangledTypeName`), and the runtime
// spells that context by the descriptor's address —
// `AnonymousContext("$<address>", <parent>, TypeList())`, which names nothing a
// reader can use. Each fixture below puts such a context, or an extension
// context, at a different position of a runtime-derived name.

/// Anonymous context directly under the module.
private struct RuntimeNamedPrivateBox<Element> {
    let element: Element
}

/// A private type used as a generic argument.
private struct RuntimeNamedPrivateArgument {
    let value: Int
}

struct RuntimeNamedHost {
    /// Anonymous context in the MIDDLE of the chain: box → anonymous context →
    /// `RuntimeNamedHost` → module.
    private struct RuntimeNamedPrivateNestedBox<Element> {
        let element: Element
    }
}

/// A field whose type is generic over the definition's own parameter: the
/// expanded field-offset comment names the nested field's type through the
/// runtime layout backend, not through the interface printer.
private struct RuntimeNamedPrivateLayoutOuter<Element> {
    let inner: RuntimeNamedPrivateLayoutInner<Element>
}

private struct RuntimeNamedPrivateLayoutInner<Element> {
    let element: Element
}

extension Int {
    /// Nested in an extension of another module's type, so its parent is an
    /// extension context rather than `Swift.Int` itself.
    struct RuntimeNamedExtensionBox<Element> {
        let element: Element
    }
}

// MARK: - Tests

/// A specialized definition's names come from the runtime, and must read the
/// way the unspecialized definition's do: a private type keeps its module and
/// its enclosing types, whether it is the definition itself, one of its type
/// arguments, or a type named in a field-offset comment.
///
/// Before the fix the interface printer rendered the runtime's anonymous
/// context as nothing, so `BoundDumpedTypeNameRenderer`'s separator dangled in
/// front of the name (`struct .WindowPortal<AppKit.ButtonContent>`, AppKit on
/// macOS 26.7), a private nested type lost its whole parent chain, and a
/// private type argument lost its module.
@Suite(.serialized)
struct SpecializedRuntimeTypeNameTests: GenericSpecializationTestingEnvironment {
    /// Specializes the indexed definition whose name contains `typeNameFragment`
    /// and prints it the way RuntimeViewer does.
    private func printSpecialized(
        _ typeNameFragment: String,
        with selection: SpecializationSelection,
        configuration: SwiftDeclarationPrintConfiguration = .init()
    ) async throws -> String {
        let resolvedIndexer = try await indexer
        let baseDefinition = try #require(
            resolvedIndexer.allTypeDefinitions.first { $0.key.name.contains(typeNameFragment) }?.value,
            "expected the indexer to hold a definition named like \(typeNameFragment)"
        )
        let specializer = GenericSpecializer(indexer: resolvedIndexer)
        let request = try specializer.makeRequest(for: baseDefinition.typeContextDescriptorWrapper)
        let specializationResult = try specializer.specialize(request, with: selection)
        let specialized = try await baseDefinition.specialize(with: specializationResult, in: machO)
        let printer = SwiftDeclarationPrinter<MachOImage>(configuration: configuration, in: machO)
        return try await printer.printTypeDefinition(specialized).string
    }

    private func headerLine(of printed: String) -> String {
        printed.split(separator: "\n").first { $0.contains("struct ") }.map(String.init) ?? ""
    }

    @Test("a specialized private type's header keeps its module")
    func privateTypeHeaderKeepsItsModule() async throws {
        let printed = try await printSpecialized("RuntimeNamedPrivateBox", with: ["A": .metatype(Int.self)])

        #expect(headerLine(of: printed) == "struct SwiftSpecializationTests.RuntimeNamedPrivateBox<Swift.Int> {")
    }

    @Test("a specialized private nested type's header keeps its enclosing types")
    func privateNestedTypeHeaderKeepsItsEnclosingTypes() async throws {
        let printed = try await printSpecialized("RuntimeNamedPrivateNestedBox", with: ["A": .metatype(Int.self)])

        #expect(headerLine(of: printed) == "struct SwiftSpecializationTests.RuntimeNamedHost.RuntimeNamedPrivateNestedBox<Swift.Int> {")
    }

    @Test("a private type argument keeps its module in the header")
    func privateTypeArgumentKeepsItsModuleInTheHeader() async throws {
        let printed = try await printSpecialized("RuntimeNamedPrivateBox", with: ["A": .metatype(RuntimeNamedPrivateArgument.self)])

        #expect(headerLine(of: printed) == "struct SwiftSpecializationTests.RuntimeNamedPrivateBox<SwiftSpecializationTests.RuntimeNamedPrivateArgument> {")
    }

    @Test("a field of a private type keeps the type's module")
    func fieldOfPrivateTypeKeepsItsModule() async throws {
        let printed = try await printSpecialized("RuntimeNamedPrivateBox", with: ["A": .metatype(RuntimeNamedPrivateArgument.self)])

        #expect(printed.contains("let element: SwiftSpecializationTests.RuntimeNamedPrivateArgument"), "got:\n\(printed)")
    }

    @Test("an expanded field-offset comment names a private type argument with its module")
    func expandedFieldOffsetCommentKeepsPrivateArgumentModule() async throws {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printFieldOffset = true
        configuration.printExpandedFieldOffsets = true

        let printed = try await printSpecialized("RuntimeNamedPrivateLayoutOuter", with: ["A": .metatype(RuntimeNamedPrivateArgument.self)], configuration: configuration)

        #expect(printed.contains("element (SwiftSpecializationTests.RuntimeNamedPrivateArgument)"), "got:\n\(printed)")
    }

    /// The extension context itself still prints as nothing — spelling it as the
    /// extended type is a separate change — but the name must not open with a
    /// dangling separator.
    @Test("a specialized type nested in another module's extension prints no leading separator")
    func typeInCrossModuleExtensionPrintsNoLeadingSeparator() async throws {
        let printed = try await printSpecialized("RuntimeNamedExtensionBox", with: ["A": .metatype(Int.self)])
        let header = headerLine(of: printed)
        try #require(header.contains("RuntimeNamedExtensionBox<Swift.Int>"), "unexpected header: \(header)")

        #expect(!header.hasPrefix("struct ."), "got: \(header)")
    }
}
