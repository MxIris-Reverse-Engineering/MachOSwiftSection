import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Command-line surface of the ObjC member recovery's name-only third tier
/// (evolution proposal `objc-member-selector-recovery`).
///
/// The tier itself always runs; the flag decides whether the INTERFACE
/// prints the keyword it implies, and defaults to off — a .swiftinterface
/// has nowhere to say a keyword rests on a name. `dump` names every tie's
/// evidence and so renders the tier unconditionally, which is why the flag
/// is not on that command at all.
@Suite
struct InferObjCOverridesFlagTests {
    @Test func interfaceFlagDefaultsOff() throws {
        let command = try InterfaceCommand.parse(["/tmp/example"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == false)
    }

    @Test func interfaceFlagParses() throws {
        let command = try InterfaceCommand.parse(["/tmp/example", "--infer-objc-overrides"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == true)
    }

    /// `dump` renders the tier always, so it takes no flag — passing one is
    /// an error rather than a silent no-op.
    @Test func dumpRejectsTheFlag() throws {
        #expect(throws: (any Error).self) {
            _ = try DumpCommand.parse(["/tmp/example", "--infer-objc-overrides"])
        }
    }
}
