import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

/// The dump declares a local type under the compiler's full name and lists
/// the members its symbols attribute to it (evolution proposal
/// `local-type-context-names`). Both of `Holder`'s `Visitor`s used to be
/// declared as `Holder.Visitor`, and since the member symbols spell the real
/// name, neither listed a member.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct LocalTypeDumpTests {
    @Test func eachVisitorIsDeclaredUnderItsMethodWithItsOwnMembers() async throws {
        let variant = LocalTypeFixture.Variant.unstripped
        let machOFile = try LocalTypeFixture.machOFile(variant)
        var dumps: [String] = []
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor,
                  try structDescriptor.name(in: machOFile.context) == "Visitor"
            else { continue }
            let structType = try Struct(descriptor: structDescriptor, in: machOFile.context)
            dumps.append(try await structType.dump(using: .demangleOptions(.test), in: machOFile).string)
        }
        let moduleName = variant.moduleName
        let countingVisitor = try #require(dumps.first { $0.hasPrefix("struct Visitor #1 in \(moduleName).Holder.countValues() -> Any {") }, "\(dumps)")
        let summingVisitor = try #require(dumps.first { $0.hasPrefix("struct Visitor #1 in \(moduleName).Holder.sumValues() -> Any {") }, "\(dumps)")

        #expect(countingVisitor.contains("var count: Swift.Int"), "\(countingVisitor)")
        #expect(!countingVisitor.contains("var sum: Swift.Int"), "\(countingVisitor)")
        #expect(countingVisitor.contains("visit(Swift.Int) -> ()"), "\(countingVisitor)")
        #expect(summingVisitor.contains("var sum: Swift.Int"), "\(summingVisitor)")
        #expect(summingVisitor.contains("visit(Swift.Int) -> ()"), "\(summingVisitor)")
    }
}
