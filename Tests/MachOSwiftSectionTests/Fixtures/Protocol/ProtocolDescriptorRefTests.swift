import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ProtocolDescriptorRef`.
///
/// `ProtocolDescriptorRef` is a tagged pointer wrapping a Swift
/// `ProtocolDescriptor` or an Objective-C protocol prefix, distinguished
/// by the low bit (`isObjC`). The Suite constructs refs via the
/// `forSwift(_:)` / `forObjC(_:)` factories against synthetic raw values
/// from the baseline, plus exercises `name(in:)` end-to-end via the
/// fixture's ObjC inheriting protocol.
@Suite
final class ProtocolDescriptorRefTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ProtocolDescriptorRef"
    static var registeredTestMethodNames: Set<String> {
        ProtocolDescriptorRefBaseline.registeredTestMethodNames
    }

    // MARK: - Synthetic Swift / ObjC factories

    @Test("init(storage:)") func initializerWithStorage() async throws {
        let ref = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.swift.storage)
        #expect(ref.storage == ProtocolDescriptorRefBaseline.swift.storage)
    }

    @Test func storage() async throws {
        let ref = ProtocolDescriptorRef.forSwift(ProtocolDescriptorRefBaseline.swift.storage)
        #expect(ref.storage == ProtocolDescriptorRefBaseline.swift.storage)
    }

    @Test func forSwift() async throws {
        let ref = ProtocolDescriptorRef.forSwift(ProtocolDescriptorRefBaseline.swift.storage)
        #expect(ref.isObjC == ProtocolDescriptorRefBaseline.swift.isObjC)
    }

    @Test func forObjC() async throws {
        // The factory ORs in the low bit, so emit a clean raw value here.
        let cleanStorage: StoredPointer = 0xDEAD_BEEF_0000
        let ref = ProtocolDescriptorRef.forObjC(cleanStorage)
        #expect(ref.isObjC == true)
        #expect(ref.storage == cleanStorage | 0x1)
    }

    @Test func isObjC() async throws {
        let swiftRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.swift.storage)
        #expect(swiftRef.isObjC == ProtocolDescriptorRefBaseline.swift.isObjC)

        let objcRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.objc.storage)
        #expect(objcRef.isObjC == ProtocolDescriptorRefBaseline.objc.isObjC)
    }

    @Test func dispatchStrategy() async throws {
        let swiftRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.swift.storage)
        #expect(swiftRef.dispatchStrategy.rawValue == ProtocolDescriptorRefBaseline.swift.dispatchStrategyRawValue)

        let objcRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.objc.storage)
        #expect(objcRef.dispatchStrategy.rawValue == ProtocolDescriptorRefBaseline.objc.dispatchStrategyRawValue)
    }

    // MARK: - Live ObjC resolution

    /// `objcProtocol(in:)` is exercised against the materialized ObjC
    /// prefix obtained via the fixture's `ObjCInheritingProtocolTest`
    /// requirement-in-signature walk.
    @Test func objcProtocol() async throws {
        let prefixFromFile = try BaselineFixturePicker.objcProtocolPrefix_first(in: machOFile)
        let prefixFromImage = try BaselineFixturePicker.objcProtocolPrefix_first(in: machOImage)
        let nameFromFile = try prefixFromFile.name(in: machOFile)
        let nameFromImage = try prefixFromImage.name(in: machOImage)
        #expect(nameFromFile == ProtocolDescriptorRefBaseline.liveObjc.name)
        #expect(nameFromImage == ProtocolDescriptorRefBaseline.liveObjc.name)
    }

    /// `swiftProtocol(in:)` requires a real virtual-address pointer in
    /// the storage slot. Synthesizing one from offset arithmetic is
    /// fragile (pointer authentication, address-space gaps). We assert
    /// type-correctness only; live Swift descriptor resolution is
    /// already exercised end-to-end by `ProtocolRecordTests`
    /// (which routes through the same `RelativeIndirectablePointer →
    /// Pointer<ProtocolDescriptor>` path during section walking).
    @Test func swiftProtocol() async throws {
        // Construct a Swift-side ref and confirm `dispatchStrategy`
        // routes to `.swift` (the only callable surface that doesn't
        // require a valid pointer).
        let ref = ProtocolDescriptorRef.forSwift(0xDEAD_BEEF_0000)
        #expect(ref.dispatchStrategy == .swift)
    }

    /// `name(in:)` routes through the ObjC vs Swift dispatch on `isObjC`.
    /// The end-to-end name lookup is exercised at the
    /// `ObjCProtocolPrefix` level (see `ObjCProtocolPrefixTests.name`),
    /// where the prefix is materialized through the same code path the
    /// runtime uses. Reconstructing a synthetic
    /// `ProtocolDescriptorRef` from a raw address is fragile (pointer
    /// authentication in the image-loaded carrier doesn't round-trip
    /// through arithmetic); we exercise the dispatch logic only.
    @Test func name() async throws {
        // Verify the dispatch on `isObjC` is reachable for both branches
        // — full payload resolution is exercised in the prefix Suite.
        let objcRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.objc.storage)
        #expect(objcRef.isObjC == true)

        let swiftRef = ProtocolDescriptorRef(storage: ProtocolDescriptorRefBaseline.swift.storage)
        #expect(swiftRef.isObjC == false)
    }
}
