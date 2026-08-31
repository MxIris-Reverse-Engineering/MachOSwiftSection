# 0012 - RuntimeMetadataTypeBuilder：TypeBuilder 的首个生产 conformer（node → 进程内活 metadata）

- **状态**: Implemented
- **创建日期**: 2026-08-30
- **最后更新**: 2026-08-31

## 摘要

swift-demangling 已完整移植上游 `TypeDecoder.h` 的遍历器（`TypeDecoder<Builder: TypeBuilder>` + `TypeBuilder` 协议，含 `NodeReference` store-backed 变体与栈安全契约），但生产侧至今没有任何 conformer（唯一实现是测试里的 `StringTypeBuilder`）。本提案实现第一个生产 conformer `RuntimeMetadataTypeBuilder`——对标 Swift 运行时 `MetadataLookup.cpp` 里 `swift_getTypeByMangledName` 的核心 `DecodedMetadataBuilder`：把 demangle 出的 `Node` 树直接构建成进程内的活 metadata（`BuiltType == Metadata`）。这替代了目前「node remangle 成字符串 → `swift_getTypeByMangledNameInContext`」的往返（该入口还要求 mangled 字节位于可寻址内存、上下文与实参按运行时约定摆放），并为后续让 `SwiftSpecialization` 接受任意类型表达式实参（用户输入 `[Int: String]?` 之类）打底。

## 方案

以下为默认档下自行敲定的假设，未获反对即按此执行：

