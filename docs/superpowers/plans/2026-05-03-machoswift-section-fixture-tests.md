# MachOSwiftSection Fixture-Based Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish fixture-based tests covering every `public`/`open` `func`/`var`/`init` declared under `Sources/MachOSwiftSection/Models/`, with cross-reader equality assertions (MachOFile/MachOImage/InProcess + their `ReadingContext` equivalents) and full ABI literal expected values pinned in git.

**Architecture:** Four pillars. (1) `MachOSwiftSectionFixtureTests` base loads `SymbolTestsCore.framework` from disk *and* `dlopen`s it into the test process, exposing `machOFile`, `machOImage`, three `ReadingContext` instances. (2) Per-method `@Test` Suites under `Tests/MachOSwiftSectionTests/Fixtures/` mirror the `Models/` directory; each `@Test` does cross-reader equality + reference to a baseline literal. (3) `baseline-generator` executable target reads fixture via MachOFile path, emits `__Baseline__/<Suite>Baseline.swift` literal data files committed to git. (4) `MachOSwiftSectionCoverageInvariantTests` uses SwiftSyntax to scan `Models/` source and reflects all `FixtureSuite`-conforming Suites; missing/extra members fail the build.

**Tech Stack:** Swift 6.2 / Xcode 26.0+, swift-testing, SwiftSyntax + SwiftParser + SwiftSyntaxBuilder (already a Package.swift dep), MachOKit, dlopen/dlfcn, ArgumentParser.

**Code generation strategy:** Baseline files are produced via SwiftSyntaxBuilder's string-interpolation form (`SourceFileSyntax(stringLiteral:)` + `\(literal:)` / `\(raw:)`). SwiftSyntax parses the interpolated source, rejecting any malformed syntax at generation time, and `.formatted()` normalizes indentation/whitespace. A small `BaselineEmitter` helper covers cases `\(literal:)` doesn't natively support (hex literals — Int default to decimal in `\(literal:)`).

**Branch:** `feature/machoswift-section-fixture-tests` (already created from `feature/reading-context-api`).

**Spec reference:** `docs/superpowers/specs/2026-05-03-machoswift-section-fixture-tests-design.md`.

**Prerequisites:** Before any task, run `swift package update` from the repo root to ensure SPM dependencies are current (per CLAUDE.md). Confirm the fixture is built: `xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore -configuration Release build` if `Tests/Projects/SymbolTests/DerivedData/.../SymbolTestsCore.framework` is absent.

---

## File Structure

### Sources/MachOTestingSupport/ (existing target — extend)
- **Modify** `MachOImageName.swift` — add `SymbolTestsCore`, `SymbolTests` cases mirroring `MachOFileName`
- **Create** `MachOSwiftSectionFixtureTests.swift` — base test class
- **Create** `FixtureLoadError.swift` — error type
- **Create** `Coverage/MethodKey.swift` — `(typeName, memberName)` struct
- **Create** `Coverage/FixtureSuite.swift` — protocol Suite types conform to
- **Create** `Coverage/PublicMemberScanner.swift` — SwiftSyntax static scan
- **Create** `Coverage/CoverageAllowlist.swift` — allowlist data type (entries supplied by test target)
- **Create** `Baseline/BaselineEmitter.swift` — small helper (`hex`/`hexArray`) for emitting hex integer literals as `\(raw:)` interpolations; strings/bools/decimal ints/optionals/arrays-of-strings handled directly by SwiftSyntaxBuilder's `\(literal:)`
- **Create** `Baseline/BaselineGenerator.swift` — top-level orchestration
- **Create** `Baseline/BaselineFixturePicker.swift` — selects "main + variants" per descriptor type
- **Create** `Baseline/Generators/<TypeName>BaselineGenerator.swift` — one per descriptor family (added incrementally per Phase 2 task)

### Sources/baseline-generator/ (NEW executable target)
- **Create** `main.swift` — ArgumentParser front, invokes `BaselineGenerator`

### Tests/MachOSwiftSectionTests/Fixtures/ (NEW)
- **Create** subdirectories mirroring `Sources/MachOSwiftSection/Models/`
- **Create** `<TypeName>Tests.swift` Suite files (added incrementally per Phase 2 task)
- **Create** `__Baseline__/<TypeName>Baseline.swift` (auto-generated; committed)
- **Create** `__Baseline__/AllFixtureSuites.swift` (auto-generated)
- **Create** `MachOSwiftSectionCoverageInvariantTests.swift` (Phase 3)
- **Create** `CoverageAllowlistEntries.swift` — concrete allowlist entries with reasons

### Modified Package.swift
- Add `baseline-generator` executable target with deps `[MachOTestingSupport, ArgumentParser]`
- Add `MachOTestingSupport` deps `[SwiftSyntax]` (for the scanner)

---

## Task 1: Test Infrastructure Foundation

**Files:**
- Modify: `Sources/MachOTestingSupport/MachOImageName.swift`
- Create: `Sources/MachOTestingSupport/FixtureLoadError.swift`
- Create: `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/FixtureLoadingProbeTests.swift` (smoke test only)

- [ ] **Step 1: Add `SymbolTestsCore` and `SymbolTests` cases to `MachOImageName`**

Read the current file, then append the two cases mirroring `MachOFileName`:

```swift
// Sources/MachOTestingSupport/MachOImageName.swift (existing file, append cases)
case SymbolTests = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTests.framework/Versions/A/SymbolTests"
case SymbolTestsCore = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore"
```

- [ ] **Step 2: Build to verify no break**

Run: `swift build 2>&1 | xcsift`
Expected: clean build.

- [ ] **Step 3: Write `FixtureLoadError`**

Create `Sources/MachOTestingSupport/FixtureLoadError.swift`:

```swift
import Foundation

package enum FixtureLoadError: Error, CustomStringConvertible {
    case fixtureFileMissing(path: String)
    case imageNotFoundAfterDlopen(path: String, dlerror: String?)

    package var description: String {
        switch self {
        case .fixtureFileMissing(let path):
            return """
            Fixture binary not found at \(path).
            Build it with:
              xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \\
                         -scheme SymbolTestsCore -configuration Release build
            """
        case .imageNotFoundAfterDlopen(let path, let dlerror):
            return """
            dlopen succeeded but MachOImage(named:) returned nil for \(path).
            dlerror: \(dlerror ?? "<none>")
            """
        }
    }
}
```

- [ ] **Step 4: Write `MachOSwiftSectionFixtureTests` base class**

Create `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift`:

```swift
import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOReading
import MachOResolving

@MainActor
package class MachOSwiftSectionFixtureTests: Sendable {
    package let machOFile: MachOFile
    package let machOImage: MachOImage

    package let fileContext: MachOContext<MachOFile>
    package let imageContext: MachOContext<MachOImage>
    package let inProcessContext: InProcessContext

    package class var fixtureFileName: MachOFileName  { .SymbolTestsCore }
    package class var fixtureImageName: MachOImageName { .SymbolTestsCore }
    package class var preferredArchitecture: CPUType { .arm64 }

    package init() async throws {
        // 1) Load MachO from disk.
        let file = try loadFromFile(named: Self.fixtureFileName)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try required(
                fatFile.machOFiles().first(where: { $0.header.cpuType == Self.preferredArchitecture })
                    ?? fatFile.machOFiles().first
            )
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // 2) Ensure fixture is dlopen'd into the test process so MachOImage(named:) succeeds.
        try Self.ensureFixtureLoaded()
        guard let image = MachOImage(named: Self.fixtureImageName) else {
            throw FixtureLoadError.imageNotFoundAfterDlopen(
                path: Self.fixtureImageName.rawValue,
                dlerror: Self.lastDlerror()
            )
        }
        self.machOImage = image

        // 3) Three ReadingContext instances over the same fixture.
        self.fileContext = MachOContext(machO: machOFile)
        self.imageContext = MachOContext(machO: machOImage)
        self.inProcessContext = InProcessContext()
    }

    private static let dlopenOnce: Void = {
        let absolute = resolveFixturePath(MachOImageName.SymbolTestsCore.rawValue)
        _ = absolute.withCString { dlopen($0, RTLD_LAZY) }
    }()

    private static func ensureFixtureLoaded() throws {
        _ = dlopenOnce
    }

    /// Resolve a relative MachOImageName path (rooted at the package-relative `../../Tests/...`
    /// convention) to an absolute filesystem path. Uses the same anchor strategy as
    /// `loadFromFile` for parity.
    private static func resolveFixturePath(_ relativePath: String) -> String {
        if relativePath.hasPrefix("/") { return relativePath }
        let anchor = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MachOTestingSupport/
            .deletingLastPathComponent()  // Sources/
        return anchor.appendingPathComponent(relativePath).standardizedFileURL.path
    }

    private static func lastDlerror() -> String? {
        guard let cString = dlerror() else { return nil }
        return String(cString: cString)
    }
}

extension MachOSwiftSectionFixtureTests {
    /// Run `body` against each (label, reader) pair, asserting all results equal the first.
    /// Returns the unique value. Fails fast with the label of the first mismatching reader.
    package func acrossAllReaders<T: Equatable>(
        file fileWork: () throws -> T,
        image imageWork: () throws -> T,
        inProcess inProcessWork: (() throws -> T)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> T {
        let fromFile = try fileWork()
        let fromImage = try imageWork()
        #expect(fromFile == fromImage, "MachOFile vs MachOImage diverged", sourceLocation: sourceLocation)
        if let inProcessWork {
            let fromInProcess = try inProcessWork()
            #expect(fromFile == fromInProcess, "MachOFile vs InProcess diverged", sourceLocation: sourceLocation)
        }
        return fromFile
    }

    /// Run `body` against each ReadingContext (file/image/inProcess), asserting all equal.
    package func acrossAllContexts<T: Equatable>(
        file fileWork: () throws -> T,
        image imageWork: () throws -> T,
        inProcess inProcessWork: (() throws -> T)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> T {
        let fromFileCtx = try fileWork()
        let fromImageCtx = try imageWork()
        #expect(fromFileCtx == fromImageCtx, "fileContext vs imageContext diverged", sourceLocation: sourceLocation)
        if let inProcessWork {
            let fromInProcessCtx = try inProcessWork()
            #expect(fromFileCtx == fromInProcessCtx, "fileContext vs inProcessContext diverged", sourceLocation: sourceLocation)
        }
        return fromFileCtx
    }
}
```

