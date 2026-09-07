# Fixture 测试体系与 CI 的设计来历

> 本文整合自 2026-03 → 2026-05 的四份设计 spec 与 CI 落地记录（原存于已删除的
> `docs/superpowers/` 目录，完整原文见 git 历史）。**现行操作规程以
> [AGENTS.md](../../AGENTS.md) 的「Fixture-Based Test Coverage (MachOSwiftSection)」与
> 「Build and Test Commands」章节为准**；本文记录的是设计动机、机制原理与踩坑史——
> 代码和规程里看不出来的那部分。

整个体系分三层，按落地时间排列：

1. **快照层**（2026-03）：`SwiftDumpTests` / `SwiftInterfaceTests` 对 fixture 输出做逐字节快照；
2. **集成/E2E 层**（2026-04）：对解析出的 `TypeDefinition` 模型与 `SwiftInterfaceBuilder` 输出做结构化断言；
3. **ABI 覆盖层**（2026-05）：`MachOSwiftSectionTests/Fixtures/` 对 `Models/` 每个 public 方法做跨 reader 一致性 + baseline 字面量断言，配覆盖不变量守护。

三层共用同一个 fixture：`Tests/Projects/SymbolTests` 编出的 `SymbolTestsCore.framework`。

## 为什么 fixture 只用 SymbolTestsCore

CI 上可复现性是唯一判据：

| 来源 | CI 可复现？ | 漂移维度 |
|---|---|---|
| 系统 dyld cache | 否——随每个 macOS 补丁变 | macOS 版本、cache 布局、框架更新 |
| Xcode 自带框架 | 否——随每个 Xcode 发布变 | Xcode / swiftlang 版本 |
| `SymbolTestsCore`（检入源码编译） | **是**——pinned 源码 + pinned Xcode | 仅 pinned 工具链版本 |

坍缩到单一确定性来源后：快照直接进 git、无外部 fixtures 包、无自动重录 workflow，快照 diff 就是「本库对某 Swift 构造发出的元数据变了」的直接信号。系统 cache / Xcode 框架的旧快照套件在快照层落地时删除，那些二进制仅供本地手动探查。

## 路径锚定——fixture 二进制怎么被找到（易踩坑）

`MachOFileName.SymbolTestsCore` 存的是相对路径
`../../Tests/Projects/SymbolTests/DerivedData/...`，**不是**对 CWD 解析，而是对
`Sources/MachOTestingSupport/Extensions.swift` 的 `#filePath` 解析——`../../` 爬回仓库根再下行。
而构建端 `xcodebuild -derivedDataPath Tests/Projects/SymbolTests/DerivedData` 是对
`xcodebuild` 自己的 CWD 解析。两者对齐**当且仅当**构建从仓库根发起——任何从子目录跑
`xcodebuild` 的 CI 步骤都会悄悄打破对齐。CI 还遇到过第三种形态：runner 上 `xcodebuild`
把产物放在 `DerivedData/Build/Products/...`（本地是 `DerivedData/SymbolTests/Build/Products/...`），
workflow 里的 "Normalize SymbolTestsCore fixture path" 步骤用符号链接补齐。

本地一键构建入口是 `Scripts/build-test-fixtures.sh`。

## Fixture 源码约定

- 每个 `.swift` 文件 = 一个语言/ABI 特性类目，以 `public enum <文件名> { … }` 做命名空间，
  内部全 `public`（保证 descriptor 落进二进制）。快照测试按「根命名空间 == 文件名」过滤归属。
- 项目用 `PBXFileSystemSynchronizedRootGroup`——新文件放进目录即入编译，无需改 `project.pbxproj`。
- 偏差与边界（约定的例外要么改写成约定、要么在此登记）：
  - `AsyncSequence.swift` / `Codable.swift` / `StringInterpolation.swift` 的 enum 名与文件名不同
    （`AsyncSequenceTests` / `CodableTests` / `StringInterpolations`），为避开 stdlib 同名类型；
  - `GlobalDeclarations.swift` 只有全局声明、不发 TypeContextDescriptor，per-category dump 有意为空，
    覆盖靠全模块 interface 快照；
  - `NeverExtensions.swift` 全是 `extension Never`，descriptor 归属 `Swift.Never`，
    用显式 Never 谓词而非命名空间归属——唯一的非命名空间归属规则。
