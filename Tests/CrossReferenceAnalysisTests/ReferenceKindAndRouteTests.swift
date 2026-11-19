import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ARM64InstructionDecoding
@testable import CrossReferenceAnalysis

/// The references step 5 of the offline cross-references proposal adds —
/// instance variables, string literals, and the route each reference took —
/// read from libraries compiled for each test and from the running system's
/// shared cache.
@Suite
struct ReferenceKindAndRouteTests {
    /// An Objective-C library: a class with an instance variable, methods
    /// that send messages, a C string and two constant strings — one ASCII,
    /// one that takes UTF-16. The class's superclass lies in another image
    /// (Foundation's `NSOperation`): over `NSObject`, whose layout is fixed,
    /// clang uses constant instance variable offsets and loads no offset
    /// variable.
    private static let objectiveCSource = """
    #import <Foundation/Foundation.h>
    #include <stdio.h>
    @interface Counter : NSOperation {
    @public
        long _count;
    }
    - (void)increment;
    - (NSString *)describe;
    @end
    @implementation Counter
    - (void)increment { _count += 1; }
    - (NSString *)describe { return [NSString stringWithFormat:@"%ld", _count]; }
    @end
    __attribute__((noinline)) const char *cStringFunction(void) { return "a C string literal"; }
    __attribute__((noinline)) NSString *constantStringFunction(void) { return @"a constant string literal"; }
    __attribute__((noinline)) NSString *wideConstantStringFunction(void) { return @"h\\u00e9llo \\u2713"; }
    void callEverything(Counter *counter) {
        [counter increment];
        puts(cStringFunction());
        NSLog(@"%@ %@", constantStringFunction(), wideConstantStringFunction());
    }
    """

    private func objectiveCLibrary(stripped: Bool = false) throws -> (directory: URL, file: MachOFile) {
        let (directory, library) = try CompiledFixture.build(
            libraryName: "libKinds.dylib",
            sources: ["Kinds.m": Self.objectiveCSource],
            compilerArguments: ["-O1", "-fobjc-arc", "-framework", "Foundation"] + (stripped ? ["-Wl,-x"] : [])
        )
        return (directory, try MachOFile(url: library))
    }

