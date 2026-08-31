# 2026-08-30 RuntimeMetadataTypeBuilder：TypeBuilder 的首个生产 conformer

## 问题

用户最初问「Swift 源码里有几个符合 TypeDecoder 的类型，我们需要搬过来吗」。调研结论是三个具体 Builder（`ASTBuilder` / `TypeRefBuilder` / `DecodedMetadataBuilder`）都不该搬——遍历器本身已由 swift-demangling 完整移植（`TypeDecoder<Builder: TypeBuilder>` + `TypeBuilder` 协议，且按上游逐项审计过），但生产侧没有任何 conformer（唯一实现是测试里的 `StringTypeBuilder`）。用户定向：第一个生产 conformer 做 in-process metadata builder（对标运行时 `DecodedMetadataBuilder`），走轻量档提案 `0012-in-process-metadata-type-builder`（当时为 `draft-` 未取号）。

## 调研

- **上游语义**（`swift/stdlib/public/runtime/MetadataLookup.cpp`）：`createNominalType` 统一走 `createBoundGenericType`；key-argument 收集是 `_gatherGenericParameters`（接受「仅最内层实参 + parent metadata 补外层」或「完整扁平实参且无 parent」两种形状；父级 written args 从 parent metadata 的 generic-argument 区读回）+ `_checkGenericRequirements`（PWT 按 requirement 顺序追加）；accessor 用 `MetadataState::Abstract` 请求（容环），顶层 `swift_checkMetadataState` 补全；tuple 单元素无标签解包、labels 用空格终止串；`createConstrainedExistentialType` 上游自己也拒绝。
- **项目侧关键事实**（探查 agent 清点）：
  - `MetadataReader` **从不产出** `.typeSymbolicReference`——context 引用都解析成命名树。命名节点解析是主路径，不是回退。
  - `GenericSpecializer.makeRequest` 为每个参数**急切枚举候选**（无约束参数 = 全镜像每类型一个 Candidate），PWT 解析硬依赖 indexer——不适合逐节点解码复用，故 key-argument 收集在 builder 内自实现。
  - swift-demangling 的 `FunctionTypeFlags` 位布局与运行时 ABI 字 1:1，可透传；`TypeLookupErrorOr<T> = Result<T, TypeLookupError>` 现成，作为 `BuiltType` 承载失败（`create*` 协议方法不抛错）。
  - 进程内 wrapper 约定：`offset` 即指针位模式，`asPointer` / `readWrapperElement` 纯往返。
- **兄弟依赖状态**：本地 `MachOObjCSection` 被 pin 在 0.7.103（detached，main 在 `.claude/worktrees` 里），带 `USING_LOCAL_DEPENDENCIES=1` 构建会因缺 `ObjCIndexing` product 失败；远端 swift-demangling 0.6.1 已含 TypeDecoder。**本批次全程用远端依赖构建**，未动被 pin 的兄弟仓库。

## 最终方案

见提案 `Documentations/Evolutions/0012-in-process-metadata-type-builder.md`（方案节 + 决策日志为准）。要点：`Sources/SwiftInspection/RuntimeMetadataTypeBuilder.swift`，`BuiltType = TypeLookupErrorOr<Any.Type>`；`MachOSwiftSectionC` 补桥六个运行时入口（extended function 变体 weak-linked）；命名节点三级解析（注入 seam → 运行时按名 → 标准库泛型内置表）；诚实拒绝面 typed error。

## 实际执行

1. `Functions.h` 补 C 桥（含 `<stdint.h>`、`ProtocolClassConstraint` ABI 反转注释、existential 协议数组会被原地排序的注释）。
2. `RuntimeMetadataTypeBuilder.swift`（约 700 行）：全协议实现 + `_gatherGenericParameters` 语义的 `keyArguments(of:ownArguments:parentType:)` + requirement subject 自举解码 + `writtenGenericArguments(ofParent:)`（value 16 字节头 / class resilient 分支）+ 标准库泛型描述符表 + `runtimeTypeByName`（remangle 剥前缀喂 `swift_getTypeByMangledNameInEnvironment`）。
3. `RuntimeMetadataTypeBuilderTests`：往返 parity（oracle = 类型字面量本身，非重算）。

## 验证

- `RuntimeMetadataTypeBuilderTests` 17 个用例全绿：标准库泛型（含 `Dictionary` 的 Hashable PWT）、tuple / 函数 / metatype / existential / 组合、ObjC class 与协议 existential、resolver seam 下的约束泛型、`Sequence.Element: Equatable` 的 assocty-witness requirement subject、`OuterGeneric<Int8>.Inner` 与 `OuterGeneric<Int8>.InnerPair<Int64>` 的父级实参合并、绑定环境替换（`x` / `SayxG`）、两类 typed error 拒绝。
- 全量 `swift test --skip IntegrationTests` 结果见提案决策日志（本报告写作时在后台运行）。

## 偏差与踩坑

- **ObjC class 崩溃**：首版按上游用 `swift_getObjCClassMetadata`，NSObject / NSString 用例 SIGSEGV——崩在测试打印重建类型时（`objc_class::demangledName` 读 0x303）。探针实测：canonical `Any.Type`（`NSObject.self`、按名查询返回值）就是 realized class 指针本身，wrapper 是另一个 metadata 身份。改用 `swift_getInitializedObjCClass` 直接返回 class 指针。上游源码（本机 checkout 6.3.2）的 decode 路径按字面读应产出 wrapper、而已装运行时按名查询返回 class 指针——机制差异未再深挖，以行为事实为准。
- **标准库泛型表是实现期补的**：方案原文只写了 seam + 运行时按名回退，实测 `SaySiG` 这类字符串 mangling 的标准替换展开成命名节点后 `Array<Int>` 都建不出，遂加表（17 个常用泛型，经已知实例化反查描述符）。
- 首版拒绝面比方案多列 constrained existential 与 value generics（决策日志有记）。
