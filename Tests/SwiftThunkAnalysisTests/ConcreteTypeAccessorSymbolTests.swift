import Foundation
import Testing
@_spi(Internals) import Demangling
@testable import SwiftThunkAnalysis

/// Which accessor symbols may name a type by themselves.
///
/// A lazily specialized accessor (`type metadata accessor for
/// Mutex<Set<String>>`) takes no arguments and spells the whole type. Two
/// look-alikes must not be taken: the unbound accessor a descriptor points
/// at, whose arguments come from the call; and a *merged* accessor, whose
/// symbol keeps the name of one of the bodies the compiler folded together
/// while the callee it reaches is a function-pointer argument — on iOS 26.5
/// simulator SwiftUICore that mistake printed `Array<LayoutDirection>` for a
/// `Mutex<Storage>` field.
@Suite
struct ConcreteTypeAccessorSymbolTests {
    private func isConcrete(_ symbolName: String) throws -> Bool {
        MachOThunkEnvironment.isConcreteTypeAccessorSymbol(try demangleAsNodeTransient(symbolName))
    }

    @Test func aSpecializedAccessorNamesItsType() throws {
        #expect(try isConcrete("_$s15Synchronization5MutexVyShySSGGMa"))
        #expect(try isConcrete("_$s15Synchronization5MutexVy7SwiftUI21MaterialBackdropProxyV7Storage33_DEF3755CDC6B87C0368876C9F497EC3DLLC4DataVGMa"))
    }

    @Test func anUnboundAccessorDoesNot() throws {
        #expect(try !isConcrete("_$s15Synchronization5MutexVMa"))
        #expect(try !isConcrete("_$s7SwiftUI13_TaskModifierVMa"))
    }

    @Test func aMergedAccessorDoesNot() throws {
        #expect(try !isConcrete("_$sypSgMaTm"))
        #expect(try !isConcrete("_$ss8RangeSetVySS5IndexVGMaTm"))
    }

    @Test func anythingElseDoesNot() throws {
        #expect(try !isConcrete("_$s15Synchronization5MutexVMn"))
        #expect(try !isConcrete("_$s7SwiftUI22BGTaskSchedulerWrapperC11observeTaskyySSSgF"))
    }
}
