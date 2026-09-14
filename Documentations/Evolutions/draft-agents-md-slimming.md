# Draft - AGENTS.md 瘦身：指令文件回归指令，架构细节回归文档

- **状态**: Implemented
- **创建日期**: 2026-09-14
- **最后更新**: 2026-09-14
- **配套文档**: 新增四篇模块参考文档——[Modules/SwiftLayout.md](../Internal/Modules/SwiftLayout.md)、[Modules/SwiftThunkAnalysis.md](../Internal/Modules/SwiftThunkAnalysis.md)、[Modules/MachOSymbols.md](../Internal/Modules/MachOSymbols.md)、[Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)

## 摘要

`AGENTS.md`（`CLAUDE.md` 是它的符号链接，Claude Code 与 Codex 共用同一份）已经长到 528 行 / 177 KB，约 4.4 万 token，每次会话全量常驻。体积的 68% 集中在 `### Core Modules` 一节（122 KB），其中 `SwiftThunkAnalysis` 一个 bullet 占 28 KB、`SwiftLayout` 占 27 KB——内容是历次演进提案结论的完整复述，包括各批次的时间线、实测数字和修复经过。

这既违反项目自己的文档分工约定（`Internal/Modules/README.md`：「已有专题文档覆盖的子系统写导读并链接，**不复述**」），也在两个 harness 上都产生实际损害：Codex 对超出预算的项目文档是**截断**而非弱注意，切点不可控，被切掉的部分等于不存在；Claude Code 注入时附带「可能与你的任务无关」的免责声明，无关内容越多，连要紧的规则一起被跳过的概率越高。

本提案把 `AGENTS.md` 压到约 20 KB：保留身份、模块依赖图、全部命令、每模块 2–3 行职责摘要，以及全部「不知道就会静默做错」的硬陷阱；砍掉的细节先逐段核对，确认已被 `Internal/` 或 `Evolutions/` 覆盖的直接换成链接，只在 `AGENTS.md` 出现过的事实先补进对口文档再删。

## 方案

### 目标形态

按 `<important if="...">` 条件块组织（系统提示自身使用的 XML 形状，对 Claude Code 是 harness 级相关性信号；对 Codex 无害，Codex 主要靠目录作用域与长度）。无条件常驻的只有三样：项目一句话定位、模块依赖图、每模块 2–3 行职责与边界。

条件块清单，一块一个触发条件，绝不把互不相干的规则并进一个宽条件：

| 触发 | 内容 |
|---|---|
| 构建 / 测试 / 运行 | 全部命令一条不少、工具链下限、`IntegrationTests` 禁跑、渲染 A/B 验证脚本及其自测脚本 |
| 写测试 | 512 KB 协作线程与大栈执行器、即时编译 fixture 必须含一个 class、共享 fixture 镜像双向声明 `ExclusiveImageAccess`、arm64e PAC 在 `swift test` 里不生效 |
| 快照 / 基线转红 | 三条环境漂移检查（fixture 二进制陈旧 vs. 缺失、兄弟依赖静默回落远端、`CODE_SIGNING_ALLOWED=NO` 平移实现偏移） |
| 动 demangler / node / 符号索引 | `Node` 迭代器语义、`NodeReference` 的 store-identity 陷阱、`detachedFromSharedTable()`、transient demangle、`swift package clean` |
| 动 ABI 层 wrapper | `@LocatableLayoutWrapping`、`@dynamicMemberLookup` 转发属性、`resolvedDirectOffset(from:)` 的 key path 约束 |
| 读 dyld cache 偏移 | 三套 accounting 的口径差异 |
| 写日志 | `@Loggable` 规则、泛型走 protocol 形式、库代码不写进程流 |
| 加公开方法 / 改 fixture | 覆盖率不变式五步、`regen-baselines` 调用姿势 |
| 写文档 / 收尾 | 四类文档分工、Evolution 提案制、文档与代码同批次 |

### 判据：什么留在指令文件里

留下的标准是**「不写在这里，agent 就会静默做错」**——不是「少了个提示」，是真的会做错事且不会立刻发现。历史叙事、实测数字、某个 bug 的修复经过一律不留：它们是提案与 task report 的内容，对「现在该怎么做」没有约束力。

### 信息去向

逐段核对，不做盲删。每个待删段落先在 `Documentations/` 下检索其关键标识符与结论：

- 已被 `Internal/*.md` 或 `Evolutions/*.md` 覆盖 → 直接删，`AGENTS.md` 留摘要 + 链接；
- 只在 `AGENTS.md` 出现过 → 先补进对口专题文档，再删；
- 按 `Internal/Modules/README.md` 的待写表，为细节最多且无单一归宿的模块补模块参考文档。

### 未询问即采用的假设

- 条件块用 XML 标记而非普通小标题。
- 模块依赖图原样保留——它对几乎每个任务都相关，属于基础上下文。
- 不新建项目级 skill：留下的硬陷阱恰恰是「没有可靠触发词、不写就会做错」的那一类，放进需要被主动召回的 skill 反而会漏。
- 不动任何源码，不改现有文档的既有内容（只增不改）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-14 | Created as Draft | 用户提出 `AGENTS.md` 体积过大，要求优化 |
| 2026-09-14 | 目标体积定为约 20 KB（而非激进的 10 KB 或保守的 40 KB） | 20 KB 能同时容纳每模块的职责摘要与全部硬陷阱，Codex 读得完；10 KB 要牺牲模块边界摘要，导致很多任务开头得多读一份文档；40 KB 仍有被 Codex 截断的风险 |
| 2026-09-14 | 逐段核对后补写，而非整段原文归档 | 原文归档会产生一份与现有专题文档大量重复、无人维护的大杂烩；核对补写虽慢，但结果符合项目既有的文档分工约定 |
| 2026-09-14 | 核对结论：零独有事实 | 930 个标识符全量检索 + 13 项关键结论人工核查，架构章节的每一条都能在 `Internal/` 或 `Evolutions/` 找到出处，因此不需要「先补后删」，只需留摘要 + 链接 |
| 2026-09-14 | 留存判据从「重要的事实」收紧为「不写就会静默做错的操作」 | 反向扫出 93 条告诫语句后发现，按前一种判据几乎什么都该留；按后一种能筛出确定的 41 条，并额外提升了 8 条原先埋在长段落里、按模块摘要方式会一起丢掉的陷阱 |
| 2026-09-14 | 四篇模块文档写成导读型而非从零的深度文档 | `Modules/README.md` 的写作约定就是「已有专题文档覆盖的写导读并链接，不复述」；`StaticLayoutEngine.md`（87 KB）与 `AccessorThunkResolutionExplained.md`（38 KB）已覆盖细节，导读层接住的是被删掉的中间层结论 |
| 2026-09-14 | 实际落在 30 KB 而非预估的 20 KB | 预估偏低：硬陷阱清单经反向扫描后从 33 条涨到 41 条，模块摘要与三条环境漂移检查也比预估密。内容范围与批准的方案一致，未额外收录历史叙事或实测数字 |
| 2026-09-14 | 状态置为 Implemented；无新术语需要登记 | 纯文档重组，未引入项目术语；配套文档已在头部登记 |
