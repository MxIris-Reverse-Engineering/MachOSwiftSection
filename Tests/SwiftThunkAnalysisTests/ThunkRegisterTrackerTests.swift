import Testing
@testable import SwiftThunkAnalysis

/// What a register pair access does to its base register in the tracker
/// `ObjCMethodThunkReferences` reads addresses with.
@Suite
struct ThunkRegisterTrackerTests {
    private let base = ThunkRegister(number: 8)
    private let first = ThunkRegister(number: 0)
    private let second = ThunkRegister(number: 1)

    /// `ldp x0, x1, [x8], #16` and `stp x0, x1, [x8, #-16]!` move `x8`, so
    /// the address it held is no longer known.
    @Test func aWriteBackPairForgetsItsBase() {
        var loading = ThunkRegisterTracker()
        loading.apply(.materializePageAddress(destination: base, pageBaseAddress: 0x4000))
        loading.apply(.loadPairFromMemory(first: first, second: second, base: base, displacement: 0, adjustsBase: true))
        #expect(loading.address(of: base) == nil)

        var storing = ThunkRegisterTracker()
        storing.apply(.materializePageAddress(destination: base, pageBaseAddress: 0x4000))
        storing.apply(.storePairToMemory(first: first, second: second, base: base, displacement: -16, adjustsBase: true))
        #expect(storing.address(of: base) == nil)
    }

    /// Without write-back the base keeps its address.
    @Test func aPairWithoutWriteBackKeepsItsBase() {
        var tracker = ThunkRegisterTracker()
        tracker.apply(.materializePageAddress(destination: base, pageBaseAddress: 0x4000))
        tracker.apply(.loadPairFromMemory(first: first, second: second, base: base, displacement: 16, adjustsBase: false))
        tracker.apply(.storePairToMemory(first: first, second: second, base: base, displacement: 16, adjustsBase: false))
        #expect(tracker.address(of: base) == 0x4000)
    }
}
