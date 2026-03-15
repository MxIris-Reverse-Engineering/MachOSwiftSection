# Snapshot Testing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add snapshot tests for SwiftDump and SwiftInterface module outputs using swift-snapshot-testing, covering SymbolTestsCore, Xcode frameworks, and specified-path dyld caches.

**Architecture:** Create reusable string-collecting protocols in `MachOTestingSupport` (`SnapshotDumpableTests`, `SnapshotInterfaceTests`) that mirror existing `DumpableTests` / `SwiftInterfaceBuilderTests` but return strings instead of printing. Separate snapshot test files inherit the same base classes and use `assertSnapshot(of:as: .lines)` for line-by-line comparison.

**Tech Stack:** swift-snapshot-testing (already a dependency), Swift Testing framework, `.lines` strategy, `.snapshots(record: .missing)` trait.

---

## Chunk 1: Infrastructure & SwiftDump Snapshots

### Task 1: Add SnapshotTesting dependency to test targets

**Files:**
- Modify: `Package.swift:499-525` (SwiftDumpTests and SwiftInterfaceTests target definitions)

- [ ] **Step 1: Add SnapshotTesting to SwiftDumpTests dependencies**

In `Package.swift`, add `.product(name: "SnapshotTesting", package: "swift-snapshot-testing")` to `SwiftDumpTests`:

```swift
static let SwiftDumpTests = Target.testTarget(
    name: "SwiftDumpTests",
    dependencies: [
        .target(.SwiftDump),
        .target(.MachOTestingSupport),
        .product(.MachOObjCSection),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ],
    swiftSettings: testSettings
)
```

- [ ] **Step 2: Add SnapshotTesting to SwiftInterfaceTests dependencies**

```swift
static let SwiftInterfaceTests = Target.testTarget(
    name: "SwiftInterfaceTests",
    dependencies: [
        .target(.SwiftInterface),
        .target(.MachOTestingSupport),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ],
    swiftSettings: testSettings
)
```

- [ ] **Step 3: Verify build resolves**

Run: `swift build --build-tests 2>&1 | head -20`
Expected: Build succeeds or progresses without dependency errors.

---

### Task 2: Create SnapshotDumpableTests protocol

**Files:**
- Create: `Sources/MachOTestingSupport/SnapshotDumpableTests.swift`

- [ ] **Step 1: Create the file with string-collecting methods**

