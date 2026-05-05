# Fixture-Coverage Tightening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the silent-sentinel coverage gap discovered in PR #85 review by tagging every sentinel-only Suite with a typed `SentinelReason`, converting ~30 runtime-only metadata Suites to InProcess single-reader real tests, and adding ~7 new SymbolTestsCore fixture types so the `needsFixtureExtension` category clears.

**Architecture:** Three-phase migration on the existing `feature/machoswift-section-fixture-tests` branch. Phase A introduces the new schema + a SwiftSyntax-based `SuiteBehaviorScanner` and tightens `MachOSwiftSectionCoverageInvariantTests` with two new assertions (`liarSentinel`, `unmarkedSentinel`). Phase C adds an `InProcessMetadataPicker` and converts runtime-only Suites to InProcess single-reader tests. Phase B adds fixture types to `SymbolTestsCore` and converts `needsFixtureExtension` Suites to cross-reader tests. Phase D refreshes docs.

**Tech Stack:** Swift 6.2 / Xcode 26, swift-testing (`@Test`/`#expect`/`@Suite`), SwiftSyntax for source-level scanning, swift-argument-parser for `baseline-generator`, custom SwiftPM command plugin (`regen-baselines`), `SymbolTestsCore.framework` Mach-O fixture, `MachOFile`/`MachOImage`/`InProcessContext` readers from MachOFoundation.

**Spec:** [`docs/superpowers/specs/2026-05-05-fixture-coverage-tightening-design.md`](../specs/2026-05-05-fixture-coverage-tightening-design.md)

---

## File Structure

### Phase A — Mechanism

| Action | Path | Responsibility |
|---|---|---|
| Modify | `Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift` | Extend with `SentinelReason`, `AllowlistKind`, `sentinelGroup(...)` helper. Keep `legacyExempt` path. |
| Create | `Sources/MachOFixtureSupport/Coverage/SuiteBehaviorScanner.swift` | SwiftSyntax-based per-method scanner producing `[MethodKey: MethodBehavior]`. |
| Create | `Tests/MachOTestingSupportTests/Coverage/SuiteBehaviorScannerTests.swift` | Unit tests for scanner using fixture sample sources. |
| Create | `Tests/MachOTestingSupportTests/Coverage/Fixtures/SuiteSampleSource.swift.txt` | Sample suites in 3 behaviors for scanner unit test. |
| Modify | `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` | Replace single legacy entry with sentinel-grouped entries for all 88 sentinel suites. |
| Modify | `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift` | Add `③ liarSentinel` + `④ unmarkedSentinel` assertions. |

### Phase C — Runtime-only InProcess conversion

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift` | Static `UnsafeRawPointer` constants for stdlib + fixture-bound metadata. |
| Modify | `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift` | Add `usingInProcessOnly(...)` helper. |
| Modify (~30) | `Tests/MachOSwiftSectionTests/Fixtures/**/*Tests.swift` | Replace `registrationOnly` with real `usingInProcessOnly`-based tests. |
| Modify (~30) | `Sources/MachOFixtureSupport/Baseline/Generators/**/*BaselineGenerator.swift` | Emit ABI-literal `Entry` from InProcess metadata pointer. |
| Modify (~30) | `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/*Baseline.swift` | Regenerated via `swift package regen-baselines`. |
| Modify | `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` | Remove converted `runtimeOnly` entries. |

### Phase B — SymbolTestsCore fixture extension

| Action | Path | Responsibility |
|---|---|---|
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/DefaultOverrideTable.swift` | Class with dynamic replacement to surface default-override table |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/ResilientClasses.swift` | Resilient class + resilient superclass references |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/ObjCClassWrappers.swift` | NSObject-inheriting Swift classes |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/ObjCResilientStubs.swift` | Swift class inheriting resilient ObjC class |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/CanonicalSpecializedMetadata.swift` | `@_specialize(exported: true)` generic types |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/ForeignTypes.swift` | Foreign class import + foreign reference type |
| Create | `Tests/Projects/SymbolTests/SymbolTestsCore/GenericValueParameters.swift` | Type with `<let N: Int>` value generic parameters |
| Modify | `Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift` | Add picker function per new fixture |
| Modify | various `Sources/MachOFixtureSupport/Baseline/Generators/**/*.swift` | Wire picker → generator |
| Modify | various `Tests/MachOSwiftSectionTests/Fixtures/**/*Tests.swift` | Convert `registrationOnly` → real cross-reader test |
| Rebuild | `Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore.framework` | Via `xcodebuild ... build` |
| Modify | `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` | Remove converted `needsFixtureExtension` entries |

### Phase D — Docs

| Action | Path | Responsibility |
|---|---|---|
| Modify | `CLAUDE.md` | Update fixture-coverage section with sentinel concept and `regen-baselines` plugin reference |

---

## Phase A — Mechanism

### Task A1: Introduce `SentinelReason`/`AllowlistKind` schema and `SuiteBehaviorScanner`

**Files:**
- Modify: `Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift`
- Create: `Sources/MachOFixtureSupport/Coverage/SuiteBehaviorScanner.swift`
- Create: `Tests/MachOTestingSupportTests/Coverage/Fixtures/SuiteSampleSource.swift.txt`
- Create: `Tests/MachOTestingSupportTests/Coverage/SuiteBehaviorScannerTests.swift`
- Modify: `Package.swift` (extend `MachOTestingSupportTests.exclude` for new fixture)

- [ ] **Step 1: Extend `CoverageAllowlist.swift` with new schema (additive, keep current public surface working)**

Replace the contents of `Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift` with:

```swift
import Foundation

/// Why a `(typeName, memberName)` pair is allowed to skip cross-reader fixture coverage.
package enum SentinelReason: Hashable {
    /// The type is allocated by the Swift runtime at type-load time and is
    /// never serialized into the fixture's Mach-O image. Covered via
    /// `InProcessMetadataPicker` + single-reader assertions instead.
    case runtimeOnly(detail: String)

    /// SymbolTestsCore currently lacks a sample that surfaces this metadata
    /// shape. Should be eliminated by extending the fixture (Phase B).
    case needsFixtureExtension(detail: String)

    /// Pure raw-value enum / marker protocol / pure-data utility. Sentinel
    /// status is intended to be permanent. Future follow-ups may pin
    /// `rawValue` literals as a deeper assertion.
    case pureDataUtility(detail: String)
}

/// Either a legacy "scanner-saw-it-but-it-shouldn't-count" exemption (kept as-is
/// from PR #85) or a typed sentinel with a reason.
package enum AllowlistKind: Hashable {
    case legacyExempt(reason: String)
    case sentinel(SentinelReason)
}

/// A single entry exempting one (typeName, memberName) pair from coverage requirements.
package struct CoverageAllowlistEntry: Hashable, CustomStringConvertible {
    package let key: MethodKey
    package let kind: AllowlistKind

    package init(typeName: String, memberName: String, reason: String) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .legacyExempt(reason: reason)
    }

    package init(typeName: String, memberName: String, sentinel: SentinelReason) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.kind = .sentinel(sentinel)
    }

    package var description: String {
        switch kind {
        case .legacyExempt(let reason):
            return "\(key)  // legacyExempt: \(reason)"
        case .sentinel(let reason):
            return "\(key)  // sentinel: \(reason)"
        }
    }
}
```

- [ ] **Step 2: Verify build still works after schema extension**

Run:
```bash
swift build 2>&1 | tail -3
```
Expected:
```
Build complete!
```

This proves the schema extension is source-compatible — `CoverageAllowlistEntries.swift` (Tests target) still uses the old `init(typeName:memberName:reason:)` initializer, which the new schema preserves.

- [ ] **Step 3: Create the SwiftSyntax sample-source fixture for scanner tests**

Create `Tests/MachOTestingSupportTests/Coverage/Fixtures/SuiteSampleSource.swift.txt`:

```swift
// Sample suites consumed by SuiteBehaviorScannerTests via on-disk reads.
// File extension intentionally `.swift.txt` so SPM ignores it during builds.

import Testing

@Suite
final class CrossReaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CrossReaderType"
    static var registeredTestMethodNames: Set<String> { ["liveMethod"] }

    @Test func liveMethod() async throws {
        let result = try acrossAllReaders(
            file: { 1 },
            image: { 1 }
        )
        #expect(result == 1)
    }
}

@Suite
final class InProcessOnlyTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "RuntimeOnlyType"
    static var registeredTestMethodNames: Set<String> { ["kind"] }

    @Test func kind() async throws {
        let result = try usingInProcessOnly { context in
            42
        }
        #expect(result == 42)
    }
}

@Suite
final class SentinelTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "RegistrationOnlyType"
    static var registeredTestMethodNames: Set<String> { ["registeredOnly"] }

    @Test func registrationOnly() async throws {
        #expect(SentinelTests.registeredTestMethodNames.contains("registeredOnly"))
    }
}
```

- [ ] **Step 4: Update `Package.swift` to exclude the new sample-source fixture**

In `Package.swift`, find `MachOTestingSupportTests` target definition (around line 619-629). Update its `exclude` array to also include the new fixture:

```swift
static let MachOTestingSupportTests = Target.testTarget(
    name: "MachOTestingSupportTests",
    dependencies: [
        .target(.MachOTestingSupport),
        .target(.MachOFixtureSupport),
    ],
    exclude: [
        "Coverage/Fixtures/SampleSource.swift.txt",
        "Coverage/Fixtures/SuiteSampleSource.swift.txt",
    ],
    swiftSettings: testSettings
)
```

- [ ] **Step 5: Write the failing scanner test**

Create `Tests/MachOTestingSupportTests/Coverage/SuiteBehaviorScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
struct SuiteBehaviorScannerTests {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    private func makeScanRoot() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let source = try String(contentsOf: fixtureRoot.appendingPathComponent("SuiteSampleSource.swift.txt"))
        let dest = tempDir.appendingPathComponent("SuiteSampleSource.swift")
        try source.write(to: dest, atomically: true, encoding: .utf8)
        return tempDir
    }

    @Test func detectsAcrossAllReaders() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "CrossReaderType", memberName: "liveMethod")
        #expect(result[key] == .acrossAllReaders)
    }

    @Test func detectsInProcessOnly() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "RuntimeOnlyType", memberName: "kind")
        #expect(result[key] == .inProcessOnly)
    }

    @Test func detectsSentinel() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = SuiteBehaviorScanner(suiteRoot: root)
        let result = try scanner.scan()
        let key = MethodKey(typeName: "RegistrationOnlyType", memberName: "registrationOnly")
        #expect(result[key] == .sentinel)
    }
}
```

- [ ] **Step 6: Run scanner test, confirm it fails because `SuiteBehaviorScanner` doesn't exist**

Run:
```bash
swift test --filter SuiteBehaviorScannerTests 2>&1 | tail -10
```
Expected:
```
error: cannot find 'SuiteBehaviorScanner' in scope
```

- [ ] **Step 7: Implement `SuiteBehaviorScanner`**

Create `Sources/MachOFixtureSupport/Coverage/SuiteBehaviorScanner.swift`:

```swift
import Foundation
import SwiftSyntax
import SwiftParser

/// Scans `*Tests.swift` Suite source files and reports per-method behavior:
/// whether each `@Test func` calls `acrossAllReaders` / `acrossAllContexts`,
/// `usingInProcessOnly` / `inProcessContext`, or neither.
///
/// Used by `MachOSwiftSectionCoverageInvariantTests` to enforce that every
/// sentinel-only method is declared in `CoverageAllowlistEntries`.
package struct SuiteBehaviorScanner {
    package enum MethodBehavior: Equatable {
        case acrossAllReaders
        case inProcessOnly
        case sentinel
    }

    package let suiteRoot: URL

    package init(suiteRoot: URL) {
        self.suiteRoot = suiteRoot
    }

    package func scan() throws -> [MethodKey: MethodBehavior] {
        let files = try collectSwiftFiles(under: suiteRoot)
        var result: [MethodKey: MethodBehavior] = [:]
        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let visitor = SuiteBehaviorVisitor(viewMode: .sourceAccurate)
            visitor.walk(tree)
            for entry in visitor.collected {
                let key = MethodKey(typeName: entry.testedTypeName, memberName: entry.methodName)
                result[key] = entry.behavior
            }
        }
        return result
    }

    private func collectSwiftFiles(under root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }
}

private final class SuiteBehaviorVisitor: SyntaxVisitor {
    struct Entry {
        let testedTypeName: String
        let methodName: String
        let behavior: SuiteBehaviorScanner.MethodBehavior
    }
    private(set) var collected: [Entry] = []
    private var currentTestedTypeName: String?

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        currentTestedTypeName = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        currentTestedTypeName = nil
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes),
              let testedTypeName = currentTestedTypeName,
              let body = node.body else {
            return .skipChildren
        }
        let behavior = inferBehavior(from: body)
        collected.append(Entry(
            testedTypeName: testedTypeName,
            methodName: node.name.text,
            behavior: behavior
        ))
        return .skipChildren
    }

    private func extractTestedTypeName(from memberBlock: MemberBlockSyntax) -> String? {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains(where: { $0.name.text == "static" })
            guard isStatic else { continue }
            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      pattern.identifier.text == "testedTypeName",
                      let initializer = binding.initializer,
                      let stringLit = initializer.value.as(StringLiteralExprSyntax.self)
                else { continue }
                let value = stringLit.segments.compactMap {
                    $0.as(StringSegmentSyntax.self)?.content.text
                }.joined()
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "Test" {
                return true
            }
        }
        return false
    }

    private func inferBehavior(from body: CodeBlockSyntax) -> SuiteBehaviorScanner.MethodBehavior {
        let bodyText = body.description
        if bodyText.contains("acrossAllReaders") || bodyText.contains("acrossAllContexts") {
            return .acrossAllReaders
        }
        if bodyText.contains("usingInProcessOnly") || bodyText.contains("inProcessContext") {
            return .inProcessOnly
        }
        return .sentinel
    }
}
```

- [ ] **Step 8: Run scanner test, confirm it passes**

Run:
```bash
swift test --filter SuiteBehaviorScannerTests 2>&1 | tail -10
```
Expected: 3 passed, 0 failed.

- [ ] **Step 9: Run full test suite to confirm nothing broke**

Run:
```bash
swift test 2>&1 | tail -5
```
Expected: All previously-passing tests still pass.

- [ ] **Step 10: Commit**

```bash
git add Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift \
        Sources/MachOFixtureSupport/Coverage/SuiteBehaviorScanner.swift \
        Tests/MachOTestingSupportTests/Coverage/SuiteBehaviorScannerTests.swift \
        Tests/MachOTestingSupportTests/Coverage/Fixtures/SuiteSampleSource.swift.txt \
        Package.swift
