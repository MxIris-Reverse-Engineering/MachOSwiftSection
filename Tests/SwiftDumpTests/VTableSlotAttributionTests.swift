import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport

/// Vtable slot attribution under identical code folding.
///
/// Which member a slot belongs to is decided by the method descriptor's own
/// `Tq` symbol, not by the symbols at its implementation address: the linker
/// folds byte-identical function bodies onto one address, so an
/// implementation-address query answers with every folded member at once and
/// the mapping cannot be inverted. Before the fix the slots were handed
/// whichever matching symbol the table listed first, which reordered them
/// (and, when a NESTED type's member folded in too, took names from outside
/// the class entirely).
///
/// The fixture compiles with `-Xlinker -deduplicate` to force the folding —
/// without it the four empty bodies stay at four addresses and the scenario
/// does not exist, which is why `foldedImplementationAddress` is a REQUIRED
/// premise of every test here rather than a soft check.
@Suite(.serialized)
struct VTableSlotAttributionTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    /// `alpha` / `beta` / `gamma` have byte-identical (empty) bodies and fold
    /// onto one address. `Nested.nestedNoop` folds onto the SAME address and is
    /// the cross-type trap: its demangled tree's first class node is `Host`, so
    /// a `first(of: .class)` match accepts it as a member of `Host` — the shape
    /// that put `GraphHost.Data`'s coroutine resume functions in `GraphHost`'s
    /// vtable. `Nested` must be a class, not a struct: a struct method's body
    /// differs in calling convention and does not fold.
    ///
    /// The class also satisfies the `__DATA`-segment requirement every
    /// on-the-fly fixture in this repository carries (see
    /// `DiffMemberIndentationTests`).
    private static let fixtureSource = """
    open class Host {
        open func alpha() {}
        open func beta() {}
        open func gamma() {}
        public class Nested {
            public func nestedNoop() {}
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("VTableAttributionFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("VTableAttributionFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libVTableAttributionFixture.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "VTableAttributionFixture",
                sourceURL.path, "-o", libraryURL.path,
                // ld64's identical-code-folding switch: without it the empty
                // bodies keep four distinct addresses and nothing is ambiguous.
                "-Xlinker", "-deduplicate",
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "vtable-attribution fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    private func classDescriptor(named name: String, in machOFile: MachOFile) throws -> ClassDescriptor {
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            guard try classDescriptor.name(in: machOFile) == name else { continue }
            return classDescriptor
        }
        Issue.record("fixture is missing the class \(name)")
        throw FixtureCompilationError(diagnostics: "class \(name) not found")
    }

    /// The vtable slot declarations of a dumped class, in slot order, as
    /// `(slot, declaration)` pairs with the kind comment stripped.
    private func vtableSlots(inDumpOf classDescriptor: ClassDescriptor, in machOFile: MachOFile) async throws -> [(slot: Int, declaration: String)] {
        var configuration = DumperConfiguration.demangleOptions(.test)
        configuration.printVTableOffset = true
        let classType = try Class(descriptor: classDescriptor, in: machOFile)
        let output = try await classType.dump(using: configuration, in: machOFile).string

        var slots: [(slot: Int, declaration: String)] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("// VTable offset: "),
                  let slot = Int(trimmed.dropFirst("// VTable offset: ".count)) else { continue }
            for followingLine in lines[(index + 1)...] {
                let candidate = followingLine.trimmingCharacters(in: .whitespaces)
                if candidate.hasPrefix("//") || candidate.isEmpty { continue }
                let declaration = candidate.replacingOccurrences(
                    of: "^/\\*[^*]*\\*/\\s*",
                    with: "",
                    options: .regularExpression
                )
                slots.append((slot, declaration))
                break
            }
        }
        return slots
    }

    /// The single address `alpha` / `beta` / `gamma` / `nestedNoop` folded onto
    /// — the premise the whole suite rests on.
    private func foldedImplementationAddress(in machOFile: MachOFile) throws -> Int {
        let hostDescriptor = try classDescriptor(named: "Host", in: machOFile)
        let hostClass = try Class(descriptor: hostDescriptor, in: machOFile)
        let methodImplementationOffsets = hostClass.methodDescriptors
            .filter { $0.flags.kind == .method }
            .compactMap(\.implementationOffset)
        let distinctOffsets = Set(methodImplementationOffsets)
        #expect(methodImplementationOffsets.count == 3, "fixture should contribute three plain vtable methods")
        return try #require(
            distinctOffsets.count == 1 ? distinctOffsets.first : nil,
            """
            the fixture's empty method bodies did NOT fold onto one address \
            (found \(distinctOffsets.count) distinct: \(distinctOffsets.sorted().map { String($0, radix: 16) })). \
            This suite cannot test attribution ambiguity without the folding — \
            check that the toolchain's linker still honours `-deduplicate`.
            """
        )
    }

    /// Every folded slot keeps ITS OWN member, in declaration order.
    ///
    /// The pre-fix output for exactly this fixture was `beta` / `alpha` /
    /// `gamma` — the symbol table's order at the folded address, not the
    /// vtable's.
    @Test func foldedSlotsKeepTheirOwnMembers() async throws {
        let machOFile = try loadFixtureMachOFile()
        _ = try foldedImplementationAddress(in: machOFile)

        let hostDescriptor = try classDescriptor(named: "Host", in: machOFile)
        let slots = try await vtableSlots(inDumpOf: hostDescriptor, in: machOFile)
        let methodSlots = slots.filter { $0.declaration.contains("func ") }

        #expect(methodSlots.map(\.slot) == methodSlots.map(\.slot).sorted(), "slots must be emitted in slot order")
        #expect(
            methodSlots.map(\.declaration) == [
                "func VTableAttributionFixture.Host.alpha() -> ()",
                "func VTableAttributionFixture.Host.beta() -> ()",
                "func VTableAttributionFixture.Host.gamma() -> ()",
            ],
            "folded slots must be attributed by their own `Tq` symbols, in declaration order; got \(methodSlots)"
        )
    }

    /// A nested type's member never surfaces as a slot of the enclosing class,
    /// even though it folded onto the same address and its demangled tree's
    /// first class node IS the enclosing class.
    ///
    /// DEFENSIVE, not a reproduction: this passes on the pre-fix code too.
    /// Whether a nested member is actually mis-attributed depends on where the
    /// linker happens to place it in the symbol table relative to the enclosing
    /// class's own members — here `Host`'s three members are listed first and
    /// exhaust the slots before `nestedNoop` is reached. Attempts to force the
    /// unfavourable order in a fixture this size did not reproduce it. The
    /// live reproduction is `GraphHostVTableAttributionTests`, where three
    /// slots really did print `GraphHost.Data`'s resume functions.
    @Test func nestedTypeMembersNeverOccupyTheEnclosingClassVTable() async throws {
        let machOFile = try loadFixtureMachOFile()
        _ = try foldedImplementationAddress(in: machOFile)

        let hostDescriptor = try classDescriptor(named: "Host", in: machOFile)
        let slots = try await vtableSlots(inDumpOf: hostDescriptor, in: machOFile)

        #expect(
            !slots.contains { $0.declaration.contains("nestedNoop") },
            "a nested type's folded member must not be attributed to the enclosing class; got \(slots)"
        )
    }

    /// The nested class's own vtable is attributed to the nested class — the
    /// counterpart to the test above, so "drop everything ambiguous" cannot
    /// pass both. Defensive in the same sense: it also passes pre-fix.
    @Test func nestedClassKeepsItsOwnVTableMember() async throws {
        let machOFile = try loadFixtureMachOFile()
        _ = try foldedImplementationAddress(in: machOFile)

        let nestedDescriptor = try classDescriptor(named: "Nested", in: machOFile)
        let slots = try await vtableSlots(inDumpOf: nestedDescriptor, in: machOFile)

        #expect(
            slots.contains { $0.declaration == "func VTableAttributionFixture.Host.Nested.nestedNoop() -> ()" },
            "the nested class's own folded member must still be attributed to it; got \(slots)"
        )
    }
}

/// The reported case, pinned end to end against the real binary: `dump`ing
/// `SwiftUI.GraphHost` from an iOS 18.5 simulator runtime's SwiftUICore.
///
/// Its four empty vtable methods fold onto `0x9330`, an address carrying 2878
/// symbols, and three of the four slots used to print coroutine resume
/// functions of the nested `GraphHost.Data` struct. Slots 20–22 are a second
/// fact worth pinning: their implementation pointers are null (the class
/// metadata binds them to `swift_deletedMethodError`), so they are ABI
/// tombstones rather than members.
///
/// Environment-gated: skipped wherever no simulator runtime ships SwiftUICore.
/// Where the gated suite below finds its binary.
///
/// Deliberately a separate type: a `@Suite(.enabled(if:))` condition that reads
/// a static of the suite it decorates is a circular macro reference and does
/// not compile.
enum SimulatorRuntimeSwiftUICore {
    /// The first SwiftUICore an installed simulator runtime provides. The
    /// runtime volumes are versioned per install (`iOS_22F77`, …), so the path
    /// is discovered rather than written down.
    static let url: URL? = {
        let fileManager = FileManager.default
        let runtimeSearchRoots = [
            "/Library/Developer/CoreSimulator/Volumes",
            "/Library/Developer/CoreSimulator/Profiles/Runtimes",
        ]
        let frameworkSuffix = "Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
        for searchRoot in runtimeSearchRoots {
            guard let enumerator = try? fileManager.contentsOfDirectory(atPath: searchRoot) else { continue }
            for entry in enumerator.sorted() {
                let entryURL = URL(fileURLWithPath: searchRoot).appendingPathComponent(entry)
                // A volume nests one more level: <volume>/Library/Developer/CoreSimulator/Profiles/Runtimes/<runtime>.
                let candidateRoots = [
                    entryURL,
                    entryURL.appendingPathComponent("Library/Developer/CoreSimulator/Profiles/Runtimes"),
                ]
                for candidateRoot in candidateRoots {
                    if fileManager.fileExists(atPath: candidateRoot.appendingPathComponent(frameworkSuffix).path) {
                        return candidateRoot.appendingPathComponent(frameworkSuffix)
                    }
                    guard let runtimes = try? fileManager.contentsOfDirectory(atPath: candidateRoot.path) else { continue }
                    for runtime in runtimes.sorted() {
                        let candidate = candidateRoot.appendingPathComponent(runtime).appendingPathComponent(frameworkSuffix)
                        if fileManager.fileExists(atPath: candidate.path) { return candidate }
                    }
                }
            }
        }
        return nil
    }()
}

@Suite(.serialized, .enabled(if: SimulatorRuntimeSwiftUICore.url != nil))
struct GraphHostVTableAttributionTests {
    private func graphHostDump() async throws -> String {
        let url = try #require(SimulatorRuntimeSwiftUICore.url)
        let machOFile: MachOFile
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }

        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor,
                  try classDescriptor.name(in: machOFile) == "GraphHost" else { continue }
            var configuration = DumperConfiguration.demangleOptions(.test)
            configuration.printVTableOffset = true
            let classType = try Class(descriptor: classDescriptor, in: machOFile)
            return try await classType.dump(using: configuration, in: machOFile).string
        }
        Issue.record("SwiftUICore does not contain a GraphHost class")
        return ""
    }

    /// The four folded slots, each with the member its `Tq` symbol names.
    /// Pre-fix, slot 26 printed `isHiddenForReuseDidChange` (slot 29's member)
    /// and 27–29 printed `GraphHost.Data`'s `.resume.0` functions.
    @Test func foldedSlotsMatchTheirMethodDescriptorSymbols() async throws {
        let output = try await graphHostDump()

        for (slot, member) in [
            (26, "instantiateOutputs"),
            (27, "uninstantiateOutputs"),
            (28, "timeDidChange"),
            (29, "isHiddenForReuseDidChange"),
        ] {
            #expect(
                output.contains("// VTable offset: \(slot)\n    /* [Method] */ func SwiftUI.GraphHost.\(member)() -> ()"),
                "vtable slot \(slot) must be attributed to \(member)"
            )
        }

        #expect(!output.contains("resume"), "no coroutine resume function belongs in GraphHost's vtable")
    }

    /// Slots 20–22 carry no implementation: deleted members whose slots stay
    /// for ABI stability. They must say so rather than read as ordinary
    /// members or as a bare lookup failure.
    @Test func deletedMethodSlotsAreMarkedAsTombstones() async throws {
        let output = try await graphHostDump()

        for slot in 20...22 {
            #expect(
                output.contains("// VTable offset: \(slot)\n    // No implementation in this image (deleted method — slot retained for ABI)"),
                "vtable slot \(slot) must be marked as an ABI tombstone"
            )
        }
        #expect(!output.contains("Symbol not found"), "the tombstone slots must not degrade to a bare lookup failure")
    }
}
