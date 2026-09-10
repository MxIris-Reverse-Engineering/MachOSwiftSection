# Draft - 补齐五组缺失的 ABI 结构

- **状态**: Accepted
- **创建日期**: 2026-09-10
- **最后更新**: 2026-09-10
- **关联提案**: [0018](0018-self-contained-abi-layer.md)（ABI 层自足，决定符号侧入口不在本批）、[0025](0025-key-path-component-and-property-descriptor.md)（同一形状的上一批：只建结构 + fixture，不接线）

## 摘要

对着 `swift/include/swift/ABI/` 把 `Sources/MachOSwiftSection/Models/` 的差集过了一遍，本提案补齐其中五组，全部只建 ABI 结构与读取入口，不改任何现有输出。

| # | 结构 | 为什么值得建 |
| --- | --- | --- |
| 1 | `AsyncFunctionPointer` / `CoroFunctionPointer` | **修正一处现有的错误认识**：async 成员与 `yield_once_2` 协程访问器的「实现指针」指向的是一条两三个字的记录，不是函数本身 |
| 2 | `CaptureDescriptor`（`__swift5_capture`） | 目录已存在但两个文件是空壳；这是唯一一个还完全读不了的反射 section，且每个 Swift 二进制都带它 |
| 3 | `GenericMetadataPattern` 家族 | `TypeGenericContextDescriptorHeader.defaultInstantiationPattern` 现在是个指向不明的裸 `RelativeOffset`，跟下去就是编译器自己算好的、不依赖实参的值见证表 |
| 4 | `AccessibleFunctionRecord`（`__swift5_acfuncs`） | 20 字节一条的扁平数组，distributed actor 的完全抽象入口只在这里描述 |
| 5 | `FunctionTypeMetadata` 的尾随对象 | 现在只建了三个字的头，参数类型、参数标志、global actor、typed throws 的错误类型全缺 |

第 1 项与提案 0025 的 property descriptor 是同一形状：符号（或某个字段）给你一个 offset，那个 offset 上是一小块编译器发出的常量记录，而 `include/swift/ABI/` 里找不到同名的 C++ 结构——它只存在于 IRGen。

## 方案

### 边界：只建结构，不接线

这一批到「能把字节读成值 + fixture 测试」为止。以下明确**不做**，各自留独立提案：

- 不改 `MethodDescriptor.implementationOffset` 的语义，也不新增穿透到真函数的 API。穿透会改变 dump / interface 的输出、要重新生成四套 ABI 字面量 baseline、还要复核符号归属逻辑，与「建结构」不是一件事。
- SwiftLayout 不改用 pattern 里的值见证表，仍走现有的 `__swift5_builtin` + `__swift5_mpenum` 推导。
- capture descriptor 里「元数据来源」那条记录的小语法不解析（见下）。
- `__swift5_replace` / `__swift5_replac2`（动态替换）不做——实测发布的系统框架不带这个 section（查过模拟器 runtime 里的 libswiftCore 与 SwiftUI），只有 Preview / debug 构建才有。
- Task / Executor / actor 的运行时结构（`AsyncTask`、`AsyncContext`、`Job`、`DefaultActor`、`TaskGroup`）不做——纯堆上运行时状态，Mach-O 里没有落点。

### 分阶段提交

一份提案，五个阶段各自一个 commit，每个阶段自带测试、可独立验证：

| 阶段 | 内容 | 大小 |
| --- | --- | --- |
| 1 | async / coro function pointer 记录 | 小 |
| 2 | accessible function record + `__swift5_acfuncs` 入口 | 小 |
| 3 | capture descriptor 骨架 + `__swift5_capture` 入口 | 中 |
| 4 | generic metadata pattern 三件套 + resilient class pattern | 中 |
| 5 | function type metadata 尾随对象 | 中 |

顺序理由：1 是唯一修正现有错误认识的一项，排最前；2 最小，顺手做掉；5 只在进程内可测，放最后不阻塞其余。收尾一并更新 AGENTS.md 的架构段、`ProjectEvolutionLog.md`、任务报告，并把本提案改名取号、状态置 `Implemented`。

### 1. async / coro function pointer 记录

`swift/lib/IRGen/GenMeta.cpp:332-342` 是根据：method descriptor 填实现指针时，`impl->isAsync()` 走 `getAddrOfAsyncFunctionPointer`，`isCalleeAllocatedCoroutine()` 走 `getAddrOfCoroFunctionPointer`，只有第三条分支才是函数本身。vtable 槽（`GenMeta.cpp:4602`）、resilient witness、protocol requirement 的默认实现走同一套。所以今天 `implementationOffset` 对每个 async 成员报的都是那条记录的地址，差一跳。

