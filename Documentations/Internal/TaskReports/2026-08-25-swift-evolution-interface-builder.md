# 2026-08-25 · SwiftEvolutionInterfaceBuilder：演进并集注解接口

## 问题

用户诉求：「写一个 SwiftEvolutionInterfaceBuilder，目前的 ABIEvolutionBuilder 输出太难看了」。
`swift-section evolution` 唯一的人读输出是 `ABIEvolutionReporter` 的 lineage 清单
（`[●●○] 名字` + 缩进事件行）：不是代码的形状、成员脱离容器语法上下文、只有变化没有
幸存者。两版本场景已有 `diff --interface`（完整接口 + git-diff 标记），N 版本没有对应物。

## 调研结论

- 两侧注解接口链路（`SwiftDiffableInterfaceBuilder` + `SwiftDiffableInterfaceRenderer`）
  的全部构件可复用：per-member 渲染单元、`HeaderOutcome` 三态失败处理、extension
  容器拆分（`ABIDiffer.extensionContainerKey` 同源）、`DiffMarking` 行拆分。
- `ABIEvolution` 只物化**有事件**的 lineage（changes-only 契约）——这直接决定了
  「注解 = lineage 查表命中，没注解 = 全程未变」的设计成立。
- 快照（`ContainerSnapshot`/`MemberRecord`）只有单行签名字符串，无嵌套、无 printer
  保真度 ⇒ interface 模式必须全二进制输入。
- 快照的 key 构造（容器 `ABIKey.makeUnwrappingType` / `extensionContainerKey`、成员
  `MemberRecord.make*`）与两侧 renderer 的匹配 key 完全一致 ⇒ 活模型渲染 + lineage
  注解可以按 key 无缝 join。
- parameter pack 需要 Swift 5.9 运行时（SE-0393）⇒ 公开 API 中只能作
  `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)` 门控的便利层。
- 模型值不携带 reader 泛型、printer 只以「async 渲染出 `SemanticString`」被消费 ⇒
  非泛型公开类 + 内部擦除无损。

## 定案（三轮澄清提问，前沿收空后确认）

1. 输出形态：并集接口 + 生命周期注解（否：逐 transition 串联、最新版 + since）。
2. 数据来源：全二进制（否：混用降级、纯快照渲染）。
3. CLI：`evolution --interface`（否：新子命令、替换默认输出）。
4. API：公开库 API 落 `SwiftInterface`，`@_spi(Support)` 暴露结构化行流。
5. 注解格式：行尾位图 + 事件短语 + 头部图例（否：纯短语、伪 `@available`）。
6. 无变化声明：渲染但不注解（否：每行位图；`--changes-only` 记为将来方向）。
7. modified：只渲染最新代际 + 变更注解（否：逐代际多行）。
8. 泛型形态：pack 异构 init（门控）+ 同质数组 init 双轨，实现收敛为非泛型类 + 擦除。

提案：`Documentations/Evolutions/draft-swift-evolution-interface-builder.md`。

## 实际执行

- `Sources/SwiftInterface/` 新增五个文件：
  - `EvolutionVersionRendering.swift`：擦除协议 + `EvolutionVersionUnit<MachO>`
    （包 `SwiftDiffableInterfaceBuilder` + 共享其 dispatcher 的 printer）。
  - `EvolutionLine.swift`：公开 `EvolutionAnnotation` / `EvolutionLine`。
  - `EvolutionAnnotationIndex.swift`：lineage → 注解查表（六桶容器 key 合一张表；
    容器空事件返回 nil——member-only lineage 的 header 保持裸）。
  - `EvolutionMarking.swift`：格式层（位图/短语/图例/逐块对齐列 cap 72/超限换行/
    警告尾注）+ `EvolutionContainerAssembler`。注解附着在渲染单元**末行**。
  - `SwiftEvolutionInterfaceRenderer.swift`：N 路归并核心（`matchAcrossVersions`：
    最新版序为脊柱、旧独有按最后存在版本序追加）、header 逐版本回退渲染
    （失败逐个 dispatch `definitionPrintFailed`，全败整体丢弃）。
  - `SwiftEvolutionInterfaceBuilder.swift`：公开类（`@Mutex` 存 prepare 产物）。
- `DiffMarking.splitIntoLines` 从 `private` 放宽为 internal（共享行拆分规则）。
- `EvolutionCommand`：`--interface` flag、与 `--json`/`--summary-only` 互斥、快照
  输入 `ValidationError`、按事件类别着色（removed 红 / modified 黄 / added 绿 /
  注释青）、`--fail-on-breaking` 复用 `builder.evolution`。
- 测试：`EvolutionMarkingTests` + `EvolutionAnnotationIndexTests`（格式层与 join
  规则单测）、`SwiftEvolutionInterfaceBuilderTests`（三版本即时编译 fixture 端到端：
  图例、四类注解、未变声明裸行、并集排序、结构化流轴对齐、notPrepared/入参校验、
  N==2 与两侧 diff 故事一致）、`EvolutionCommandValidationTests`（CLI 校验钉子）。

## 验证

- 新增 4 个 suite 共 30 tests 全绿（`swift test` 原始退出码 0，按规矩不认 xcsift 摘要）。
- 受影响三个 target（SwiftInterfaceTests / SwiftSectionCommandTests / SwiftDiffingTests）
  全量回归（见本批次 push 前的运行记录；worktree 无 `.package.env`，走远程 pin，
  fixture DerivedData symlink 自主检出）。
- CLI 手动端到端：三个 fixture dylib 跑 `evolution --interface`，输出与设计逐项吻合
  （对齐列、位图、removed 容器整体渲染、memberwise `init` 以 removed+added 呈现
  字段改型的涟漪——不同 mangled 签名即不同 ABI 入口，符合 differ 语义）。

## 与方案的差异

- `evolution` 属性定为 `ABIEvolution?`（prepare 前 nil），提案写的是非可选——可选
  更诚实，避免未 prepare 时 crash 或空值捏造。
- 渲染入口 `printAnnotatedInterface()` / `annotatedBlocks()` 增加 `throws`
  （`SwiftEvolutionInterfaceBuilderError.notPrepared`），同因。
- 注解附着点从提案的「首行」细化为「末行」：printer 在成员声明行上方发注释行、
  容器 header 末行是 `{` 行，末行才是声明本体。
- 提案预告的「实现说明单独成篇」改为在 `ABIEvolutionDesign.md` 追加「第五批」一节
  ——耦合点全部在与 evolution 模型的契约上，与既有增量批次同处一文更利检索。
- 输出中发现 extension 里多行 accessor 块（`hashValue { get }`）缩进偏深，与既有
  `diff --interface` 路径行为一致（printer 交互，非本改动引入），不在本批修。
