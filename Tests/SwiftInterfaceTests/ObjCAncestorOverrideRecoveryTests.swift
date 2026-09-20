import Foundation
import Testing
import Demangling
import MachOKit
import MachOFoundation
import ObjCDump
import ObjCIndexing
import ObjCMetadataSource
import SwiftDeclaration
import SwiftIndexing
import SwiftInterface
import SwiftInspection
import SwiftThunkAnalysis
@testable import MachOTestingSupport

/// `override` of ObjC-inherited members recovered from the ObjC method tables
/// (evolution proposal `objc-ancestor-override-recovery`), over the shared
/// `@objc @implementation` fixture: a clang class with overridable members,
/// an `@implementation` subclass and two plain Swift subclasses overriding
/// them, plus the negative controls.
@Suite(.serialized)
struct ObjCAncestorOverrideRecoveryTests {
    private func interface(of machOFile: MachOFile) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func interface(of machOImage: MachOImage) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOImage)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The block whose header line STARTS with `prefix` (the superclass
    /// spelling after the colon is not what these tests are about).
    private func block(startingWith prefix: String, in interface: String) -> String? {
        var lines = interface.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        lines = lines[start...]
        guard let end = lines.firstIndex(where: { $0 == "}" }) else { return lines.joined(separator: "\n") }
        return lines[start...end].joined(separator: "\n")
    }

    private static var swiftDerivedWidgetRuntimeName: String {
        "_TtC\(ObjCImplementationFixture.moduleName.count)\(ObjCImplementationFixture.moduleName)18SwiftDerivedWidget"
    }

    // MARK: - Interface

    @Test func swiftSubclassOverridesOfClangMembersAreMarked() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.full))
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget {", in: interface))
        #expect(derived.contains("override func ping()"))
        // `override static` is not Swift: an overriding type-level member prints `class`.
        #expect(derived.contains("override class func pingCount() -> Swift.Int"))
        #expect(!derived.contains("static func pingCount"))
        #expect(derived.contains("override var level: Swift.Int"))
        // A same-class `@objc` member whose selector no ancestor implements.
        #expect(derived.contains("func notAnOverride()"))
        #expect(!derived.contains("override func notAnOverride()"))
        #expect(!derived.contains("override func dynamicHook()"))
        // NSObject's `description` lives in libobjc: from the FILE the clang
        // class's superclass is a bind with nothing behind it, so the chain
        // stops at `ClangWidget` and the fact is honestly absent.
        #expect(derived.contains("var description: Swift.String"))
        #expect(!derived.contains("override var description"))
    }

    @Test func overrideOfAnObjCDynamicSwiftMemberIsMarked() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.full))
        let grandchild = try #require(block(startingWith: "class SwiftGrandchildWidget:", in: interface))
        // The base is `@objc dynamic` — no vtable entry on either side — so
        // the ObjC method tables are the only evidence here too.
        #expect(grandchild.contains("override func dynamicHook()"))
    }

    @Test func implementationClassOverridesAreMarked() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.full))
        let implementation = try #require(block(startingWith: "@objc @implementation extension __C.DerivedImplementationWidget {", in: interface))
        #expect(implementation.contains("override func ping()"))
        #expect(implementation.contains("override class func pingCount() -> Swift.Int"))
        #expect(implementation.contains("override var level: Swift.Int"))
        // The member implementation of a header-declared method is not an override.
        #expect(implementation.contains("@objc func poke()"))
        #expect(!implementation.contains("override func poke()"))
    }

    /// In-process every superclass pointer is real, so the chain runs through
    /// libobjc's `NSObject` and the `description` override is provable.
    @Test func inProcessImageFollowsTheChainIntoTheRuntime() async throws {
        let libraryURL = try ObjCImplementationFixture.libraryURL(.full)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        let machOImage = try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
        let interface = try await interface(of: machOImage)
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget {", in: interface))
        #expect(derived.contains("override var description: Swift.String"))
        #expect(derived.contains("override func ping()"))
        #expect(!derived.contains("override func notAnOverride()"))
    }

    // MARK: - The facts behind the rendering

    @Test func tablesJoinThroughToThunksAndReportTheChain() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)

        let implementation = try #require(ObjCAncestorOverrides.table(forObjCClassNamed: "DerivedImplementationWidget", in: machOFile))
        #expect(implementation.hierarchy.ancestors.map(\.className) == ["ClangWidget"])
        #expect(implementation.hierarchy.isAncestorChainComplete == false)
        #expect(implementation.hierarchy.unresolvedAncestorName == "NSObject")
        #expect(implementation.overridesByImplementationSymbolName.keys.allSatisfy { $0.hasSuffix("To") })
        let implementationSelectors = Set(implementation.overridesByImplementationSymbolName.values.map(\.selector))
        #expect(implementationSelectors == ["ping", "pingCount", "level", "setLevel:"])
        #expect(implementation.overridesByImplementationSymbolName.values.allSatisfy { $0.ancestorClassName == "ClangWidget" })
        let pingCount = try #require(implementation.overridesByImplementationSymbolName.values.first { $0.selector == "pingCount" })
        #expect(pingCount.isClassMethod)
        #expect(pingCount.description == "+[ClangWidget pingCount]")

        let swiftDerived = try #require(ObjCAncestorOverrides.table(forSwiftClassQualifiedName: "\(ObjCImplementationFixture.moduleName).SwiftDerivedWidget", in: machOFile))
        #expect(Set(swiftDerived.overridesByImplementationSymbolName.values.map(\.selector)) == ["ping", "pingCount", "level", "setLevel:"])
        #expect(swiftDerived.hierarchy.methods.contains { $0.selector == "description" })

        // A Swift class with `@objc` members none of which override: a table
        // with nothing in it, not a missing table.
        let sibling = try #require(ObjCAncestorOverrides.table(forSwiftClassQualifiedName: "\(ObjCImplementationFixture.moduleName).PlainSwiftSibling", in: machOFile))
        #expect(sibling.isEmpty)
        #expect(ObjCAncestorOverrides.table(forSwiftClassQualifiedName: "\(ObjCImplementationFixture.moduleName).NoSuchClass", in: machOFile) == nil)
        #expect(ObjCAncestorOverrides.table(forObjCClassNamed: "NSObject", in: machOFile) == nil)
    }

    // MARK: - The provider seam

    /// A host that already indexed the ObjC side hands its class groups in;
    /// the recovery must consult them and reach the same verdicts the
    /// library's own reader does.
    @Test func registeredProviderIsConsultedAndAgreesWithTheReader() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let baseline = try await interface(of: machOFile)

        let objcIndexer = ObjCInterfaceIndexer(machO: machOFile, imagePath: machOFile.imagePath)
        try await objcIndexer.prepare()
        let spy = SpyingProvider(wrapping: ObjCInterfaceIndexerClassHierarchyProvider(indexer: objcIndexer))
        ObjCClassHierarchyProviderStore.shared.register(spy, for: machOFile)
        defer { ObjCClassHierarchyProviderStore.shared.remove(for: machOFile) }
        #expect(ObjCClassHierarchyProviderStore.shared.provider(for: machOFile) === spy)

        let withProvider = try await interface(of: machOFile)
        #expect(withProvider == baseline)
        #expect(spy.queriedNames.contains(Self.swiftDerivedWidgetRuntimeName))
        #expect(spy.queriedNames.contains("DerivedImplementationWidget"))
        #expect(spy.answeredNames.contains(Self.swiftDerivedWidgetRuntimeName))
        #expect(spy.answeredNames.contains("DerivedImplementationWidget"))

        // The adapter's own view of the chain: the ObjC indexer stops at the
        // bound superclass exactly where the library's reader does.
        let hierarchy = try #require(spy.objcClassHierarchy(forClassNamed: "DerivedImplementationWidget"))
        #expect(hierarchy.ancestors.map(\.className) == ["ClangWidget"])
        #expect(hierarchy.isAncestorChainComplete == false)
        #expect(hierarchy.methods.contains { $0.selector == "ping" && !$0.isClassMethod })
    }

    @Test func registrationIsWeak() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        var provider: SpyingProvider? = SpyingProvider(wrapping: EmptyProvider())
        ObjCClassHierarchyProviderStore.shared.register(provider!, for: machOFile)
        #expect(ObjCClassHierarchyProviderStore.shared.provider(for: machOFile) != nil)
        provider = nil
        #expect(ObjCClassHierarchyProviderStore.shared.provider(for: machOFile) == nil)
    }

    @Test func memberShapesFollowTheImporterSpelling() throws {
        let viewWillMove = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE12viewWillMove8toWindowySo8NSWindowCSg_tF")))
        #expect(viewWillMove.kind == .method(baseName: "viewWillMove", labels: ["toWindow"], arity: 1))
        #expect(viewWillMove.ownerQualifiedName == "__C.NSGlassEffectView")
        #expect(!viewWillMove.isStatic)
        #expect(viewWillMove.isConsistent(withSelector: "viewWillMoveToWindow:", isClassMethod: false))
        #expect(!viewWillMove.isConsistent(withSelector: "viewWillMoveToSuperview:", isClassMethod: false))
        #expect(!viewWillMove.isConsistent(withSelector: "viewWillMoveToWindow:", isClassMethod: true))
        #expect(!viewWillMove.isConsistent(withSelector: "viewWillMoveToWindow:with:", isClassMethod: false))

        let layout = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE6layoutyyF")))
        #expect(layout.kind == .method(baseName: "layout", labels: [], arity: 0))
        #expect(layout.isConsistent(withSelector: "layout", isClassMethod: false))
        #expect(!layout.isConsistent(withSelector: "layoutSubtreeIfNeeded", isClassMethod: false))

        let setter = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE13clipsToBoundsSbvs")))
        #expect(setter.kind == .setter(propertyName: "clipsToBounds"))
        #expect(setter.isConsistent(withSelector: "setClipsToBounds:", isClassMethod: false))
        #expect(!setter.isConsistent(withSelector: "clipsToBounds", isClassMethod: false))
        let getter = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE13clipsToBoundsSbvg")))
        #expect(getter.kind == .getter(propertyName: "clipsToBounds"))
        #expect(getter.isConsistent(withSelector: "clipsToBounds", isClassMethod: false))
        #expect(!getter.isConsistent(withSelector: "setClipsToBounds:", isClassMethod: false))

        let classMethod = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE16defaultAnimation6forKeyypSgSS_tFZ")))
        #expect(classMethod.isStatic)
        #expect(classMethod.isConsistent(withSelector: "defaultAnimationForKey:", isClassMethod: true))
        #expect(!classMethod.isConsistent(withSelector: "defaultAnimationForKey:", isClassMethod: false))

        let initializer = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE5coderABSgSo7NSCoderC_tcfc")))
        #expect(initializer.kind == .initializer(labels: ["coder"], arity: 1))
        #expect(initializer.isConsistent(withSelector: "initWithCoder:", isClassMethod: false))
        #expect(!initializer.isConsistent(withSelector: "initWithFrame:", isClassMethod: false))

        // Shapes the importer produces by dropping words: the check follows
        // the selector forward, never the name backward.
        let encode = ObjCMemberShape(kind: .method(baseName: "encode", labels: ["with"], arity: 1), isStatic: false, ownerQualifiedName: nil)
        #expect(encode.isConsistent(withSelector: "encodeWithCoder:", isClassMethod: false))
        #expect(!encode.isConsistent(withSelector: "encodeRestorableStateWithCoder:", isClassMethod: false))
        let unlabelled = ObjCMemberShape(kind: .method(baseName: "addSubview", labels: [], arity: 1), isStatic: false, ownerQualifiedName: nil)
        #expect(unlabelled.isConsistent(withSelector: "addSubview:", isClassMethod: false))
        let twoArguments = ObjCMemberShape(kind: .method(baseName: "insertText", labels: [nil, "replacementRange"], arity: 2), isStatic: false, ownerQualifiedName: nil)
        #expect(twoArguments.isConsistent(withSelector: "insertText:replacementRange:", isClassMethod: false))
        #expect(!twoArguments.isConsistent(withSelector: "insertText:range:", isClassMethod: false))
        let booleanSetter = ObjCMemberShape(kind: .setter(propertyName: "isEnabled"), isStatic: false, ownerQualifiedName: nil)
        #expect(booleanSetter.isConsistent(withSelector: "setEnabled:", isClassMethod: false))
        #expect(booleanSetter.isConsistent(withSelector: "setIsEnabled:", isClassMethod: false))

        // Not a member entry point at all.
        #expect(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewCMa")) == nil)
    }

    @Test func nameInferenceAttributesOnlyAUniqueCandidate() {
        let hierarchy = ObjCClassHierarchy(className: "X", methods: [], ancestors: [], isAncestorChainComplete: true)
        let table = ObjCAncestorOverrideTable(
            hierarchy: hierarchy,
            overridesByImplementationSymbolName: [:],
            unattributedOverriddenMethods: [
                .init(selector: "viewDidHide", isClassMethod: false, ancestorClassName: "NSView"),
                .init(selector: "layoutWithFoo:", isClassMethod: false, ancestorClassName: "NSView"),
            ]
        )
        let shapes: [(key: String, shape: ObjCMemberShape)] = [
            ("hide", ObjCMemberShape(kind: .method(baseName: "viewDidHide", labels: [], arity: 0), isStatic: false, ownerQualifiedName: nil)),
            ("first", ObjCMemberShape(kind: .method(baseName: "layoutWith", labels: ["foo"], arity: 1), isStatic: false, ownerQualifiedName: nil)),
            ("second", ObjCMemberShape(kind: .method(baseName: "layoutWith", labels: ["foo"], arity: 1), isStatic: false, ownerQualifiedName: nil)),
        ]
        let inferred = table.inferredOverrides(forMemberShapes: shapes)
        #expect(inferred.keys.sorted() == ["hide"])
        #expect(inferred["hide"] == ObjCAncestorOverride(selector: "viewDidHide", isClassMethod: false, ancestorClassName: "NSView", evidence: .selectorName))
    }

    @Test func hierarchyFromClassInfoChainMapsMethodsAndAncestors() {
        let child = ObjCClassInfo(
            name: "Child", version: 0, imageName: nil, instanceSize: 8, superClassName: "Parent",
            protocols: [], ivars: [], classProperties: [], properties: [],
            classMethods: [ObjCMethodInfo(name: "make", typeEncoding: "@16@0:8", isClassMethod: true, imp: 0x2000)],
            methods: [ObjCMethodInfo(name: "ping", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x1000), ObjCMethodInfo(name: "noImplementation", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0)]
        )
        let parent = ObjCClassInfo(
            name: "Parent", version: 0, imageName: nil, instanceSize: 8, superClassName: nil,
            protocols: [], ivars: [], classProperties: [], properties: [],
            classMethods: [ObjCMethodInfo(name: "make", typeEncoding: "@16@0:8", isClassMethod: true, imp: 0x3000)],
            methods: [ObjCMethodInfo(name: "ping", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x4000)]
        )
        let hierarchy = ObjCClassHierarchy(classInfoChain: [child, parent], isAncestorChainComplete: true)
        #expect(hierarchy.className == "Child")
        #expect(hierarchy.methods == [
            .init(selector: "ping", isClassMethod: false, implementation: .address(0x1000)),
            .init(selector: "noImplementation", isClassMethod: false, implementation: nil),
            .init(selector: "make", isClassMethod: true, implementation: .address(0x2000)),
        ])
        #expect(hierarchy.ancestors.map(\.className) == ["Parent"])
        #expect(hierarchy.ancestorDeclaring(selector: "ping", isClassMethod: false)?.className == "Parent")
        #expect(hierarchy.ancestorDeclaring(selector: "make", isClassMethod: true)?.className == "Parent")
        #expect(hierarchy.ancestorDeclaring(selector: "make", isClassMethod: false) == nil)
        #expect(hierarchy.ancestorDeclaring(selector: "noImplementation", isClassMethod: false) == nil)

        let broken = ObjCClassHierarchy(classInfoChain: [child], isAncestorChainComplete: false)
        #expect(broken.unresolvedAncestorName == "Parent")
        #expect(broken.ancestors.isEmpty)
    }
}

