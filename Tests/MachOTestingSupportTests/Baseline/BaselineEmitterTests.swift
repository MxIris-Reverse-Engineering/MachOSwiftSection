import Foundation
import Testing
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
struct BaselineEmitterTests {
    @Test func emitsIntHex() {
        #expect(BaselineEmitter.hex(0x10) == "0x10")
    }

    @Test func emitsZeroHex() {
        #expect(BaselineEmitter.hex(0) == "0x0")
    }

    @Test func emitsUInt32Hex() {
        #expect(BaselineEmitter.hex(UInt32(0x40000051)) == "0x40000051")
    }

    @Test func emitsNegativeIntAsTwosComplementHex() {
        // Negative Int sign-extends to UInt64 representation.
        #expect(BaselineEmitter.hex(Int(-1)) == "0xffffffffffffffff")
    }

    @Test func emitsHexArray() {
        #expect(BaselineEmitter.hexArray([0x10, 0x18, 0x28]) == "[0x10, 0x18, 0x28]")
    }

    @Test func emitsEmptyHexArray() {
        #expect(BaselineEmitter.hexArray([Int]()) == "[]")
    }
}