- ProtocolConformance 按**遵循方类型**的根命名空间归属（与浏览 dump 输出的习惯一致）。
- 2026-04-13 的扩展批把 fixture 从 18 个文件扩到 54+，分三类：通用语言特性（KeyPaths、
  Codable 合成、property observers …）、扩展特性（protocol composition、class-bound generics、
  marker protocols …）、以及**专为二进制元数据形态设计**的一批——后者与目标 section 的对应关系
  是选 fixture 样本时的检索表：

| 文件 | 目标 section / descriptor |
|---|---|
| `FieldDescriptorVariants.swift` | `__swift5_fieldmd` 字段形态全集 |
| `GenericRequirementVariants.swift` | `TargetGenericRequirementDescriptor` 全 requirement kind（含 `~Copyable`/`~Escapable`） |
| `VTableEntryVariants.swift` | class `VTableDescriptorHeader` 各 entry flag |
| `ConditionalConformanceVariants.swift` | `__swift5_proto` 条件 requirement 表 |
| `DefaultImplementationVariants.swift` | `__swift5_protos` 默认实现扩展（含 `where Self:` 约束） |
| `FrozenResilienceContrast.swift` | 同布局 `@frozen` vs resilient 的 descriptor 形态对照 |
| `AssociatedTypeWitnessPatterns.swift` | `__swift5_assocty` 五种 witness 模式 |
| `BuiltinTypeFields.swift` | builtin 类型字段 |

后续 2026-05-05 批又为 sentinel 消化加了 default-override table、resilient class、
ObjC class wrapper、canonical specialized metadata、foreign types、value generics 等形态
（见下文 ABI 覆盖层）。

## 集成/E2E 层（2026-04-10）

两层分工：`SymbolTestsCoreIntegrationTests` 加载二进制后在 **`TypeDefinition` 模型层**断言
（类型/字段/conformance/override/嵌套/关联类型/属性推断/vtable 与 PWT 排序）；
`SymbolTestsCoreE2ETests` 走 `SwiftInterfaceBuilder` 在**输出字符串层**断言
（`@propertyWrapper` 等 attribute 出现、vtable offset 注释升序、`@retroactive` / `override` 关键字在场）。
同批为 attribute 推断加了专用 fixture 类型（`PropertyWrapperStruct` / `ResultBuilderStruct` /
`DynamicMemberLookupStruct` / `DynamicCallableStruct` / `ObjCAttributeClass`）。

## ABI 覆盖层（2026-05-03 设计 + 2026-05-05 收紧）

### 四支柱架构

```
fixture.framework (SymbolTestsCore)
    ├─[disk]──── MachOFile ──┐
    ├─[dlopen]── MachOImage ─┼─→ 3 个 ReadingContext ─→ Fixtures/ 各 Suite
    └─[ptr]───── InProcess ──┘        │
                                      ├─→ ① 跨 reader 一致性 #expect
                                      └─→ ② ABI baseline 字面量 #expect ←─ baseline-generator 生成
                          MachOSwiftSectionCoverageInvariantTests 守护（源码静态扫描 vs 注册名单）
```

关键设计决策：

- **generator 只走 MachOFile 单一路径生成 baseline**（单路径易审计）；MachOImage / InProcess 的
  正确性由跨 reader 一致性独立验证，不依赖 baseline——两道防线互为兜底（三家同错一个 bug 时
  baseline 字面量兜住；generator 自身出错时一致性断言兜住）。
- **数值进制约定**：offset / size / flags 用 hex（便于和反汇编工具对照），count / index 用十进制。
- **重载合并**：同名方法的 `(in: MachO)` / `(in: Context)` / `()` InProcess 三家重载共享一个
  `MethodKey`，在单个 `@Test` 内一并验证；覆盖守护按 `(typeName, memberName)` 比对不区分重载。
- baseline 头部记录 toolchain 版本 + 生成日期；`--suite <Name>` 支持局部重生成以缩小 review 面。

### 信任危机与 sentinel 收紧（2026-05-05）

原始落地被 review 发现**系统性失真**：157 个 suite 里 88 个（56%）从不调用
`acrossAllReaders`/`acrossAllContexts`，687 个声明覆盖的方法里 277 个（40%）只是挂在
baseline 字符串集合里的 sentinel——`registeredTestMethodNames` 是手工名单，
「registered == expected」的不变量对这些 suite 是空挡。原设计要求「没有合适样本就进
allowlist 并填 reason」，实施时被偷换成永远通过的 sentinel 测试，绕开了 reason 强制。

修复沿三条路径（机制细节现录于 AGENTS.md）：

