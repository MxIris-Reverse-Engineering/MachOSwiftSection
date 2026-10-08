import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftLayout

/// Where the simulator-runtime-gated suite below finds its runtime. A
/// separate type on purpose: a `@Suite(.enabled(if:))` condition that reads a
/// static of the suite it decorates is a circular macro reference.
enum IOS18SimulatorRuntimeFixtures {
    /// The iOS 18.5 simulator runtime's `RuntimeRoot`, on whichever volume
    /// CoreSimulator mounted it.
    static let runtimeRootPath: String? = {
        let volumesDirectory = "/Library/Developer/CoreSimulator/Volumes"
        let runtimeSuffix = "Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.5.simruntime/Contents/Resources/RuntimeRoot"
        let volumeNames = (try? FileManager.default.contentsOfDirectory(atPath: volumesDirectory)) ?? []
        return volumeNames.sorted()
            .map { "\(volumesDirectory)/\($0)/\(runtimeSuffix)" }
            .first { FileManager.default.fileExists(atPath: "\($0)/System/Library/Frameworks/SwiftUI.framework/SwiftUI") }
    }()

    static func swiftUI(underRuntimeRoot runtimeRootPath: String) throws -> MachOFile {
        let url = URL(fileURLWithPath: "\(runtimeRootPath)/System/Library/Frameworks/SwiftUI.framework/SwiftUI")
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let thinFile):
            return thinFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }, "the runtime's SwiftUI has no arm64 slice")
        }
    }
}

/// A simulator runtime's frameworks are linked `-interposable`, so UIKitCore
/// reaches every class it exports through a bind to itself — its class list
/// entry included. Reading only rebases, the ObjC reader lost 1,586 of
/// UIKitCore's 5,017 classes, `UIDocument` among them, and a Swift class
/// deriving from one could not place its own fields:
/// `// Field offset: unknown (Objective-C ancestor UIDocument unresolved)`.
@Suite(.enabled(if: IOS18SimulatorRuntimeFixtures.runtimeRootPath != nil))
struct SimulatorRuntimeObjCAncestorLayoutTests {
    @Test("A Swift class places its fields after an ObjC ancestor its dependency binds to itself")
    func fieldsStartAfterASelfBoundObjCAncestor() throws {
        let runtimeRootPath = try #require(IOS18SimulatorRuntimeFixtures.runtimeRootPath)
        let swiftUI = try IOS18SimulatorRuntimeFixtures.swiftUI(underRuntimeRoot: runtimeRootPath)
        let universe = try ImageUniverse.dependencyClosure(root: swiftUI, searchPaths: [.systemRoot(path: runtimeRootPath)])
        let calculator = StaticLayoutCalculator(imageUniverse: universe)
        // The universe indexes the root's types up front; scanning SwiftUI's
        // descriptors again by name would demangle every one of them.
        let platformDocumentDescriptor = try #require(universe.resolveType(byQualifiedTypeName: "SwiftUI.PlatformDocument")?.descriptor)
        let platformDocument = try calculator.fieldLayout(of: platformDocumentDescriptor)
        // `UIDocument`'s `class_ro_t.instanceSize` in the runtime's UIKitCore
        // is 0xc4 (read with xxd); its subclass's first field is 8-aligned.
        #expect(platformDocument.computedFieldOffsets.first == 0xc8)
    }
}
