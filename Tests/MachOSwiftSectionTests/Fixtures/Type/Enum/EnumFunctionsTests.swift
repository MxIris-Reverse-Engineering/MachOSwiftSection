import Foundation
import Testing
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `EnumFunctions.swift`.
///
/// `EnumFunctions.swift` declares the value type `EnumTagCounts` (with two
/// public stored ivars `numTags`/`numTagBytes`) and one top-level helper
/// function `getEnumTagCounts(payloadSize:emptyCases:payloadCases:)`.
///
/// `PublicMemberScanner` cannot key top-level free functions, so the
/// registered set captures only `EnumTagCounts.numTags` and
/// `EnumTagCounts.numTagBytes`. The ivar tests re-evaluate `getEnumTagCounts`
/// against deterministic inputs and compare against the literal baseline
/// — there is no MachO dependency here.
@Suite
@FixtureSuite(testedTypeName: "EnumTagCounts")
final class EnumFunctionsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func numTags() async throws {
        for entry in EnumFunctionsBaseline.cases {
            let result = getEnumTagCounts(
                payloadSize: entry.payloadSize,
                emptyCases: entry.emptyCases,
                payloadCases: entry.payloadCases
            )
            #expect(result.numTags == entry.numTags, "numTags mismatch for input (payloadSize: \(entry.payloadSize), emptyCases: \(entry.emptyCases), payloadCases: \(entry.payloadCases))")
        }
    }

    @Test func numTagBytes() async throws {
        for entry in EnumFunctionsBaseline.cases {
            let result = getEnumTagCounts(
                payloadSize: entry.payloadSize,
                emptyCases: entry.emptyCases,
                payloadCases: entry.payloadCases
            )
            #expect(result.numTagBytes == entry.numTagBytes, "numTagBytes mismatch for input (payloadSize: \(entry.payloadSize), emptyCases: \(entry.emptyCases), payloadCases: \(entry.payloadCases))")
        }
    }
}
