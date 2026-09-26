import Foundation
import Testing

/// The macOS CI job runs only the suites its `--filter` names, and a name that
/// matches no suite fails nothing: `swift test` runs whatever the other names
/// match and exits green. So when a suite is renamed and the workflow is not,
/// the CI quietly stops running it. `MetadataReaderDemanglingTests` went that
/// way when `MetadataReader` became `SymbolicDemangler`, and its four tests
/// left CI unnoticed.
///
/// Every name the filter lists must therefore be a suite some test source
/// declares.
@Suite
struct ContinuousIntegrationTestFilterTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // MachOTestingSupportTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root

    /// The suite names inside `\.(A|B|…)(/|$)`, the shape the workflow's
    /// filter is written in.
    private static func filteredSuiteNames() throws -> [String] {
        let workflowURL = packageRoot.appendingPathComponent(".github/workflows/macOS.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
        let filterLine = try #require(workflow.split(separator: "\n").first { $0.contains("--filter") }, "the workflow runs a filtered suite subset")
        let openingDelimiter = #"\.("#
        let closingDelimiter = ")(/|$)"
        let alternativesStart = try #require(filterLine.range(of: openingDelimiter)).upperBound
        let alternativesEnd = try #require(filterLine.range(of: closingDelimiter, range: alternativesStart ..< filterLine.endIndex)).lowerBound
        return filterLine[alternativesStart ..< alternativesEnd].split(separator: "|").map(String.init)
    }

    /// Every type name declared in the test sources — a suite is a type.
    private static func declaredTypeNames() throws -> Set<String> {
        let testsDirectory = packageRoot.appendingPathComponent("Tests")
        let declaration = try NSRegularExpression(pattern: #"\b(?:struct|class|enum|actor)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        var names: Set<String> = []
        let enumerator = try #require(FileManager.default.enumerator(at: testsDirectory, includingPropertiesForKeys: nil))
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let sourceRange = NSRange(source.startIndex ..< source.endIndex, in: source)
            for match in declaration.matches(in: source, range: sourceRange) {
                if let nameRange = Range(match.range(at: 1), in: source) {
                    names.insert(String(source[nameRange]))
                }
            }
        }
        return names
    }

    @Test("every suite the CI filter names is declared in the test sources")
    func everyFilteredSuiteExists() throws {
        let filteredSuiteNames = try Self.filteredSuiteNames()
        try #require(!filteredSuiteNames.isEmpty, "the premise: the filter lists suites")
        let declaredTypeNames = try Self.declaredTypeNames()
        let missingSuiteNames = filteredSuiteNames.filter { !declaredTypeNames.contains($0) }
        #expect(missingSuiteNames.isEmpty, "the CI filter names suites no test declares: \(missingSuiteNames)")
    }
}
