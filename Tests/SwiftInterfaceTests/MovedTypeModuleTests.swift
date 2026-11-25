import Foundation
import Testing
import MachOKit
import MachOSwiftSection
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import Semantic
import SwiftSectionFixtureSupport

/// Evolution proposal `moved-swift-type-modules`: a Swift type the SDK moved
/// between modules (`@_originallyDefinedIn`) mangles under the module it was
/// originally defined in, and prints under the module a
/// `MovedTypeModuleResolving` resolver names — nested types with it.
///
/// The resolver here is a table, so no SDK is involved: `CGFloat` moves from
/// CoreGraphics to CoreFoundation as the SDK says, and the fixture's own
/// `Outer` and `Drawable` move to a module named `NewHome`.
@Suite
struct MovedTypeModuleTests {
    private static let fixtureModuleName = "MovedTypeModuleFixture"

    /// The class is ballast: a struct-only fixture dylib has no `__DATA`
    /// segment and MachOKit before 0.52.103 mis-walked its chained-fixup pages.
    private static let source = """
    import Foundation

    public final class FixtureAnchor {}

    public struct Outer {
        public struct Inner {
            public init() {}
        }
        public init() {}
    }

    public protocol Drawable {}

    extension Drawable {
        public func draw() {}
    }

    public struct Holder {
        public var width: CGFloat
        public var inner: Outer.Inner
        public var drawable: any Drawable
        public var name: NSString
        public init(width: CGFloat, inner: Outer.Inner, drawable: any Drawable, name: NSString) {
            self.width = width
            self.inner = inner
            self.drawable = drawable
            self.name = name
        }
    }

    extension CGFloat {
        public var doubled: CGFloat { self * 2 }
    }
    """

    private static func libraryURL() throws -> URL {
        try FixtureCompiler.shared.dynamicLibrary(
            named: fixtureModuleName,
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "MovedTypeModuleFixture.swift", contents: source)],
            arguments: ["-swift-version", "5", "-O", "-target", "arm64-apple-macosx15.0"]
        )
    }

    /// Answers from a table and records every question.
    private final class RecordingMovedTypeResolver: MovedTypeModuleResolving, @unchecked Sendable {
        struct Question: Hashable {
            let typeName: String
            let originalModuleName: String
        }

        private let lock = NSLock()
        private var recordedQuestions: Set<Question> = []
        private let declaringModuleNames: [Question: String]

        init(declaringModuleNames: [Question: String]) {
            self.declaringModuleNames = declaringModuleNames
        }

        var questions: Set<Question> {
            lock.withLock { recordedQuestions }
        }

        func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String) async -> String? {
            let question = Question(typeName: typeName, originalModuleName: originalModuleName)
            lock.withLock { _ = recordedQuestions.insert(question) }
            return declaringModuleNames[question]
        }
    }

    private static func makeResolver() -> RecordingMovedTypeResolver {
        RecordingMovedTypeResolver(declaringModuleNames: [
            .init(typeName: "CGFloat", originalModuleName: "CoreGraphics"): "CoreFoundation",
            .init(typeName: "Outer", originalModuleName: fixtureModuleName): "NewHome",
            .init(typeName: "Drawable", originalModuleName: fixtureModuleName): "NewHome",
        ])
    }

    private func buildInterface(usesModuleSelectors: Bool = false, resolver: RecordingMovedTypeResolver?) async throws -> String {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.usesModuleSelectors = usesModuleSelectors
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration = printConfiguration
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: HostSlice.machOFile(at: Self.libraryURL()))
        if let resolver {
            builder.printer.addTypeNameResolver(resolver)
        }
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func lines(of interface: String, startingWith prefix: String) -> [String] {
        interface.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix(prefix) }
    }

    @Test
    func movedTopLevelTypePrintsUnderItsDeclaringModule() async throws {
        let interface = try await buildInterface(resolver: Self.makeResolver())
        #expect(lines(of: interface, startingWith: "var width:") == ["var width: CoreFoundation.CGFloat"])
        #expect(!interface.contains("CoreGraphics.CGFloat"), "\(interface)")
    }

    @Test
    func nestedTypeFollowsItsOutermostType() async throws {
        let interface = try await buildInterface(resolver: Self.makeResolver())
        #expect(lines(of: interface, startingWith: "var inner:") == ["var inner: NewHome.Outer.Inner"])
    }

    /// With module selectors a nested type writes its own, which is the
    /// outermost type's declaring module too.
    @Test
    func moduleSelectorsSpellTheDeclaringModuleOnNestedTypes() async throws {
        let interface = try await buildInterface(usesModuleSelectors: true, resolver: Self.makeResolver())
        #expect(lines(of: interface, startingWith: "var inner:") == ["var inner: NewHome::Outer.NewHome::Inner"])
        #expect(lines(of: interface, startingWith: "var width:") == ["var width: CoreFoundation::CGFloat"])
    }

    @Test
    func extensionHeaderOfAMovedProtocolUsesTheDeclaringModule() async throws {
        let interface = try await buildInterface(resolver: Self.makeResolver())
        #expect(lines(of: interface, startingWith: "extension NewHome.Drawable").count == 1, "\(interface)")
        #expect(lines(of: interface, startingWith: "extension CoreFoundation.CGFloat").count == 1, "\(interface)")
        #expect(lines(of: interface, startingWith: "var drawable:") == ["var drawable: any NewHome.Drawable"])
    }

    @Test
    func cImportedModulesAreNeverAskedAboutMoves() async throws {
        let resolver = Self.makeResolver()
        _ = try await buildInterface(resolver: resolver)
        let askedModules = Set(resolver.questions.map(\.originalModuleName))
        #expect(!askedModules.contains("__C"))
        #expect(!askedModules.contains("__ObjC"))
        #expect(askedModules.contains("CoreGraphics"))
    }

    @Test
    func withoutAResolverTheManglingModuleIsKept() async throws {
        let interface = try await buildInterface(resolver: nil)
        #expect(lines(of: interface, startingWith: "var width:") == ["var width: CoreGraphics.CGFloat"])
        #expect(lines(of: interface, startingWith: "var inner:") == ["var inner: \(Self.fixtureModuleName).Outer.Inner"])
    }

    /// The original module re-exports the one declaring the type now, so the
    /// imports the binary's symbols name still compile the rewritten names.
    @Test
    func importLinesKeepTheManglingModules() async throws {
        let rewrittenInterface = try await buildInterface(resolver: Self.makeResolver())
        let unresolvedInterface = try await buildInterface(resolver: nil)
        #expect(lines(of: rewrittenInterface, startingWith: "import ") == lines(of: unresolvedInterface, startingWith: "import "))
    }
}
