import Foundation
import Testing
@testable import Demangle

struct DemanglingTests {
    @Test func test() async throws {
        var demangler = Demangler(scalars: "_$ss8RangeSetV7SwiftUISxRzSZ6StrideRpzrlE13IndexSequenceV8IteratorVySi__G".unicodeScalars)
        print(try demangler.demangleSymbol().print())
    }
}
