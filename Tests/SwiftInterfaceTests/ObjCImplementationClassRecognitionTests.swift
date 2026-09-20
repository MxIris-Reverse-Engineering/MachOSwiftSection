import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftDeclaration
import SwiftInterface
import SwiftInspection
@_spi(Internals) import MachOSymbols
@testable import MachOTestingSupport

/// `@objc @implementation` recognition on the interface path (evolution
/// proposal `objc-implementation-class-recognition`), over the on-the-fly
/// fixture's three link/strip variants — one per evidence tier — plus the
/// negative controls: a clang-compiled class that a Swift extension merely
/// adds to, and a plain Swift class with ObjC ancestry.
@Suite(.serialized)
struct ObjCImplementationClassRecognitionTests {
    private func interface(of variant: ObjCImplementationFixture.Variant, printFieldOffset: Bool = false) async throws -> String {
        let machOFile = try ObjCImplementationFixture.machOFile(variant)
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printFieldOffset = printFieldOffset
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func block(named header: String, in interface: String) -> String? {
        guard let headerRange = interface.range(of: header) else { return nil }
        let rest = interface[headerRange.lowerBound...]
        guard let end = rest.range(of: "\n}\n") else { return String(rest) }
        return String(rest[..<end.upperBound])
    }

    // MARK: - Definitive tier: every symbol present

    @Test func fullFixtureRendersTheClassBodyWithStoredProperties() async throws {
        let interface = try await interface(of: .full)
        let widget = try #require(block(named: "@objc @implementation extension __C.Widget {", in: interface))
        // Stored properties render as storage, not as the `{ get set }` shape
        // their accessor symbols alone suggest.
        #expect(widget.contains("@objc var title: Swift.String\n"))
        #expect(widget.contains("@objc var count: Swift.Int\n"))
        #expect(widget.contains("var swiftOnlyCache: [Swift.Int]\n"))
        #expect(!widget.contains("var title: Swift.String {"))
        // Members carry the `@objc` their `To` thunks prove; the Swift-only
        // `final var` has no thunk and stays bare.
        #expect(widget.contains("@objc init(title: Swift.String)"))
        #expect(widget.contains("@objc func refresh()"))
        #expect(widget.contains("@objc func describe() -> Swift.String"))
        #expect(!widget.contains("@objc var swiftOnlyCache"))
        // Definitive: no inference marker.
        #expect(!widget.contains("inferred from ObjC class data"))
    }

    @Test func fieldOffsetCommentsComeFromTheObjCIvarList() async throws {
        let interface = try await interface(of: .full, printFieldOffset: true)
        let widget = try #require(block(named: "@objc @implementation extension __C.Widget {", in: interface))
        #expect(widget.contains("// Field offset: 0x8\n    @objc var title: Swift.String"))
        #expect(widget.contains("// Field offset: 0x18\n    @objc var count: Swift.Int"))
        #expect(widget.contains("// Field offset: 0x20\n    var swiftOnlyCache: [Swift.Int]"))
    }

    @Test func negativeControlsStayPlainExtensionsOrClasses() async throws {
        let interface = try await interface(of: .full)
        // The clang-compiled class passes the ObjC-side gate but hits no tier.
        #expect(interface.contains("\nextension __C.ClangWidget {"))
        #expect(!interface.contains("@objc @implementation extension __C.ClangWidget"))
        #expect(interface.contains("@objc func swiftAdded() -> Swift.Int"))
        // A Swift class with ObjC ancestry has the Swift bit set: never a candidate.
        #expect(interface.contains("class PlainSwiftSibling: __C.NSObject {"))
        #expect(!interface.contains("@implementation extension __C.PlainSwiftSibling"))
        // A plain extension of an imported class in the same image is a category.
        #expect(!interface.contains("@implementation extension __C.NSObject"))
    }

    // MARK: - Definitive tier on the exported accessor alone

    @Test func strippedLocalsStillRecognizeThroughTheExportedAccessor() async throws {
        let interface = try await interface(of: .strippedLocals)
        let widget = try #require(block(named: "@objc @implementation extension __C.Widget {", in: interface))
        #expect(!widget.contains("inferred from ObjC class data"))
        // No field-offset symbol survived, so the ivars render as honest
        // comments — ObjC facts, no fabricated Swift type.
        #expect(widget.contains("// stored property title: Swift type not recoverable (ObjC ivar, offset 0x8, size 16, encoding \"?\")"))
        #expect(widget.contains("// stored property count: Swift type not recoverable (ObjC ivar, offset 0x18, size 8, encoding \"q\")"))
        #expect(widget.contains("// stored property swiftOnlyCache: Swift type not recoverable (ObjC ivar, offset 0x20, size 8, encoding \"\")"))
    }

    // MARK: - Inferred tier: no Swift symbol at all

    @Test func fullyStrippedImageIsRecognizedFromIvarEncodingsAndSaysSo() async throws {
        let interface = try await interface(of: .strippedEverything)
        // The class has no member symbol left, so the extension is synthesized
        // from the ObjC side alone — and labelled as an inference.
        let widget = try #require(block(named: "@objc @implementation /* inferred from ObjC class data: 2 ivars carry Swift-style type encodings */ extension __C.Widget {", in: interface))
        #expect(widget.contains("// stored property title: Swift type not recoverable"))
        #expect(widget.contains("// stored property swiftOnlyCache: Swift type not recoverable"))
        // The clang class has complete encodings and no Swift symbols: silent
        // (it still appears as the SUPERCLASS of the fixture's Swift subclasses).
        #expect(!interface.contains("extension __C.ClangWidget"))
    }

    // MARK: - The facts behind the rendering

    @Test func factsCarryTheEvidenceAndTheOffsetJoin() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let facts = try #require(ObjCImplementationClasses.facts(forClassNamed: "Widget", in: machOFile))
        guard case .definitive(let reasons) = facts.evidence else {
            Issue.record("expected a definitive recognition, got \(facts.evidence)")
            return
        }
        #expect(reasons.contains(.metadataAccessorSymbol(name: "_$sSo6WidgetCMa")))
        #expect(reasons.contains(.fieldOffsetSymbols(count: 3)))
        #expect(reasons.contains { if case .swiftSymbolsAtMethodImplementations = $0 { return true } else { return false } })
        #expect(facts.implementingModuleName == ObjCImplementationFixture.moduleName)
        #expect(facts.superclassName == "NSObject")
        #expect(facts.instanceVariables.count == 3)
        // The header-declared property's ivar carries an EMPTY name in this
        // fixture; the join through the field-offset global's value still
        // pairs it with `title`.
        let title = try #require(facts.instanceVariable(forSwiftPropertyNamed: "title"))
        #expect(title.offset == 8)
        #expect(title.size == 16)
        #expect(title.typeEncoding == "?")
        #expect(title.swiftFieldOffsetSymbolName == "_$sSo6WidgetC11ImplFixtureE5titleSSvpWvd".replacingOccurrences(of: "11ImplFixture", with: "\(ObjCImplementationFixture.moduleName.count)\(ObjCImplementationFixture.moduleName)"))
        let swiftOnlyCache = try #require(facts.instanceVariable(forSwiftPropertyNamed: "swiftOnlyCache"))
        #expect(swiftOnlyCache.typeEncoding.isEmpty)
        #expect(!swiftOnlyCache.isObjCVisible)
        // The class's own method list is the Swift `To` thunks.
        let initWithTitle = try #require(facts.instanceMethods.first { $0.selector == "initWithTitle:" })
        #expect(initWithTitle.implementationSymbolNames.contains { $0.hasSuffix("tcfcTo") })
        #expect(facts.instanceMethods.contains { $0.selector == ".cxx_destruct" })
        #expect(facts.properties.map(\.name).sorted() == ["count", "title"])

        #expect(ObjCImplementationClasses.facts(forClassNamed: "ClangWidget", in: machOFile) == nil)
        // Two `@implementation` bodies: `Widget` and the override-recovery
        // fixture's `DerivedImplementationWidget`.
        #expect(Set(ObjCImplementationClasses.all(in: machOFile).map(\.className)) == ["Widget", "DerivedImplementationWidget"])
    }

