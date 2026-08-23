import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Dump-path coverage for the `// not exported` annotation (evolution
/// proposal 0008), pinning the two false-positive classes the member-symbol
/// loops originally missed (the interface path had guarded them, the dump
/// path had not — both verified live on this fixture before the fix):
///
/// - a `public override`'s implementation symbol is an ordinary member
///   symbol of the subclass with zero exported forms of its own (external
///   callers link the PARENT's dispatch thunk);
/// - an `@objc dynamic` member dispatches through objc_msgSend, its Swift
///   symbols legitimately trie-miss.
///
/// Plus the `Tq` row correction: a `method descriptor` line's symbol name
/// already carries the `Tq` suffix, so the derived-form expansion must run
/// over the stripped implementation name (appending `Tj`/`Tu` onto "…Tq"
/// queries names that never exist, degrading to the bare-name query).
@Suite(.serialized)
final class ExportStatusDumpAnnotationTests: MachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private static let overrideImplementationName = "_$s15SymbolTestsCore7ClassesO12SubclassTestC14instanceMethodAEXDyF"
    private static let objcDynamicImplementationName = "_$s15SymbolTestsCore10AttributesO18ObjCAttributeClassC17objcDynamicMethodyyF"

    private func dumpClasses(printExportStatus: Bool, inNamespace namespace: String) async throws -> String {
        var configuration = DumperConfiguration.demangleOptions(.test)
        configuration.printExportStatus = printExportStatus
        let unsafeMachOFile = machOFile
        let typeContextDescriptors = try unsafeMachOFile.swift.typeContextDescriptors
        var results: [String] = []
        for typeContextDescriptor in typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            guard (try? rootNamespace(of: typeContextDescriptor, in: unsafeMachOFile)) == namespace else { continue }
            let classType = try Class(descriptor: classDescriptor, in: unsafeMachOFile)
            results.append(try await classType.dump(using: configuration, in: unsafeMachOFile).string)
        }
        return results.joined(separator: "\n")
    }

    /// Whether the line immediately preceding the first line matching
    /// `lineMatches` is a `not exported` comment.
    private func isAnnotated(in output: String, where lineMatches: @escaping (Substring) -> Bool) throws -> Bool {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let index = try #require(lines.firstIndex(where: lineMatches), "no line matched")
        guard index > 0 else { return false }
        return lines[index - 1].contains("// not exported")
    }

    /// The A2 reproduction: `SubclassTest.instanceMethod`'s implementation
    /// symbol appears in the member-symbol section (NOT just the vtable
    /// override section) and carries zero exported forms — premise pinned
    /// via the store so the exemption, not fixture luck, is what's tested.
    @Test func overrideImplementationSymbolIsExempt() async throws {
        let unsafeMachOFile = machOFile
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: Self.overrideImplementationName, in: unsafeMachOFile) == false)

        let output = try await dumpClasses(printExportStatus: true, inNamespace: "Classes")
        let annotated = try isAnnotated(in: output) { line in
            line.hasSuffix("Classes.SubclassTest.instanceMethod() -> Self") && !line.contains("override")
        }
        #expect(!annotated)
    }

    @Test func objcDynamicImplementationSymbolIsExempt() async throws {
        let unsafeMachOFile = machOFile
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: Self.objcDynamicImplementationName, in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.containsSymbol(named: Self.objcDynamicImplementationName + "To", in: unsafeMachOFile))

        let output = try await dumpClasses(printExportStatus: true, inNamespace: "Attributes")
        let annotated = try isAnnotated(in: output) { line in
            line.hasSuffix("ObjCAttributeClass.objcDynamicMethod() -> ()")
        }
        #expect(!annotated)
    }

    /// The true positive survives the exemptions: `Classes.ClassTest`
    /// declares no initializer, its implicit internal `init()` emits only a
    /// `Tq` method-descriptor symbol, and no form of the member reaches the
    /// trie — the `method descriptor` line stays annotated (now via the
    /// stripped implementation name).
    @Test func internalInitMethodDescriptorRowStaysAnnotated() async throws {
        let output = try await dumpClasses(printExportStatus: true, inNamespace: "Classes")
        let annotated = try isAnnotated(in: output) { line in
            line.contains("method descriptor for SymbolTestsCore.Classes.ClassTest.__allocating_init()")
        }
        #expect(annotated)
    }

    @Test func defaultDumpCarriesNoAnnotation() async throws {
        let output = try await dumpClasses(printExportStatus: false, inNamespace: "Classes")
        #expect(!output.contains("// not exported"))
    }
}
