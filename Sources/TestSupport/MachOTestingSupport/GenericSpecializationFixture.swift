import Foundation
import MachOKit
import MachOFoundation
import MachOFixtureSupport
import MachOSwiftSection
import Testing

/// An on-the-fly fixture for generic specialization, compiled once per process
/// and read two ways: as a `MachOFile` (the offline path, evolution proposal
/// `offline-generic-specialization`) and, `dlopen`ed into the test process, as
/// a `MachOImage` (the runtime path). The same binary on both sides is what
/// lets a test hold the two paths' output against each other byte for byte.
///
/// Three groups of shapes:
///
/// - **Generic parameter depths.** A depth counts only the contexts that
///   declare parameters: `DepthOuter<OuterElement>.Middle.Inner<InnerElement>`
///   puts `InnerElement` at depth 1, because `Middle` declares none, and a
///   constrained extension of `DepthOuter.SecondMiddle` spans both of
///   `DepthOuter`'s and `SecondMiddle`'s depths. Every reader that numbered
///   depths by counting generic ancestors got both wrong.
/// - **Offline/runtime parity.** One of every shape the offline specializer
///   prints: struct, class (with a generic superclass), single- and
///   multi-payload enums, an associated-type field, nested types that inherit
///   or add parameters, a private type, a type nested in another module's
///   extension, and a host for `.boundGeneric` arguments.
/// - **Constraint checks.** One type per requirement kind the offline
///   preflight checks, with conforming and non-conforming arguments beside.
package enum GenericSpecializationFixture {
    package static let moduleName = "GenericSpecializationFixture"

    package static let source = """
    // Ballast: a struct-only dylib has no `__DATA` segment, and MachOKit before
    // 0.52.103 mis-walked such a dylib's chained-fixup pages.
    public final class FixtureAnchor {}

    // MARK: - Generic parameter depths

    public struct DepthOuter<OuterElement> {
        // Generic only because it is nested in `DepthOuter`: it declares no
        // parameter, so it opens no depth.
        public struct Middle {
            public var outerElement: OuterElement

            public struct Inner<InnerElement: Hashable> {
                public var outerElement: OuterElement
                public var innerElement: InnerElement
            }

            // `Inner` without the requirement: its accessor takes no witness
            // table, so a test can instantiate it directly.
            public struct PlainInner<InnerElement> {
                public var outerElement: OuterElement
                public var innerElement: InnerElement
            }
        }

        public struct SecondMiddle<MiddleElement> {
            public var middleElement: MiddleElement
        }
    }

    // `OuterElement` is pinned, so it takes no key argument; `InnerElement`
    // is at depth 1.
    extension DepthOuter where OuterElement == Int {
        public struct ConstrainedInner<InnerElement> {
            public var outerElement: OuterElement
            public var innerElement: InnerElement
        }
    }

    // `Second` is tied to `First`, so it takes no key argument: the compiler
    // writes the requirement as `First == Second`, the parameter that keeps
    // its key argument on the left, and the instantiation binds `Second` to
    // `First`'s argument. A warning in the fixture's Swift 5 mode.
    public struct TiedParameterPair<First, Second> where First == Second {
        public var first: First
        public var second: Second
    }

    // The extension's parameters span two depths, `DepthOuter`'s and
    // `SecondMiddle`'s, so `InnerElement` is at depth 2.
    extension DepthOuter.SecondMiddle where OuterElement == Int {
        public struct DeepConstrainedInner<InnerElement: Hashable> {
            public var middleElement: MiddleElement
            public var innerElement: InnerElement
        }
    }

    // Fields whose types are instantiations of the shapes above. A field
    // naming `DeepConstrainedInner` is left out: its mangled name does not
    // demangle (a separate, older problem).
    public struct DepthHolder {
        public var inner: DepthOuter<Int>.Middle.Inner<String>
        public var constrained: DepthOuter<Int>.ConstrainedInner<String>
        public var trailing: Int
    }

    // MARK: - Offline/runtime parity

    public struct PairBox<First, Second> {
        public var first: First
        public var second: Second
        public var count: Int
    }

    public final class ReferenceBox<Element> {
        public var element: Element
        public var flag: Bool

        public init(element: Element, flag: Bool) {
            self.element = element
            self.flag = flag
        }
    }

    open class BaseBox<Element> {
        public var base: Element

        public init(base: Element) {
            self.base = base
        }
    }

    public final class DerivedBox<Element>: BaseBox<Element> {
        public var extra: Int8 = 0
    }

    public enum SingleChoice<Payload> {
        case value(Payload)
        case empty
        case other
    }

    public enum MultiChoice<Left, Right> {
        case left(Left)
        case right(Right)
        case neither
    }

    public struct ElementsHolder<Elements: Collection> {
        public var elements: Elements
        public var first: Elements.Element?
    }

    // A non-generic holder of an instantiation whose field is a member of
    // the argument: the static walk names it `[Swift.Int].Element` unless it
    // projects the member through `Array`'s conformance.
    public struct ElementsHolderHolder {
        public var holder: ElementsHolder<[Int]>
    }

    public struct NestedHost<Key: Hashable> {
        public var key: Key

        public struct Plain {
            public var key: Key
        }

        public struct Pair<Value> {
            public var key: Key
            public var value: Value
        }
    }

    private struct PrivateBox<Element> {
        var element: Element
        var count: Int
    }

    extension Int {
        public struct IntExtensionBox<Element> {
            public var element: Element
        }
    }

    // MARK: - Constraint checks

    public struct ClassBound<Object: AnyObject> {
        public var object: Object
    }

    open class ConstraintBase {
        public init() {}
    }

    public final class ConstraintSubclass: ConstraintBase {}

    public final class ConstraintUnrelated {
        public init() {}
    }

    public struct BaseClassBound<Subject: ConstraintBase> {
        public var subject: Subject
    }

    public protocol FixtureMarker {}

    public struct FixtureMarked: FixtureMarker {
        public var value: Int
    }

    public struct FixtureUnmarked {
        public var value: Int
    }

    public struct ProtocolBound<Subject: FixtureMarker> {
        public var subject: Subject
    }

    public struct ElementSameType<Elements: Sequence> where Elements.Element == Int {
        public var elements: Elements
    }

    public struct ElementHashable<Elements: Sequence> where Elements.Element: Hashable {
        public var elements: Elements
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture compilation failed:\n\(diagnostics)" }
    }

    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private static let compilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                // The language mode pinned: CI's toolchain and a newer local one
                // must compile the same source the same way. `-Onone` keeps the
                // private type, which nothing references.
                "swiftc", "-swift-version", "5", "-Onone", "-emit-library",
                "-module-name", moduleName,
                // The absolute output path as the install name, so the
                // in-process leg loads with no rpath.
                "-Xlinker", "-install_name", "-Xlinker", libraryURL.path,
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    package static func libraryURL() throws -> URL {
        try compilationResult.get()
    }

    /// The fixture read from disk — what the offline path sees.
    package static func machOFile() throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: libraryURL()) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The fixture loaded into the test process — what the runtime path sees.
    package static func loadedImage() throws -> MachOImage {
        let libraryURL = try libraryURL()
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }

    /// The descriptor of the fixture type whose own (unqualified) name is
    /// `name`. Every fixture type name is unique, so the bare name is enough.
    package static func typeContextDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeContextDescriptorWrapper {
        for descriptor in try machO.swift.typeContextDescriptors where try descriptor.namedContextDescriptor.name(in: machO.context) == name {
            return descriptor
        }
        throw CompilationError(diagnostics: "the fixture declares no type named \(name)")
    }

    /// The running system's `libswiftCore`, read from its dyld shared cache:
    /// the offline indexer's sub-indexer for the standard library's
    /// protocols and conformances.
    package static func systemStandardLibraryFile() throws -> MachOFile {
        let cache = try DyldCache(url: URL(fileURLWithPath: DyldSharedCachePath.current.rawValue))
        return try #require(cache.machOFile(by: .name("libswiftCore")), "libswiftCore not found in the running system's dyld shared cache")
    }
}
