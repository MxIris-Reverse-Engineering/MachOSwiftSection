# 2026-08-26：issue #115（同名私有类型成员混入）与 #116（pack 结构体偏移误降级）修复

## 问题

外部（Kyle-Ye）同日报告两个问题：

- **#115（bug）**：`swift-section dump` 对同名但私有判别符不同的类型
  （SwiftUI 的 `(ArchivableDisplayList in _6FA…)` / `(… in _AEFE…)` 两对），把双方的
  init（Allocator）与方法（Function）互相混入对方声明，双向重复。0.14.0 起即可复现。
- **#116（enhancement，标签如此、实为正确性收窄）**：0.16.0 对 C-imported struct 的
  保护（commit `5a6d5b0`）在结构化累加与 `__swift5_builtin` 记录的 size/stride/alignment
  任一不等时把全部字段降级为 `unknown`。`CMTime` 在 `#pragma pack(push, 4)` 下只有聚合
  alignment 不同（4 vs 自然值 8），偏移 0/8/12/16（Clang 布局实证）被整体误降级；
  0.14.0 曾正确输出。

## 调研（关键取证）

- **#115 根因**：成员索引三层结构 `[MemberKind][打印名 String][interned 上下文节点] → 符号行`，
  打印名用 `.interfaceTypeBuilderOnly` 生成，而 `.interface` 系列移除了
  `.showPrivateDiscriminators`（`swift-demangling` `DemangleOptions.swift`）——同名私有类型
  塌进同一个 name 桶，只有第三层节点能区分。dump 三个 dumper 走 name-only 重载
  （`SymbolIndexStore.swift` 的 `memberSymbols(of:for:in:)` 把桶下全部子桶拍平），interface
  路径（`TypeDefinition.index`）一直走带 `node:` 的重载所以正确——与 issue 只报 dump 一致。
- **四问**：可复现（代码层确凿 + fixture 红测试双向混入）；非回归（dump 路径从未区分过，
  报告者证实 0.14.0 已有）；值得修（错误归属直接误导逆向分析，大框架必中）；未修过
  （Stage 5a 修的是 interface 路径 store-identity 键的另一类归属病，dump 路径不在当时范围）。
- **横向排查同类**（一个问题确认为真后全库搜同模式）：interface 路径仍有三处 name-only——
  `TypeDefinition` 的 deallocator/destructor `.first`、`applyThunkAttributes`（thunk 桶无节点层 +
  成员名字符串匹配）、`typeInfoByName` last-wins（`indexExtensions` 判扩展目标 kind）。一并纳入。
- **#116 根因与收窄论证**：`StaticLayoutCalculator.fieldLayout(ofStruct:)` 的三项全等 guard。
  报告者建议「size/stride 相等、只差 alignment 就放行」；推导后改用更强的**紧密排列证明**：
  每字段偏移 == 前序字段 size 累计和，且累计和 == builtin 整型 size ⇒ 两边都零 padding、
  零隐藏存储，且 C 不重排字段 ⇒ 偏移被唯一确定。宽条件在 bitfield/隐藏字段与 pack 叠加的
  构造性极端情形下无法证明；紧条件还不依赖 size/stride 逐项相等（顺带覆盖 pack 后尾部
  padding 缩小的变体）。`Decimal`（可见字段和 16 ≠ 20）、`PathData`（无记录）通不过证明，照旧降级。

## 最终方案

- **#115**：查询侧带 node，不改 name key 格式（改 key 会波及 `typeInfoByName`、
  `excluding:` 集合与 RuntimeViewer 等消费者，收益与查询侧等价）。dump 三个 dumper
  demangle descriptor 上下文节点改走 `node:` 重载（demangle 失败回退 name-only，宁合并不丢）；
  新增 `methodDescriptorMemberSymbols(of:for:node:in:)`；thunk 索引与 `typeInfoByName`
  补第三层节点 key 并新增 `node:` 重载；三处漏网改接。name-only 重载保留为文档化聚合语义。
- **#116**：guard 的不一致分支前插 `fieldOffsetsProvenByTightPacking`，通过则保留字段偏移、
  整型事实（size/stride/alignment/XI）取 builtin。

## 实际执行

- 源码：`SymbolIndexStore.swift`（索引结构、sweep、四个 node 重载、`TypeInfo.Kind: Equatable`）、
  `StructDumper` / `EnumDumper` / `ClassDumper`、`TypeDefinition.swift`、
  `SwiftDeclarationIndexer.swift`、`StaticLayoutCalculator.swift`。
- fixture（`SymbolTestsCore` 同步组，免改 pbxproj）：`PrivateDoppelgangers.swift` +
  `PrivateDoppelgangersSecondFile.swift`（两文件各一个顶层 `private struct PrivateDoppelganger`，
  成员集不相交 alpha*/beta*）、`ForeignPackedTime.swift`（`CMTime` 字段把 `__C.CMTime`
  descriptor + builtin 记录拉进 fixture 二进制）。**防优化两件套**：`@_optimize(none)` 保
  未特化成员符号（否则 Release 只剩 `Tf4nd_n` 特化 thunk，索引不识别）；anchor 装箱 `Any`
  保 descriptor（首版 fixture 实测私有类型被整个优化删除，`nm` 取证）。
- 测试：`PrivateTypeMemberAttributionTests`（断言式复现）、
  `ForeignStructTopLevelLayoutTests.packedForeignStructKeepsDerivableFieldOffsets`、
  三个新 dump 快照 + coverage 名册登记、`typeInfoLookupMatchesIndexedNames` 升级为双路径校验、
  全模块 interface 快照重录（diff 纯增量 36 行，同时钉住 interface 路径归属正确与
  `ForeignPackedTimeContainer` 嵌套布局 24/24/align4、Double@0x18）。
- 基线：fixture 重建后 `regen-baselines` 全量重生成，diff 59 文件 97 行**全部为偏移值漂移**
  （逐行 grep 验证零非 offset 行）。
- 文档：`AGENTS.md`（MachOSymbols 不变量 + SwiftLayout 收窄）、`StaticLayoutEngine.md`、
  新增 `PrivateTypeMemberAttribution.md` + README 索引登记、`ProjectEvolutionLog.md` 第 43 节。

## 验证

- **红→绿**：`git stash push -- Sources` 后跑两条新测试——#115 四条 `!contains` 断言全红
  （alpha dump 含 beta 成员、反之亦然），#116 偏移全 0、resolution 全 unknown（5 issues）；
  `stash pop` 后同测试全绿，`Decimal` 降级回归测试保持绿（防放宽过头）。
- **预改动环境基线**：worktree（远程 pin，等价 CI）+ 自建 fixture 先跑全量 1439 tests，
  仅 2 个已知 flaky 墙钟并发测试失败（`differentKeysParallelVia*`，记忆有档），排除环境漂移。
- **全量**：修复 + fixture + 基线重生成后 `swift test --skip IntegrationTests` 复跑，
  1444 tests / 272 suites，仅上述 2 个 flaky 失败（与预改动基线完全一致）；两者随后
  按记忆惯例单独过滤复跑全绿，确认非回归。

## 与计划的偏差

- 首版 fixture 只有 `@inline(never)`，Release 下私有类型 descriptor 被整个优化删除、init 只剩
  特化 thunk——加 `@_optimize(none)` 与 `Any` 装箱后二进制取证齐全。此教训已写进
  `PrivateTypeMemberAttribution.md`。
- 快照录制即验收（`record: .missing` 首跑记录并标红），故 #115 的红色证据由断言式测试
  单独承担，快照只做长期钉死——与「修复必带复现测试」的红绿闭环不冲突。
