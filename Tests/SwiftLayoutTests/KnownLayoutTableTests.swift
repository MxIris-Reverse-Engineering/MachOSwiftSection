import Testing
@testable import SwiftLayout

/// Pure data tests for the hard-coded frozen-ABI layout table.
@Suite
struct KnownLayoutTableTests {
    @Test func wordSizedIntegerIsEightBytes() {
        let layout = KnownLayoutTable.layout(forFullyQualifiedTypeName: "Swift.Int")
        #expect(layout?.size == 8)
        #expect(layout?.stride == 8)
        #expect(layout?.alignmentMask == 7)
    }

    @Test func boolIsOneByteWithSpareInhabitants() {
        let layout = KnownLayoutTable.layout(forFullyQualifiedTypeName: "Swift.Bool")
        #expect(layout?.size == 1)
        #expect(layout?.extraInhabitantCount == 254)
    }

    @Test func referenceBackedContainersAreSinglePointers() {
        for containerName in ["Swift.Array", "Swift.Dictionary", "Swift.Set"] {
            let layout = KnownLayoutTable.layout(forFullyQualifiedTypeName: containerName)
            #expect(layout?.size == 8, "\(containerName) should be a single buffer pointer")
            #expect(layout?.alignmentMask == 7)
        }
    }

    @Test func stringIsSixteenBytes() {
        let layout = KnownLayoutTable.layout(forFullyQualifiedTypeName: "Swift.String")
        #expect(layout?.size == 16)
        #expect(layout?.alignmentMask == 7)
    }

    @Test func unknownTypeReturnsNil() {
        #expect(KnownLayoutTable.layout(forFullyQualifiedTypeName: "MyModule.MyType") == nil)
    }
}