- [ ] **Step 5: Write a smoke test verifying the fixture loads from all three readers**

Create `Tests/MachOSwiftSectionTests/Fixtures/FixtureLoadingProbeTests.swift`:

```swift
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport

@Suite
final class FixtureLoadingProbeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func machOFileSwiftSectionParses() async throws {
        let typeContextDescriptors = try machOFile.swift.typeContextDescriptors
        #expect(!typeContextDescriptors.isEmpty, "fixture must contain at least one type")
    }

    @Test func machOImageSwiftSectionParses() async throws {
        let typeContextDescriptors = try machOImage.swift.typeContextDescriptors
        #expect(!typeContextDescriptors.isEmpty, "fixture image must contain at least one type")
    }

    @Test func threeReadersSeeSameTypeCount() async throws {
        let fileCount = try machOFile.swift.typeContextDescriptors.count
        let imageCount = try machOImage.swift.typeContextDescriptors.count
        #expect(fileCount == imageCount, "MachOFile and MachOImage disagree on type count")
    }
}
```

- [ ] **Step 6: Build and run smoke test**

Run: `swift build 2>&1 | xcsift`
Expected: clean build.

Run: `swift test --filter FixtureLoadingProbeTests 2>&1 | xcsift`
Expected: 3 tests pass.

If MachOImage count differs from MachOFile count, that itself is a finding worth investigating — but most likely they agree because both read the same `__swift5_types` section.

- [ ] **Step 7: Commit**

```bash
git add Sources/MachOTestingSupport/MachOImageName.swift \
        Sources/MachOTestingSupport/FixtureLoadError.swift \
        Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/FixtureLoadingProbeTests.swift
git commit -m "$(cat <<'EOF'
test(MachOTestingSupport): add MachOSwiftSectionFixtureTests base + dlopen fixture loader

Loads SymbolTestsCore.framework from disk, dlopens it once into the test
process, and exposes machOFile/machOImage plus three ReadingContext
instances (fileContext/imageContext/inProcessContext). Adds smoke probe
to verify all three readers see the fixture's swift5_types section.
EOF
)"
```

---

## Task 2: BaselineEmitter (hex helper) + SwiftSyntaxBuilder dep

**Files:**
- Modify: `Package.swift` — add `SwiftSyntaxBuilder` to `MachOTestingSupport` deps; declare `MachOTestingSupportTests` test target if it doesn't already exist
- Create: `Sources/MachOTestingSupport/Baseline/BaselineEmitter.swift`
- Create: `Tests/MachOTestingSupportTests/Baseline/BaselineEmitterTests.swift`

**Background.** Most ABI baseline data (strings, bools, decimal ints, arrays of strings, optionals) will be emitted via SwiftSyntaxBuilder's `\(literal:)` interpolation, which auto-escapes and parses-validates at generation time. The exception is **hex literals** — `\(literal: 0x10)` produces `16` (decimal), not `0x10`. We emit hex via `\(raw:)` and a small `BaselineEmitter` helper that returns the hex literal string. That helper, plus its hex-array variant, is the entirety of `BaselineEmitter`.

- [ ] **Step 1: Add `SwiftSyntaxBuilder` to `MachOTestingSupport` target deps**

Inspect `Package.swift`. The `MachOTestingSupport` target currently depends on `SwiftSyntax`/`SwiftParser` (added in Task 3). Add `SwiftSyntaxBuilder` alongside:

```swift
// In Package.swift, MachOTestingSupport target dependencies:
.product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
```

And in `extension Target.Dependency` near the other SwiftSyntax aliases:

```swift
static let SwiftSyntaxBuilder = Target.Dependency.product(
    name: "SwiftSyntaxBuilder",
    package: "swift-syntax"
)
```

(Note: Task 3 also adds `SwiftSyntax`/`SwiftParser` deps. If executing Task 2 before Task 3, add all three at once and Task 3 Step 1 becomes a no-op.)

- [ ] **Step 2: Confirm `MachOTestingSupportTests` test target exists in `Package.swift`**

If a `MachOTestingSupportTests` target is not present, add this declaration alongside the other testTargets (mirror `MachOSwiftSectionTests` style):

```swift
// Sources/Package.swift (extension Target, near other testTargets)
static let MachOTestingSupportTests = Target.testTarget(
    name: "MachOTestingSupportTests",
    dependencies: [
        .target(.MachOTestingSupport),
    ],
    swiftSettings: testSettings
)
```

And register it in the `targets:` array of the `Package(...)` declaration.

- [ ] **Step 3: Build to verify deps wire up**

Run: `swift package update && swift build 2>&1 | xcsift`
Expected: clean build.

- [ ] **Step 4: Write failing emitter test**

Create `Tests/MachOTestingSupportTests/Baseline/BaselineEmitterTests.swift`:

```swift
import Foundation
import Testing
@testable import MachOTestingSupport

@Suite
struct BaselineEmitterTests {
    @Test func emitsIntHex() {
        #expect(BaselineEmitter.hex(0x10) == "0x10")
    }

    @Test func emitsZeroHex() {
        #expect(BaselineEmitter.hex(0) == "0x0")
    }

    @Test func emitsUInt32Hex() {
        #expect(BaselineEmitter.hex(UInt32(0x40000051)) == "0x40000051")
    }

    @Test func emitsNegativeIntAsTwosComplementHex() {
        // Negative Int sign-extends to UInt64 representation.
        #expect(BaselineEmitter.hex(Int(-1)) == "0xffffffffffffffff")
    }

    @Test func emitsHexArray() {
        #expect(BaselineEmitter.hexArray([0x10, 0x18, 0x28]) == "[0x10, 0x18, 0x28]")
    }

    @Test func emitsEmptyHexArray() {
        #expect(BaselineEmitter.hexArray([Int]()) == "[]")
    }
}
```

- [ ] **Step 5: Run test to verify it fails**

Run: `swift test --filter BaselineEmitterTests 2>&1 | xcsift`
Expected: FAIL — `BaselineEmitter` not defined.

- [ ] **Step 6: Implement `BaselineEmitter`**

Create `Sources/MachOTestingSupport/Baseline/BaselineEmitter.swift`:

```swift
import Foundation

/// Tiny helper providing the few literal forms that SwiftSyntaxBuilder's
/// `\(literal:)` does NOT produce in the form we want for ABI baselines.
///
/// Specifically: integers via `\(literal:)` come out as decimal Swift literals,
/// but baseline files emit offsets/sizes/flags as hex (`0x...`) for parity with
/// `otool` / Hopper output. Use these helpers with `\(raw:)` in the
/// SwiftSyntaxBuilder source string.
///
/// For everything else — strings, bools, decimal ints, arrays of strings,
/// optionals — use `\(literal:)` directly; SwiftSyntaxBuilder handles escaping.
package enum BaselineEmitter {
    /// Emit `0x<lowercase-hex>` for any binary integer (sign-extends to UInt64).
    package static func hex<T: BinaryInteger>(_ value: T) -> String {
        let unsigned = UInt64(truncatingIfNeeded: value)
        return "0x\(String(unsigned, radix: 16))"
    }

    /// Emit `[0x..., 0x..., ...]` for an array of binary integers.
    package static func hexArray<T: BinaryInteger>(_ values: [T]) -> String {
        "[\(values.map(hex).joined(separator: ", "))]"
    }
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `swift test --filter BaselineEmitterTests 2>&1 | xcsift`
Expected: 6 tests pass.

- [ ] **Step 8: Commit**

```bash
git add Package.swift \
        Sources/MachOTestingSupport/Baseline/BaselineEmitter.swift \
        Tests/MachOTestingSupportTests/Baseline/BaselineEmitterTests.swift
git commit -m "$(cat <<'EOF'
test(MachOTestingSupport): add BaselineEmitter hex helper + SwiftSyntaxBuilder dep

Adds two-function helper (hex/hexArray) for emitting integer literals as
hex (`0x...`) for ABI baseline files. Strings/bools/decimal ints/arrays of
strings/optionals are emitted via SwiftSyntaxBuilder's `\(literal:)`
interpolation directly. Hex needs a helper because `\(literal: 0x10)` outputs
`16` (decimal). Wires SwiftSyntaxBuilder into MachOTestingSupport deps.
EOF
)"
```

---

## Task 3: PublicMemberScanner + Coverage Framework

**Files:**
- Create: `Sources/MachOTestingSupport/Coverage/MethodKey.swift`
- Create: `Sources/MachOTestingSupport/Coverage/FixtureSuite.swift`
- Create: `Sources/MachOTestingSupport/Coverage/CoverageAllowlist.swift`
- Create: `Sources/MachOTestingSupport/Coverage/PublicMemberScanner.swift`
- Modify: `Package.swift` — add SwiftSyntax dep to `MachOTestingSupport` target if not present
- Create: `Tests/MachOTestingSupportTests/Coverage/PublicMemberScannerTests.swift`
- Create: `Tests/MachOTestingSupportTests/Coverage/Fixtures/SampleSource.swift` — input fixture for scanner test

- [ ] **Step 1: Add SwiftSyntax to MachOTestingSupport target deps if missing**

Inspect `Package.swift` `MachOTestingSupport` target. If it doesn't already depend on `SwiftSyntax` and `SwiftParser`, add:

```swift
.product(.SwiftSyntax),
.product(.SwiftParser),
```

to the `dependencies:` array of the `MachOTestingSupport` target declaration.

- [ ] **Step 2: Build to verify deps wire up**

Run: `swift build 2>&1 | xcsift`
Expected: clean build.

- [ ] **Step 3: Create `MethodKey`**

`Sources/MachOTestingSupport/Coverage/MethodKey.swift`:

```swift
import Foundation

package struct MethodKey: Hashable, Comparable, CustomStringConvertible {
    package let typeName: String
    package let memberName: String

    package init(typeName: String, memberName: String) {
        self.typeName = typeName
        self.memberName = memberName
    }

    package static func < (lhs: MethodKey, rhs: MethodKey) -> Bool {
        if lhs.typeName != rhs.typeName { return lhs.typeName < rhs.typeName }
        return lhs.memberName < rhs.memberName
    }

    package var description: String {
        "\(typeName).\(memberName)"
    }
}
```

- [ ] **Step 4: Create `FixtureSuite` protocol**

`Sources/MachOTestingSupport/Coverage/FixtureSuite.swift`:

```swift
import Foundation

