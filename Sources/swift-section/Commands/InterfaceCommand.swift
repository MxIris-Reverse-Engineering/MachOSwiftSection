import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface
import ArgumentParser

struct InterfaceCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "interface",
        abstract: "Generate Swift interface from a Mach-O file."
    )

    @Argument(help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @Flag(help: "Show imported C types in the generated Swift interface.")
    var showCImportedTypes: Bool = false

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

        let configuration = SwiftInterfaceBuilderConfiguration(showCImportedTypes: showCImportedTypes)

        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [OSLogEventHandler()], in: machOFile)

        print("Preparing to build Swift interface...")

        try await builder.prepare()

        print("Building Swift interface...")

        let interfaceString = try builder.printRoot()

        print("Swift interface built successfully.")

        print("Writing Swift interface to \(outputPath)...")
        let outputURL = URL(fileURLWithPath: outputPath)
        try interfaceString.string.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