/// Records what the recovery asked a provider and what the provider knew.
private final class SpyingProvider: ObjCClassHierarchyProviding, @unchecked Sendable {
    private let wrapped: any ObjCClassHierarchyProviding
    private let lock = NSLock()
    private var queried: [String] = []
    private var answered: [String] = []

    init(wrapping wrapped: any ObjCClassHierarchyProviding) {
        self.wrapped = wrapped
    }

    var queriedNames: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(queried)
    }

    var answeredNames: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(answered)
    }

    func objcClassHierarchy(forClassNamed runtimeName: String) -> ObjCClassHierarchy? {
        let hierarchy = wrapped.objcClassHierarchy(forClassNamed: runtimeName)
        lock.lock()
        defer { lock.unlock() }
        queried.append(runtimeName)
        if hierarchy != nil {
            answered.append(runtimeName)
        }
        return hierarchy
    }
}

private final class EmptyProvider: ObjCClassHierarchyProviding {
    func objcClassHierarchy(forClassNamed runtimeName: String) -> ObjCClassHierarchy? { nil }
}

/// The real thing: macOS 26's AppKit implements `NSGlassEffectView` through
/// `@objc @implementation`, overriding a dozen NSView members Apple's source
/// spells `override`. Gated on the running system carrying that AppKit.
@Suite(.serialized)
struct AppKitObjCAncestorOverrideTests {
    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "NSGlassEffectView ships with macOS 26")) func glassEffectViewOverridesResolveAgainstNSView() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
        let table = try #require(ObjCAncestorOverrides.table(forObjCClassNamed: "NSGlassEffectView", in: machOFile))
        // The chain crosses into libobjc inside the cache and reaches the root.
        #expect(table.hierarchy.ancestors.map(\.className) == ["NSView", "NSResponder", "NSObject"])
        #expect(table.hierarchy.isAncestorChainComplete)
        let overrides = Array(table.overridesByImplementationSymbolName.values)
        let selectors = Set(overrides.map(\.selector))
        // The OS build strips the `To` thunk symbols, so every attribution
        // comes from decoding the anonymous thunk: a `bl` to the
        // implementation (`layout`, `initWithCoder:`, `setClipsToBounds:`,
        // `viewWillMoveToWindow:`, `didChangeValueForKey:`) or the
        // implementation's address materialized for an outlined helper
        // (`+defaultAnimationForKey:`).
        #expect(selectors.isSuperset(of: ["layout", "viewWillMoveToWindow:", "initWithCoder:", "setClipsToBounds:", "didChangeValueForKey:", "defaultAnimationForKey:"]))
        #expect(overrides.allSatisfy { $0.evidence == .thunkReference })
        // NSView overrides `didChangeValueForKey:` itself, so the nearest
        // ancestor is NSView, not NSObject.
        #expect(overrides.first { $0.selector == "didChangeValueForKey:" }?.ancestorClassName == "NSView")
        let defaultAnimation = try #require(overrides.first { $0.selector == "defaultAnimationForKey:" })
        #expect(defaultAnimation.isClassMethod)
        #expect(defaultAnimation.ancestorClassName == "NSView")
        // Every key is one of the class's own Swift implementations.
        #expect(table.overridesByImplementationSymbolName.keys.allSatisfy { $0.contains("So17NSGlassEffectViewC") && !$0.hasSuffix("To") })
        // Bodies the optimizer inlined (`clipsToBounds`'s getter is a bare
        // `super` call through `objc_msgSendSuper`, `viewDidHide` an
        // outlined one) reference no Swift symbol: reported, never guessed.
        let unattributed = Set(table.unattributedOverriddenMethods.map(\.selector))
        #expect(unattributed.contains("clipsToBounds"))
        #expect(unattributed.contains("viewDidHide"))
        #expect(unattributed.isDisjoint(with: selectors))
    }
}