/// Conformance contract for fixture-based test suites participating in coverage tracking.
///
/// Each Suite type provides:
/// - `testedTypeName`: the source-code Type whose public members the Suite covers
///   (e.g. "StructDescriptor"). Must match the type name exactly as it appears in
///   `Sources/MachOSwiftSection/Models/`.
/// - `registeredTestMethodNames`: the member names covered by `@Test` methods in this Suite.
///   For each entry "foo", the Coverage Invariant test expects a public member
///   `<testedTypeName>.foo` (any overload group) to exist in the source.
package protocol FixtureSuite {
    static var testedTypeName: String { get }
    static var registeredTestMethodNames: Set<String> { get }
}
```

- [ ] **Step 5: Create `CoverageAllowlist`**

`Sources/MachOTestingSupport/Coverage/CoverageAllowlist.swift`:

```swift
import Foundation

/// A single entry exempting one (typeName, memberName) pair from coverage requirements.
/// Each entry MUST carry a human-readable reason.
package struct CoverageAllowlistEntry: Hashable, CustomStringConvertible {
    package let key: MethodKey
    package let reason: String

    package init(typeName: String, memberName: String, reason: String) {
        self.key = MethodKey(typeName: typeName, memberName: memberName)
        self.reason = reason
    }

    package var description: String {
        "\(key)  // \(reason)"
    }
}
```

- [ ] **Step 6: Create scanner skeleton (no SwiftSyntax integration yet)**

`Sources/MachOTestingSupport/Coverage/PublicMemberScanner.swift`:

```swift
import Foundation
import SwiftSyntax
import SwiftParser

/// Scans a directory of Swift source files and extracts the set of public/open
/// `func`, `var`, and `init` members, keyed by `(typeName, memberName)`.
///
/// Skipped:
/// - `internal`, `private`, `fileprivate` declarations
/// - `@_spi(...)` declarations (treated as non-public)
/// - members on types whose name ends with `Layout` (covered by LayoutTests)
/// - `init(layout:offset:)` synthesized by `@MemberwiseInit`
/// - extensions on enums whose name ends with `Kind`/`Flags` and similar pure-data utilities
///   (handled via allowlist if they slip through)
package struct PublicMemberScanner {
    package let sourceRoot: URL

    package init(sourceRoot: URL) {
        self.sourceRoot = sourceRoot
    }

    package func scan(applyingAllowlist allowlist: Set<MethodKey> = []) throws -> Set<MethodKey> {
        let files = try collectSwiftFiles(under: sourceRoot)
        var result: Set<MethodKey> = []
        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let visitor = PublicMemberVisitor(viewMode: .sourceAccurate)
            visitor.walk(tree)
            for key in visitor.collected {
                if allowlist.contains(key) { continue }
                result.insert(key)
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

private final class PublicMemberVisitor: SyntaxVisitor {
    private(set) var collected: [MethodKey] = []
    private var typeStack: [String] = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Push the extended type as the current scope.
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        collected.append(MethodKey(typeName: typeName, memberName: node.name.text))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                collected.append(MethodKey(typeName: typeName, memberName: pattern.identifier.text))
            }
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        if isMemberwiseSynthesizedInit(node) { return .skipChildren }
        let signature = node.signature.parameterClause.parameters.map { $0.firstName.text }.joined(separator: ":")
        let memberName = signature.isEmpty ? "init" : "init(\(signature):)"
        collected.append(MethodKey(typeName: typeName, memberName: memberName))
        return .skipChildren
    }

    private func currentTypeName() -> String? {
        typeStack.last
    }

    private func shouldSkip(typeName: String) -> Bool {
        if typeName.hasSuffix("Layout") { return true }
        return false
    }

    private func isPublicLike(_ modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> Bool {
        // Reject if any @_spi attribute is present.
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "_spi" {
                return false
            }
        }
        // Accept only if `public` or `open` modifier exists.
        for modifier in modifiers {
            let name = modifier.name.text
            if name == "public" || name == "open" { return true }
        }
        return false
    }

    private func isMemberwiseSynthesizedInit(_ node: InitializerDeclSyntax) -> Bool {
        // Detect explicit synthesis when authoring class declares @MemberwiseInit;
        // the macro expands to init(layout: ..., offset: ...).
        let names = node.signature.parameterClause.parameters.map { $0.firstName.text }
        return names == ["layout", "offset"] || names == ["offset", "layout"]
    }
}
```

- [ ] **Step 7: Write a sample-source fixture for the scanner test**

Create `Tests/MachOTestingSupportTests/Coverage/Fixtures/SampleSource.swift`:

```swift
// Sample source consumed by PublicMemberScannerTests via on-disk reads.
// Not actually compiled — file extension must remain `.swift` but content is
// read from disk by the test, so it'll go through SwiftSyntax parser, not the
// build's Swift compiler. Scope matches typical Models/ patterns.

public struct SampleDescriptor {
    public func name() -> String { "" }
    public var nameOptional: String? { nil }
    public init(layout: SampleLayout, offset: Int) {}
    public init(custom: Int) {}
    internal func internalHelper() {}
    private var hidden: Int { 0 }
}

extension SampleDescriptor {
    public func sectionedFoo() -> Int { 0 }
}

@_spi(Internals)
extension SampleDescriptor {
    public func spiHidden() -> Int { 0 }
}

public struct SampleLayout {
    public static func offset(of field: PartialKeyPath<SampleLayout>) -> Int { 0 }
}
```

Note: this file must be excluded from the build target. Place it under
`Tests/MachOTestingSupportTests/Coverage/Fixtures/` and ensure the test target
doesn't compile it (Xcode/SPM will compile any `.swift` under `Tests/`, so
prefix the file name with `_` would help — but cleaner is to rename the
extension to something other than `.swift`). Use `.swiftsample` and read
explicitly:

Actually rename to `SampleSource.swift.txt` and update the test path. The
scanner reads files by URL anyway.

Re-create `Tests/MachOTestingSupportTests/Coverage/Fixtures/SampleSource.swift.txt` with the content above.

- [ ] **Step 8: Write the failing scanner test**

Create `Tests/MachOTestingSupportTests/Coverage/PublicMemberScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import MachOTestingSupport

@Suite
struct PublicMemberScannerTests {
    private var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Coverage/
            .appendingPathComponent("Fixtures")
    }

    /// Scanner reads `.swift` files in the directory. We renamed our test source to
    /// `.swift.txt` to avoid build inclusion, then rename a tmp copy to `.swift` for the scan.
    private func makeScanRoot() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let source = try String(contentsOf: fixtureRoot.appendingPathComponent("SampleSource.swift.txt"))
        let dest = tempDir.appendingPathComponent("SampleSource.swift")
        try source.write(to: dest, atomically: true, encoding: .utf8)
        return tempDir
    }

    @Test func collectsPublicMembers() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "name")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "nameOptional")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "init(custom:)")))
        #expect(result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "sectionedFoo")))
    }

    @Test func skipsInternalAndPrivate() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "internalHelper")))
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "hidden")))
    }

    @Test func skipsSPI() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "spiHidden")))
    }

    @Test func skipsMemberwiseInit() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        // The 2-arg `init(layout:offset:)` should be filtered as MemberwiseInit synthesized.
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "init(layout:offset:)")))
    }

    @Test func skipsLayoutTypes() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let result = try scanner.scan()

        #expect(!result.contains(MethodKey(typeName: "SampleLayout", memberName: "offset")))
    }

    @Test func appliesAllowlist() throws {
        let root = try makeScanRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PublicMemberScanner(sourceRoot: root)
        let allowlist: Set<MethodKey> = [MethodKey(typeName: "SampleDescriptor", memberName: "name")]
        let result = try scanner.scan(applyingAllowlist: allowlist)
        #expect(!result.contains(MethodKey(typeName: "SampleDescriptor", memberName: "name")))
    }
}
```

- [ ] **Step 9: Run scanner test to verify it fails**

Run: `swift test --filter PublicMemberScannerTests 2>&1 | xcsift`
Expected: at least the path-fixture-not-found assertion or compile error indicating fixture is missing — fix by creating the fixture.

Then re-run; expected: scanner tests pass.

- [ ] **Step 10: Run all coverage tests + emitter tests**

Run: `swift test --filter MachOTestingSupportTests 2>&1 | xcsift`
Expected: all pass.

- [ ] **Step 11: Commit**

```bash
git add Sources/MachOTestingSupport/Coverage/ \
        Tests/MachOTestingSupportTests/Coverage/ \
        Package.swift
git commit -m "$(cat <<'EOF'
test(MachOTestingSupport): add coverage framework — MethodKey, FixtureSuite, scanner

PublicMemberScanner walks SwiftSyntax to extract public/open func/var/init from a
source root, keyed by (typeName, memberName). Skips internal/private/fileprivate,
@_spi(...), Layout-suffixed types, and @MemberwiseInit-synthesized
init(layout:offset:). FixtureSuite protocol exposes testedTypeName +
registeredTestMethodNames for the Coverage Invariant test wiring up later.
EOF
)"
```

---

## Task 4: Reference Suite — `Type/Struct/` end-to-end

Pilot the full pattern on `Sources/MachOSwiftSection/Models/Type/Struct/` (5 files: `Struct.swift`, `StructDescriptor.swift`, `StructDescriptorLayout.swift`, `StructMetadata.swift`, `StructMetadataLayout.swift`, `StructMetadataProtocol.swift`). `*Layout.swift` files are scanner-skipped; the 4 testable files yield ~3-5 Suites total.

This task delivers the *first* Suite and its corresponding sub-generator end-to-end, locking in the pattern reused by Tasks 5-15.

**Files:**
- Create: `Sources/MachOTestingSupport/Baseline/Generators/StructDescriptorBaselineGenerator.swift`
- Create: `Sources/MachOTestingSupport/Baseline/BaselineFixturePicker.swift` (skeleton)
- Create: `Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructDescriptorTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructMetadataTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructMetadataProtocolTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift` (auto-generated)
- (and matching baseline files for Struct, StructMetadata, StructMetadataProtocol)

- [ ] **Step 1: Inventory `Type/Struct/` public surface**

Run from the repo root to enumerate public methods (cross-check with the scanner once it lands later in this Task):

```bash
rg -n "^    public (func|var|init)" Sources/MachOSwiftSection/Models/Type/Struct/ -t swift
```

Expected output: list of public funcs/vars/inits across `Struct.swift`, `StructDescriptor.swift`, `StructMetadata.swift`, `StructMetadataProtocol.swift`. Save the list (paste into a scratch buffer) — this is the master list of `@Test func`s you must produce.

- [ ] **Step 2: Pick the fixture targets**

In `SymbolTestsCore/Structs.swift` we have `public struct Structs.StructTest`. In `SymbolTestsCore/GenericFieldLayout.swift` we have `public struct GenericFieldLayout.GenericStructNonRequirement<A>`. We'll use:

| variant key | fixture target | rationale |
|---|---|---|
| `structTest` | `SymbolTestsCore.Structs.StructTest` | concrete (no generics) |
| `genericStructNonRequirement` | `SymbolTestsCore.GenericFieldLayout.GenericStructNonRequirement<A>` | generic struct, exercises generic context paths |

- [ ] **Step 3: Write `BaselineFixturePicker` skeleton**

`Sources/MachOTestingSupport/Baseline/BaselineFixturePicker.swift`:

```swift
import Foundation
import MachOFoundation
@testable import MachOSwiftSection

