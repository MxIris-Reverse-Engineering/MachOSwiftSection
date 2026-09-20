import Foundation
import MachOKit
import Testing

/// An on-the-fly fixture for the `@objc @implementation` recognition tests
/// (evolution proposal `objc-implementation-class-recognition`): one ObjC
/// header declaring two classes, `Widget` implemented in Swift through
/// `@objc @implementation` and `ClangWidget` implemented in Objective-C and
/// merely EXTENDED from Swift — the negative control that passes the
/// ObjC-side gate (defined in this image, Swift bit clear) and must fail
/// every evidence tier, a hidden non-unique metadata accessor included. A
/// plain Swift class with ObjC ancestry rides along
/// as the `__DATA`-segment ballast every compiled fixture needs.
///
/// The ObjC-ancestor override recovery tests (evolution proposal
/// `objc-ancestor-override-recovery`) share the fixture: `ClangWidget` gained
/// overridable members, `DerivedImplementationWidget` overrides them from an
/// `@objc @implementation` body, `SwiftDerivedWidget` / `SwiftGrandchildWidget`
/// from ordinary Swift class bodies.
///
/// Three link/strip variants exercise the three evidence tiers:
/// - `.full`: every symbol present — accessor, field-offset globals, `To`
///   thunks at the class's own IMPs.
/// - `.strippedLocals` (`strip -x`): only the exported accessor survives,
///   the field-offset globals and thunks are gone.
/// - `.strippedEverything` (linked with an empty exported-symbols list, then
///   `strip -x`): no Swift symbol at all; only the ivar encodings remain.
package enum ObjCImplementationFixture {
    package enum Variant: String, CaseIterable, Sendable {
        case full
        case strippedLocals
        case strippedEverything
    }

    package static let moduleName = "ObjCImplementationFixture"

    package static let header = """
    #import <Foundation/Foundation.h>

    NS_ASSUME_NONNULL_BEGIN

    @interface Widget : NSObject
    @property (nonatomic, copy) NSString *title;
    @property (nonatomic) NSInteger count;
    - (instancetype)initWithTitle:(NSString *)title;
    - (void)refresh;
    @end

    @interface Widget (Extras)
    - (NSString *)describe;
    @end

    @interface ClangWidget : NSObject
    @property (nonatomic, copy) NSString *label;
    @property (nonatomic) NSInteger tally;
    @property (nonatomic) NSInteger level;
    - (void)bump;
    - (void)ping;
    + (NSInteger)pingCount;
    @end

    // Implemented in Swift through `@objc @implementation`, deriving from the
    // clang class: its `ping` / `pingCount` / `level` are overrides of
    // ObjC-inherited members, which only the ObjC method tables can show.
    @interface DerivedImplementationWidget : ClangWidget
    - (void)poke;
    @end

    NS_ASSUME_NONNULL_END
    """

    package static let objectiveCSource = """
    #import "Fixture.h"

    @implementation ClangWidget
    - (void)bump { self.tally += 1; }
    - (void)ping { self.tally += 2; }
    + (NSInteger)pingCount { return 1; }
    @end
    """

    package static let swiftSource = """
    import Foundation

    @objc @implementation extension Widget {
        var title: String
        var count: Int
        final var swiftOnlyCache: [Int] = []

        init(title: String) {
            self.title = title
            self.count = 0
            super.init()
        }

        func refresh() {
            count += 1
            swiftOnlyCache.append(count)
        }
    }

    @objc(Extras) @implementation extension Widget {
        func describe() -> String { "\\(title) x\\(count)" }
    }

    // The clang-compiled class only gets a Swift EXTENSION: a category, not
    // the class body. Must not be recognized — even though the metatype use
    // below makes this module emit a hidden, non-unique metadata accessor
    // `$sSo11ClangWidgetCMa` for the imported class (the same shape a dyld
    // cache's local symbol table carries for SwiftUICore's clang-implemented
    // `DateFormattingContext`, which misled the first version).
    extension ClangWidget {
        @objc public func swiftAdded() -> Int { Int(tally) + 1 }
        public func typeName() -> String { String(describing: ClangWidget.self) }
    }

    // Plain Swift class with ObjC ancestry: Swift bit set, never a candidate;
    // also the `__DATA`-segment ballast every on-the-fly fixture needs.
    public final class PlainSwiftSibling: NSObject {
        public var label: String = ""
        @objc public func poke() {}
    }

    // `@objc @implementation` class body deriving from the clang class
    // (evolution proposal `objc-ancestor-override-recovery`): `poke` is a
    // member implementation, the other three override ObjC-inherited members.
    @objc @implementation extension DerivedImplementationWidget {
        func poke() { bump() }
        // `public`: an override must be as accessible as the imported member.
        public override func ping() { super.ping(); bump() }
        public override class func pingCount() -> Int { super.pingCount() + 1 }
        public override var level: Int {
            get { super.level + 1 }
            set { super.level = newValue - 1 }
        }
    }

    // Plain Swift subclass of the clang class: an override of an ObjC-inherited
    // member gets a NEW vtable entry (the compiler's `NeedsNewVTableEntryRequest`
    // answers `true` when the base has a clang node), so the Swift metadata
    // alone never says `override` for `ping` / `pingCount` / `level`, nor for
    // `description` (NSObject's, in libobjc — a bind from this file, followed
    // only when the fixture is loaded in-process). `notAnOverride` is the
    // negative control; `dynamicHook` is the `@objc dynamic` base the grandchild
    // overrides with no vtable entry on either side.
    public class SwiftDerivedWidget: ClangWidget {
        public override func ping() { super.ping() }
        public override class func pingCount() -> Int { super.pingCount() + 2 }
        public override var level: Int {
            get { super.level }
            set { super.level = newValue }
        }
        public override var description: String { "SwiftDerivedWidget" }
        @objc public func notAnOverride() {}
        @objc public dynamic func dynamicHook() {}
    }

    public class SwiftGrandchildWidget: SwiftDerivedWidget {
        public override func dynamicHook() { super.dynamicHook() }
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let step: String
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture \(step) failed:\n\(diagnostics)" }
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

    /// Compiled once per process; every variant shares one working directory.
    private static let compilationResult: Result<[Variant: URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let headerURL = workingDirectory.appendingPathComponent("Fixture.h")
            let objectiveCSourceURL = workingDirectory.appendingPathComponent("ClangWidget.m")
            let objectURL = workingDirectory.appendingPathComponent("ClangWidget.o")
            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            let emptyExportsURL = workingDirectory.appendingPathComponent("empty-exports.txt")
            try header.write(to: headerURL, atomically: true, encoding: .utf8)
            try objectiveCSource.write(to: objectiveCSourceURL, atomically: true, encoding: .utf8)
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)
            try "".write(to: emptyExportsURL, atomically: true, encoding: .utf8)

            try run(step: "clang", ["clang", "-c", "-fobjc-arc", "-O", objectiveCSourceURL.path, "-o", objectURL.path])

            var libraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(variant.rawValue).dylib")
                // `-Onone` on purpose: under `-O` the optimizer inlines the clang
                // class's non-unique metadata accessor into its one use site,
                // leaving only the lazy-cache variable behind, and the negative
                // control would no longer carry the accessor SYMBOL it exists
                // to exercise. Nothing else the tests pin depends on the level.
                var arguments = [
                    "swiftc", "-emit-library", "-module-name", moduleName,
                    "-import-objc-header", headerURL.path, "-Onone",
                    swiftSourceURL.path, objectURL.path, "-framework", "Foundation",
                    "-o", libraryURL.path,
                ]
                if variant == .strippedEverything {
                    arguments += ["-Xlinker", "-exported_symbols_list", "-Xlinker", emptyExportsURL.path]
                }
                try run(step: "swiftc (\(variant.rawValue))", arguments)
                if variant != .full {
                    try run(step: "strip (\(variant.rawValue))", ["strip", "-x", libraryURL.path])
                }
                libraries[variant] = libraryURL
            }
            return libraries
        }
    }()

    private static func run(step: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CompilationError(step: step, diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    package static func libraryURL(_ variant: Variant) throws -> URL {
        let libraries = try compilationResult.get()
        guard let libraryURL = libraries[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no library for variant \(variant.rawValue)")
        }
        return libraryURL
    }

    package static func machOFile(_ variant: Variant) throws -> MachOFile {
        let libraryURL = try libraryURL(variant)
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }
}
