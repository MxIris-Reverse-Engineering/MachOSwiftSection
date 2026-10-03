import Foundation
import Testing
import OutputTransformer
import SwiftOutputTransformer
import SwiftSectionKit

@Suite
struct TransformerRequestTests {
    @Test("The tokens listing of one module names its placeholders, aligned")
    func tokensOfOneModule() {
        let output = RecordingOutput()
        TransformerTokensRequest(module: .fieldOffset).run(output: output)
        #expect(output.printedProduct == """
        Swift Field Offset Comment (field-offset)
          Tokens — --field-offset-template
            ${startOffset}  Start Offset
            ${endOffset}    End Offset

        """)
    }

    @Test("Listing every module lists each once, in order, an empty line apart")
    func everyModuleIsListed() {
        let output = RecordingOutput()
        TransformerTemplatesRequest().run(output: output)
        let lines = output.printedProduct.split(separator: "\n", omittingEmptySubsequences: false)
        let moduleNames = lines
            .filter { !$0.isEmpty && !$0.hasPrefix(" ") }
            .compactMap { line in line.split(separator: "(").last.map { String($0.dropLast()) } }
        #expect(moduleNames == ["field-offset", "vtable-offset", "member-address", "type-layout", "enum-layout"])
        // Four separators between five modules, plus the final newline.
        #expect(lines.filter(\.isEmpty).count == 5)
    }

    @Test("The configuration JSON reads back as the configuration it was made from")
    func configurationRoundTrips() throws {
        var configuration = Transformer.SwiftConfiguration()
        configuration.swiftFieldOffset.isEnabled = true
        configuration.swiftFieldOffset.template = "${startOffset}"
        let output = RecordingOutput()
        try TransformerConfigurationRequest(configuration: configuration).run(output: output)

        guard case .text(let json)? = output.products.first else {
            Issue.record("expected one text product, got \(output.products)")
            return
        }
        let decoded = try JSONDecoder().decode(Transformer.SwiftConfiguration.self, from: Data(json.utf8))
        #expect(decoded == configuration)
    }

    /// A file holds the JSON as is; printed, the same JSON is followed by a
    /// newline — the one `print` always added.
    @Test("A file destination holds the printed JSON minus its newline")
    func configurationFileDestination() throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let filePath = directoryURL.appendingPathComponent("transformers.json").path

        let printed = RecordingOutput()
        try TransformerConfigurationRequest().run(output: printed)
        let written = RecordingOutput()
        try TransformerConfigurationRequest(destination: .file(path: filePath)).run(output: written)

        #expect(written.events.isEmpty)
        #expect(try String(contentsOfFile: filePath, encoding: .utf8) + "\n" == printed.printedProduct)
    }
}