/// Centralizes the "pick (main + variants) fixture entities for each descriptor type"
/// logic, ensuring Suites and their corresponding BaselineGenerators look at the
/// same set of entities.
package enum BaselineFixturePicker {
    package static func struct_StructTest(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: {
                try $0.name(in: machO) == "StructTest"
                    && (try? $0.parent(in: machO)?.dumpName(using: .default, in: machO).string).flatMap { $0 == "Structs" } == true
            })
        )
    }

    package static func struct_GenericStructNonRequirement(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> StructDescriptor {
        try required(
            try machO.swift.typeContextDescriptors.compactMap(\.struct).first(where: {
                try $0.name(in: machO) == "GenericStructNonRequirement"
            })
        )
    }
}
```

If `dumpName` is not available at this layer, use `parent(in:)` chasing to walk up the context chain; the simplest robust check is by exact `name(in:)` since both `StructTest` and `GenericStructNonRequirement` are unique names within the fixture.

- [ ] **Step 4: Run baseline-generator manually for StructDescriptor — first cut**

We don't have the executable target yet (Task 17). Use a temporary `@Test`-shaped shim or write a one-shot Swift script that:

1. Loads `SymbolTestsCore.framework` MachOFile (via the already-existing `loadFromFile`).
2. Picks the two struct variants via `BaselineFixturePicker`.
3. For each public member of `StructDescriptor`, reads the value through the `MachOFile` reader.
4. Emits the Swift literal data into `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift`.

Sketch script (commit to `Sources/baseline-generator/main.swift` as a stub Task 17 will polish):

```swift
import Foundation
import ArgumentParser
import MachOTestingSupport

// Phase-1 stub: invokes BaselineGenerator.generateAll(); proper CLI in Task 17.
@main
struct BaselineGeneratorMain: AsyncParsableCommand {
    func run() async throws {
        try await BaselineGenerator.generateAll(
            outputDirectory: URL(fileURLWithPath: "Tests/MachOSwiftSectionTests/Fixtures/__Baseline__")
        )
    }
}
```

(`BaselineGenerator.generateAll()` will start with just StructDescriptor and grow per-task.)

- [ ] **Step 5: Implement `BaselineGenerator` (dispatcher pattern from the start) + `StructDescriptorBaselineGenerator`**

`Sources/MachOTestingSupport/Baseline/BaselineGenerator.swift`:

```swift
import Foundation
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection

package enum BaselineGenerator {
    package static func generateAll(outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let machOFile = try loadFixtureMachOFile()
        // Add one call per Suite as it lands in Tasks 5-15. Keep deterministic ordering.
        try dispatchSuite("StructDescriptor", in: machOFile, outputDirectory: outputDirectory)
    }

    package static func generate(suite name: String, outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let machOFile = try loadFixtureMachOFile()
        try dispatchSuite(name, in: machOFile, outputDirectory: outputDirectory)
    }

    private static func dispatchSuite(_ name: String, in machOFile: MachOFile, outputDirectory: URL) throws {
        switch name {
        case "StructDescriptor":
            try StructDescriptorBaselineGenerator.generate(in: machOFile, outputDirectory: outputDirectory)
        // Add cases here as Tasks 5-15 land.
        default:
            throw BaselineGeneratorError.unknownSuite(name)
        }
    }

    private static func loadFixtureMachOFile() throws -> MachOFile {
        let file = try loadFromFile(named: .SymbolTestsCore)
        switch file {
        case .fat(let fat):
            return try required(
                fat.machOFiles().first(where: { $0.header.cpuType == .arm64 })
                    ?? fat.machOFiles().first
            )
        case .machO(let machO):
            return machO
        @unknown default:
            fatalError()
        }
    }
}

package enum BaselineGeneratorError: Error, CustomStringConvertible {
    case unknownSuite(String)
    package var description: String {
        switch self {
        case .unknownSuite(let name):
            return "Unknown suite: \(name). Use --help for the list of valid suites."
        }
    }
}
```

Now Tasks 5-15 each add **one line** to `dispatchSuite` and **one line** to `generateAll`, plus their sub-generator file.

`Sources/MachOTestingSupport/Baseline/Generators/StructDescriptorBaselineGenerator.swift`:

```swift
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