    /// An imported ObjC class has `PublicNonUnique` linkage, so any module
    /// that needs its metadata emits a hidden non-unique accessor of its
    /// own; only the implementing module's public unique accessor reaches
    /// the export trie. The first version took any accessor in the symbol
    /// table as proof and recognized SwiftUICore's clang-implemented
    /// `DateFormattingContext` (caught by the rendering A/B).
    @Test func aHiddenNonUniqueAccessorIsNotEvidence() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let symbolIndexStore = SymbolIndexStore.shared
        // The premise: the fixture really does carry the clang class's accessor,
        // and it really is not exported.
        #expect(symbolIndexStore.containsSymbol(named: "_$sSo11ClangWidgetCMa", in: machOFile), "the fixture no longer emits the non-unique accessor the test is about")
        #expect(symbolIndexStore.isExported(name: "_$sSo11ClangWidgetCMa", in: machOFile) == false)
        #expect(symbolIndexStore.isExported(name: "_$sSo6WidgetCMa", in: machOFile) == true)
        #expect(ObjCImplementationClasses.facts(forClassNamed: "ClangWidget", in: machOFile) == nil)
    }

    @Test func fullyStrippedFactsAreInferred() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.strippedEverything)
        let facts = try #require(ObjCImplementationClasses.facts(forClassNamed: "Widget", in: machOFile))
        #expect(facts.evidence == .inferred(swiftStyleEncodedInstanceVariableCount: 2))
        #expect(facts.instanceVariables.allSatisfy { $0.swiftFieldOffsetSymbolName == nil })
        #expect(ObjCImplementationClasses.facts(forClassNamed: "ClangWidget", in: machOFile) == nil)
    }

    @Test func recognitionIsReportedAsAnEvent() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let collector = SwiftIndexEventCollector()
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [collector], in: machOFile)
        try await builder.prepare()
        let recognized = collector.events.compactMap { event -> SwiftIndexEvents.ObjCImplementationClassContext? in
            guard case .objcImplementationClassRecognized(let context) = event else { return nil }
            return context
        }
        #expect(Set(recognized.map(\.className)) == ["Widget", "DerivedImplementationWidget"])
        let widget = try #require(recognized.first { $0.className == "Widget" })
        #expect(widget.isInferred == false)
        #expect(widget.instanceVariableCount == 3)
        // Informational, not a failure: it must not reach the zero-handler floor.
        #expect(SwiftIndexEvents.Payload.objcImplementationClassRecognized(context: recognized[0]).unhandledFailureDescription == nil)
        #expect(SwiftIndexEvents.Payload.objcImplementationClassSkipped(className: "X", reason: "unreadable").unhandledFailureDescription != nil)
    }
}

