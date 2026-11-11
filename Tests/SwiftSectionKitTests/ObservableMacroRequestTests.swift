import Foundation
import Testing
import SwiftSectionKit
@testable import MachOTestingSupport

/// `interface` folds what `@Observable` generated unless the request expands
/// macros, and `dump` names the macro on the class's header line (evolution
/// proposal `observable-macro-folding`).
@Suite(.serialized)
struct ObservableMacroRequestTests {
    private static func source() async throws -> MachOSource {
        .file(path: try await ObservableMacroFixture.libraryURL(.release).path, architecture: nil)
    }

    @Test("The interface folds the expansion unless the request expands macros")
    func interfaceFoldsTheExpansion() async throws {
        let folded = RecordingOutput()
        try await InterfaceRequest(source: try await Self.source()).run(output: folded, environment: .testing)
        #expect(folded.printedProduct.contains("@Observation.Observable\nclass FinalModel {"), "\(folded.printedProduct)")
        // The look-alikes declare a registrar of their own; the class the
        // macro expanded prints none.
        let finalModelStart = try #require(folded.printedProduct.range(of: "class FinalModel {"), "\(folded.printedProduct)")
        let finalModelEnd = try #require(folded.printedProduct.range(of: "\n}", range: finalModelStart.upperBound ..< folded.printedProduct.endIndex))
        let finalModel = folded.printedProduct[finalModelStart.lowerBound ..< finalModelEnd.upperBound]
        #expect(!finalModel.contains("_$observationRegistrar"), "\(finalModel)")

        let expanded = RecordingOutput()
        try await InterfaceRequest(source: try await Self.source(), expandsMacros: true).run(output: expanded, environment: .testing)
        #expect(!expanded.printedProduct.contains("@Observation."), "\(expanded.printedProduct)")
        #expect(expanded.printedProduct.contains("_$observationRegistrar"), "\(expanded.printedProduct)")
        #expect(expanded.printedProduct.contains("extension ObservableMacroFixture.FinalModel: Observation.Observable {}"), "\(expanded.printedProduct)")
    }

    @Test("The dump names the macro on the class's header line")
    func dumpNamesTheMacro() async throws {
        let output = RecordingOutput()
        try await DumpRequest(source: try await Self.source()).run(output: output, environment: .testing)
        #expect(output.printedProduct.contains("@Observation.Observable class ObservableMacroFixture.FinalModel"), "\(output.printedProduct)")
        #expect(output.printedProduct.contains("_$observationRegistrar"), "\(output.printedProduct)")
    }
}