git commit -m "$(cat <<'EOF'
feat(MachOFixtureSupport): introduce SentinelReason schema + SuiteBehaviorScanner

Phase A1 of fixture-coverage tightening (see
docs/superpowers/specs/2026-05-05-fixture-coverage-tightening-design.md).

CoverageAllowlist.swift now exposes typed AllowlistKind with two paths:
  - legacyExempt(reason): identical to the prior single-reason path,
    used by the existing ProtocolDescriptorRef.init(storage:) entry.
  - sentinel(SentinelReason): typed reason with three cases —
    runtimeOnly, needsFixtureExtension, pureDataUtility.

SuiteBehaviorScanner walks fixture suite source files and produces
[MethodKey: MethodBehavior] keyed on testedTypeName + method name.
Behavior is inferred from substring presence of acrossAllReaders /
acrossAllContexts / usingInProcessOnly / inProcessContext in the
@Test function body. Identifier collisions are avoided by the
project's identifier conventions.

CoverageInvariant assertions remain unchanged in this commit; they
will be tightened in A3 once existing 88 sentinel suites are tagged
in A2.
EOF
)"
```

---

### Task A2: Seed sentinel reasons for all 88 existing sentinel Suites

**Files:**
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`
- Modify: `Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift` (add `sentinelGroup` helper)

This is the largest single commit in the plan. We add 88 `sentinelGroup(...)` calls covering 277 method names across three categories. Each group's reason is type-stable based on the type's nature (runtime-allocated metadata → `runtimeOnly`, fixture-extension-needed → `needsFixtureExtension`, pure raw-value enum → `pureDataUtility`).

- [ ] **Step 1: Add `sentinelGroup` helper**

In `Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift`, append (after the `CoverageAllowlistEntry` struct):

```swift
package enum CoverageAllowlistHelpers {
    /// Construct flat `[CoverageAllowlistEntry]` with the same `SentinelReason`
    /// applied to every member of `typeName`. Used in `CoverageAllowlistEntries.entries`
    /// to avoid repeating the reason on every method.
    package static func sentinelGroup(
        typeName: String,
        members: [String],
        reason: SentinelReason
    ) -> [CoverageAllowlistEntry] {
        members.map { memberName in
            CoverageAllowlistEntry(typeName: typeName, memberName: memberName, sentinel: reason)
        }
    }
}
```

- [ ] **Step 2: Inventory the 88 sentinel suites and their methods**

Run:
```bash
for f in $(find Tests/MachOSwiftSectionTests/Fixtures -name '*Tests.swift' -not -name 'CoverageInvariant*' -not -name 'FixtureLoadingProbe*'); do
  if ! grep -q 'acrossAllReaders\|acrossAllContexts' "$f" 2>/dev/null; then
    suite=$(basename $f .swift)
    baseline_file="Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/${suite%Tests}Baseline.swift"
    if [ -f "$baseline_file" ]; then
      tested=$(grep -E 'static let testedTypeName' $f | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
      methods=$(grep -E 'registeredTestMethodNames: Set<String>' $baseline_file | head -1 | grep -oE '\["[^]]+"' | tr -d '[' | tr ',' '\n' | tr -d '"' | tr -d ' ' | sort | tr '\n' ',' | sed 's/,$//')
      echo "$tested|$methods"
    fi
  fi
done | sort > /tmp/sentinel_inventory.txt

wc -l /tmp/sentinel_inventory.txt
```
Expected: ~88 lines (one per sentinel suite). Inspect `/tmp/sentinel_inventory.txt` to confirm.

- [ ] **Step 3: Write the new `CoverageAllowlistEntries.swift` skeleton with empty sentinel arrays**

Note: This step writes a structurally-complete file with empty entry arrays. Steps 4, 5, 6 use Edit to replace each empty array with the populated content. After step 6 the file is in its committed state.

Replace the entire contents of `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` with:

```swift
import Foundation
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Public members of `Sources/MachOSwiftSection/Models/` that are intentionally
/// not under cross-reader fixture coverage. Each entry MUST carry either a
/// legacy exemption reason or a typed `SentinelReason`. The Coverage Invariant
/// Test treats listed entries as if they had been tested.
///
/// Categories:
///
///   - `legacyExempt`: scanner blind spots (e.g., `@MemberwiseInit` synthesized
///     init visible to `@testable` but not to the SwiftSyntax scanner).
///
///   - `.sentinel(.runtimeOnly(...))`: type is allocated by the Swift runtime
///     at type-load time and is never serialized into the fixture's Mach-O.
///     Covered via `InProcessMetadataPicker` + single-reader assertions in
///     Phase C; suite is allowed to skip cross-reader assertions.
///
///   - `.sentinel(.needsFixtureExtension(...))`: SymbolTestsCore lacks a
///     sample that surfaces this metadata shape. Should be eliminated by
///     Phase B; entries removed when each fixture file lands.
///
///   - `.sentinel(.pureDataUtility(...))`: pure raw-value enum / marker
///     protocol / pure-data utility. Sentinel status is intended to be
///     permanent; future follow-ups may pin rawValue literals.
enum CoverageAllowlistEntries {
    static let entries: [CoverageAllowlistEntry] = legacyEntries + sentinelEntries

    /// Pre-existing entries from PR #85 that aren't strictly sentinel-only.
    private static let legacyEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistEntry(
            typeName: "ProtocolDescriptorRef",
            memberName: "init(storage:)",
            reason: "synthesized memberwise initializer (visible via @testable)"
        ),
    ]

    /// All current sentinel-only suite methods (88 suites, ~277 methods).
    /// Phase B and Phase C remove entries here as suites are converted to
    /// real cross-reader / InProcess single-reader tests.
    private static let sentinelEntries: [CoverageAllowlistEntry] = (
        runtimeOnlyEntries
        + needsFixtureExtensionEntries
        + pureDataUtilityEntries
    )

    // MARK: - runtimeOnly

    private static let runtimeOnlyEntries: [CoverageAllowlistEntry] = []

    // MARK: - needsFixtureExtension

    private static let needsFixtureExtensionEntries: [CoverageAllowlistEntry] = []

    // MARK: - pureDataUtility

    private static let pureDataUtilityEntries: [CoverageAllowlistEntry] = []

    static var keys: Set<MethodKey> { Set(entries.map(\.key)) }

    /// Subset of `keys` whose entry kind is `.sentinel(...)`. Used by the
    /// Coverage Invariant Test for `liarSentinel` and `unmarkedSentinel`
    /// assertions.
    static var sentinelKeys: Set<MethodKey> {
        Set(entries.compactMap { entry in
            if case .sentinel = entry.kind { return entry.key } else { return nil }
        })
    }
}
```

This skeleton compiles but is empty in the three sentinel arrays. We populate them next.

- [ ] **Step 4: Populate `runtimeOnlyEntries` array**

In `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`, replace the line:
```swift
    private static let runtimeOnlyEntries: [CoverageAllowlistEntry] = []
```
with:

```swift
private static let runtimeOnlyEntries: [CoverageAllowlistEntry] = [
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "Metadata",
        members: ["init", "kind", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "abstract Metadata pointer; concrete kind dispatched at runtime")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FullMetadata",
        members: ["init", "metadata", "header"],
        reason: .runtimeOnly(detail: "metadata layout prefix not serialized in section data")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataProtocol",
        members: ["kind", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "marker protocol on runtime metadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataWrapper",
        members: ["init", "pointer", "kind"],
        reason: .runtimeOnly(detail: "wraps live runtime metadata pointer")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataRequest",
        members: ["init", "rawValue", "state", "isBlocking", "isNonBlocking"],
        reason: .runtimeOnly(detail: "passed to runtime metadata accessor functions")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataResponse",
        members: ["metadata", "state"],
        reason: .runtimeOnly(detail: "returned by runtime metadata accessor functions")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataAccessorFunction",
        members: ["init", "address", "invoke"],
        reason: .runtimeOnly(detail: "function pointer to runtime metadata accessor")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "SingletonMetadataPointer",
        members: ["init", "pointer", "metadata"],
        reason: .runtimeOnly(detail: "runtime singleton metadata cache pointer")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataBounds",
        members: ["init", "negativeSizeInWords", "positiveSizeInWords"],
        reason: .runtimeOnly(detail: "computed by runtime, not in section data")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetadataBoundsProtocol",
        members: ["negativeSizeInWords", "positiveSizeInWords"],
        reason: .runtimeOnly(detail: "marker protocol on runtime-computed bounds")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ClassMetadataBounds",
        members: ["init", "immediateMembers", "negativeSizeInWords", "positiveSizeInWords"],
        reason: .runtimeOnly(detail: "computed by runtime from ClassDescriptor + parent chain")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ClassMetadataBoundsProtocol",
        members: ["immediateMembers", "negativeSizeInWords", "positiveSizeInWords"],
        reason: .runtimeOnly(detail: "marker protocol on runtime-computed class bounds")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "StoredClassMetadataBounds",
        members: ["init", "immediateMembers", "bounds"],
        reason: .runtimeOnly(detail: "filled in by runtime at class-loading time")
    ),
    // Type-flavored runtime metadata (B/C-eligible ones go here too;
    // C will convert them when InProcessMetadataPicker provides pointers)
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "StructMetadata",
        members: ["init", "kind", "description", "fieldOffsetVectorOffset"],
        reason: .runtimeOnly(detail: "live runtime metadata pointer; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "StructMetadataProtocol",
        members: ["description", "fieldOffsetVectorOffset"],
        reason: .runtimeOnly(detail: "marker protocol on StructMetadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "EnumMetadata",
        members: ["init", "kind", "description"],
        reason: .runtimeOnly(detail: "live runtime metadata; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "EnumMetadataProtocol",
        members: ["description"],
        reason: .runtimeOnly(detail: "marker protocol on EnumMetadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ClassMetadata",
        members: ["init", "kind", "superclass", "flags", "instanceAddressPoint", "instanceSize", "instanceAlignMask", "classSize", "classAddressPoint", "description", "iVarDestroyer"],
        reason: .runtimeOnly(detail: "live class metadata; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ClassMetadataObjCInterop",
        members: ["init", "isaPointer", "superclass", "cacheData0", "cacheData1", "data", "flags", "instanceAddressPoint", "instanceSize", "instanceAlignMask", "classSize", "classAddressPoint", "description", "iVarDestroyer"],
        reason: .runtimeOnly(detail: "live ObjC-interop class metadata; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "AnyClassMetadata",
        members: ["init", "kind", "isaPointer", "superclass"],
        reason: .runtimeOnly(detail: "any-class metadata; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "AnyClassMetadataObjCInterop",
        members: ["init", "isaPointer", "superclass", "cacheData0", "cacheData1", "data"],
        reason: .runtimeOnly(detail: "any-class metadata with ObjC interop; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "AnyClassMetadataProtocol",
        members: ["isaPointer", "superclass"],
        reason: .runtimeOnly(detail: "marker protocol on AnyClassMetadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "AnyClassMetadataObjCInteropProtocol",
        members: ["isaPointer", "superclass", "cacheData0", "cacheData1", "data"],
        reason: .runtimeOnly(detail: "marker protocol on AnyClassMetadataObjCInterop")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FinalClassMetadataProtocol",
        members: ["isaPointer", "superclass", "flags"],
        reason: .runtimeOnly(detail: "marker protocol on final class metadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "DispatchClassMetadata",
        members: ["init", "kind", "isaPointer", "superclass", "data", "ivar1", "flags"],
        reason: .runtimeOnly(detail: "Swift class with embedded ObjC metadata for dispatch; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ValueMetadata",
        members: ["init", "kind", "description"],
        reason: .runtimeOnly(detail: "value-type metadata (struct/enum); covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ValueMetadataProtocol",
        members: ["description"],
        reason: .runtimeOnly(detail: "marker protocol on ValueMetadata")
    ),
    // Existentials
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExistentialTypeMetadata",
        members: ["init", "kind", "flags", "numberOfWitnessTables", "numberOfProtocols", "isClassConstrained", "isErrorExistential", "superclassConstraint", "protocols"],
        reason: .runtimeOnly(detail: "live existential metadata; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExistentialMetatypeMetadata",
        members: ["init", "kind", "instanceType", "flags"],
        reason: .runtimeOnly(detail: "live existential metatype; covered via InProcess in Phase C")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExtendedExistentialTypeMetadata",
        members: ["init", "kind", "shape", "genericArguments"],
        reason: .runtimeOnly(detail: "Swift 5.7+ extended existential metadata; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExtendedExistentialTypeShape",
        members: ["init", "flags", "existentialType", "requirementSignatureHeader", "typeExpression", "suggestedValueWitnesses"],
        reason: .runtimeOnly(detail: "Shape descriptor stored alongside extended existential metadata at runtime")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "NonUniqueExtendedExistentialTypeShape",
        members: ["init", "uniqueShape", "specializedShape"],
        reason: .runtimeOnly(detail: "non-uniqued shape variant computed at runtime")
    ),
    // Tuple/function/metatype/opaque/fixed-array/heap
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TupleTypeMetadata",
        members: ["init", "kind", "numberOfElements", "labels", "elements"],
        reason: .runtimeOnly(detail: "tuple metadata is allocated lazily by the runtime; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "Element",
        members: ["init", "type", "offset"],
        reason: .runtimeOnly(detail: "TupleTypeMetadata.Element nested struct; lives in runtime tuple metadata")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FunctionTypeMetadata",
        members: ["init", "kind", "flags", "result", "parameters", "parameterFlags"],
        reason: .runtimeOnly(detail: "function-type metadata is uniqued at runtime; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MetatypeMetadata",
        members: ["init", "kind", "instanceType"],
        reason: .runtimeOnly(detail: "metatype metadata is per-type runtime singleton; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "OpaqueMetadata",
        members: ["init", "kind", "instanceType"],
        reason: .runtimeOnly(detail: "Swift Builtin opaque metadata; covered via InProcess")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FixedArrayTypeMetadata",
        members: ["init", "kind", "count", "element"],
        reason: .runtimeOnly(detail: "InlineArray<N, T> runtime metadata; covered via InProcess on Swift 6.2+")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericBoxHeapMetadata",
        members: ["init", "kind", "valueWitnessTable", "offsetOfBoxHeader", "captureOffset", "boxedType"],
        reason: .runtimeOnly(detail: "swift_allocBox-allocated; not feasible to construct stably from tests")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "HeapLocalVariableMetadata",
        members: ["init", "kind", "offsetToFirstCapture", "captureDescription"],
        reason: .runtimeOnly(detail: "captured by closures; not feasible to construct stably from tests")
    ),
    // Headers (live in metadata layout prefix)
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "HeapMetadataHeader",
        members: ["init", "destroy", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "metadata layout prefix; readable via InProcess + offset")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "HeapMetadataHeaderPrefix",
        members: ["init", "destroy"],
        reason: .runtimeOnly(detail: "metadata layout prefix")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeMetadataHeader",
        members: ["init", "destroy", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "metadata layout prefix")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeMetadataHeaderBase",
        members: ["destroy", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "marker protocol on type-metadata layout prefix")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeMetadataLayoutPrefix",
        members: ["destroy", "valueWitnessTable"],
        reason: .runtimeOnly(detail: "marker protocol on layout prefix")
    ),
    // Generic / VWT / runtime layer
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericEnvironment",
        members: ["init", "flags", "genericParameters", "requirements"],
        reason: .runtimeOnly(detail: "generic environment is materialized at runtime")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericWitnessTable",
        members: ["init", "witnessTableSizeInWords", "witnessTablePrivateSizeInWordsAndRequiresInstantiation", "instantiator", "privateData"],
        reason: .runtimeOnly(detail: "generic witness table allocated lazily by runtime")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ValueWitnessTable",
        members: ["init", "initializeBufferWithCopyOfBuffer", "destroy", "initializeWithCopy", "assignWithCopy", "initializeWithTake", "assignWithTake", "getEnumTagSinglePayload", "storeEnumTagSinglePayload", "size", "stride", "flags", "extraInhabitantCount"],
        reason: .runtimeOnly(detail: "value witness table is computed by runtime; covered via InProcess on stdlib types")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeLayout",
        members: ["init", "size", "stride", "flags", "extraInhabitantCount"],
        reason: .runtimeOnly(detail: "value-witness-table layout slice; covered via InProcess")
    ),
    // Foreign metadata initialization
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ForeignMetadataInitialization",
        members: ["init", "completionFunction"],
        reason: .runtimeOnly(detail: "foreign-metadata callback installed by runtime")
    ),
].flatMap { $0 }
```

