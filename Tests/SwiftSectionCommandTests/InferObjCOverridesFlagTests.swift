import Foundation
import Testing
import ArgumentParser
@testable import swift_section

/// Command-line surface of the ObjC member recovery's name-only third tier
/// (evolution proposal `objc-member-selector-recovery`): `--infer-objc-overrides`
/// exists on both `interface` and `dump`, and defaults to off — the recovery
/// joins by default, it does not guess.
@Suite
struct InferObjCOverridesFlagTests {
    @Test func interfaceFlagDefaultsOff() throws {
        let command = try InterfaceCommand.parse(["/tmp/example"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == false)
        #expect(command.objcMemberOptions.recoveryOptions == .default)
    }

    @Test func interfaceFlagParses() throws {
        let command = try InterfaceCommand.parse(["/tmp/example", "--infer-objc-overrides"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == true)
        #expect(command.objcMemberOptions.recoveryOptions.infersOverridesFromSelectorNames)
    }

    @Test func dumpFlagDefaultsOff() throws {
        let command = try DumpCommand.parse(["/tmp/example"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == false)
    }

    @Test func dumpFlagParses() throws {
        let command = try DumpCommand.parse(["/tmp/example", "--infer-objc-overrides"])
        #expect(command.objcMemberOptions.infersOverridesFromSelectorNames == true)
    }
}
