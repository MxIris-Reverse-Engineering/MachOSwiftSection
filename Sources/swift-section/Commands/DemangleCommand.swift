import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import ArgumentParser

struct DemangleCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "demangle",
        abstract: "Demangle mangled name in a Mach-O file."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @Option(name: .shortAndLong, help: "The mangled name to demangle.")
    var mangledName: String

    @Option(name: .shortAndLong, help: "The offset of the mangled name in the Mach-O file. If not specified, it will be assumed to be 0.")
    var fileOffset: Int?

    @OptionGroup
    var demangleOptionGroup: DemangleOptionGroup

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)
        let demangledNode = try MetadataReader.demangleSymbol(for: .init(offset: fileOffset ?? 0, name: mangledName), in: machOFile)
        let demangleOptions = demangleOptionGroup.buildSwiftDumpDemangleOptions()
        print(mangledName, "--->", demangledNode?.print(using: demangleOptions) ?? mangledName)
    }
}
