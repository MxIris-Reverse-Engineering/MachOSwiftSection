import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Validates phase 4: a Swift class whose ancestor is an Objective-C class
/// (`NSObject`) has no Swift superclass descriptor, so its first stored property
/// starts at the ObjC ancestor's `class_ro_t` instance size (8 for `NSObject` —
/// just the `isa`). The dependency closure reaches the framework defining the
/// ancestor (`libobjc`), so these offsets — left partial by the single-image
/// engine — resolve.
///
/// The runtime field-offset vector is non-empty for ObjC-rooted Swift classes,
/// so the assertions are checked against it automatically (no pinned literals
/// beyond the human-readable expectation).
@Suite
final class ObjCAncestorLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    private static let objCMembersTestName = "SymbolTestsCore.Classes.ObjCMembersTest"
    private static let objCBridgeName = "SymbolTestsCore.ObjCClassWrapperFixtures.ObjCBridge"
    private static let objCBridgeWithProtoName = "SymbolTestsCore.ObjCClassWrapperFixtures.ObjCBridgeWithProto"

    /// ObjC-rooted classes with at least one stored field. Each field lands right
    /// after `NSObject`'s instance size (8): `ObjCMembersTest.property` (`Int`)
    /// and `ObjCBridge.label` (`String`, 8-aligned) are both at offset 8.
    private static let expectedObjCAncestorFieldOffsets: [String: [Int]] = [
        objCMembersTestName: [8],
        objCBridgeName: [8],
    ]

    // MARK: - In-process closure (automatic runtime cross-check)

    /// With the in-process closure, the ObjC ancestor resolves and the
    /// statically-computed field offsets match the runtime field-offset vector
    /// exactly — a fully automatic cross-check that the ObjC `instanceSize` start
    /// is correct.
    @MainActor
    @Test func inProcessClosureResolvesObjCAncestorFields() async throws {
        let machO = machOImage
        let universe = try ImageUniverse.dependencyClosure(root: machO)
        #expect(universe.dependencyImageCount > 0, "the closure must collect dependency images")
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        for (typeName, expectedOffsets) in Self.expectedObjCAncestorFieldOffsets {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: expectedOffsets, typeName: typeName)

            // Independent ground truth: the runtime field-offset vector must match
            // the statically-computed offsets.
            let runtimeOffsets = try runtimeFieldOffsets(ofQualifiedTypeName: typeName, in: machO)
            #expect(
                runtimeOffsets == expectedOffsets,
                "\(typeName) runtime vector \(String(describing: runtimeOffsets)) must match \(expectedOffsets)"
            )
        }
    }

    /// An ObjC-rooted class with no stored properties: the ancestor still
    /// resolves (so nothing degrades to `unknown`) and the field vector is empty.
    @MainActor
    @Test func inProcessClosureResolvesFieldlessObjCAncestorClass() async throws {
        let machO = machOImage
        let universe = try ImageUniverse.dependencyClosure(root: machO)
        let calculator = StaticLayoutCalculator(imageUniverse: universe)

        let aggregate = try fieldLayout(ofQualifiedTypeName: Self.objCBridgeWithProtoName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: [], typeName: Self.objCBridgeWithProtoName)

        let runtimeOffsets = try runtimeFieldOffsets(ofQualifiedTypeName: Self.objCBridgeWithProtoName, in: machO)
        #expect(runtimeOffsets == [], "ObjCBridgeWithProto has no stored properties")
    }

    // MARK: - Single-image regression guard

    /// The single-image engine cannot reach the ObjC ancestor's `class_ro_t`, so
    /// a class with stored fields degrades to all-unknown — demonstrating the
    /// dependency closure is what resolves these. (The field-less class is
    /// excluded: with no fields it is trivially "fully computed" whether or not
    /// the ancestor resolved.)
    @MainActor
    @Test func singleImageEngineLeavesObjCAncestorClassesPartial() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        for typeName in Self.expectedObjCAncestorFieldOffsets.keys {
            let aggregate = try fieldLayout(ofQualifiedTypeName: typeName, with: calculator, in: machO)
            let isFullyComputed = aggregate.fields.allSatisfy {
                if case .computed = $0.resolution { return true } else { return false }
            }
            #expect(!isFullyComputed, "\(typeName) is expected to be partial under the single-image engine")
        }
    }
}
