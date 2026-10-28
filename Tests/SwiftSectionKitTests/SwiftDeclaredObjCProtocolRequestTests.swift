import Foundation
import Testing
import SwiftSectionKit
@testable import MachOTestingSupport

/// `dump`'s `protocols` section and `interface` carry the `@objc` protocols
/// a Swift module declares (evolution proposal
/// `swift-declared-objc-protocols`), which have no protocol descriptor.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct SwiftDeclaredObjCProtocolRequestTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private static func source() throws -> MachOSource {
        .file(path: try SwiftDeclaredObjCProtocolsFixture.libraryURL(.full).path, architecture: nil)
    }

    @Test("Both dump orderings list the protocols, then the records no protocol claims", arguments: [DumpRequest.Ordering.bySection, .binaryOrder])
    func dumpListsTheProtocols(ordering: DumpRequest.Ordering) async throws {
        let output = RecordingOutput()
        try await DumpRequest(
            source: try Self.source(),
            dependencySearchPaths: try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths(),
            ordering: ordering
        ).run(output: output, environment: .testing)
        let product = output.printedProduct

        for name in ["DerivedSelectors", "SameNameRenamed", "DifferentlyNamed", "RefinedProtocol", "InternalProtocol", "Outer.NestedProtocol"] {
            #expect(product.contains(" protocol \(Self.moduleName).\(name)"), "\(name)\n---\n\(product)")
        }
        let unclaimedRecords = try #require(product.range(of: "// ObjC protocol records emitted by Swift that no protocol of this image claims"), "\(product)")
        let lastProtocol = try #require(product.range(of: " protocol \(Self.moduleName).", options: .backwards), "\(product)")
        #expect(lastProtocol.upperBound < unclaimedRecords.lowerBound, "\(product)")
    }

    @Test("The interface declares the protocols")
    func interfaceDeclaresTheProtocols() async throws {
        let output = RecordingOutput()
        try await InterfaceRequest(
            source: try Self.source(),
            dependencySearchPaths: try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths()
        ).run(output: output, environment: .testing)
        let product = output.printedProduct

        #expect(product.contains("@objc protocol DerivedSelectors: __C.NSObject {"), "\(product)")
        #expect(product.contains("@objc(SameNameRenamed) protocol SameNameRenamed {"), "\(product)")
        #expect(product.contains("extension \(Self.moduleName).Outer {\n    @objc protocol NestedProtocol {"), "\(product)")
    }
}