package enum StructDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let toolchain = "Swift 6.2"
        let date = ISO8601DateFormatter().string(from: Date())

        // Pick fixture entities.
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        let genericStruct = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO)

        // Read ABI fields per variant. Each helper returns the precise Swift
        // initializer expression as a SourceFileSyntax-compatible string.
        let structTestExpr = try emitEntryExpr(for: structTest, in: machO)
        let genericStructExpr = try emitEntryExpr(for: genericStruct, in: machO)

        let registered = memberNames().sorted()

        // SwiftSyntaxBuilder string-interpolation form. SwiftSyntax parses this
        // string at construction time — any malformed Swift fails immediately.
        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift run baseline-generator --suite StructDescriptor
        // Source fixture: SymbolTestsCore.framework
        // Toolchain: \(toolchain)
        // Generated: \(date)
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let name: String
                let numberOfFields: Int
                let fieldNames: [String]
                let fieldOffsets: [Int]
                let isGeneric: Bool
                let flagsRawValue: UInt32
                // ... extend per StructDescriptor public member
            }

            static let structTest = \(raw: structTestExpr)

            static let genericStructNonRequirement = \(raw: genericStructExpr)
        }
        """

        // `.formatted()` normalizes indentation/whitespace so re-runs produce
        // byte-identical output (idempotency; verified in Task 4 Step 12).
        let formatted = file.formatted().description + "\n"

        let outputURL = outputDirectory.appendingPathComponent("StructDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    /// Build the `Entry(...)` initializer expression as a Swift source fragment.
    /// Plain values use `\(literal:)`; hex values use `\(raw:)` + `BaselineEmitter.hex`.
    private static func emitEntryExpr(
        for descriptor: StructDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let name = try descriptor.name(in: machO)
        let numFields = Int(descriptor.layout.numFields)
        let fields = try descriptor.fields(in: machO)
        let fieldNames = try fields.records.map { try $0.fieldName(in: machO) }
        let fieldOffsets = try fields.records.map { try $0.fieldOffset(in: machO) }
        let isGeneric = descriptor.layout.flags.isGeneric
        let flagsRaw = descriptor.layout.flags.rawValue

        // We build this expression as an ExprSyntax to get string-interpolation
        // ergonomics, then return its description (the resulting source fragment
        // is later embedded into the SourceFileSyntax above).
        let expr: ExprSyntax = """
        Entry(
            name: \(literal: "SymbolTestsCore." + name),
            numberOfFields: \(literal: numFields),
            fieldNames: \(literal: fieldNames),
            fieldOffsets: \(raw: BaselineEmitter.hexArray(fieldOffsets)),
            isGeneric: \(literal: isGeneric),
            flagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
        )
        """
        return expr.description
    }

    /// Hand-curated member name list mirroring StructDescriptor public surface.
    /// Each entry must correspond to a `@Test func <name>` in
    /// StructDescriptorTests.swift. The Coverage Invariant test (Task 16)
    /// verifies this matches the static scan output.
    private static func memberNames() -> [String] {
        [
            "name",
            "fields",
            "genericContext",
            "numberOfFields",
            "fieldOffsetVectorOffset",
            // ... extend per StructDescriptor public surface inventoried in Step 1
        ]
    }
}
```

(Adapt method calls to actual `StructDescriptor` public API — Step 1's inventory is the source of truth.)

**SwiftSyntaxBuilder primer:**
- `\(literal: x)` — `x` is `ExpressibleByLiteralSyntax`-conforming (`String`, `Int`, `Bool`, `[String]`, `Optional`, etc.). Output is a properly escaped/formatted Swift literal token. SwiftSyntax parses + validates at construction time.
- `\(raw: string)` — inserts `string` as raw Swift source. Use when `\(literal:)` doesn't apply (e.g. hex literals, pre-built expressions).
- `SourceFileSyntax`/`ExprSyntax` accept multi-line string literals and parse them; malformed Swift throws at construction site.
- `.formatted()` returns a copy with normalized trivia (indentation, whitespace, newlines).

- [ ] **Step 6: Add `baseline-generator` executable target stub to Package.swift**

Add to `Package.swift` `extension Target`:

```swift
static let baseline_generator = Target.executableTarget(
    name: "baseline-generator",
    dependencies: [
        .target(.MachOTestingSupport),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ],
    swiftSettings: testSettings
)
```

Add to the `Package(...)` `targets:` array:

```swift
.baseline_generator,
```

Build:

Run: `swift build 2>&1 | xcsift`
Expected: clean build.

- [ ] **Step 7: Run baseline-generator to produce StructDescriptorBaseline.swift**

```bash
swift run baseline-generator
```

Expected: `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift` is created. Inspect it visually:

```bash
cat Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift
```

Confirm names/offsets look plausible. If a value looks suspicious (e.g. `numberOfFields: 0`, `fieldOffsets: []`), recheck `BaselineFixturePicker` — likely picked wrong type.

Note: SwiftSyntax's `.formatted()` normalizes whitespace, so the actual layout might differ slightly from the source string template — that's expected and desirable (idempotent re-runs produce byte-identical output).

If `swift run baseline-generator` itself crashes with a SwiftSyntax parse error, the source string template has malformed Swift; SwiftSyntax catches this at construction time so the message will point at the offending line.

- [ ] **Step 8: Write `StructDescriptorTests` Suite using the baseline**

`Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/StructDescriptorTests.swift`:

```swift
import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

@Suite
final class StructDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "StructDescriptor"
    static var registeredTestMethodNames: Set<String> {
        StructDescriptorBaseline.registeredTestMethodNames
    }

    @Test func name() async throws {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllReaders(
            file: { try fileSubject.name(in: machOFile) },
            image: { try imageSubject.name(in: machOImage) },
            inProcess: { try imageSubject.asPointerWrapper(in: machOImage).name() }
        )
        _ = try acrossAllContexts(
            file: { try fileSubject.name(in: fileContext) },
            image: { try imageSubject.name(in: imageContext) }
        )

        #expect("SymbolTestsCore." + result == StructDescriptorBaseline.structTest.name)
    }

    @Test func numberOfFields() async throws {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let result = try acrossAllReaders(
            file: { fileSubject.layout.numFields },
            image: { imageSubject.layout.numFields }
        )

        #expect(Int(result) == StructDescriptorBaseline.structTest.numberOfFields)
    }

    @Test func fields() async throws {
        let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileFieldNames = try fileSubject.fields(in: machOFile).records.map { try $0.fieldName(in: machOFile) }
        let imageFieldNames = try imageSubject.fields(in: machOImage).records.map { try $0.fieldName(in: machOImage) }
        let inProcessFieldNames = try imageSubject.asPointerWrapper(in: machOImage).fields().records.map { try $0.fieldName() }

        #expect(fileFieldNames == imageFieldNames)
        #expect(fileFieldNames == inProcessFieldNames)
        #expect(fileFieldNames == StructDescriptorBaseline.structTest.fieldNames)

        let fileFieldOffsets = try fileSubject.fields(in: machOFile).records.map { try $0.fieldOffset(in: machOFile) }
        #expect(fileFieldOffsets == StructDescriptorBaseline.structTest.fieldOffsets)
    }

    // ... one @Test per entry in StructDescriptorBaseline.registeredTestMethodNames
}
```

Repeat the pattern for every entry in `registeredTestMethodNames`. The body of each `@Test` follows the template:

```swift
@Test func <memberName>() async throws {
    let fileSubject = try BaselineFixturePicker.struct_StructTest(in: machOFile)
    let imageSubject = try BaselineFixturePicker.struct_StructTest(in: machOImage)
    // 1) Cross-reader equality (omit inProcess block if no InProcess overload exists)
    let result = try acrossAllReaders(
        file: { try fileSubject.<memberName>(in: machOFile) },
        image: { try imageSubject.<memberName>(in: machOImage) },
        inProcess: { try imageSubject.asPointerWrapper(in: machOImage).<memberName>() }
    )
    // 2) Baseline literal
    #expect(<projection>(result) == StructDescriptorBaseline.structTest.<memberName>)
}
```

- [ ] **Step 9: Run StructDescriptorTests**

Run: `swift test --filter StructDescriptorTests 2>&1 | xcsift`
Expected: all tests pass. If a test fails:

- **mismatch with baseline**: investigate whether the baseline value or the reader is wrong. If the baseline is wrong (generator bug), fix generator and rerun `swift run baseline-generator`. If the reader is wrong, fix the reader.
- **cross-reader mismatch**: a real bug in one of the three readers — investigate which one disagrees.

- [ ] **Step 10: Repeat Steps 5-9 for `Struct`, `StructMetadata`, `StructMetadataProtocol`**

Apply the same pattern to the other 3 testable Type/Struct/ files. For each:

1. Inventory public members (`rg "^    public (func|var|init)" Sources/MachOSwiftSection/Models/Type/Struct/<File>.swift -t swift`).
2. Add to `BaselineFixturePicker` if needed (e.g. `struct_StructTest_metadata` etc.).
3. Add a sub-generator under `Sources/MachOTestingSupport/Baseline/Generators/`.
4. Wire the sub-generator call into `BaselineGenerator.generateAll()`.
5. Run `swift run baseline-generator`; visually inspect the new baseline file.
6. Write the corresponding `<TypeName>Tests.swift` Suite, one `@Test` per registered member name.
7. Run `swift test --filter <TypeName>Tests`.

For `StructMetadata`, fixture targets are picked by calling `metadataAccessorFunction()` on the descriptor in MachOImage and resolving — this only works for `MachOImage`, so the cross-reader equality block omits InProcess and treats `imageContext` differently. Document the asymmetry in the Suite comment.

- [ ] **Step 11: Run all Type/Struct tests**

Run: `swift test --filter "Type/Struct" 2>&1 | xcsift`

Expected: all 4 (or however many) Suite files pass.

- [ ] **Step 12: Confirm baseline-generator is idempotent**

Run: `swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/`

Expected: no modified files. If diffs appear, fix the generator (likely a non-deterministic field iteration order — sort).

- [ ] **Step 13: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/ \
        Sources/baseline-generator/ \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Struct/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructMetadataBaseline.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructMetadataProtocolBaseline.swift \
        Package.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): add fixture-based Suite + baseline for Type/Struct

Reference implementation locking the pattern reused by remaining Models/
subdirectories: per-file BaselineGenerator (MachOFile path) writes a literal
__Baseline__/<File>Baseline.swift, and per-file Tests Suite asserts both
cross-reader equality (file/image/inProcess + ReadingContext variants) and
baseline literal equality. Picks Structs.StructTest + GenericStructNonRequirement
as fixture variants.
EOF
)"
```

---

## Tasks 5–15: Per-Subdirectory Suite Migration

Each task in this phase follows the exact same shape as Task 4 Steps 1-13, applied to a different `Models/` subdirectory. The deliverable per task is:

1. **Inventory**: `rg "^    public (func|var|init)" Sources/MachOSwiftSection/Models/<dir>/ -t swift` — produces the list of `@Test func`s required.
2. **Picker entries**: extend `BaselineFixturePicker` with `<dir>_<variantKey>` static methods.
3. **Sub-generator(s)**: under `Sources/MachOTestingSupport/Baseline/Generators/`, one per testable file.
4. **Wire into `BaselineGenerator`**: add a `case "<SuiteName>":` to `dispatchSuite(_:in:outputDirectory:)` calling the new sub-generator, AND a matching `try dispatchSuite("<SuiteName>", ...)` line in `generateAll(outputDirectory:)`. Both edits are required so `swift run baseline-generator` and `swift run baseline-generator --suite <Name>` both produce the new baseline.
5. **Run generator, eyeball diff**: `swift run baseline-generator && git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/`.
6. **Suite(s)**: under `Tests/MachOSwiftSectionTests/Fixtures/<dir>/`, one Suite per testable file, conforming to `MachOSwiftSectionFixtureTests` and `FixtureSuite`.
7. **`@Test` per registered member**: full cross-reader equality + baseline literal block per Task 4 Step 8 template.
8. **Run + commit** per Task 4 Steps 11-13.

If a `Models/<dir>/<File>.swift` only declares enums/flags/protocols/layouts with no public func/var/init that needs MachO state, skip it; the scanner will not produce expected entries either.

If `BaselineFixturePicker` cannot find a fixture entity for a given variant — log it, add a `CoverageAllowlistEntry` to `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift` (created in Task 16) with reason `needs fixture extension`, and proceed.

The fixture variants chosen per task are documented inline below.

### Task 5: `Anonymous/`, `Module/`, `Extension/`

**Files (testable):**
- `Anonymous/AnonymousContext.swift`, `AnonymousContextDescriptor.swift`, `AnonymousContextDescriptorProtocol.swift`, `AnonymousContextDescriptorFlags.swift`
- `Module/ModuleContext.swift`, `ModuleContextDescriptor.swift`, `ModuleContextDescriptorProtocol.swift`
- `Extension/ExtensionContext.swift`, `ExtensionContextDescriptor.swift`, `ExtensionContextDescriptorProtocol.swift`

**Fixture variants:**
- `Anonymous`: anonymous context arises from generic param scopes — pick from any generic struct's parent chain (e.g. `GenericFieldLayout.GenericStructNonRequirement`).
- `Module`: pick the `SymbolTestsCore` module context itself (from any descriptor's parent chain).
- `Extension`: pick the extension on `Structs.StructTest` for `Protocols.ProtocolWitnessTableTest` (in `SymbolTestsCore/Structs.swift`).

- [ ] **Step 1: Apply Task 4 Steps 1-13 to Anonymous/**

For each file in `Models/Anonymous/`:
- Inventory public members.
- Extend `BaselineFixturePicker` with `anonymous_*` accessors.
- Add `Anonymous*BaselineGenerator.swift` sub-generators.
- Wire into `BaselineGenerator`: add `case "<SuiteName>"` to `dispatchSuite` + matching call in `generateAll`.
- Run `swift run baseline-generator`; verify baselines look reasonable.
- Write `Anonymous*Tests.swift` Suites under `Tests/MachOSwiftSectionTests/Fixtures/Anonymous/`.
- `swift test --filter Anonymous`.

- [ ] **Step 2: Apply Task 4 Steps 1-13 to Module/**

Same as Step 1, scoped to `Models/Module/`.

- [ ] **Step 3: Apply Task 4 Steps 1-13 to Extension/**

Same as Step 1, scoped to `Models/Extension/`.

- [ ] **Step 4: Confirm idempotence + run all three sub-Suite groups**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Anonymous|Module|Extension" 2>&1 | xcsift
```

Expected: no baseline diffs, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/ \
        Tests/MachOSwiftSectionTests/Fixtures/Anonymous/ \
        Tests/MachOSwiftSectionTests/Fixtures/Module/ \
        Tests/MachOSwiftSectionTests/Fixtures/Extension/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): add fixture-based Suites for Anonymous/Module/Extension

Cover Anonymous/Module/Extension context wrappers and descriptors via
SymbolTestsCore fixture: anonymous (generic param scopes), module
(SymbolTestsCore module context), extension (Structs.StructTest extension on
Protocols.ProtocolWitnessTableTest). Each public member gets a @Test with
cross-reader equality + baseline literal.
EOF
)"
```

### Task 6: `ContextDescriptor/`

**Files (testable):**
- `ContextDescriptor.swift`, `ContextDescriptorProtocol.swift`, `ContextDescriptorWrapper.swift`, `ContextProtocol.swift`, `ContextWrapper.swift`, `NamedContextDescriptorProtocol.swift`

(Skip: `*Layout.swift`, `*Flags.swift`, `*Kind.swift`, `KindSpecificFlags.swift` — pure data types.)

**Fixture variants:** Use `Structs.StructTest` ContextDescriptor for testing flags/parent/name; use `SymbolTestsCore` module context for `ContextWrapper.parent`/`forContextDescriptorWrapper`.

- [ ] **Step 1: Apply Task 4 pattern to `ContextDescriptor/`**

Mirror Task 5 substeps. For `ContextDescriptorWrapper` and `ContextWrapper`, the fixture variants need to span `class`/`struct`/`enum`/`protocol`/`extension`/`anonymous`/`module` cases — pick one per ContextDescriptorKind.

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "ContextDescriptor" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/ContextDescriptor*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/ContextDescriptor/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ContextDescriptor*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Context*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for ContextDescriptor/"
```

### Task 7: `Type/Class/` (incl. `Method/`, `Metadata/`, `Resilient/`)

**Files (testable):** `Class.swift`, `ClassDescriptor.swift`, `ClassFlags.swift` (only public funcs/vars), `Method/MethodDescriptor.swift`, `Method/MethodOverrideDescriptor.swift`, `Method/MethodDefaultOverrideDescriptor.swift`, `Method/MethodDescriptorWrapper.swift`, `Method/VTableDescriptorHeader.swift`, `Method/OverrideTableHeader.swift`, `Method/MethodDefaultOverrideTableHeader.swift`, `Method/MethodImplementationPointer.swift`, `Metadata/AnyClassMetadata/AnyClassMetadata.swift`, `Metadata/AnyClassMetadata/AnyClassMetadataProtocol.swift`, `Metadata/AnyClassMetadataObjCInterop/AnyClassMetadataObjCInterop.swift`, `Metadata/AnyClassMetadataObjCInterop/AnyClassMetadataObjCInteropProtocol.swift`, `Metadata/Bounds/ClassMetadataBounds.swift`, `Metadata/Bounds/ClassMetadataBoundsProtocol.swift`, `Metadata/Bounds/StoredClassMetadataBounds.swift`, `Metadata/ClassMetadata/ClassMetadata.swift`, `Metadata/ClassMetadata/ClassMetadataProtocol.swift`, `Metadata/ClassMetadataObjCInterop/ClassMetadataObjCInterop.swift`, `Metadata/ClassMetadataObjCInterop/ClassMetadataObjCInteropProtocol.swift`, `Metadata/FinalClassMetadataProtocol.swift`, `Metadata/ObjCClassWrapperMetadata.swift`, `Resilient/ResilientSuperclass.swift`, `Resilient/ObjCResilientClassStubInfo.swift`

**Fixture variants:**
- Plain class: `Classes.SimpleClassTest` (or whatever exists in `SymbolTestsCore/Classes.swift`).
- Diamond: pick from `DiamondInheritance.swift`.
- ObjC interop: pick from `Classes.swift` for an `NSObject`-derived class.
- Generic class: pick from `ClassBoundGenerics.swift`.

- [ ] **Step 1: Apply Task 4 pattern to each file under `Models/Type/Class/`**

Many files (~25 testable). Group sub-generators under `Sources/MachOTestingSupport/Baseline/Generators/Class/`. Suites under `Tests/MachOSwiftSectionTests/Fixtures/Type/Class/`.

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Type/Class" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Class/ \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Class/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Class*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AnyClassMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Method*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/VTable*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Resilient*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Override*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StoredClass*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ObjCClass*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ObjCResilient*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/FinalClass*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Type/Class/"
```

### Task 8: `Type/Enum/`

**Files (testable):** `Enum.swift`, `EnumDescriptor.swift`, `EnumFunctions.swift` (if it has public APIs), `MultiPayloadEnumDescriptor.swift`, `Metadata/EnumMetadata.swift`, `Metadata/EnumMetadataProtocol.swift`

**Fixture variants:**
- No-payload: from `Enums.swift`.
- Single payload: from `Enums.swift`.
- Multi-payload: from `Enums.swift` (the test types in `MetadataAccessorTests.swift` already document these — adapt names).

- [ ] **Step 1: Apply Task 4 pattern to `Models/Type/Enum/`**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Type/Enum" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Enum/ \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Enum/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Enum*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/MultiPayload*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Type/Enum/"
```

### Task 9: `Type/` root files

**Files (testable):** `TypeContextDescriptor.swift`, `TypeContextDescriptorWrapper.swift`, `TypeContextWrapper.swift`, `TypeContextDescriptorProtocol.swift`, `TypeReference.swift`, `TypeMetadataRecord.swift`, `ValueMetadata.swift`, `ValueMetadataProtocol.swift`

**Fixture variants:** mix of `Structs.StructTest` (struct), `Classes.SimpleClassTest` (class), `Enums.SimpleEnumTest` (enum) — these wrappers/descriptors abstract over kind, so each test runs against all three to catch kind-specific reader bugs.

- [ ] **Step 1: Apply Task 4 pattern to `Models/Type/` root files**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Type/" 2>&1 | xcsift
```

(Note: `Type/` filter will match `Type/Class/`, `Type/Enum/`, `Type/Struct/`, `Type/` root — confirm all green.)

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Type*.swift \
        Sources/MachOTestingSupport/Baseline/Generators/ValueMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Type*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/Type/Value*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Type*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ValueMetadata*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Type/ root files"
```

### Task 10: `Protocol/`

**Files (testable):** `Protocol.swift`, `ProtocolDescriptor.swift`, `ProtocolDescriptorProtocol.swift`, `ProtocolDescriptorRef.swift`, `ProtocolDescriptorWithObjCInterop.swift`, `ProtocolRecord.swift`, `ProtocolRequirement.swift`, `ProtocolWitnessTable.swift`, `ResilientWitness.swift`, `ResilientWitnessesHeader.swift`, `ObjC/ObjCProtocolPrefix.swift`, `ObjC/RelativeObjCProtocolPrefix.swift`, `Invertible/InvertibleProtocolSet.swift`

**Fixture variants:**
- Plain protocol: `Protocols.ProtocolTest` (from `SymbolTestsCore/Protocols.swift`).
- Witness-table protocol: `Protocols.ProtocolWitnessTableTest`.
- Associated-type protocol: pick from `AssociatedTypeWitnessPatterns.swift`.
- ObjC protocol: pick a `@objc protocol` from `Protocols.swift` if available; otherwise add to allowlist with reason "needs fixture extension".

- [ ] **Step 1: Apply Task 4 pattern**

For `ResilientWitness.implementationAddress` (MachO-only debug formatter), add a `CoverageAllowlistEntry` (created in Task 16) referencing the source comment that already explains the omission.

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Protocol" 2>&1 | xcsift
```

(Filter matches `Protocol/`, `ProtocolConformance/` — make sure both pass once Task 11 lands.)

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Protocol/ \
        Tests/MachOSwiftSectionTests/Fixtures/Protocol/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Protocol*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ResilientWitness*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ObjCProtocol*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Invertible*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Protocol/"
```

### Task 11: `ProtocolConformance/`

**Files (testable):** `ProtocolConformance.swift`, `ProtocolConformanceDescriptor.swift`, `GlobalActorReference.swift` (if applicable)

**Fixture variants:**
- Concrete struct conforming to plain protocol: `Structs.StructTest: Protocols.ProtocolTest`.
- Class conforming to multiple protocols: pick from `ConditionalConformanceVariants.swift` or `Codable.swift`.
- Conditional conformance: pick from `ConditionalConformanceVariants.swift`.
- GlobalActor: from `Actors.swift` or `Concurrency.swift`.

- [ ] **Step 1: Apply Task 4 pattern**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "ProtocolConformance" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/ProtocolConformance/ \
        Tests/MachOSwiftSectionTests/Fixtures/ProtocolConformance/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/ProtocolConformance*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/GlobalActorReference*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for ProtocolConformance/"
```

### Task 12: `Generic/`

**Files (testable, public methods):** `GenericContext.swift`, `GenericRequirement.swift`, `GenericRequirementDescriptor.swift`, `GenericContextDescriptorHeader.swift`, `GenericContextDescriptorHeaderProtocol.swift`, `GenericPackShapeDescriptor.swift`, `GenericPackShapeHeader.swift`, `GenericParamDescriptor.swift`, `GenericValueDescriptor.swift`, `GenericValueHeader.swift`, `GenericWitnessTable.swift`, `TypeGenericContext.swift`, `TypeGenericContextDescriptorHeader.swift`, `GenericEnvironment.swift`

(Skip `*Flags.swift`, `*Kind.swift`, `*Type.swift` (pure data types).)

**Fixture variants:**
- No-requirement generic struct: `GenericFieldLayout.GenericStructNonRequirement`.
- Layout-requirement: `GenericFieldLayout.GenericStructLayoutRequirement`.
- Swift-protocol-requirement: `GenericFieldLayout.GenericStructSwiftProtocolRequirement`.
- ObjC-protocol-requirement: `GenericFieldLayout.GenericStructObjCProtocolRequirement`.
- Same-type-requirement: from `SameTypeRequirements.swift`.
- Multiple variants from `GenericRequirementVariants.swift`.

- [ ] **Step 1: Apply Task 4 pattern**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Generic" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Generic/ \
        Tests/MachOSwiftSectionTests/Fixtures/Generic/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Generic*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/TypeGeneric*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Generic/"
```

### Task 13: `FieldDescriptor/`, `FieldRecord/`, `AssociatedType/`

**Files (testable):**
- `FieldDescriptor/FieldDescriptor.swift`
- `FieldRecord/FieldRecord.swift`
- `AssociatedType/AssociatedType.swift`, `AssociatedTypeDescriptor.swift`, `AssociatedTypeRecord.swift`

**Fixture variants:**
- Plain field-bearing struct: `Structs.StructTest`.
- Generic struct: `GenericFieldLayout.GenericStructNonRequirement`.
- AssociatedType: pick from `AssociatedTypeWitnessPatterns.swift`.

- [ ] **Step 1: Apply Task 4 pattern**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "FieldDescriptor|FieldRecord|AssociatedType" 2>&1 | xcsift
```

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/FieldDescriptor*.swift \
        Sources/MachOTestingSupport/Baseline/Generators/FieldRecord*.swift \
        Sources/MachOTestingSupport/Baseline/Generators/AssociatedType*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/FieldDescriptor/ \
        Tests/MachOSwiftSectionTests/Fixtures/FieldRecord/ \
        Tests/MachOSwiftSectionTests/Fixtures/AssociatedType/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Field*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AssociatedType*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for FieldDescriptor/FieldRecord/AssociatedType"
```

### Task 14: `Metadata/`

**Files (testable):** `Metadata.swift`, `MetadataAccessorFunction.swift`, `MetadataBounds.swift`, `MetadataBoundsProtocol.swift`, `MetadataProtocol.swift`, `MetadataRequest.swift`, `MetadataResponse.swift`, `MetadataWrapper.swift`, `MetatypeMetadata.swift`, `FullMetadata.swift`, `FixedArrayTypeMetadata.swift`, `Headers/HeapMetadataHeader.swift`, `Headers/HeapMetadataHeaderProtocol.swift`, `Headers/HeapMetadataHeaderPrefix.swift`, `Headers/HeapMetadataHeaderPrefixProtocol.swift`, `Headers/TypeMetadataHeader.swift`, `Headers/TypeMetadataHeaderProtocol.swift`, `Headers/TypeMetadataHeaderBase.swift`, `Headers/TypeMetadataHeaderBaseProtocol.swift`, `Headers/TypeMetadataLayoutPrefix.swift`, `Headers/TypeMetadataLayoutPrefixProtocol.swift`, `MetadataInitialization/ForeignMetadataInitialization.swift`, `MetadataInitialization/SingletonMetadataInitialization.swift`, `CanonicalSpecialized*.swift` (if they have public methods), `HeapMetadataProtocol.swift`, `SingletonMetadataPointer.swift`

(Skip pure layout/state/kind enums.)

**Fixture variants:** mostly resolved via `MetadataAccessorFunction` — exercise across struct/class/enum kinds, generic vs non-generic, ObjC interop vs pure Swift.

`metadataAccessorFunction` only resolves on `MachOImage` (not `MachOFile`); accordingly, sub-Suite tests targeting metadata wrappers must adapt the cross-reader equality block:
- For methods that read MachOImage-only state: skip MachOFile assertion, document why.
- For methods that read static descriptor state: full three-way assertion.

- [ ] **Step 1: Apply Task 4 pattern**

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter "Metadata" 2>&1 | xcsift
```

(`Metadata` filter matches Type/*/Metadata as well as Models/Metadata — confirm all pass.)

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/Metadata/ \
        Tests/MachOSwiftSectionTests/Fixtures/Metadata/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Metadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Heap*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/TypeMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Metatype*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/FullMetadata*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/FixedArray*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Foreign*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Singleton*.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/Canonical*.swift
git commit -m "test(MachOSwiftSection): add fixture-based Suites for Metadata/ (incl. Headers + Initialization)"
```

### Task 15: Misc — `ExistentialType/`, `TupleType/`, `OpaqueType/`, `BuiltinType/`, `ForeignType/`, `Function/`, `Heap/`, `Capture/`, `DispatchClass/`, `ValueWitnessTable/`, `Mangling/`, `Misc/`

**Files (testable):** All public-method-bearing files in the listed subdirectories. Each subdirectory typically has 1-3 testable files.

**Fixture variants per subdirectory:**
- `ExistentialType`: from `ExistentialAny.swift`, `ProtocolComposition.swift`.
- `TupleType`: from `Tuples.swift`.
- `OpaqueType`: from `OpaqueReturnTypes.swift`.
- `BuiltinType`: from `BuiltinTypeFields.swift`.
- `ForeignType`: depends — Swift CFTypes exposed via SymbolTestsCore. If none, add allowlist entries with `needs fixture extension`.
- `Function`: from `FunctionFeatures.swift`, `FunctionTypes.swift`.
- `Heap`: from `Closure.swift` if present, otherwise allowlist.
- `Capture`: from `Closure.swift` / generic functions.
- `DispatchClass`: ObjC dispatch metadata — pick from `Classes.swift` `NSObject`-derived test type.
- `ValueWitnessTable`: any concrete struct with non-trivial layout — `Structs.StructTest`.
- `Mangling`: `MangledName.swift` operates on raw bytes; pick any descriptor's mangled type name.
- `Misc/SpecialPointerAuthDiscriminators.swift`: typically constants — confirm with inventory and allowlist if no public methods worth testing.

- [ ] **Step 1: Apply Task 4 pattern to each subdirectory**

For each, follow Steps 1-13 of Task 4. Take care for `ForeignType` and `Heap` — add `CoverageAllowlistEntry`s (with reason `needs fixture extension`) if SymbolTestsCore doesn't have a sample that reaches those code paths.

- [ ] **Step 2: Confirm + run**

```bash
swift run baseline-generator && git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
swift test --filter MachOSwiftSectionTests 2>&1 | xcsift
```

Expected: all currently-existing fixture tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/Baseline/Generators/ \
        Tests/MachOSwiftSectionTests/Fixtures/ \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): add fixture-based Suites for misc subdirectories

Cover ExistentialType, TupleType, OpaqueType, BuiltinType, ForeignType, Function,
Heap, Capture, DispatchClass, ValueWitnessTable, Mangling, Misc. Subdirectories
without fixture coverage in SymbolTestsCore get CoverageAllowlist entries with
reason `needs fixture extension`.
EOF
)"
```

---

## Task 16: Coverage Invariant Test

**Files:**
- Create: `Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift`
- Create: `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AllFixtureSuites.swift` (auto-generated, but also editable manually as a fallback if generator hasn't gotten to it)

- [ ] **Step 1: Write `CoverageAllowlistEntries`**

`Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift`:

```swift
import Foundation
import MachOTestingSupport

/// Public members of MachOSwiftSection/Models/ that are intentionally not under
/// fixture-based test coverage. Each entry MUST carry a human-readable reason.
enum CoverageAllowlistEntries {
    static let entries: [CoverageAllowlistEntry] = [
        // MachO-only debug formatters — no ReadingContext mirror exists by design.
        .init(
            typeName: "ResilientWitness",
            memberName: "implementationAddress",
            reason: "MachO-only debug formatter, documented in source"
        ),

        // Subdirectories without SymbolTestsCore fixture coverage. Track these
        // and address with a fixture extension when prioritized.
        // Entries added per-task during Tasks 5-15 land here.
        // Example (remove when fixture lands):
        // .init(
        //     typeName: "ForeignClassMetadata",
        //     memberName: "classDescriptor",
        //     reason: "needs fixture extension — no foreign class in SymbolTestsCore"
        // ),
    ]

    static var keys: Set<MethodKey> { Set(entries.map(\.key)) }
}
```

- [ ] **Step 2: Write `MachOSwiftSectionCoverageInvariantTests`**

`Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift`:

```swift
import Foundation
import Testing
@testable import MachOTestingSupport

@Suite
struct MachOSwiftSectionCoverageInvariantTests {

    private var modelsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Fixtures/
            .deletingLastPathComponent()  // MachOSwiftSectionTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources/MachOSwiftSection/Models")
    }

    @Test func everyPublicMemberHasATest() throws {
        let scanner = PublicMemberScanner(sourceRoot: modelsRoot)
        let expected = try scanner.scan(applyingAllowlist: CoverageAllowlistEntries.keys)

        let registered: Set<MethodKey> = Set(
            allFixtureSuites.flatMap { suite -> [MethodKey] in
                suite.registeredTestMethodNames.map { name in
                    MethodKey(typeName: suite.testedTypeName, memberName: name)
                }
            }
        )

        let missing = expected.subtracting(registered)
        let extra = registered.subtracting(expected)

        #expect(
            missing.isEmpty,
            """
            Missing tests for these public members of MachOSwiftSection/Models:
            \(missing.sorted().map { "  \($0)" }.joined(separator: "\n"))

            Tip: add the corresponding @Test func to the matching Suite, append the
            name to its registeredTestMethodNames (or rerun
            `swift run baseline-generator --suite <Name>`), and re-run.
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
```

- [ ] **Step 3: Generate `AllFixtureSuites.swift`**

Either:
- Extend `BaselineGenerator.generateAll()` to emit `AllFixtureSuites.swift` listing every Suite registered so far.
- Or hand-write one (pre-populating with the Suites added in Tasks 4-15).

For the auto-generated form, replace the `writeAllFixtureSuitesIndex` no-op stub in `BaselineGenerator.swift` (Task 4 Step 5) with an implementation that uses SwiftSyntaxBuilder:

```swift
import SwiftSyntax
import SwiftSyntaxBuilder

