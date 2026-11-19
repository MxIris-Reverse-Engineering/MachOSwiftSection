import Foundation
import Testing
import CryptoKit
import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences

/// Whole reference tables of a few large images, reduced to a count and a
/// SHA-256 per image, so that a refactoring of the analyzer can be shown to
/// change no reference at all.
///
/// An A/B check, not a regression test: the tables follow the running
/// system's dyld shared cache, so there is no baseline to keep in the
/// repository. The procedure:
///
/// 1. Export the baseline commit (`git archive`), copy this file into its
///    `Tests/CrossReferenceAnalysisTests/`, and run it there with
///    `CROSS_REFERENCE_TABLE_DIGEST_DIRECTORY=<directory>`: it writes one
///    `<image>.digest` file per image.
/// 2. Run it in the candidate with
///    `CROSS_REFERENCE_TABLE_BASELINE_DIRECTORY=<the same directory>`: it
///    compares every image against the baseline's file.
///
/// It uses the public API alone, which is what lets the same file run on
/// both sides. Without either variable it does not run.
@Suite(
    .enabled(
        if: ReferenceTableDigestEnvironment.digestDirectory != nil || ReferenceTableDigestEnvironment.baselineDirectory != nil || ReferenceTableDigestEnvironment.dumpDirectory != nil,
        "set CROSS_REFERENCE_TABLE_DIGEST_DIRECTORY, CROSS_REFERENCE_TABLE_BASELINE_DIRECTORY or CROSS_REFERENCE_TABLE_DUMP_DIRECTORY"
    )
)
struct ReferenceTableDigestTests {
    /// The images compared: Objective-C heavy, Swift heavy, and Foundation,
    /// which is both.
    static let imageSuffixes = [
        "/AppKit.framework/Versions/C/AppKit",
        "/SwiftUICore.framework/Versions/A/SwiftUICore",
        "/Foundation.framework/Versions/C/Foundation",
    ]

    @Test(arguments: imageSuffixes)
    func inProcessReferenceTablesAreUnchangedForAppKitSwiftUICoreAndFoundation(imageSuffix: String) throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let imageIndex = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(imageSuffix) }, "no image ending with \(imageSuffix)")
        let table = analyzer.referenceTable(ofImageAt: imageIndex)
        let digest = Self.digest(of: table)
        let fileName = (imageSuffix as NSString).lastPathComponent + ".digest"

        // Every reference, one per line, to find what differs once a digest
        // does.
        if let dumpDirectory = ReferenceTableDigestEnvironment.dumpDirectory {
            try FileManager.default.createDirectory(at: dumpDirectory, withIntermediateDirectories: true)
            let lines = table.references.filter { !Self.isAddedByStepFive($0) }.map(Self.spelling(of:)).joined(separator: "\n")
            try lines.write(to: dumpDirectory.appendingPathComponent((imageSuffix as NSString).lastPathComponent + ".references"), atomically: true, encoding: .utf8)
        }

        if let digestDirectory = ReferenceTableDigestEnvironment.digestDirectory {
            try FileManager.default.createDirectory(at: digestDirectory, withIntermediateDirectories: true)
            try digest.write(to: digestDirectory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }
        if let baselineDirectory = ReferenceTableDigestEnvironment.baselineDirectory {
            let baseline = try String(contentsOf: baselineDirectory.appendingPathComponent(fileName), encoding: .utf8)
            #expect(digest == baseline, "\(imageSuffix): baseline \(baseline), now \(digest)")
        }
    }

    /// `<reference count> <SHA-256 of every reference, one per line>`. A
    /// reference is spelled the way `String(describing:)` spells it, which
    /// covers every stored property — with the modules of the
    /// cross-reference layers taken out: it qualifies a type nested in an
    /// enum's payload with its module (`CrossReferenceCore.CodeLocation`),
    /// and moving a type between the layers is no change to a reference.
    static func digest(of table: CodeReferenceTable) -> String {
        var hasher = SHA256()
        var count = 0
        for reference in table.references where !isAddedByStepFive(reference) {
            hasher.update(data: Data((spelling(of: reference) + "\n").utf8))
            count += 1
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(count) \(hash)"
    }

    /// A reference of a kind step 5 of the proposal added — an instance
    /// variable, a string literal, a data reference through a slot binding
    /// to an imported symbol — which a baseline from before has none of.
    static func isAddedByStepFive(_ reference: CodeReference) -> Bool {
        switch reference.target {
        case .objectiveCInstanceVariable, .cString, .constantString:
            return true
        case .importedSymbol:
            return reference.kind == .reference
        default:
            return false
        }
    }

    /// A reference as `String(describing:)` spells it, with what moving a
    /// type between the layers changes in that spelling taken out: the
    /// module qualifying a type nested in an enum's payload, and
    /// `CodeReference.Kind`, which became a typealias of the core's
    /// `CodeReferenceKind`.
    static func spelling(of reference: CodeReference) -> String {
        let description = String(describing: reference).replacingOccurrences(of: "CodeReference.Kind.", with: "CodeReferenceKind.")
        let unqualified = moduleQualifier.stringByReplacingMatches(in: description, range: NSRange(location: 0, length: description.utf16.count), withTemplate: "")
        // The route came with step 5; a baseline from before has none.
        return routeField.stringByReplacingMatches(in: unqualified, range: NSRange(location: 0, length: unqualified.utf16.count), withTemplate: "")
    }

    private static let moduleQualifier = try! NSRegularExpression(pattern: #"\b(CrossReferenceCore|CrossReferenceObjC|CrossReferenceAnalysis)\."#)
    private static let routeField = try! NSRegularExpression(pattern: #", route: CodeReferenceRoute\.[A-Za-z]+"#)
}

/// Where the digests go, and where the baseline's are: outside the suite's
/// own type, which its `@Suite` attribute cannot refer to.
enum ReferenceTableDigestEnvironment {
    static let digestDirectory = ProcessInfo.processInfo.environment["CROSS_REFERENCE_TABLE_DIGEST_DIRECTORY"].map(URL.init(fileURLWithPath:))
    static let baselineDirectory = ProcessInfo.processInfo.environment["CROSS_REFERENCE_TABLE_BASELINE_DIRECTORY"].map(URL.init(fileURLWithPath:))
    /// Where to write every reference, one per line, besides the digest.
    static let dumpDirectory = ProcessInfo.processInfo.environment["CROSS_REFERENCE_TABLE_DUMP_DIRECTORY"].map(URL.init(fileURLWithPath:))
}
