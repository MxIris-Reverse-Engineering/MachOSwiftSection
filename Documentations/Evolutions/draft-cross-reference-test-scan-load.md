# Draft - 跨引用测试的整份 cache 扫描限并发，Tuist 工作区里扫描模块在 Debug 下开优化

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-21
- **最后更新**: 2026-11-21
- **所属愿景**: 无
- **关联提案**: [0099-tuist-workspace](0099-tuist-workspace.md)（本提案改的 Tuist 开发工作区）
- **实现分支 / PR**: `feature/cross-reference-test-scan-load`（从 `next` 切出，worktree `.worktrees/MachOSwiftSection-CrossReferenceTestScanLoad`）
- **配套文档**: 待定 —— 落地时判断；预计只更新既有文档（见「文档与示例」），不新写专题文章
- **网页版**: 同目录同名的 `.html`

## 摘要

`CrossReferenceAnalysisTests` 里有四个测试辅助函数用不设上限的 `DispatchQueue.concurrentPerform` 扫描整份 dyld shared cache，Debug 构建下每次跑测试都把机器的全部核心占满好几分钟。本提案做两件事：

1. **测试限并发**：测试 target 里新增一个全进程共用的扫描名额 `ImageScanConcurrency`，默认 `max(2, 核心数 / 2)`，四处扫描改走它；Swift Testing 并行跑多个套件时，所有扫描加起来也不超过这个名额。另加一个源码扫描测试，禁止以后在这个 target 里绕过它直接调 `concurrentPerform`。
2. **Debug 提速**：Tuist 开发工作区里，让采样中占满时间的两个扫描模块 `MachOCodeReferences`、`ARM64InstructionDecoding`（都在 MachOKitExtensions）在 Debug 配置下也用 `-O` 编译，去掉 Debug 下每条指令一次的 Swift 运行时元数据查找。

库的公开 API、原生 `MachOSwiftSection.xcworkspace`、`swift test` 与 CI 的行为都不变。

## 动机

- **跑一次测试，机器被占满好几分钟。** 2026-11-21 在 Ultra（M3 Ultra，28 核）上用 `./TuistScript.sh test` 跑 Debug 测试，xctest 进程持续占 2369% CPU（约 24 个核心），采样时已经跑了 8 分多钟、仍未结束。这台机器上 `queued-build` 不限核，测试期间同机的编译、其他 agent 会话和前台应用都被挤占。
- **占满核心的是测试辅助函数，不是库本身。** 对 xctest 采样 3 秒（`sample <pid> 3`），28 个工作线程全部落在 `ObjectiveCClassReferenceTests.imagesReferencing(_:at:among:)` 里的 `concurrentPerform` → `CrossReferenceAnalyzer.references(to:inImageAt:)` → `ReferenceScanner.scanFunction(at:)`。四个同类辅助函数（见「前期调研」）都按镜像数开满并发，没有上限。
- **Debug 下扫描慢在 Swift 运行时，而不是扫描算法。** 同一份采样里，工作线程约 11 600 个样本中，栈顶是 `LockingConcurrentMap<TupleCacheEntry>::getOrInsert`（元组类型元数据缓存，带锁）的有 4762 个（约 41%）；经过 `swift_getTupleTypeMetadata2` 的帧合计 5380 个（约 46%），再加泛型元数据实例化约 1510 个（约 13%）。来源是扫描热路径上的 `for … in` 区间循环：`-Onone` 下它们走 libswiftCore 里未特化的 `IndexingIterator.next()`，每走一步都要查一次元组元数据，28 个线程争同一把锁。按 AGENTS.md 的记载，Release 下整份 macOS shared cache 两三秒扫完；`ObjectiveCClassReferenceTests` 的注释则写明 Debug 构建「扫整份 cache 要几分钟」。
- **只限并发不够。** 限到一半核心后，同样的工作要跑更久；不把 Debug 下的这份运行时开销去掉，测试总时长会明显变长。两件事要一起做。

## 前期调研

- **四处不限并发的整份 cache 扫描**（路径相对 `Tests/CrossReferenceAnalysisTests/`，行号取自 `next` 25c4515c）：
  - `CrossReferenceAnalyzerTests.swift:259` · `imagesReferencing(_:among:)` —— 调用者预筛的抽样复查
  - `SwiftTypeReferenceTests.swift:324` · `imagesReferencing(_:among:)` —— Swift 类型引用的预筛复查
  - `ObjectiveCClassReferenceTests.swift:196` · `imagesReferencing(_:at:among:)` —— ObjC 类引用的预筛复查（这次采样抓到的就是它）
  - `FunctionStartOutsideTextTests.swift:25` · `imagesWithAStartOutsideText()` —— 对每个镜像建一次函数表