两条记录的布局：

| 结构 | 符号后缀 | 布局 | 来源 |
| --- | --- | --- | --- |
| `AsyncFunctionPointer` | `Tu` | `{ int32 相对函数指针; uint32 ExpectedContextSize }`，8 字节 | `include/swift/ABI/Executor.h:405` |
| `CoroFunctionPointer` | `Twc` | `{ int32 相对函数指针; uint32 分配大小; uint64 malloc type id }`，packed 16 字节 | `lib/IRGen/IRGenModule.cpp:744` 建类型、`lib/IRGen/GenMeta.cpp:7671` 填内容 |

`CoroFunctionPointer` 在 `include/swift/ABI/` 下没有对应的 C++ 结构，与 property descriptor 同样只存在于 IRGen，注释里要写明这一点。两者的函数字段都是 compact function pointer，在 Darwin 上就是 32 位相对直接指针，语义与 `MethodDescriptor` 的实现指针一致——暴露成已解析的文件偏移（`Int?`，null 给 `nil`），符号归属留给上一层。

### 2. accessible function record

`__swift5_acfuncs` 是扁平数组，每条 20 字节：四个 int32 相对指针（`Name` / `GenericEnvironment` / `FunctionType` / `Function`）+ uint32 `Flags`（`include/swift/ABI/Metadata.h:5336`）。`Flags` 目前只定义了 bit 0 = `Distributed`（`MetadataValues.h:3051`）。`Name` 是查找用的字符串键，`FunctionType` 是函数类型的 mangled name——两者都能直接喂给现成的 `MangledName`。

section 入口按 `stdlib/public/runtime/AccessibleFunction.cpp:46` 的做法，用 `begin + size` 直接切数组。

### 3. capture descriptor（骨架档）

布局（`include/swift/RemoteInspection/Records.h:486/531/589`）比预想的简单：

```
uint32 NumCaptureTypes
uint32 NumMetadataSources
uint32 NumBindings
CaptureTypeRecord[NumCaptureTypes]        // 每条：int32 相对指针 → mangled type name
MetadataSourceRecord[NumMetadataSources]  // 每条：int32 mangled type name + int32 mangled metadata source
```

总长 = `12 + 4 * NumCaptureTypes + 8 * NumMetadataSources`，变长且顺序排布，跟 `__swift5_fieldmd` / `__swift5_assocty` 同构，直接复用现成的 `_readDescriptors(from:)` + `TopLevelDescriptor.actualSize`。

**骨架档的含义**：capture type 的 mangled name 走现成的 `MangledName`，立刻就能回答「这个闭包捕获了哪些类型」；`MangledMetadataSource` 那一条只按 `MangledName` 原样暴露，不解析它的语法（那是一套独立的小表达式语言，回答的是「运行时怎么从上下文里恢复泛型实参」，单独就是一个不小的子任务，留后续提案）。

顺带一处改型：`HeapLocalVariableMetadata.captureDescription` 现在的类型是 `Pointer<String?>`，而它实际指向的是一条 capture descriptor。本批把它改成正确的目标类型——除 fixture 机制外没有别的使用者。

### 4. generic metadata pattern 家族

`TypeGenericContextDescriptorHeader.defaultInstantiationPattern` 现在只是个 `RelativeOffset`，没有目标类型。跟下去（`include/swift/ABI/Metadata.h:3540` 起）：

- 基类 `GenericMetadataPattern`：`{ int32 InstantiationFunction; int32 CompletionFunction; uint32 PatternFlags }`
- value 变体尾随 `{ int32 ValueWitnesses }`（relative indirectable）——**这就是编译器自己算好的、不依赖实参的值见证表**
- class 变体尾随 `{ int32 Destroy; int32 IVarDestroyer; uint32 ClassFlags; uint16 ClassRODataOffset; uint16 MetaclassObjectOffset; uint16 MetaclassRODataOffset; uint16 Reserved }`
- 两者再按 flags 尾随 0–2 个 `GenericMetadataPartialPattern`：`{ int32 Pattern; uint16 OffsetInWords; uint16 SizeInWords }`
- `GenericMetadataPatternFlags`（`MetadataValues.h:2449`）：bit 0 `HasExtraDataPattern`、bit 1 `HasTrailingFlags`、bit 31 `Class_HasImmediateMembersPattern`、bit 21 起 11 位宽的 `Value_MetadataKind`