private static func writeAllFixtureSuitesIndex(outputDirectory: URL) throws {
    // Hand-maintained list of every Suite type registered across Tasks 4-15.
    // When a new Suite is added, update this list AND the dispatchSuite case
    // (both can be done from one editor pass).
    let suiteTypeNames = [
        "StructDescriptorTests",
        "StructTests",
        "StructMetadataTests",
        "StructMetadataProtocolTests",
        "AnonymousContextTests",
        "AnonymousContextDescriptorTests",
        // ... extend per Task 5-15 as Suites land
    ].sorted()

    // `\(raw: "Foo.self")` because `\(literal:)` would treat the string as a
    // String literal (i.e. emit `"Foo.self"`).
    let suiteListItems = suiteTypeNames.map { "\($0).self" }.joined(separator: ",\n    ")

    let header = """
    // AUTO-GENERATED — DO NOT EDIT.
    // Regenerate via: swift run baseline-generator
    // Generated: \(ISO8601DateFormatter().string(from: Date()))
    """

    let file: SourceFileSyntax = """
    \(raw: header)

    let allFixtureSuites: [any FixtureSuite.Type] = [
        \(raw: suiteListItems)
    ]
    """

    let formatted = file.formatted().description + "\n"
    let outputURL = outputDirectory.appendingPathComponent("AllFixtureSuites.swift")
    try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
}
```

(In practice, the generator could build the list from a registry populated by each sub-generator's call — but the hand-maintained list in `writeAllFixtureSuitesIndex` is simpler and the Coverage Invariant test in Step 4 below catches drift if a Suite is missing.)

Run `swift run baseline-generator` to produce the file.

- [ ] **Step 4: Run coverage test**

```bash
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | xcsift
```

Expected: passes (missing/extra are both empty).

If `missing` is non-empty: each entry shows `<Type>.<member>`. Either add a `@Test` and `registeredTestMethodNames` entry to the relevant Suite, or add a `CoverageAllowlistEntry` with a reason. Re-run.

If `extra` is non-empty: a member name in `registeredTestMethodNames` doesn't match any public source member. Likely a typo or stale entry — fix and re-run.

- [ ] **Step 5: Probe the guard works (manual verification)**

Temporarily add to `Sources/MachOSwiftSection/Models/Type/Struct/StructDescriptor.swift`:

```swift
extension StructDescriptor {
    public func _coverageProbe() -> Int { 0 }
}
```

Run: `swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | xcsift`

Expected: FAIL with `Missing tests for these public members ... StructDescriptor._coverageProbe`.

Revert the probe. Re-run; expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Tests/MachOSwiftSectionTests/Fixtures/CoverageAllowlistEntries.swift \
        Tests/MachOSwiftSectionTests/Fixtures/MachOSwiftSectionCoverageInvariantTests.swift \
        Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/AllFixtureSuites.swift \
        Sources/MachOTestingSupport/Baseline/BaselineGenerator.swift
git commit -m "$(cat <<'EOF'
test(MachOSwiftSection): wire up coverage invariant guard

Static SwiftSyntax scan of Sources/MachOSwiftSection/Models/ produces the
expected (typeName, memberName) set; reflection over allFixtureSuites produces
the registered set. missing/extra are both required to be empty.
CoverageAllowlistEntries collects intentional exclusions with reasons.
Verified by adding a probe public func and observing the test failed.
EOF
)"
```

