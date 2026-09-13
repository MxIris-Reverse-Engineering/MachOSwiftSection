import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@testable import SwiftThunkAnalysis

/// A kind-9 thunk in a file that is **not** in a dyld shared cache calls the
/// accessors of the types it needs through GOT binds — the shape every
/// third-party app and every framework of an iOS 26 or earlier simulator
/// runtime has, and the one the shared-cache measurements never exercised.
///
/// The fixture is compiled on the fly so the thunk's shape is the current
/// toolchain's, not one OS build's: a generic `~Copyable` struct holding a
/// `Mutex<Set<Element>>` gets a thunk that tests
/// `_swift_runtimeSupportsNoncopyableTypes`, reads its two arguments out of
/// the buffer, calls `Set`'s accessor in `libswiftCore` and then `Mutex`'s in
/// `libswiftSynchronization`, both through stubs onto binds. Reading it means
/// finding those two images (here: in the host's shared cache) and their
/// accessor indexes. The non-generic fields are compiled as mangled-name
/// instantiations, which already resolved before this route existed; they
/// are asserted so that stays true.
@Suite(.serialized)
struct StandaloneFileThunkResolutionTests {
    private static let installName = "/System/Library/Frameworks/ThunkProbe.framework/ThunkProbe"

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

    private struct FixtureCompilationError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "ThunkProbe fixture compilation failed:\n\(diagnostics)" }
    }

    /// The compiled dylib, placed under a fake system root at its own install
    /// name so the file's location also exercises search-path inference.
    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ThunkProbeFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let systemRoot = workingDirectory.appendingPathComponent("Root")
            let libraryURL = systemRoot.appendingPathComponent(String(installName.dropFirst()))
            try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("ThunkProbe.swift")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            // `Synchronization.Mutex` needs macOS 15; optimized so the
            // accessor thunks take the shapes a shipping binary carries.
            process.arguments = [
                "swiftc", "-O", "-emit-library", "-module-name", "ThunkProbe",
                "-target", "arm64-apple-macosx15.0",
                "-Xlinker", "-install_name", "-Xlinker", installName,
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain before waiting, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    /// A class is deliberate: a struct-only fixture dylib has no `__DATA`
    /// segment and the pinned MachOKit mis-walks its chained-fixup pages.
    private static let fixtureSource = """
    import Foundation
    import Synchronization

    public final class ProbeHolder {
        public let observed: Mutex<Set<String>>
        public let counter: Mutex<Int>
        public init() {
            observed = Mutex([])
            counter = Mutex(0)
        }
    }

    public struct ProbeGenericHolder<Element: Hashable>: ~Copyable {
        public let members: Mutex<Set<Element>>
        public init(members: consuming Mutex<Set<Element>>) { self.members = members }
    }
    """

    private func loadFixture() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    private struct ResolvedField {
        let owner: String
        let name: String
        let text: String
        let thunkOffset: Int
        let ownerLayout: AccessorThunkOwnerLayout
    }

    /// Every kind-9 field of the fixture, resolved through the same entry the
    /// dump and interface paths use — under whatever resolver the task has.
    private func resolvedAccessorFields(in machOFile: MachOFile) throws -> [ResolvedField] {
        var resolved: [ResolvedField] = []
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile) else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            let ownerName = try SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default)
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile),
                      let reference = typeNode.first(of: Node.Kind.accessorFunctionReference),
                      let thunkOffset = reference.index
                else { continue }
                let resolvedNode = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout)
                resolved.append(ResolvedField(
                    owner: ownerName,
                    name: try record.fieldName(in: machOFile),
                    text: resolvedNode.print(using: .default),
                    thunkOffset: Int(thunkOffset),
                    ownerLayout: ownerLayout
                ))
            }
        }
        return resolved
    }

    @Test func aGenericFieldWhoseThunkBindsToOtherImagesResolves() throws {
        let machOFile = try loadFixture()
        let fields = try resolvedAccessorFields(in: machOFile)
        for field in fields { print("\(field.owner).\(field.name): \(field.text) (thunk at \(field.thunkOffset))") }
        func text(of name: String) -> String? { fields.first { $0.name == name }?.text }

        // The generic field: both accessors are reached through binds
        // (`libswiftCore/_$sShMa`, `libswiftSynchronization/_$s15Synchronization5MutexVMa`).
        #expect(text(of: "members") == "Synchronization.Mutex<Swift.Set<A>>")
        // The concrete fields: mangled-name instantiations, resolved before
        // and still.
        #expect(text(of: "observed") == "Synchronization.Mutex<Swift.Set<Swift.String>>")
        #expect(text(of: "counter") == "Synchronization.Mutex<Swift.Int>")
    }

    /// Without any search path the binds have nowhere to resolve, and the
    /// honest answer is the placeholder — never a partial or wrong type.
    @Test func withoutSearchPathsTheBindsStayUnreadAndAreNamed() throws {
        let machOFile = try loadFixture()
        let fields = try AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver(searchPaths: [])) {
            try resolvedAccessorFields(in: machOFile)
        }
        let members = try #require(fields.first { $0.name == "members" })
        #expect(members.text.contains("accessor function at"), "\(members.text)")

        let resolved = try AccessorThunkReader.read(thunkAtOffset: members.thunkOffset, in: machOFile, ownerLayout: members.ownerLayout, searchPaths: [])
        #expect(resolved.underlyingTypes.isEmpty)
        let unlocatedBindNames = resolved.limitations.compactMap { limitation -> String? in
            guard case .calleeInUnlocatedImage(let bindName) = limitation else { return nil }
            return bindName
        }
        #expect(unlocatedBindNames.contains { $0.hasSuffix("$sShMa") }, "\(resolved.limitations)")
    }

    /// The fixture sits under `<root>/System/Library/Frameworks/…` at its own
    /// install name, which is what an iOS 26 or earlier simulator runtime's
    /// `RuntimeRoot` looks like — so the root is inferred without being told.
    @Test func theSystemRootIsInferredFromWhereTheFileSits() throws {
        let machOFile = try loadFixture()
        let libraryURL = try Self.fixtureCompilationResult.get()
        let expectedRoot = String(libraryURL.path.dropLast(Self.installName.count))
        #expect(DependencySearchPath.inferred(forRoot: machOFile) == [.systemRoot(path: expectedRoot)])
        #expect(MachOThunkEnvironment.defaultSearchPaths(for: machOFile) == [.systemRoot(path: expectedRoot), .systemDyldSharedCache])
    }
}
