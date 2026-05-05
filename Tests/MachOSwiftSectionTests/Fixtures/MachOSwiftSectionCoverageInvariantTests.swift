import Foundation
import Testing
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Static-vs-runtime invariant guard for fixture-based test coverage.
///
/// Compares four sets:
///   - **Expected** (source-code public members, scanned by SwiftSyntax).
///   - **Registered** (Suite-declared `registeredTestMethodNames`, reflected).
///   - **Behavior** (per-method behavior inferred from Suite source by
///     SuiteBehaviorScanner: acrossAllReaders / inProcessOnly / sentinel).
///   - **Allowlist** (`CoverageAllowlistEntries`, with typed `SentinelReason`).
///
/// Failure modes:
///   ① missing — declared public member with no registered name and no
///     allowlist entry → add `@Test` or sentinel allowlist entry.
///   ② extra — registered name not matching any declaration → sync
///     `registeredTestMethodNames` and remove orphan `@Test`.
///   ③ liarSentinel — sentinel-tagged key whose Suite actually calls
///     `acrossAllReaders` / `inProcessContext` → tag is stale, remove
///     sentinel entry or revert test.
///   ④ unmarkedSentinel — Suite method behavior is sentinel but the key
///     isn't declared sentinel in the allowlist → either implement a real
///     test, or add a `SentinelReason` entry.
@Suite
@MainActor
struct MachOSwiftSectionCoverageInvariantTests {

    private var modelsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Fixtures/
            .deletingLastPathComponent()  // MachOSwiftSectionTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("../Sources/MachOSwiftSection/Models")
            .standardizedFileURL
    }

    private var suitesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Fixtures/
            .standardizedFileURL
    }

    @Test func everyPublicMemberHasATest() throws {
        let scanner = PublicMemberScanner(sourceRoot: modelsRoot)
        let allowlistKeys = CoverageAllowlistEntries.keys
        let sentinelKeys = CoverageAllowlistEntries.sentinelKeys

        let expected = try scanner.scan(applyingAllowlist: allowlistKeys)

        let registered: Set<MethodKey> = Set(
            allFixtureSuites.flatMap { suite -> [MethodKey] in
                suite.registeredTestMethodNames.map { name in
                    MethodKey(typeName: suite.testedTypeName, memberName: name)
                }
            }
        ).subtracting(allowlistKeys)

        let behaviorScanner = SuiteBehaviorScanner(suiteRoot: suitesRoot)
        let behaviorMap = try behaviorScanner.scan()

        // ① missing
        let missing = expected.subtracting(registered)
        #expect(
            missing.isEmpty,
            """
            Missing tests for these public members of MachOSwiftSection/Models:
            \(missing.sorted().map { "  \($0)" }.joined(separator: "\n"))

            Tip: add the corresponding @Test func to the matching Suite, append the
            name to its registeredTestMethodNames (or rerun
            `swift package --allow-writing-to-package-directory regen-baselines --suite <Name>`),
            and re-run.
            """
        )

        // ② extra
        let extra = registered.subtracting(expected)
        #expect(
            extra.isEmpty,
            """
            Tests registered for non-existent (or refactored-away) public members:
            \(extra.sorted().map { "  \($0)" }.joined(separator: "\n"))

            Tip: source method was renamed or removed — sync the Suite's
            registeredTestMethodNames + remove the orphan @Test.
            """
        )

        // ③ liarSentinel — sentinel tag claims sentinel but suite actually tests
        let liarSentinels = sentinelKeys.filter { key in
            if let behavior = behaviorMap[key], behavior != .sentinel {
                return true
            }
            return false
        }
        #expect(
            liarSentinels.isEmpty,
            """
            These methods are tagged sentinel in CoverageAllowlistEntries but
            their Suite actually calls acrossAllReaders / inProcessContext — the
            sentinel tag is stale. Remove the sentinel entry or revert the test
            to registration-only:
            \(liarSentinels.sorted().map { "  \($0)" }.joined(separator: "\n"))
            """
        )

        // ④ unmarkedSentinel — suite behavior is sentinel but key isn't declared
        let actualSentinelKeys = Set(behaviorMap.compactMap { (key, behavior) in
            behavior == .sentinel ? key : nil
        })
        let unmarked = actualSentinelKeys
            .subtracting(sentinelKeys)
            .subtracting(allowlistKeys)
            .intersection(expected)  // only flag if it's actually a public method
        #expect(
            unmarked.isEmpty,
            """
            These methods are sentinel-only (the Suite never calls
            acrossAllReaders / inProcessContext) but are not declared in
            CoverageAllowlistEntries. Either implement a real test, or add a
            SentinelReason entry explaining why this is the right level of
            coverage:
            \(unmarked.sorted().map { "  \($0)" }.joined(separator: "\n"))
            """
        )
    }
}