/// The real thing: macOS 26's AppKit implements NSGlassEffectView (and a few
/// dozen other classes, NSScreen and NSGradient among them) through
/// `@objc @implementation`. Gated on the running system carrying that AppKit.
@Suite(.serialized)
struct AppKitObjCImplementationClassTests {
    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "NSGlassEffectView ships with macOS 26")) func appKitGlassEffectViewIsDefinitive() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
        let facts = try #require(ObjCImplementationClasses.facts(forClassNamed: "NSGlassEffectView", in: machOFile))
        guard case .definitive(let reasons) = facts.evidence else {
            Issue.record("expected a definitive recognition, got \(facts.evidence)")
            return
        }
        #expect(reasons.contains(.metadataAccessorSymbol(name: "_$sSo17NSGlassEffectViewCMa")))
        #expect(reasons.contains { if case .fieldOffsetSymbols(let count) = $0 { return count >= 9 } else { return false } })
        #expect(facts.implementingModuleName == "AppKit")
        #expect(facts.superclassName == "NSView")
        let scrimState = try #require(facts.instanceVariable(forSwiftPropertyNamed: "_scrimState"))
        #expect(scrimState.swiftTypeNode != nil)
        #expect(scrimState.typeEncoding == "q")
        // Rewritten AppKit classes, and two that predate Swift.
        for className in ["NSScreen", "NSGradient", "NSScene", "NSBackgroundExtensionView"] {
            #expect(ObjCImplementationClasses.facts(forClassNamed: className, in: machOFile) != nil, "\(className) should be recognized")
        }
        // A clang class with Swift extensions in the same image: the gate
        // passes, no tier does.
        #expect(ObjCImplementationClasses.facts(forClassNamed: "NSView", in: machOFile) == nil)
        #expect(ObjCImplementationClasses.facts(forClassNamed: "NSWindow", in: machOFile) == nil)
        #expect(ObjCImplementationClasses.all(in: machOFile).count >= 30)
    }
}
