import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclaration
import SwiftDeclarationRendering
import SwiftInterface
import SwiftThunkAnalysis
@_spi(Internals) import SwiftInspection
@testable import MachOTestingSupport

/// Classes a source renamed for the Objective-C runtime on the interface
/// path (evolution proposal `objc-custom-class-name`): the attribute the
/// source carried, and the ObjC member recovery and the static layout engine,
/// both of which used to find a Swift class's ObjC class object by
/// demangling its runtime name — which a renamed class's name is not.
///
/// Holds `ExclusiveImageAccess` because the indexer registers an ancestor
/// resolver per image for the file leg.
@Suite(.serialized, ExclusiveImageAccess(RenamedObjCClassFixture.moduleName))
struct CustomObjCClassNameInterfaceTests {
    private func interface(of variant: RenamedObjCClassFixture.Variant, printFieldOffset: Bool = false) async throws -> String {
        let searchPaths = try RenamedObjCClassFixture.dependencySearchPaths()
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.indexConfiguration.dependencySearchPaths = searchPaths
        configuration.printConfiguration.printFieldOffset = printFieldOffset
        configuration.printConfiguration.staticLayoutDependencyResolution = .dependencyClosure(searchPaths: searchPaths)
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: try RenamedObjCClassFixture.machOFile(variant))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func inProcessInterface() async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: try RenamedObjCClassFixture.loadedImage())
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The block whose header line STARTS with `prefix`, through its closing
    /// brace at the same indentation.
    private func block(startingWith prefix: String, in interface: String) -> String? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[start...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    private func expectRenamedClassAttributes(in interface: String) {
        #expect(interface.contains("\n@objc(RCFRenamedWidget)\nclass RenamedWidget: __C.NSObject {\n"), "\(interface)")
        // Renamed to its own Swift name: without the attribute the runtime
        // name would have been the mangling, so it is still printed.
        #expect(interface.contains("\n@objc(RCFSameNameWidget)\nclass RCFSameNameWidget: __C.NSObject {\n"), "\(interface)")
        // The native object model: `@objc` would not be legal Swift here.
        #expect(interface.contains("\n@_objcRuntimeName(RCFNativeRoot)\nclass NativeRoot {\n"), "\(interface)")
        #expect(!interface.contains("@objc(RCFNativeRoot)"), "\(interface)")
        // Nested: the attribute sits at the class's own indentation.
        #expect(interface.contains("\n    @objc(RCFNestedWidget)\n    class NestedWidget: __C.NSObject {\n"), "\(interface)")
        // No class object in the class list: read from the metadata pattern.
        #expect(interface.contains("\n@objc(RCFResilientChild)\nclass ResilientChild: RenamedObjCClassFixtureKit.ResilientBase {\n"), "\(interface)")
        // Swift reference counting, yet `NSObject`-derived.
        #expect(interface.contains("\n@objc(RCFRenamedActor)\nactor RenamedActor: "), "\(interface)")
        // The negative control, filed under its `_TtC…` mangling.
        #expect(interface.contains("\nclass PlainWidget: __C.NSObject {\n"), "\(interface)")
        #expect(!interface.contains(")\nclass PlainWidget"), "\(interface)")
    }

    // MARK: - The attribute

    @Test func renamedClassesCarryTheirRuntimeNameOffline() async throws {
        expectRenamedClassAttributes(in: try await interface(of: .full))
    }

    @Test func renamedClassesCarryTheirRuntimeNameInProcess() async throws {
        expectRenamedClassAttributes(in: try await inProcessInterface())
    }

    /// The diff and evolution renderers compose a type's header themselves;
    /// the attribute must come out of that path too.
    @Test func diffInterfaceHeadersCarryTheRuntimeName() async throws {
        let oldBuilder = SwiftDiffableInterfaceBuilder(in: try RenamedObjCClassFixture.machOFile(.full))
        try await oldBuilder.prepare()
        let newBuilder = SwiftDiffableInterfaceBuilder(in: try RenamedObjCClassFixture.machOFile(.strippedLocals))
        try await newBuilder.prepare()
        let output = await SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder).printAnnotatedInterface().string
        #expect(output.contains("  @objc(RCFRenamedWidget)\n  class RenamedWidget: __C.NSObject {"), "\(output)")
        #expect(output.contains("  @_objcRuntimeName(RCFNativeRoot)\n  class NativeRoot {"), "\(output)")
    }

    // MARK: - The ObjC member recovery

    /// The renamed class's own ObjC method table: `init` and `description`
    /// override NSObject's, `copy` overrides it from an extension (a
    /// category on the renamed class).
    @Test func renamedClassOverridesAreMarked() async throws {
        let interface = try await interface(of: .full)
        let widget = try #require(block(startingWith: "class RenamedWidget:", in: interface), "\(interface)")
        #expect(widget.contains("@objc override init()"), "\(widget)")
        #expect(widget.contains("@objc override var description: Swift.String"), "\(widget)")
        #expect(widget.contains("@objc override func copy() -> Any"), "\(widget)")
        #expect(widget.contains("@objc func poke()"), "\(widget)")
        #expect(!widget.contains("override func poke()"), "\(widget)")
    }

    /// With the `To` thunks stripped, as in every OS framework, the method
    /// table is the only `@objc` evidence — and without it the `final`
    /// recovery took the renamed class's ObjC members for `final` ones.
    @Test func strippedRenamedClassMembersJoinTheirObjCMethodTable() async throws {
        let interface = try await interface(of: .strippedLocals)
        let widget = try #require(block(startingWith: "class RenamedWidget:", in: interface), "\(interface)")
        #expect(widget.contains("@objc override var description: Swift.String"), "\(widget)")
        #expect(widget.contains("@objc override func copy() -> Any"), "\(widget)")
        #expect(widget.contains("@objc func poke()"), "\(widget)")
        #expect(widget.contains("@objc func pokeFromExtension()"), "\(widget)")
        #expect(!widget.contains("final"), "\(widget)")
    }

    /// The table itself, asked by the Swift qualified name the way every
    /// consumer asks: a renamed class answers under the name its source chose.
    @Test func memberTableOfARenamedClassIsFoundByItsQualifiedName() throws {
        let machOFile = try RenamedObjCClassFixture.machOFile(.full)
        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(RenamedObjCClassFixture.moduleName).RenamedWidget", in: machOFile))
        #expect(table.hierarchy.className == "RCFRenamedWidget")
        let plainTable = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "\(RenamedObjCClassFixture.moduleName).PlainWidget", in: machOFile))
        #expect(plainTable.hierarchy.className.hasPrefix("_TtC"))
    }

    /// Same-named private classes share a qualified name (it drops the
    /// private discriminator), and the lookup refuses to guess between them —
    /// which must hold when one of the two is renamed, too: its runtime name
    /// is found through the renamed-class index, not the demangled one.
    @Test func sameNamedPrivateClassesStayAmbiguousWhenOneIsRenamed() throws {
        let machOFile = try RenamedObjCClassFixture.machOFile(.full)
        #expect(ObjCMembers.table(forSwiftClassQualifiedName: "\(RenamedObjCClassFixture.moduleName).PrivateTwin", in: machOFile) == nil)
    }

    // MARK: - The static layout engine

    /// The compiler lays a subclass of an ObjC class out from the root's 8
    /// bytes (the isa); the runtime slides the fields en masse past the
    /// base's real size (20), by the drift rounded up to the widest field's
    /// alignment (16) — `small` at 0x18, `wide` at 0x20. The engine
    /// reproduces that from the class's own `class_ro_t.instanceStart`, which
    /// for a renamed class it used to miss, falling back to laying the fields
    /// out from 20 (`small` at 0x14, `wide` at 0x18). The `_TtC…` twin is the
    /// control.
    @Test func renamedClassFieldsFollowTheRuntimeSlide() async throws {
        let interface = try await interface(of: .full, printFieldOffset: true)
        for className in ["RenamedDrifter", "PlainDrifter"] {
            let drifter = try #require(block(startingWith: "class \(className):", in: interface), "\(interface)")
            #expect(drifter.contains("// Field offset: 0x18\n    var small: Swift.Int8"), "\(drifter)")
            #expect(drifter.contains("// Field offset: 0x20\n    var wide: Swift.Int64"), "\(drifter)")
        }

        // The runtime's own answer, from the realized class.
        _ = try RenamedObjCClassFixture.loadedImage()
        let drifterClass = try #require(objc_getClass("RCFRenamedDrifter") as? AnyClass)
        _ = class_getInstanceSize(drifterClass)
        let smallIvar = try #require(class_getInstanceVariable(drifterClass, "small"))
        let wideIvar = try #require(class_getInstanceVariable(drifterClass, "wide"))
        #expect(ivar_getOffset(smallIvar) == 0x18)
        #expect(ivar_getOffset(wideIvar) == 0x20)
    }
}

