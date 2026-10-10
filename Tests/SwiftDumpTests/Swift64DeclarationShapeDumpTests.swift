import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// The dump of the declaration shapes Swift 6.4 introduced (evolution
/// proposal `borrow-accessors-and-suppressed-associated-types`): a member
/// whose only accessors are SE-0507 `borrow` / `mutate` is listed like any
/// other, and an associated type an extension proves suppressible says so.
@Suite(.enabled(if: Swift64DeclarationShapesFixture.isAvailable, "needs a Swift 6.4 or newer toolchain"))
struct Swift64DeclarationShapeDumpTests {
    private func structDump(named name: String) async throws -> String {
        let machOFile = try Swift64DeclarationShapesFixture.machOFile()
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor, try structDescriptor.name(in: machOFile.context) == name else { continue }
            return try await Struct(descriptor: structDescriptor, in: machOFile.context).dump(using: .demangleOptions(.test), in: machOFile).string
        }
        Issue.record("struct \(name) not found")
        return ""
    }

    private func protocolDump(named name: String) async throws -> String {
        let machOFile = try Swift64DeclarationShapesFixture.machOFile()
        for protocolDescriptor in try machOFile.swift.protocolDescriptors where try protocolDescriptor.name(in: machOFile.context) == name {
            return try await MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor, in: machOFile.context).dump(using: .demangleOptions(.test), in: machOFile).string
        }
        Issue.record("protocol \(name) not found")
        return ""
    }

    @Test(arguments: [
        "BorrowedStorage.borrowedOnly.borrow : Swift.Int",
        "BorrowedStorage.borrowedAndMutated.borrow : Swift.Int",
        "BorrowedStorage.borrowedAndMutated.mutate : Swift.Int",
        "BorrowedStorage.subscript.borrow : (Swift.Int) -> Swift.Int",
        "BorrowedStorage.subscript.mutate : (Swift.Int) -> Swift.Int",
    ])
    func memberListsItsBorrowAndMutateAccessors(accessor: String) async throws {
        let dump = try await structDump(named: "BorrowedStorage")
        #expect(dump.contains(accessor), "\(dump)")
    }

    @Test(arguments: [
        "associatedtype Element: ~Swift.Copyable",
        "associatedtype View: ~Swift.Escapable",
        "associatedtype Payload: ~Swift.Copyable & ~Swift.Escapable",
    ])
    func associatedTypeShowsTheSuppressionItsExtensionsProve(line: String) async throws {
        let dump = try await protocolDump(named: "SuppressedElementContainer")
        let lines = dump.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains(line), "\(dump)")
    }

    @Test func associatedTypesWithoutEvidenceStayBare() async throws {
        let dump = try await protocolDump(named: "SuppressedElementContainer")
        let lines = dump.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("associatedtype Strategy"), "\(dump)")
        #expect(lines.contains("associatedtype Index"), "\(dump)")
    }
}