- **位置与命名**：`Sources/SwiftInspection/RuntimeMetadataTypeBuilder.swift`（SwiftInspection 是「运行时 metadata 分析」的既有归属，`MetadataReader` 在此；它已依赖 Demangling 与 MachOSwiftSection，无需新增依赖边）。关联类型：`BuiltType = Metadata`、`BuiltTypeDecl` = 类型上下文描述符 wrapper、`BuiltProtocolDecl` = Swift/ObjC 双态的 protocol descriptor 引用。仅进程内（`MachOImage` / in-process）可用，与现有运行时路径一致。
- **结构类型走运行时官方入口**，在 `MachOSwiftSectionC` 补齐 C 桥接（现仅有 `swift_getTypeByMangledName*` / `swift_conformsToProtocol` / `swift_getAssociatedTypeWitness`）：tuple → `swift_getTupleTypeMetadata`，function → `swift_getFunctionTypeMetadata`，existential → `swift_getExistentialTypeMetadata`，metatype → `swift_getMetatypeMetadata` / `swift_getExistentialMetatypeMetadata`，ObjC class → `objc_getClass` + `swift_getObjCClassMetadata`。sugar 节点（Optional / Array / Dictionary / InlineArray）按 stdlib 类型的 bound generic 处理。
- **nominal 类型**：`createTypeDecl` 把节点解析为描述符——symbolic reference 节点直接持有描述符指针（`node.index` 即进程内地址，上游 `getIndex()` 约定）；命名节点走三级解析：调用方注入的 `nominalTypeDescriptorResolver` seam（有索引的宿主接进来）→ 非泛型命名节点 remangle 后经 `swift_getTypeByMangledNameInEnvironment` 按名查询（运行时自己的全镜像搜索）→ 标准库常用泛型（Array / Dictionary / Optional / Range 等 17 个）从内置表取描述符（经任一已知实例化的 metadata 反查，进程内一次性缓存）。`createNominalType` 统一走 `createBoundGenericType`（上游同构）；key-argument 收集按 `_gatherGenericParameters` + `_checkGenericRequirements` 语义在 builder 内自实现：全 cumulative 参数列表的 written args（父级实参从 parent metadata 的 generic-argument 区读回，class 的 resilient/非 resilient 偏移分支与 `RuntimeFunctions` 同构）、key 参数 metadata 先行、key protocol requirement 的 PWT 按 requirement 顺序经 `swift_conformsToProtocol` 追加，requirement subject（`A` / `A.Element`）用携带 written-args 绑定环境的嵌套 builder 自举解码。
- **泛型参数**：builder 可携带一个可选绑定环境（`(depth, index) → Metadata`）；无绑定时 `createGenericTypeParameterType` 抛 typed `TypeLookupError`——诚实降级，绝不造值。
- **首版明确拒绝**（typed error，不 fabricate）：SIL 系（`createImplFunctionType` / SILBox）、pack expansion、`resolveOpaqueType`。拒绝面与运行时 `DecodedMetadataBuilder` 一致或更窄，后续按需求逐项放开。
- **验证**：往返 parity 测试（`RuntimeMetadataTypeBuilderTests`）——对活类型取 `_mangledTypeName`，demangle 成节点经 builder 重建，产物必须与原类型指针相等（运行时 metadata 全局唯一化，指针相等即语义相等；期望值是独立的类型字面量，非重算）。覆盖：标准库泛型、tuple / 函数 / metatype / existential、ObjC class 与协议 existential、resolver seam 下的约束泛型（Hashable PWT）、dependent-member requirement subject（assocty witness）、嵌套泛型的父级实参合并、绑定环境替换，以及无绑定参数 / 无 resolver 命名泛型的 typed error 拒绝。
- **本提案不动 `GenericSpecializer` 现有路径**。接线（如 `SpecializationSelection.Argument` 新增 `.typeExpression(Node)` case）是后续独立批次，届时在本提案决策日志登记或另开提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-08-30 | Created as Draft | 用户定向：TypeBuilder 的第一个生产 conformer 做 in-process metadata builder |
| 2026-08-30 | 不从 Swift 源码搬移三个 builder（ASTBuilder / TypeRefBuilder / DecodedMetadataBuilder），只在本项目实现协议 | 遍历器已由 swift-demangling 移植并按上游审计；ASTBuilder 依赖编译器 AST 无场景，TypeRefBuilder 对应的离线布局本项目已有更强实现 |
| 2026-08-30 | 离线 layout 引擎不重构到 TypeDecoder 上 | `StaticTypeLayoutResolver` 在 spare-bits XI、parameter pack 等处已强于官方 `TypeLowering`；重构触发强制渲染 A/B 验证，churn 大收益低 |
| 2026-08-30 | 用户批准方案（默认档假设无异议），状态 Draft → In Progress | 轻量档：点头即动手 |
| 2026-08-30 | 不复用 `GenericSpecializer` 做 bound-generic 构建，key-argument 收集在 builder 内按运行时语义自实现 | `makeRequest` 会为每个参数急切枚举候选（无约束参数 = 全镜像每个类型一个 Candidate），且 PWT 解析硬依赖 indexer——交互流形状，不适合逐节点解码；进程内 `swift_conformsToProtocol` 即是运行时自己的解析路径 |
| 2026-08-30 | 命名泛型增设标准库描述符内置表 + `nominalTypeDescriptorResolver` seam；本项目 `MetadataReader` 从不产出 `.typeSymbolicReference`（都解析成命名树），命名路径是主路径而非回退 | 字符串 mangling 里 `Sa` / `SD` 等标准替换展开成命名节点，没有表则 `Array<Int>` 都建不出；索引级解析留给有索引的宿主注入 |
| 2026-08-30 | `createObjCClassType` 返回 realized class 指针本身（`swift_getInitializedObjCClass`），不走 `swift_getObjCClassMetadata` | 实测 canonical `Any.Type`（`NSObject.self`、按名查询结果）就是 class 指针；wrapper 是另一个 metadata 身份，会分裂泛型实例化缓存，且在测试进程里打印 wrapper 触发 SIGSEGV |
| 2026-08-30 | 首版拒绝面在方案基础上补列 constrained existential（上游 DecodedMetadataBuilder 同样拒绝）与 value generic 实参（`InlineArray<5, _>`）、非 key 或非 type 的父级参数 | 诚实降级：typed error 优于错值；后续按需求逐项放开 |
| 2026-08-30 | 实现完成：`RuntimeMetadataTypeBuilderTests` 17 用例全绿；全量 `swift test --skip IntegrationTests` 1572 测试 / 294 suite 通过（原始退出码 0）。本批次以远端依赖构建（本地 `MachOObjCSection` 兄弟副本被 pin 在 0.7.103，缺 `ObjCIndexing`，未动它） | 待与代码同批合入共享分支时置 `Implemented` 并取号 |
| 2026-08-31 | In Progress → Implemented，编号 draft → 0012 | 随 `next` rebase 到 `main` 之上、与代码同批落入共享分支，兑现上一行「待与代码同批合入共享分支时置 `Implemented` 并取号」。取号按 README 规则：fetch 全部远程分支后取 `Evolutions/` 编号全局最大值 0011 + 1（取号当时 `draft-swift-evolution-interface-builder` / `draft-unify-interface-renderers` 两份虽已 `Implemented` 却仍未取号，按规则 `draft-` 不占号；该两份随后于同日补取 0013 / 0014）。同批完成互链改名：ProjectEvolutionLog 第 52 节（标题占位「落地时定节号」一并兑现）、AGENTS.md、任务报告 |
