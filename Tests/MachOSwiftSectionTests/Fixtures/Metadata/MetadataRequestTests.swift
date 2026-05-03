import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataRequest`.
///
/// `MetadataRequest` is a `MutableFlagSet` packing `state` (8 bits) and
/// `isBlocking` (1 bit) into a single `Int` raw value. Bit-packing
/// invariants are reader-independent, so the Suite drives the type via
/// constant round-trips.
@Suite
final class MetadataRequestTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataRequest"
    static var registeredTestMethodNames: Set<String> {
        MetadataRequestBaseline.registeredTestMethodNames
    }

    /// Default `init()` produces a zero-valued request (`.complete` state,
    /// non-blocking).
    @Test("init") func defaultInitializer() async throws {
        let request = MetadataRequest()
        #expect(request.rawValue == 0)
        #expect(request.state == .complete)
        #expect(request.isBlocking == false)
    }

    /// `init(rawValue:)` accepts a raw integer; the projected `state` and
    /// `isBlocking` decode from the bit fields.
    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let raw = MetadataRequestBaseline.layoutCompleteRawValue
        let request = MetadataRequest(rawValue: raw)
        #expect(request.rawValue == raw)
        #expect(request.state == .layoutComplete)
        #expect(request.isBlocking == false)
    }

    /// `init(state:isBlocking:)` constructs a request with explicit fields.
    @Test("init(state:isBlocking:)") func initializerWithStateAndBlocking() async throws {
        let request = MetadataRequest(state: .complete, isBlocking: true)
        #expect(request.state == .complete)
        #expect(request.isBlocking == true)
        #expect(request.rawValue == MetadataRequestBaseline.completeAndBlockingExpectedRawValue)
    }

    /// `completeAndBlocking` is the static convenience constructor.
    @Test func completeAndBlocking() async throws {
        let request = MetadataRequest.completeAndBlocking
        #expect(request.state == .complete)
        #expect(request.isBlocking == true)
        #expect(request.rawValue == MetadataRequestBaseline.completeAndBlockingExpectedRawValue)
    }

    /// `state` setter writes the 8-bit field at offset 0.
    @Test func state() async throws {
        var request = MetadataRequest()
        request.state = .abstract
        #expect(request.state == .abstract)
        #expect(request.rawValue == MetadataRequestBaseline.abstractRawValue)
    }

    /// `isBlocking` setter writes the bit at offset 8.
    @Test func isBlocking() async throws {
        var request = MetadataRequest()
        request.isBlocking = true
        #expect(request.isBlocking == true)
        #expect(request.rawValue == 0x100)
    }

    /// `rawValue` projects the underlying integer; setter (inherited from
    /// `MutableFlagSet`) is exercised via `state`/`isBlocking` setters
    /// above.
    @Test func rawValue() async throws {
        let request = MetadataRequest(rawValue: 0x42)
        #expect(request.rawValue == 0x42)
    }
}
