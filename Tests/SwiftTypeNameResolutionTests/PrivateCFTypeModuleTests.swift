#if os(macOS)

import Foundation
import MachODependencies
import MachOKit
import Semantic
import SwiftInterface
import SwiftSectionFixtureSupport
import SwiftTypeNameResolution
import Testing

/// Evolution proposal `private-cf-type-modules`, end to end: a CF type no SDK
/// header declares prints under the module of the image exporting its
/// `GetTypeID` function, through `SwiftInterfaceBuilderTypeNameProvider`.
///
/// `ProbeCF` stands for a private framework such as CoreSVG: a C library
/// exporting `ProbeWidgetGetTypeID`. `ProbeKit` stands for SwiftUICore: a Swift
/// library whose bridging header declares the CF types, which links `ProbeCF`
/// and defines a CF type of its own, exporting `ProbeGadgetGetTypeID` through
/// `@_cdecl`, and declares a third, `ProbeLonelyRef`, that no image exports a
/// `GetTypeID` for — a bridged type made up without the CF convention.
/// `FixtureCompiler` gives every library the install name
/// `@rpath/lib<name>.dylib`, and `TypeDatabase` names a module after the
/// install name's file, so the two modules read `libProbeCF` and `libProbeKit`.
@Suite
struct PrivateCFTypeModuleTests {
    private static let probeCFSource = """
    unsigned long ProbeWidgetGetTypeID(void) { return 1; }
    """

    private static let probeKitBridgingHeader = """
    #include <CoreFoundation/CoreFoundation.h>
    typedef struct CF_BRIDGED_TYPE(id) __ProbeWidget *ProbeWidgetRef;
    typedef struct CF_BRIDGED_TYPE(id) __ProbeGadget *ProbeGadgetRef;
    typedef struct CF_BRIDGED_TYPE(id) __ProbeLonely *ProbeLonelyRef;
    CFTypeID ProbeWidgetGetTypeID(void);
    """

    /// `Anchor` keeps a `__DATA` segment in the dylib. Hashing the CF
    /// types through a generic function makes the library carry their type
    /// descriptors, and calling `ProbeWidgetGetTypeID` keeps `ProbeCF` among
    /// its load commands.
    private static let probeKitSource = """
    import Foundation

    public final class Anchor {}

    public struct Holder {
        public var widget: ProbeWidget
        public var gadget: ProbeGadget
        public var lonely: ProbeLonely

        public init(widget: ProbeWidget, gadget: ProbeGadget, lonely: ProbeLonely) {
            self.widget = widget
            self.gadget = gadget
            self.lonely = lonely
        }
    }

    @_cdecl("ProbeGadgetGetTypeID")
    public func probeGadgetGetTypeID() -> UInt {
        2
    }

    @inline(never)
    public func hashValue<Value: Hashable>(of value: Value) -> Int {
        value.hashValue
    }

    public func exercise(_ holder: Holder) -> Int {
        hashValue(of: holder.widget) &+ hashValue(of: holder.gadget) &+ hashValue(of: holder.lonely) &+ Int(ProbeWidgetGetTypeID())
    }
    """

    private struct FixtureLibraries: Sendable {
        let probeKitURL: URL
        let probeCFURL: URL
    }

    private static let fixtureLibraries = Result<FixtureLibraries, any Swift.Error>(catching: {
        let probeCFURL = try FixtureCompiler.shared.dynamicLibrary(named: "ProbeCF", language: .c, source: probeCFSource)
        let headerDirectoryURL = FileManager.default.temporaryDirectory
            .appending(component: "PrivateCFTypeModuleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: headerDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: headerDirectoryURL) }
        let headerURL = headerDirectoryURL.appending(component: "ProbeKit-Bridging-Header.h")
        try probeKitBridgingHeader.write(to: headerURL, atomically: true, encoding: .utf8)
        let probeKitURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "ProbeKit",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "ProbeKit.swift", contents: probeKitSource)],
            arguments: ["-swift-version", "5", "-import-objc-header", headerURL.path, "-Xlinker", probeCFURL.path]
        )
        return FixtureLibraries(probeKitURL: probeKitURL, probeCFURL: probeCFURL)
    })

    /// `ProbeKit`'s interface; with the provider, `ProbeCF` is its one
    /// resolvable dependency.
    private static func probeKitInterface(attachingTypeNameProvider: Bool) async throws -> String {
        let libraries = try fixtureLibraries.get()
        let probeKit = try HostSlice.machOFile(at: libraries.probeKitURL)
        let builder = try SwiftInterfaceBuilder(in: probeKit)
        if attachingTypeNameProvider {
            let dependencies = SwiftInterfaceBuilderDependencies(machO: probeKit, searchPaths: [.machOFile(path: libraries.probeCFURL.path)])
            let typeNameProvider = try #require(SwiftInterfaceBuilderTypeNameProvider(machO: probeKit, dependencies: dependencies))
            builder.addExtraDataProvider(typeNameProvider)
        }
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    @Test
    func aPrivateCFTypePrintsUnderTheImageExportingItsTypeID() async throws {
        let interface = try await Self.probeKitInterface(attachingTypeNameProvider: true)
        #expect(interface.contains("widget: libProbeCF.ProbeWidget"), "\(interface)")
    }

    @Test
    func aCFTypeTheRootDefinesPrintsUnderTheRootsModule() async throws {
        let interface = try await Self.probeKitInterface(attachingTypeNameProvider: true)
        #expect(interface.contains("gadget: libProbeKit.ProbeGadget"), "\(interface)")
    }

    /// No image exports `ProbeLonelyGetTypeID`, and nothing else in the binaries
    /// names the module that declares `ProbeLonelyRef` — the class it is
    /// bridged to is not recorded — so it keeps the descriptor's bare name.
    @Test
    func aBridgedTypeWithoutATypeIDFunctionKeepsItsBareSwiftName() async throws {
        let interface = try await Self.probeKitInterface(attachingTypeNameProvider: true)
        #expect(interface.contains("lonely: ProbeLonely\n"), "\(interface)")
    }

    /// What 0106 alone prints: the descriptor's Swift name, with no module.
    @Test
    func withoutTheProviderAPrivateCFTypeKeepsItsBareSwiftName() async throws {
        let interface = try await Self.probeKitInterface(attachingTypeNameProvider: false)
        #expect(interface.contains("widget: ProbeWidget"), "\(interface)")
    }
}

#endif
