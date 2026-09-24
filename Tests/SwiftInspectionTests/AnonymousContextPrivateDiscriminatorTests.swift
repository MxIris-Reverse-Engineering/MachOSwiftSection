import Foundation
import Testing
import MachOKit
import MachOObjCSection
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable @_spi(Internals) import SwiftInspection

/// A private type's descriptor hangs off an anonymous context, and the private
/// discriminator its name needs is recorded in only two places the demangler
/// reads today: the anonymous context's own mangled name, which the compiler
/// writes only under `-enable-anonymous-context-mangled-names` (a debugger flag,
/// off by default), and a symbol on the anonymous descriptor, which a dyld
/// shared cache image does not keep. Without either, `SymbolicDemangler` skips
/// the anonymous context and the type demangles as if it were internal.
///
/// Anchored on AppKit's private `FontPanelBIUSPopUpButton`. The discriminator
/// it has to come back with is read from the class's Objective-C runtime name
/// (`_TtC6AppKitP33_<discriminator>24FontPanelBIUSPopUpButton`), which the
/// compiler writes from the same declaration — so the expectation follows the
/// running system instead of pinning one build's hash.
@Suite(.serialized)
struct AnonymousContextPrivateDiscriminatorTests {
    private static let appKitPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

    private static let privateClassName = "FontPanelBIUSPopUpButton"

    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor class ships with macOS 26's AppKit"))
    func privateClassKeepsItsDiscriminatorInTheSystemCache() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
        let classDescriptor = try #require(try Self.classDescriptor(named: Self.privateClassName, in: machOFile))
        let expectedDiscriminator = try #require(try Self.discriminatorFromObjCRuntimeName(in: machOFile))

        let node = try SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machOFile)

        #expect(Self.privateDiscriminator(ofNominal: node) == expectedDiscriminator)
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor class ships with macOS 26's AppKit"))
    func privateClassKeepsItsDiscriminatorInProcess() throws {
        let machOImage = try Self.loadedAppKitImage()
        let classDescriptor = try #require(try Self.classDescriptor(named: Self.privateClassName, in: machOImage))
        let expectedDiscriminator = try #require(try Self.discriminatorFromObjCRuntimeName(in: machOImage))

        let node = try SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machOImage)

        #expect(Self.privateDiscriminator(ofNominal: node) == expectedDiscriminator)
    }

    /// The runtime-metadata paths demangle through `InProcessContext`, where a
    /// descriptor's "offset" is its address.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor class ships with macOS 26's AppKit"))
    func privateClassKeepsItsDiscriminatorThroughAnInProcessDescriptor() throws {
        let machOImage = try Self.loadedAppKitImage()
        let classDescriptor = try #require(try Self.classDescriptor(named: Self.privateClassName, in: machOImage))
        let expectedDiscriminator = try #require(try Self.discriminatorFromObjCRuntimeName(in: machOImage))
        let inProcessDescriptor: ContextDescriptorWrapper = try .resolve(from: machOImage.ptr.advanced(by: classDescriptor.offset))

        let node = try SymbolicDemangler.demangleContext(for: inProcessDescriptor)

        #expect(Self.privateDiscriminator(ofNominal: node) == expectedDiscriminator)
    }

    /// Every Swift class AppKit registers with the Objective-C runtime must
    /// demangle, from its descriptor, to the very name its Objective-C runtime
    /// name spells — private discriminators included. That equality is what
    /// lets a host pair the two faces of one class by name. The descriptor is
    /// reached through the class object itself (its Swift metadata's
    /// `Description`), so the pairing under test is the ground truth rather
    /// than a name match.
    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor class ships with macOS 26's AppKit"))
    func everySwiftClassDemanglesToItsObjCRuntimeName() throws {
        let machOImage = try Self.loadedAppKitImage()
        var comparedCount = 0
        var privateCount = 0
        var mismatches: [String] = []
        for classObject in machOImage.objcImplementationClassObjects() ?? [] where classObject.isSwiftStable {
            guard let readOnlyData = machOImage.instanceReadOnlyData(of: classObject),
                  let runtimeName = machOImage.className(of: readOnlyData),
                  runtimeName.hasPrefix("_Tt")
            else { continue }
            let metadata: ClassMetadataObjCInterop = try machOImage.readWrapperElement(offset: classObject.offset)
            let classDescriptor = try #require(try metadata.descriptor(in: machOImage), "\(runtimeName) has no class descriptor")
            let descriptorBuiltName = try Self.qualifiedName(ofNominal: SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machOImage))
            let runtimeNameBuiltName = try Self.qualifiedName(ofNominal: demangleAsNodeTransient(runtimeName))
            comparedCount += 1
            if runtimeName.contains("P33_") {
                privateCount += 1
            }
            if descriptorBuiltName != runtimeNameBuiltName {
                mismatches.append("\(runtimeName): descriptor \(descriptorBuiltName ?? "nil"), runtime name \(runtimeNameBuiltName ?? "nil")")
            }
        }
        #expect(comparedCount > 100, "AppKit on macOS 26 registers well over a hundred Swift classes")
        #expect(privateCount > 50, "and dozens of them are private")
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(comparedCount) differ:\n\(mismatches.joined(separator: "\n"))")
    }

    // MARK: - Helpers

    /// The nominal's fully qualified name, private discriminators spelled out.
    private static func qualifiedName(ofNominal node: Node) -> String? {
        var nominal = node
        while nominal.kind == .global || nominal.kind == .type || nominal.kind == .typeMangling, let child = nominal.children.first {
            nominal = child
        }
        guard nominal.kind == .class else { return nil }
        return nominal.print(using: .default)
    }

    /// The test process does not link AppKit, so it has to be mapped before a
    /// `MachOImage` can be made of it.
    private static func loadedAppKitImage() throws -> MachOImage {
        try #require(dlopen(appKitPath, RTLD_LAZY) != nil, "AppKit could not be loaded into the test process")
        return try #require(MachOImage(name: "AppKit"))
    }

    private static func classDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            if try classDescriptor.name(in: machO) == name {
                return classDescriptor
            }
        }
        return nil
    }

    /// The discriminator the Objective-C runtime name of the anchor class
    /// carries, demangled rather than sliced out of the string.
    private static func discriminatorFromObjCRuntimeName(in machO: some ObjCImplementationClassReading) throws -> String? {
        for classObject in machO.objcImplementationClassObjects() ?? [] {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let runtimeName = machO.className(of: readOnlyData),
                  runtimeName.hasPrefix("_TtC6AppKitP33_"),
                  runtimeName.hasSuffix(privateClassName)
            else { continue }
            let node = try demangleAsNodeTransient(runtimeName)
            return node.first(of: .privateDeclName)?.children.first?.text
        }
        return nil
    }

    /// The discriminator on the nominal's own name, or `nil` when the name is
    /// a plain identifier.
    private static func privateDiscriminator(ofNominal node: Node) -> String? {
        var nominal = node
        while nominal.kind == .global || nominal.kind == .type || nominal.kind == .typeMangling, let child = nominal.children.first {
            nominal = child
        }
        guard nominal.children.count >= 2, nominal.children[1].kind == .privateDeclName else { return nil }
        return nominal.children[1].children.first?.text
    }
}