/// The same recovery on the running system's AppKit, which renames dozens
/// of its Swift classes: `NSScrollPocket` (macOS 26 and later) is
/// `@objc(NSScrollPocket)` and overrides `NSView` members only its ObjC method
/// table can show.
@Suite(.serialized)
struct SystemFrameworkCustomObjCClassNameTests {
    private static let appKitPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    private static func appKitFileInSystemCache() throws -> MachOFile {
        let cache = try DyldCache(path: .current)
        return try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
    }

    private static func loadedAppKitImage() throws -> MachOImage {
        try #require(dlopen(appKitPath, RTLD_LAZY) != nil, "AppKit could not be loaded into the test process")
        return try #require(MachOImage(name: "AppKit"))
    }

    private static func classDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            if try classDescriptor.name(in: machO.context) == name {
                return classDescriptor
            }
        }
        return nil
    }

    private static func expectScrollPocketRecovery(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        let descriptor = try #require(try classDescriptor(named: "NSScrollPocket", in: machO))
        let customObjCClassName = SwiftClassObjectIndex.shared.customObjCClassName(forClassDescriptorOffset: descriptor.offset, in: machO)
        #expect(customObjCClassName == CustomObjCClassName(name: "NSScrollPocket", attribute: .objc))
        let table = try #require(ObjCMembers.table(forSwiftClassQualifiedName: "AppKit.NSScrollPocket", in: machO))
        #expect(table.hierarchy.className == "NSScrollPocket")
        #expect(table.hierarchy.ancestors.first?.className == "NSView")
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "NSScrollPocket ships with macOS 26's AppKit"))
    func scrollPocketIsRecoveredFromTheSystemCache() throws {
        try Self.expectScrollPocketRecovery(in: try Self.appKitFileInSystemCache())
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "NSScrollPocket ships with macOS 26's AppKit"))
    func scrollPocketIsRecoveredInProcess() throws {
        try Self.expectScrollPocketRecovery(in: try Self.loadedAppKitImage())
    }
}
