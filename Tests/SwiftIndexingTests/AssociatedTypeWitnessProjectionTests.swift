import Foundation
import Testing
import SwiftDeclaration
import SwiftDeclarationRendering

/// The frozen witness projection's persistence contract: candidates round
/// trip, and a projection persisted before `conditionalCandidates` existed
/// still decodes (the key is optional on the way in).
@Suite
struct AssociatedTypeWitnessProjectionTests {
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    @Test func roundTripsConditionalCandidates() throws {
        let satisfied = PlatformAvailabilityCondition(platform: 1, major: 26, minor: 0, patch: 0, isSatisfiedBranch: true)
        let notSatisfied = PlatformAvailabilityCondition(platform: 1, major: 26, minor: 0, patch: 0, isSatisfiedBranch: false)
        let projection = AssociatedTypeWitnessProjection(
            name: "Body",
            substitutedTypeText: "M.Box<M.Static>",
            conditionalCandidates: [
                ConditionalWitnessCandidate(availability: satisfied, candidateTypeText: "M.Static", substitutedTypeText: "M.Box<M.Static>"),
                ConditionalWitnessCandidate(availability: notSatisfied, candidateTypeText: "M.Dynamic", substitutedTypeText: "M.Box<M.Dynamic>"),
            ]
        )
        let data = try encoder().encode(projection)
        let decoded = try JSONDecoder().decode(AssociatedTypeWitnessProjection.self, from: data)
        #expect(decoded == projection)
    }

    @Test func decodesAProjectionPersistedWithoutCandidates() throws {
        let legacy = Data(#"{"name":"Element","substitutedTypeText":"Swift.Int"}"#.utf8)
        let decoded = try JSONDecoder().decode(AssociatedTypeWitnessProjection.self, from: legacy)
        #expect(decoded == AssociatedTypeWitnessProjection(name: "Element", substitutedTypeText: "Swift.Int"))
        #expect(decoded.conditionalCandidates.isEmpty)
    }

    /// An unconditional answer (a thunk with no version check) carries no
    /// availability, and that absence survives the round trip as `nil`
    /// rather than decoding as a zero version.
    @Test func roundTripsAnUnconditionalCandidate() throws {
        let projection = AssociatedTypeWitnessProjection(
            name: "Body",
            substitutedTypeText: "M.Static",
            conditionalCandidates: [ConditionalWitnessCandidate(availability: nil, candidateTypeText: "M.Static", substitutedTypeText: "M.Static")]
        )
        let decoded = try JSONDecoder().decode(AssociatedTypeWitnessProjection.self, from: try encoder().encode(projection))
        #expect(decoded == projection)
        #expect(decoded.conditionalCandidates.first?.availability == nil)
    }
}