- **A — sentinel 一等公民化**：`SentinelReason` 类型化三档（`runtimeOnly` / `needsFixtureExtension`
  / `pureDataUtility`），`SuiteBehaviorScanner` 用 SwiftSyntax 按 `@Test` 函数体内的调用痕迹判定
  实际行为，新增两段不变量——**liarSentinel**（标了 sentinel 但实际在真测 → 标签过期）与
  **unmarkedSentinel**（行为是 sentinel 但没登记 → 堵住 silent sentinel）。行为事实最难撒谎，
  故选全自动扫描而非手工 marker。
- **B — 扩 fixture 消化 `needsFixtureExtension`**：每种缺失的 metadata 形态一个新 fixture 文件
  一个 commit（重编 fixture 会引发整片 baseline 漂移，故批间先做 baseline 对齐 commit）。
- **C — runtime-only 转 InProcess 真测**：运行时现场分配的 metadata（metatype / tuple / function /
  existential …）在其他 reader 上拿不到数据，强求跨 reader 是另一种 sentinel——所以走
  `usingInProcessOnly` 单 reader + baseline 字面量。样本来源分流：stdlib 类型直接
  `unsafeBitCast(T.self, …)`，fixture nominal 类型取其 metadata 指针，header/bounds 类从既有
  metadata 指针偏移读取。无法稳定构造的（`swift_allocBox` 产物等）保留 `runtimeOnly` 永久 sentinel。

## CI（2026-04-18 设计 + 落地反馈）

- **白名单而非黑名单**：CI 只跑不依赖开发机环境（Xcode 框架、模拟器 runtime、系统 dyld cache、
  运行时加载镜像）的 fixture 套件。白名单正面表达意图（「CI 只跑可复现的 fixture 测试」），
  黑名单会让新测试被默默包含。代价是新增可上 CI 的套件要记得进名单。
- **过滤器是一条锚定 regex**：`\.(SuiteA|SuiteB|…)(/|$)`——前导 `\.` 锚住模块前缀，尾部 `(/|$)`
  是词边界，防 `STCoreTests` 匹配进 `STCoreE2ETests` 这类子串陷阱（多个 `--filter` 分开传没有
  这层保护）。当前名单与 runner/Xcode 版本以 [`.github/workflows/macOS.yml`](../../.github/workflows/macOS.yml)
  为活权威（名单在过滤层落地后已多次扩充）。
- **首轮 CI 踩过的五个坑**（都已修进 workflow，重配 CI 时先对照这张表）：

| 坑 | 修法 |
|---|---|
| `xcodebuild` 因缺开发者证书失败 | `CODE_SIGNING_ALLOWED=NO` |
| `generic/platform=macOS` 产 universal slice，x86_64 `.swiftinterface` 验证失败（项目 ARM-only） | `ARCHS=arm64` |
| Xcode 26.2（Swift 6.2.3）发出的 `.swiftinterface` 含 `nonisolated(nonsending)` 后自己拒绝验证（编译器 bug） | 跳到 Xcode 26.4（Swift 6.3 修复）——这就是当年 pin 26.4 而非需求档案里 26.2 的原因 |
| 远端依赖 pin 版本缺新 API | 升 `Package.swift` pin |
| runner 上 fixture 产物路径与本地布局不同 | "Normalize SymbolTestsCore fixture path" 符号链接步骤 |

- **无自动重录 workflow**：快照漂移永远由开发者本地 `SNAPSHOT_TESTING_RECORD=all` 重录、
  人工 review 后与触发变更同 PR 提交。CI 的 `xcode-version` 永远显式 pin，不用 `latest-stable`——
  任何 bump 都应是有意的、可 review 的变更（工具链升级可能合法地改变发出的元数据与 section 顺序，
  后者由 linker 决定，同工具链内稳定）。

## 相关文档

- [AGENTS.md](../../AGENTS.md) —— 覆盖体系的现行操作规程（invariants、regen-baselines、环境漂移排查）
- [Reviews/2026-05-06-generic-specializer-bug-review.md](Reviews/2026-05-06-generic-specializer-bug-review.md) —— 同期 GenericSpecializer 审查（复现测试纪律的样板）
- [ProjectEvolutionLog.md](ProjectEvolutionLog.md) §6–§7 —— 这两个工作弧在演进账本里的条目
- 原始四份 spec 与逐步执行 plan 的完整原文：git 历史中的 `docs/superpowers/`（2026-09-01 移除）
