import Foundation
import MachOKit
import MachOSwiftSection
import Testing

/// An on-the-fly fixture for types declared inside function and closure
/// bodies (evolution proposal `local-type-context-names`).
///
/// A local type hangs off a chain of anonymous contexts — one for the type
/// itself, one per enclosing closure, one for the function — none of which
/// carries a name unless the compiler ran with
/// `-enable-anonymous-context-mangled-names`, which the driver adds only to
/// `-g -Onone` builds. The full name a reader needs comes from one of three
/// places; each of the first three variants keeps exactly one of them:
///
/// - `.debugNames`: compiled with that flag, then `strip -x` — only the
///   anonymous context descriptors' own names.
/// - `.anonymousDescriptorSymbols`: the exported and imported symbols plus
///   the anonymous descriptors' `$s<context>MXX` symbols.
/// - `.symbolicReferences`: the exported and imported symbols plus the
///   `_symbolic` ones — the shape of AppKit in the dyld shared cache, where
///   only the symbol on a field descriptor's type name spells a local type.
/// - `.unstripped`: every symbol — the shape of an unstripped release build
///   (SwiftUI in the dyld shared cache), and the one variant whose member
///   symbols survive, so members are attributed in it.
/// - `.stripped` (`strip -x`): none of them — a stripped app.
///
/// No strip option removes chosen local symbols (`strip -R` handles global
/// ones only), so the two variants that keep some are cut with
/// `strip -s <the symbols to keep>` — which accepts a local symbol only when
/// it was a private external before linking, as the `MXX` and `_symbolic`
/// ones are and the member symbols are not. Stripping invalidates the
/// linker's ad-hoc signature, which `dlopen` then refuses; every variant is
/// re-signed. Each variant has a module name of its own, so all of them can
/// be loaded into the test process at once.
package enum LocalTypeFixture {
    /// The `ExclusiveImageAccess` key every suite touching these images
    /// declares: one for all four, since a suite reads several of them.
    package static let exclusiveAccessName = "LocalTypeFixture"

    package enum Variant: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case debugNames
        case anonymousDescriptorSymbols
        case symbolicReferences
        case unstripped
        case stripped

        /// The variants that keep a source of every local type's name.
        package static let named: [Variant] = [.debugNames, .anonymousDescriptorSymbols, .symbolicReferences, .unstripped]

        package var moduleName: String {
            "LocalTypeFixture" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }

        package var testDescription: String { rawValue }
    }

    /// One shape per way a local type's context can look. Compiled `-Onone`
    /// so nothing is dead-stripped; without `-g` the driver adds no
    /// anonymous context names, which is what a release build leaves too.
    package static let swiftSource = """
    public protocol LocalTypeFixtureVisitor {
        mutating func visit(_ value: Int)
    }

    public protocol LocalTypeFixtureEntryVisitor: ~Copyable {
        mutating func visit(entry: Int) -> Bool
    }

    public struct Holder {
        public init() {}

        // Two methods each declaring a `Visitor`: SwiftUI's `TableDataSource`
        // shape, where every one of them used to demangle as `Holder.Visitor`.
        // The first is `Equatable`, so a local type also appears in the
        // parameter list of a member (`__derived_struct_equals`).
        public func countValues() -> Any {
            struct Visitor: LocalTypeFixtureVisitor, Equatable {
                var count: Int
                mutating func visit(_ value: Int) {
                    count += 1
                }
            }
            return Visitor(count: 0)
        }

        public func sumValues() -> Any {
            struct Visitor: LocalTypeFixtureVisitor {
                var sum: Int
                mutating func visit(_ value: Int) {
                    sum += value
                }
            }
            return Visitor(sum: 0)
        }

        // A private method: its private discriminator names the method, never
        // the type declared in it.
        private func hiddenValues() -> Any {
            struct Hidden {
                var value: Int
            }
            return Hidden(value: 0)
        }

        public func revealHiddenValues() -> Any {
            hiddenValues()
        }

        // A closure between the method and the type: one more anonymous context.
        public func valuesFromClosure() -> Any {
            let make = { () -> Any in
                struct InClosure {
                    var value: Int
                }
                return InClosure(value: 0)
            }
            return make()
        }

        // Two same-named types in one method: `Twin #1` and `Twin #2`.
        public func twins(_ flag: Bool) -> Any {
            if flag {
                struct Twin {
                    var first: Int
                }
                return Twin(first: 0)
            } else {
                struct Twin {
                    var second: Int
                }
                return Twin(second: 0)
            }
        }

        // An enum and a class: every nominal kind.
        public func mode(_ flag: Bool) -> Any {
            enum Mode {
                case on
                case off
            }
            return flag ? Mode.on : Mode.off
        }

        public func box() -> AnyObject {
            final class Box {
                var value = 0
            }
            return Box()
        }

        // A type nested in a local type, referenced by a field of it.
        public func nested() -> Any {
            struct Generator {
                struct Element {
                    var value: Int
                }
                var element: Element
            }
            return Generator(element: Generator.Element(value: 0))
        }

        // SwiftUI's `IndexWrappingVisitor` shape: a `~Copyable` generic
        // parameter makes the compiler name the type's members as if they
        // were declared in an extension carrying the inverse requirement
        // (`…Ri_zrlE…`).
        public func wrapping() -> Bool {
            struct WrappingGenerator {
                struct IndexWrappingVisitor<Base: LocalTypeFixtureEntryVisitor & ~Copyable>: LocalTypeFixtureEntryVisitor, ~Copyable {
                    var index: Int
                    var base: Base
                    mutating func visit(entry: Int) -> Bool {
                        index += 1
                        return base.visit(entry: entry)
                    }
                }
                struct Counter: LocalTypeFixtureEntryVisitor {
                    var count: Int
                    mutating func visit(entry: Int) -> Bool {
                        count += 1
                        return true
                    }
                }
            }
            var visitor = WrappingGenerator.IndexWrappingVisitor(index: 0, base: WrappingGenerator.Counter(count: 0))
            return visitor.visit(entry: 0)
        }

        // A generic method's opaque result type hangs off the method's own
        // anonymous context, whatever the build.
        public func opaqueValue<Value>(_ value: Value) -> some Equatable {
            0
        }

        // Conformances to standard-library protocols, whose witnesses are
        // symbols filed under the conformance — under the local type's full
        // name, its enclosing declaration included. A getter, a `static`
        // method and a throwing method each put a node of their own kind
        // into that name. `KeyTwin` and `PayloadTwin` declare the same types
        // outside any body. The getter's `Key` also has a static stored
        // property, whose storage symbol is no accessor while its name holds
        // one.
        public var keyFromGetter: Any {
            struct Key: Hashable {
                static var shared = 0
                var value: Int
            }
            Key.shared += 1
            return Key(value: Key.shared)
        }

        public static func keyFromStaticMethod() -> Any {
            struct Key: Hashable {
                var value: Int
            }
            return Key(value: 0)
        }

        // The synthesized `CodingKeys` brings initializers and properties
        // to the conformances: every member kind.
        public func payload() throws -> Any {
            struct Payload: Codable {
                var value: Int
            }
            return Payload(value: 0)
        }

        // A method with argument labels and parameters: its label list and
        // argument tuple sit in every member's name, ahead of the member's
        // own. `LookupTwin` declares the same type outside any body.
        public func lookup(named name: String, at index: Int) -> Any {
            @dynamicMemberLookup
            struct Lookup: Hashable {
                var value: Int
                subscript(dynamicMember member: String) -> Int { value }
                func combine(_ first: Int, _ second: Int, _ third: Int) -> Int { first + second + third }
            }
            return Lookup(value: index + name.count)
        }
    }

    public struct KeyTwin: Hashable {
        static var shared = 0
        var value: Int
    }

    public struct PayloadTwin: Codable {
        var value: Int
    }

    @dynamicMemberLookup
    public struct LookupTwin: Hashable {
        var value: Int
        public subscript(dynamicMember member: String) -> Int { value }
        func combine(_ first: Int, _ second: Int, _ third: Int) -> Int { first + second + third }
    }

    // A method of another module's type: an extension above the anonymous
    // contexts.
    extension String {
        public func localTypeFixtureWrapped() -> Any {
            struct Wrapper {
                var value: String
            }
            return Wrapper(value: self)
        }
    }

    // A top-level function: nothing but the module above the anonymous contexts.
    public func localTypeFixtureTopLevel() -> Any {
        struct TopLevel {
            var value: Int
        }
        return TopLevel(value: 0)
    }
    """

    /// The compiler's spelling of every type the source declares in a body,
    /// nested types of local types included, as the stock demangler prints
    /// the type descriptors' `Mn` symbols of an unstripped build
    /// (`swift-demangle -compact`) — the ground truth a name built from the
    /// descriptors is held to. `Hidden` is not listed: its method is private,
    /// and the discriminator hashes the source file's name (see
    /// `isCompilerSpelledHiddenName(_:of:)`).
    package static func compilerSpelledNames(of variant: Variant) -> [String] {
        let moduleName = variant.moduleName
        return [
            "TopLevel #1 in \(moduleName).localTypeFixtureTopLevel() -> Any",
            "Visitor #1 in \(moduleName).Holder.countValues() -> Any",
            "Visitor #1 in \(moduleName).Holder.sumValues() -> Any",
            "InClosure #1 in closure #1 () -> Any in \(moduleName).Holder.valuesFromClosure() -> Any",
            "Box #1 in \(moduleName).Holder.box() -> Swift.AnyObject",
            "Mode #1 in \(moduleName).Holder.mode(Swift.Bool) -> Any",
            "Twin #1 in \(moduleName).Holder.twins(Swift.Bool) -> Any",
            "Twin #2 in \(moduleName).Holder.twins(Swift.Bool) -> Any",
            "Generator #1 in \(moduleName).Holder.nested() -> Any",
            "Element in Generator #1 in \(moduleName).Holder.nested() -> Any",
            "WrappingGenerator #1 in \(moduleName).Holder.wrapping() -> Swift.Bool",
            "IndexWrappingVisitor in WrappingGenerator #1 in \(moduleName).Holder.wrapping() -> Swift.Bool",
            "Counter in WrappingGenerator #1 in \(moduleName).Holder.wrapping() -> Swift.Bool",
            "Wrapper #1 in (extension in \(moduleName)):Swift.String.localTypeFixtureWrapped() -> Any",
            "Key #1 in \(moduleName).Holder.keyFromGetter.getter : Any",
            "Key #1 in static \(moduleName).Holder.keyFromStaticMethod() -> Any",
            "Payload #1 in \(moduleName).Holder.payload() throws -> Any",
            "CodingKeys in Payload #1 in \(moduleName).Holder.payload() throws -> Any",
            "Lookup #1 in \(moduleName).Holder.lookup(named: Swift.String, at: Swift.Int) -> Any",
        ]
    }

    /// Whether the fixture declares the type in a body — a local type, or a
    /// type nested in one — as opposed to `Holder` and the twins.
    ///
    /// Read off the descriptors alone, so a test can pick the local types
    /// without trusting the names it checks: a local type's own anonymous
    /// context sits under its function's or closure's, while a private
    /// type's sits under a type, an extension or the module.
    package static func isDeclaredInABody(_ descriptor: ContextDescriptorWrapper, in context: some ReadingContext) throws -> Bool {
        var parent = try descriptor.parent(in: context)?.resolved
        while let currentParent = parent {
            let grandparent = try currentParent.parent(in: context)?.resolved
            if case .anonymous = currentParent, case .anonymous? = grandparent {
                return true
            }
            parent = grandparent
        }
        return false
    }

    /// `Hidden #1 in <module>.Holder.(hiddenValues in _<discriminator>)() -> Any`:
    /// the discriminator belongs to the private method, and the type's own
    /// name is a local one.
    package static func isCompilerSpelledHiddenName(_ name: String, of variant: Variant) -> Bool {
        name.hasPrefix("Hidden #1 in \(variant.moduleName).Holder.(hiddenValues in _") && name.hasSuffix(")() -> Any")
    }

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let step: String
        package let diagnostics: String
        package var description: String { "LocalTypeFixture \(step) failed:\n\(diagnostics)" }
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
                .appendingPathComponent("LocalTypeFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let swiftSourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try swiftSource.write(to: swiftSourceURL, atomically: true, encoding: .utf8)

            var libraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let libraryURL = workingDirectory.appendingPathComponent("lib\(variant.moduleName).dylib")
                // Install names are the absolute output paths, so the
                // in-process leg loads each variant with no rpath.
                var arguments = [
                    // The language mode pinned: CI's toolchain and a newer
                    // local one must compile the same source the same way.
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", variant.moduleName,
                    "-Xlinker", "-install_name", "-Xlinker", libraryURL.path,
                    swiftSourceURL.path, "-o", libraryURL.path,
                ]
                if variant == .debugNames {
                    arguments += ["-Xfrontend", "-enable-anonymous-context-mangled-names"]
                }
                _ = try run(step: "swiftc (\(variant.rawValue))", arguments)

                switch variant {
                case .debugNames,
                     .stripped:
                    _ = try run(step: "strip (\(variant.rawValue))", ["strip", "-x", libraryURL.path])
                case .anonymousDescriptorSymbols:
                    try strip(libraryURL, keepingLocalSymbolsWhere: { $0.hasSuffix("MXX") }, in: workingDirectory, variant: variant)
                case .symbolicReferences:
                    try strip(libraryURL, keepingLocalSymbolsWhere: { $0.hasPrefix("_symbolic") }, in: workingDirectory, variant: variant)
                case .unstripped:
                    break
                }
                _ = try run(step: "codesign (\(variant.rawValue))", ["codesign", "--force", "--sign", "-", libraryURL.path])
                libraries[variant] = libraryURL
            }
            return libraries
        }
    }()

    private static func symbolNames(of libraryURL: URL, globalOnly: Bool, step: String) throws -> [String] {
        let output = try run(step: step, ["nm", globalOnly ? "-gj" : "-j", libraryURL.path])
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Strips every local symbol but those `isKept` selects. The global ones
    /// stay: `-g` lists the imported symbols too, which the indirect symbol
    /// table refers to and `strip -s` refuses to drop.
    private static func strip(_ libraryURL: URL, keepingLocalSymbolsWhere isKept: (String) -> Bool, in workingDirectory: URL, variant: Variant) throws {
        let globalSymbolNames = try symbolNames(of: libraryURL, globalOnly: true, step: "nm -g (\(variant.rawValue))")
        let keptLocalSymbolNames = try symbolNames(of: libraryURL, globalOnly: false, step: "nm (\(variant.rawValue))").filter(isKept)
        let keepListURL = workingDirectory.appendingPathComponent("keep-\(variant.rawValue).txt")
        try ((globalSymbolNames + keptLocalSymbolNames).joined(separator: "\n") + "\n").write(to: keepListURL, atomically: true, encoding: .utf8)
        _ = try run(step: "strip -s (\(variant.rawValue))", ["strip", "-s", keepListURL.path, libraryURL.path])
    }

    /// Runs `xcrun <arguments>` and returns its standard output.
    @discardableResult
    private static func run(step: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        try process.run()
        // Drain both pipes BEFORE waitUntilExit, or a long output deadlocks
        // both sides; standard error on a thread of its own so neither pipe
        // can fill while the other is read.
        let standardErrorReader = PipeReader(pipe: standardErrorPipe)
        let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let diagnosticsData = standardErrorReader.waitForData()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CompilationError(step: step, diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
        return String(decoding: outputData, as: UTF8.self)
    }

    /// Reads a pipe to its end on a thread of its own.
    private final class PipeReader: @unchecked Sendable {
        private let condition = NSCondition()
        private var data: Data?

        init(pipe: Pipe) {
            Thread {
                let readData = pipe.fileHandleForReading.readDataToEndOfFile()
                self.condition.lock()
                self.data = readData
                self.condition.signal()
                self.condition.unlock()
            }.start()
        }

        func waitForData() -> Data {
            condition.lock()
            defer { condition.unlock() }
            while data == nil {
                condition.wait()
            }
            return data ?? Data()
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

    /// The variant loaded into the test process.
    package static func loadedImage(_ variant: Variant) throws -> MachOImage {
        let libraryURL = try libraryURL(variant)
        let handle = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        try #require(handle != nil, "the \(variant.rawValue) fixture did not load: \(dlerror().map { String(cString: $0) } ?? "no dlerror")")
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the \(variant.rawValue) fixture dylib did not load in-process")
    }
}
