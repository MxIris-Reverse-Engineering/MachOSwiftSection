# 2026-08-08 MetadataReaderCache 清退（class Node 树缓存换持 NodeReference）

## 问题

`SharedNodeStore` 迁移（同日上一批）把 `NodeStore` 实例从 14,451 砍到 15，但 RV 五镜像复测里存活的 class `Node` 几乎没动：208,809 → 207,489。两侧会话独立扫描一致归因：约 89%（~18.4 万棵树）被 `Sources/SwiftInspection/MetadataReader.swift` 里的 `MetadataReaderCache.Storage` 永久持有——三张字典（mangled name / context offset / symbol 名）的 value 都是整棵 class `Node` 树，private 单例、`SwiftDeclarationIndexer` 的按镜像清理够不到它、树全部经 transient 构造所以零 hash-consing 共享。用户经 swift-demangling 会话下达指示：这套 NodeStore 体系之前的旧式简单缓存去掉，方案按本仓库规矩走。

## 调研

- 调用面：Sources 内 36 个文件 103 处调用 `MetadataReader.demangleType` / `demangleContext` / `demangleTypeUncached`（对面报 112，差额是测试目标），全部消费 `Node` 返回值。
- 上游能力核实：`NodeReference.materialize()` cache-free 且按 index 记忆化**保 DAG 共享**（`NodeStore.BufferView.materializeNode` 显式栈 + memo）；`InternedNodeReferenceCache` 的镜像/进程两个作用域接口即为 metadata 派生树设的（AGENTS.md 既载模型）；`SharedCache.remove(for:)` 本就存在，缺的只是公开 seam。
- 身份稳定性排查（换掉共享实例唯一可能破的面）：全库按 `ObjectIdentifier` 键控 `Node` 的只有 `SwiftPrinting` 的 `printCache`——单次 `printRoot` 内存活，依赖的是同一棵树内的 DAG 共享，物化保共享故不受影响；`RuntimeFieldLayoutBackend:223` 的 `ObjectIdentifier(metatype)` 是 runtime metadata 指针，与 `Node` 无关。
- 对面「`MultiPayloadEnumDescriptorCache` 的 `[Node: …]` 键必须同批改」的判断**证伪**：上游 `Node+Hashable.swift` 的 `==`/`hash` 是全子树结构摘要（DAG 记忆化），实例身份只是快路径；换后端后跨实例照常命中。对面复核后接受（「你们对、我错」口径回执）。

## 最终方案

设计文档 [MetadataReaderCacheRetirement.md](../MetadataReaderCacheRetirement.md)（Draft → 用户批准 → 同日 Implemented）：三张字典载荷换 `NodeReference` / `NodeReference?`，miss 时 intern 进 `InternedNodeReferenceCache` 对应作用域（与声明模型的同批树去重共享），hit 时 `materialize()`；`nil` 拒绝裁决用 `updateValue` 显式写入（subscript 赋 `nil` 会删键）；新增 `MetadataReader.removeCache(for:)` 接进 `SwiftDeclarationIndexer.deinit` 的按镜像清理；公开 API、`isCacheEnabled`、`demangleTypeUncached`、103 处调用点全部不动。被否方案：彻底删除（CPU 回归换不来更多内存）、API 改返回 `NodeReference`（103 处调用点连锁改动，内存收益相同）。

## 实际执行

按方案原样落地，无偏差。改动面：`MetadataReader.swift`（Storage + 六方法 + 类文档 + seam）、`SwiftDeclarationIndexer.swift`（deinit 一行 + 注释）、AGENTS.md 两处、文档四篇（设计文档、演进日志第 33 节、README 索引、内存足迹文档后记）。

## 验证

1. 全量 `swift test --skip IntegrationTests`：**1337 tests 全绿、0 失败**，与改动前完全同数。
2. 渲染 A/B（`Scripts/run-rendering-ab-verification.py`，baseline `ed2f4d1`）：**96 对全部逐字节一致、零跳过**（当前系统 dyld cache + 七个模拟器 runtime + in-process MachOImage，dump + interface）。
3. 性能：脚本 72 对场景总耗时 1150s vs 1148s（±0.2%）；iOS 18.5 模拟器 SwiftUI `interface` 三轮交错受控测量中位 71.3s vs 70.9s——hit 物化代价不可感知。
4. RV 五镜像 memory graph 复测待对面协调（预期 207,489 → ≲23,000），结果补记进设计文档。

## 偏差与附带发现

- 方案本身零偏差。
- **附带踩坑**：A/B 首跑基线 release 构建失败（`NodeStoreBuilder has no member reserveCapacity`）——全新 scratch 用当前环境重新求值 manifest，`USING_LOCAL_DEPENDENCIES` 未置位导致 swift-demangling 静默回落远端 0.5.1；旧 scratch 靠早前会话的 manifest 求值缓存一直没暴露。本地 sibling 生效是「兄弟目录存在 + 环境变量」双条件。已补进 AGENTS.md 环境漂移检查第 2 条（诊断：`workspace-state.json` 的 `packageRef.kind` 读 `fileSystem` 还是 `remoteSourceControl`），A/B 带 `USING_LOCAL_DEPENDENCIES=1` 重跑通过。