---

## Task 17: `baseline-generator` Executable Polish

**Files:**
- Modify: `Sources/baseline-generator/main.swift` — proper ArgumentParser CLI

- [ ] **Step 1: Replace stub `main.swift` with proper CLI**

```swift
// Sources/baseline-generator/main.swift
import Foundation
import ArgumentParser
import MachOTestingSupport

@main
struct BaselineGeneratorMain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "baseline-generator",
        abstract: "Regenerates ABI baselines for MachOSwiftSection fixture tests."
    )

    @Option(
        name: .long,
        help: "Output directory for baseline files. Defaults to Tests/MachOSwiftSectionTests/Fixtures/__Baseline__."
    )
    var output: String = "Tests/MachOSwiftSectionTests/Fixtures/__Baseline__"

    @Option(
        name: .long,
        help: "Restrict regeneration to a specific Suite, e.g. StructDescriptor. If omitted, regenerates all baselines."
    )
    var suite: String?

    func run() async throws {
        let outputURL = URL(fileURLWithPath: output)
        if let suite {
            try await BaselineGenerator.generate(suite: suite, outputDirectory: outputURL)
        } else {
            try await BaselineGenerator.generateAll(outputDirectory: outputURL)
        }
    }
}
```

- [ ] **Step 2: Confirm `generate(suite:outputDirectory:)` dispatcher exists in `BaselineGenerator`**

