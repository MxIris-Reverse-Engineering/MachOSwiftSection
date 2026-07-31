@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import SwiftDump

// MARK: - In-process fixture

/// Reflection fixture for the Void-payload parenthesis contract. Lives in the
/// test binary itself so `MachOImage.current()` carries its descriptors.
public enum VoidPayloadRenderingFixtureEnum {
    case unitPayload(Void)
    case intPayload(Int)
    case plain
}

// MARK: - Tests

/// Pins the enum-case spelling parity between the dump path (`EnumDumper`)
/// and the model-driven interface path (`renderModelFields` →
/// `printThrowingEnumCase`).
///
/// The regression being guarded: the leaf migration rerouted the main
/// interface path onto the diff renderer's `printEnumCase`, whose payload
/// gating inspects the *rendered payload text* (`"()"` means no payload) —
/// so a `Void` payload case printed as bare `case unitPayload` while the
/// dump path (gating on the field record's mangled type name, the
/// pre-refactor contract) kept printing `case unitPayload()`. The two paths
/// must spell the same enum identically; a `Void` payload is a payload case
/// in the ABI (it participates in the payload-case count) and keeps its
/// parentheses.
@Suite(.serialized)
struct EnumCaseRenderingParityTests: GenericSpecializationTestingEnvironment {
    private func resolveTypeDefinition(named substring: String) async throws -> TypeDefinition {
        let resolvedIndexer = try await indexer
        return try #require(
            resolvedIndexer.allTypeDefinitions.first(where: { entry in
                entry.key.name.contains(substring)
            })?.value,
            "expected indexer to have a TypeDefinition whose typeName contains \"\(substring)\""
        )
    }

    private func caseLines(in output: String) -> Set<String> {
        Set(
            output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("case ") || $0.hasPrefix("indirect case ") }
        )
    }

    @MainActor
    @Test("interface path keeps Void-payload parentheses")
    func interfacePathKeepsVoidPayloadParentheses() async throws {
        let definition = try await resolveTypeDefinition(named: "VoidPayloadRenderingFixtureEnum")
        let printer = SwiftDeclarationPrinter<MachOImage>(in: machO)
        let printed = try await printer.printTypeDefinition(definition).string

        #expect(printed.contains("case unitPayload()"), "got: \(printed)")
        #expect(printed.contains("case intPayload(Swift.Int)"), "got: \(printed)")
        #expect(!printed.contains("case plain("), "empty case must stay bare — got: \(printed)")
    }

    @MainActor
    @Test("dump and interface paths spell every case identically")
    func dumpAndInterfacePathsAgree() async throws {
        // Interface path (model-driven).
        let definition = try await resolveTypeDefinition(named: "VoidPayloadRenderingFixtureEnum")
        let printer = SwiftDeclarationPrinter<MachOImage>(in: machO)
        let interfaceOutput = try await printer.printTypeDefinition(definition).string

        // Dump path (raw descriptor through `EnumDumper`).
        var dumpOutput: String? = nil
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .enum(let enumDescriptor) = typeContextDescriptor,
                  try enumDescriptor.name(in: machO) == "VoidPayloadRenderingFixtureEnum" else { continue }
            let enumType = try Enum(descriptor: enumDescriptor, in: machO)
            dumpOutput = try await enumType.dump(using: .demangleOptions(.interface), in: machO).string
            break
        }
        let resolvedDumpOutput = try #require(dumpOutput, "fixture enum descriptor not found in the test image")

        let interfaceCaseLines = caseLines(in: interfaceOutput)
        let dumpCaseLines = caseLines(in: resolvedDumpOutput)
        #expect(interfaceCaseLines == dumpCaseLines, "interface: \(interfaceCaseLines) vs dump: \(dumpCaseLines)")
        #expect(dumpCaseLines.contains("case unitPayload()"))
    }
}