    private func function(named name: String, in analyzer: CrossReferenceAnalyzer) throws -> CodeFunction {
        try #require(analyzer.functions(inImageAt: 0).first { function in
            switch function.name {
            case .symbol(let symbol)?: symbol == name
            case .objectiveCMethod(let className, let selector, let isClassMethod)?: "\(isClassMethod ? "+" : "-")[\(className) \(selector)]" == name
            default: false
            }
        }, "no function \(name)")
    }

    /// A method reads its instance variable through the class's offset
    /// variable in `__objc_ivar`, named by its `_OBJC_IVAR_$_` symbol — or,
    /// when the symbol table is stripped, by the class's instance variable
    /// list, whose entry points at the same variable.
    @Test(arguments: [false, true])
    func instanceVariableOffsetLoadsBecomeInstanceVariableReferences(stripped: Bool) throws {
        let (directory, file) = try objectiveCLibrary(stripped: stripped)
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file])
        for method in ["-[Counter increment]", "-[Counter describe]"] {
            let references = analyzer.references(madeBy: try function(named: method, in: analyzer))
            let variableReferences = references.filter { $0.target == .objectiveCInstanceVariable(className: "Counter", name: "_count") }
            #expect(variableReferences.count == 1, "\(method), stripped: \(stripped): \(references.map(\.target))")
            #expect(variableReferences.allSatisfy { $0.kind == .reference && ($0.route == .pointerSlot || $0.route == .literalLoad) })
        }
        let filed = analyzer.references(to: [.instanceVariable(className: "Counter", name: "_count")], inImageAt: 0)
        #expect(filed.count == 2)
    }

    /// Strings are recorded when the analyzer is made to, or for a query for
    /// a string key — not in a whole-image table otherwise.
    @Test func stringReferencesAreRecordedOnlyWhenRequested() throws {
        let (directory, file) = try objectiveCLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let withoutStrings = try CrossReferenceAnalyzer(machOFiles: [file])
        #expect(!withoutStrings.recordsStringReferences)
        #expect(!withoutStrings.referenceTable(ofImageAt: 0).references.contains { reference in
            switch reference.target {
            case .cString, .constantString: true
            default: false
            }
        })
        // In `cStringFunction` and, inlined, in `callEverything`.
        let queried = withoutStrings.references(to: [.cString("a C string literal")], inImageAt: 0)
        #expect(queried.count == 2)
        #expect(queried.allSatisfy { $0.route == .addressMaterialization })

        let withStrings = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let references = withStrings.references(madeBy: try function(named: "_cStringFunction", in: withStrings))
        #expect(references.map(\.target) == [.cString("a C string literal")])
    }

    /// A constant `CFString` is referenced by its characters, eight-bit or
    /// UTF-16 alike.
    @Test func constantStringReferencesCarryTheirCharacters() throws {
        let (directory, file) = try objectiveCLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let ascii = analyzer.references(madeBy: try function(named: "_constantStringFunction", in: analyzer)).map(\.target)
        #expect(ascii.contains(.constantString("a constant string literal")), "\(ascii)")
        let wide = analyzer.references(madeBy: try function(named: "_wideConstantStringFunction", in: analyzer)).map(\.target)
        #expect(wide.contains(.constantString("h\u{e9}llo \u{2713}")), "\(wide)")
        let format = analyzer.references(madeBy: try function(named: "_callEverything", in: analyzer)).map(\.target)
        #expect(format.contains(.constantString("%@ %@")), "\(format)")
    }

    /// Swift keeps a large string literal as its address less 32: `adrp`,
    /// `add` to the characters, `sub #0x20`. The `add` names the string; the
    /// subtraction names no other.
    @Test func swiftLargeStringLiteralPointsAtItsCharacters() throws {
        let (directory, library) = try CompiledFixture.buildSwift(libraryName: "libLargeString.dylib", source: """
        @inline(never) public func largeStringLiteral() -> String {
            "a string literal longer than fifteen bytes"
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: library)], recordingStringReferences: true)
        let function = try #require(analyzer.functions(inImageAt: 0).first { $0.name == .symbol("_$s7Fixture18largeStringLiteralSSyF") })
        let strings = analyzer.references(madeBy: function).filter { if case .cString = $0.target { true } else { false } }
        #expect(strings.map(\.target) == [.cString("a string literal longer than fifteen bytes")])
    }

    /// Every reference says how it got where it points: a call to a function
    /// of the library goes straight there, a call into Foundation and a send
    /// through `__objc_stubs` go through the library's own stubs, a string's
    /// address is built, an instance variable's offset is loaded through its
    /// slot.
    @Test func everyReferenceCarriesTheRouteItTook() throws {
        let (directory, file) = try objectiveCLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let references = analyzer.references(madeBy: try function(named: "_callEverything", in: analyzer))
        func route(of target: CodeReferenceTarget) -> CodeReferenceRoute? {
            references.first { $0.target == target }?.route
        }
        let constantStringFunction = try function(named: "_constantStringFunction", in: analyzer)
        #expect(route(of: .function(constantStringFunction.location)) == .direct)
        #expect(route(of: .importedSymbol(name: "_puts")) == .imageStub)
        #expect(references.first { if case .messageSend("increment", _) = $0.target { true } else { false } }?.route == .imageStub, "\(references)")
        #expect(route(of: .constantString("%@ %@")) == .addressMaterialization)
    }

    /// The process's own cache: macOS 27 sends through the selector stubs the
    /// whole cache shares, calls into its own code straight, reads classes
    /// both through slots and by building their address, and calls through
    /// registers.
    @Test(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
    func inProcessReferencesCarryTheirRoutes() throws {
        let analyzer = try #require(SharedAnalyzer.analyzer)
        let appKit = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/AppKit.framework/Versions/C/AppKit") })
        let references = analyzer.referenceTable(ofImageAt: appKit).references
        let routes = Set(references.map(\.route))
        #expect(routes.isSuperset(of: [.direct, .pointerSlot, .addressMaterialization, .indirect]), "\(routes)")
        #expect(routes.contains(.cacheSharedStub) || routes.contains(.imageStub), "\(routes)")
        for reference in references {
            switch reference.target {
            case .indirect:
                #expect(reference.route == .indirect)
            case .objectiveCClass:
                #expect([.pointerSlot, .addressMaterialization, .literalLoad].contains(reference.route) || reference.kind != .reference)
            default:
                break
            }
        }
    }

    /// The table and the index a host keeps answer the same — the new kinds
    /// and every route included.
    @Test func referenceIndexRoundTripsNewTargetsAndRoutes() throws {
        let (directory, file) = try objectiveCLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let table = analyzer.referenceTable(ofImageAt: 0)
        let index = analyzer.referenceIndex(ofImageAt: 0)
        let keys: [CodeReferenceTable.Key] = [
            .instanceVariable(className: "Counter", name: "_count"),
            .cString("a C string literal"),
            .constantString("a constant string literal"),
            .constantString("h\u{e9}llo \u{2713}"),
            .importedSymbol("_puts"),
            .selector("increment"),
        ]
        for key in keys {
            let fromTable = table.references(to: key)
            #expect(!fromTable.isEmpty, "\(key)")
            #expect(index.references(to: [key]) == fromTable, "\(key)")
        }
    }

    /// An Objective-C class object can lie exactly on a page: its address is
    /// then built by `adrp` and an `add` of 0, which is still a reference to
    /// it — a disassembler that takes the `add #0` for a move loses it.
    @Test(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
    func pageAlignedClassObjectMaterializationIsAReference() throws {
        let analyzer = try #require(SharedAnalyzer.analyzer)
        var found: CodeReference?
        let candidates = ["/SwiftUI.framework/Versions/A/SwiftUI", "/SwiftUICore.framework/Versions/A/SwiftUICore", "/AppKit.framework/Versions/C/AppKit", "/Foundation.framework/Versions/C/Foundation"]
        for suffix in candidates {
            guard let imageIndex = analyzer.imagePaths.firstIndex(where: { $0.hasSuffix(suffix) }) else { continue }
            found = analyzer.referenceTable(ofImageAt: imageIndex).references.first { reference in
                guard reference.route == .addressMaterialization, case .objectiveCClass(_, let location) = reference.target else { return false }
                return location.address & 0xFFF == 0
            }
            if found != nil { break }
        }
        let reference = try #require(found, "no page-aligned class object built by adrp / add in \(candidates)")
        // The instruction is the `add` of 0.
        let word = try #require(analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: reference.function.imageIndex, address: reference.instructionAddress))))
        let arithmetic = try #require(ARM64InstructionWord.addImmediate(word))
        #expect(arithmetic.addend == 0)
    }
}
