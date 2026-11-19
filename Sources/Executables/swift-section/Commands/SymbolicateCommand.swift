import ArgumentParser
import Foundation
import SwiftSectionKit

struct SymbolicateCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "symbolicate",
        abstract: "Say what each unslid address is — inside which function, a stub and where it leads, a pointer slot and what it holds, a string, the nearest symbol — in a dyld shared cache or a set of arm64 Mach-O files.",
        discussion: "Each line is an address: the address, its image, its segment and section, and what lies there."
    )

    @Argument(help: "Unslid addresses, 0x… or decimal.")
    var addresses: [String] = []

    @Option(name: .customLong("file"), help: "A Mach-O file to analyze. Repeatable: files are read together, as dyld would load them.", completion: .file())
    var filePaths: [String] = []

    @OptionGroup var inputOptions: CrossReferenceInputOptionGroup

    @Flag(help: "Print one JSON document; its addresses are hexadecimal strings.")
    var json: Bool = false

    func validate() throws {
        guard !addresses.isEmpty else { throw ValidationError("Name at least one address.") }
        for address in addresses {
            _ = try parseAddress(address)
        }
        if inputOptions.imageNames.count > 1 {
            throw ValidationError("--in-image names the one image whose addresses these are.")
        }
        _ = try inputOptions.input(filePaths: filePaths)
    }

    /// The library request these flags describe.
    func makeRequest() throws -> SymbolicateRequest {
        SymbolicateRequest(
            input: try inputOptions.input(filePaths: filePaths),
            addresses: try addresses.map(parseAddress),
            imageName: inputOptions.imageNames.first,
            format: json ? .json : .text
        )
    }

    func run() async throws {
        let request = try makeRequest()
        do {
            try await request.run(output: StandardStreamOutput())
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }
}
