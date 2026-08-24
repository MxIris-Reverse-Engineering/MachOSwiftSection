# 2026-08-24 — opaque 返回类型 primary associated type 归属修复（提案 0011）

## 问题

用户复查 fixture 时指出 `functionNested` 的 SwiftInterface 输出把 `some Sequence<[A]> & Equatable`
打成 `some Swift.Equatable<[A]> & Swift.Sequence<[A]>`——`Equatable` 没有任何 associated type，
`<[A]>` 是非法 Swift。用户记忆中的成因是「二进制信息不够，必须追到 libswiftCore」。

## 调研（关键取证）

- 直接逐字节解析 fixture 二进制的 opaque type descriptor（符号 `…lFQOMQ`，偏移 `0x42fa8`，
  13 条 generic requirements），确认三件事：
  1. same-type 约束的 subject **带 anchor 协议**（`7ElementSTQyd__` = `τ_1_0.[Swift.Sequence]Element`），
     「信息不够」的旧印象部分失实——anchor 身份不缺，丢它的是 provider 收集阶段
     （`SwiftInterfaceBuilderOpaqueTypeProvider.swift` 旧 `:53-54`）。
  2. **等价类塌缩**是真实信息丢失：源码两处 sugar（`Collection<[A]>` 与 `TestCollection<[A]>`）
     在 descriptor 里只剩 anchor=Sequence 的一条约束。
  3. anchor 会越过组合成员落在 refine 链上层（Collection 的约束 anchor 是 Sequence，而
     Sequence 不在组合里）——「追 libswiftCore」的真实出处是 **refine 关系**，不是 anchor。
- demangler 侧确认 `dependentAssociatedTypeRef` 保留 `[identifier, protocol]` 两个 child
  （sibling `swift-demangling` `Demangler.swift:710`）。
- primary 标记运行时元数据不存在（SE-0346），内置表按本机 `swift-6.3.2-RELEASE` 源码树
  （`/Volumes/SwiftProjects/swift-project/swift`）核对；Concurrency 协议 demangle 在
  `Swift` 模块下（`$sSciMp` → `Swift.AsyncSequence`）。

## 最终方案

提案 0011（两轮澄清提问后立项，状态机走全程）：归属四步（anchor 直接命中 → refine 闭包 →
名字兜底 → 缺信息不挂）+ 三层协议事实解析链（本模块 descriptor → 内置 stdlib 表 →
进程内跨镜像），离线依赖闭包出参、另立后续提案；接受两种 reader 输出深度差异。

## 实际执行

- `Sources/SwiftInterface/` 新增 `OpaqueSameTypeConstraint.swift`、`ProtocolFactsResolver.swift`、
  `BuiltinStandardLibraryProtocolFacts.swift`，provider 收集阶段保留 anchor、裁决阶段替换
  无差别分发。
- fixture：`Protocols.swift` 加 `UnpinnedElementProtocol` / `ModuleBaseProtocol` /
  `ModuleRefinedProtocol`；`SymbolTestsHelper` 加 `HelperBaseProtocol` / `HelperRefinedProtocol`；
  `OpaqueReturnTypes.swift` 加三个 witness struct 与 `functionNameFallbackGuard` /
  `functionModuleRefineClosure` / `functionCrossImageRefineClosure`。
- 测试：E2E 断言收紧（`functionNested` 三个 opaque 精确串 + `!contains("Swift.Equatable<")`），
  修正把错误输出当预期的注释（原 `:159`）；新增 MachOImage 侧 `OpaqueAttributionImageE2ETests`
  （跨镜像挂 `<Swift.Int>` + 与离线一致性）；interfaceSnapshot 因 fixture 新符号重录
  （diff 纯新增 40 行，既有行零改动）。
- 文档同批：提案原地更新（Accepted → 实施期精化 → Implemented）、实现说明
  `OpaquePrimaryAssociatedTypeAttribution.md`、AGENTS.md SwiftInterface 段、
  `Documentations/README.md` 索引、ProjectEvolutionLog 第 28 节、本报告。

## 验证

- 离线（MachOFile）四场景 CLI 与 E2E 全部符合预期：Equatable 不再带参数；Sequence anchor
  直接命中；Collection 经内置表 refine 闭包；TestCollection 经名字兜底恢复；UEP 不被捏造；
  模块内 refine 闭包挂 `<Swift.Int>`；跨镜像离线诚实降级。
- 进程内（MachOImage）：跨镜像 refine 闭包挂 `<Swift.Int>`（第三层实测工作，
  `SymbolOrElement.resolve` 只在 MachOFile 分支查 bind，进程内永远解析到 descriptor）。
- 全量 `swift test --skip IntegrationTests`（结果见提案落地步骤勾选）。

## 与计划的偏差

1. **名字兜底加「anchor 在组合外」判据**（实施期发现）：塌缩恢复与「同名 assoc 未被 pin」
   在 descriptor 里逐字节同形，原规则会给未 pin 成员捏造 sugar（`UnpinnedElementProtocol<[A]>`）。
   纯保守收紧，`TestCollection<[A]>` 恢复不受影响；已回写提案决策日志与规则 3。
2. **三层解析链在实现里塌成两问**：`resolvedContent(in:)` 已统一「同镜像 symbolic ref」与
   「进程内跨镜像间接指针」两种可达性，`ProtocolFactsResolving` 协议 + 三实现的提案形态
   徒增间接，改为单 `ProtocolFactsResolver` struct；记入实现说明「与提案的差异」。
3. **歧义场景（同名不同值双 pin）未做成 fixture**：一个类型对同名 associated type 只能给
   一个 witness，合法 Swift 里几乎构造不出「同名不同值」的 opaque 组合；歧义分支由
   「兜底防捏造」场景覆盖其保守面，`candidates.count == 1` 的判定保留为纵深防御。
