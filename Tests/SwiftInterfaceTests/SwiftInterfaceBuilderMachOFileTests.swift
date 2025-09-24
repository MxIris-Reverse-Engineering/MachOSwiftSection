import Foundation
import Testing
import MachOKit
@testable import MachOTestingSupport
@testable import SwiftInterface

class SwiftInterfaceBuilderMachOFileTests: MachOFileTests {
    override class var fileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }

    @Test func buildFile() async throws {
        let machO = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: .init(isEnabledTypeIndexing: false), eventHandlers: [OSLogEventHandler()], in: machO)
        builder.setDependencyPaths([.usesSystemDyldSharedCache])
        try await builder.prepare()
        try builder.build().string.write(to: .desktopDirectory.appending(path: "\(machO.imagePath.lastPathComponent)-Dump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}
