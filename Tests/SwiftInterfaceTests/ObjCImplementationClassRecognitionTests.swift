import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftDeclaration
import SwiftInterface
import SwiftInspection
import SwiftObjCInterop
import Semantic
@_spi(Internals) import SwiftSymbols
@testable import SwiftSectionTestingSupport
import SwiftPrinting
import SwiftSectionFixtureSupport
import OutputTransformer
import ObjCOutputTransformer

/// `@objc @implementation` recognition on the interface path (evolution
/// proposal `objc-implementation-class-recognition`), over the on-the-fly
/// fixture's three link/strip variants — one per evidence tier — plus the
/// negative controls: a clang-compiled class that a Swift extension merely
/// adds to, and a plain Swift class with ObjC ancestry.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct ObjCImplementationClassRecognitionTests {
    private func interface(of variant: ObjCImplementationFixture.Variant, printFieldOffset: Bool = false, configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) async throws -> String {
        try await printInterface(of: variant, printFieldOffset: printFieldOffset, marksCommentStructure: false, configure: configure).string
    }

    private func printInterface(of variant: ObjCImplementationFixture.Variant, printFieldOffset: Bool, marksCommentStructure: Bool, configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) async throws -> SemanticString {
        let machOFile = try ObjCImplementationFixture.machOFile(variant)
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printFieldOffset = printFieldOffset
        configuration.printConfiguration.marksCommentStructure = marksCommentStructure
        configure(&configuration.printConfiguration)
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot()
    }

    /// The notes of a recognized `@objc @implementation` — inferred
    /// evidence, an ivar's unrecoverable type — and its ivars' field offsets
    /// are marked like every other comment (evolution proposal
    /// `comment-structure`).
    @Test(arguments: ObjCImplementationFixture.Variant.allCases)
    func markingCommentStructureKeepsTheContract(variant: ObjCImplementationFixture.Variant) async throws {
        let marked = try await printInterface(of: variant, printFieldOffset: true, marksCommentStructure: true).frozen()
        let plain = try await printInterface(of: variant, printFieldOffset: true, marksCommentStructure: false).frozen()
        let violation = CommentStructureContract.violation(marked: marked, unmarked: plain)
        #expect(violation == nil, "\(violation ?? "")")
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
        // A `private` property and a `lazy var`'s storage: their field-offset
        // symbols name the variable through a `privateDeclName`. Both render as
        // storage as well — the lazy one folded onto its property with the
        // getter's type, as a Swift type's own lazy field is.
        #expect(widget.contains("var hiddenTally: Swift.Int\n"))
        #expect(widget.contains("lazy var summary: Swift.String\n"))
        #expect(!widget.contains("var summary: Swift.String {"))
        #expect(!widget.contains("$__lazy_storage_$_"))
        #expect(!widget.contains("stored property"))
        // Definitive: no inference marker.
        #expect(!widget.contains("inferred from ObjC class data"))
    }

    @Test func fieldOffsetCommentsComeFromTheObjCIvarList() async throws {
        let interface = try await interface(of: .full, printFieldOffset: true)
        let widget = try #require(block(named: "@objc @implementation extension __C.Widget {", in: interface))
        #expect(widget.contains("// Field offset: 0x8\n    @objc var title: Swift.String"))
        #expect(widget.contains("// Field offset: 0x18\n    @objc var count: Swift.Int"))
        #expect(widget.contains("// Field offset: 0x20\n    var swiftOnlyCache: [Swift.Int]"))
        #expect(widget.contains("// Field offset: 0x28\n    var hiddenTally: Swift.Int"))
        #expect(widget.contains("// Field offset: 0x30\n    lazy var summary: Swift.String"))
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
        // No field-offset symbol survived. The Objective-C side still gives
        // the types of the `@objc` ones (evolution proposal
        // `objc-ivar-type-recovery`): a complete encoding is the type itself,
        // a `?` one the bridged form of its Objective-C property. The others
        // render as honest comments — ObjC facts, no fabricated Swift type.
        #expect(widget.contains("    var title: Swift.String!\n"))
        #expect(!widget.contains("stored property title"))
        #expect(widget.contains("    var count: Swift.Int\n"))
        #expect(!widget.contains("stored property count"))
        #expect(widget.contains("// stored property swiftOnlyCache: Swift type not recoverable (ObjC ivar, offset 0x20, size 8, encoding \"\")"))
        #expect(widget.contains("// stored property hiddenTally: Swift type not recoverable (ObjC ivar, offset 0x28, size 8, encoding \"\")"))
        #expect(widget.contains("// stored property $__lazy_storage_$_summary: Swift type not recoverable (ObjC ivar, offset 0x30, size 16, encoding \"\")"))
    }

    // MARK: - Stored property types the Objective-C side gives

    // Evolution proposal `objc-ivar-type-recovery`: `AdaptiveTransitionWidget`'s
    // members are internal, so `strip -x` leaves only its ivar list and
    // Objective-C properties.

    private func adaptiveTransitionWidget(of variant: ObjCImplementationFixture.Variant, configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) async throws -> String {
        let interface = try await interface(of: variant, configure: configure)
        // The fully stripped variant's header carries the inferred evidence
        // between `@implementation` and `extension`.
        return try #require(block(named: "extension __C.AdaptiveTransitionWidget {", in: interface))
    }

    /// What follows `var <name>: ` or `let <name>: ` on its line in `block`.
    private func declaredType(of propertyName: String, in block: String) -> String? {
        for line in block.split(separator: "\n") {
            for introducer in ["var ", "let "] {
                guard let range = line.range(of: "\(introducer)\(propertyName): ") else { continue }
                return String(line[range.upperBound...])
            }
        }
        return nil
    }

    @Test func strippedClassTypedIvarsRecoverTheClassImplicitlyUnwrapped() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("    var containerView: __C.NSObject!\n"), "\(widget)")
        // `NSMutableString` is no class Swift bridges.
        #expect(widget.contains("    var buffer: __C.NSMutableString!\n"), "\(widget)")
        #expect(!widget.contains("stored property containerView"))
    }

    @Test func strippedProtocolTypedIvarRecoversTheExistentialImplicitlyUnwrapped() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("    var previousLayout: (any __C.AdaptiveLayout)!\n"), "\(widget)")
    }

    @Test func strippedScalarIvarsRecoverTheTypesTheirEncodingsName() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("    var isAnimated: Swift.Bool\n"), "\(widget)")
        // `CGFloat` and `Double` encode alike; with no C type replacement the
        // encoding's own type prints.
        #expect(widget.contains("    var interactiveProgress: Swift.Double\n"), "\(widget)")
        #expect(widget.contains("    var stepCount: Swift.Int\n"), "\(widget)")
        // A structure prints as the field-offset symbol spells it.
        let full = try await adaptiveTransitionWidget(of: .full)
        let structureType = try #require(declaredType(of: "selectedRange", in: full))
        #expect(declaredType(of: "selectedRange", in: widget) == structureType, "\(widget)")
    }

    @Test func readOnlyObjCPropertyRecoversAsALet() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("    let revision: Swift.Int\n"), "\(widget)")
    }

    @Test func bridgedIvarsRecoverTheImportedTypeOfTheirObjCProperty() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        // `readonly` over stored storage: a `let`.
        #expect(widget.contains("    let identifier: Swift.String!\n"), "\(widget)")
        // The `T` attribute names no element type.
        #expect(widget.contains("    var names: [Any]!\n"), "\(widget)")
        #expect(widget.contains("    var payload: Any!\n"), "\(widget)")
        #expect(!widget.contains("stored property identifier"))
    }

    @Test func weakObjCPropertyRecoversAsAWeakOptionalOfItsClass() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("    weak var observer: __C.NSObject?\n"), "\(widget)")
    }

    @Test func cTypeReplacementsSpellARecoveredPrimitiveType() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals) { configuration in
            configuration.cTypeReplacements = [.double: "CGFloat", .longLong: "NSInteger"]
        }
        #expect(widget.contains("    var interactiveProgress: CGFloat\n"), "\(widget)")
        #expect(widget.contains("    var stepCount: NSInteger\n"), "\(widget)")
        // Only a primitive type is replaced.
        #expect(widget.contains("    var isAnimated: Swift.Bool\n"), "\(widget)")
    }

    @Test func objcTransformersInstallTheirCTypeReplacementsOnlyWhenEnabled() async throws {
        let enabled = try await adaptiveTransitionWidget(of: .strippedLocals) { configuration in
            configuration.applyTransformers(Transformer.ObjCConfiguration(cType: .init(isEnabled: true, replacements: [.double: "CGFloat", .longLong: ""])))
        }
        #expect(enabled.contains("    var interactiveProgress: CGFloat\n"), "\(enabled)")
        // An empty spelling replaces nothing.
        #expect(enabled.contains("    var stepCount: Swift.Int\n"), "\(enabled)")
        let disabled = try await adaptiveTransitionWidget(of: .strippedLocals) { configuration in
            configuration.cTypeReplacements = [.double: "Float64"]
            configuration.applyTransformers(Transformer.ObjCConfiguration(cType: .init(isEnabled: false, replacements: [.double: "CGFloat"])))
        }
        #expect(disabled.contains("    var interactiveProgress: Swift.Double\n"), "\(disabled)")
    }

    @Test func ivarWithNoEncodingStaysAComment() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedLocals)
        #expect(widget.contains("// stored property transitionAnimations: Swift type not recoverable (ObjC ivar, offset 0x"), "\(widget)")
        #expect(!widget.contains("var transitionAnimations"))
    }

    @Test func recoveredTypesHoldWithEveryObjCImplementationSymbolGone() async throws {
        let widget = try await adaptiveTransitionWidget(of: .strippedEverything)
        #expect(widget.contains("    var containerView: __C.NSObject!\n"), "\(widget)")
        #expect(widget.contains("    var isAnimated: Swift.Bool\n"), "\(widget)")
    }

    // MARK: - Inferred tier: no Swift symbol at all

    @Test func fullyStrippedImageIsRecognizedFromIvarEncodingsAndSaysSo() async throws {
        let interface = try await interface(of: .strippedEverything)
        // The class has no member symbol left, so the extension is synthesized
        // from the ObjC side alone — and labelled as an inference.
        let widget = try #require(block(named: "@objc @implementation /* inferred from ObjC class data: 4 ivars carry Swift-style type encodings */ extension __C.Widget {", in: interface))
        #expect(widget.contains("    var title: Swift.String!\n"))
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
        #expect(reasons.contains(.fieldOffsetSymbols(count: 5)))
        #expect(reasons.contains { if case .swiftSymbolsAtMethodImplementations = $0 { return true } else { return false } })
        #expect(facts.implementingModuleName == ObjCImplementationFixture.moduleName)
        #expect(facts.superclassName == "NSObject")
        #expect(facts.instanceVariables.count == 5)
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
        // A `private` property's field-offset symbol names the variable through
        // a `privateDeclName`, and so does a `lazy var`'s storage.
        let hiddenTally = try #require(facts.instanceVariable(forSwiftPropertyNamed: "hiddenTally"))
        #expect(hiddenTally.offset == 0x28)
        #expect(hiddenTally.swiftTypeNode != nil)
        #expect(hiddenTally.swiftFieldOffsetSymbolName?.contains("11hiddenTally33_") == true)
        let summaryStorage = try #require(facts.instanceVariable(forSwiftPropertyNamed: "$__lazy_storage_$_summary"))
        #expect(summaryStorage.offset == 0x30)
        #expect(summaryStorage.size == 16)
        #expect(summaryStorage.swiftTypeNode != nil)
        // The storage answers for the `lazy var` it belongs to.
        #expect(summaryStorage.lazyPropertyName == "summary")
        #expect(hiddenTally.lazyPropertyName == nil)
        #expect(facts.storageInstanceVariable(forPropertyNamed: "summary") === summaryStorage)
        #expect(facts.storageInstanceVariable(forPropertyNamed: "title") === title)
        // The class's own method list is the Swift `To` thunks.
        let initWithTitle = try #require(facts.instanceMethods.first { $0.selector == "initWithTitle:" })
        #expect(initWithTitle.implementationSymbolNames.contains { $0.hasSuffix("tcfcTo") })
        #expect(facts.instanceMethods.contains { $0.selector == ".cxx_destruct" })
        #expect(facts.properties.map(\.name).sorted() == ["count", "title"])

        #expect(ObjCImplementationClasses.facts(forClassNamed: "ClangWidget", in: machOFile) == nil)
        // Four `@implementation` bodies: `Widget`, the override-recovery
        // fixture's `DerivedImplementationWidget`, the imported
        // declarations' `ScenePresentationWidget` and the ivar type
        // recovery's `AdaptiveTransitionWidget`.
        #expect(Set(ObjCImplementationClasses.all(in: machOFile).map(\.className)) == ["Widget", "DerivedImplementationWidget", "ScenePresentationWidget", "AdaptiveTransitionWidget"])
    }

    /// An imported ObjC class has `PublicNonUnique` linkage, so any module
    /// that needs its metadata emits a hidden non-unique accessor of its
    /// own; only the implementing module's public unique accessor reaches
    /// the export trie. The first version took any accessor in the symbol
    /// table as proof and recognized SwiftUICore's clang-implemented
    /// `DateFormattingContext` (caught by the rendering A/B).
    @Test func aHiddenNonUniqueAccessorIsNotEvidence() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let symbolIndexStore = SwiftSymbolIndexStore.shared
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
        #expect(facts.evidence == .inferred(swiftStyleEncodedInstanceVariableCount: 4))
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
        #expect(Set(recognized.map(\.className)) == ["Widget", "DerivedImplementationWidget", "ScenePresentationWidget", "AdaptiveTransitionWidget"])
        let widget = try #require(recognized.first { $0.className == "Widget" })
        #expect(widget.isInferred == false)
        #expect(widget.instanceVariableCount == 5)
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
        let cache = try #require(FullDyldCache.cachedHost, "no host dyld shared cache").mainCache
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
