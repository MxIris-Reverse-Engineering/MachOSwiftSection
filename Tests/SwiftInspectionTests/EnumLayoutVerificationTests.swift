import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInspection

// MARK: - Test Enum Definitions

// --- Strategy 1: Multi-Payload Spare Bits (class references have spare bits on arm64) ---

final class VerificationRef1 { var x: Int = 0 }
final class VerificationRef2 { var y: Int = 0 }
final class VerificationRef3 { var z: Int = 0 }

enum MP_Ref_2P_0E { case a(VerificationRef1); case b(VerificationRef2) }
enum MP_Ref_2P_3E { case a(VerificationRef1); case b(VerificationRef2); case e0; case e1; case e2 }
enum MP_Ref_3P_0E { case a(VerificationRef1); case b(VerificationRef2); case c(VerificationRef3) }
enum MP_Ref_3P_5E {
    case a(VerificationRef1); case b(VerificationRef2); case c(VerificationRef3)
    case e0; case e1; case e2; case e3; case e4
}

// --- Strategy 2: Tagged Multi-Payload (integer payloads, no spare bits) ---

enum TMP_U8_2P_0E { case a(UInt8); case b(UInt8) }
enum TMP_U8_2P_3E { case a(UInt8); case b(UInt8); case e0; case e1; case e2 }
enum TMP_U8_3P_1E { case a(UInt8); case b(UInt8); case c(UInt8); case e0 }
enum TMP_U8_4P_0E { case a(UInt8); case b(UInt8); case c(UInt8); case d(UInt8) }
enum TMP_U16_2P_2E { case a(UInt16); case b(UInt16); case e0; case e1 }
enum TMP_U16_3P_0E { case a(UInt16); case b(UInt16); case c(UInt16) }
enum TMP_U32_2P_1E { case a(UInt32); case b(UInt32); case e0 }
enum TMP_U32_3P_5E {
    case a(UInt32); case b(UInt32); case c(UInt32)
    case e0; case e1; case e2; case e3; case e4
}
enum TMP_U64_2P_3E { case a(UInt64); case b(UInt64); case e0; case e1; case e2 }
enum TMP_U64_3P_0E { case a(UInt64); case b(UInt64); case c(UInt64) }

// --- Strategy 3: Single Payload - Overflow (0 XI types) ---

enum SP_U8_1E { case payload(UInt8); case e0 }
enum SP_U8_3E { case payload(UInt8); case e0; case e1; case e2 }
enum SP_U16_1E { case payload(UInt16); case e0 }
enum SP_U16_3E { case payload(UInt16); case e0; case e1; case e2 }
enum SP_U32_1E { case payload(UInt32); case e0 }
enum SP_U32_5E { case payload(UInt32); case e0; case e1; case e2; case e3; case e4 }
enum SP_U64_1E { case payload(UInt64); case e0 }
enum SP_U64_3E { case payload(UInt64); case e0; case e1; case e2 }

// --- Strategy 3: Single Payload - Extra Inhabitants (XI) ---

// Bool: 1 byte, 254 XI (values 2..255 are extra inhabitants)
enum SP_Bool_1E { case payload(Bool); case e0 }
enum SP_Bool_3E { case payload(Bool); case e0; case e1; case e2 }
// Optional<UInt8>: 2 bytes, 254 XI
enum SP_OptU8_1E { case payload(UInt8?); case e0 }
enum SP_OptU8_3E { case payload(UInt8?); case e0; case e1; case e2 }
// Class reference: 8 bytes, many XI
enum SP_Ref_2E { case payload(VerificationRef1); case e0; case e1 }

// MARK: - Helpers

private func readBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}

private typealias Calculator = EnumLayoutCalculator

/// Locate the MultiPayloadEnumDescriptor for a given type name substring in the test binary.
private func findMultiPayloadDescriptor(
    typeName needle: String,
    in machO: MachOImage
) throws -> (spareBytes: [UInt8], spareBytesOffset: Int, usesSpare: Bool)? {
    for descriptor in try machO.swift.multiPayloadEnumDescriptors {
        let inProcess = descriptor.asPointerWrapper(in: machO)
        let mangledName = try inProcess.mangledTypeName()
        let name = try MetadataReader.demangleType(for: mangledName).print(using: .default)
        if name.contains(needle) {
            if inProcess.usesPayloadSpareBits {
                let spareBytes = try inProcess.payloadSpareBits()
                let offset = Int(try inProcess.payloadSpareBitMaskByteOffset())
                return (spareBytes, offset, true)
            }
            return ([], 0, false)
        }
    }
    return nil
}

// MARK: - Tests

@Suite("EnumLayoutCalculator Verification")
struct EnumLayoutVerificationTests {

    // MARK: - Strategy 2: Tagged Multi-Payload

