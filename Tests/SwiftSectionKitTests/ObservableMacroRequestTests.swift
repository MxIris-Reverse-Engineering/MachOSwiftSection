import Foundation
import Testing
import SwiftSectionKit
@testable import MachOTestingSupport

/// `interface` folds what `@Observable` generated unless the request expands
/// macros, and `dump` names the macro on the class's header line (evolution
/// proposal `observable-macro-folding`).
@Suite(.serialized)
struct ObservableMacroRequestTests {
    private static func source() throws -> MachOSource {
        .file(path: try ObservableMacroFixture.libraryURL(.release).path, architecture: nil)
    }

    @Test("The interface folds the expansion unless the request expands macros")
    func interfaceFoldsTheExpansion() async throws {
        let folded = RecordingOutput()
        try await InterfaceRequest(source: try Self.source()).run(output: folded, environment: .testing)
        #expect(folded.printedProduct.contains("@Observation.Observable\nclass FinalModel {"), "\(folded.printedProduct)")
        #expect(!folded.printedProduct.contains("_$observationRegistrar"), "\(folded.printedProduct)")

        let expanded = RecordingOutput()
        try await InterfaceRequest(source: try Self.source(), expandsMacros: true).run(output: expanded, environment: .testing)
        #expect(!expanded.printedProduct.contains("@Observation."), "\(expanded.printedProduct)")
        #expect(expanded.printedProduct.contains("_$observationRegistrar"), "\(expanded.printedProduct)")
        #expect(expanded.printedProduct.contains("extension ObservableMacroFixture.FinalModel: Observation.Observable {}"), "\(expanded.printedProduct)")
    }

    @Test("The dump names the macro on the class's header line")
    func dumpNamesTheMacro() async throws {
        let output = RecordingOutput()
        try await DumpRequest(source: try Self.source()).run(output: output, environment: .testing)
        #expect(output.printedProduct.contains("@Observation.Observable class ObservableMacroFixture.FinalModel"), "\(output.printedProduct)")
        #expect(output.printedProduct.contains("_$observationRegistrar"), "\(output.printedProduct)")
    }
}
