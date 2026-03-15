# CI Snapshot Testing Design

## Overview

Move snapshot tests to run on CI with support for large frameworks (SwiftUI, AppKit, etc.). Snapshots are stored in an external SPM package repository, keyed by platform version. CI auto-records missing snapshots and opens PRs for human review.

## Architecture

```
MachOSwiftSection (main repo)
    │
    ├── depends on SnapshotFixtures (SPM package, test-only)
    │       │
    │       └── MachOSwiftSection-Snapshots (external repo)
    │               └── Resources/
    │                   ├── macOS-26.3_Xcode-26.3/
    │                   │   ├── SwiftDump/SwiftUI/typesSnapshot.1.txt
    │                   │   ├── SwiftDump/Sharing/typesSnapshot.1.txt
    │                   │   └── SwiftInterface/SwiftUI/interfaceSnapshot.1.txt
    │                   └── macOS-15.5_Xcode-16.3/
    │                       └── ...
    │
    └── Tests/
        ├── SwiftDumpTests/Snapshots/     (test classes, no snapshot data)
        └── SwiftInterfaceTests/Snapshots/ (test classes, no snapshot data)
```

## Snapshot Repository

### Repository: `MachOSwiftSection-Snapshots`

A standalone SPM package with snapshot files as bundled resources.

**Package.swift:**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MachOSwiftSection-Snapshots",
    products: [
        .library(name: "SnapshotFixtures", targets: ["SnapshotFixtures"]),
    ],
    targets: [
        .target(
            name: "SnapshotFixtures",
            resources: [.copy("Resources")]
        ),
    ]
)
```

The `Resources/` directory must always exist (with at least a `.gitkeep`) so `Bundle.module` resolves correctly even when no snapshots are recorded yet.

**`SnapshotFixtures.swift` — public API:**

```swift
import Foundation

public enum SnapshotFixtures {
    /// Returns the snapshot directory for the current platform version.
    ///
    /// - In CI recording mode: returns the `SNAPSHOT_FIXTURES_DIR` environment variable
    ///   (set by the recording workflow to a writable output directory).
    /// - In normal mode: looks up existing snapshots in the bundle by version key.
    ///   Returns nil if no snapshots exist (tests should skip).
    public static func snapshotDirectory() -> String? {
        // CI recording mode: use override directory
        if let override = ProcessInfo.processInfo.environment["SNAPSHOT_FIXTURES_DIR"] {
            return override
        }
        // Normal mode: look up existing snapshots by version
        let key = versionKey()
        let url = Bundle.module.resourceURL?
            .appendingPathComponent("Resources")
            .appendingPathComponent(key)
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url.path
    }

    /// Version key for the current environment.
    /// Format: "macOS-{major.minor}_Xcode-{major.minor}"
    public static func versionKey() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion)"

        // Read Xcode version from version.plist, using DEVELOPER_DIR to support
        // CI environments where Xcode may be at a non-default path.
        let xcodeString: String
        let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? "/Applications/Xcode.app/Contents/Developer"
        let versionPlistPath = URL(fileURLWithPath: developerDir)
            .deletingLastPathComponent()  // Contents/
            .appendingPathComponent("version.plist")
            .path
        if let dict = NSDictionary(contentsOfFile: versionPlistPath),
           let shortVersion = dict["CFBundleShortVersionString"] as? String {
            xcodeString = shortVersion
        } else {
            xcodeString = "unknown"
        }

        return "macOS-\(osString)_Xcode-\(xcodeString)"
    }
}
```

**Resource directory structure:**

```
Resources/
├── .gitkeep
├── macOS-26.3_Xcode-26.3/
│   ├── SwiftDump/
│   │   ├── SwiftUI/
│   │   │   ├── typesSnapshot.1.txt
│   │   │   ├── protocolsSnapshot.1.txt
│   │   │   ├── protocolConformancesSnapshot.1.txt
│   │   │   └── associatedTypesSnapshot.1.txt
│   │   ├── Sharing/
│   │   │   └── ...
│   │   └── SourceKitSupport/
│   │       └── ...
│   └── SwiftInterface/
│       ├── SwiftUI/
│       │   └── interfaceSnapshot.1.txt
│       └── ...
└── macOS-15.5_Xcode-16.3/
    └── ...