另加 `ResilientClassMetadataPattern`（`Metadata.h:3901`）。它**不**挂在 `defaultInstantiationPattern` 上，而是 `SingletonMetadataInitialization` 那个 union 的另一支：现有模型的 `incompleteMetadata` 字段，在 class descriptor 的 `hasResilientSuperclass` 为真时装的是这条 pattern 的相对指针。所以这一项只需加一个结构 + 一个判据访问器，不改现有布局。

### 5. function type metadata 的尾随对象

尾随顺序（`Metadata.h:1529`），每一项的条数都由头部的 `FunctionTypeFlags` 决定，而现有模型已经把那些位建好了：

```
Parameter[numberOfParameters]              // 每条一个 metadata 指针
ParameterFlags[numberOfParameters]         // hasParameterFlags 时
DifferentiabilityKind                      // isDifferentiable 时
GlobalActor                                // hasGlobalActor 时
ExtendedFunctionTypeFlags                  // hasExtendedFlags 时
ThrownError                                // hasThrownError 时（条件位在 extended flags 里）
```

全是运行时分配的 metadata，Mach-O 里没有落点，测试走 `usingInProcessOnly`，与 `TupleTypeMetadata` / `MetatypeMetadata` 同一档。

### 覆盖

按 AGENTS.md 的覆盖契约，每个新公开方法要么注册进对应 Suite 的 `registeredTestMethodNames`，要么进 `CoverageAllowlistEntries.swift` 并带 `SentinelReason`；纯位域枚举（`AccessibleFunctionFlags`、`GenericMetadataPatternFlags` 的一部分）预计落 `pureDataUtility`。baseline 走 `regen-baselines --suite <Name>`。

`SymbolTestsCore` 的现成材料（实测）：

| 项 | 材料 |
| --- | --- |
| async function pointer | 40 个 `Tu` 符号 |
| accessible function record | `__swift5_acfuncs` 共 0x50 字节 = 4 条 |
| capture descriptor | `__swift5_capture` 共 0x270 字节 |
| generic metadata pattern | 107 个 `MP` 符号 |

**只有 coro function pointer 没有现成材料**：`Twc` 符号需要 `-enable-experimental-feature CoroutineAccessors`，`SymbolTestsCore` 没开。实测当前工具链能发（探针产物里拿到 `$s9CoroProbe6HolderV5firstSivxTwc`），所以走随手编译的 fixture module，照 `VTableSlotAttributionTests` 的做法，并按 AGENTS.md 的规矩让 fixture 源码带至少一个 class 以保证有 `__DATA` 段。

## 决策日志

| 日期 | 决定 | 理由 |
| --- | --- | --- |
| 2026-09-10 | 建为 Draft，范围锁定这五项 | 用户在 ABI 差集调研后点名「1、2、3、4、5 都做，其他不做」 |
| 2026-09-10 | 一份提案，分五个阶段提交 | 遵循「一次改动 = 一份提案文件」，文档权威唯一；五项工作量差异大，分阶段落地才有可验收的中间态 |
| 2026-09-10 | 只建 ABI 结构 + fixture，不接线 | 与提案 0025 同样的边界。穿透 `implementationOffset` 会改输出、动四套 baseline、需复核符号归属，属于另一件事；SwiftLayout 换用 pattern 值见证表同理 |
| 2026-09-10 | capture descriptor 先做骨架，metadata source 留原始形式 | capture type 的 mangled name 已经能回答主要问题；metadata source 的小语法单独就是一个不小的子任务，不该把这一项拖成整批的瓶颈 |
| 2026-09-10 | 不做 `__swift5_replace` | 实测模拟器 runtime 的 libswiftCore 与 SwiftUI 都不带这个 section，发布产物里没有；只有 Preview / debug 构建才发，对本库的主要分析对象价值低 |
| 2026-09-10 | coro fixture 走随手编译，不动 `SymbolTestsCore` | 给 `SymbolTestsCore` 加 `CoroutineAccessors` flag 会改变构建产物布局、挪动每一个实现偏移，四套 ABI 字面量 baseline 全红（AGENTS.md 已记过 `CODE_SIGNING_ALLOWED=NO` 造成 +16 字节偏移的同类事故） |
| 2026-09-10 | 符号侧入口（按 `Tu` / `Twc` 符号名查 offset）不在本批 | 同提案 0025：需要符号索引，而提案 0018 规定 `MachOSwiftSection` 只依赖 `MachOBase`；那一步属于 `SwiftInspection` |
| 2026-09-10 | 状态置 `Accepted`，开工 | 用户审阅提案后指示「开工」 |
