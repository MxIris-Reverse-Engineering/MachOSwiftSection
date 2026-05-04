import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MetadataRequest`.
///
/// `MetadataRequest` is a `MutableFlagSet` packing `state` (8 bits) and
/// `isBlocking` (1 bit) into a single `Int` raw value. Bit-packing
/// invariants are reader-independent — there is no Mach-O serialised
/// presence — but Phase C5 wraps each test in `usingInProcessOnly` so
/// the suite is classified as `.inProcessOnly` by the behavior scanner
/// (rather than `.sentinel`). The `InProcessContext` is unused; the
/// assertions exercise the flag-set bit-packing accessors directly.
@Suite
final class MetadataRequestTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetadataRequest"
    static var registeredTestMethodNames: Set<String> {
        MetadataRequestBaseline.registeredTestMethodNames
    }

    /// Default `init()` produces a zero-valued request (`.complete` state,
    /// non-blocking).
    @Test("init") func defaultInitializer() async throws {
        _ = try usingInProcessOnly { _ in
            let request = MetadataRequest()
            #expect(request.rawValue == 0)
            #expect(request.state == .complete)
            #expect(request.isBlocking == false)
            return request.rawValue
        }
    }

    /// `init(rawValue:)` accepts a raw integer; the projected `state` and
    /// `isBlocking` decode from the bit fields.
    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        _ = try usingInProcessOnly { _ in
            let raw = MetadataRequestBaseline.layoutCompleteRawValue
            let request = MetadataRequest(rawValue: raw)
            #expect(request.rawValue == raw)
            #expect(request.state == .layoutComplete)
            #expect(request.isBlocking == false)
            return request.rawValue
        }
    }

    /// `init(state:isBlocking:)` constructs a request with explicit fields.
    @Test("init(state:isBlocking:)") func initializerWithStateAndBlocking() async throws {
        _ = try usingInProcessOnly { _ in
            let request = MetadataRequest(state: .complete, isBlocking: true)
            #expect(request.state == .complete)
            #expect(request.isBlocking == true)
            #expect(request.rawValue == MetadataRequestBaseline.completeAndBlockingExpectedRawValue)
            return request.rawValue
        }
    }

    /// `completeAndBlocking` is the static convenience constructor.
    @Test func completeAndBlocking() async throws {
        _ = try usingInProcessOnly { _ in
            let request = MetadataRequest.completeAndBlocking
            #expect(request.state == .complete)
            #expect(request.isBlocking == true)
            #expect(request.rawValue == MetadataRequestBaseline.completeAndBlockingExpectedRawValue)
            return request.rawValue
        }
    }

    /// `state` setter writes the 8-bit field at offset 0.
    @Test func state() async throws {
        _ = try usingInProcessOnly { _ in
            var request = MetadataRequest()
            request.state = .abstract
            #expect(request.state == .abstract)
            #expect(request.rawValue == MetadataRequestBaseline.abstractRawValue)
            return request.rawValue
        }
    }

    /// `isBlocking` setter writes the bit at offset 8.
    @Test func isBlocking() async throws {
        _ = try usingInProcessOnly { _ in
            var request = MetadataRequest()
            request.isBlocking = true
            #expect(request.isBlocking == true)
            #expect(request.rawValue == 0x100)
            return request.rawValue
        }
    }

    /// `rawValue` projects the underlying integer; setter (inherited from
    /// `MutableFlagSet`) is exercised via `state`/`isBlocking` setters
    /// above.
    @Test func rawValue() async throws {
        _ = try usingInProcessOnly { _ in
            let request = MetadataRequest(rawValue: 0x42)
            #expect(request.rawValue == 0x42)
            return request.rawValue
        }
    }
}