Task 4 Step 5 already established the dispatcher (`dispatchSuite(_:in:outputDirectory:)`) and the `generate(suite:outputDirectory:)` entry point. Tasks 5-15 should have already extended both `generateAll` and `dispatchSuite` with each new sub-generator.

Verify by inspecting `Sources/MachOTestingSupport/Baseline/BaselineGenerator.swift`:

```bash
rg "case \"" Sources/MachOTestingSupport/Baseline/BaselineGenerator.swift
```

Expected: one `case "<SuiteName>":` line per sub-generator added across Tasks 4-15.

If any `case` is missing for a suite that has a sub-generator file, add it (and the corresponding `try dispatchSuite("...", ...)` line in `generateAll`). Re-run `swift build`.

- [ ] **Step 3: Test the CLI**

```bash
swift run baseline-generator --suite StructDescriptor
git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift
```

Expected: file unchanged (idempotent regeneration of just one file).

```bash
swift run baseline-generator --output /tmp/test-baselines
ls /tmp/test-baselines/
```

Expected: full set of baseline files in `/tmp/test-baselines/`.

- [ ] **Step 4: Test full regen idempotence**

```bash
swift run baseline-generator
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/
```

Expected: empty diff. If non-empty, the generator is non-deterministic somewhere — fix.

- [ ] **Step 5: Run full test suite**

```bash
swift test --filter MachOSwiftSectionTests 2>&1 | xcsift
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add Sources/baseline-generator/ Sources/MachOTestingSupport/Baseline/BaselineGenerator.swift
git commit -m "$(cat <<'EOF'
feat(baseline-generator): polish CLI with --suite/--output flags

Adds AsyncParsableCommand-based CLI to baseline-generator. --suite restricts
regeneration to one Suite (e.g. `swift run baseline-generator --suite StructDescriptor`),
--output overrides the default Tests/MachOSwiftSectionTests/Fixtures/__Baseline__.
EOF
)"
```

---

## Task 18: Final validation + cleanup

**Files:**
- Modify: `CLAUDE.md` — add brief section on the new test infrastructure
- Modify: `.gitignore` if generated files leak

- [ ] **Step 1: Validate the full Validation checklist from spec**

```bash
swift test --filter MachOSwiftSectionTests 2>&1 | xcsift
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | xcsift
swift run baseline-generator --suite StructDescriptor
git status Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/StructDescriptorBaseline.swift
```

Expected from the spec:
- All `swift test --filter MachOSwiftSectionTests` green.
- Coverage invariant green (missing/extra empty).
- `baseline-generator --suite <name>` is idempotent.

- [ ] **Step 2: Probe Coverage guard with synthetic public method**

```bash
# Temporarily add a public func
echo 'extension StructDescriptor { public func _probe() {} }' >> Sources/MachOSwiftSection/Models/Type/Struct/StructDescriptor.swift
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | xcsift
# Should FAIL with "Missing tests for ... StructDescriptor._probe"
git checkout Sources/MachOSwiftSection/Models/Type/Struct/StructDescriptor.swift
swift test --filter MachOSwiftSectionCoverageInvariantTests 2>&1 | xcsift
# Should PASS
```

- [ ] **Step 3: Probe baseline assertion with manual edit**

Open any `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/<File>Baseline.swift`. Change one numeric value. Run the corresponding Suite — expect `#expect(... == ...)` failure with a clear message. Revert the change.

- [ ] **Step 4: Update `CLAUDE.md`**

In `CLAUDE.md`, add a new section under "Test Environment":

```markdown
## Fixture-Based Test Coverage (MachOSwiftSection)

`MachOSwiftSection/Models/` is exhaustively covered by `Tests/MachOSwiftSectionTests/Fixtures/`. Suites mirror the source directory and assert (a) cross-reader equality across MachOFile/MachOImage/InProcess + their ReadingContext counterparts, and (b) per-method ABI literal expected values from `__Baseline__/*Baseline.swift`.

To add a new public method:

1. Add the method.
2. Run `swift test --filter MachOSwiftSectionCoverageInvariantTests` to see which Suite needs updating.
3. Add a `@Test` to that Suite + append the member name to `registeredTestMethodNames`.
4. Run `swift run baseline-generator --suite <Name>` to regenerate the baseline.
5. Re-run the affected Suite.

To regenerate all baselines after fixture rebuild or toolchain upgrade:

```
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore -configuration Release build
swift run baseline-generator
git diff Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/  # review drift
```
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(MachOSwiftSection): document fixture-based test coverage workflow"
```

- [ ] **Step 6: Final summary commit (optional)**

```bash
git log --oneline feature/machoswift-section-fixture-tests ^feature/reading-context-api
```

Expected: ~18 commits showing the structured implementation.

---

## Spec → Plan Coverage Check

| Spec section | Plan task |
|---|---|
| §1 整体架构 — Fixture loading layer | Task 1 |
| §1 整体架构 — Suite layer | Tasks 4-15 |
| §1 整体架构 — Baseline generator layer | Tasks 4 (sub-generator), 17 (CLI polish) |
| §1 整体架构 — Coverage invariant layer | Task 16 |
| §2 Test Infrastructure — `MachOSwiftSectionFixtureTests` | Task 1 |
| §2.2 `MachOImageName.SymbolTestsCore` | Task 1 Step 1 |
| §2.3 `acrossAllReaders` / `acrossAllContexts` | Task 1 Step 4 |
| §3.1 文件组织 (镜像 Models/) | Tasks 4-15 |
| §3.2 Suite 模板 | Task 4 Step 8 (template), reused 5-15 |
| §3.3 fixture 主测目标 (主 + 变体) | Task 4 Step 2 + per-task variants |
| §3.4 Baseline 引用形态 | Task 4 Step 5 + per-task baselines |
| §4.1 baseline-generator executable | Task 4 Step 6 (stub), Task 17 (CLI) |
| §4.2 模块组织 | Task 4 Step 5 |
| §4.3 生成流程 | Task 4 Step 7 + per-task generator runs |
| §4.4 数值进制约定 | Task 2 (BaselineEmitter hex helper, with `\(literal:)` covering decimal/string/bool/array) |
| §4.5 重生成流程 | Task 18 Step 4 (CLAUDE.md docs) |
| §4.6 Generator 自身正确性保证 | Task 4 Step 5 (generator only uses MachOFile path) + Task 2 (emitter unit tests) |
| §5.1 数据源 (expected via SwiftSyntax + registered via reflection) | Task 3 (scanner) + Task 16 (invariant test) |
| §5.2 MethodKey | Task 3 Step 3 |
| §5.3 Scanner 实现 | Task 3 Step 6 |
| §5.4 Coverage Test | Task 16 Step 2 |
| §5.5 失败信息 | Task 16 Step 2 (#expect messages) |
| §5.6 Coverage / Generator 协作矩阵 | Tasks 16+18 (probe verification) |
| §6.1 入测范围 | Task 3 Step 6 (scanner config) |
| §6.2 显式 Exclusions | Task 16 Step 1 (CoverageAllowlistEntries) |
| §7 Risks & Mitigations | Task 1 (FixtureLoadError), Task 4 (idempotence check), Task 16 (probe) |
| Validation checklist | Task 18 Steps 1-3 |

---

**Plan complete.**