```

Snapshot file names include the `.1.txt` suffix to match `swift-snapshot-testing`'s default naming convention.

## Main Repository Changes

### Package.swift

Add dependency:

```swift
.package(url: "https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection-Snapshots", from: "1.0.0"),
```

Add `SnapshotFixtures` to the `MachOTestingSupport` target (which already depends on `SnapshotTesting` and is shared across all test targets):

```swift
// MachOTestingSupport target
.product(name: "SnapshotFixtures", package: "MachOSwiftSection-Snapshots"),
```

### SnapshotTestable Protocol

Defined in `MachOTestingSupport` (which already depends on `SnapshotTesting`; add `SnapshotFixtures` as an additional dependency):

```swift
import Foundation
import Testing
import SnapshotFixtures
import SnapshotTesting

@MainActor
protocol SnapshotTestable {
    /// Module name: "SwiftDump" or "SwiftInterface"
    static var snapshotModule: String { get }
    /// Target framework name: "SwiftUI", "Sharing", etc.
    static var snapshotTarget: String { get }
}

extension SnapshotTestable {
    /// Returns the snapshot directory for this test, or nil if version not recorded.
    func resolvedSnapshotDirectory() -> String? {
        guard let base = SnapshotFixtures.snapshotDirectory() else { return nil }
        return "\(base)/\(Self.snapshotModule)/\(Self.snapshotTarget)"
    }

    /// Skips the test if no snapshots exist for the current platform version.
    func skipIfNoSnapshots() throws {
        guard resolvedSnapshotDirectory() != nil else {
            throw XCTSkip("No snapshots for \(SnapshotFixtures.versionKey()). Run snapshot-record workflow to generate.")
        }
    }

    /// Asserts a snapshot using the resolved directory from SnapshotFixtures.
    /// Uses `verifySnapshot` directly since `assertSnapshot` and `withSnapshotTesting`
    /// do not accept a `snapshotDirectory` parameter.
    func assertFixtureSnapshot(
        of value: String,
        as strategy: Snapshotting<String, String> = .lines,
        named name: String? = nil,
        fileID: StaticString = #fileID,
        file filePath: StaticString = #filePath,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let failure = verifySnapshot(
            of: value,
            as: strategy,
            named: name,
            snapshotDirectory: resolvedSnapshotDirectory(),
            fileID: fileID,
            file: filePath,
            testName: function,
            line: line,
            column: column
        )
        if let message = failure {
            Issue.record(
                Comment(rawValue: message),
                sourceLocation: SourceLocation(
                    fileID: fileID.description,
                    filePath: filePath.description,
                    line: Int(line),
                    column: Int(column)
                )
            )
        }
    }
}
```

Key design decisions:
- Uses `verifySnapshot` (not `assertSnapshot`) because only `verifySnapshot` accepts a `snapshotDirectory` parameter. Failures are reported via `Issue.record`.
- Uses `XCTSkip` (or Swift Testing equivalent) for skip behavior, not `#require` (which would fail instead of skip).
- Lives in `MachOTestingSupport` to avoid code duplication across test targets. The `SnapshotFixtures` dependency is acceptable here since `MachOTestingSupport` is test-only.

### Test Class Pattern

Each snapshot test class adopts `SnapshotTestable` and checks version before comparing:

```swift
@Suite(.serialized)
final class SwiftUIDumpSnapshotTests: DyldCacheTests, SnapshotDumpableTests, SnapshotTestable, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .SwiftUI }

    static var snapshotModule: String { "SwiftDump" }
    static var snapshotTarget: String { "SwiftUI" }

    @Test func typesSnapshot() async throws {
        try skipIfNoSnapshots()
        let output = try await collectDumpTypes(for: machOFileInCache)
        assertFixtureSnapshot(of: output)
    }
}
```

Note: `cachePath` defaults to `.current` in `DyldCacheTests`, no override needed.

### Binary Sources

| Source | How | CI available? |
|---|---|---|
| System dyld cache | `DyldSharedCachePath.current` | Yes, CI runner's own cache |
| Xcode frameworks | `XcodeMachOFileName` paths | Yes, CI runner's Xcode |
| SymbolTestsCore | Not used for CI snapshots | Excluded from CI snapshot tests |

