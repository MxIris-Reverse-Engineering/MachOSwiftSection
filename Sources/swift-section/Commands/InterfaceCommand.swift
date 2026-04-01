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

    @Flag(help: "Show imported C types in the generated Swift interface.")
    var showCImportedTypes: Bool = false

    @Flag(help: "Parse opaque return value, this option is an experimental feature and may result in parsing errors for complex return types.")
    var parseOpaqueReturnType: Bool = false

    @Flag(help: "Generate field offset and PWT offset comments, if possible")
    var emitOffsetComments: Bool = false

    @Flag(help: "Generate member address comments for each member symbol")
    var emitMemberAddresses: Bool = false

    @Flag(help: "Generate vtable offset comments for class methods and computed properties")
    var emitVtableOffsets: Bool = false

    @Flag(help: "Expand nested struct fields with their absolute offsets (requires --emit-offset-comments)")
    var emitExpandedFieldOffsets: Bool = false

    @Flag(help: "Sort members by binary layout offset instead of grouping by category")
    var sortMembersByOffset: Bool = false

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: showCImportedTypes
            ),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: emitOffsetComments,
                printExpandedFieldOffsets: emitExpandedFieldOffsets,
                printMemberAddress: emitMemberAddresses,
                printVTableOffset: emitVtableOffsets,
                memberSortOrder: sortMembersByOffset ? .byOffset : .byCategory
            )
        )

        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [ConsoleEventHandler()], in: machOFile)

        if parseOpaqueReturnType {
            builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        }

        print("Preparing to build Swift interface...")

        try await builder.prepare()

        print("Building Swift interface...")

        let interfaceString = try await builder.printRoot()

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
