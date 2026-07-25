# 2026-07-25 — NodeStore 迁移回归修复与三源基线建设

## 问题

用户报告两件事：

1. **RuntimeViewer 内存图报泄漏**：32 个 `NodeStore`、32 个 `_ContiguousArrayStorage<CompactNode>`、14 个 `_ContiguousArrayStorage<UInt8>`、12 个 `__NSArrayI`。
2. **测试覆盖不足**：fixture 之外缺少对 `dump` / `interface` 的整文件验证，需要用同一二进制在 main 与迁移分支之间做快照对比。

## 调研

### 泄漏

`NodeStore` 是只持有扁平缓冲的 `final class`，无外向引用，不可能自成环——被判 leaked 只能是上游持有链不可达但存活。实测：

- `leaks --atExit` 跑 `swift-section dump` / `interface`（含 SymbolIndexStore 构建、per-type 字段 store、整条打印管线）：**0 leaks / 0 bytes**。
- 自建 in-process 复现程序（dlopen 框架 → `SwiftInterfaceBuilder` + 逐类型 dumper，MachOImage 路径，与 RV 同口径）：**0 leaks**。
- 最小 associated-object 探针（`objc_setAssociatedObject` 挂 `[Payload]`、宿主保活）：`leaks` **也报 0**，说明 `leaks` CLI 会扫描 association 侧表。

两个并行 Explore agent 分别审计 RV 与库：

- 库侧唯一把「模型对象数组」桥进 ObjC 的地方是 `SwiftSpecialization/TypeDefinition+Specialization.swift:23` 的 `@AssociatedObject _specializedChildren: [TypeDefinition]`，数字完全吻合：12 个 `__NSArrayI` = 12 个被特化过的泛型 def；32 个 store = 每个特化 def 的 `typeName` 经 `NodeReference(interning:)` 生成的 mini store；14 个文本缓冲 = 其中带非空 bound-generic 标识符文本者（其余共享空文本单例）。
- RV 侧 `NodeStore` 全部挂在 `RuntimeEngine` → `RuntimeSwiftSectionFactory` 之下；`.local` 引擎是静态根，其下对象不会被判 leaked。故被标 leaked 意味着有非 local 引擎被终止后未释放。查到两个嫌疑（`RuntimeEngineManager.pollUntilPeerAnswers` 中被放弃、强捕获 `engine` 的 `probeTask`；`RuntimeMessageChannel` 无超时 continuation），外加结构性问题：`removeSection` / `removeAllSections` 无调用者、`addSubIndexer` 无逆操作。

**结论**：迁移代码本身无泄漏；RV 内存图的判定与 `leaks` 的可达性引擎不同（Memory Graph 不把 association 侧表还原为图的边），叠加 RV 自身生命周期缺口。用户指示 RV 侧暂不处理。

### 快照对比

用 `git worktree` 拉 main、符号链接四个本地依赖、两侧同配置构建 `swift-section`。首轮对 iOS 18.5 / 26.5 的三件套跑 18 份整文件快照，**16/18 一致，2 份差异**：`ios185-SwiftData.interface` 与 `.interface-full`——main 打印 5 处 `override` 及配套 `// VTable offset:`，分支全部丢失。两侧构建内确定性均已验证，stderr 索引统计完全一致（差异只在渲染，不在索引）。

## 最终方案

### 根因

Stage 5a 把 `TypeDefinition.index(in:)` 的 `methodDescriptorLookup` / `vtableOffsetLookup` 从 `[Node: …]`（结构相等）换成裸 `[NodeReference: …]`。`NodeReference` 的固有 `Hashable`/`==` 是 **store-identity**（`(store, index)`）。这两个字典的**键**来自 override 描述符的实现符号——`SymbolIndexStore.demangledNodeReference(for:)` 对落在 build sweep 之外的符号会新建 per-symbol mini store——而**查询**用成员符号（主 store）。两者结构相等但 store 不同 ⇒ 查表 miss ⇒ override 与 vtable 注释一起丢。

放大因素：`TypeDefinition.index` 的 offset 兜底表只从 `methodDescriptors` 建，`methodOverrideDescriptors` / `methodDefaultOverrideDescriptors` 未进兜底表，故 override 方法只有 `NodeReference` 一条路，一 miss 即彻底丢失。

数据相关性：iOS 18.5 SwiftData 该类的 override 实现符号恰好落到 mini store；iOS 26.5 同一个类、以及 SwiftUI/SwiftUICore 数百个 override 都在主 store，故只有前者复现。

这正是 `Name` 类型当初改结构语义 `Hashable` 所规避的同一陷阱，但这两个裸字典漏改了。