    @Test("TMP_U8_2P_0E: 2 UInt8 payloads, 0 empty")
    func taggedMultiPayload_U8_2P_0E() {
        let payloadSize = MemoryLayout<UInt8>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 2, numEmptyCases: 0
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_0E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_0E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyTagBytes(bytes: readBytes(TMP_U8_2P_0E.a(42)), projection: result.cases[0], payloadSize: payloadSize, label: "a(42)")
        verifyTagBytes(bytes: readBytes(TMP_U8_2P_0E.b(0xFF)), projection: result.cases[1], payloadSize: payloadSize, label: "b(0xFF)")
    }

    @Test("TMP_U8_2P_3E: 2 UInt8 payloads, 3 empty (small payload branch)")
    func taggedMultiPayload_U8_2P_3E() {
        let payloadSize = MemoryLayout<UInt8>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 2, numEmptyCases: 3
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_3E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_3E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_3E.e0), projection: result.cases[2], label: "e0")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_3E.e1), projection: result.cases[3], label: "e1")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_2P_3E.e2), projection: result.cases[4], label: "e2")
    }

    @Test("TMP_U8_3P_1E: 3 UInt8 payloads, 1 empty")
    func taggedMultiPayload_U8_3P_1E() {
        let payloadSize = MemoryLayout<UInt8>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 3, numEmptyCases: 1
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_3P_1E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_3P_1E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_3P_1E.c(0)), projection: result.cases[2], label: "c(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_3P_1E.e0), projection: result.cases[3], label: "e0")
        verifyTagBytes(bytes: readBytes(TMP_U8_3P_1E.a(7)), projection: result.cases[0], payloadSize: payloadSize, label: "a(7)")
        verifyTagBytes(bytes: readBytes(TMP_U8_3P_1E.c(200)), projection: result.cases[2], payloadSize: payloadSize, label: "c(200)")
    }

    @Test("TMP_U8_4P_0E: 4 UInt8 payloads, 0 empty (pure payload)")
    func taggedMultiPayload_U8_4P_0E() {
        let payloadSize = MemoryLayout<UInt8>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 4, numEmptyCases: 0
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_4P_0E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_4P_0E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_4P_0E.c(0)), projection: result.cases[2], label: "c(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U8_4P_0E.d(0)), projection: result.cases[3], label: "d(0)")
        verifyTagBytes(bytes: readBytes(TMP_U8_4P_0E.d(128)), projection: result.cases[3], payloadSize: payloadSize, label: "d(128)")
    }

    @Test("TMP_U16_2P_2E: 2 UInt16 payloads, 2 empty (2-byte payload, <4 branch)")
    func taggedMultiPayload_U16_2P_2E() {
        let payloadSize = MemoryLayout<UInt16>.size // 2
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 2, numEmptyCases: 2
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_2P_2E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_2P_2E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_2P_2E.e0), projection: result.cases[2], label: "e0")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_2P_2E.e1), projection: result.cases[3], label: "e1")
        verifyTagBytes(bytes: readBytes(TMP_U16_2P_2E.a(0x1234)), projection: result.cases[0], payloadSize: payloadSize, label: "a(0x1234)")
    }

    @Test("TMP_U16_3P_0E: 3 UInt16 payloads, 0 empty")
    func taggedMultiPayload_U16_3P_0E() {
        let payloadSize = MemoryLayout<UInt16>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 3, numEmptyCases: 0
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_3P_0E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_3P_0E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U16_3P_0E.c(0)), projection: result.cases[2], label: "c(0)")
        verifyTagBytes(bytes: readBytes(TMP_U16_3P_0E.b(0xABCD)), projection: result.cases[1], payloadSize: payloadSize, label: "b(0xABCD)")
    }

    @Test("TMP_U32_2P_1E: 2 UInt32 payloads, 1 empty (large payload branch)")
    func taggedMultiPayload_U32_2P_1E() {
        let payloadSize = MemoryLayout<UInt32>.size // 4
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 2, numEmptyCases: 1
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_2P_1E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_2P_1E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_2P_1E.e0), projection: result.cases[2], label: "e0")
        verifyTagBytes(bytes: readBytes(TMP_U32_2P_1E.a(1000)), projection: result.cases[0], payloadSize: payloadSize, label: "a(1000)")
    }

    @Test("TMP_U32_3P_5E: 3 UInt32 payloads, 5 empty")
    func taggedMultiPayload_U32_3P_5E() {
        let payloadSize = MemoryLayout<UInt32>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 3, numEmptyCases: 5
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_3P_5E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_3P_5E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U32_3P_5E.c(0)), projection: result.cases[2], label: "c(0)")

        let emptyCases: [TMP_U32_3P_5E] = [.e0, .e1, .e2, .e3, .e4]
        for (i, emptyCase) in emptyCases.enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(emptyCase), projection: result.cases[3 + i], label: "e\(i)")
        }
    }

    @Test("TMP_U64_2P_3E: 2 UInt64 payloads, 3 empty (8-byte payload, >=4 branch)")
    func taggedMultiPayload_U64_2P_3E() {
        let payloadSize = MemoryLayout<UInt64>.size // 8
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 2, numEmptyCases: 3
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_2P_3E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_2P_3E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_2P_3E.e0), projection: result.cases[2], label: "e0")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_2P_3E.e1), projection: result.cases[3], label: "e1")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_2P_3E.e2), projection: result.cases[4], label: "e2")
        verifyTagBytes(bytes: readBytes(TMP_U64_2P_3E.a(0xDEAD_BEEF)), projection: result.cases[0], payloadSize: payloadSize, label: "a(0xDEADBEEF)")
        verifyTagBytes(bytes: readBytes(TMP_U64_2P_3E.b(UInt64.max)), projection: result.cases[1], payloadSize: payloadSize, label: "b(max)")
    }

    @Test("TMP_U64_3P_0E: 3 UInt64 payloads, 0 empty")
    func taggedMultiPayload_U64_3P_0E() {
        let payloadSize = MemoryLayout<UInt64>.size
        let result = Calculator.calculateTaggedMultiPayload(
            payloadSize: payloadSize, numPayloadCases: 3, numEmptyCases: 0
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_3P_0E.a(0)), projection: result.cases[0], label: "a(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_3P_0E.b(0)), projection: result.cases[1], label: "b(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(TMP_U64_3P_0E.c(0)), projection: result.cases[2], label: "c(0)")
        verifyTagBytes(bytes: readBytes(TMP_U64_3P_0E.c(42)), projection: result.cases[2], payloadSize: payloadSize, label: "c(42)")
    }

    // MARK: - Strategy 3: Single Payload (Overflow, 0 XI)

    @Test("SP_U8_1E: UInt8 payload, 1 empty (small overflow)")
    func singlePayload_U8_1E() throws {
        let enumSize = MemoryLayout<SP_U8_1E>.size
        let payloadSize = MemoryLayout<UInt8>.size
        let xi = try Int(Metadata.createInProcess(SP_U8_1E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U8_1E.payload(0)), projection: result.cases[0], label: "payload(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U8_1E.e0), projection: result.cases[1], label: "e0")
    }

    @Test("SP_U8_3E: UInt8 payload, 3 empty (multiple overflow, small payload)")
    func singlePayload_U8_3E() throws {
        let enumSize = MemoryLayout<SP_U8_3E>.size
        let payloadSize = MemoryLayout<UInt8>.size
        let xi = try Int(Metadata.createInProcess(SP_U8_3E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 3, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U8_3E.payload(0)), projection: result.cases[0], label: "payload(0)")
        for (i, e) in ([SP_U8_3E.e0, .e1, .e2] as [SP_U8_3E]).enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(e), projection: result.cases[1 + i], label: "e\(i)")
        }
    }

    @Test("SP_U16_1E: UInt16 payload, 1 empty (2-byte payload, <4 branch)")
    func singlePayload_U16_1E() throws {
        let enumSize = MemoryLayout<SP_U16_1E>.size
        let payloadSize = MemoryLayout<UInt16>.size
        let xi = try Int(Metadata.createInProcess(SP_U16_1E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U16_1E.payload(0)), projection: result.cases[0], label: "payload(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U16_1E.e0), projection: result.cases[1], label: "e0")
    }

    @Test("SP_U16_3E: UInt16 payload, 3 empty (2-byte payload, multiple overflow)")
    func singlePayload_U16_3E() throws {
        let enumSize = MemoryLayout<SP_U16_3E>.size
        let payloadSize = MemoryLayout<UInt16>.size
        let xi = try Int(Metadata.createInProcess(SP_U16_3E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 3, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U16_3E.payload(0)), projection: result.cases[0], label: "payload(0)")
        for (i, e) in ([SP_U16_3E.e0, .e1, .e2] as [SP_U16_3E]).enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(e), projection: result.cases[1 + i], label: "e\(i)")
        }
    }

    @Test("SP_U32_1E: UInt32 payload, 1 empty (large payload, single tag)")
    func singlePayload_U32_1E() throws {
        let enumSize = MemoryLayout<SP_U32_1E>.size
        let payloadSize = MemoryLayout<UInt32>.size
        let xi = try Int(Metadata.createInProcess(SP_U32_1E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U32_1E.payload(0)), projection: result.cases[0], label: "payload(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U32_1E.e0), projection: result.cases[1], label: "e0")
    }

    @Test("SP_U32_5E: UInt32 payload, 5 empty (large payload, multiple overflow)")
    func singlePayload_U32_5E() throws {
        let enumSize = MemoryLayout<SP_U32_5E>.size
        let payloadSize = MemoryLayout<UInt32>.size
        let xi = try Int(Metadata.createInProcess(SP_U32_5E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 5, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U32_5E.payload(0)), projection: result.cases[0], label: "payload(0)")
        for (i, e) in ([SP_U32_5E.e0, .e1, .e2, .e3, .e4] as [SP_U32_5E]).enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(e), projection: result.cases[1 + i], label: "e\(i)")
        }
    }

    @Test("SP_U64_1E: UInt64 payload, 1 empty (8-byte payload)")
    func singlePayload_U64_1E() throws {
        let enumSize = MemoryLayout<SP_U64_1E>.size
        let payloadSize = MemoryLayout<UInt64>.size
        let xi = try Int(Metadata.createInProcess(SP_U64_1E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U64_1E.payload(0)), projection: result.cases[0], label: "payload(0)")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U64_1E.e0), projection: result.cases[1], label: "e0")
    }

    @Test("SP_U64_3E: UInt64 payload, 3 empty (8-byte payload, multiple overflow)")
    func singlePayload_U64_3E() throws {
        let enumSize = MemoryLayout<SP_U64_3E>.size
        let payloadSize = MemoryLayout<UInt64>.size
        let xi = try Int(Metadata.createInProcess(SP_U64_3E.self).typeLayout().extraInhabitantCount)

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 3, numExtraInhabitants: xi
        )

        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_U64_3E.payload(0)), projection: result.cases[0], label: "payload(0)")
        for (i, e) in ([SP_U64_3E.e0, .e1, .e2] as [SP_U64_3E]).enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(e), projection: result.cases[1 + i], label: "e\(i)")
        }
    }

    // MARK: - Strategy 3: Single Payload (Extra Inhabitants)

    // Bool has 254 XI; empty cases fit within XI so no overflow tag bytes needed.
    // The Calculator produces XI cases with tagValue=0 and overflow cases with tagValue>=1.
    // We verify structural properties and that the enum size equals the payload size
    // (confirming no extra tag bytes were appended).

    @Test("SP_Bool_1E: Bool payload, 1 empty (pure XI, no overflow)")
    func singlePayload_Bool_1E() throws {
        let enumSize = MemoryLayout<SP_Bool_1E>.size
        let payloadSize = MemoryLayout<Bool>.size
        let xi = try Int(Metadata.createInProcess(SP_Bool_1E.self).typeLayout().extraInhabitantCount)

        // Bool has 254 XI; 1 empty case fits entirely within XI
        #expect(xi + 1 >= 1, "Bool should have enough XI for 1 empty case")
        #expect(enumSize == payloadSize, "No extra tag bytes needed when XI suffice")

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: xi
        )

        #expect(result.cases.count == 2, "Expected 1 payload + 1 empty case")

        // Payload case: all zero bytes
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_Bool_1E.payload(false)), projection: result.cases[0], label: "payload(false)")

        // XI case: tagValue should be 0 (XI encoding is within payload area)
        #expect(result.cases[1].tagValue == 0, "XI case should have tagValue=0")
    }

    @Test("SP_Bool_3E: Bool payload, 3 empty (pure XI)")
    func singlePayload_Bool_3E() throws {
        let enumSize = MemoryLayout<SP_Bool_3E>.size
        let payloadSize = MemoryLayout<Bool>.size
        let xi = try Int(Metadata.createInProcess(SP_Bool_3E.self).typeLayout().extraInhabitantCount)

        #expect(xi + 1 >= 3, "Bool should have enough XI for 3 empty cases")
        #expect(enumSize == payloadSize, "No extra tag bytes needed when XI suffice")

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 3, numExtraInhabitants: xi
        )

        #expect(result.cases.count == 4, "Expected 1 payload + 3 empty cases")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_Bool_3E.payload(false)), projection: result.cases[0], label: "payload(false)")

        // All 3 empty cases should be XI (tagValue=0), no overflow
        for i in 1 ... 3 {
            #expect(result.cases[i].tagValue == 0, "XI case \(i) should have tagValue=0")
        }
    }

    // Optional<UInt8> has 0 XI (all 257 bit patterns used: 256 Some + 1 None).
    // So SP_OptU8enums use overflow strategy, same as other 0-XI payload types.

    @Test("SP_OptU8_1E: Optional<UInt8> payload, 1 empty (overflow, 2-byte payload)")
    func singlePayload_OptU8_1E() throws {
        let enumSize = MemoryLayout<SP_OptU8_1E>.size
        let payloadSize = MemoryLayout<UInt8?>.size // 2
        let payloadXI = try Int(Metadata.createInProcess(UInt8?.self).typeLayout().extraInhabitantCount)

        #expect(payloadXI == 0, "Optional<UInt8> should have 0 XI")
        #expect(enumSize > payloadSize, "Overflow requires extra tag bytes")

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 1, numExtraInhabitants: payloadXI
        )

        #expect(result.cases.count == 2)
        // Use .some(0) as zero-valued payload (Optional.none has non-zero tag byte)
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_OptU8_1E.payload(.some(0))), projection: result.cases[0], label: "payload(.some(0))")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_OptU8_1E.e0), projection: result.cases[1], label: "e0")
    }

    @Test("SP_OptU8_3E: Optional<UInt8> payload, 3 empty (overflow, 2-byte payload)")
    func singlePayload_OptU8_3E() throws {
        let enumSize = MemoryLayout<SP_OptU8_3E>.size
        let payloadSize = MemoryLayout<UInt8?>.size // 2
        let payloadXI = try Int(Metadata.createInProcess(UInt8?.self).typeLayout().extraInhabitantCount)

        #expect(payloadXI == 0, "Optional<UInt8> should have 0 XI")

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 3, numExtraInhabitants: payloadXI
        )

        #expect(result.cases.count == 4)
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(SP_OptU8_3E.payload(.some(0))), projection: result.cases[0], label: "payload(.some(0))")
        for (i, e) in ([SP_OptU8_3E.e0, .e1, .e2] as [SP_OptU8_3E]).enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(e), projection: result.cases[1 + i], label: "e\(i)")
        }
    }

    @Test("SP_Ref_2E: class reference payload, 2 empty (XI from pointer)")
    func singlePayload_Ref_2E() throws {
        let enumSize = MemoryLayout<SP_Ref_2E>.size
        let payloadSize = MemoryLayout<VerificationRef1>.size
        let xi = try Int(Metadata.createInProcess(SP_Ref_2E.self).typeLayout().extraInhabitantCount)

        // Class references have many XI (null pointer + aligned invalid pointers)
        #expect(xi >= 2, "Class reference should have XI for 2 empty cases")
        #expect(enumSize == payloadSize, "No extra tag bytes when XI suffice")

        let result = Calculator.calculateSinglePayload(
            size: enumSize, payloadSize: payloadSize, numEmptyCases: 2, numExtraInhabitants: xi
        )

        #expect(result.cases.count == 3, "Expected 1 payload + 2 empty cases")
        for i in 1 ... 2 {
            #expect(result.cases[i].tagValue == 0, "XI case \(i) should have tagValue=0")
        }
    }

    // MARK: - Strategy 1: Multi-Payload Spare Bits

    @Test("MP_Ref_2P_0E: 2 class payloads, 0 empty (pure spare bits tag)")
    func multiPayloadSpareBits_Ref_2P_0E() throws {
        let ptr = unsafeBitCast(MP_Ref_2P_0E.self, to: UnsafeRawPointer.self)
        let machO = try #require(MachOImage.image(for: ptr))
        let info = try #require(try findMultiPayloadDescriptor(typeName: "MP_Ref_2P_0E", in: machO))
        try #require(info.usesSpare, "Expected spare bits strategy")

        let payloadSize = MemoryLayout<AnyObject>.size
        let result = Calculator.calculateMultiPayload(
            payloadSize: payloadSize, spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset,
            numPayloadCases: 2, numEmptyCases: 0
        )

        #expect(result.cases.count == 2, "Expected 2 payload cases only")

        // Payload case 0 (tag=0): spare bits should all be 0
        let bytes_a = readBytes(MP_Ref_2P_0E.a(VerificationRef1()))
        verifySpareBitsTag(bytes: bytes_a, projection: result.cases[0], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "a(Ref1)")

        let bytes_b = readBytes(MP_Ref_2P_0E.b(VerificationRef2()))
        verifySpareBitsTag(bytes: bytes_b, projection: result.cases[1], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "b(Ref2)")
    }

    @Test("MP_Ref_2P_3E: 2 class payloads, 3 empty (spare bits strategy)")
    func multiPayloadSpareBits_Ref_2P_3E() throws {
        let ptr = unsafeBitCast(MP_Ref_2P_3E.self, to: UnsafeRawPointer.self)
        let machO = try #require(MachOImage.image(for: ptr))
        let info = try #require(try findMultiPayloadDescriptor(typeName: "MP_Ref_2P_3E", in: machO))
        try #require(info.usesSpare, "Expected spare bits strategy")

        let payloadSize = MemoryLayout<AnyObject>.size
        let result = Calculator.calculateMultiPayload(
            payloadSize: payloadSize, spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset,
            numPayloadCases: 2, numEmptyCases: 3
        )

        // Payload cases: verify spare bits tag only
        let bytes_a = readBytes(MP_Ref_2P_3E.a(VerificationRef1()))
        verifySpareBitsTag(bytes: bytes_a, projection: result.cases[0], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "a(Ref1)")

        let bytes_b = readBytes(MP_Ref_2P_3E.b(VerificationRef2()))
        verifySpareBitsTag(bytes: bytes_b, projection: result.cases[1], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "b(Ref2)")

        // Empty cases: full byte comparison
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(MP_Ref_2P_3E.e0), projection: result.cases[2], label: "e0")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(MP_Ref_2P_3E.e1), projection: result.cases[3], label: "e1")
        verifyEmptyCaseOrZeroPayload(bytes: readBytes(MP_Ref_2P_3E.e2), projection: result.cases[4], label: "e2")
    }

    @Test("MP_Ref_3P_0E: 3 class payloads, 0 empty (3-way spare bits)")
    func multiPayloadSpareBits_Ref_3P_0E() throws {
        let ptr = unsafeBitCast(MP_Ref_3P_0E.self, to: UnsafeRawPointer.self)
        let machO = try #require(MachOImage.image(for: ptr))
        let info = try #require(try findMultiPayloadDescriptor(typeName: "MP_Ref_3P_0E", in: machO))
        try #require(info.usesSpare, "Expected spare bits strategy")

        let payloadSize = MemoryLayout<AnyObject>.size
        let result = Calculator.calculateMultiPayload(
            payloadSize: payloadSize, spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset,
            numPayloadCases: 3, numEmptyCases: 0
        )

        #expect(result.cases.count == 3, "Expected 3 payload cases only")

        let bytes_a = readBytes(MP_Ref_3P_0E.a(VerificationRef1()))
        verifySpareBitsTag(bytes: bytes_a, projection: result.cases[0], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "a(Ref1)")

        let bytes_b = readBytes(MP_Ref_3P_0E.b(VerificationRef2()))
        verifySpareBitsTag(bytes: bytes_b, projection: result.cases[1], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "b(Ref2)")

        let bytes_c = readBytes(MP_Ref_3P_0E.c(VerificationRef3()))
        verifySpareBitsTag(bytes: bytes_c, projection: result.cases[2], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "c(Ref3)")
    }

    @Test("MP_Ref_3P_5E: 3 class payloads, 5 empty (3-way spare bits + empty)")
    func multiPayloadSpareBits_Ref_3P_5E() throws {
        let ptr = unsafeBitCast(MP_Ref_3P_5E.self, to: UnsafeRawPointer.self)
        let machO = try #require(MachOImage.image(for: ptr))
        let info = try #require(try findMultiPayloadDescriptor(typeName: "MP_Ref_3P_5E", in: machO))
        try #require(info.usesSpare, "Expected spare bits strategy")

        let payloadSize = MemoryLayout<AnyObject>.size
        let result = Calculator.calculateMultiPayload(
            payloadSize: payloadSize, spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset,
            numPayloadCases: 3, numEmptyCases: 5
        )

        #expect(result.cases.count == 8, "Expected 3 payload + 5 empty cases")

        // Payload cases: verify spare bits tag
        let bytes_a = readBytes(MP_Ref_3P_5E.a(VerificationRef1()))
        verifySpareBitsTag(bytes: bytes_a, projection: result.cases[0], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "a(Ref1)")

        let bytes_b = readBytes(MP_Ref_3P_5E.b(VerificationRef2()))
        verifySpareBitsTag(bytes: bytes_b, projection: result.cases[1], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "b(Ref2)")

        let bytes_c = readBytes(MP_Ref_3P_5E.c(VerificationRef3()))
        verifySpareBitsTag(bytes: bytes_c, projection: result.cases[2], spareBytes: info.spareBytes, spareBytesOffset: info.spareBytesOffset, payloadSize: payloadSize, label: "c(Ref3)")

        // Empty cases: full byte comparison
        let emptyCases: [MP_Ref_3P_5E] = [.e0, .e1, .e2, .e3, .e4]
        for (i, emptyCase) in emptyCases.enumerated() {
            verifyEmptyCaseOrZeroPayload(bytes: readBytes(emptyCase), projection: result.cases[3 + i], label: "e\(i)")
        }
    }

    // MARK: - getEnumTagCounts Verification

    @Test("getEnumTagCounts numTagBytes matches actual memory overhead")
    func enumTagCountsVerification() {
        // Small payload (1 byte)
        verifyTagCounts(payloadSize: 1, emptyCases: 3, payloadCases: 2,
                        actualEnumSize: MemoryLayout<TMP_U8_2P_3E>.size, label: "U8 2P 3E")
        verifyTagCounts(payloadSize: 1, emptyCases: 1, payloadCases: 3,
                        actualEnumSize: MemoryLayout<TMP_U8_3P_1E>.size, label: "U8 3P 1E")
        verifyTagCounts(payloadSize: 1, emptyCases: 0, payloadCases: 4,
                        actualEnumSize: MemoryLayout<TMP_U8_4P_0E>.size, label: "U8 4P 0E")

        // Medium payload (2 bytes)
        verifyTagCounts(payloadSize: 2, emptyCases: 2, payloadCases: 2,
                        actualEnumSize: MemoryLayout<TMP_U16_2P_2E>.size, label: "U16 2P 2E")
        verifyTagCounts(payloadSize: 2, emptyCases: 0, payloadCases: 3,
                        actualEnumSize: MemoryLayout<TMP_U16_3P_0E>.size, label: "U16 3P 0E")

        // Large payload (4 bytes)
        verifyTagCounts(payloadSize: 4, emptyCases: 1, payloadCases: 2,
                        actualEnumSize: MemoryLayout<TMP_U32_2P_1E>.size, label: "U32 2P 1E")
        verifyTagCounts(payloadSize: 4, emptyCases: 5, payloadCases: 3,
                        actualEnumSize: MemoryLayout<TMP_U32_3P_5E>.size, label: "U32 3P 5E")

        // Extra-large payload (8 bytes)
        verifyTagCounts(payloadSize: 8, emptyCases: 3, payloadCases: 2,
                        actualEnumSize: MemoryLayout<TMP_U64_2P_3E>.size, label: "U64 2P 3E")
        verifyTagCounts(payloadSize: 8, emptyCases: 0, payloadCases: 3,
                        actualEnumSize: MemoryLayout<TMP_U64_3P_0E>.size, label: "U64 3P 0E")
    }

    @Test("getEnumTagCounts for single-payload overflow enums")
    func enumTagCountsSinglePayload() {
        // For single-payload overflow, getEnumTagCounts(payloadSize, overflowCases, 1) gives tag bytes.
        // UInt8 payload: 0 XI → all empty cases are overflow
        let tc_U8_1 = Calculator.getEnumTagCounts(payloadSize: 1, emptyCases: 1, payloadCases: 1)
        let actual_U8_1 = MemoryLayout<SP_U8_1E>.size - MemoryLayout<UInt8>.size
        #expect(tc_U8_1.numTagBytes == actual_U8_1, "SP_U8_1E")

        let tc_U8_3 = Calculator.getEnumTagCounts(payloadSize: 1, emptyCases: 3, payloadCases: 1)
        let actual_U8_3 = MemoryLayout<SP_U8_3E>.size - MemoryLayout<UInt8>.size
        #expect(tc_U8_3.numTagBytes == actual_U8_3, "SP_U8_3E")

        let tc_U16_1 = Calculator.getEnumTagCounts(payloadSize: 2, emptyCases: 1, payloadCases: 1)
        let actual_U16_1 = MemoryLayout<SP_U16_1E>.size - MemoryLayout<UInt16>.size
        #expect(tc_U16_1.numTagBytes == actual_U16_1, "SP_U16_1E")

        let tc_U32_1 = Calculator.getEnumTagCounts(payloadSize: 4, emptyCases: 1, payloadCases: 1)
        let actual_U32_1 = MemoryLayout<SP_U32_1E>.size - MemoryLayout<UInt32>.size
        #expect(tc_U32_1.numTagBytes == actual_U32_1, "SP_U32_1E")

        let tc_U64_1 = Calculator.getEnumTagCounts(payloadSize: 8, emptyCases: 1, payloadCases: 1)
        let actual_U64_1 = MemoryLayout<SP_U64_1E>.size - MemoryLayout<UInt64>.size
        #expect(tc_U64_1.numTagBytes == actual_U64_1, "SP_U64_1E")
    }

    // MARK: - MemoryLayout Size Consistency

    @Test("MemoryLayout sizes match Calculator expectations for all enum types")
    func memorySizeConsistency() throws {
        // Tagged multi-payload: size = payloadSize + numTagBytes
        #expect(MemoryLayout<TMP_U8_2P_0E>.size == 1 + Calculator.getEnumTagCounts(payloadSize: 1, emptyCases: 0, payloadCases: 2).numTagBytes)
        #expect(MemoryLayout<TMP_U16_2P_2E>.size == 2 + Calculator.getEnumTagCounts(payloadSize: 2, emptyCases: 2, payloadCases: 2).numTagBytes)
        #expect(MemoryLayout<TMP_U32_2P_1E>.size == 4 + Calculator.getEnumTagCounts(payloadSize: 4, emptyCases: 1, payloadCases: 2).numTagBytes)
        #expect(MemoryLayout<TMP_U64_2P_3E>.size == 8 + Calculator.getEnumTagCounts(payloadSize: 8, emptyCases: 3, payloadCases: 2).numTagBytes)

        // Single payload with XI: size == payloadSize (no extra tag bytes)
        #expect(MemoryLayout<SP_Bool_1E>.size == MemoryLayout<Bool>.size, "Bool XI enum needs no extra bytes")
        #expect(MemoryLayout<SP_Bool_3E>.size == MemoryLayout<Bool>.size, "Bool XI enum needs no extra bytes")
        // Optional<UInt8> has 0 XI → overflow with extra tag byte
        #expect(MemoryLayout<SP_OptU8_1E>.size == MemoryLayout<UInt8?>.size + Calculator.getEnumTagCounts(payloadSize: MemoryLayout<UInt8?>.size, emptyCases: 1, payloadCases: 1).numTagBytes)
        #expect(MemoryLayout<SP_Ref_2E>.size == MemoryLayout<VerificationRef1>.size, "Ref XI enum needs no extra bytes")
    }

    // MARK: - Verification Helpers

    /// Verify all bytes for empty cases or payload cases with value=0.
    /// For these cases, all bytes are deterministic (no user payload involved).
    private func verifyEmptyCaseOrZeroPayload(
        bytes: [UInt8],
        projection: Calculator.EnumCaseProjection,
        label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (offset, expectedByte) in projection.memoryChanges {
            guard offset < bytes.count else {
                Issue.record(
                    "\(label): offset \(offset) out of bounds (size=\(bytes.count))",
                    sourceLocation: sourceLocation
                )
                continue
            }
            #expect(
                bytes[offset] == expectedByte,
                "\(label) [\(projection.caseName)]: byte at offset \(offset) expected \(String(format: "0x%02X", expectedByte)), got \(String(format: "0x%02X", bytes[offset]))",
                sourceLocation: sourceLocation
            )
        }

        // Bytes not in memoryChanges should be 0 for empty cases and zero-payload cases
        for offset in 0 ..< bytes.count {
            if projection.memoryChanges[offset] == nil {
                #expect(
                    bytes[offset] == 0,
                    "\(label) [\(projection.caseName)]: byte at offset \(offset) expected 0x00 (not in memoryChanges), got \(String(format: "0x%02X", bytes[offset]))",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    /// Verify only the tag bytes (after payload area) for payload cases with non-zero values.
    private func verifyTagBytes(
        bytes: [UInt8],
        projection: Calculator.EnumCaseProjection,
        payloadSize: Int,
        label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (offset, expectedByte) in projection.memoryChanges where offset >= payloadSize {
            guard offset < bytes.count else {
                Issue.record(
                    "\(label): tag offset \(offset) out of bounds (size=\(bytes.count))",
                    sourceLocation: sourceLocation
                )
                continue
            }
            #expect(
                bytes[offset] == expectedByte,
                "\(label) [\(projection.caseName)]: tag byte at offset \(offset) expected \(String(format: "0x%02X", expectedByte)), got \(String(format: "0x%02X", bytes[offset]))",
                sourceLocation: sourceLocation
            )
        }
    }

    /// Verify spare bits tag region for multi-payload spare bits strategy.
    /// Only checks the spare bit positions within the payload, not the non-spare bits (which hold the heap pointer).
    private func verifySpareBitsTag(
        bytes: [UInt8],
        projection: Calculator.EnumCaseProjection,
        spareBytes: [UInt8],
        spareBytesOffset: Int,
        payloadSize: Int,
        label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (offset, expectedByte) in projection.memoryChanges {
            guard offset < bytes.count else {
                Issue.record(
                    "\(label): offset \(offset) out of bounds (size=\(bytes.count))",
                    sourceLocation: sourceLocation
                )
                continue
            }

            if offset >= payloadSize {
                // Extra tag bytes after payload: compare directly
                #expect(
                    bytes[offset] == expectedByte,
                    "\(label) [\(projection.caseName)]: extra tag byte at offset \(offset) expected \(String(format: "0x%02X", expectedByte)), got \(String(format: "0x%02X", bytes[offset]))",
                    sourceLocation: sourceLocation
                )
            } else {
                // Within payload: only compare the spare bit positions
                let spareIndex = offset - spareBytesOffset
                let spareMask: UInt8
                if spareIndex >= 0 && spareIndex < spareBytes.count {
                    spareMask = spareBytes[spareIndex]
                } else {
                    spareMask = 0
                }

                if spareMask != 0 {
                    let actualSpareBits = bytes[offset] & spareMask
                    let expectedSpareBits = expectedByte & spareMask
                    #expect(
                        actualSpareBits == expectedSpareBits,
                        "\(label) [\(projection.caseName)]: spare bits at offset \(offset) (mask=\(String(format: "0x%02X", spareMask))) expected \(String(format: "0x%02X", expectedSpareBits)), got \(String(format: "0x%02X", actualSpareBits))",
                        sourceLocation: sourceLocation
                    )
                }
            }
        }
    }

    /// Verify getEnumTagCounts numTagBytes against actual enum memory overhead.
    private func verifyTagCounts(
        payloadSize: Int,
        emptyCases: Int,
        payloadCases: Int,
        actualEnumSize: Int,
        label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let tagCounts = Calculator.getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: payloadCases)
        let actualTagBytes = actualEnumSize - payloadSize
        #expect(
            tagCounts.numTagBytes == actualTagBytes,
            "\(label): expected numTagBytes=\(actualTagBytes), got \(tagCounts.numTagBytes)",
            sourceLocation: sourceLocation
        )
    }
}
