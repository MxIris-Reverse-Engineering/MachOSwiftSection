import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable @_spi(Internals) import SwiftInspection
@testable import SwiftDeclarationRendering

/// A name that comes from the runtime (`_mangledTypeName`) spells a private
/// type's anonymous context by the descriptor's address. It has to come out
/// carrying the discriminator the name built from the descriptors carries —
/// which, for an OS framework in the dyld shared cache, only a `_symbolic`
/// symbol records (`AnonymousContextPrivateDiscriminatorIndex`). Dropping the
/// anonymous context instead, as `RuntimeTypeNameDemangling` used to, left the
/// two names disagreeing about the same type.
///
/// Anchored on AppKit's private `FontPanelBIUSPopUpButton`, reached through
/// its Objective-C runtime name.
@Suite(.serialized)
struct RuntimeTypeNamePrivateDiscriminatorTests {
    private static let appKitPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

    private static let privateClassName = "FontPanelBIUSPopUpButton"

    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "the anchor class ships with macOS 26's AppKit"))
    func runtimeNameCarriesTheDiscriminatorOfTheDescriptorBuiltName() throws {
        try #require(dlopen(Self.appKitPath, RTLD_LAZY) != nil, "AppKit could not be loaded into the test process")
        let machOImage = try #require(MachOImage(name: "AppKit"))
        let classDescriptor = try #require(try Self.classDescriptor(named: Self.privateClassName, in: machOImage))
        let descriptorBuiltNode = try SymbolicDemangler.demangleContext(for: .type(.class(classDescriptor)), in: machOImage)
        let descriptorBuiltDiscriminator = try #require(Self.privateDiscriminator(ofNominal: descriptorBuiltNode))
        let objcRuntimeName = try #require(Self.objcRuntimeName(in: machOImage))
        let privateClass: AnyClass = try #require(NSClassFromString(objcRuntimeName))

        let runtimeNode = try #require(RuntimeTypeNameDemangling.node(forMetatype: privateClass))

        #expect(Self.privateDiscriminator(ofNominal: runtimeNode) == descriptorBuiltDiscriminator)
        #expect(runtimeNode.first(of: .anonymousContext) == nil)
    }

    // MARK: - Helpers

    private static func classDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            if try classDescriptor.name(in: machO) == name {
                return classDescriptor
            }
        }
        return nil
    }

    private static func objcRuntimeName(in machO: some ObjCImplementationClassReading) -> String? {
        for classObject in machO.objcImplementationClassObjects() ?? [] {
            guard let readOnlyData = machO.instanceReadOnlyData(of: classObject),
                  let runtimeName = machO.className(of: readOnlyData),
                  runtimeName.hasPrefix("_TtC6AppKitP33_"),
                  runtimeName.hasSuffix(privateClassName)
            else { continue }
            return runtimeName
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