```swift
import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump

@MainActor
package protocol SnapshotDumpableTests {}

extension SnapshotDumpableTests {
    package func collectDumpTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO,
        options: DumpableTypeOptions = [.enum, .struct, .class],
        using configuration: DumperConfiguration? = nil
    ) async throws -> String {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var results: [String] = []
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .enum(let enumDescriptor):
                guard options.contains(.enum) else { continue }
                do {
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    let output = try await enumType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .struct(let structDescriptor):
                guard options.contains(.struct) else { continue }
                do {
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    let output = try await structType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            case .class(let classDescriptor):
                guard options.contains(.class) else { continue }
                do {
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    let output = try await classType.dump(using: configuration ?? .demangleOptions(.test), in: machO).string
                    results.append(output)
                } catch {
                    results.append("Error: \(error)")
                }
            }
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        var results: [String] = []
        for protocolDescriptor in protocolDescriptors {
            let output = try await Protocol(descriptor: protocolDescriptor, in: machO)
                .dump(using: .demangleOptions(.test), in: machO).string
            results.append(output)
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors
        var results: [String] = []
        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            let output = try await ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO)
                .dump(using: .demangleOptions(.test), in: machO).string
            results.append(output)
        }
        return results.joined(separator: "\n")
    }

    package func collectDumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(
        for machO: MachO
    ) async throws -> String {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        var results: [String] = []
        for associatedTypeDescriptor in associatedTypeDescriptors {
            let output = try await AssociatedType(descriptor: associatedTypeDescriptor, in: machO)
                .dump(using: .demangleOptions(.test), in: machO).string
            results.append(output)
        }
        return results.joined(separator: "\n")
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --build-tests 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 3: SwiftDump snapshot test — MachOFile (SymbolTestsCore)

**Files:**
- Create: `Tests/SwiftDumpTests/Snapshots/MachOFileDumpSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized, .snapshots(record: .missing))
final class MachOFileDumpSnapshotTests: MachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func typesSnapshot() async throws {
        let output = try await collectDumpTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDumpProtocols(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolConformancesSnapshot() async throws {
        let output = try await collectDumpProtocolConformances(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypesSnapshot() async throws {
        let output = try await collectDumpAssociatedTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests to generate baseline snapshots**

Run: `swift test --filter MachOFileDumpSnapshotTests 2>&1 | tail -20`
Expected: Tests pass (`.record: .missing` auto-creates reference snapshots). Snapshot files appear in `Tests/SwiftDumpTests/Snapshots/__Snapshots__/MachOFileDumpSnapshotTests/`.

- [ ] **Step 3: Verify snapshot files were created**

Run: `ls Tests/SwiftDumpTests/Snapshots/__Snapshots__/MachOFileDumpSnapshotTests/`
Expected: 4 `.txt` files (one per test method).

- [ ] **Step 4: Run tests again without record mode to verify they pass**

Run: `swift test --filter MachOFileDumpSnapshotTests 2>&1 | tail -10`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/MachOTestingSupport/SnapshotDumpableTests.swift Tests/SwiftDumpTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftDump MachOFile (SymbolTestsCore)"
```

---

### Task 4: SwiftDump snapshot test — XcodeMachOFile

**Files:**
- Create: `Tests/SwiftDumpTests/Snapshots/XcodeMachOFileDumpSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized, .snapshots(record: .missing))
final class XcodeMachOFileDumpSnapshotTests: XcodeMachOFileTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceKitSupport) }

    @Test func typesSnapshot() async throws {
        let output = try await collectDumpTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDumpProtocols(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolConformancesSnapshot() async throws {
        let output = try await collectDumpProtocolConformances(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypesSnapshot() async throws {
        let output = try await collectDumpAssociatedTypes(for: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests to generate baseline snapshots**

Run: `swift test --filter XcodeMachOFileDumpSnapshotTests 2>&1 | tail -20`
Expected: Tests pass, snapshots created in `Tests/SwiftDumpTests/Snapshots/__Snapshots__/XcodeMachOFileDumpSnapshotTests/`.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftDumpTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftDump XcodeMachOFile (SourceKitSupport)"
```

---

### Task 5: SwiftDump snapshot test — Specified DyldCache

**Files:**
- Create: `Tests/SwiftDumpTests/Snapshots/DyldCacheDumpSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport

@Suite(.serialized, .snapshots(record: .missing))
final class DyldCacheDumpSnapshotTests: DyldCacheTests, SnapshotDumpableTests, @unchecked Sendable {
    override class var cachePath: DyldSharedCachePath { .macOS_15_5 }

    override class var cacheImageName: MachOImageName { .Sharing }

    @Test func typesSnapshot() async throws {
        let output = try await collectDumpTypes(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolsSnapshot() async throws {
        let output = try await collectDumpProtocols(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func protocolConformancesSnapshot() async throws {
        let output = try await collectDumpProtocolConformances(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }

    @Test func associatedTypesSnapshot() async throws {
        let output = try await collectDumpAssociatedTypes(for: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests to generate baseline snapshots**

Run: `swift test --filter DyldCacheDumpSnapshotTests 2>&1 | tail -20`
Expected: Tests pass, snapshots created.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftDumpTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftDump DyldCache (macOS 15.5 Sharing)"
```

---

## Chunk 2: SwiftInterface Snapshots

### Task 6: Create SnapshotInterfaceTests protocol

**Files:**
- Create: `Sources/MachOTestingSupport/SnapshotInterfaceTests.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface

@MainActor
package protocol SnapshotInterfaceTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SnapshotInterfaceTests {
    package var snapshotBuilderConfiguration: SwiftInterfaceBuilderConfiguration {
        SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: false
            ),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printTypeLayout: true
            )
        )
    }

    package func collectInterfaceString(in machO: MachOFile) async throws -> String {
        let builder = try SwiftInterfaceBuilder(
            configuration: snapshotBuilderConfiguration,
            eventHandlers: [],
            in: machO
        )
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }
}
```

- [ ] **Step 2: Add SwiftInterface dependency to MachOTestingSupport if needed**

Check if `MachOTestingSupport` already depends on `SwiftInterface`. If not, add it in `Package.swift`:

```swift
static let MachOTestingSupport = Target.target(
    name: "MachOTestingSupport",
    dependencies: [
        .product(.MachOKit),
        .target(.MachOExtensions),
        .target(.SwiftDump),
        .target(.SwiftInterface),
        .target(.MachOTestingSupportC),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ],
    swiftSettings: testSettings
)
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build --build-tests 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 7: SwiftInterface snapshot test — MachOFile (SymbolTestsCore)

**Files:**
- Create: `Tests/SwiftInterfaceTests/Snapshots/MachOFileInterfaceSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface

@Suite(.serialized, .snapshots(record: .missing))
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class MachOFileInterfaceSnapshotTests: MachOFileTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func interfaceSnapshot() async throws {
        let output = try await collectInterfaceString(in: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests to generate baseline snapshot**

Run: `swift test --filter MachOFileInterfaceSnapshotTests 2>&1 | tail -20`
Expected: Test passes, snapshot created in `Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/MachOFileInterfaceSnapshotTests/`.

- [ ] **Step 3: Commit**

```bash
git add Sources/MachOTestingSupport/SnapshotInterfaceTests.swift Tests/SwiftInterfaceTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftInterface MachOFile (SymbolTestsCore)"
```

---

### Task 8: SwiftInterface snapshot test — XcodeMachOFile

**Files:**
- Create: `Tests/SwiftInterfaceTests/Snapshots/XcodeMachOFileInterfaceSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface

@Suite(.serialized, .snapshots(record: .missing))
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class XcodeMachOFileInterfaceSnapshotTests: XcodeMachOFileTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var fileName: XcodeMachOFileName { .sharedFrameworks(.SourceKitSupport) }

    @Test func interfaceSnapshot() async throws {
        let output = try await collectInterfaceString(in: machOFile)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests and commit**

Run: `swift test --filter XcodeMachOFileInterfaceSnapshotTests 2>&1 | tail -20`
Expected: Test passes, snapshot created.

```bash
git add Tests/SwiftInterfaceTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftInterface XcodeMachOFile (SourceKitSupport)"
```

---

### Task 9: SwiftInterface snapshot test — Specified DyldCache

**Files:**
- Create: `Tests/SwiftInterfaceTests/Snapshots/DyldCacheInterfaceSnapshotTests.swift`

- [ ] **Step 1: Create test file**

```swift
import Foundation
import Testing
import SnapshotTesting
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) @testable import MachOCaches

@Suite(.serialized, .snapshots(record: .missing))
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class DyldCacheInterfaceSnapshotTests: DyldCacheTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var cachePath: DyldSharedCachePath { .macOS_15_5 }

    override class var cacheImageName: MachOImageName { .Sharing }

    @Test func interfaceSnapshot() async throws {
        let output = try await collectInterfaceString(in: machOFileInCache)
        assertSnapshot(of: output, as: .lines)
    }
}
```

- [ ] **Step 2: Run tests and commit**

Run: `swift test --filter DyldCacheInterfaceSnapshotTests 2>&1 | tail -20`
Expected: Test passes, snapshot created.

```bash
git add Tests/SwiftInterfaceTests/Snapshots/
git commit -m "feat: add snapshot tests for SwiftInterface DyldCache (macOS 15.5 Sharing)"
```

---

## Chunk 3: Final Verification

### Task 10: Run all snapshot tests together

- [ ] **Step 1: Run all snapshot tests**

Run: `swift test --filter "SnapshotTests" 2>&1 | tail -30`
Expected: All snapshot tests pass (14 tests total: 12 SwiftDump + 3 SwiftInterface - but note it's 4+4+4=12 dump + 1+1+1=3 interface = 15 total).

- [ ] **Step 2: Verify all snapshot files exist**

Run: `fd -e txt . Tests/ --path-separator / | grep __Snapshots__`
Expected: All snapshot `.txt` files listed.

- [ ] **Step 3: Review a few snapshot files for correctness**

Read a couple of snapshot files to verify they contain reasonable Swift type/interface output, not empty or error-filled.

---

## Summary of New Files

```
Sources/MachOTestingSupport/
├── SnapshotDumpableTests.swift          # String-collecting dump methods
└── SnapshotInterfaceTests.swift         # String-collecting interface method

Tests/SwiftDumpTests/Snapshots/
├── MachOFileDumpSnapshotTests.swift     # SymbolTestsCore
├── XcodeMachOFileDumpSnapshotTests.swift # Xcode SourceKitSupport
├── DyldCacheDumpSnapshotTests.swift     # macOS 15.5 Sharing
└── __Snapshots__/                       # Auto-generated

Tests/SwiftInterfaceTests/Snapshots/
├── MachOFileInterfaceSnapshotTests.swift # SymbolTestsCore
├── XcodeMachOFileInterfaceSnapshotTests.swift # Xcode SourceKitSupport
├── DyldCacheInterfaceSnapshotTests.swift # macOS 15.5 Sharing
└── __Snapshots__/                       # Auto-generated
```

## Modified Files

- `Package.swift` — Add `SnapshotTesting` to `SwiftDumpTests`, `SwiftInterfaceTests`; add `SwiftInterface` to `MachOTestingSupport`
