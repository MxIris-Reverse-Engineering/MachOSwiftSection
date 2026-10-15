import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
import SwiftInspection

final class ProtocolGenericContextTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func test() async throws {
        let machO = machOFile

        let protocols = try machO.swift.protocols

        for `protocol` in protocols {
            if let genericContext = try `protocol`.descriptor.genericContext(in: machO.context) {
                try await genericContext.dumpGenericSignature(resolver: .using(options: .default), depthLayout: GenericParameterDepthLayout.make(for: genericContext, ownedBy: `protocol`.descriptor, in: machO.context), in: machO.context).string.print()
            }
        }
    }
}
