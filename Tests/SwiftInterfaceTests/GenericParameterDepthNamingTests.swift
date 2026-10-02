import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
import MachOTestingSupport

/// A generic parameter's printed name encodes its depth (`A1` is depth 1,
/// index 0), and a depth counts only the contexts that declare parameters.
/// The field records name the parameters that way — the demangler reads the
/// depth straight out of the mangling — so a header has to as well, or its
/// parameter clause and its fields disagree about one parameter.
///
/// The header used to number depths by counting every generic ancestor.
/// `Middle` in `DepthOuter<OuterElement>.Middle.Inner<InnerElement>`
/// declares nothing but is generic, so `InnerElement` printed as `A2` while
/// its field read `A1`; a constrained extension of `DepthOuter.SecondMiddle`
/// spans two depths but counted as one, so `DeepConstrainedInner`'s
/// `InnerElement` printed as `A1` while its field read `A2`.
@Suite
struct GenericParameterDepthNamingTests {
    private func renderInterface() async throws -> String {
        let machOFile = try GenericSpecializationFixture.machOFile()
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func headerLine(declaring typeName: String, in interface: String) -> String? {
        interface.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("struct \(typeName)<") }
    }

    @Test("a parameter behind a level that declares none is named by its canonical depth")
    func parameterBehindNonDeclaringLevel() async throws {
        let interface = try await renderInterface()

        #expect(headerLine(declaring: "Inner", in: interface) == "struct Inner<A1> where A1: Swift.Hashable {", "\(interface)")
        #expect(interface.contains("var innerElement: A1"), "\(interface)")
    }

    @Test("a parameter in a constrained extension of a nested generic type is named by its canonical depth")
    func parameterInConstrainedExtensionOfNestedGeneric() async throws {
        let interface = try await renderInterface()

        #expect(headerLine(declaring: "DeepConstrainedInner", in: interface) == "struct DeepConstrainedInner<A2> where A2: Swift.Hashable {", "\(interface)")
        #expect(interface.contains("var innerElement: A2"), "\(interface)")
    }

    @Test("a parameter in a constrained extension of a top-level generic type keeps depth 1")
    func parameterInConstrainedExtensionOfTopLevelGeneric() async throws {
        let interface = try await renderInterface()

        #expect(headerLine(declaring: "ConstrainedInner", in: interface) == "struct ConstrainedInner<A1> {", "\(interface)")
    }
}