- [ ] **Step 5: Populate `needsFixtureExtensionEntries`**

In `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`, replace the line:
```swift
    private static let needsFixtureExtensionEntries: [CoverageAllowlistEntry] = []
```
with:

```swift
private static let needsFixtureExtensionEntries: [CoverageAllowlistEntry] = [
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MethodDefaultOverrideDescriptor",
        members: ["originalMethodDescriptor", "replacementMethodDescriptor", "implementationSymbols", "layout", "offset"],
        reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore — Phase B1")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MethodDefaultOverrideTableHeader",
        members: ["init", "numEntries"],
        reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore — Phase B1")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "OverrideTableHeader",
        members: ["init", "numEntries"],
        reason: .needsFixtureExtension(detail: "no class triggers method-override table in SymbolTestsCore — Phase B1")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ResilientSuperclass",
        members: ["init", "superclass", "layout", "offset"],
        reason: .needsFixtureExtension(detail: "no resilient class with explicit superclass reference — Phase B2")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ObjCClassWrapperMetadata",
        members: ["init", "kind", "objcClass"],
        reason: .needsFixtureExtension(detail: "no NSObject-derived class in SymbolTestsCore — Phase B3")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ObjCResilientClassStubInfo",
        members: ["init", "stub"],
        reason: .needsFixtureExtension(detail: "no Swift class inheriting resilient ObjC class — Phase B4")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "RelativeObjCProtocolPrefix",
        members: ["init", "isObjC", "rawValue"],
        reason: .needsFixtureExtension(detail: "no ObjC-prefix protocol references in SymbolTestsCore — Phase B3")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ObjCProtocolPrefix",
        members: ["init", "rawValue"],
        reason: .needsFixtureExtension(detail: "no ObjC-prefix protocol references in SymbolTestsCore — Phase B3")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "CanonicalSpecializedMetadataAccessorsListEntry",
        members: ["init", "accessor"],
        reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "CanonicalSpecializedMetadatasCachingOnceToken",
        members: ["init", "token"],
        reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "CanonicalSpecializedMetadatasListCount",
        members: ["init", "count"],
        reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "CanonicalSpecializedMetadatasListEntry",
        members: ["init", "metadata"],
        reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ForeignClassMetadata",
        members: ["init", "kind", "name", "superclass", "reserved"],
        reason: .needsFixtureExtension(detail: "no foreign class import in SymbolTestsCore — Phase B6")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ForeignReferenceTypeMetadata",
        members: ["init", "kind", "name"],
        reason: .needsFixtureExtension(detail: "no foreign reference type in SymbolTestsCore — Phase B6")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericValueDescriptor",
        members: ["init", "type", "valueType"],
        reason: .needsFixtureExtension(detail: "no <let N: Int> value-generic type in SymbolTestsCore — Phase B7")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericValueHeader",
        members: ["init", "numValues"],
        reason: .needsFixtureExtension(detail: "no <let N: Int> value-generic type in SymbolTestsCore — Phase B7")
    ),
].flatMap { $0 }
```

- [ ] **Step 6: Populate `pureDataUtilityEntries`**

In `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`, replace the line:
```swift
    private static let pureDataUtilityEntries: [CoverageAllowlistEntry] = []
```
with:

```swift
private static let pureDataUtilityEntries: [CoverageAllowlistEntry] = [
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ContextDescriptorFlags",
        members: ["init", "rawValue", "kind", "isGeneric", "isUnique", "version", "kindSpecificFlags"],
        reason: .pureDataUtility(detail: "raw bitfield over context descriptor flag word")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ContextDescriptorKindSpecificFlags",
        members: ["init", "rawValue"],
        reason: .pureDataUtility(detail: "raw bitfield over kind-specific flag word")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "AnonymousContextDescriptorFlags",
        members: ["init", "rawValue", "hasMangledName"],
        reason: .pureDataUtility(detail: "raw bitfield over anonymous descriptor flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeContextDescriptorFlags",
        members: ["init", "rawValue", "metadataInitialization", "hasImportInfo", "hasCanonicalMetadataPrespecializations", "hasLayoutString"],
        reason: .pureDataUtility(detail: "raw bitfield over type-context flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ClassFlags",
        members: ["init", "rawValue", "hasResilientSuperclass", "hasOverrideTable", "hasVTable", "hasObjCResilientClassStub", "isActor", "isDefaultActor"],
        reason: .pureDataUtility(detail: "raw bitfield over class metadata flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExtraClassDescriptorFlags",
        members: ["init", "rawValue", "hasObjCResilientClassStub"],
        reason: .pureDataUtility(detail: "raw bitfield over extra class descriptor flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MethodDescriptorFlags",
        members: ["init", "rawValue", "isInstance", "isDynamic", "kind", "extraDiscriminator"],
        reason: .pureDataUtility(detail: "raw bitfield over method descriptor flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "MethodDescriptorKind",
        members: ["init", "rawValue"],
        reason: .pureDataUtility(detail: "method descriptor kind enum")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ProtocolDescriptorFlags",
        members: ["init", "rawValue", "hasClassConstraint", "isResilient", "specialProtocol", "dispatchStrategy"],
        reason: .pureDataUtility(detail: "raw bitfield over protocol descriptor flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ProtocolContextDescriptorFlags",
        members: ["init", "rawValue", "isClassConstrained", "isResilient", "specialProtocol"],
        reason: .pureDataUtility(detail: "raw bitfield over protocol-context flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ProtocolRequirementFlags",
        members: ["init", "rawValue", "kind", "isInstance", "extraDiscriminator"],
        reason: .pureDataUtility(detail: "raw bitfield over protocol requirement flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ProtocolRequirementKind",
        members: ["init", "rawValue"],
        reason: .pureDataUtility(detail: "protocol requirement kind enum")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericContextDescriptorFlags",
        members: ["init", "rawValue", "hasTypePacks", "hasConditionalInvertedRequirements"],
        reason: .pureDataUtility(detail: "raw bitfield over generic context flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericRequirementFlags",
        members: ["init", "rawValue", "hasKeyArgument", "isPackRequirement", "isValueRequirement", "kind"],
        reason: .pureDataUtility(detail: "raw bitfield over generic requirement flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "GenericEnvironmentFlags",
        members: ["init", "rawValue", "numGenericParameterLevels"],
        reason: .pureDataUtility(detail: "raw bitfield over generic environment flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FieldRecordFlags",
        members: ["init", "rawValue", "isVar", "isArtificial"],
        reason: .pureDataUtility(detail: "raw bitfield over field record flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ProtocolConformanceFlags",
        members: ["init", "rawValue", "kind", "isRetroactive", "isSynthesizedNonUnique", "numConditionalRequirements", "numConditionalPackShapeDescriptors", "hasResilientWitnesses", "hasGenericWitnessTable", "isGlobalActorIsolated"],
        reason: .pureDataUtility(detail: "raw bitfield over protocol conformance flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExistentialTypeFlags",
        members: ["init", "rawValue", "numProtocols", "numWitnessTables", "isClassConstraint", "isErrorExistential", "isObjCExistential"],
        reason: .pureDataUtility(detail: "raw bitfield over existential type flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ExtendedExistentialTypeShapeFlags",
        members: ["init", "rawValue", "specialKind", "hasGeneralizationSignature", "hasTypeExpression", "hasSuggestedValueWitnesses", "hasImplicitGenericParamsCount"],
        reason: .pureDataUtility(detail: "raw bitfield over extended existential shape flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "FunctionTypeFlags",
        members: ["init", "rawValue", "numParameters", "convention", "isThrowing", "isAsync", "isEscaping", "isSendable", "hasParameterFlags", "hasGlobalActor", "hasThrownError"],
        reason: .pureDataUtility(detail: "raw bitfield over function type flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ValueWitnessFlags",
        members: ["init", "rawValue", "alignmentMask", "isNonPOD", "isNonInline", "hasExtraInhabitants", "hasSpareBits", "isNonBitwiseTakable", "isIncomplete"],
        reason: .pureDataUtility(detail: "raw bitfield over value witness flags")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "ContextDescriptorKind",
        members: ["init", "rawValue"],
        reason: .pureDataUtility(detail: "context descriptor kind enum")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "EnumFunctions",
        members: ["destroy", "initializeWithCopy", "destructiveInjectEnumTag", "destructiveProjectEnumValue", "getEnumTag"],
        reason: .pureDataUtility(detail: "enum-specific value witness function group; covered via VWT InProcess test")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "InvertibleProtocolSet",
        members: ["init", "rawValue", "contains", "isSuppressedByDefault"],
        reason: .pureDataUtility(detail: "raw bitset over invertible protocols")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "InvertibleProtocolsRequirementCount",
        members: ["init", "rawValue"],
        reason: .pureDataUtility(detail: "encoded count of invertible protocol requirements")
    ),
    CoverageAllowlistHelpers.sentinelGroup(
        typeName: "TypeReference",
        members: ["init", "kind", "directType", "indirectType", "objCClassName"],
        reason: .pureDataUtility(detail: "discriminated union over type reference forms")
    ),
].flatMap { $0 }
```

- [ ] **Step 7: Run build to verify entries compile**

Run:
```bash
swift build 2>&1 | tail -3
```
Expected:
```
Build complete!
```

