import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import MachOTestingSupport

/// The dump path's half of `GenericParameterDepthNamingTests`: the dumpers
/// render a generic declaration's parameter clause through the same
/// `GenericContext` helper the interface printer does, so they numbered
/// depths the same wrong way — `Inner<A2>` over a field the record names
/// `A1`.
@Suite
struct GenericParameterDepthDumpTests {
    private func dumpedStruct(named name: String) async throws -> String {
        let machOFile = try GenericSpecializationFixture.machOFile()
        let descriptor = try #require(try GenericSpecializationFixture.typeContextDescriptor(named: name, in: machOFile).struct)
        let structType = try Struct(descriptor: descriptor, in: machOFile.context)
        return try await structType.dump(using: .demangleOptions(.test), in: machOFile).string
    }

    @Test("a parameter behind a level that declares none is named by its canonical depth")
    func parameterBehindNonDeclaringLevel() async throws {
        let dumped = try await dumpedStruct(named: "Inner")

        #expect(dumped.contains("Inner<A1> where A1: Swift.Hashable {"), "\(dumped)")
        #expect(!dumped.contains("A2"), "\(dumped)")
    }

    @Test("a parameter in a constrained extension of a nested generic type is named by its canonical depth")
    func parameterInConstrainedExtensionOfNestedGeneric() async throws {
        let dumped = try await dumpedStruct(named: "DeepConstrainedInner")

        #expect(dumped.contains("DeepConstrainedInner<A2> where A2: Swift.Hashable {"), "\(dumped)")
    }
}
