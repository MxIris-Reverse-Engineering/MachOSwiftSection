import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

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
@FixtureSuite(testedTypeName: "InvertedProtocols")
final class GenericRequirementContentTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadInvertedProtocols() throws -> (file: GenericRequirementContent.InvertedProtocols, image: GenericRequirementContent.InvertedProtocols) {
        let fileDescriptor = try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: machOImage)
        let fileGenericContext = try required(try fileDescriptor.typeGenericContext(in: fileContext))
        let imageGenericContext = try required(try imageDescriptor.typeGenericContext(in: imageContext))
        let fileValue = try requireInvertedProtocols(in: fileGenericContext)
        let imageValue = try requireInvertedProtocols(in: imageGenericContext)
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
        let result = try acrossAllReaders(payloads.file, payloads.image) { $0.genericParamIndex }
        #expect(result == GenericRequirementContentBaseline.invertibleProtocolRequirement.genericParamIndex)
    }

    @Test func protocols() async throws {
        let payloads = try loadInvertedProtocols()
        let result = try acrossAllReaders(payloads.file, payloads.image) { $0.protocols.rawValue }
        #expect(result == GenericRequirementContentBaseline.invertibleProtocolRequirement.protocolsRawValue)
    }
}