If a property name was wrong (the type's actual public surface uses a different name), this fails with `value of type 'X' has no member 'Y'` from the test target — but the new schema is in `MachOFixtureSupport`, so it won't fail on missing members directly. Instead, the **CoverageInvariant** will detect mismatches at runtime in step 8.

- [ ] **Step 8: Run CoverageInvariantTests, expect missing/extra to be empty**

Run:
```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -15
```
Expected: PASS. The new entries cover the same `MethodKey` set that the legacy single entry plus implicit "registered" set covered, so `missing` and `extra` remain empty.

If `extra` reports keys, those are members listed in the seeded array but not actually declared in `Sources/MachOSwiftSection/Models/`. Cross-check the spelling in `Models/<Type>.swift`. Common mistakes: `init` (no parameters) vs `init(layout:offset:)` (has parameters).

If `missing` reports keys, an existing public member was missed — add it to the appropriate sentinel group above.

- [ ] **Step 9: Run the entire fixture suite to confirm regression-free**

Run:
```bash
swift test --filter MachOSwiftSectionTests 2>&1 | tail -5
```
Expected: All previously-passing tests still pass.

- [ ] **Step 10: Commit**

```bash
git add Sources/MachOFixtureSupport/Coverage/CoverageAllowlist.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): seed sentinel reasons for 88 sentinel suites

Phase A2 of fixture-coverage tightening. Tags every existing
sentinel-only suite (88 suites, ~277 methods) with a typed
SentinelReason in CoverageAllowlistEntries, grouped via the new
sentinelGroup helper.

Categories:
  - runtimeOnly: ~50 suites — runtime-allocated metadata + headers,
    layered protocols, etc. Phase C will convert most to InProcess
    single-reader real tests.
  - needsFixtureExtension: ~15 suites — SymbolTestsCore lacks samples.
    Phase B will add fixtures and convert these.
  - pureDataUtility: ~25 suites — pure raw-value enums, flag bitfields,
    discriminated unions. Permanent sentinels; rawValue pinning is a
    follow-up.

CoverageInvariant assertions are not yet tightened (next commit).
EOF
)"
```

---

### Task A3: Enable `liarSentinel` and `unmarkedSentinel` invariant assertions

**Files:**
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift`

- [ ] **Step 1: Update CoverageInvariant test to include behavior scanning + new assertions**

Replace the entire contents of `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift` with:

```swift
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
```

- [ ] **Step 2: Run CoverageInvariant test, expect all four assertions pass**

Run:
```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -15
```
Expected: PASS.

If `liarSentinels` reports keys: a Suite labeled sentinel calls cross-reader test machinery — either the Suite was upgraded recently and the allowlist tag is stale, or the scanner detected a misleading substring. Fix the allowlist tag.

If `unmarked` reports keys: a Suite without `acrossAllReaders`/`inProcessContext` exists but isn't tagged sentinel — verify A2 covered all ~88 sentinel suites; add the missing one to the appropriate group.

- [ ] **Step 3: Run full test suite to confirm no regression**

Run:
```bash
swift test 2>&1 | tail -5
```
Expected: All previously-passing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): enable liarSentinel + unmarkedSentinel invariant assertions

Phase A3 of fixture-coverage tightening. Tightens
MachOSwiftSectionCoverageInvariantTests with two new assertions backed
by SuiteBehaviorScanner (per-method @Test behavior introspection):

  ③ liarSentinel — fails if a sentinel-tagged key's Suite actually
    calls acrossAllReaders / inProcessContext. Catches stale tags
    after a sentinel suite is upgraded to a real test.

  ④ unmarkedSentinel — fails if a Suite has sentinel behavior (no
    acrossAllReaders / inProcessContext call) but the key isn't
    declared sentinel in CoverageAllowlistEntries. Closes the
    silent-sentinel loophole found in PR #85 review.

The PR's 88 existing sentinel suites are tagged in A2; this commit
just wires the gates. Phase B and Phase C remove sentinel entries as
suites are converted to real tests.
EOF
)"
```

- [ ] **Step 5: Push Phase A**

```bash
git push 2>&1 | tail -5
```
Expected: success on `feature/machoswift-section-fixture-tests` upstream.

---

## Phase C — Runtime-only InProcess conversion

### Task C1: Add `InProcessMetadataPicker` + `usingInProcessOnly` helper

**Files:**
- Create: `Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift`
- Modify: `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift`

- [ ] **Step 1: Create `InProcessMetadataPicker.swift`**

Create `Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift`:

```swift
import Foundation

/// Static `UnsafeRawPointer` constants exposing Swift runtime metadata
/// for Suites that exercise `*Metadata` types without a fixture-binary
/// section presence (runtime-allocated metadata).
///
/// Each constant is a `unsafeBitCast(<TypeRef>.self, to: UnsafeRawPointer.self)`
/// — this is the standard idiom for obtaining a metadata pointer from a
/// Swift type reference. The pointer is stable for the test process's
/// lifetime; the Swift runtime uniques metadata.
///
/// Suites consume these via `MachOSwiftSectionFixtureTests.usingInProcessOnly(_:)`.
package enum InProcessMetadataPicker {
    // MARK: - stdlib metatype

    /// `Int.self.self` — metatype of metatype. Exercises `MetatypeMetadata.kind`
    /// + `instanceType` chain.
    package static let stdlibIntMetatype: UnsafeRawPointer = {
        unsafeBitCast(Int.self.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib tuple

    /// `(Int, String).self` — covers `TupleTypeMetadata` + `TupleTypeMetadata.Element`.
    package static let stdlibTupleIntString: UnsafeRawPointer = {
        unsafeBitCast((Int, String).self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib function

    /// `((Int) -> Void).self` — covers `FunctionTypeMetadata` + `FunctionTypeFlags`.
    package static let stdlibFunctionIntToVoid: UnsafeRawPointer = {
        unsafeBitCast(((Int) -> Void).self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib existential

    /// `Any.self` — covers `ExistentialTypeMetadata` for the maximally-general
    /// existential.
    package static let stdlibAnyExistential: UnsafeRawPointer = {
        unsafeBitCast(Any.self, to: UnsafeRawPointer.self)
    }()

    /// `(any Equatable).self` — covers `ExtendedExistentialTypeMetadata` (with
    /// shape) and constrained existential.
    package static let stdlibAnyEquatable: UnsafeRawPointer = {
        unsafeBitCast((any Equatable).self, to: UnsafeRawPointer.self)
    }()

    /// `(Any).Type.self` — covers `ExistentialMetatypeMetadata`.
    package static let stdlibAnyMetatype: UnsafeRawPointer = {
        unsafeBitCast(Any.Type.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib opaque

    /// `Int8.self` proxies for OpaqueMetadata; Swift runtime exposes opaque
    /// metadata via Builtin types but `Builtin.Int8` isn't visible outside
    /// the standard library, so use the user-visible `Int8` whose metadata
    /// includes the same opaque-metadata layout.
    package static let stdlibOpaqueInt8: UnsafeRawPointer = {
        unsafeBitCast(Int8.self, to: UnsafeRawPointer.self)
    }()

    // MARK: - stdlib fixed array (macOS 26+ only)

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    package static let stdlibInlineArrayInt3: UnsafeRawPointer = {
        unsafeBitCast(InlineArray<3, Int>.self, to: UnsafeRawPointer.self)
    }()
    #endif
}
```

The `*MetadataHeader`, `*MetadataBounds`, and `Metadata`/`FullMetadata`/etc. layer-protocol Suites are covered using existing pointers above + `InProcessContext` offset arithmetic; they don't need separate constants.

- [ ] **Step 2: Add `usingInProcessOnly` helper to `MachOSwiftSectionFixtureTests`**

In `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift`, append a new helper extension at the bottom of the file (after the existing `acrossAllReaders` / `acrossAllContexts` helpers):

```swift
extension MachOSwiftSectionFixtureTests {
    /// Run `body` against the in-process reader only. Used by Suites covering
    /// runtime-only metadata types (MetatypeMetadata, TupleTypeMetadata,
    /// FunctionTypeMetadata, etc.) — types that the Swift runtime allocates
    /// at type-load time and that have no Mach-O section to read from.
    ///
    /// Cross-reader equality is not asserted because `MachOFile` and
    /// `MachOImage` cannot reach this metadata. Single-reader assertion +
    /// baseline literal pinning is the deepest coverage achievable.
    package func usingInProcessOnly<T: Equatable>(
        _ work: (InProcessContext) throws -> T,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> T {
        try work(inProcessContext)
    }
}
```

- [ ] **Step 3: Run build to verify**

Run:
```bash
swift build 2>&1 | tail -3
```
Expected:
```
Build complete!
```

- [ ] **Step 4: Run full test suite to confirm no regression**

Run:
```bash
swift test 2>&1 | tail -5
```
Expected: All previously-passing tests still pass. CoverageInvariant remains green (no allowlist changes).

- [ ] **Step 5: Commit**

```bash
git add Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift \
        Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift
git commit -m "$(cat <<'EOF'
feat(MachOFixtureSupport): add InProcessMetadataPicker + usingInProcessOnly

Phase C1 of fixture-coverage tightening. Provides the infrastructure
for converting runtime-only metadata sentinel suites to real
single-reader InProcess tests:

  - InProcessMetadataPicker exposes `UnsafeRawPointer` constants for
    stdlib metatype, tuple, function, existential, opaque, and fixed
    array (macOS 26+) types via `unsafeBitCast(T.self, to: UnsafeRawPointer.self)`.
    Each pointer is stable for the test process lifetime (Swift
    runtime uniques metadata).

  - MachOSwiftSectionFixtureTests gains usingInProcessOnly(_:), the
    SuiteBehaviorScanner-recognized helper that runs a closure with
    only the in-process reader and skips cross-reader assertions
    (other readers cannot see runtime-allocated metadata).

C2-C5 will use these to convert ~30 runtime-only sentinel suites.
EOF
)"
```

---

### Task C2: Convert stdlib metatype/tuple/function suites (5 suites)

**Files:**
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Metadata/MetatypeMetadataTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/TupleType/TupleTypeMetadataTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/TupleType/TupleTypeMetadataElementTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Function/FunctionTypeMetadataTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Function/FunctionTypeFlagsTests.swift`
- Modify (5): corresponding `Sources/MachOFixtureSupport/Baseline/Generators/.../*BaselineGenerator.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` (remove 5 suite groups from `runtimeOnlyEntries`)

This task converts the most straightforward 5 sentinel suites — those whose underlying types live in stdlib and have stable metadata pointers via `InProcessMetadataPicker`. Each follows the same pattern.

- [ ] **Step 1: Convert `MetatypeMetadataTests.swift`**

Replace the contents of `Tests/MachOSwiftSectionTests/Fixtures/Metadata/MetatypeMetadataTests.swift` with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class MetatypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MetatypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        MetatypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let result = try usingInProcessOnly { context in
            try MetatypeMetadata(at: InProcessMetadataPicker.stdlibIntMetatype, in: context).kind
        }
        #expect(result.rawValue == MetatypeMetadataBaseline.stdlibIntMetatype.kindRawValue)
    }

    @Test func instanceType() async throws {
        let pointer = try usingInProcessOnly { context in
            try MetatypeMetadata(at: InProcessMetadataPicker.stdlibIntMetatype, in: context).instanceType
        }
        // `Int.self.self.instanceType == Int.self`. The pointer must equal
        // `unsafeBitCast(Int.self, to: UnsafeRawPointer.self)`.
        #expect(pointer == unsafeBitCast(Int.self, to: UnsafeRawPointer.self))
    }
}
```

- [ ] **Step 2: Update `MetatypeMetadataBaselineGenerator.swift` to emit InProcess Entry**

Replace the contents of `Sources/MachOFixtureSupport/Baseline/Generators/Metadata/MetatypeMetadataBaselineGenerator.swift` with:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum MetatypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibIntMetatype
        let metatype = try MetatypeMetadata(at: pointer, in: InProcessContext())
        let kindRaw = metatype.kind.rawValue

        let registered = ["instanceType", "kind"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (stdlib `Int.self.self`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MetatypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt
            }

            static let stdlibIntMetatype = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MetatypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Regenerate the baseline**

Run:
```bash
swift package --allow-writing-to-package-directory regen-baselines --suite MetatypeMetadata 2>&1 | tail -5
```
Expected: success, baseline updated. Verify:
```bash
cat Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/MetatypeMetadataBaseline.swift
```
Should show non-zero `kindRawValue` (the value of `MetadataKind.metatype`).

- [ ] **Step 4: Run the converted suite**

Run:
```bash
swift test --filter MetatypeMetadataTests 2>&1 | tail -10
```
Expected: 2 tests pass (`kind`, `instanceType`).

- [ ] **Step 5: Convert `TupleTypeMetadataTests.swift`**

Replace contents with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class TupleTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TupleTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let result = try usingInProcessOnly { context in
            try TupleTypeMetadata(at: InProcessMetadataPicker.stdlibTupleIntString, in: context).kind
        }
        #expect(result.rawValue == TupleTypeMetadataBaseline.stdlibTupleIntString.kindRawValue)
    }

    @Test func numberOfElements() async throws {
        let result = try usingInProcessOnly { context in
            try TupleTypeMetadata(at: InProcessMetadataPicker.stdlibTupleIntString, in: context).numberOfElements
        }
        #expect(result == TupleTypeMetadataBaseline.stdlibTupleIntString.numberOfElements)
    }

    @Test func labels() async throws {
        let result = try usingInProcessOnly { context in
            try TupleTypeMetadata(at: InProcessMetadataPicker.stdlibTupleIntString, in: context).labels
        }
        #expect(result == TupleTypeMetadataBaseline.stdlibTupleIntString.labels)
    }
}
```

- [ ] **Step 6: Update `TupleTypeMetadataBaselineGenerator.swift`**

Replace contents with:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum TupleTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibTupleIntString
        let context = InProcessContext()
        let metadata = try TupleTypeMetadata(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let count = metadata.numberOfElements
        let labels = metadata.labels

        let registered = ["kind", "labels", "numberOfElements"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (stdlib `(Int, String).self`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt
                let numberOfElements: Int
                let labels: String
            }

            static let stdlibTupleIntString = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                numberOfElements: \(literal: count),
                labels: \(literal: labels)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 7: Regenerate + run**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite TupleTypeMetadata 2>&1 | tail -3
swift test --filter TupleTypeMetadataTests 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 8: Convert `TupleTypeMetadataElementTests.swift`**

Replace contents with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class TupleTypeMetadataElementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Element"
    static var registeredTestMethodNames: Set<String> {
        TupleTypeMetadataElementBaseline.registeredTestMethodNames
    }

    @Test func type() async throws {
        let result = try usingInProcessOnly { context in
            let tuple = try TupleTypeMetadata(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
            return try tuple.elements.first!.type
        }
        // First element of `(Int, String)` is `Int` — pointer must equal Int's metadata.
        #expect(result == unsafeBitCast(Int.self, to: UnsafeRawPointer.self))
    }

    @Test func offset() async throws {
        let result = try usingInProcessOnly { context in
            let tuple = try TupleTypeMetadata(at: InProcessMetadataPicker.stdlibTupleIntString, in: context)
            return try tuple.elements.first!.offset
        }
        #expect(result == TupleTypeMetadataElementBaseline.firstElementOfIntStringTuple.offset)
    }
}
```

- [ ] **Step 9: Update `TupleTypeMetadataElementBaselineGenerator.swift`**

Replace contents with:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum TupleTypeMetadataElementBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibTupleIntString
        let context = InProcessContext()
        let tuple = try TupleTypeMetadata(at: pointer, in: context)
        let firstElement = try tuple.elements.first!
        let offset = try firstElement.offset

        let registered = ["offset", "type"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess first element of `(Int, String)`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TupleTypeMetadataElementBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
            }

            static let firstElementOfIntStringTuple = Entry(
                offset: \(literal: offset)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TupleTypeMetadataElementBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 10: Regenerate + run**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite TupleTypeMetadataElement 2>&1 | tail -3
swift test --filter TupleTypeMetadataElementTests 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 11: Convert `FunctionTypeMetadataTests.swift`**

Replace contents with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class FunctionTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let result = try usingInProcessOnly { context in
            try FunctionTypeMetadata(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context).kind
        }
        #expect(result.rawValue == FunctionTypeMetadataBaseline.stdlibFunctionIntToVoid.kindRawValue)
    }

    @Test func flags() async throws {
        let result = try usingInProcessOnly { context in
            try FunctionTypeMetadata(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context).flags.rawValue
        }
        #expect(result == FunctionTypeMetadataBaseline.stdlibFunctionIntToVoid.flagsRawValue)
    }
}
```

- [ ] **Step 12: Update `FunctionTypeMetadataBaselineGenerator.swift`**

Replace contents with:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum FunctionTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibFunctionIntToVoid
        let context = InProcessContext()
        let metadata = try FunctionTypeMetadata(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let flagsRaw = metadata.flags.rawValue

        let registered = ["flags", "kind"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `((Int) -> Void).self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt
                let flagsRawValue: UInt
            }

            static let stdlibFunctionIntToVoid = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 13: Convert `FunctionTypeFlagsTests.swift`**

Replace contents with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class FunctionTypeFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "FunctionTypeFlags"
    static var registeredTestMethodNames: Set<String> {
        FunctionTypeFlagsBaseline.registeredTestMethodNames
    }

    @Test func numberOfParameters() async throws {
        let result = try usingInProcessOnly { context in
            try FunctionTypeMetadata(at: InProcessMetadataPicker.stdlibFunctionIntToVoid, in: context)
                .flags.numParameters
        }
        #expect(result == FunctionTypeFlagsBaseline.stdlibFunctionIntToVoid.numParameters)
    }
}
```

- [ ] **Step 14: Update `FunctionTypeFlagsBaselineGenerator.swift`**

Replace contents with:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum FunctionTypeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibFunctionIntToVoid
        let context = InProcessContext()
        let metadata = try FunctionTypeMetadata(at: pointer, in: context)
        let numParams = metadata.flags.numParameters

        let registered = ["numberOfParameters"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `((Int) -> Void).self` flags slice.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let numParameters: Int
            }

            static let stdlibFunctionIntToVoid = Entry(
                numParameters: \(literal: numParams)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 15: Regenerate both Function baselines + run**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite FunctionTypeMetadata 2>&1 | tail -3
swift package --allow-writing-to-package-directory regen-baselines --suite FunctionTypeFlags 2>&1 | tail -3
swift test --filter "FunctionTypeMetadataTests|FunctionTypeFlagsTests" 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 16: Remove the 5 converted suites from `runtimeOnlyEntries`**

Edit `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`. In the `runtimeOnlyEntries` array, **delete** the 5 `sentinelGroup` calls for:
- `MetatypeMetadata`
- `TupleTypeMetadata`
- `Element` (the `TupleTypeMetadata.Element` group)
- `FunctionTypeMetadata`

(Note: `FunctionTypeFlags` is in `pureDataUtilityEntries` not `runtimeOnlyEntries` — it's `numberOfParameters` registered above so the registered method becomes a real test, but the type stays in `pureDataUtility` allowlist for unconverted methods. Do **not** remove it from `pureDataUtilityEntries` here. The `numberOfParameters` registered name is now a real test, so it should be removed from the allowlist's `FunctionTypeFlags` group's members list.)

For `FunctionTypeFlags` in `pureDataUtilityEntries`, change:
```swift
CoverageAllowlistHelpers.sentinelGroup(
    typeName: "FunctionTypeFlags",
    members: ["init", "rawValue", "numParameters", "convention", "isThrowing", "isAsync", "isEscaping", "isSendable", "hasParameterFlags", "hasGlobalActor", "hasThrownError"],
    ...
)
```
to:
```swift
CoverageAllowlistHelpers.sentinelGroup(
    typeName: "FunctionTypeFlags",
    members: ["init", "rawValue", "convention", "isThrowing", "isAsync", "isEscaping", "isSendable", "hasParameterFlags", "hasGlobalActor", "hasThrownError"],
    ...
)
```
(removed `numberOfParameters` — wait, the original used `numParameters` which is the `FunctionTypeFlags` property name; the `@Test` is `numberOfParameters`. The `MethodKey` is keyed on the **public method name** which is `numParameters` in the source. Inspect `Sources/MachOSwiftSection/Models/Function/FunctionTypeFlags.swift` to confirm the actual public name. If the source says `numParameters`, the suite's `@Test func numberOfParameters` is technically registering a different name than the source declares — flag this in step 18.)

- [ ] **Step 17: Run CoverageInvariant + full test**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -10
swift test --filter MachOSwiftSectionTests 2>&1 | tail -5
```
Expected: PASS. CoverageInvariant should now confirm 5 fewer sentinel-tagged keys, all replaced by real-test keys.

- [ ] **Step 18: Reconcile property name mismatch if step 16 found one**

If `FunctionTypeFlags` source declares `numParameters` but the suite uses `@Test func numberOfParameters`, fix the test name to match the source, regenerate baseline, re-run. (`MethodKey` matching is exact: scanner produces `(FunctionTypeFlags, numParameters)`; if test is named `numberOfParameters`, scanner won't see a match in `expected`.)

- [ ] **Step 19: Commit**

```bash
git add Tests/MachOSwiftSectionTests/Fixtures/Metadata/MetatypeMetadataTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/TupleType/TupleTypeMetadataTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/TupleType/TupleTypeMetadataElementTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Function/FunctionTypeMetadataTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Function/FunctionTypeFlagsTests.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Metadata/MetatypeMetadataBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/TupleType/TupleTypeMetadataBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/TupleType/TupleTypeMetadataElementBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Function/FunctionTypeMetadataBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Function/FunctionTypeFlagsBaselineGenerator.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/MetatypeMetadataBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/TupleTypeMetadataBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/TupleTypeMetadataElementBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/FunctionTypeMetadataBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/FunctionTypeFlagsBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): convert metatype/tuple/function suites to InProcess real tests

Phase C2 of fixture-coverage tightening. Converts 5 sentinel-only
suites covering stdlib runtime-allocated metadata:
  - MetatypeMetadata (Int.self.self)
  - TupleTypeMetadata, TupleTypeMetadataElement ((Int, String).self)
  - FunctionTypeMetadata, FunctionTypeFlags (((Int) -> Void).self)

Each suite now uses usingInProcessOnly + InProcessMetadataPicker
constants and asserts against ABI literals pinned in regenerated
baselines. Removed corresponding entries from CoverageAllowlistEntries
runtimeOnly group.
EOF
)"
```

---

### Task C3: Convert existential family suites (7 suites)

**Files:**
- Modify (7): `Tests/MachOSwiftSectionTests/Fixtures/ExistentialType/*Tests.swift`
- Modify (7): `Sources/MachOFixtureSupport/Baseline/Generators/ExistentialType/*BaselineGenerator.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`

This task converts the existential-family suites: `ExistentialTypeMetadata`, `ExistentialMetatypeMetadata`, `ExistentialTypeFlags`, `ExtendedExistentialTypeMetadata`, `ExtendedExistentialTypeShape`, `ExtendedExistentialTypeShapeFlags`, `NonUniqueExtendedExistentialTypeShape`.

The pattern follows C2 exactly — use `InProcessMetadataPicker.stdlibAnyExistential` for plain existentials, `stdlibAnyEquatable` for extended existentials, `stdlibAnyMetatype` for existential metatype.

- [ ] **Step 1: Convert `ExistentialTypeMetadataTests.swift`**

Replace with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class ExistentialTypeMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ExistentialTypeMetadata"
    static var registeredTestMethodNames: Set<String> {
        ExistentialTypeMetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).kind
        }
        #expect(result.rawValue == ExistentialTypeMetadataBaseline.stdlibAnyExistential.kindRawValue)
    }

    @Test func numberOfProtocols() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).numberOfProtocols
        }
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyExistential.numberOfProtocols)
    }

    @Test func numberOfWitnessTables() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).numberOfWitnessTables
        }
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyExistential.numberOfWitnessTables)
    }

    @Test func isClassConstrained() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).isClassConstrained
        }
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyExistential.isClassConstrained)
    }

    @Test func isErrorExistential() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).isErrorExistential
        }
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyExistential.isErrorExistential)
    }

    @Test func flags() async throws {
        let result = try usingInProcessOnly { context in
            try ExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyExistential, in: context).flags.rawValue
        }
        #expect(result == ExistentialTypeMetadataBaseline.stdlibAnyExistential.flagsRawValue)
    }
}
```

- [ ] **Step 2: Update `ExistentialTypeMetadataBaselineGenerator.swift`**

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

package enum ExistentialTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.stdlibAnyExistential
        let context = InProcessContext()
        let metadata = try ExistentialTypeMetadata(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let numProtocols = metadata.numberOfProtocols
        let numWitnessTables = metadata.numberOfWitnessTables
        let classConstrained = metadata.isClassConstrained
        let errorExistential = metadata.isErrorExistential
        let flagsRaw = metadata.flags.rawValue

        let registered = ["flags", "isClassConstrained", "isErrorExistential", "kind", "numberOfProtocols", "numberOfWitnessTables"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess `Any.self`; no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt
                let numberOfProtocols: Int
                let numberOfWitnessTables: Int
                let isClassConstrained: Bool
                let isErrorExistential: Bool
                let flagsRawValue: UInt32
            }

            static let stdlibAnyExistential = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                numberOfProtocols: \(literal: numProtocols),
                numberOfWitnessTables: \(literal: numWitnessTables),
                isClassConstrained: \(literal: classConstrained),
                isErrorExistential: \(literal: errorExistential),
                flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Regenerate + verify ExistentialTypeMetadata**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite ExistentialTypeMetadata 2>&1 | tail -3
swift test --filter ExistentialTypeMetadataTests 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 4: Apply the same pattern to remaining 6 existential suites**

Repeat steps 1-3 (suite + generator + regenerate + test) for each of:

| Suite | InProcess source | Methods to convert |
|---|---|---|
| `ExistentialMetatypeMetadataTests` | `stdlibAnyMetatype` | `kind`, `instanceType`, `flags` |
| `ExistentialTypeFlagsTests` | `stdlibAnyExistential.flags` slice | `numProtocols`, `numWitnessTables`, `isClassConstraint`, `isErrorExistential`, `isObjCExistential`, `rawValue` |
| `ExtendedExistentialTypeMetadataTests` | `stdlibAnyEquatable` | `kind`, `shape` |
| `ExtendedExistentialTypeShapeTests` | `(stdlibAnyEquatable as ExtendedExistentialTypeMetadata).shape` | `flags`, `existentialType`, `requirementSignatureHeader` |
| `ExtendedExistentialTypeShapeFlagsTests` | shape flags slice | `specialKind`, `hasGeneralizationSignature`, `hasTypeExpression`, `rawValue` |
| `NonUniqueExtendedExistentialTypeShapeTests` | maybe-not-applicable; if `(any Equatable).shape` is uniqued, leave as `runtimeOnly` and document |

For the shape tests, source the shape pointer like this in the suite:
```swift
let shapePointer = try usingInProcessOnly { context in
    try ExtendedExistentialTypeMetadata(at: InProcessMetadataPicker.stdlibAnyEquatable, in: context).shape
}
let result = try usingInProcessOnly { context in
    try ExtendedExistentialTypeShape(at: shapePointer, in: context).<member>
}
```

If `NonUniqueExtendedExistentialTypeShape` cannot be sourced from `(any Equatable).self` (most extended existentials use the unique form), update that suite's allowlist entry to keep it `runtimeOnly` with detail "non-unique form not produced by stdlib types"; do not convert.

- [ ] **Step 5: Update `CoverageAllowlistEntries.swift`**

In `runtimeOnlyEntries`, remove the `sentinelGroup` calls for converted types:
- `ExistentialTypeMetadata`
- `ExistentialMetatypeMetadata`
- `ExtendedExistentialTypeMetadata`
- `ExtendedExistentialTypeShape`
- (Keep `NonUniqueExtendedExistentialTypeShape` if not converted)

In `pureDataUtilityEntries`, the `ExistentialTypeFlags` and `ExtendedExistentialTypeShapeFlags` entries' members list should drop converted method names.

- [ ] **Step 6: Run CoverageInvariant + full**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -10
swift test --filter "ExistentialType|ExtendedExistentialType" 2>&1 | tail -5
```
Expected: PASS. Liar/unmarked sentinel reports empty.

- [ ] **Step 7: Push C2 + C3 progress (mid-Phase C push)**

```bash
git add Tests/MachOSwiftSectionTests/Fixtures/ExistentialType/ \
        Sources/MachOFixtureSupport/Baseline/Generators/ExistentialType/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Existential*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ExtendedExistential*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/NonUniqueExtended*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): convert existential-family suites to InProcess real tests

Phase C3. Converts 6-7 existential-related sentinel suites to
real InProcess single-reader tests using stdlib `Any.self` and
`(any Equatable).self` as metadata sources.

NonUniqueExtendedExistentialTypeShape may remain runtimeOnly if
stdlib produces only the unique form — documented in allowlist.
EOF
)"

git push 2>&1 | tail -3
```

---

### Task C4: Convert fixture-nominal-bound metadata suites (~10 suites)

**Files:**
- Modify (~10): suites under `Tests/MachOSwiftSectionTests/Fixtures/Type/{Struct,Enum,Class}/Metadata/...`
- Modify (~10): generators
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`

These suites cover metadata for types that **do** have a fixture-binary nominal type counterpart but whose metadata is still runtime-allocated (e.g., `StructMetadata` of `StructTest`).

- [ ] **Step 1: Add fixture-nominal pickers**

Append to `Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift`:

```swift
extension InProcessMetadataPicker {
    // MARK: - fixture nominal types
    //
    // These metadata pointers come from `dlopen`-loaded SymbolTestsCore
    // types reached via `unsafeBitCast(<Type>.self, to: UnsafeRawPointer.self)`.
    // The fixture must be loaded into the test process (handled by
    // MachOSwiftSectionFixtureTests' dlopen) before these are valid.
    //
    // Type names follow the SymbolTestsCore convention `Structs.StructTest`,
    // `Classes.ClassTest`, `Enums.EnumTest`. We resolve them via @objc lookup
    // when ObjC bridge applies, otherwise via a generated symbol-resolution
    // helper. For simplicity here, we hard-code unsafeBitCast on the
    // public Swift type reference — but the SymbolTestsCore module is
    // not imported into MachOFixtureSupport (it's a separate framework
    // loaded at test time). We expose them as accessor functions taking
    // a metadata pointer, sourced by the consuming Suite via dlsym.

    /// Returns a metadata pointer for SymbolTestsCore's nominal type.
    /// `metatypeName` is the demangled symbol of the type metadata accessor,
    /// e.g. "$s15SymbolTestsCore10StructTestVMa".
    package static func fixtureMetadata(symbol: String) throws -> UnsafeRawPointer {
        guard let handle = dlopen(nil, RTLD_NOW) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(path: "<self>", dlerror: nil)
        }
        guard let accessorAddress = dlsym(handle, symbol) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: symbol,
                dlerror: dlerror().map { String(cString: $0) }
            )
        }
        // Type metadata accessor signature: `MetadataResponse(MetadataRequest)`.
        // For simple non-generic types, pass MetadataRequest(0) and return
        // the metadata pointer from the response.
        typealias MetadataAccessor = @convention(c) (UInt) -> (UnsafeRawPointer, UInt)
        let accessor = unsafeBitCast(accessorAddress, to: MetadataAccessor.self)
        let response = accessor(0)
        return response.0
    }
}
```

- [ ] **Step 2: Convert `StructMetadataTests.swift`**

Replace contents of `Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructMetadataTests.swift` with:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class StructMetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructMetadata"
    static var registeredTestMethodNames: Set<String> {
        StructMetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let pointer = try InProcessMetadataPicker.fixtureMetadata(
            symbol: "$s15SymbolTestsCore10StructTestVMa"
        )
        let result = try usingInProcessOnly { context in
            try StructMetadata(at: pointer, in: context).kind
        }
        #expect(result.rawValue == StructMetadataBaseline.structTest.kindRawValue)
    }

    @Test func description() async throws {
        let pointer = try InProcessMetadataPicker.fixtureMetadata(
            symbol: "$s15SymbolTestsCore10StructTestVMa"
        )
        let result = try usingInProcessOnly { context in
            try StructMetadata(at: pointer, in: context).description
        }
        // The description pointer should equal the StructDescriptor's offset
        // resolved via MachOFile (already covered by StructDescriptorTests),
        // so just assert it's non-zero here.
        #expect(result != UnsafeRawPointer(bitPattern: 0))
    }

    @Test func fieldOffsetVectorOffset() async throws {
        let pointer = try InProcessMetadataPicker.fixtureMetadata(
            symbol: "$s15SymbolTestsCore10StructTestVMa"
        )
        let result = try usingInProcessOnly { context in
            try StructMetadata(at: pointer, in: context).fieldOffsetVectorOffset
        }
        #expect(result == StructMetadataBaseline.structTest.fieldOffsetVectorOffset)
    }
}
```

- [ ] **Step 3: Update `StructMetadataBaselineGenerator.swift`**

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection
import MachOFixtureSupport

package enum StructMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = try InProcessMetadataPicker.fixtureMetadata(
            symbol: "$s15SymbolTestsCore10StructTestVMa"
        )
        let context = InProcessContext()
        let metadata = try StructMetadata(at: pointer, in: context)
        let kindRaw = metadata.kind.rawValue
        let fieldOffsetVectorOffset = try metadata.fieldOffsetVectorOffset

        let registered = ["description", "fieldOffsetVectorOffset", "kind"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess SymbolTestsCore.Structs.StructTest metadata.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt
                let fieldOffsetVectorOffset: Int
            }

            static let structTest = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw)),
                fieldOffsetVectorOffset: \(literal: fieldOffsetVectorOffset)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StructMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

The mangled symbol `$s15SymbolTestsCore10StructTestVMa` follows Swift mangling: `$s` + module-name-length + module-name + type-name-length + type-name + `V` (struct) + `Ma` (metadata accessor). If `StructTest` is nested inside `Structs.swift`'s top-level enum namespace, the mangled name becomes `$s15SymbolTestsCore7StructsO10StructTestVMa`. Run

```bash
nm -gU Tests/Projects/SymbolTests/DerivedData/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore | grep '10StructTest' | grep 'Ma$'
```

to confirm the exact symbol name. Replace `$s15SymbolTestsCore10StructTestVMa` with whatever `nm` reports.

- [ ] **Step 4: Regenerate + verify**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite StructMetadata 2>&1 | tail -3
swift test --filter StructMetadataTests 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 5: Apply the same pattern to remaining fixture-nominal suites**

Repeat steps 2-4 for each of:

| Suite | Fixture type | Symbol pattern |
|---|---|---|
| `EnumMetadataTests` | `EnumTest` | `$s...10EnumTestOMa` (`O` = enum) |
| `ClassMetadataTests` | `ClassTest` | `$s...09ClassTestCMa` (`C` = class) |
| `ClassMetadataObjCInteropTests` | (skip if `ClassTest` doesn't inherit NSObject — Phase B3 will add it) |
| `AnyClassMetadataTests` | `ClassTest` | reuse `$s...09ClassTestCMa` |
| `AnyClassMetadataObjCInteropTests` | (skip; depends on B3) |
| `DispatchClassMetadataTests` | `ClassTest` | reuse `$s...09ClassTestCMa` (DispatchClassMetadata layer reads class metadata + ObjC fields, can probe with regular Swift class) |
| `ValueMetadataTests` | `StructTest` | reuse |
| `StructMetadataProtocolTests` | (protocol-extension on StructMetadata; protocol methods are not stand-alone) — most likely just maps to StructMetadata methods, may not need separate suite. Inspect `Sources/MachOSwiftSection/Models/Type/Struct/StructMetadataProtocol.swift` to see what extension methods it adds. If empty, allowlist stays `pureDataUtility`. |
| `EnumMetadataProtocolTests` | similar |
| `AnyClassMetadataProtocolTests` | similar |
| `AnyClassMetadataObjCInteropProtocolTests` | similar |
| `FinalClassMetadataProtocolTests` | similar |
| `ValueMetadataProtocolTests` | similar |
| `ClassMetadataBoundsTests` | from `ClassMetadata.bounds`; reuse `ClassTest` |
| `ClassMetadataBoundsProtocolTests` | similar |
| `StoredClassMetadataBoundsTests` | similar |

For each suite:
1. Add 2-5 `@Test` methods using `usingInProcessOnly` + appropriate metadata pointer
2. Update generator to emit ABI-literal `Entry`
3. Regenerate baseline
4. Run suite

- [ ] **Step 6: Update `CoverageAllowlistEntries.swift`**

Remove from `runtimeOnlyEntries`:
- All converted suite entries

Keep:
- `ClassMetadataObjCInterop`, `AnyClassMetadataObjCInterop` (and their protocol forms) — wait until Phase B3 adds NSObject-inheriting fixture
- All `MetadataBounds*` if they're protocol-only (no public stand-alone surface)
- All `*MetadataProtocol` if they're empty marker protocols (no extension methods)

- [ ] **Step 7: Run CoverageInvariant + full**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -10
swift test 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 8: Commit + push**

```bash
git add Tests/MachOSwiftSectionTests/Fixtures/Type/ \
        Tests/MachOSwiftSectionTests/Fixtures/Metadata/ \
        Sources/MachOFixtureSupport/Baseline/Generators/Type/ \
        Sources/MachOFixtureSupport/Baseline/Generators/Metadata/ \
        Sources/MachOFixtureSupport/InProcess/InProcessMetadataPicker.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/EnumMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ClassMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AnyClassMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/DispatchClass*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ValueMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/*Bounds*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): convert fixture-nominal metadata suites to InProcess

Phase C4. Converts ~10 sentinel suites covering metadata bound to
SymbolTestsCore nominal types (StructMetadata of StructTest, etc.)
using dlsym-resolved metadata accessor functions.

ObjC-interop variants (ClassMetadataObjCInterop, etc.) deferred to
Phase B3 once NSObject-inheriting fixture lands.
EOF
)"

git push 2>&1 | tail -3
```

---

### Task C5: Convert metadata-layer suites (~6 suites)

**Files:**
- Modify (~6): `Tests/MachOSwiftSectionTests/Fixtures/Metadata/*.swift`
- Modify (~6): generators
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`

This task converts the "metadata layer" suites — types covering the metadata layout prefix (`*MetadataHeader`, `*Bounds`, `MetadataResponse`, `Metadata`, `FullMetadata`, `MetadataAccessorFunction`, `SingletonMetadataPointer`, etc.). They reuse the metadata pointers from C2/C3/C4 and read offset slices.

- [ ] **Step 1: Convert `MetadataTests.swift`**

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class MetadataTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "Metadata"
    static var registeredTestMethodNames: Set<String> {
        MetadataBaseline.registeredTestMethodNames
    }

    @Test func kind() async throws {
        let pointer = InProcessMetadataPicker.stdlibIntMetatype
        let result = try usingInProcessOnly { context in
            try Metadata(at: pointer, in: context).kind
        }
        #expect(result.rawValue == MetadataBaseline.intMetadata.kindRawValue)
    }

    @Test func valueWitnessTable() async throws {
        let pointer = InProcessMetadataPicker.stdlibIntMetatype
        let pointer2 = try usingInProcessOnly { context in
            try Metadata(at: pointer, in: context).valueWitnessTable
        }
        #expect(pointer2 != UnsafeRawPointer(bitPattern: 0))
    }
}
```

- [ ] **Step 2: Update generator + regenerate**

Apply pattern from C2 step 2; baseline emits `kindRawValue` for `Int.self.self` metadata layer.

- [ ] **Step 3: Convert remaining metadata-layer suites**

| Suite | Pointer source | Methods |
|---|---|---|
| `FullMetadataTests` | `stdlibIntMetatype` | `metadata`, `header` |
| `MetadataWrapperTests` | `stdlibIntMetatype` | `pointer`, `kind` |
| `MetadataResponseTests` | construct via `MetadataRequest(0)` accessor call | `metadata`, `state` |
| `MetadataRequestTests` | new `MetadataRequest(state: .complete)` instance | `rawValue`, `state`, `isBlocking` |
| `MetadataAccessorFunctionTests` | dlsym lookup of any accessor | `address`, `invoke` |
| `SingletonMetadataPointerTests` | from a fixture singleton accessor | `pointer`, `metadata` |
| `MetadataBoundsTests` | computed offset on class metadata | `negativeSizeInWords`, `positiveSizeInWords` |
| `HeapMetadataHeaderTests` | header offset before class metadata | `destroy`, `valueWitnessTable` |
| `HeapMetadataHeaderPrefixTests` | similar | `destroy` |
| `TypeMetadataHeaderTests` | type-metadata layout prefix | `valueWitnessTable` |

- [ ] **Step 4: Update `CoverageAllowlistEntries.swift`**

Remove converted suites' entries from `runtimeOnlyEntries`. Keep `MetadataProtocol`, `MetadataBoundsProtocol`, `*BaseProtocol` (marker-only protocols) and `GenericBoxHeapMetadata`, `HeapLocalVariableMetadata` (cannot construct stably).

- [ ] **Step 5: Run CoverageInvariant + full + commit + push (Phase C complete)**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -10
swift test 2>&1 | tail -5

git add Tests/MachOSwiftSectionTests/Fixtures/Metadata/ \
        Sources/MachOFixtureSupport/Baseline/Generators/Metadata/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Metadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Heap*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Type*Header*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): convert metadata-layer suites to InProcess

Phase C5 — completes Phase C. Converts ~6 metadata-layer suites:
Metadata, FullMetadata, MetadataWrapper, MetadataRequest/Response,
MetadataAccessorFunction, SingletonMetadataPointer, *MetadataHeader,
*Bounds. Each reuses pointers from C2-C4 + offset arithmetic.

Remaining runtimeOnly sentinel: marker protocols (no public extension
methods) and GenericBoxHeapMetadata / HeapLocalVariableMetadata
(cannot construct stably from tests).
EOF
)"

git push 2>&1 | tail -3
```

---

## Phase B — SymbolTestsCore Fixture Extension

### Task B0: Re-align baselines if `xcodebuild` rebuild drift detected

**Files:**
- Possibly: all `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/*Baseline.swift`

This task is conditional. If during Phase A or Phase C the `SymbolTestsCore.framework` binary in `Tests/Projects/SymbolTests/DerivedData/` was modified incidentally (e.g., re-derived during Xcode auto-build), the file/image baselines may have drifted relative to the latest build. Re-run the regen and review diffs.

- [ ] **Step 1: Detect drift**

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
           -scheme SymbolTestsCore -configuration Release build 2>&1 | tail -5

swift package --allow-writing-to-package-directory regen-baselines 2>&1 | tail -5

git diff --stat Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
```
Expected: empty diff (Phase A/C didn't introduce drift) or a small set of file/image-baseline tweaks.

- [ ] **Step 2: If diff is non-empty, review and commit baseline alignment**

```bash
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/  # human review
git add Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): realign baselines after SymbolTestsCore rebuild

Phase B0. After xcodebuild produced a fresh SymbolTestsCore.framework,
baselines drift in offset/flag values. This commit captures the new
ABI literal values; review the diff to confirm only expected drift.
EOF
)"
```

If the diff is empty, **skip this task**.

- [ ] **Step 3: Confirm tests pass**

```bash
swift test --filter MachOSwiftSectionTests 2>&1 | tail -5
```
Expected: PASS.

---

### Task B1: Add `DefaultOverrideTable.swift` fixture

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/DefaultOverrideTable.swift`
- Modify: `Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift`
- Modify: `Sources/MachOFixtureSupport/Baseline/Generators/Class/MethodDefaultOverrideDescriptorBaselineGenerator.swift`
- Modify: `Sources/MachOFixtureSupport/Baseline/Generators/Class/MethodDefaultOverrideTableHeaderBaselineGenerator.swift`
- Modify: `Sources/MachOFixtureSupport/Baseline/Generators/Class/OverrideTableHeaderBaselineGenerator.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Method/MethodDefaultOverrideDescriptorTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Method/MethodDefaultOverrideTableHeaderTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/Type/Class/OverrideTableHeaderTests.swift`
- Modify: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`

- [ ] **Step 1: Create the fixture file**

Create `Tests/Projects/SymbolTests/SymbolTestsCore/DefaultOverrideTable.swift`:

```swift
// Fixtures producing __swift5_types entries with method default-override tables.
//
// `dynamicReplacement(for:)` causes the compiler to emit a method
// default-override descriptor in the class context descriptor's tail.
// We declare a "primary" class with a dynamic method, then a separate
// extension that replaces it via `@_dynamicReplacement(for:)`.

public enum DefaultOverrideTableFixtures {
    /// Primary class whose dynamic method will be replaced. The presence of
    /// `dynamic` triggers the class to emit a method-override stub in its
    /// vtable, and the replacement adds an entry to the default-override
    /// table.
    open class PrimaryWithDynamic {
        public init() {}
        public dynamic func dynamicMethod() -> Int { 1 }
    }

    /// Replacement extension. The `@_dynamicReplacement(for:)` attribute
    /// causes the compiler to emit a default-override descriptor in the
    /// primary class's descriptor tail.
    public static func setupReplacement() {}
}

extension DefaultOverrideTableFixtures.PrimaryWithDynamic {
    @_dynamicReplacement(for: dynamicMethod())
    public func replacedDynamicMethod() -> Int { 2 }
}
```

- [ ] **Step 2: Rebuild SymbolTestsCore**

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
           -scheme SymbolTestsCore -configuration Release build 2>&1 | tail -5
```
Expected:
```
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Verify the new descriptor surface**

```bash
nm -gU Tests/Projects/SymbolTests/DerivedData/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore \
  | grep 'PrimaryWithDynamic'
```
Expected: visible mangled symbols for the class and its replacement, including a `Mn` (nominal type descriptor) suffix.

- [ ] **Step 4: Add picker for the new fixture**

In `Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift`, append:

```swift
extension BaselineFixturePicker {
    /// Picks the SymbolTestsCore class with default-override table
    /// (`DefaultOverrideTableFixtures.PrimaryWithDynamic`).
    package static func class_PrimaryWithDynamic(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "PrimaryWithDynamic"
            })
        )
    }
}
```

- [ ] **Step 5: Convert `MethodDefaultOverrideDescriptorTests.swift` to real test**

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class MethodDefaultOverrideDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDefaultOverrideDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MethodDefaultOverrideDescriptorBaseline.registeredTestMethodNames
    }

    @Test func offset() async throws {
        let fileSubject = try BaselineFixturePicker.class_PrimaryWithDynamic(in: machOFile)
        let imageSubject = try BaselineFixturePicker.class_PrimaryWithDynamic(in: machOImage)

        let result = try acrossAllReaders(
            file: { try fileSubject.methodDefaultOverrideDescriptors(in: machOFile).first!.offset },
            image: { try imageSubject.methodDefaultOverrideDescriptors(in: machOImage).first!.offset }
        )
        #expect(result == MethodDefaultOverrideDescriptorBaseline.primaryReplacement.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try BaselineFixturePicker.class_PrimaryWithDynamic(in: machOFile)
        let imageSubject = try BaselineFixturePicker.class_PrimaryWithDynamic(in: machOImage)

        let originalDescriptorOffset = try acrossAllReaders(
            file: { try fileSubject.methodDefaultOverrideDescriptors(in: machOFile).first!.layout.originalMethodDescriptor.offset },
            image: { try imageSubject.methodDefaultOverrideDescriptors(in: machOImage).first!.layout.originalMethodDescriptor.offset }
        )
        #expect(originalDescriptorOffset == MethodDefaultOverrideDescriptorBaseline.primaryReplacement.layoutOriginalMethodDescriptorOffset)
    }
}
```

(Adjust calls to match the actual public API of `ClassDescriptor` for accessing `methodDefaultOverrideDescriptors`. Check `Sources/MachOSwiftSection/Models/Type/Class/ClassDescriptor.swift` for the exact method/property name. If absent, use the existing `extension`-style accessor and adjust the suite.)

- [ ] **Step 6: Update `MethodDefaultOverrideDescriptorBaselineGenerator.swift`**

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

package enum MethodDefaultOverrideDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let primary = try BaselineFixturePicker.class_PrimaryWithDynamic(in: machO)
        let firstDescriptor = try primary.methodDefaultOverrideDescriptors(in: machO).first!
        let offset = firstDescriptor.offset
        let originalOffset = firstDescriptor.layout.originalMethodDescriptor.offset

        let registered = ["implementationSymbols", "layout", "offset", "originalMethodDescriptor", "replacementMethodDescriptor"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source fixture: SymbolTestsCore.DefaultOverrideTableFixtures.PrimaryWithDynamic
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodDefaultOverrideDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutOriginalMethodDescriptorOffset: Int
            }

            static let primaryReplacement = Entry(
                offset: \(raw: BaselineEmitter.hex(offset)),
                layoutOriginalMethodDescriptorOffset: \(raw: BaselineEmitter.hex(originalOffset))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDefaultOverrideDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
```

Update `BaselineGenerator.dispatchSuite`'s `MethodDefaultOverrideDescriptor` case to pass the `machOFile` argument (it was previously called without `in:`):

```swift
case "MethodDefaultOverrideDescriptor":
    try MethodDefaultOverrideDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
```

- [ ] **Step 7: Update `MethodDefaultOverrideTableHeaderTests.swift` and `OverrideTableHeaderTests.swift`**

Apply the same pattern: source `numEntries` from `class_PrimaryWithDynamic`'s default-override table header. Both suites become `acrossAllReaders` based.

- [ ] **Step 8: Regenerate the three baselines**

```bash
swift package --allow-writing-to-package-directory regen-baselines --suite MethodDefaultOverrideDescriptor 2>&1 | tail -3
swift package --allow-writing-to-package-directory regen-baselines --suite MethodDefaultOverrideTableHeader 2>&1 | tail -3
swift package --allow-writing-to-package-directory regen-baselines --suite OverrideTableHeader 2>&1 | tail -3
```

- [ ] **Step 9: Run the three converted suites**

```bash
swift test --filter "MethodDefaultOverrideDescriptorTests|MethodDefaultOverrideTableHeaderTests|OverrideTableHeaderTests" 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 10: Remove the three suite groups from `needsFixtureExtensionEntries`**

In `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`'s `needsFixtureExtensionEntries`, delete the three `sentinelGroup` calls:
- `MethodDefaultOverrideDescriptor`
- `MethodDefaultOverrideTableHeader`
- `OverrideTableHeader`

- [ ] **Step 11: Run CoverageInvariant + full**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | tail -10
swift test --filter MachOSwiftSectionTests 2>&1 | tail -5
```
Expected: PASS.

- [ ] **Step 12: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/DefaultOverrideTable.swift \
        Tests/Projects/SymbolTests/DerivedData/ \
        Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Class/MethodDefaultOverrideDescriptorBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Class/MethodDefaultOverrideTableHeaderBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Class/OverrideTableHeaderBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/BaselineGenerator.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Method/MethodDefaultOverrideDescriptorTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Method/MethodDefaultOverrideTableHeaderTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/OverrideTableHeaderTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/MethodDefaultOverride*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/OverrideTableHeader*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(fixture): add DefaultOverrideTable fixture, convert 3 sentinel suites

Phase B1 of fixture-coverage tightening. Adds
SymbolTestsCore.DefaultOverrideTableFixtures.PrimaryWithDynamic, a
class with a `dynamic` method replaced via `@_dynamicReplacement(for:)`.
This produces a method default-override table in the class context
descriptor's tail, surfacing:

  - MethodDefaultOverrideDescriptor (per-replacement record)
  - MethodDefaultOverrideTableHeader (table header)
  - OverrideTableHeader (general method-override table header)

All three suites convert from sentinel registrationOnly to real
acrossAllReaders cross-reader assertions. Allowlist entries removed.
EOF
)"
```

---

### Task B2: Add `ResilientClasses.swift` fixture (2 suites)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ResilientClasses.swift`
- Modify: `Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift`
- Modify (2): generators
- Modify (2): suites
- Modify: `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Create fixture**

```swift
// Fixtures producing classes with resilient superclass references and
// resilient bounds (i.e., the compiler defers metadata bounds computation
// to runtime because the parent class's layout may change).

public enum ResilientClassFixtures {
    /// Resilient class — declared `@_fixed_layout` is INTENTIONALLY OMITTED,
    /// and the framework is built `-enable-library-evolution` so this class
    /// gets resilient metadata bounds.
    public class ResilientBase {
        public init() {}
        public var counter: Int = 0
    }

    /// Subclass referring to the resilient parent. Triggers a
    /// ResilientSuperclass record in the class context descriptor.
    public class ResilientChild: ResilientBase {
        public override init() { super.init() }
        public var extraField: Int = 0
    }
}
```

- [ ] **Step 2: Rebuild + verify**

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
           -scheme SymbolTestsCore -configuration Release build 2>&1 | tail -5
nm -gU Tests/Projects/SymbolTests/DerivedData/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore \
  | grep 'ResilientChild'
```

- [ ] **Step 3: Add `class_ResilientChild` picker, convert `ResilientSuperclassTests` and `StoredClassMetadataBoundsTests`, update generators, regenerate baselines, run, remove from `needsFixtureExtensionEntries`**

Follow B1 pattern (steps 4-12) substituting `ResilientChild` for `PrimaryWithDynamic`. The two suites are:

| Suite | Methods | Fixture source |
|---|---|---|
| `ResilientSuperclassTests` | `superclass`, `layout`, `offset` | `ResilientChild`'s class descriptor's resilient-superclass tail |
| `StoredClassMetadataBoundsTests` | `immediateMembers`, `bounds` | `ResilientChild` runtime-loaded class metadata's bounds slot |

Note: `StoredClassMetadataBoundsTests` reads class metadata at runtime, so it stays InProcess-only — but it's now backed by a real fixture-bound class, so you can assert pinned literal values.

- [ ] **Step 4: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/ResilientClasses.swift \
        Tests/Projects/SymbolTests/DerivedData/ \
        Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Class/ResilientSuperclassBaselineGenerator.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/Class/StoredClassMetadataBoundsBaselineGenerator.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Resilient/ResilientSuperclassTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Metadata/Bounds/StoredClassMetadataBoundsTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ResilientSuperclassBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StoredClassMetadataBoundsBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(fixture): add ResilientClasses fixture, convert 2 sentinel suites

Phase B2. SymbolTestsCore.ResilientClassFixtures.ResilientChild
inherits from ResilientBase; under -enable-library-evolution the
parent's metadata is resilient, triggering:

  - ResilientSuperclass (descriptor tail record)
  - StoredClassMetadataBounds (runtime-loaded class metadata bounds)

Both suites converted from sentinel to real tests; allowlist updated.
EOF
)"
```

---

### Task B3: Add `ObjCClassWrappers.swift` fixture (4 suites)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ObjCClassWrappers.swift`
- Modify: same support files as B1, B2
- Modify (4): suites + generators
- Modify: `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Create fixture**

```swift
import Foundation

// Fixtures producing classes with ObjC interop, surfacing
// AnyClassMetadataObjCInterop, ClassMetadataObjCInterop,
// ObjCClassWrapperMetadata, and ObjC protocol prefix metadata.

public enum ObjCClassWrapperFixtures {
    /// Swift class inheriting NSObject — gets full ObjC interop metadata.
    @objc(SymbolTestsCoreObjCBridgeClass)
    public class ObjCBridge: NSObject {
        public override init() { super.init() }
        @objc public var label: String = "objc"
    }

    /// Class with ObjC-protocol conformance — surfaces RelativeObjCProtocolPrefix.
    @objc public protocol ObjCProto {
        @objc func ping()
    }

    @objc(SymbolTestsCoreObjCBridgeWithProto)
    public class ObjCBridgeWithProto: NSObject, ObjCProto {
        public override init() { super.init() }
        public func ping() {}
    }
}
```

- [ ] **Step 2: Rebuild SymbolTestsCore**

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
           -scheme SymbolTestsCore -configuration Release build 2>&1 | tail -5
```

- [ ] **Step 3: Add picker for ObjC-bridge classes**

```swift
extension BaselineFixturePicker {
    package static func class_ObjCBridge(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ClassDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.class).first(where: { descriptor in
                try descriptor.name(in: machO) == "ObjCBridge"
            })
        )
    }
}
```

- [ ] **Step 4: Convert 4 suites**

| Suite | Methods | Pattern |
|---|---|---|
| `ObjCClassWrapperMetadataTests` | `kind`, `objcClass` | InProcess `unsafeBitCast(NSObject.self, to: UnsafeRawPointer.self)` (NSObject metadata is the wrapped form) |
| `ClassMetadataObjCInteropTests` | full property set | InProcess on `ObjCBridge`'s metadata via dlsym |
| `AnyClassMetadataObjCInteropTests` | `isaPointer`, `superclass`, etc. | same |
| `RelativeObjCProtocolPrefixTests` | `isObjC`, `rawValue` | from `ObjCProto`'s relative-protocol-descriptor reference in `ObjCBridgeWithProto`'s conformance |

- [ ] **Step 5-7: Update generators, regenerate baselines, run**

Standard pattern per B1 steps 6-9.

- [ ] **Step 8: Remove from `needsFixtureExtensionEntries`**

Delete `sentinelGroup` calls for: `ObjCClassWrapperMetadata`, `RelativeObjCProtocolPrefix`, `ObjCProtocolPrefix`. Move `ClassMetadataObjCInterop` and `AnyClassMetadataObjCInterop` from `runtimeOnlyEntries` to nothing (they're converted now).

- [ ] **Step 9: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/ObjCClassWrappers.swift \
        Tests/Projects/SymbolTests/DerivedData/ \
        Sources/MachOFixtureSupport/Baseline/BaselineFixturePicker.swift \
        Sources/MachOFixtureSupport/Baseline/Generators/ \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/ \
        Tests/MachOSwiftSectionTests/Fixtures/Protocol/ObjC/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ObjCClassWrapper*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ClassMetadataObjCInterop*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AnyClassMetadataObjCInterop*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/RelativeObjCProtocolPrefix*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift
git commit -m "$(cat <<'EOF'
test(fixture): add ObjCClassWrappers fixture, convert 4 sentinel suites

Phase B3. ObjCBridge (NSObject-derived) and ObjCBridgeWithProto
(conforming to @objc protocol) surface:
  - ObjCClassWrapperMetadata
  - ClassMetadataObjCInterop, AnyClassMetadataObjCInterop
  - RelativeObjCProtocolPrefix

All 4 suites converted to real tests via dlsym + InProcess pointer
acquisition. Allowlist entries removed.
EOF
)"

git push 2>&1 | tail -3   # Phase B mid-push
```

---

### Task B4: Add `ObjCResilientStubs.swift` fixture (1 suite)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ObjCResilientStubs.swift`
- Modify: `BaselineFixturePicker.swift`, generator, suite, `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Create fixture**

```swift
import Foundation

// A Swift class inheriting from a resilient ObjC class. The Swift compiler
// emits an `ObjCResilientClassStubInfo` record so the runtime can fixup
// the class's superclass pointer at load time.
//
// Inherit from NSDictionary (a resilient Foundation class); the framework's
// -enable-library-evolution means the Swift compiler treats Foundation as
// resilient and emits the stub record.

public enum ObjCResilientStubFixtures {
    public class ResilientObjCSubclass: NSDictionary {}
}
```

- [ ] **Step 2-9: Rebuild, picker, convert `ObjCResilientClassStubInfoTests`, generator, regenerate, run, remove allowlist entry, commit**

Standard pattern.

```bash
git commit -m "test(fixture): add ObjCResilientStubs fixture, convert ObjCResilientClassStubInfo"
```

---

### Task B5: Add `CanonicalSpecializedMetadata.swift` fixture (4 suites, experimental)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/CanonicalSpecializedMetadata.swift`
- Modify (4): suites + generators
- Modify: `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Attempt fixture**

```swift
// Fixtures producing canonical pre-specialized metadata.
// `@_specialize(exported: true, where T == Int)` on a generic function or
// type causes the compiler to emit a "canonical specialized metadata
// list" entry for the specialization, complete with caching once-token
// and accessor function.
//
// Stability note: this attribute's emission rules can shift between
// Swift versions. If the resulting binary doesn't surface
// CanonicalSpecializedMetadatas* records (verify with otool / xref to
// __swift5_types tail), this fixture stays sentinel.

public enum CanonicalSpecializedFixtures {
    @_specialize(exported: true, where T == Int)
    @_specialize(exported: true, where T == String)
    public static func specializedFunction<T>(_ value: T) -> T { value }

    public struct SpecializedGeneric<T> {
        public init(_ value: T) {}
    }
}
```

- [ ] **Step 2: Rebuild + verify presence**

```bash
xcodebuild ... build
otool -V -s __TEXT __swift5_types Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore | head -30
```

If the `__swift5_types` section gains entries with canonical-specialized-metadata tails (look for "canonical specialized" in `otool -V -s __TEXT __swift5_types`), proceed. Otherwise:

- [ ] **Step 3: If presence not surfaced, document and skip**

Update `CoverageAllowlistEntries.swift` `needsFixtureExtensionEntries` to relabel the 4 canonical-specialized entries as `runtimeOnly` with detail "@_specialize(exported:) on stdlib types not emitted by Swift 6.2 — needs revisit when toolchain emission changes". Move them to `runtimeOnlyEntries`. Commit:

```bash
git commit -m "test: defer canonical-specialized-metadata fixture (Swift 6.2 toolchain doesn't emit)"
```

Skip remaining steps for B5.

- [ ] **Step 4: Otherwise, convert 4 suites + commit**

Standard pattern, similar to B1.

---

### Task B6: Add `ForeignTypes.swift` fixture (2 suites)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/ForeignTypes.swift`
- Modify (2): suites + generators
- Modify: `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Create fixture (uses CoreFoundation)**

```swift
import CoreFoundation

// Fixtures producing references to foreign classes. CoreFoundation types
// (CFString, CFArray) are imported as foreign classes — the Swift compiler
// emits a ForeignClassMetadata record for them.

public enum ForeignTypeFixtures {
    public static func foreignClassReference() -> CFString {
        "" as CFString
    }
}
```

- [ ] **Step 2-9: Rebuild, convert `ForeignClassMetadataTests` and `ForeignReferenceTypeMetadataTests`, etc.**

Note: `ForeignReferenceTypeMetadata` covers C++ interop foreign-reference types; if SymbolTestsCore can't reasonably import C++, leave that one as `runtimeOnly` with detail "no C++ interop in SymbolTestsCore".

```bash
git commit -m "test(fixture): add ForeignTypes fixture, convert ForeignClassMetadata"
```

---

### Task B7: Add `GenericValueParameters.swift` fixture (2 suites)

**Files:**
- Create: `Tests/Projects/SymbolTests/SymbolTestsCore/GenericValueParameters.swift`
- Modify: `CoverageAllowlistEntries.swift`

- [ ] **Step 1: Attempt fixture**

```swift
// Generic types with value parameters (Swift 6.1+).

@available(macOS 26.0, *)
public enum GenericValueFixtures {
    public struct FixedSizeArray<let N: Int, T> {
        public init() {}
    }
}
```

- [ ] **Step 2: Rebuild**

If Swift 6.2 / Xcode 26 is the active toolchain, this should compile. If not:

- [ ] **Step 3: If unavailable, defer**

Move `GenericValueDescriptor` and `GenericValueHeader` from `needsFixtureExtensionEntries` to `runtimeOnlyEntries` with detail "value generics require macOS 26.0 + InProcess only — defer to follow-up PR after toolchain stabilizes". Commit:

```bash
git commit -m "test: defer value-generic fixture pending toolchain stability"
```

- [ ] **Step 4: Otherwise, convert 2 suites + commit**

Standard pattern.

```bash
git commit -m "test(fixture): add GenericValueParameters fixture, convert GenericValueDescriptor/Header"
git push 2>&1 | tail -3   # Phase B complete push
```

---

## Phase D — Cleanup

### Task D1: Update CLAUDE.md fixture-coverage section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md fixture-coverage section**

In `CLAUDE.md`, find the "Fixture-Based Test Coverage (MachOSwiftSection)" section. Replace it with:

```markdown
## Fixture-Based Test Coverage (MachOSwiftSection)

`MachOSwiftSection/Models/` is exhaustively covered by `Tests/MachOSwiftSectionTests/Fixtures/`. Suites mirror the source directory and assert one of:

- **Cross-reader equality** across MachOFile/MachOImage/InProcess + their ReadingContext counterparts (via `acrossAllReaders` / `acrossAllContexts` helpers), plus per-method ABI literal values from `__Baseline__/*Baseline.swift` — this is the standard depth.
- **InProcess single-reader equality** plus per-method ABI literal values (via `usingInProcessOnly` helper). Used for runtime-allocated metadata types (MetatypeMetadata, TupleTypeMetadata, etc.) that have no Mach-O section presence.
- **Sentinel allowlist** with typed `SentinelReason` (in `CoverageAllowlistEntries.swift`). Used for:
  - `pureDataUtility`: pure raw-value enums / flag bitfields with no behavior to test (tests would just be tautologies)
  - `runtimeOnly`: types impossible to construct stably from tests (e.g., `swift_allocBox`-allocated `GenericBoxHeapMetadata`)

`MachOSwiftSectionCoverageInvariantTests` enforces four invariants:
1. Every public method in `Sources/MachOSwiftSection/Models/` has a registered test (or allowlist entry)
2. Every registered test name maps to an actual public method
3. Sentinel-tagged keys' Suites must actually have sentinel behavior (no acrossAllReaders / inProcessContext)
4. Sentinel-behavior Suites must be tagged in the allowlist (no silent sentinels)

To add a new public method:

1. Add the method.
2. Run `swift test --filter MachOSwiftSectionCoverageInvariantTests` to see which Suite needs updating.
3. Add a `@Test` to that Suite, using `acrossAllReaders` for fixture-bound types or `usingInProcessOnly` for runtime-only metadata.
4. Append the member name to `registeredTestMethodNames`.
5. Run `swift package --allow-writing-to-package-directory regen-baselines --suite <Name>` to regenerate the baseline.
6. Re-run the affected Suite.

To regenerate all baselines after fixture rebuild or toolchain upgrade:

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore -configuration Release build
swift package --allow-writing-to-package-directory regen-baselines
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/  # review drift
```

The `regen-baselines` command is provided by the `RegenerateBaselinesPlugin`
SwiftPM command plugin (`Plugins/RegenerateBaselinesPlugin/`). It builds and
invokes the `baseline-generator` executable target. From Xcode you can also
right-click the package → "Regenerate MachOSwiftSection fixture-test ABI
baselines.".
```

- [ ] **Step 2: Run all gates one last time**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -10
```
Expected: All green.

- [ ] **Step 3: Verify the residual sentinel set**

```bash
grep -E '\.sentinel\(' Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift | grep -oE 'runtimeOnly|needsFixtureExtension|pureDataUtility' | sort | uniq -c
```
Expected: only `runtimeOnly` (~3-5) and `pureDataUtility` (~25). `needsFixtureExtension` count should be 0 (or only appear with explicit "deferred" detail comments from B5/B7 if those were skipped).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(MachOSwiftSection): update fixture-coverage workflow for sentinel concept

Phase D of fixture-coverage tightening (closes the work). Updates
CLAUDE.md to reflect:
  - acrossAllReaders / usingInProcessOnly distinction
  - typed SentinelReason categorization
  - 4-invariant CoverageInvariant
  - regen-baselines SwiftPM plugin path
EOF
)"
```

- [ ] **Step 5: Push final**

```bash
git push 2>&1 | tail -3
```

---

## Self-Review Notes

This plan covers every requirement from the spec:

- ✅ Goal 1 (typed `SentinelReason`): Tasks A1, A2
- ✅ Goal 2 (4 invariants): Task A3
- ✅ Goal 3 (88 suites categorized): Task A2
- ✅ Goal 4 (15 fixture types added): Tasks B1-B7
- ✅ Goal 5 (~30 runtime-only suites converted): Tasks C2-C5
- ✅ Goal 6 (residual ~25 pureDataUtility + ~3-5 runtimeOnly): verified in Task D1 step 3

Risks called out in spec section 5.4 are addressed inline:
- Scanner edge cases — addressed in A1 step 7 implementation
- xcodebuild drift — addressed in B0 conditional task
- Fixture build failures — fallback paths in B5 (canonical specialized) and B7 (value generics) explicitly documented
- macOS 26 dependency — guarded with `@available` in InProcessMetadataPicker
- swift_allocBox unavailability — `GenericBoxHeapMetadata` and `HeapLocalVariableMetadata` kept as `runtimeOnly` with documented detail
