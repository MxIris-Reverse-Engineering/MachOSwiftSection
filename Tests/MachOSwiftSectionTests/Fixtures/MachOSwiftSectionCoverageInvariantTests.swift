import Foundation
import Testing
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Static-vs-runtime invariant guard for fixture-based test coverage.
///
/// Compares two `MethodKey` sets:
///   - **Expected** (from source): SwiftSyntax scan of
///     `Sources/MachOSwiftSection/Models/` produces the set of
///     `(typeName, memberName)` pairs for `public`/`open` `func` / `var` /
///     `init` / `subscript` declarations.
///   - **Registered** (from Suites): reflection over `allFixtureSuites`
///     produces `(testedTypeName, registeredTestMethodName)` pairs.
///
/// Failure modes:
///   - `missing` (expected − registered): a declared public member has no
///     corresponding registered test name. Either add a `@Test`/registration,
///     or — if the omission is intentional — add a `CoverageAllowlistEntry`
///     with a reason in `CoverageAllowlistEntries.swift`.
///   - `extra` (registered − expected): a registered name does not match any
///     declaration. Likely a renamed/removed source method — sync the Suite's
///     `registeredTestMethodNames` and remove the orphan `@Test`.
///
/// `@MainActor` is required because `FixtureSuite` is `@MainActor`-isolated
/// (Task 4 deviation: every conformer inherits from
/// `MachOSwiftSectionFixtureTests`, which is itself `@MainActor`).
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

    @Test func everyPublicMemberHasATest() throws {
        let scanner = PublicMemberScanner(sourceRoot: modelsRoot)
        let allowlist = CoverageAllowlistEntries.keys
        let expected = try scanner.scan(applyingAllowlist: allowlist)

        // Subtract the allowlist from `registered` as well, so that an
        // intentionally exempted (typeName, memberName) — e.g., a
        // macro-synthesized memberwise init that the scanner cannot see but
        // the Suite still exercises — does not surface as "extra".
        let registered: Set<MethodKey> = Set(
            allFixtureSuites.flatMap { suite -> [MethodKey] in
                suite.registeredTestMethodNames.map { name in
                    MethodKey(typeName: suite.testedTypeName, memberName: name)
                }
            }
        ).subtracting(allowlist)

        let missing = expected.subtracting(registered)
        let extra = registered.subtracting(expected)

        #expect(
            missing.isEmpty,
            """
            Missing tests for these public members of MachOSwiftSection/Models:
            \(missing.sorted().map { "  \($0)" }.joined(separator: "\n"))

            Tip: add the corresponding @Test func to the matching Suite, append the
            name to its registeredTestMethodNames (or rerun
            `Scripts/regen-baselines.sh --suite <Name>`), and re-run.
            """
        )
        #expect(
            extra.isEmpty,
            """
            Tests registered for non-existent (or refactored-away) public members:
            \(extra.sorted().map { "  \($0)" }.joined(separator: "\n"))

            Tip: source method was renamed or removed — sync the Suite's
            registeredTestMethodNames + remove the orphan @Test.
            """
        )
    }
}
