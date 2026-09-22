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

/// The ObjC member recovery over the shared `@objc @implementation` fixture
/// (evolution proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`): a clang class with overridable members,
/// an `@implementation` subclass and two plain Swift subclasses overriding
/// them, `@objc` members with derived and explicit selectors, an `@objc`
/// protocol's witnesses, a category — plus the negative controls, and the
/// stripped variant every OS framework is.
///
/// From a standalone FILE the clang class's superclass is a bind; the
/// image's `ObjCAncestorResolver` follows it into the running system's dyld
/// shared cache (evolution proposal `objc-ancestor-dependency-closure`), so
/// the file leg reaches libobjc's `NSObject` like the in-process leg does,
/// and the categories of the files in the closure — the fixture's separately
/// shipped category dylib — complete the ancestors' selector sets. The
/// fixture's search paths (`ObjCImplementationFixture.dependencySearchPaths()`)
/// name that dylib; the tests that need the chain to STOP at the bind
/// install a resolver over no images — the behavior of a file whose
/// dependencies are nowhere to be found — and remove it after. Every suite
/// touching the fixture holds `ExclusiveImageAccess`, since a registration
/// is per image.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
struct ObjCMemberRecoveryTests {
    private func interface(of machOFile: MachOFile, dependencySearchPaths: [DependencySearchPath]? = nil, infersObjCOverridesFromSelectorNames: Bool = false) async throws -> String {
        let configuration = SwiftInterfaceBuilderConfiguration(indexConfiguration: .init(
            dependencySearchPaths: try dependencySearchPaths ?? ObjCImplementationFixture.dependencySearchPaths(),
            infersObjCOverridesFromSelectorNames: infersObjCOverridesFromSelectorNames
        ))
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// Runs `body` with `machOFile`'s ancestor resolver replaced by one over
    /// no images, and the store cleared afterwards so the next test gets
    /// the default again.
    private func withoutDependencyImages<Result>(for machOFile: MachOFile, _ body: () async throws -> Result) async rethrows -> Result {
        ObjCAncestorResolverStore.shared.register(.empty, for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        return try await body()
    }

    /// Runs `body` with a resolver over the fixture's whole world — the
    /// category dylib and the host's cache — the same paths the interface
    /// helper configures, for the direct table queries.
    private func withFixtureWorld<Result>(for machOFile: MachOFile, _ body: () async throws -> Result) async throws -> Result {
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: try ObjCImplementationFixture.dependencySearchPaths()), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        return try await body()
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

    private static var moduleName: String { ObjCImplementationFixture.moduleName }

    /// The `.full` fixture loaded in-process: every superclass pointer and
    /// protocol is real there, so inheritance can be ruled out and explicit
    /// selectors judged with no resolver involved — the reference the file
    /// leg, resolving its bound `NSObject` through the host's cache, must
    /// agree with.
    private func loadedFixtureImage() throws -> MachOImage {
        let libraryURL = try ObjCImplementationFixture.libraryURL(.full)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }

    private static var swiftDerivedWidgetRuntimeName: String {
        "_TtC\(moduleName.count)\(moduleName)18SwiftDerivedWidget"
    }

    // MARK: - Interface: `override`

    @Test func swiftSubclassOverridesOfClangMembersAreMarked() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.full))
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override func ping()"))
        // `override static` is not Swift: an overriding type-level member prints `class`.
        #expect(derived.contains("override class func pingCount() -> Swift.Int"))
        #expect(!derived.contains("static func pingCount"))
        #expect(derived.contains("override var level: Swift.Int"))
        // A same-class `@objc` member whose selector no ancestor implements.
        #expect(derived.contains("@objc func notAnOverride()"))
        #expect(!derived.contains("override func notAnOverride()"))
        #expect(!derived.contains("override func dynamicHook()"))
        // NSObject's `description` lives in libobjc: from the FILE the clang
        // class's superclass is a bind, which the resolver follows into the
        // running system's cache, so the override is provable offline too.
        #expect(derived.contains("override var description: Swift.String"))
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
        // The chain reaches `NSObject` through the host's cache, so the
        // explicit selector is judged on the file as well.
        #expect(implementation.contains("@objc(drawInRect:) func draw(in:"))
    }

    /// An `@implementation` body derives selectors from Swift names like any
    /// other class: matching the header's `drawInRect:` from a member named
    /// `draw(in:)` takes an explicit `@objc(drawInRect:)` — provable once
    /// the chain is complete, which in-process it is.
    @Test func implementationClassExplicitSelectorIsJudgedInProcess() async throws {
        let interface = try await interface(of: try loadedFixtureImage())
        let implementation = try #require(block(startingWith: "@objc @implementation extension __C.DerivedImplementationWidget {", in: interface))
        #expect(implementation.contains("@objc(drawInRect:) func draw(in:"))
        #expect(implementation.contains("@objc func poke()"))
    }

    /// An `override` declared in a Swift EXTENSION compiles to a category:
    /// the class's own method table does not list it, `__objc_catlist` does.
    @Test func overrideDeclaredInAnExtensionIsMarked() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.full))
        #expect(interface.contains("override func bump()"))
        #expect(interface.contains("@objc func fromExtension()"))
    }

    /// In-process every superclass pointer is real, so the chain runs through
    /// libobjc's `NSObject` and the `description` override is provable.
    @Test func inProcessImageFollowsTheChainIntoTheRuntime() async throws {
        let interface = try await interface(of: try loadedFixtureImage())
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override var description: Swift.String"))
        #expect(derived.contains("override func ping()"))
        #expect(!derived.contains("override func notAnOverride()"))
    }

    // MARK: - Interface: `@objc` and explicit selectors

    /// Every OS framework strips the `To` thunk symbols, which used to be
    /// the ONLY evidence of a member's `@objc`: the stripped variant of the
    /// fixture is the same shape, and the method table now supplies it.
    @Test func objcAttributeSurvivesStrippedThunkSymbols() async throws {
        let interface = try await interface(of: try ObjCImplementationFixture.machOFile(.strippedLocals))
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("@objc func notAnOverride()"))
        #expect(derived.contains("@objc func move(toWindow:"))
        // `@objc dynamic` has no vtable descriptor; without the `@objc`
        // evidence the `final` recovery took it for a non-overridable member.
        #expect(derived.contains("@objc func dynamicHook()"))
        #expect(!derived.contains("final func dynamicHook()"))
        // The overrides too — tied through the anonymous thunk's code.
        #expect(derived.contains("override func ping()"))
        #expect(derived.contains("override class func pingCount() -> Swift.Int"))
        // An EXPLICIT selector cannot survive the strip: the thunk-reference
        // join is guarded by the selector being the importer's spelling of
        // the member's name, and `pokeUsingForce:` is nobody's spelling of
        // `poke(force:)`. Honestly unattributed — never guessed.
        #expect(derived.contains("func poke(force: Swift.Int)"))
        #expect(!derived.contains("@objc(pokeUsingForce:)"))

        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: try ObjCImplementationFixture.machOFile(.strippedLocals)))
        #expect(!table.membersByImplementationSymbolName.isEmpty)
        #expect(table.membersByImplementationSymbolName.values.allSatisfy { $0.evidence == .thunkReference })
        #expect(table.membersByImplementationSymbolName.keys.allSatisfy { !$0.hasSuffix("To") })
    }

    // MARK: - The name-only third tier

    /// `-O` inlines every small override body into its thunk, so on the
    /// stripped product neither joining tier ties them: by default the
    /// overrides go unmarked — reported as unattributed, never guessed —
    /// exactly what an OS framework's `viewDidHide` looks like.
    @Test func inlinedOverridesStayUnmarkedByDefault() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.optimizedStripped)
        let interface = try await interface(of: machOFile)
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("func ping()"))
        #expect(!derived.contains("override func ping()"))
        #expect(!derived.contains("override var description"))
        try await withFixtureWorld(for: machOFile) {
            let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
            let unattributed = Set(table.unattributedOverriddenMethods.map(\.selector))
            #expect(unattributed.isSuperset(of: ["ping", "pingCount", "level", "setLevel:", "description", "noteValueForKeyPath:ofObject:"]))
            #expect(table.overrides.isEmpty)
        }
    }

    /// Asked for (`infersObjCOverridesFromSelectorNames`), the third tier
    /// attributes each of those methods to the one member whose name is the
    /// importer's spelling of its selector — and nothing else: a method no
    /// ancestor implements (`notAnOverride`, the explicit `pokeUsingForce:`)
    /// is never touched, so the switch can add `override` but never `@objc(name)`.
    @Test func inlinedOverridesAreInferredWhenAsked() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.optimizedStripped)
        defer { ObjCMemberRecoveryOptionsStore.shared.remove(for: machOFile) }
        let interface = try await interface(of: machOFile, infersObjCOverridesFromSelectorNames: true)
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override func ping()"))
        #expect(derived.contains("override class func pingCount() -> Swift.Int"))
        #expect(derived.contains("override var level: Swift.Int"))
        #expect(derived.contains("override var description: Swift.String"))
        // The category dylib's method, through the closure's files.
        #expect(derived.contains("override func noteValue(forKeyPath: Swift.String, of: Any)"))
        #expect(derived.contains("func notAnOverride()"))
        #expect(!derived.contains("@objc func notAnOverride()"))
        #expect(!derived.contains("@objc(pokeUsingForce:)"))
        // The override declared in the extension, and the grandchild's.
        #expect(interface.contains("override func bump()"))
        let grandchild = try #require(block(startingWith: "class SwiftGrandchildWidget:", in: interface))
        #expect(grandchild.contains("override func dynamicHook()"))
        // The `@implementation` body has no vtable at all, so these come
        // from the same inference.
        let implementation = try #require(block(startingWith: "@objc @implementation extension __C.DerivedImplementationWidget {", in: interface))
        #expect(implementation.contains("override func ping()"))
        #expect(implementation.contains("override class func pingCount() -> Swift.Int"))
        #expect(implementation.contains("override var level: Swift.Int"))
        #expect(!implementation.contains("override func poke()"))
    }

    /// The switch is per image, read from the store at each class's indexing.
    @Test func recoveryOptionsAreRegisteredPerImage() throws {
        let optimized = try ObjCImplementationFixture.machOFile(.optimizedStripped)
        let full = try ObjCImplementationFixture.machOFile(.full)
        #expect(ObjCMemberRecoveryOptionsStore.shared.options(for: optimized) == .default)
        #expect(!ObjCMemberRecoveryOptions.default.infersOverridesFromSelectorNames)
        ObjCMemberRecoveryOptionsStore.shared.register(ObjCMemberRecoveryOptions(infersOverridesFromSelectorNames: true), for: optimized)
        defer { ObjCMemberRecoveryOptionsStore.shared.remove(for: optimized) }
        #expect(ObjCMemberRecoveryOptionsStore.shared.options(for: optimized).infersOverridesFromSelectorNames)
        #expect(ObjCMemberRecoveryOptionsStore.shared.contains(in: optimized))
        #expect(!ObjCMemberRecoveryOptionsStore.shared.options(for: full).infersOverridesFromSelectorNames)
        #expect(!ObjCMemberRecoveryOptionsStore.shared.contains(in: full))
        ObjCMemberRecoveryOptionsStore.shared.remove(for: optimized)
        #expect(!ObjCMemberRecoveryOptionsStore.shared.contains(in: optimized))
    }

    /// With no dependency image to look in — a file whose linked images are
    /// nowhere on the host, here an indexer configured with no search paths
    /// — the chain stops at the bind: the same-image overrides stand, the
    /// `description` override is honestly absent rather than guessed, and
    /// since an inherited selector cannot be ruled out no `@objc(name)` is
    /// claimed (on an app binary every override of a UIKit method would
    /// otherwise read as a custom selector).
    @Test func fileWithABrokenChainClaimsNoExplicitSelector() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        ObjCAncestorResolverStore.shared.remove(for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        let interface = try await interface(of: machOFile, dependencySearchPaths: [])
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override func ping()"))
        #expect(derived.contains("var description: Swift.String"))
        #expect(!derived.contains("override var description"))
        #expect(derived.contains("@objc func poke(force: Swift.Int)"))
        #expect(derived.contains("@objc var alias: Swift.Int"))
        #expect(!derived.contains("@objc("))
        try await withoutDependencyImages(for: machOFile) {
            let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
            #expect(!table.hierarchy.isAncestorChainComplete)
            #expect(table.hierarchy.unresolvedAncestorName == "NSObject")
            #expect(table.membersByImplementationSymbolName.values.allSatisfy { !$0.hasExplicitSelector })
        }
    }

    /// The same file with its world resolvable: the bind is followed into
    /// the host's cache, the chain completes, and the explicit selectors are
    /// judged exactly as in-process — the memo tells the two resolvers'
    /// chains apart, so the broken chain above is never read back here.
    /// `noteValueForKeyPath:ofObject:` is an override of a member the
    /// category dylib implements: found through that file's `__objc_catlist`
    /// (its selector is not what the compiler derives from
    /// `noteValue(forKeyPath:of:)`, so without the fold it would read as an
    /// `@objc(name)`).
    @Test func fileWithItsWorldResolvableReachesTheRoot() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let interface = try await interface(of: machOFile)
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("@objc(pokeUsingForce:) func poke(force: Swift.Int)"))
        #expect(derived.contains("@objc(customLevel) var alias: Swift.Int"))
        #expect(derived.contains("override var description: Swift.String"))
        #expect(derived.contains("override func noteValue(forKeyPath: Swift.String, of: Any)"))
        #expect(!derived.contains("@objc(noteValueForKeyPath:ofObject:)"))
        #expect(derived.components(separatedBy: "@objc(").count == 3)
        try await withFixtureWorld(for: machOFile) {
            let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
            #expect(table.hierarchy.ancestors.map(\.className) == ["ClangWidget", "NSObject"])
            #expect(table.hierarchy.isAncestorChainComplete)
            #expect(table.hierarchy.unresolvedAncestorName == nil)
            #expect(table.overrides.contains { $0.selector == "description" && $0.overriddenAncestorClassName == "NSObject" })
            let noteValue = try #require(table.overrides.first { $0.selector == "noteValueForKeyPath:ofObject:" })
            #expect(noteValue.overriddenAncestorClassName == "NSObject")
            #expect(!noteValue.hasExplicitSelector)
            #expect(try #require(table.hierarchy.ancestors.last).implements(selector: "noteValueForKeyPath:ofObject:", isClassMethod: false))
        }
    }

    /// The boundary: a category in an image the closure cannot reach is
    /// invisible. With the category dylib left out of the search paths its
    /// load name is reported unresolved, `NSObject` shows no
    /// `noteValueForKeyPath:ofObject:`, and the member — an override in
    /// truth — reads as an explicit selector. Pinned so the boundary is
    /// explicit, not so it is desirable.
    @Test func categoryInAnUnreachableImageIsInvisible() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let closure = DependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache], traversal: .transitive)
        #expect(closure.unresolvedLoadNames.contains { $0.hasSuffix("Categories.dylib") })
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: [.systemDyldSharedCache]), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
        #expect(table.hierarchy.isAncestorChainComplete)
        #expect(!(try #require(table.hierarchy.ancestors.last).implements(selector: "noteValueForKeyPath:ofObject:", isClassMethod: false)))
        let noteValue = try #require(table.membersByImplementationSymbolName.values.first { $0.selector == "noteValueForKeyPath:ofObject:" })
        #expect(!noteValue.isOverride)
        #expect(noteValue.hasExplicitSelector)
    }

    /// The resolver itself: the bind's class name is looked up in the
    /// file's dependency closure by export trie and class list, first hit
    /// wins, and every verdict is memoized — hit or miss.
    @Test func resolverFindsTheBoundSuperclassInTheDependencyClosure() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let resolver = ObjCAncestorResolver(root: machOFile, searchPaths: [.systemDyldSharedCache])
        let (image, classObject) = try #require(resolver.classObject(named: "NSObject"))
        #expect(DependencyLoadName.bareImageName(of: image.imagePath) == "libobjc")
        #expect(!classObject.isSwift)
        #expect(resolver.classObject(named: "NoSuchClassAnywhere") == nil)
        #expect(ObjCAncestorResolver.empty.classObject(named: "NSObject") == nil)
        // The store hands a file the registered resolver, else a default one.
        ObjCAncestorResolverStore.shared.register(resolver, for: machOFile)
        #expect(ObjCAncestorResolverStore.shared.resolver(for: machOFile) === resolver)
        ObjCAncestorResolverStore.shared.remove(for: machOFile)
        #expect(!ObjCAncestorResolverStore.shared.contains(in: machOFile))
        #expect(ObjCAncestorResolverStore.shared.resolver(for: machOFile) !== resolver)
        ObjCAncestorResolverStore.shared.remove(for: machOFile)
    }

    /// The pre-macOS 12 bind format leaves a bound superclass slot zero in
    /// the file, which the ObjC reader takes for a root class; the first A/B
    /// on the iOS 15.5 simulator runtime's SwiftUI then judged every UIKit
    /// override an `@objc(name)`. The bind opcode stream still names the
    /// target, and a Swift class is never a root anyway — so with no
    /// dependency image the chain stops AT the name, not before it.
    @Test func legacyBindSuperclassIsUnresolvableNotRoot() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.legacyBinds)
        #expect(machOFile.dyldChainedFixups == nil, "the legacy variant must not carry chained fixups")
        ObjCAncestorResolverStore.shared.remove(for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        try await withoutDependencyImages(for: machOFile) {
            let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
            #expect(table.hierarchy.ancestors.map(\.className) == ["ClangWidget"])
            #expect(!table.hierarchy.isAncestorChainComplete)
            #expect(table.hierarchy.unresolvedAncestorName == "NSObject")
            #expect(Set(table.overrides.map(\.selector)) == ["ping", "pingCount", "level", "setLevel:", "bump"])
            #expect(table.membersByImplementationSymbolName.values.allSatisfy { !$0.hasExplicitSelector })
        }

        let interface = try await interface(of: machOFile, dependencySearchPaths: [])
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override func ping()"))
        #expect(derived.contains("@objc func poke(force: Swift.Int)"))
        #expect(!derived.contains("@objc("))
    }

    /// The name the legacy bind stream yields is what the resolver looks up:
    /// with the host's cache the legacy-format file's chain completes too.
    @Test func legacyBindSuperclassIsFollowedThroughTheResolver() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.legacyBinds)
        try await withFixtureWorld(for: machOFile) {
            let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
            #expect(table.hierarchy.ancestors.map(\.className) == ["ClangWidget", "NSObject"])
            #expect(table.hierarchy.isAncestorChainComplete)
            // With `NSObject` reached, the compiler-synthesized `init` is what it
            // is in the source: an override of `-[NSObject init]`.
            #expect(Set(table.overrides.map(\.selector)) == ["ping", "pingCount", "level", "setLevel:", "bump", "description", "init", "noteValueForKeyPath:ofObject:"])
            #expect(try #require(table.membersByImplementationSymbolName.values.first { $0.selector == "pokeUsingForce:" }).hasExplicitSelector)
        }

        let interface = try await interface(of: machOFile)
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        #expect(derived.contains("override var description: Swift.String"))
        #expect(derived.contains("@objc(pokeUsingForce:) func poke(force: Swift.Int)"))
    }

    @Test func explicitSelectorsPrintAndDerivedOnesDoNot() async throws {
        let interface = try await interface(of: try loadedFixtureImage())
        let derived = try #require(block(startingWith: "class SwiftDerivedWidget: __C.ClangWidget", in: interface))
        // Spelled in the source.
        #expect(derived.contains("@objc(pokeUsingForce:) func poke(force: Swift.Int)"))
        #expect(derived.contains("@objc(customLevel) var alias: Swift.Int"))
        // Derived by the compiler — a `With` suppressed by a preposition, an
        // unlabelled first parameter, `throws`, `async`.
        #expect(derived.contains("@objc func move(toWindow:"))
        #expect(derived.contains("@objc func perform(after:"))
        #expect(derived.contains("@objc func insertText(_:"))
        #expect(derived.contains("@objc func fetch() throws"))
        #expect(derived.contains("@objc func load() async"))
        for selector in ["moveToWindow:", "performAfter:", "insertText:replacementRange:", "fetchAndReturnError:", "loadWithCompletionHandler:", "setCustomLevel:", "setLevel:", "level", "ping", "pingCount"] {
            #expect(!derived.contains("@objc(\(selector))"), "\(selector) is not an explicit selector")
        }
        // Witnesses inherit the requirement's selector: `observerPriority` is
        // the protocol's `@objc(name)`, not the class's.
        #expect(derived.contains("@objc func widgetDidPing(_:"))
        #expect(derived.contains("@objc var priority: Swift.Int"))
        #expect(!derived.contains("@objc(observerPriority)"))
        #expect(!derived.contains("@objc(widgetDidPing:)"))
        // An override inherits too — in-process the chain reaches NSObject,
        // so `description` / `isEqual:`-style members are overrides, never
        // explicit. Exactly the two spelled ones remain.
        #expect(derived.components(separatedBy: "@objc(").count == 3)
    }

    // MARK: - The facts behind the rendering

    @Test func tablesJoinThroughToThunksAndReportTheChain() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        try await withFixtureWorld(for: machOFile) {
        let implementation = try #require(ObjCMembers.table(forObjCClassNamed: "DerivedImplementationWidget", in: machOFile))
        // The bound `NSObject` is followed into the host's cache.
        #expect(implementation.hierarchy.ancestors.map(\.className) == ["ClangWidget", "NSObject"])
        #expect(implementation.hierarchy.isAncestorChainComplete)
        #expect(implementation.hierarchy.unresolvedAncestorName == nil)
        #expect(implementation.membersByImplementationSymbolName.keys.allSatisfy { $0.hasSuffix("To") })
        // `init` is the initializer the compiler synthesizes for the class.
        #expect(Set(implementation.membersByImplementationSymbolName.values.map(\.selector)) == ["init", "ping", "pingCount", "level", "setLevel:", "poke", "drawInRect:"])
        // Judged since the chain is complete: the header's `drawInRect:` is
        // the one selector the compiler would not derive.
        #expect(implementation.membersByImplementationSymbolName.values.filter(\.hasExplicitSelector).map(\.selector) == ["drawInRect:"])
        #expect(Set(implementation.overrides.map(\.selector)) == ["ping", "pingCount", "level", "setLevel:", "init"])
        #expect(implementation.overrides.filter { $0.selector != "init" }.allSatisfy { $0.overriddenAncestorClassName == "ClangWidget" })
        #expect(implementation.overrides.first { $0.selector == "init" }?.overriddenAncestorClassName == "NSObject")
        let pingCount = try #require(implementation.overrides.first { $0.selector == "pingCount" })
        #expect(pingCount.isClassMethod)
        #expect(pingCount.description == "+[DerivedImplementationWidget pingCount]")
        #expect(pingCount.overriddenMethodDescription == "+[ClangWidget pingCount]")
        let poke = try #require(implementation.membersByImplementationSymbolName.values.first { $0.selector == "poke" })
        #expect(!poke.isOverride)
        #expect(!poke.hasExplicitSelector)
        #expect(poke.evidence == .thunkSymbol)

        let swiftDerived = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOFile))
        // `bump` is overridden from the extension — a category the reader
        // folds in; `description` overrides NSObject's, reached in libobjc.
        #expect(Set(swiftDerived.overrides.map(\.selector)) == ["ping", "pingCount", "level", "setLevel:", "bump", "description", "init", "noteValueForKeyPath:ofObject:"])
        #expect(swiftDerived.hierarchy.methods.contains { $0.selector == "description" })
        #expect(swiftDerived.hierarchy.methods.contains { $0.selector == "fromExtension" })

        // A Swift class with `@objc` members none of which override — other
        // than the synthesized `init`, which overrides NSObject's now that
        // the chain reaches it: members, not a missing table.
        let sibling = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).PlainSwiftSibling", in: machOFile))
        #expect(sibling.overrides.map(\.selector) == ["init"])
        #expect(sibling.overrides.first?.overriddenAncestorClassName == "NSObject")
        // Its own `poke`, the synthesized `init`, and the `.cxx_destruct` the
        // compiler points at the ivar destroyer.
        #expect(Set(sibling.membersByImplementationSymbolName.values.map(\.selector)) == ["poke", "init", ".cxx_destruct"])
        #expect(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).NoSuchClass", in: machOFile) == nil)
        #expect(ObjCMembers.table(forObjCClassNamed: "NSObject", in: machOFile) == nil)
        }
    }

    @Test func explicitSelectorsAreTheOnesTheCompilerWouldNotDerive() throws {
        let machOImage = try loadedFixtureImage()
        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftDerivedWidget", in: machOImage))
        #expect(table.hierarchy.isAncestorChainComplete)
        func member(_ selector: String) throws -> ObjCMember {
            try #require(table.membersByImplementationSymbolName.values.first { $0.selector == selector }, "no member answers to \(selector)")
        }
        #expect(try member("pokeUsingForce:").hasExplicitSelector)
        #expect(try member("customLevel").hasExplicitSelector)
        #expect(try member("setCustomLevel:").hasExplicitSelector)
        for selector in ["moveToWindow:", "performAfter:", "insertText:replacementRange:", "fetchAndReturnError:", "loadWithCompletionHandler:", "notAnOverride", "dynamicHook", "fromExtension"] {
            #expect(!(try member(selector).hasExplicitSelector), Comment(rawValue: selector))
            #expect(!(try member(selector).isOverride), Comment(rawValue: selector))
        }
        // The protocol is in this image, so its requirements are readable
        // and the witnesses' inherited selectors are not explicit.
        let protocolSelectors = try #require(table.hierarchy.adoptedProtocolSelectors)
        #expect(protocolSelectors.isComplete)
        #expect(protocolSelectors.instanceSelectors.isSuperset(of: ["widgetDidPing:", "observerPriority"]))
        #expect(!(try member("observerPriority").hasExplicitSelector))
        #expect(!(try member("widgetDidPing:").hasExplicitSelector))
        // Overrides never claim one — `description` overrides NSObject's,
        // reachable in-process, and would otherwise read as explicit; so
        // would `noteValueForKeyPath:ofObject:`, whose category the runtime
        // attached out of the fixture's category dylib where the reader does
        // not look — the in-process resolver folds it from the loaded image.
        #expect(try member("bump").isOverride)
        #expect(try member("bump").overriddenAncestorClassName == "ClangWidget")
        #expect(try member("description").isOverride)
        #expect(try member("noteValueForKeyPath:ofObject:").isOverride)
        #expect(table.overrides.allSatisfy { !$0.hasExplicitSelector })

        let implementation = try #require(ObjCMembers.table(forObjCClassNamed: "DerivedImplementationWidget", in: machOImage))
        let draw = try #require(implementation.membersByImplementationSymbolName.values.first { $0.selector == "drawInRect:" })
        #expect(draw.hasExplicitSelector)
        #expect(implementation.membersByImplementationSymbolName.values.filter(\.hasExplicitSelector).map(\.selector) == ["drawInRect:"])

        // A conformance is inherited: the grandchild's `widgetWillPing()`
        // satisfies the parent's protocol's optional requirement and takes
        // its `widgetWillPingSoon` — the requirement's selector, not explicit.
        let grandchild = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(Self.moduleName).SwiftGrandchildWidget", in: machOImage))
        #expect(grandchild.hierarchy.isAdoptedProtocolSetComplete)
        #expect(grandchild.hierarchy.adoptedProtocolDeclares(selector: "widgetWillPingSoon", isClassMethod: false))
        let willPing = try #require(grandchild.membersByImplementationSymbolName.values.first { $0.selector == "widgetWillPingSoon" })
        #expect(!willPing.hasExplicitSelector)
        #expect(!willPing.isOverride)
    }

    // MARK: - The provider seam

    /// A host that already indexed the ObjC side hands its class groups in;
    /// the recovery must consult them and reach the same verdicts the
    /// library's own reader does — categories and protocols included.
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
        try await withFixtureWorld(for: machOFile) {
        #expect(spy.queriedNames.contains(Self.swiftDerivedWidgetRuntimeName))
        #expect(spy.queriedNames.contains("DerivedImplementationWidget"))
        #expect(spy.answeredNames.contains(Self.swiftDerivedWidgetRuntimeName))
        #expect(spy.answeredNames.contains("DerivedImplementationWidget"))

        // The adapter's own view of the chain: the ObjC indexer stops at the
        // bound superclass exactly where the library's reader would without
        // its resolver — and the recovery continues the chain from there
        // through the same resolver, so the two seams agree.
        let hierarchy = try #require(spy.objcClassHierarchy(forClassNamed: "DerivedImplementationWidget"))
        #expect(hierarchy.ancestors.map(\.className) == ["ClangWidget"])
        #expect(hierarchy.isAncestorChainComplete == false)
        #expect(hierarchy.unresolvedAncestorName == "NSObject")
        #expect(hierarchy.methods.contains { $0.selector == "ping" && !$0.isClassMethod })
        let continued = try #require(ObjCMembers.table(forObjCClassNamed: "DerivedImplementationWidget", in: machOFile)).hierarchy
        #expect(continued.ancestors.map(\.className) == ["ClangWidget", "NSObject"])
        #expect(continued.isAncestorChainComplete)
        #expect(continued.adoptedProtocolSelectors == hierarchy.adoptedProtocolSelectors)
        }

        // Categories and protocols come through the adapter too.
        let swiftDerived = try #require(spy.objcClassHierarchy(forClassNamed: Self.swiftDerivedWidgetRuntimeName))
        #expect(swiftDerived.methods.contains { $0.selector == "fromExtension" })
        #expect(swiftDerived.methods.contains { $0.selector == "bump" })
        #expect(swiftDerived.adoptedProtocolSelectors?.isComplete == true)
        #expect(swiftDerived.adoptedProtocolSelectors?.instanceSelectors.contains("observerPriority") == true)
    }

    @Test func registrationIsWeak() throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        var provider: SpyingProvider? = SpyingProvider(wrapping: EmptyProvider())
        ObjCClassHierarchyProviderStore.shared.register(provider!, for: machOFile)
        #expect(ObjCClassHierarchyProviderStore.shared.provider(for: machOFile) != nil)
        provider = nil
        #expect(ObjCClassHierarchyProviderStore.shared.provider(for: machOFile) == nil)
    }

    // MARK: - Shapes

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
        // A `To` thunk symbol demangles to the same entity behind an attribute.
        let layoutThunk = try #require(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewC6AppKitE6layoutyyFTo")))
        #expect(layoutThunk == layout)

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
        let subscriptGetter = ObjCMemberShape(kind: .subscriptGetter, isStatic: false, ownerQualifiedName: nil)
        #expect(subscriptGetter.isConsistent(withSelector: "objectAtIndexedSubscript:", isClassMethod: false))
        #expect(subscriptGetter.isConsistent(withSelector: "objectForKeyedSubscript:", isClassMethod: false))
        #expect(!subscriptGetter.isConsistent(withSelector: "setObject:atIndexedSubscript:", isClassMethod: false))

        // Not a member entry point at all.
        #expect(ObjCMemberShape(demangledSymbol: try demangleAsNode("$sSo17NSGlassEffectViewCMa")) == nil)
    }

    /// `AbstractFunctionDecl::getObjCSelector` and
    /// `VarDecl::getDefaultObjCSetterSelector`, case by case.
    @Test func defaultSelectorsFollowTheCompiler() {
        func method(_ baseName: String, _ labels: [String?], isThrowing: Bool = false, isAsync: Bool = false) -> ObjCMemberShape {
            ObjCMemberShape(kind: .method(baseName: baseName, labels: labels, arity: labels.count), isStatic: false, ownerQualifiedName: nil, isThrowing: isThrowing, isAsync: isAsync)
        }
        func initializer(_ labels: [String?], isThrowing: Bool = false) -> ObjCMemberShape {
            ObjCMemberShape(kind: .initializer(labels: labels, arity: labels.count), isStatic: false, ownerQualifiedName: nil, isThrowing: isThrowing)
        }
        #expect(method("layout", []).defaultSelector() == "layout")
        #expect(method("addSubview", [nil]).defaultSelector() == "addSubview:")
        // A labelled first parameter takes `With` — unless the label starts
        // with a preposition, or the base name ends with one.
        #expect(method("foo", ["bar", "baz"]).defaultSelector() == "fooWithBar:baz:")
        #expect(method("viewWillMove", ["toWindow"]).defaultSelector() == "viewWillMoveToWindow:")
        #expect(method("perform", ["after"]).defaultSelector() == "performAfter:")
        #expect(method("moveTo", ["view"]).defaultSelector() == "moveToView:")
        #expect(method("insertText", [nil, "replacementRange"]).defaultSelector() == "insertText:replacementRange:")
        #expect(method("replace", [nil, "with"]).defaultSelector() == "replace:with:")
        // The compiler's derivation, NOT the importer's: `encode(with:)`
        // declared in Swift would be `encodeWith:`, and `encodeWithCoder:`
        // therefore reads as explicit — exactly the fact wanted.
        #expect(method("encode", ["with"]).defaultSelector() == "encodeWith:")
        #expect(!method("encode", ["with"]).isDefaultSelector("encodeWithCoder:"))
        // Effects.
        #expect(method("fetch", [], isThrowing: true).defaultSelector() == "fetchAndReturnError:")
        #expect(method("load", [], isAsync: true).defaultSelector() == "loadWithCompletionHandler:")
        #expect(method("save", ["to"], isThrowing: true).defaultSelector() == "saveTo:error:")
        #expect(method("download", ["from"], isThrowing: true, isAsync: true).defaultSelector() == "downloadFrom:completionHandler:")
        #expect(method("run", [nil], isThrowing: true).defaultSelector() == "run:error:")
        // Initializers.
        #expect(initializer([]).defaultSelector() == "init")
        #expect(initializer(["coder"]).defaultSelector() == "initWithCoder:")
        #expect(initializer(["from"]).defaultSelector() == "initFrom:")
        #expect(initializer([nil]).defaultSelector() == "init:")
        #expect(initializer(["frame"], isThrowing: true).defaultSelector() == "initWithFrame:error:")
        // Accessors — no `is` handling on the Swift side.
        #expect(ObjCMemberShape(kind: .getter(propertyName: "isEnabled"), isStatic: false, ownerQualifiedName: nil).defaultSelector() == "isEnabled")
        #expect(ObjCMemberShape(kind: .setter(propertyName: "isEnabled"), isStatic: false, ownerQualifiedName: nil).defaultSelector() == "setIsEnabled:")
        #expect(ObjCMemberShape(kind: .setter(propertyName: "clipsToBounds"), isStatic: false, ownerQualifiedName: nil).defaultSelector() == "setClipsToBounds:")
        // Subscripts: no single default, four accepted spellings.
        let subscriptSetter = ObjCMemberShape(kind: .subscriptSetter, isStatic: false, ownerQualifiedName: nil)
        #expect(subscriptSetter.defaultSelector() == nil)
        #expect(subscriptSetter.isDefaultSelector("setObject:forKeyedSubscript:"))
        #expect(!subscriptSetter.isDefaultSelector("objectForKeyedSubscript:"))
        // The word splitter and the preposition list behind the `With` rule.
        #expect(ObjCMemberShape.CamelCaseWords.words(of: "viewWillMove") == ["view", "Will", "Move"])
        #expect(ObjCMemberShape.CamelCaseWords.words(of: "URLSession") == ["URL", "Session"])
        #expect(ObjCMemberShape.CamelCaseWords.firstWord(of: "toWindow") == "to")
        #expect(ObjCMemberShape.CamelCaseWords.lastWord(of: "moveTo") == "To")
        #expect(ObjCMemberShape.prepositions.count == 30)
        #expect(ObjCMemberShape.prepositions.isSuperset(of: ["with", "to", "for", "at", "in", "given", "matching", "via"]))
        #expect(!ObjCMemberShape.prepositions.contains("and"))
    }

    @Test func nameInferenceAttributesOnlyAUniqueCandidate() {
        let hierarchy = ObjCClassHierarchy(className: "X", methods: [], ancestors: [], isAncestorChainComplete: true)
        let table = ObjCMemberTable(
            hierarchy: hierarchy,
            membersByImplementationSymbolName: [:],
            unattributedMethods: [
                .init(selector: "viewDidHide", isClassMethod: false, overriddenAncestorClassName: "NSView"),
                .init(selector: "layoutWithFoo:", isClassMethod: false, overriddenAncestorClassName: "NSView"),
                // Not an override: the name-based tier never touches it.
                .init(selector: "plainHelper", isClassMethod: false, overriddenAncestorClassName: nil),
            ]
        )
        let shapes: [(key: String, shape: ObjCMemberShape)] = [
            ("hide", ObjCMemberShape(kind: .method(baseName: "viewDidHide", labels: [], arity: 0), isStatic: false, ownerQualifiedName: nil)),
            ("first", ObjCMemberShape(kind: .method(baseName: "layoutWith", labels: ["foo"], arity: 1), isStatic: false, ownerQualifiedName: nil)),
            ("second", ObjCMemberShape(kind: .method(baseName: "layoutWith", labels: ["foo"], arity: 1), isStatic: false, ownerQualifiedName: nil)),
            ("helper", ObjCMemberShape(kind: .method(baseName: "plainHelper", labels: [], arity: 0), isStatic: false, ownerQualifiedName: nil)),
        ]
        let inferred = table.inferredOverrides(forMemberShapes: shapes)
        #expect(inferred.keys.sorted() == ["hide"])
        #expect(inferred["hide"] == ObjCMember(className: "X", selector: "viewDidHide", isClassMethod: false, overriddenAncestorClassName: "NSView", evidence: .selectorName))
        #expect(table.unattributedOverriddenMethods.count == 2)
    }

    @Test func hierarchyFromClassInfoChainMapsMethodsAncestorsCategoriesAndProtocols() {
        let observing = ObjCProtocolInfo(
            name: "Observing", protocols: [], classProperties: [], properties: [],
            classMethods: [], methods: [ObjCMethodInfo(name: "observe:", typeEncoding: "v24@0:8@16", isClassMethod: false, imp: 0)],
            optionalClassProperties: [], optionalProperties: [],
            optionalClassMethods: [ObjCMethodInfo(name: "sharedObserver", typeEncoding: "@16@0:8", isClassMethod: true, imp: 0)],
            optionalMethods: [ObjCMethodInfo(name: "didObserve", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0)]
        )
        let child = ObjCClassInfo(
            name: "Child", version: 0, imageName: nil, instanceSize: 8, superClassName: "Parent",
            protocols: [observing], ivars: [], classProperties: [], properties: [],
            classMethods: [ObjCMethodInfo(name: "make", typeEncoding: "@16@0:8", isClassMethod: true, imp: 0x2000)],
            methods: [ObjCMethodInfo(name: "ping", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x1000), ObjCMethodInfo(name: "noImplementation", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0)]
        )
        let parent = ObjCClassInfo(
            name: "Parent", version: 0, imageName: nil, instanceSize: 8, superClassName: nil,
            protocols: [], ivars: [], classProperties: [], properties: [],
            classMethods: [ObjCMethodInfo(name: "make", typeEncoding: "@16@0:8", isClassMethod: true, imp: 0x3000)],
            methods: [ObjCMethodInfo(name: "ping", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x4000)]
        )
        let category = ObjCCategoryInfo(
            name: "Extras", className: "Child", protocols: [], classProperties: [], properties: [],
            classMethods: [], methods: [ObjCMethodInfo(name: "extra", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x5000), ObjCMethodInfo(name: "ping", typeEncoding: "v16@0:8", isClassMethod: false, imp: 0x1000)]
        )
        let hierarchy = ObjCClassHierarchy(classInfoChain: [child, parent], categoryInfos: [category], isAncestorChainComplete: true)
        #expect(hierarchy.className == "Child")
        // The category's `ping` duplicates the class's own and is kept once.
        #expect(hierarchy.methods == [
            .init(selector: "ping", isClassMethod: false, implementation: .address(0x1000)),
            .init(selector: "noImplementation", isClassMethod: false, implementation: nil),
            .init(selector: "make", isClassMethod: true, implementation: .address(0x2000)),
            .init(selector: "extra", isClassMethod: false, implementation: .address(0x5000)),
        ])
        #expect(hierarchy.ancestors.map(\.className) == ["Parent"])
        #expect(hierarchy.ancestorDeclaring(selector: "ping", isClassMethod: false)?.className == "Parent")
        #expect(hierarchy.ancestorDeclaring(selector: "make", isClassMethod: true)?.className == "Parent")
        #expect(hierarchy.ancestorDeclaring(selector: "make", isClassMethod: false) == nil)
        #expect(hierarchy.ancestorDeclaring(selector: "noImplementation", isClassMethod: false) == nil)
        let protocolSelectors = hierarchy.adoptedProtocolSelectors
        #expect(protocolSelectors?.isComplete == true)
        #expect(protocolSelectors?.instanceSelectors == ["observe:", "didObserve"])
        #expect(protocolSelectors?.classSelectors == ["sharedObserver"])
        #expect(hierarchy.adoptedProtocolDeclares(selector: "didObserve", isClassMethod: false))
        #expect(!hierarchy.adoptedProtocolDeclares(selector: "sharedObserver", isClassMethod: false))

        let broken = ObjCClassHierarchy(classInfoChain: [child], isAncestorChainComplete: false)
        #expect(broken.unresolvedAncestorName == "Parent")
        #expect(broken.ancestors.isEmpty)

        // An ancestor's protocols count: the conformance is inherited.
        let parentWithProtocol = ObjCClassInfo(
            name: "Parent", version: 0, imageName: nil, instanceSize: 8, superClassName: nil,
            protocols: [observing], ivars: [], classProperties: [], properties: [], classMethods: [], methods: []
        )
        let plainChild = ObjCClassInfo(
            name: "Child", version: 0, imageName: nil, instanceSize: 8, superClassName: "Parent",
            protocols: [], ivars: [], classProperties: [], properties: [], classMethods: [], methods: []
        )
        let inherited = ObjCClassHierarchy(classInfoChain: [plainChild, parentWithProtocol], isAncestorChainComplete: true)
        #expect(inherited.adoptedProtocolSelectors?.instanceSelectors.isEmpty == true)
        #expect(inherited.adoptedProtocolDeclares(selector: "didObserve", isClassMethod: false))
        #expect(inherited.isAdoptedProtocolSetComplete)
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
struct AppKitObjCMemberTests {
    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "NSGlassEffectView ships with macOS 26")) func glassEffectViewOverridesResolveAgainstNSView() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
        let table = try #require(ObjCMembers.table(forObjCClassNamed: "NSGlassEffectView", in: machOFile))
        // The chain crosses into libobjc inside the cache and reaches the root.
        #expect(table.hierarchy.ancestors.map(\.className) == ["NSView", "NSResponder", "NSObject"])
        #expect(table.hierarchy.isAncestorChainComplete)
        let overrides = table.overrides
        let selectors = Set(overrides.map(\.selector))
        // The OS build strips the `To` thunk symbols, so every attribution
        // comes from decoding the anonymous thunk: a `bl` to the
        // implementation (`layout`, `initWithCoder:`, `setClipsToBounds:`,
        // `viewWillMoveToWindow:`, `didChangeValueForKey:`) or the
        // implementation's address materialized for an outlined helper
        // (`+defaultAnimationForKey:`).
        #expect(selectors.isSuperset(of: ["layout", "viewWillMoveToWindow:", "initWithCoder:", "setClipsToBounds:", "didChangeValueForKey:", "defaultAnimationForKey:"]))
        #expect(table.membersByImplementationSymbolName.values.allSatisfy { $0.evidence == .thunkReference })
        // NSView overrides `didChangeValueForKey:` itself, so the nearest
        // ancestor is NSView, not NSObject.
        #expect(overrides.first { $0.selector == "didChangeValueForKey:" }?.overriddenAncestorClassName == "NSView")
        let defaultAnimation = try #require(overrides.first { $0.selector == "defaultAnimationForKey:" })
        #expect(defaultAnimation.isClassMethod)
        #expect(defaultAnimation.overriddenAncestorClassName == "NSView")
        // An override's selector is inherited, never reported as explicit.
        #expect(overrides.allSatisfy { !$0.hasExplicitSelector })
        // Every key is one of the class's own Swift implementations.
        #expect(table.membersByImplementationSymbolName.keys.allSatisfy { $0.contains("So17NSGlassEffectViewC") && !$0.hasSuffix("To") })
        // Bodies the optimizer inlined (`clipsToBounds`'s getter is a bare
        // `super` call through `objc_msgSendSuper`, `viewDidHide` an
        // outlined one) reference no Swift symbol: reported, never guessed.
        let unattributed = Set(table.unattributedOverriddenMethods.map(\.selector))
        #expect(unattributed.contains("clipsToBounds"))
        #expect(unattributed.contains("viewDidHide"))
        #expect(unattributed.isDisjoint(with: selectors))
        // The adopted protocols (NSCoding via NSView, …) resolve inside the cache.
        #expect(table.hierarchy.adoptedProtocolSelectors?.isComplete == true)
    }

    /// `NSGradient` is an `@implementation` class whose header spells
    /// `drawInRect:angle:` for the member the importer names
    /// `draw(in:angle:)`; the compiler derives `drawIn:angle:` from that name
    /// and demands the header declare it, so Apple's Swift source must carry
    /// `@objc(drawInRect:angle:)` — an explicit selector, provable because
    /// the chain and the protocols resolve inside the cache.
    @Test(.enabled(if: runsOnMacOS26OrLater, "NSGradient's Swift implementation ships with macOS 26")) func gradientHeaderSelectorsAreExplicit() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
        let table = try #require(ObjCMembers.table(forObjCClassNamed: "NSGradient", in: machOFile))
        #expect(table.hierarchy.isAncestorChainComplete)
        let draw = try #require(table.membersByImplementationSymbolName.values.first { $0.selector == "drawInRect:angle:" })
        #expect(draw.hasExplicitSelector)
        #expect(!draw.isOverride)
        // `encodeWithCoder:` is NSCoding's requirement: inherited, not explicit.
        let encode = try #require(table.membersByImplementationSymbolName.values.first { $0.selector == "encodeWithCoder:" })
        #expect(!encode.hasExplicitSelector)
    }
}