- **dyld cache** and **Xcode frameworks** come from the CI runner environment. Only `.current` is used on CI; local-only paths like `.macOS_15_5` and `.iOS_18_5` are not used for snapshot tests.
- **SymbolTestsCore** is excluded from CI snapshot testing. Its tests remain local-only since the binary must be manually built from the SymbolTests Xcode project. SymbolTestsCore-based snapshot tests use the existing `__Snapshots__` local directory approach.

### Cleanup

- Delete all `Tests/**/Snapshots/__Snapshots__/` directories
- Update `.gitignore`: change `Tests/__Snapshots__` to `**/__Snapshots__/` to match all nested snapshot directories
- Remove `.snapshots(record: .missing)` from test suite traits
- This design is SPM-only; Xcode project builds are not supported for snapshot tests

## CI Workflows

### Existing: `macOS.yml` (test runner)

No major changes. Snapshot tests run as part of `swift test`. Behavior:
- Version matches recorded snapshots -> compare and assert
- Version not recorded -> test skips (not failure)

### New: `snapshot-record.yml` (snapshot recorder)

**Trigger:** `workflow_dispatch` (manual) with optional framework filter parameter.

**Steps:**

1. Checkout main repo
2. Detect version key:
   ```bash
   OS_VER=$(sw_vers -productVersion)
   XCODE_VER=$(xcodebuild -version | head -1 | awk '{print $2}')
   VERSION_KEY="macOS-${OS_VER}_Xcode-${XCODE_VER}"
   BRANCH_NAME="snapshots/${VERSION_KEY}"
   ```
3. Clone snapshot repo
4. Check if version directory exists OR if `BRANCH_NAME` already exists (prevents race conditions from concurrent runs)
5. If exists -> exit (already recorded)
6. If missing:
   a. Create output directory: `RECORD_DIR=$(mktemp -d)/snapshots`
   b. Run snapshot tests with environment variables:
      - `SNAPSHOT_TESTING_RECORD=all` (built-in `swift-snapshot-testing` record mode)
      - `SNAPSHOT_FIXTURES_DIR=$RECORD_DIR` (tells `SnapshotFixtures.snapshotDirectory()` to use writable output path)
   c. Copy recorded snapshots from `$RECORD_DIR` to snapshot repo under `Resources/{VERSION_KEY}/`
   d. Create branch `BRANCH_NAME`, commit, push
   e. `gh pr create` to snapshot repo with diff summary
7. PR requires human approval before merge

Uses the built-in `SNAPSHOT_TESTING_RECORD` environment variable recognized by `swift-snapshot-testing`. The custom `SNAPSHOT_FIXTURES_DIR` variable provides a writable output directory for recording, since the bundle resources are read-only.

## New Snapshot Test Targets

Large frameworks available via dyld cache `.current`:

| Framework | MachOImageName | Expected snapshot size |
|---|---|---|
| SwiftUI | `.SwiftUI` | ~10k+ lines (types) |
| SwiftUICore | `.SwiftUICore` | ~5k+ lines |
| AppKit | `.AppKit` | ~8k+ lines |
| Foundation | `.Foundation` | ~3k+ lines |
| Combine | `.Combine` | ~2k+ lines |
| HomeKit | `.HomeKit` | ~1k lines |
| Network | `.Network` | ~1k lines |

Each gets a dump snapshot test class and an interface snapshot test class.

## Version Key Format

```
macOS-{major.minor}_Xcode-{major.minor}
```

Examples:
- `macOS-26.3_Xcode-26.3`
- `macOS-15.5_Xcode-16.3`

Derived at runtime from `ProcessInfo.processInfo.operatingSystemVersion` and Xcode's `version.plist` (`CFBundleShortVersionString`). No shelling out to `xcodebuild` is needed.

## Retention Policy

Old version directories in the snapshot repo should be pruned periodically. Keep snapshots for:
- The current CI matrix versions
- The previous major version (for reference)

Pruning can be done manually or via a scheduled workflow that removes directories not matching the active CI matrix.

## Git LFS

Not required initially. Monitor snapshot repo size growth over time. If it exceeds ~500MB (many versions x many frameworks), enable Git LFS for `*.txt` files in the snapshot repo.
