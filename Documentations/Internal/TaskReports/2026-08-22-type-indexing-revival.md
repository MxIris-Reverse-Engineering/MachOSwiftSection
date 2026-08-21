# 2026-08-22 TypeIndexing 重启：`__C` 模块归属解析

> 提案：[Evolutions/0008](../../Evolutions/0008-type-indexing-revival.md)（In Progress → Implemented）。实现说明：[TypeIndexingPipeline.md](../TypeIndexingPipeline.md)。分支 `feature/type-indexing-revival`（基于 `next`，独立 worktree，用户裁定）。

## 问题

`Sources/TypeIndexing`（把 `__C.NSString` 恢复成 `Foundation.NSString` 的模块归属索引）自 Swift 6 迁移期起被整体注释出 `Package.swift`。打印侧挂接点（`NodePrintable.printModule` 的 `moduleName(forTypeName:)` delegate）一直是活的，但唯一的 provider 实现躺在不编译的 target 里，所有 `__C` 类型原样打印。用户要求修复重启，并追加两条裁定：旧的 `ObjCInterfaceIndexer` 删除（MachOObjCSection 已有 `ObjCIndexing` 索引 API）；SwiftSyntax 不得作为运行时依赖进来（体积暴增）。

## 调研结论（详见提案「前期调研」）

- **禁用主因**：`SDKIndexer.index()` 在 SDK 扫描时对每个 `.swiftmodule` 当场跑 sourcekitd 生成全模块 interface——数百模块全量生成、依赖过滤在其后才生效，首次索引小时级。
- **正确性 bug 一串**：APINotes 双向表把 `moduleName` 字段写成 swiftName；`SwiftModule.write` 写错路径；SwiftSyntax 解析器不认 `extension Foo { struct Bar }` 嵌套（键错误）；缓存不带 SDK 版本（Xcode 升级吃旧数据）；sourcekitd 路径硬编码 `/Applications/Xcode.app`。
- **体积发现**：swift-syntax 在包里只喂 `MachOMacros` 宏插件（编译期产物），TypeIndexing 把它变成运行时链接才是体积引入点；而 `TypeDatabase` 对解析结果的全部消费只有类型名清单——语法树解析是杀鸡用牛刀。
- **闸门实测**（scratchpad 探针包）：SourceKitD 0.1.0 与 swift-apinotes 在 Swift 6.2 编译通过；`editor.open.interface` + `key.enablesubstructure` 返回完整结构树（kind + name + 嵌套 + extension）；APINotes 解析真实 `Foundation.apinotes` 正常。

## 最终方案

提案 0008 五块：A 发现与生成分离（过滤前移 + per-module 按 SDK 构建分层的 JSON 缓存）；A′ 类型名提取走 sourcekitd substructure（零 SwiftSyntax，值树 + 纯函数提取器）；B 删自建 ObjC 索引器、接 MachOObjCSection `ObjCIndexing` 懒索引；C 正确性逐条修；D `@Loggable`/`#log` 规范整改 + 移除 `PrintFailureEventTests` 豁免；E `Package.swift` 恢复 + CLI `--resolve-c-module-names` + 测试分层。

## 实际执行

- 删除 `ObjCInterfaceIndexer.swift` / `SwiftInterfaceParser.swift` / `SwiftModule.swift`；重写其余全部文件，新增 `InterfaceDeclarationNode` / `InterfaceTypeNameExtractor` / `APINotesIndex` / `ModuleIndexCache` / `ModuleInterfaceIndexer`。`TypeDatabase` 改为 actor，三个 `register` 步骤公开为 package API（合并优先级可脱离 sourcekitd 单测）。
- `Package.swift`：恢复 target / product / `TypeIndexingTests`；新增 SourceKitD 与 swift-apinotes（macOS 条件）；`swift_section` 与 `IntegrationTests` 挂上 TypeIndexing。本 worktree 基点的 MachOObjCSection 下限已是 0.8.105（泛型 `ObjCMetadataSource` indexer 所需）。
- CLI：`interface` 命令新增 `--resolve-c-module-names`（默认关，默认输出不变）；警告走 `fputs`（第一版误用 `FileHandle.standardError.write(_:)`——项目明令禁止的 raising 重载，当场改正）。
- 测试：`TypeIndexingTests` 23 个纯单测（提取器 / import 扫描 / APINotes 双向表与归属 / 合并优先级 / 缓存 roundtrip 与版本失效）；`PrintFailureEventTests` 的 `SDKIndexer.swift` 豁免移除；IntegrationTests 新增维护者手动端到端（`TypeNameProviderTests`）。
- 文档：提案原地推进 + 决策日志（含编号 0006 → 0008 避让 `main` 并行提案占号）；`TypeIndexingPipeline.md`；AGENTS.md 架构节；`Documentations/README.md` 索引；本报告。

## 踩坑记录

- **`@Loggable` 直接类型形态在 `@available(macOS 13.0, *)` 类型上编不过**：宏展开的 static stored `logger` 自带 availability 标注，单 target 编译只是 warning，整包 emit-module 时升级为 error（"cannot be more available than enclosing scope"）。全模块改 protocol 形态（protocol 不标 availability、conformance extension 标）。已写进实现说明与 AGENTS.md 条目。
- **并行会话占号**：实施当天 `main` 上另一会话登记了 0005–0007 三个 Draft，与本案的 0006 撞号（其 0005 也与 `next` 已有的 0005 互撞——既有漂移，非本案引入，留待两线合并裁决）。本案避让至 0008。
- **worktree 环境**：fixture `DerivedData` 是 gitignored 机器状态，worktree 里缺失；本分支对 `Tests/Projects/` 无 diff，按 AGENTS.md 指引 symlink 主 checkout 的副本。

## 验证

- 整包 `swift build` 通过（零 error）。
- `TypeIndexingTests` 23/23 通过；`PrintFailureEventTests` 豁免收紧后 7/7 通过（新模块过两道源扫描）。
- 端到端（fixture `SymbolTestsCore`，依赖面 Foundation + overlays）：baseline 21 处 `__C.` → 加 flag 后 **0 处**，diff 全部行都是模块名替换（`Foundation.NSObject` / `CoreFoundation.CFStringRef` / APINotes 改名的 `Foundation.Decimal`），无任何意外差异。首次运行 33 秒（含 sourcekitd 索引），缓存命中后 10 秒、输出逐字节一致；缓存目录只出现依赖过滤命中的 9 个模块条目（历史实现是全 SDK 数百个）。
- 全套 `swift test --skip IntegrationTests` 退出码见提交前终验（成败只认退出码，不认 xcsift 摘要）。

## 与提案的偏差

见实现说明「与提案的差异」：swift-dependencies 未引入（register 步骤替代注入框架）；兜底行级解析器未编写（substructure 实测可用，按提案条款定夺）；APINotes 归属注册比历史实现更宽（含无改名与 `SwiftPrivate` 实体）。