- **不在范围内的 `concurrentPerform`**：`ScanThroughputBenchmarkTests.swift:48/64/90` 是吞吐基准，套件带 `.enabled(if: ScanThroughputBenchmarkEnvironment.outputPath != nil)`，要设 `CROSS_REFERENCE_BENCHMARK_OUTPUT` 才跑，量的就是全核吞吐；库内 `Sources/Support/Utilities/ConcurrentMap.swift`、`Sources/Commands/SwiftSectionKit/CrossReferences/ReferencesRequest.swift:146`、`Sources/Symbols/SwiftSymbols/SwiftSymbolIndexStore.swift:1757` 与 MachOKitExtensions 的 `RenamedReexportIndex.swift:45` 是给 CLI 与宿主用的，应当用满核心。
- **Swift Testing 并行跑套件**：上面四处分属四个套件，`.serialized` 只约束套件内部。每次调用各自限宽的话，几个套件同时扫描时会叠加回满核，所以名额必须是全进程共用的。
- **既有先例**：`Tests/SwiftPrintingTests/ConcurrentDefinitionPrintingTests.swift:70` 的 `taskGroupWidth = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)`；收集结果的 `ImageIndexCollector`（`CrossReferenceAnalyzerTests.swift:325`）用 `NSLock`。测试 target 的部署版本在 SwiftPM 与 Tuist 下都是 macOS 14（`Tuist/Package.swift` 的 `testTargetSettings`），用不了要求 macOS 15 的 `Synchronization.Atomic` / `Mutex`，沿用 `NSLock`。
- **热点循环的位置**（MachOKitExtensions 主检出，`Sources/Analysis/MachOCodeReferences/Scanning/`）：
  - `RegisterFile.swift:148` · `clobberCallerSavedRegisters()` 的 `for register in 0 ... 18`
  - `RegisterFile.swift:48` · `Snapshot.meet(_:)` 的 `for register in 0 ..< RegisterFile.registerCount`
  - `ReferenceScanner.swift:150`、`:292` · `scanFunction(at:)` 里逐条指令的 `for instructionIndex in 0 ..< instructionCount`
  - 采样栈顶里自家函数还有 `RegisterFile.Snapshot.agrees(with:on:)`、`ReferenceScanner.scanFunction(at:)`（MachOCodeReferences）与 `ARM64InstructionWord.conditionalBranchTarget(_:at:)`（ARM64InstructionDecoding）。前 30 名里没有 `CrossReferenceAnalysis` 与 `ObjCCodeReferences` 的函数。
- **开 `-O` 不会丢掉检查**：`MachOCodeReferences`、`ARM64InstructionDecoding` 里没有 `assert` / `assertionFailure`（`-O` 会去掉它们），`MachOCodeReferences` 的两处 `precondition` 在 `-O` 下保留。本包的 `CrossReferenceAnalysis` 有一处 `assert`，这也是它不进名单的原因之一。
- **Tuist 工作区里这两个模块从源码编**：TuistDevelopment.md 写明原生 workspace 里的五个上游库（含 MachOKitExtensions）在两种依赖模式下都从源码编、不进二进制缓存，`PackageSettings.targetSettings` 按 target 名对它们生效（已有先例：`restatedTraitDefinitions` 给远程包 Capstone 加设置）。
- **Tuist 生成的工程把优化级别写在每个配置里**：现有生成结果 `…/Dependencies/<checkout>/tuist-derived/Projects/MachOKitExtensions/MachOKitExtensions.xcodeproj/project.pbxproj` 中，每个 target 的 Debug 配置写 `SWIFT_OPTIMIZATION_LEVEL = "-Onone"`、Release 写 `"-O"`。**未验证**：`targetSettings` 的 `base` 是否覆盖这个按配置写的值。落地第 4 步先验证，不行就改用按配置的设置（见「详细设计」）。
- **实测收益**（落地第 1、5 步，同一台 Ultra、同样条件）：`CrossReferenceAnalysisTests` 从约 14 分钟降到约 1.5 分钟，xctest 累计 CPU 时间从约 234 分钟降到约 14 分钟（约 17 倍）。开头约 35 秒仍会用满核心，那是 Swift Testing 同时跑着二十多个测试，不是这四处扫描（见决策日志）。

