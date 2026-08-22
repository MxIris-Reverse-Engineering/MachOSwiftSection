# 2026-08-22 `final` 关键字还原与 lazy var 访问器类型修正（issue #106 首批）

## 问题

issue #106 是把本库 dump 拿去手写可编译 `.swiftinterface`（重建 Xcode 私有 `SourceEditor.framework`）的实战反馈，八点建议中本批做第 1、4 点：`final` 关键字完全缺失（唯一破坏链接的一点——经 dispatch thunk 的成员必须平凡声明、只有直接符号的必须 `final`）；lazy var 打印 `Optional` 存储类型而非调用方看到的 getter 类型。另有三批规划：0007（extension 容器去重，issue §5）、0008（文件头部与导出标注，issue §2/§3/§8，等 §6 import 重构落地）；§6 已由另一会话实现修复中，§7 按用户决定忽略。

## 调研结论

- 判据不用 issue 建议的 `Tj` dispatch thunk（仅 resilient 二进制有效），用 method descriptor 存在与否——`isClassMember`（`class`/`static` 还原）同一条 ABI 事实的镜像，resilient 与否均成立且覆盖非 public 成员。
- 关键发现：stored `var` 的 accessor→vtable 归属**已在 `DefinitionBuilder.variables` 里解析完毕**，只是被 `fieldNames` 去重整组丢弃（防止属性打印两次）。缺的不是解析能力，是保留结果。
- lazy 检测是 `$__lazy_storage_$_` 前缀匹配；剥前缀后与 accessor 同名，getter 组恰好也被同一行 guard 丢弃——两点同根因，同批修。
- 调研先在 main（`32bf83c1`）完成、于 next（`a03d0f1b`）复核：机制无漂移，形态差异为 `StructuralNodeReferenceKey` 键与 `NodeReference` interning（0002 号提案的 descriptor 化）。

## 最终方案

提案 [0006](../../Evolutions/0006-final-keyword-and-lazy-accessor-type-recovery.md)（在 next 上因编号占用从 0005 改号）。要点：`variablesProduct` 交还被抑制的 accessor 组 → 折回 `FieldDefinition.accessors`；模型层 `isFinal` 存储属性（index 期在证据充分时置位）；`final` 关键字默认输出、stored var 的 vtable 注释跟随既有 `--emit-vtable-offsets`；lazy 用 getter 的类型节点渲染；dump 路径 `final` 对齐（名字级 join）。用户预先拍板：关键字默认开/注释挂 flag、0007 索引期合并、0008 公共组件 + 等 §6。

## 实际执行

1. worktree：`MachOSwiftSection-0005` 目录（Org 下同级，保住 `../MachOKit` 等兄弟依赖路径），分支 `feature/0006-final-and-lazy-recovery` 基于 next。本地 sibling `swift-demangling`（main）API 领先 next 所需无法配对，构建走远端 pin（swift-demangling 0.6.0）。
2. 模型层：`FieldDefinition` + `accessors`/`accessorTypeNode`/`isFinal`/`hasVTableAccessor`；三个成员定义 + `isFinal`；`DefinitionBuilder.variablesProduct`；`TypeDefinition.index` 折回 + 三层证据门 + 标记块。
3. 渲染层：`Keyword.final`；`printThrowingField`（关键字 + `fieldTypeNode` 取型）；`renderModelFields` 复用 `DeclarationRenderConfiguration.vtableOffsetComment`（dump/interface 单一来源）；三个 node printer `printRoot` 写 `final `。
4. dump 层：`TypedDumper.fieldDeclarationKeywords` + `isFinal` 参数；`ClassDumper` 名字级 join（`vtableAccessorFieldNames` / `storedAccessorFieldNames`，含 `@objc` 排除）。
5. fixture：`VTableEntryVariants.FinalMembersTest` 全组合矩阵（加进既有文件，避免动 pbxproj）；重建 fixture 二进制。
6. 快照审查驱动的三轮修正（见下）。
7. 文档同批：提案决策日志、实现说明 `FinalKeywordAndLazyAccessorTypeRecovery.md`、`Documentations/README.md` 索引、AGENTS.md SwiftPrinting 段、Roadmaps L-12、ProjectEvolutionLog 第 42 节、本报告。