### 修复

新增 `StructuralNodeReferenceKey`（`package`，`SwiftDeclaration`，照 `Name` 类型用 `structurallyEquals` + `structuralHash`），把这对跨 store 查询字典的键类型改为它，插入端（`TypeDefinition.index` 5 处）与查询端（`DefinitionBuilder` 4 处）统一包装。

**仅动这一对字典**。其余 `NodeReference` 键容器（`accessorsByNode`、`canonicalIndexBy*Node`、`pendingMergedBy*Node`、`visitedNodes`）都在单个 `memberSymbols` 批次内使用（同一 hash-consed store，结构相等即 index 相等），安全，未动。

## 实际执行

1. 枚举全部裸 `NodeReference` 键容器，确认修复范围。
2. 新增 `Sources/SwiftDeclaration/Components/Definitions/StructuralNodeReferenceKey.swift`。
3. `DefinitionBuilder.swift`：8 处签名类型 + 4 处查询点。
4. `TypeDefinition.swift`：2 处局部声明 + 5 处插入点。
5. 因 `package` 函数签名暴露该类型，将其从 `internal` 提升为 `package`。
6. 新增 `Tests/SwiftPrintingTests/StructuralNodeReferenceKeyTests.swift`（4 个用例）。
7. 文档：迁移计划追加「Stage 5a 回归修复」一节；AGENTS.md 补入硬性约定。
8. 建设三源基线（见下）。

## 验证

- **单元测试**：全量 `swift test --skip IntegrationTests` → **1263 tests / 242 suites 全绿**，含直接覆盖此功能的 `outputContainsOverrideKeyword` / `outputContainsVTableOffsetComments`。
- **新增回归测试**：4/4 绿。其中 `structuralKeyDictionaryHitsAcrossStores` 精确复刻生产形态——裸 `NodeReference` 字典 miss、结构键 hit，直接钉住本次 bug。
- **三源快照对比（修复后，main vs 分支）**：

| 来源 | 覆盖 | 结果 |
|---|---|---|
| MachOFile | iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5 / 27.0b1 / 27.0b2 的可用三件套，含全注释变体 | **38/38 逐字节一致** |
| DyldCache | macOS 宿主 cache + iOS 27.0b3 / b4 模拟器 cache 的三件套 | **18/18 逐字节一致** |
| MachOImage | 宿主三件套 in-process 渲染 | **6/6 逐字节一致** |

修复前差异的 2 份现已一致，此前一致的条目全部保持不变。

## 附带产出与发现

### 基线仓库

`MachOSwiftSection-Baselines/main-27726bc/`（62 份快照 + `SHA256SUMS.txt` + 复现 harness + README）。后续优化迭代以此为准做整文件对比。

### 发现：`-n` 名称选镜像会静默选错（既存缺陷，非本次迁移引入）

`DyldCache+.swift` 的名称匹配是 `imagePath.lastPathComponent.deletingPathExtension == name`，而 cache 内叶名并不唯一。iOS 27 模拟器 cache 同时含
`/System/Library/Frameworks/SwiftUI.framework/SwiftUI` 与
`/System/Library/AccessibilityBundles/SwiftUI.axbundle/SwiftUI`，`-n SwiftUI` 命中先枚举到的 axbundle（无 Swift 元数据），dump 输出 0 字节、interface 只剩 4 行 import，**且不报错**。

已验证：macOS 三件套与模拟器 SwiftUICore/SwiftData 的 `-n` 与 `-p` 结果一致，只有 SwiftUI 撞名。基线 harness 已全面改用 `-p` 安装路径。

修复方向（**尚未实施，待决策**）：优先匹配 `.framework/` 路径、或在多命中时报歧义错误而非静默取第一个。

### 差异

- 首轮快照遗漏了 iOS 18.5 二进制是 fat 的事实（需 `-a arm64`），第一次运行 8 个条目全部失败，补 `-a` 后重跑。
- 原计划仅覆盖 18.5/26.5；用户要求扩展到三种来源与更宽版本跨度后，矩阵从 18 份扩到 62 份。
- Image harness 初版用 `.dumper(...).body` 与 `DemangleResolver.default`，均为不存在的 API，改为 `dump(using:in:)` 与 `.using(options:)`。
- Image harness 初版开启 `printMemberAddress`，进程相关地址不可跨运行比较，已关闭。

## 待办

- 是否提交本次修复（工作区改动尚未提交，按约定待用户确认）。
- 是否修复 `-n` 选镜像歧义。
- RV 侧生命周期缺口（`removeSection` 无调用者、`probeTask` 强捕获）——用户已指示暂不处理。