## 提议方案

1. 测试 target 新增 `ImageScanConcurrency`：一个进程内共用的计数信号量（`DispatchSemaphore`，值为 `maximumConcurrentScans`），加一个与 `DispatchQueue.concurrentPerform(iterations:execute:)` 同形的入口。每次调用最多起 `maximumConcurrentScans` 个工作者，从共享游标领下一个下标，每扫一个镜像前先取一个名额、扫完归还。所以不管同时有几个套件在扫，正在扫描的镜像总数都不超过名额。
2. 四处辅助函数把 `DispatchQueue.concurrentPerform(iterations:)` 换成 `ImageScanConcurrency.concurrentPerform(iterations:)`，闭包体不动。
3. 新增源码扫描测试 `ParallelScanSourceTests`：这个 target 里除 `ImageScanConcurrency.swift` 与 `ScanThroughputBenchmarkTests.swift` 外，出现 `DispatchQueue.concurrentPerform(` 就失败；照项目惯例配一个 `theScanDiscriminates` 证明扫描本身能区分。
4. `Tuist/Package.swift` 新增 `optimizedScanSettings`，给 `MachOCodeReferences`、`ARM64InstructionDecoding` 设 `SWIFT_OPTIMIZATION_LEVEL = -O`，并入 `PackageSettings.targetSettings`。本包自己的 `CrossReferenceAnalysis` 保持 Debug 不优化。
5. 改前、改后各量一次 `CrossReferenceAnalysisTests` 的墙钟时间、xctest 的累计 CPU 时间与 CPU 占用峰值，写回本提案。

### 非目标

