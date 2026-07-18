import Foundation
import Testing
@testable import SwiftInspection

// MARK: - Test Enums
//
// Each enum is projected through `RuntimeEnumCaseProjector` (which drives the
// enum's own value witnesses) and the projected patterns are compared against
// the actual bytes of real case values — the ground truth the compiler itself
// materializes.

/// A class reference: its extra inhabitants are the small invalid addresses
/// (`0x0, 0x1, 0x2, …` on 64-bit Darwin).
private final class ProjectorBoxClass {
    var storedValue: Int = 0
}

/// The `SwiftUI.Text.Style.LineStyle` shape that motivated the projector: a
/// struct payload whose extra inhabitants come from an `Optional` class
/// reference at a nonzero offset. `Optional`'s `nil` consumes extra
/// inhabitant #0 (the null pointer), so the enum's empty cases land on the
/// pointer values `1` and `2` at offset 8 — bytes no formula over the
/// extra-inhabitant *count* can produce.
private struct ProjectorStructPayload {
    var rawValue: Int
    var box: ProjectorBoxClass?
}

private enum ProjectorSinglePayloadOverStruct {
    case wrapped(ProjectorStructPayload)
    case first
    case second
}

/// A non-optional class-reference payload: extra inhabitant #0 is the null
/// pointer itself, so the first empty case's pattern is *all zero bytes* — a
/// pattern that must still be reported explicitly (zero is a fixed byte here,
/// not "nothing written").
private enum ProjectorSinglePayloadOverReference {
    case wrapped(ProjectorBoxClass)
    case first
    case second
}

/// A `Bool` payload: sub-byte extra inhabitants (values 2...255 of the single
/// byte).
private enum ProjectorSinglePayloadOverBool {
    case flag(Bool)
    case first
    case second
}

/// An `Optional<UInt8>` payload has zero extra inhabitants, so the empty case
/// overflows into an appended extra tag byte.
private enum ProjectorSinglePayloadOverflow {
    case value(UInt8?)
    case overflowed
}

// MARK: - Tests

