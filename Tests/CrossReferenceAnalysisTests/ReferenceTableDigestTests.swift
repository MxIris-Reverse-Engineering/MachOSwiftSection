import Foundation
import Testing
import CryptoKit
import CrossReferenceAnalysis

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
        if: ReferenceTableDigestEnvironment.digestDirectory != nil || ReferenceTableDigestEnvironment.baselineDirectory != nil,
        "set CROSS_REFERENCE_TABLE_DIGEST_DIRECTORY or CROSS_REFERENCE_TABLE_BASELINE_DIRECTORY"
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
        let digest = Self.digest(of: analyzer.referenceTable(ofImageAt: imageIndex))
        let fileName = (imageSuffix as NSString).lastPathComponent + ".digest"

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
    /// covers every stored property.
    static func digest(of table: CodeReferenceTable) -> String {
        var hasher = SHA256()
        for reference in table.references {
            hasher.update(data: Data((String(describing: reference) + "\n").utf8))
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(table.references.count) \(hash)"
    }
}

/// Where the digests go, and where the baseline's are: outside the suite's
/// own type, which its `@Suite` attribute cannot refer to.
enum ReferenceTableDigestEnvironment {
    static let digestDirectory = ProcessInfo.processInfo.environment["CROSS_REFERENCE_TABLE_DIGEST_DIRECTORY"].map(URL.init(fileURLWithPath:))
    static let baselineDirectory = ProcessInfo.processInfo.environment["CROSS_REFERENCE_TABLE_BASELINE_DIRECTORY"].map(URL.init(fileURLWithPath:))
}
