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
    
    @OptionGroup
    var machOOptions: MachOOptionGroup
    
    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String?
    
    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none
    
    @Flag(name: .customLong("enable-type-indexing"), help: "Enable type indexing for the generated Swift interface.")
    var isEnabledTypeIndexing: Bool = false
    
    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)
        
        let configuration = SwiftInterfaceBuilderConfiguration(isEnabledTypeIndexing: isEnabledTypeIndexing)
        
        let builder = try SwiftInterfaceBuilder(configuration: configuration, in: machOFile)
        
        print("Preparing to build Swift interface...")
        
        try await builder.prepare()
        
        print("Building Swift interface...")
        
        let interfaceString = try builder.build()
        
        print("Swift interface built successfully.")
        
        if let outputPath {
            print("Writing Swift interface to \(outputPath)...")
            let outputURL = URL(fileURLWithPath: outputPath)
            try interfaceString.string.write(to: outputURL, atomically: true, encoding: .utf8)
        } else {
            interfaceString.printColorfully(using: colorScheme)
        }
    }
}