- **不改库代码**：不改 MachOKitExtensions 里的热点循环。那条路让 `swift test` 与原生 workspace 也受益，但要发 MachOKitExtensions 新版，这次不做（见「替代方案」）。
- **不动库内与 CLI 的并发**：`ConcurrentMap`、`ReferencesRequest`、`SwiftSymbolIndexStore`、`RenamedReexportIndex` 照旧用满核心。
- **不动吞吐基准**：`ScanThroughputBenchmarkTests` 要手动开启，量的就是全核吞吐。
- **不改原生 workspace、`swift test` 与 CI**：CI 的 runner 只有 3 核，名额算出来是 2，与现在差别不大；CI 用 `swift test`，不经 Tuist，所以 `-O` 设置也碰不到它。
- **名额不做成可配置**：不加环境变量；真要调，改 `maximumConcurrentScans` 一处。
- **不改 RuntimeViewer 的 Tuist 工作区**：它有自己的 `TuistScript.sh` 与清单。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Tests/CrossReferenceAnalysisTests/ImageScanConcurrency.swift` · `ImageScanConcurrency` | 新增 | 进程共用的名额 `maximumConcurrentScans` 与信号量，入口 `concurrentPerform(iterations:execute:)`；私有的 `IterationCursor`（`NSLock` 保护的下一个下标） | 四处扫描共用一份上限，并行的套件不叠加 | 2 |
| `Tests/CrossReferenceAnalysisTests/ImageScanConcurrencyTests.swift` · `ImageScanConcurrencyTests` | 新增 | 四个行为测试（见落地步骤 2） | 钉住「每个下标只跑一次」与「同时进行的不超过名额」 | 2 |
| `Tests/CrossReferenceAnalysisTests/CrossReferenceAnalyzerTests.swift` · `imagesReferencing(_:among:)` | 修改 | `DispatchQueue.concurrentPerform` → `ImageScanConcurrency.concurrentPerform` | 不限并发的整份 cache 扫描 | 3 |
| `Tests/CrossReferenceAnalysisTests/SwiftTypeReferenceTests.swift` · `imagesReferencing(_:among:)` | 修改 | 同上 | 同上 | 3 |
| `Tests/CrossReferenceAnalysisTests/ObjectiveCClassReferenceTests.swift` · `imagesReferencing(_:at:among:)` | 修改 | 同上 | 同上（这次采样抓到的那处） | 3 |
| `Tests/CrossReferenceAnalysisTests/FunctionStartOutsideTextTests.swift` · `imagesWithAStartOutsideText()` | 修改 | 同上 | 同上 | 3 |
| `Tests/CrossReferenceAnalysisTests/ParallelScanSourceTests.swift` · `ParallelScanSourceTests` | 新增 | 扫本 target 源码，禁止名额与基准之外直接调 `DispatchQueue.concurrentPerform(`；`theScanDiscriminates` | 以后新写的整份 cache 测试默认会照抄 `concurrentPerform`，靠测试拦住 | 3 |
| `Tuist/Package.swift` · `optimizedScanSettings` | 新增 | 两个扫描模块 `SWIFT_OPTIMIZATION_LEVEL = -O`，并入 `mergingSettings(...)` | Debug 下扫描的时间过半花在运行时元数据查找 | 4 |
| `Documentations/Internal/TuistDevelopment.md` | 修改 | 「已知的坑」加一条：两个扫描模块在 Debug 下也开 `-O`，在 Tuist 里对它们打断点会看到优化后的代码；要调试时从名单里临时拿掉再生成 | 这是 Tuist 工作区与原生 workspace 的一处有意差异 | 5 |
| `Documentations/Internal/FixtureTestingAndContinuousIntegration.md` | 修改 | 新增一小节「整份 cache 扫描共用一份并发名额（2026-11-21）」：为什么要全进程共用、名额怎么算、哪些地方例外 | 记录设计来历 | 5 |
| `AGENTS.md`（`CLAUDE.md` 是指向它的符号链接） | 修改 | 「writing or modifying tests」块加一条：并行扫描很多镜像的测试走 `ImageScanConcurrency.concurrentPerform`，不直接调 `DispatchQueue.concurrentPerform` | agent 默认会照抄旧写法 | 5 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时追加一节，节号按落地规则取 | 项目要求每个非平凡批次记一节 | 落地 |
| `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案（现在一次，落地改名时一次） | 索引 | 现在 / 落地 |

## 架构图

改了什么：

```text
Tests/CrossReferenceAnalysisTests/
  CrossReferenceAnalyzerTests.imagesReferencing(_:among:)
  SwiftTypeReferenceTests.imagesReferencing(_:among:)
  ObjectiveCClassReferenceTests.imagesReferencing(_:at:among:)
  FunctionStartOutsideTextTests.imagesWithAStartOutsideText()
-     └── DispatchQueue.concurrentPerform(iterations:)            (every core, per call)
+     └── ImageScanConcurrency.concurrentPerform(iterations:)     (one process-wide budget)
+ ImageScanConcurrency            maximumConcurrentScans = max(2, activeProcessorCount / 2)
+ ImageScanConcurrencyTests
+ ParallelScanSourceTests         no bare concurrentPerform outside the budget and the benchmark
  ScanThroughputBenchmarkTests    unchanged (opt-in, every core)

Tuist/Package.swift  PackageSettings.targetSettings
+ optimizedScanSettings
+   MachOCodeReferences           SWIFT_OPTIMIZATION_LEVEL = -O   (Debug too)
+   ARM64InstructionDecoding      SWIFT_OPTIMIZATION_LEVEL = -O   (Debug too)
    CrossReferenceAnalysis        unchanged (-Onone in Debug)
    ObjCCodeReferences            unchanged (-Onone in Debug)
```

名额怎么在并行的套件之间共用：

```text
suite A ─ concurrentPerform(iterations: 1600) ─┐  workers ≤ maximumConcurrentScans per call
suite B ─ concurrentPerform(iterations:  110) ─┼─ each worker: cursor.next() → permits.wait()
suite C ─ concurrentPerform(iterations: 1700) ─┘                → scan one image → permits.signal()

permits = DispatchSemaphore(value: maximumConcurrentScans)   shared by every call in the process
⇒ images being scanned at once, across all suites ≤ maximumConcurrentScans
```

Debug 下热路径为什么慢（改前）与开 `-O` 后（改后）：

```text
ReferenceScanner.scanFunction(at:)                       MachOCodeReferences, -Onone
- for instructionIndex in 0 ..< instructionCount
-   IndexingIterator<Range<Int>>.next()                  libswiftCore, unspecialized
-     Range.formIndex(after:) witness
-       swift_getTupleTypeMetadata2                      locked global cache, 28 threads contend
+ for instructionIndex in 0 ..< instructionCount         MachOCodeReferences, -O
+   specialized and inlined integer loop                 no runtime metadata lookup
```

## 详细设计

### `ImageScanConcurrency`

```swift
import Foundation

/// How many images the test target's parallel scans may read at once: half of
/// the cores, at least two. A Debug scan of the whole shared cache keeps every
/// core it is given busy for minutes, and Swift Testing runs the suites holding
/// these scans in parallel — so the budget is one for the whole process, not
/// one per call, or four suites at once would add up to every core again.
enum ImageScanConcurrency {
    static let maximumConcurrentScans = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

    private static let permits = DispatchSemaphore(value: maximumConcurrentScans)

    /// Runs `body` once for every index in `0 ..< iterations`, the way
    /// `DispatchQueue.concurrentPerform(iterations:execute:)` does, with at most
    /// `maximumConcurrentScans` bodies running at once across the process.
    ///
    /// `body` must not call this function again: a nested call waits for a
    /// permit while its caller holds one, and with every permit held that way
    /// nothing is ever released.
    static func concurrentPerform(iterations: Int, execute body: (Int) -> Void) {
        guard iterations > 0 else { return }
        let cursor = IterationCursor(iterationCount: iterations)
        DispatchQueue.concurrentPerform(iterations: min(maximumConcurrentScans, iterations)) { _ in
            while let index = cursor.next() {
                permits.wait()
                defer { permits.signal() }
                body(index)
            }
        }
    }
}

/// Hands out each index of `0 ..< iterationCount` once, to whichever worker asks first.
private final class IterationCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let iterationCount: Int
    private var nextIndex = 0

    init(iterationCount: Int) {
        self.iterationCount = iterationCount
    }

    func next() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard nextIndex < iterationCount else { return nil }
        defer { nextIndex += 1 }
        return nextIndex
    }
}
```

- **为什么每次调用也限工作者数**：只靠信号量的话，`concurrentPerform` 仍按核心数起线程，多出来的线程全阻塞在 `permits.wait()` 上；内核的 workqueue 看到线程阻塞还会补新线程。先把每次调用的工作者限到名额以内，阻塞的线程数就有上界（同时在扫的套件数 × 名额）。
- **为什么不会卡死**：名额只在扫一个镜像的期间持有，扫描是同步的 CPU 工作，不等任何线程池上的工作，持有者总会归还。调用线程可能是 Swift Testing 的 cooperative thread（同步测试函数跑在它上面，`concurrentPerform` 也在调用线程上执行迭代），它在 `permits.wait()` 上等的是别的扫描线程归还名额，而那些线程不需要 cooperative pool。这与 AGENTS.md「不要让 cooperative thread 不设超时地等需要池线程的工作」不冲突。嵌套调用会卡死，文档注释写明禁止；四处调用点的闭包体都不嵌套。
- **CI**：runner 3 核，`activeProcessorCount / 2 = 1`，取下限 2。CI 跑的是 `swift test`，同样经过这份名额。

### 调用点（以 `ObjectiveCClassReferenceTests` 为例）

```swift
// before
DispatchQueue.concurrentPerform(iterations: imageIndices.count) { position in
    let imageIndex = imageIndices[position]
    …
}
// after
ImageScanConcurrency.concurrentPerform(iterations: imageIndices.count) { position in
    let imageIndex = imageIndices[position]
    …
}
```

闭包体、收集结果的 `ImageIndexCollector` 与 `FunctionStartOutsideTextTests` 的 `flagsBase` 写法都不变。

### `ParallelScanSourceTests`

照 `MemoryAccessScanTests` 的写法：从 `#filePath` 取本 target 目录，逐行扫 `.swift` 文件，跳过 `//` 开头的行，匹配 `DispatchQueue.concurrentPerform(`；`ImageScanConcurrency.swift` 与 `ScanThroughputBenchmarkTests.swift` 两个文件名在允许名单里。`theScanDiscriminates` 断言：`DispatchQueue.concurrentPerform(iterations: n) {` 命中，`ImageScanConcurrency.concurrentPerform(iterations: n) {` 与注释行不命中。

### `Tuist/Package.swift`

```swift
    // A Debug build of the cross-reference scan spends most of its time in the Swift runtime, not in
    // the scan: an unspecialized range loop looks tuple metadata up on every instruction, under one
    // lock every thread shares, so CrossReferenceAnalysisTests' whole-cache scans take minutes instead
    // of the seconds a Release build needs. The scan's two hottest modules compile optimized in every
    // configuration here; this package's own CrossReferenceAnalysis stays debuggable.
    // (Evolution proposal cross-reference-test-scan-load.)
    let optimizedScanSettings: [String: Settings] = Dictionary(
        ["MachOCodeReferences", "ARM64InstructionDecoding"].map { targetName in
            (targetName, Settings.settings(base: ["SWIFT_OPTIMIZATION_LEVEL": "-O"]))
        },
        uniquingKeysWith: { first, _ in first }
    )
```

并入 `PackageSettings(targetSettings: mergingSettings(warningSettings, restatedTraitDefinitions, testTargetSettings, testingSupportSettings, optimizedScanSettings), …)`。`mergingSettings` 合并的是各自的 build setting 键，`SWIFT_OPTIMIZATION_LEVEL` 与其它几组的键不重叠，它头上「keys never overlap」的注释仍然成立。

**`base` 覆盖不了按配置写的值时的后备**（第 4 步验证结果决定）：改成

```swift
Settings.settings(configurations: [.debug(name: .debug, settings: ["SWIFT_OPTIMIZATION_LEVEL": "-O"])])
```

并让 `mergingSettings` 连同 `configurations` 一起合并（现在它只合并 `base`，会把 `configurations` 丢掉）。这条后备只在验证失败时启用，结果记入决策日志。

### 怎么量

- 在不跑其它测试的时候量（同机别的 xctest 会争核心），`TUIST_SCRIPT_ROOT=/Volumes/DerivedData/Agents.noindex/claude/Tuist-MachOSwiftSection`。
- 先 `queued-build ./TuistScript.sh build --scheme "MachOSwiftSection Tests"`，把编译排除在外；再 `queued-build ./TuistScript.sh test --scheme "MachOSwiftSection Tests" -- -only-testing:CrossReferenceAnalysisTests`。
- 测试期间每 10 秒读一次 `ps -o %cpu=,time= -p <xctest pid>`：取 `%cpu` 的峰值，以及进程结束前最后一次的累计 CPU 时间；墙钟时间取 `.xcresult` 里这个 target 的总耗时。
- 测试成败按全局规则只认原始退出码。

## 替代方案考量

- **改 MachOKitExtensions 里的热点循环**（把 `for … in` 区间循环改成 Debug 下不查元数据的写法）：`swift test`、原生 workspace 与 CI 都受益，但收益只有元数据那一块（估计快一倍左右，未实测），要发 MachOKitExtensions 新版本，热路径上的写法也变得不自然，以后新写的循环还会再犯。这次选了 Tuist 配置，这条留作以后 `swift test` 也嫌慢时的选项。
- **整个 Debug 工作区开 `-O`，或用 Release 跑测试**：失去所有模块的调试能力；Release 下 `@testable import` 还要额外开 `ENABLE_TESTABILITY`，二进制缓存按配置分份，整套都要重做。范围远超问题本身。
- **`CrossReferenceAnalysis`、`ObjCCodeReferences` 也开 `-O`**：采样栈顶的前 30 名里没有它们；`CrossReferenceAnalysis` 是本包自己的代码，最常被调试，还有一处 `assert` 会被 `-O` 去掉。等第 5 步的采样说明它们也是瓶颈再加。
- **每次调用各自限宽，不共用名额**：Swift Testing 并行跑四个套件时，加起来又是满核。
- **把四个套件串行化**：`.serialized` 只管套件内部；要跨套件串行得把它们挪进同一个父套件，改动面大，而且把不扫描的测试也拖慢了。
- **降低扫描线程的 QoS 而不限并发**：CPU 照样占满，只是让出优先级；Apple Silicon 上 `.background` 还会把工作压到能效核，测试会慢很多。
- **用库里现成的 `concurrentMap(maximumConcurrency:)`**（`Sources/Support/Utilities/BoundedConcurrentMap.swift`）：它是 async 的 task group，测试是同步函数；在 cooperative thread 上跑这种同步的重活正是 AGENTS.md 要避免的；它的上限也是每次调用各算各的。

## 影响

### 源码兼容性（source compatibility）

**纯新增**。改动全在测试 target 与 Tuist 开发清单里，库的公开 API 不变。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：只有 `CrossReferenceAnalysisTests`（四处调用点与三个新文件）和 Tuist 工作区的生成结果。
- 下游仓库：无。`Tuist/Package.swift` 只用于本仓库的开发工作区，RuntimeViewer、MachOKitUI 等用的是 SwiftPM 清单。
- **并行进行的功能分支**：`feature/shared-macho-testing-support` 也改了 `FunctionStartOutsideTextTests.swift`（19 行），合并时可能有小冲突；本提案只改其中一行调用。

### 文档与示例

- `Documentations/Internal/TuistDevelopment.md`、`Documentations/Internal/FixtureTestingAndContinuousIntegration.md`、`AGENTS.md`：见改动地图。
- `Documentations/Internal/ProjectEvolutionLog.md`：落地时追加一节。
- README、DocC、示例代码：无需改动（不涉及用法）。

## API 演进与废弃策略

不适用 —— 没有新增、修改或废弃任何公开 API，不需要版本号跃迁。

## 落地步骤

1. **量基线** —— 不改代码（已完成，数字见决策日志）
   - 行为：`baselineWallTimeCpuTimeAndPeakAreRecordedInTheProposal`（按「怎么量」在 `next` 上量一次，数字写进决策日志）
2. **加名额与它的测试** —— 改动地图第 1、2 行（已完成）
   - 行为：`everyIterationRunsExactlyOnce`（1000 次迭代，每个下标恰好执行一次）
   - 行为：`noMoreThanTheBudgetRunAtOnce`（闭包里记录同时在跑的数目，最大值不超过 `maximumConcurrentScans`）
   - 行为：`twoCallsAtOnceShareTheBudget`（两个线程同时调用，合计同时在跑的数目不超过名额）
   - 行为：`zeroIterationsReturnWithoutRunning`
   - 实现时临时把入口换成裸 `DispatchQueue.concurrentPerform`，确认后三条里与上限有关的两条会失败（证明测试抓得住），再换回来；这一步不提交。
3. **四处调用点改走名额，加源码扫描测试** —— 改动地图第 3–7 行（已完成；四个套件原有的测试在第 5 步的整批复测里一起验证）
   - 行为：`everyParallelScanGoesThroughTheSharedBudget`
   - 行为：`theScanDiscriminates`
   - 行为：四个套件原有的测试照旧全部通过
4. **Tuist 里两个扫描模块开 `-O`** —— 改动地图第 8 行（已完成）
   - 行为：`debugConfigurationCompilesTheScanModulesOptimized`（重新生成后，生成的 `MachOKitExtensions.xcodeproj` 里 `MachOCodeReferences`、`ARM64InstructionDecoding` 的 Debug 配置是 `-O`，构建日志里它们的编译命令带 `-O`）
   - 行为：`crossReferenceAnalysisStaysUnoptimizedInDebug`
   - 验证不通过就启用「详细设计」里的后备写法，再验证一次
5. **复测并更新文档** —— 改动地图第 9–11 行（已完成）
   - 行为：`wholeCacheScansStayWithinTheBudget`（采样里，四处扫描同时占用的线程不超过名额）。原先写的「xctest 的 `%cpu` 峰值不超过名额」没有成立：开头约 35 秒是 Swift Testing 自身的并行，见决策日志
   - 行为：`wallTimeAndCpuTimeAreRecordedAgainstTheBaseline`
   - 复测时再采样一次；`CrossReferenceAnalysis` 或 `ObjCCodeReferences` 的帧占比明显时，把结论记进决策日志，再决定要不要扩大 `-O` 名单

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不需要：设计来历写进 FixtureTestingAndContinuousIntegration.md 的新小节，Tuist 差异写进 TuistDevelopment.md 的「已知的坑」。
- **有没有引入新术语** —— 预计没有：「扫描名额」只在本提案与那一小节里用，不登记术语表。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-21 | Created as Draft | Ultra 上跑 Debug 测试时 xctest 长时间占满 28 核。采样定位到两个原因：四处不限并发的整份 cache 扫描，以及 Debug 下扫描循环每条指令都查一次运行时元数据。用户决定两项都改：测试限并发；Debug 提速走 Tuist 配置，不改 MachOKitExtensions 源码。按轻量档写提案。 |
| 2026-11-21 | Accepted | 用户批准，开始实现。 |
| 2026-11-21 | 测量时临时套用另一分支的修复 | `next` 上 `./TuistScript.sh test` 编不过：`SwiftSectionTestingMacrosTests` 报 `Unable to resolve module dependency: 'SwiftSectionTestingMacros'`。`feature/shared-macho-testing-support` 已经修了（Tuist 映射测试时把依赖宏 target 的测试也拿掉，改 `Package.swift` 两行），还没合进 `next`。本分支只在工作区里临时套用这两行来测量，不提交；改前改后在同样条件下量。 |
| 2026-11-21 | 基线 | Ultra，`next` 的代码，Tuist Debug，`-only-testing:CrossReferenceAnalysisTests`：124 个测试用时 841 秒（Swift Testing 的报告）；xctest 累计 CPU 时间约 234 分钟（约 14 030 秒，平均约 17 个核心）；`ps` 读到的 `%cpu` 峰值 2356%。同机另有一个会话的 `swift test` 占着约 4 个核心。3 个失败是新 worktree 缺 `SymbolTestsCore` 夹具，按 AGENTS.md 链接主检出的 `DerivedData` 后解决，与本提案无关。 |
| 2026-11-21 | 第 2 步验证 | 入口临时换成裸 `concurrentPerform` 时，两条上限测试失败；只按调用限宽、不共用名额时，只有 `twoCallsAtOnceShareTheBudget` 失败，证明这条测试抓得住「名额必须全进程共用」。正式实现四条全过。 |
| 2026-11-21 | 第 3 步验证 | 把一处调用点临时改回 `DispatchQueue.concurrentPerform` 时 `everyParallelScanGoesThroughTheSharedBudget` 失败，恢复后通过。四个重型套件单独复测一次要十几分钟，与第 4 步之后的整批复测合并进行。 |
| 2026-11-21 | 第 4 步验证 | `base` 里的 `SWIFT_OPTIMIZATION_LEVEL` 盖过了 Tuist 按配置写的值，后备写法不需要：重新生成后，`MachOKitExtensions.xcodeproj` 里 `MachOCodeReferences`、`ARM64InstructionDecoding` 的 Debug 配置是 `-O`，同工程没进名单的 `MachOAddressResolution` 仍是 `-Onone`；本包 `MachOSwiftSection.xcodeproj` 里 `CrossReferenceAnalysis` 的 Debug 仍是 `-Onone`。 |
| 2026-11-21 | 第 5 步复测 | 同一台 Ultra，同样条件（机器上没有别的测试在跑）：127 个测试全部通过（3 个跳过）；xctest 存活约 91 秒，累计 CPU 时间约 829 秒（基线约 14 030 秒，约 17 倍）；第二次复测 93 秒、843 秒，结果一致。构建日志里 `MachOCodeReferences` 的编译命令带 `-O`。 |
| 2026-11-21 | 偏离：开头约 35 秒仍满核 | `ps` 读到的 `%cpu` 在头 35 秒达到约 2500%，之后降到 300% 以下。在第 6 秒与第 20 秒各采样 3 秒：占着线程的是二十多个不同的测试（`FileModeTests` 建文件模式分析器、各种预筛测试、`LargeStackThreadPool` 的工作线程），每个测试一个线程，是 Swift Testing 按核心数并行跑测试，不是四处扫描。限制测试运行器自身的并行度超出本提案范围，原定的「峰值不超过名额」改为「四处扫描不超过名额」，后续要不要限由用户决定。 |
| 2026-11-21 | 不扩大 `-O` 名单 | 复测时在第 61 秒采样：只剩三个 `FileModeTests` 在跑，时间花在 ICU 正则与字符串查找上，运行时元数据查找已不显著，`CrossReferenceAnalysis`、`ObjCCodeReferences` 开 `-O` 收益不大，维持原名单。 |
| 2026-11-21 | 收尾判断 | 不需要专题文章：设计来历写进 FixtureTestingAndContinuousIntegration.md 的新小节，Tuist 差异写进 TuistDevelopment.md 的新小节，规则写进 AGENTS.md。没有引入新术语。 |
| 2026-11-21 | 完整验证 | Tuist workspace 的 `MachOSwiftSection Tests` 整个 scheme（Debug，Ultra，带测量时同样临时套用的 `Package.swift` 两行）：3005 个通过、0 失败、7 个跳过，634 秒。 |
| 2026-11-21 | 实现完成，待用户看过后收尾 | 功能分支已推送并在本地合进 `next` 的常驻检出（不推送）；测量时临时套用的 `Package.swift` 两行没有提交。 |
