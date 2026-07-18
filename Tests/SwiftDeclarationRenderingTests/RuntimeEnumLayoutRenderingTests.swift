import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import Demangling
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Verifies the **MachOImage** (runtime) enum-layout path end-to-end on the
/// fixture: single-payload empty cases render their *exact* extra-inhabitant
/// byte patterns (projected through the enum's own value witnesses via
/// `RuntimeEnumCaseProjector`) instead of the former placeholder output, and
/// the per-case comments carry the source-level case names.
///
/// `Enums.SinglePayloadOverStructTest` is the regression shape: a struct
/// payload whose extra inhabitants come from a class reference, where empty
/// case `first` is the *all-zero* pattern (null reference) and `second` is
/// pointer value `1` — bytes only the runtime projection can know.
@Suite(.serialized)
final class RuntimeEnumLayoutRenderingTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func findFixtureEnum(named typeName: String) throws -> TypeContextWrapper? {
        for type in try machOImage.swift.types {
            guard case .enum(let enumType) = type, !enumType.descriptor.isGeneric else { continue }
            guard let node = try? MetadataReader.demangleContext(for: .type(.enum(enumType.descriptor)), in: machOImage) else { continue }
            if node.print(using: .default).contains(typeName) {
                return type
            }
        }
        return nil
    }

    @MainActor
    @Test func rendersExactSinglePayloadEmptyCasePatterns() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        let type = try #require(try findFixtureEnum(named: "SinglePayloadOverStructTest"))
        let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
        let enumLayout = try #require(await renderer.enumLayout)

        #expect(enumLayout.cases.count == 3)

        let payloadCase = enumLayout.cases[0]
        #expect(payloadCase.isPayloadCase)
        #expect(payloadCase.declaredName == "wrapped")
        #expect(payloadCase.patternResolution == .exactBytes)
        #expect(payloadCase.memoryChanges.isEmpty, "no extra tag bytes — the payload case writes nothing")

        // `first` is extra inhabitant #0 of the class-reference payload: the
        // null pointer, i.e. the all-zero word — previously indistinguishable
        // from "no pattern computed".
        let firstCase = enumLayout.cases[1]
        #expect(firstCase.declaredName == "first")
        #expect(firstCase.patternResolution == .exactBytes)
        #expect(!firstCase.memoryChanges.isEmpty)
        #expect(firstCase.memoryChanges.values.allSatisfy { $0 == 0 })

        // `second` is extra inhabitant #1: pointer value 1.
        let secondCase = enumLayout.cases[2]
        #expect(secondCase.declaredName == "second")
        #expect(secondCase.patternResolution == .exactBytes)
        #expect(secondCase.memoryChanges[0] == 1)

        // The rendered comments spell the discriminator bytes out.
        let strategyComment = await renderer.enumPrefixComments(enumLayout: enumLayout).string
        #expect(strategyComment.contains("Single Payload"), "got: \(strategyComment)")

        let records = try #require(try? type.contextDescriptorWrapper.typeContextDescriptor?.fieldDescriptor(in: machOImage).records(in: machOImage))
        let firstCaseComment = try await renderer.enumCaseComments(
            forCaseAtIndex: 1,
            mangledTypeName: records[1].mangledTypeName(in: machOImage),
            enumLayout: enumLayout
        ).string
        #expect(firstCaseComment.contains("`first`"), "got: \(firstCaseComment)")
        #expect(firstCaseComment.contains("bytes[0x0..<0x8] = 0x0"), "got: \(firstCaseComment)")

        let secondCaseComment = try await renderer.enumCaseComments(
            forCaseAtIndex: 2,
            mangledTypeName: records[2].mangledTypeName(in: machOImage),
            enumLayout: enumLayout
        ).string
        #expect(secondCaseComment.contains("bytes[0x0..<0x8] = 0x1"), "got: \(secondCaseComment)")
    }

    @MainActor
    @Test func rendersDistinctPatternsForStringPayloadEmptyCases() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        let type = try #require(try findFixtureEnum(named: "SinglePayloadEnumTest"))
        let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
        let enumLayout = try #require(await renderer.enumLayout)

        // value(String) + none + error: the `String` extra-inhabitant patterns
        // are `_StringObject` discriminator details no formula predicts — both
        // empty cases must still resolve to exact, distinct, nonempty patterns.
        #expect(enumLayout.cases.count == 3)
        let emptyCases = enumLayout.cases.dropFirst()
        for emptyCase in emptyCases {
            #expect(emptyCase.patternResolution == .exactBytes, "\(emptyCase.caseName) should resolve exactly")
            #expect(!emptyCase.memoryChanges.isEmpty, "\(emptyCase.caseName) should have a concrete pattern")
        }
        #expect(enumLayout.cases[1].memoryChanges != enumLayout.cases[2].memoryChanges, "the two empty cases must be distinguishable")
    }
}
