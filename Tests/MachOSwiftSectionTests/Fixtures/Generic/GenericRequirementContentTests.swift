import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `GenericRequirementContent.InvertedProtocols`.
///
/// `GenericRequirementContent.swift` declares two enums
/// (`GenericRequirementContent`, `ResolvedGenericRequirementContent`) plus
/// a nested struct `InvertedProtocols`. The `@CaseCheckable(.public)` /
/// `@AssociatedValue(.public)` macros generate case-presence helpers and
/// extractors but those are macro-injected and not visited by
/// `PublicMemberScanner`. The scanner sees only the nested
/// `InvertedProtocols` struct's stored properties.
///
/// `testedTypeName` is therefore `InvertedProtocols` (the source-level
/// nested struct name); the Suite asserts cross-reader equality on the
/// payload from the fixture's
/// `InvertibleProtocolRequirementTest<Element: ~Copyable>: ~Copyable`
/// generic struct, which surfaces a `.invertedProtocols` requirement.
@Suite
final class GenericRequirementContentTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "InvertedProtocols"
    static var registeredTestMethodNames: Set<String> {
        GenericRequirementContentBaseline.registeredTestMethodNames
    }

    private func loadInvertedProtocols() throws -> (file: GenericRequirementContent.InvertedProtocols, image: GenericRequirementContent.InvertedProtocols) {
        let fileDescriptor = try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileValue = try requireInvertedProtocols(in: fileContext)
        let imageValue = try requireInvertedProtocols(in: imageContext)
        return (file: fileValue, image: imageValue)
    }

    private func requireInvertedProtocols(in context: TypeGenericContext) throws -> GenericRequirementContent.InvertedProtocols {
        let candidates =
            context.conditionalInvertibleProtocolsRequirements
            + context.requirements
        for requirement in candidates {
            if case .invertedProtocols(let payload) = requirement.content {
                return payload
            }
        }
        throw RequiredError.requiredNonOptional
    }

    @Test func genericParamIndex() async throws {
        let payloads = try loadInvertedProtocols()
        let result = try acrossAllReaders(
            file: { payloads.file.genericParamIndex },
            image: { payloads.image.genericParamIndex }
        )
        #expect(result == GenericRequirementContentBaseline.invertibleProtocolRequirement.genericParamIndex)
    }

    @Test func protocols() async throws {
        let payloads = try loadInvertedProtocols()
        let result = try acrossAllReaders(
            file: { payloads.file.protocols.rawValue },
            image: { payloads.image.protocols.rawValue }
        )
        #expect(result == GenericRequirementContentBaseline.invertibleProtocolRequirement.protocolsRawValue)
    }
}
