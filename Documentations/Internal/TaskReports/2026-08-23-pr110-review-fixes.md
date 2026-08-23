# 2026-08-23：PR #110 review 修复（内置资源移除 + 发现 3–7）

## 问题

并行 review 会话（machoswiftsection-27）对 PR #110（`feature/type-indexing-revival` → `next`）提出 15 条发现并逐条做了四问核实。核心教训：PR 分支当时全套 1466 测试全绿，但该修的 7 条**没有一条会被现有测试抓到**——新代码测试只覆盖纯函数（提取器 / APINotes / 合并优先级 / 缓存 roundtrip），装配与分发路径完全空白。原始清单与全部处置状态见 [Roadmaps/2026-08-23-pr110-review-findings.md](../../../Roadmaps/2026-08-23-pr110-review-findings.md)。

## 抽查核实（在 review 会话的实测之上二次确认）

- 发现 5（死循环）：`swift -e` 最小复现，`.hidden` 经 `deletingPathExtension` 五轮不动点，`while name.contains(".")` 永真——证实。
- 发现 1（构建 flag）：`USE_CUSTOM_OBJC_SECTION=0` 切 p-x9 上游后 `ObjCIndexing` product 不存在——结构性必然，证实。
- 发现 4 / 7：代码直读证实（catch 后无条件 `cache.store`；`for await` 完成序 + 后写覆盖）。
- 发现 2（`Bundle.module` fatalError）：SwiftPM 生成 accessor 的已知行为，候选路径只有 main bundle 旁与编译期烧死的构建目录。

## 用户裁定与执行

用户裁定：「3,4,5,6,7 直接修，不要内置资源」。

1. **内置资源层整体移除**（发现 2 的结构性消解）：删 `Sources/TypeIndexing/Resources/`（AttributeGraph 内置包）与 `Package.swift` 的 resources 声明；`SupplementaryAPINotesLoader` 只保留用户路径枚举（`builtinFiles()` 删除）；`TypeDatabase.index()` 只加载 `supplementaryAPINotesURLs`。提案 0009 的「提议方案 B.1（库内置包）」作废（决策日志已记）；AttributeGraph 样例移入公开指引 [SupplementaryTypeMappings.md](../../SupplementaryTypeMappings.md)（改写为纯用户自备叙事）。
2. **发现 3**：CLI 在 provider 依赖解析结果为空时 fputs stderr 警告（非 macOS 二进制对宿主 dyld cache 的典型症状是 install name 精确匹配全 miss、功能静默不干活）。
3. **发现 4**：`ModuleInterfaceIndexer` 任一 submodule 生成失败时本轮照常返回 entry 但**不写缓存**（缓存无完整性标记，写了就把缺口固化到 SDK/generator 版本变化）；sourcekitd 调用提炼为 `InterfaceGenerator` 闭包注入缝（公开 init 语义不变），`SDKSettings` 加直接赋值测试口。
4. **发现 5**：`moduleName(forImagePath:)` 剥除循环加不动点守卫（`strippedName != name` 且非空才继续）。
5. **发现 6**：CLI 对每个 `--supplementary-apinotes` 路径预检（存在性 + 单文件试解析）并 fputs 警告；目录内坏文件仍走库内 skip-and-log 契约。
6. **发现 7**：task group 结果经 `entriesInDiscoveryOrder`（新 package static 纯函数）按 SDK 发现序重排后注册，恢复 searchPaths 优先序的跨运行确定性。

未处理（用户批复未点名）：发现 1（候选修法：flag=0 时条件剔除 TypeIndexing）、发现 15（deprecated 旧签名转发）、发现 8 的注释措辞、发现 9/10 的低优先级待办——状态均记入 findings 文件。「不修 / 误报」终审 5 条（8/11/12/13/14）进 [ReviewAdjudications.md](../ReviewAdjudications.md) A13–A17。

## 验证

- 新增回归测试 5 条：`leadingDotImagePathsTerminate`（发现 5）、`collectedEntriesAreReorderedToDiscoveryOrder`（发现 7）、`ModuleInterfaceIndexerTests` 三条（发现 4：partial 不缓存 / 完整缓存 / 全败零缓存）。
- `SupplementaryAPINotesTests` 重写为纯用户自备叙事：AG 三形态数据流改从临时文件加载（三形态断言全保留），内置包加载测试删除。
- TypeIndexingTests：37 tests / 7 suites 全绿；全套 `--skip IntegrationTests` 1470 tests / 277 suites 退出码 0。
- e2e（AG probe）：不带 `--supplementary-apinotes` 时 AG 类型保持 `__C.`（库确无内置映射）；带用户文件时全部引用解析为 `AttributeGraph.Graph`/`.Subgraph`，与移除前输出一致。

## 与方案的差异

呈报方案中发现 2 的推荐修法是「内嵌字符串常量」；用户裁定更进一步——不内置任何映射，让用户自己提供。比内嵌更彻底：resource 分发、内置内容的证据审查负担、库体积全部消失，代价是开箱不再自带 AttributeGraph（样例 YAML 完整保留在公开指引里，用户复制即用）。
