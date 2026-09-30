import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
import MachOObjCSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@_spi(Internals) @testable import SwiftInspection

/// `SwiftClassObjectIndex` (evolution proposal `objc-custom-class-name`):
/// the runtime name a source gave a Swift class, read off the class metadata
/// — the class object's flag word and descriptor pointer, or for a class
/// with a resilient superclass its metadata pattern — through both readers.
@Suite(.serialized, ExclusiveImageAccess(RenamedObjCClassFixture.moduleName))
struct SwiftClassObjectIndexTests {
    private static func classDescriptor(named name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor {
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor, try classDescriptor.name(in: machO.context) == name else { continue }
            return classDescriptor
        }
        Issue.record("no class named \(name)")
        throw RenamedObjCClassFixture.CompilationError(step: "lookup", diagnostics: "class \(name) not found")
    }

    private static func customObjCClassName(ofClassNamed name: String, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> CustomObjCClassName? {
        SwiftClassObjectIndex.shared.customObjCClassName(forClassDescriptorOffset: try classDescriptor(named: name, in: machO).offset, in: machO)
    }

    private static func expectRenamedClasses(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        #expect(try customObjCClassName(ofClassNamed: "RenamedWidget", in: machO) == CustomObjCClassName(name: "RCFRenamedWidget", attribute: .objc))
        #expect(try customObjCClassName(ofClassNamed: "RCFSameNameWidget", in: machO) == CustomObjCClassName(name: "RCFSameNameWidget", attribute: .objc))
        #expect(try customObjCClassName(ofClassNamed: "NestedWidget", in: machO) == CustomObjCClassName(name: "RCFNestedWidget", attribute: .objc))
        #expect(try customObjCClassName(ofClassNamed: "NativeRoot", in: machO) == CustomObjCClassName(name: "RCFNativeRoot", attribute: .objcRuntimeName))
        #expect(try customObjCClassName(ofClassNamed: "RenamedActor", in: machO) == CustomObjCClassName(name: "RCFRenamedActor", attribute: .objc))
        #expect(try customObjCClassName(ofClassNamed: "ResilientChild", in: machO) == CustomObjCClassName(name: "RCFResilientChild", attribute: .objc))
        #expect(try customObjCClassName(ofClassNamed: "PlainWidget", in: machO) == nil)
        #expect(try customObjCClassName(ofClassNamed: "PlainDrifter", in: machO) == nil)

        let moduleName = RenamedObjCClassFixture.moduleName
        #expect(SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: "\(moduleName).RenamedWidget", in: machO) == ["RCFRenamedWidget"])
        #expect(SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: "\(moduleName).Namespace.NestedWidget", in: machO) == ["RCFNestedWidget"])
        // A resilient superclass keeps the class out of the class list: no
        // class object, so no runtime name for the name-keyed indexes.
        #expect(SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: "\(moduleName).ResilientChild", in: machO).isEmpty)
        #expect(SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: "\(moduleName).PlainWidget", in: machO).isEmpty)
    }

    @Test func renamedClassesAreReadFromTheFile() throws {
        try Self.expectRenamedClasses(in: try RenamedObjCClassFixture.machOFile(.full))
    }

    @Test func renamedClassesAreReadInProcess() throws {
        try Self.expectRenamedClasses(in: try RenamedObjCClassFixture.loadedImage())
    }

    /// The compile-time `instanceStart` the layout engine slides from: 8, the
    /// root's isa — the compiler leaves an Objective-C superclass's size to
    /// the runtime. A class with a resilient superclass has no class object
    /// to carry one.
    @Test func renamedClassKeepsItsOwnInstanceStart() throws {
        let machOFile = try RenamedObjCClassFixture.machOFile(.full)
        let drifterDescriptor = try Self.classDescriptor(named: "RenamedDrifter", in: machOFile)
        let resilientChildDescriptor = try Self.classDescriptor(named: "ResilientChild", in: machOFile)
        let drifterInstanceStart = SwiftClassObjectIndex.shared.renamedClassInstanceStart(forClassDescriptorOffset: drifterDescriptor.offset, in: machOFile)
        let resilientChildInstanceStart = SwiftClassObjectIndex.shared.renamedClassInstanceStart(forClassDescriptorOffset: resilientChildDescriptor.offset, in: machOFile)
        #expect(drifterInstanceStart == 8)
        #expect(resilientChildInstanceStart == nil)
    }

    /// The flag word is read at its own width. Read as an Optional, it took
    /// the byte after it — `instanceAddressPoint`'s low byte — as the
    /// Optional's tag, and a non-zero one dropped the class. The compiler
    /// always writes zero there, so a patched copy of the library sets it.
    @Test func renamedClassSurvivesANonZeroByteAfterTheFlagWord() throws {
        let original = try RenamedObjCClassFixture.machOFile(.full)
        let swiftClassObjectOffsets = (original.objcImplementationClassObjects() ?? []).filter(\.isSwift).map(\.offset)
        try #require(!swiftClassObjectOffsets.isEmpty)
        let byteAfterFlagWord = try #require(MemoryLayout<ClassMetadataObjCInterop.Layout>.offset(of: \.instanceAddressPoint))
        let uuidCommand = try #require(original.loadCommands.info(of: LoadCommand.uuid))

        var libraryBytes = try Data(contentsOf: RenamedObjCClassFixture.libraryURL(.full))
        for classObjectOffset in swiftClassObjectOffsets {
            libraryBytes[original.headerStartOffset + classObjectOffset + byteAfterFlagWord] = 0x01
        }
        // A copy with the original's UUID and install name is the same image
        // to every per-image cache, which would answer from the original's
        // index without reading the patched bytes.
        libraryBytes[original.cmdsStartOffset + uuidCommand.offset + MemoryLayout<load_command>.size] ^= 0xFF
        let patchedLibraryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(RenamedObjCClassFixture.moduleName)-byteAfterFlagWord-\(UUID().uuidString).dylib")
        try libraryBytes.write(to: patchedLibraryURL)
        defer { try? FileManager.default.removeItem(at: patchedLibraryURL) }

        let patched = try MachOFile(url: patchedLibraryURL, headerStartOffset: original.headerStartOffset)
        try #require(patched.identifier != original.identifier)
        let renamedWidgetName = try Self.customObjCClassName(ofClassNamed: "RenamedWidget", in: patched)
        #expect(renamedWidgetName == CustomObjCClassName(name: "RCFRenamedWidget", attribute: .objc))
    }
}

/// The shared fixture's two `@objc(Name)` classes, through every reader.
@Suite
final class SwiftClassObjectIndexFixtureTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func expectObjCBridgeClasses(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        var namesByClassName: [String: CustomObjCClassName?] = [:]
        for typeContextDescriptor in try machO.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            let name = try classDescriptor.name(in: machO.context)
            guard ["ObjCBridge", "ObjCBridgeWithProto", "ObjCAttributeClass"].contains(name) else { continue }
            namesByClassName[name] = SwiftClassObjectIndex.shared.customObjCClassName(forClassDescriptorOffset: classDescriptor.offset, in: machO)
        }
        #expect(namesByClassName["ObjCBridge"] == CustomObjCClassName(name: "SymbolTestsCoreObjCBridgeClass", attribute: .objc))
        #expect(namesByClassName["ObjCBridgeWithProto"] == CustomObjCClassName(name: "SymbolTestsCoreObjCBridgeWithProto", attribute: .objc))
        // An `NSObject` subclass the source did not rename.
        #expect(namesByClassName["ObjCAttributeClass"] == .some(nil))
        #expect(SwiftClassObjectIndex.shared.customRuntimeNames(forSwiftClassQualifiedName: "SymbolTestsCore.ObjCClassWrapperFixtures.ObjCBridge", in: machO) == ["SymbolTestsCoreObjCBridgeClass"])
    }

    @MainActor
    @Test func objcBridgeClassesInTheFile() throws {
        try expectObjCBridgeClasses(in: machOFile)
    }

    @MainActor
    @Test func objcBridgeClassesInProcess() throws {
        try expectObjCBridgeClasses(in: machOImage)
    }
}