@Suite("RuntimeEnumCaseProjector", .enabled(if: MemoryLayout<UnsafeRawPointer>.size == 8))
struct RuntimeEnumCaseProjectorTests {
    private func projectedPatterns(
        of enumType: Any.Type,
        payloadCaseCount: Int,
        caseCount: Int
    ) throws -> [RuntimeEnumCaseProjector.CasePattern] {
        let enumMetadataPointer = unsafeBitCast(enumType, to: UnsafeRawPointer.self)
        return try #require(
            RuntimeEnumCaseProjector.projectCasePatterns(
                enumMetadataPointer: enumMetadataPointer,
                payloadCaseCount: payloadCaseCount,
                caseCount: caseCount
            )
        )
    }

    private func actualBytes<EnumValue>(of value: EnumValue) -> [UInt8] {
        withUnsafeBytes(of: value) { Array($0) }
    }

    /// Every projected fixed byte must equal the corresponding byte of the
    /// actual case value the compiler materializes.
    private func expectPatternMatches<EnumValue>(
        _ pattern: RuntimeEnumCaseProjector.CasePattern,
        actualValue: EnumValue,
        label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let valueBytes = actualBytes(of: actualValue)
        for (byteOffset, fixedByte) in pattern.fixedBytes {
            guard byteOffset < valueBytes.count else {
                Issue.record("\(label): fixed byte offset \(byteOffset) out of bounds", sourceLocation: sourceLocation)
                continue
            }
            #expect(
                valueBytes[byteOffset] == fixedByte,
                "\(label): byte at offset \(byteOffset) expected \(String(format: "0x%02X", fixedByte)), actual value holds \(String(format: "0x%02X", valueBytes[byteOffset]))",
                sourceLocation: sourceLocation
            )
        }
    }

    @Test("Struct payload with Optional class reference (the Text.Style.LineStyle shape)")
    func structPayloadWithOptionalReference() throws {
        let patterns = try projectedPatterns(of: ProjectorSinglePayloadOverStruct.self, payloadCaseCount: 1, caseCount: 3)
        #expect(patterns.count == 3)

        // Payload case: single-payload with enough extra inhabitants appends
        // no tag bytes, so the payload case writes nothing.
        #expect(patterns[0].fixedBytes.isEmpty, "payload case has no fixed bytes")

        // Empty cases: `Optional`'s nil consumed extra inhabitant #0 (null),
        // so the empty cases occupy pointer values 1 and 2 at the Optional's
        // offset 8.
        expectPatternMatches(patterns[1], actualValue: ProjectorSinglePayloadOverStruct.first, label: "first")
        expectPatternMatches(patterns[2], actualValue: ProjectorSinglePayloadOverStruct.second, label: "second")

        let firstWord = actualBytes(of: ProjectorSinglePayloadOverStruct.first)[8 ..< 16]
        let secondWord = actualBytes(of: ProjectorSinglePayloadOverStruct.second)[8 ..< 16]
        #expect(Array(firstWord) == [1, 0, 0, 0, 0, 0, 0, 0], "first is pointer value 1 at offset 8")
        #expect(Array(secondWord) == [2, 0, 0, 0, 0, 0, 0, 0], "second is pointer value 2 at offset 8")
        #expect(patterns[1].fixedBytes[8] == 1)
        #expect(patterns[2].fixedBytes[8] == 2)
    }

    @Test("Non-optional class-reference payload: the all-zero pattern is reported explicitly")
    func referencePayloadAllZeroPattern() throws {
        let patterns = try projectedPatterns(of: ProjectorSinglePayloadOverReference.self, payloadCaseCount: 1, caseCount: 3)
        #expect(patterns.count == 3)

        expectPatternMatches(patterns[1], actualValue: ProjectorSinglePayloadOverReference.first, label: "first")
        expectPatternMatches(patterns[2], actualValue: ProjectorSinglePayloadOverReference.second, label: "second")

        // Extra inhabitant #0 of a non-optional reference is the null pointer:
        // all zero bytes — and the projector must report those zero bytes as
        // the case's fixed pattern rather than an empty dictionary.
        #expect(!patterns[1].fixedBytes.isEmpty, "the all-zero pattern is still a fixed pattern")
        #expect(patterns[1].fixedBytes.values.allSatisfy { $0 == 0 })
        #expect(patterns[2].fixedBytes[0] == 1)
    }

    @Test("Bool payload: sub-byte extra-inhabitant patterns")
    func boolPayloadSubBytePatterns() throws {
        let patterns = try projectedPatterns(of: ProjectorSinglePayloadOverBool.self, payloadCaseCount: 1, caseCount: 3)
        #expect(patterns.count == 3)

        expectPatternMatches(patterns[1], actualValue: ProjectorSinglePayloadOverBool.first, label: "first")
        expectPatternMatches(patterns[2], actualValue: ProjectorSinglePayloadOverBool.second, label: "second")

        // Bool occupies bit 0; its extra inhabitants are the byte values 2...255.
        #expect(patterns[1].fixedBytes[0] == 2)
        #expect(patterns[2].fixedBytes[0] == 3)
    }

    @Test("Zero-extra-inhabitant payload overflows into an extra tag byte")
    func overflowPayloadTagByte() throws {
        let patterns = try projectedPatterns(of: ProjectorSinglePayloadOverflow.self, payloadCaseCount: 1, caseCount: 2)
        #expect(patterns.count == 2)

        // The payload case zeroes the appended tag byte — that zero is part of
        // its pattern.
        #expect(patterns[0].fixedBytes[2] == 0, "payload case zeroes the extra tag byte")

        expectPatternMatches(patterns[1], actualValue: ProjectorSinglePayloadOverflow.overflowed, label: "overflowed")
        #expect(patterns[1].fixedBytes[2] == 1, "overflow case sets the extra tag byte")
    }

    @Test("Empty-case patterns round-trip through the calculator overlay")
    func calculatorOverlayCarriesExactPatterns() throws {
        let patterns = try projectedPatterns(of: ProjectorSinglePayloadOverStruct.self, payloadCaseCount: 1, caseCount: 3)
        let formulaResult = EnumLayoutCalculator.calculateSinglePayload(
            size: MemoryLayout<ProjectorSinglePayloadOverStruct>.size,
            payloadSize: MemoryLayout<ProjectorStructPayload>.size,
            numEmptyCases: 2,
            numExtraInhabitants: 2
        )

        // Before the overlay the formula honestly reports the patterns as
        // unresolved (it knows the count, not the bytes).
        for emptyCase in formulaResult.cases.dropFirst() {
            #expect(emptyCase.patternResolution == .unresolvedExtraInhabitant(extraInhabitantIndex: emptyCase.caseIndex - 1))
        }

        let overlaid = formulaResult.applyingExactCasePatterns(
            Dictionary(uniqueKeysWithValues: patterns.map { ($0.caseIndex, $0.fixedBytes) })
        )
        for (overlaidCase, pattern) in zip(overlaid.cases, patterns) {
            #expect(overlaidCase.patternResolution == .exactBytes)
            #expect(overlaidCase.memoryChanges == pattern.fixedBytes)
        }

        // The rendered description now names the exact discriminator bytes.
        let named = overlaid.attachingDeclaredCaseNames(["wrapped", "first", "second"])
        let firstCaseDescription = named.cases[1].description
        #expect(firstCaseDescription.contains("`first`"))
        #expect(firstCaseDescription.contains("bytes[0x8..<0x10] = 0x1"), "got: \(firstCaseDescription)")
    }
}