## 快照审查抓住的三类误标（本任务最有价值的部分）

1. **async 成员误标 `final`**（被子类 override 的 `asyncMethod` 竟标 final）：根因是 async 方法的 method descriptor `implementation` 指向 `Tu` async-function-pointer 常量，demangled 树多一层 `.asyncFunctionPointer` 前导标记，与成员符号树结构键永不匹配——**join 从未成功过**，此前仅表现为 async 成员没有 vtable 注释、async override 丢 `override` 关键字（都不显眼）。`memberJoinKey` 剥标记修复，三个症状一起消失（子类 `override func asyncMethod()` 回归可见于快照 diff）。
2. **`@objc dynamic` 误标**：objc_msgSend 派发、无 vtable 条目、但可覆写。排除规则「`@objc` 且无 descriptor ⇒ dynamic」，标记块移到 `applyThunkAttributes` 之后（且必须在 `orderedMembers` 构建之前——它持值拷贝）。
3. **final class 的成员被标 `final`**：final class 因 designated init 的 vtable 条目仍带 header，「无 header」门挡不住。定性为**接受的行为**：类级 `final` 无 ABI 位（Roadmaps 新增 L-12），成员级标记如实反映派发、对重建链接恰好正确。

另有一处测试自身的教训：窗口式邻接断言（取声明前 N 字符）会跨类边界，恰好把前一个类 async override 新获得的 vtable 注释捞进来——改为只看紧邻前一行。

## 验证

- `FinalMemberRecoveryTests` 五用例：渲染层 final 配对（全矩阵正反断言）、lazy 访问器类型（`lazy var lazyProperty: Swift.String` 非 Optional）、plain stored var 的 getter/setter vtable 注释邻接 + final stored var 无注释、模型层 `isFinal`/`accessors`/`accessorTypeNode` 事实。
- 快照重录并逐行审查：interface 整模块 + dump `enums`/`genericFieldLayout`/`vTableEntryVariants`；全部变更可归因（真 final、final class 成员、body 化 extension 成员、async 修复、lazy 类型、新矩阵类）。
- 全量 `swift test --skip IntegrationTests`：1438 tests，除 fixture 重建引发的 136 条 ABI 基线 offset 漂移外全绿；`regen-baselines` 后 59 个基线文件 96 行 diff **全部为 offset 字面量**（无语义变更），复跑收敛。
- 真实框架对照（首次提交后、0007 开工前补做）：对 Xcode `SourceEditor.framework` 生成整模块 interface 并与 `nm` 逐符号核对，**当场抓到第四类误标**——1128 个空实现被 ICF 折叠到同一地址，descriptor→symbol 地址 join 配不上对，`SourceEditorView.elide` 等带 `Tq` 的真类成员被标 `final`。修复为第四道门（成员名存在 `Tq` method-descriptor 符号即绝不标，`Tq` 是每成员唯一地址的数据符号、ICF 免疫），interface/dump 两路同步，回归钉死在环境门控的 `FinalKeywordICFRegressionTests`；正例 `SourceEditorDataSource.languageService` 在原始二进制上打印 `final lazy var languageService: SourceEditor.SourceEditorLanguageService`（issue 第 1、4 点合体）。fixture 快照零扰动。

## 与计划的偏离

- lazy 的「剥一层 Optional」回退未实现（getter 缺失 ⇒ 保持存储类型，诚实回退且免写 sugar 兼容的剥离器）。
- dump 路径 lazy 保持存储真相，仅 `final` 对齐（dump 是原始视图，`[Getter]` 列表已展示访问器类型）。
- 提案未预见的 async join 修复、`@objc dynamic` 排除、final class 成员级标记，均已回填提案决策日志。
- snapshot 重录机制勘误：suite trait `.snapshots(record: .missing)` 覆盖 `SNAPSHOT_TESTING_RECORD=all` 环境变量，重录须删文件让 `.missing` 补写。
