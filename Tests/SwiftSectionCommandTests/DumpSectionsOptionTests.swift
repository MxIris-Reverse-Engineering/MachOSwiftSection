import Testing
import ArgumentParser
import SwiftSectionKit
@testable import swift_section

/// `dump --sections` accepts the `objcImplementationClasses` section
/// (evolution proposal `objc-implementation-class-recognition`) and keeps it
/// in the default (all-sections) run.
struct DumpSectionsOptionTests {
    @Test func objcImplementationClassesIsASection() throws {
        let command = try DumpCommand.parse(["/tmp/example", "--sections", "types", "objcImplementationClasses"])
        #expect(command.sections == [.types, .objcImplementationClasses])
        #expect(DumpSection.allCases.contains(.objcImplementationClasses))
    }
}
