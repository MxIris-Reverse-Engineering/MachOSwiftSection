import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `FunctionTypeMetadata`.
///
/// Function type metadata is runtime-allocated and sits in no Mach-O
/// section, so every carrier is a live in-process type and every assertion
/// runs through `usingInProcessOnly`.
///
/// The trailing blocks are what this Suite is really about. They appear in a
/// fixed order, each on its own alignment, and only when the flags say so —
/// so the checks compare the resolved trailing TYPES against the metadata of
/// the very types the carriers name. `((Int, String) -> Bool)` must report
/// `Int` and `String`; the `@MainActor () throws(E) -> Void` carrier must
/// report `MainActor` and `E`. Pointer identity is what makes those
/// assertions strong: a mis-computed offset by even one word lands on
/// something else entirely.
@Suite
final class FunctionTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeMetadataBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let label: String
        let pointer: UnsafeRawPointer
        let expected: FunctionTypeMetadataBaseline.Entry
    }

    /// The carriers that exist at every deployment target. The typed-throws
    /// one is added by ``typedThrowsCarrier`` where availability allows.
    private var alwaysAvailableCarriers: [Carrier] {
        [
            Carrier(
                label: "intToVoid",
                pointer: InProcessMetadataPicker.stdlibFunctionIntToVoid,
                expected: FunctionTypeMetadataBaseline.stdlibFunctionIntToVoid
            ),
            Carrier(
                label: "intStringToBool",
                pointer: InProcessMetadataPicker.stdlibFunctionIntStringToBool,
                expected: FunctionTypeMetadataBaseline.stdlibFunctionIntStringToBool
            ),
            Carrier(
                label: "inOutIntToVoid",
                pointer: InProcessMetadataPicker.stdlibFunctionInOutIntToVoid,
                expected: FunctionTypeMetadataBaseline.stdlibFunctionInOutIntToVoid
            ),
        ]
    }

    private var typedThrowsCarrier: Carrier? {
        guard #available(macOS 15.0, *),
              let expected = FunctionTypeMetadataBaseline.stdlibFunctionMainActorTypedThrows else { return nil }
        return Carrier(
            label: "mainActorTypedThrows",
            pointer: InProcessMetadataPicker.stdlibFunctionMainActorTypedThrows,
            expected: expected
        )
    }

    private var allCarriers: [Carrier] {
        alwaysAvailableCarriers + (typedThrowsCarrier.map { [$0] } ?? [])
    }

    private func metadataAddress<T>(of type: T.Type) -> UInt64 {
        UInt64(UInt(bitPattern: unsafeBitCast(type, to: UnsafeRawPointer.self)))
    }

    @Test func layout() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            #expect(resolved.kind.rawValue == carrier.expected.kindRawValue, "\(carrier.label)")
            #expect(resolved.layout.flags.rawValue == carrier.expected.flagsRawValue, "\(carrier.label)")
        }
    }

    @Test func offset() async throws {
        for carrier in allCarriers {
            let resolvedOffset = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context).offset
            }
            // For InProcess resolution, `offset` is the bit-pattern of the
            // runtime metadata pointer itself.
            #expect(resolvedOffset == Int(bitPattern: carrier.pointer), "\(carrier.label)")
        }
    }

    @Test func flags() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            #expect(resolved.flags.rawValue == carrier.expected.flagsRawValue, "\(carrier.label)")
            #expect(resolved.flags.hasParameterFlags == carrier.expected.hasParameterFlags, "\(carrier.label)")
            #expect(resolved.flags.hasGlobalActor == carrier.expected.hasGlobalActor, "\(carrier.label)")
            #expect(resolved.flags.hasExtendedFlags == carrier.expected.hasExtendedFlags, "\(carrier.label)")
            #expect(resolved.flags.isDifferentiable == carrier.expected.isDifferentiable, "\(carrier.label)")
        }
    }

    @Test func numberOfParameters() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            #expect(resolved.numberOfParameters == carrier.expected.numberOfParameters, "\(carrier.label)")
        }
    }

    @Test func parametersOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            // The first trailing block starts immediately after the
            // three-word header — kind, flags, result type.
            #expect(resolved.parametersOffset == resolved.offset + MemoryLayout<FunctionTypeMetadata.Layout>.size, "\(carrier.label)")
            #expect(MemoryLayout<FunctionTypeMetadata.Layout>.size == 24)
        }
    }

    /// The assertion that makes the arithmetic trustworthy: the parameter
    /// types must be the metadata of the types the carrier names.
    @Test func parameters() async throws {
        let resolved = try usingInProcessOnly { context in
            let metadata = try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntStringToBool, in: context)
            return try metadata.parameters(in: context).map(\.address)
        }
        #expect(resolved == [metadataAddress(of: Int.self), metadataAddress(of: String.self)])

        let noParameters = try usingInProcessOnly { context -> [UInt64] in
            guard let carrier = typedThrowsCarrier else { return [] }
            let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            return try metadata.parameters(in: context).map(\.address)
        }
        #expect(noParameters.isEmpty, "a parameterless carrier must read no parameters, not one garbage word")
    }

    /// The array is omitted entirely when every parameter is an ordinary
    /// by-value one, so an empty result means "all plain", never "unknown".
    @Test func parameterFlags() async throws {
        let inOutFlags = try usingInProcessOnly { context in
            let metadata = try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionInOutIntToVoid, in: context)
            return try metadata.parameterFlags(in: context)
        }
        #expect(inOutFlags.count == 1)
        #expect(inOutFlags.first?.ownership == .inOut)
        #expect(inOutFlags.first?.isVariadic == false)

        let plainFlags = try usingInProcessOnly { context in
            let metadata = try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntStringToBool, in: context)
            return try metadata.parameterFlags(in: context)
        }
        #expect(plainFlags.isEmpty)
    }

    @Test func parameterFlagsOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            if carrier.expected.hasParameterFlags {
                #expect(resolved.parameterFlagsOffset == resolved.parametersOffset + carrier.expected.numberOfParameters * 8, "\(carrier.label)")
            } else {
                #expect(resolved.parameterFlagsOffset == nil, "\(carrier.label)")
            }
        }
    }

    @Test func differentiabilityKindOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            // No carrier here is differentiable; the block must be absent
            // rather than defaulted to some position.
            #expect(resolved.differentiabilityKindOffset == nil, "\(carrier.label)")
        }
    }

    @Test func differentiabilityKind() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context -> FunctionTypeDifferentiabilityKind? in
                let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
                return try metadata.differentiabilityKind(in: context)
            }
            #expect(resolved == nil, "\(carrier.label)")
        }
    }

    @Test func globalActorOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            #expect((resolved.globalActorOffset != nil) == carrier.expected.hasGlobalActor, "\(carrier.label)")
        }
    }

    @Test func globalActorType() async throws {
        guard let carrier = typedThrowsCarrier else { return }
        let resolved = try usingInProcessOnly { context -> UInt64? in
            let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            return try metadata.globalActorType(in: context)?.address
        }
        #expect(resolved == metadataAddress(of: MainActor.self))

        let none = try usingInProcessOnly { context -> UInt64? in
            let metadata = try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context)
            return try metadata.globalActorType(in: context)?.address
        }
        #expect(none == nil)
    }

    @Test func extendedFlagsOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context in
                try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            }
            #expect((resolved.extendedFlagsOffset != nil) == carrier.expected.hasExtendedFlags, "\(carrier.label)")
        }
    }

    @Test func extendedFlags() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context -> UInt32? in
                let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
                return try metadata.extendedFlags(in: context)?.rawValue
            }
            #expect(resolved == carrier.expected.extendedFlagsRawValue, "\(carrier.label)")
        }
    }

    /// Whether a thrown-error block is present is recorded in the extended
    /// flags' VALUE, not in the first flag word, so this offset genuinely
    /// needs a read — unlike every other one here.
    @Test func thrownErrorTypeOffset() async throws {
        for carrier in allCarriers {
            let resolved = try usingInProcessOnly { context -> Int? in
                let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
                return try metadata.thrownErrorTypeOffset(in: context)
            }
            #expect((resolved != nil) == carrier.expected.isTypedThrows, "\(carrier.label)")
        }
    }

    @Test func thrownErrorType() async throws {
        guard let carrier = typedThrowsCarrier else { return }
        let resolved = try usingInProcessOnly { context -> UInt64? in
            let metadata = try FunctionTypeMetadata.resolve(at: carrier.pointer, in: context)
            return try metadata.thrownErrorType(in: context)?.address
        }
        #expect(resolved == metadataAddress(of: InProcessMetadataPicker.FunctionFixtureError.self))

        let untyped = try usingInProcessOnly { context -> UInt64? in
            let metadata = try FunctionTypeMetadata.resolve(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context)
            return try metadata.thrownErrorType(in: context)?.address
        }
        #expect(untyped == nil)
    }
}
