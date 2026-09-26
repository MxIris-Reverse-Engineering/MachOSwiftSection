# 补齐五组缺失的 ABI 结构

- **日期**：2026-09-10
- **提案**：[0026 missing-abi-structures](../../Evolutions/0026-missing-abi-structures.md)
- **前一批**：[2026-09-10 property descriptor 模型](2026-09-10-property-descriptor-model.md)

## 问题

用户问「我们这里还差什么 ABI，挑那些有用的」。这是一次差集调研加落地，不是从某个 bug 出发。

## 调研

把 `swift/include/swift/ABI/` 下所有 `Target*` 结构名和 `Sources/MachOSwiftSection/Models/`
下的文件名对了一遍，再逐个判断"对这个库现在的功能有没有实际改善"。结论分三档：

**第一梯队（真能改善现有输出）**

1. **async / coro function pointer 记录**。这是唯一一处**现有行为确实是错的**：
   `swift/lib/IRGen/GenMeta.cpp:332-342` 显示 method descriptor 填实现指针时，
   `impl->isAsync()` 走 `getAddrOfAsyncFunctionPointer`、
   `isCalleeAllocatedCoroutine()` 走 `getAddrOfCoroFunctionPointer`，只有第三条分支才是函数
   本身。vtable 槽（`GenMeta.cpp:4602`）、resilient witness、protocol requirement 默认实现
   走同一套。所以 `implementationOffset` 对每个 async 成员报的都是那条记录的地址。
2. **`__swift5_capture`**。`Models/Capture/` 下两个文件当时是空壳（各一行 `import Foundation`），
   也没有 section reader。而这个 section 在每个 Swift 二进制里都有——实测模拟器 runtime 的
   libswiftCore 和 SwiftUI 都带。
3. **泛型元数据模板**。`TypeGenericContextDescriptorHeader.defaultInstantiationPattern`
   是个裸 `RelativeOffset`，没有目标类型。跟下去是编译器自己算好的值见证表。

**第二梯队** `__swift5_acfuncs`、`FunctionTypeMetadata` 的尾随对象。

**判定不做** `__swift5_replace`（实测发布的系统框架不带这个 section）、Task / Executor /
actor 的运行时结构（Mach-O 里没有落点）。

## 最终方案

用户点名「1、2、3、4、5 都做，其他不做」。一轮澄清提问确定三件事：一份提案分五个阶段提交；
边界与 0025 相同（只建 ABI 结构 + fixture，不接线）；capture descriptor 先做骨架。

## 实际执行

五个阶段各一对 commit（模型 + 测试），加一个提案 commit 和一个收尾文档 commit。

| 阶段 | 新增 | fixture 材料 |
| --- | --- | --- |
| 1 | `AsyncFunctionPointer` / `CoroFunctionPointer` | 40 个 `…Tu` 符号；`…Twc` 单独编译 |
| 2 | `AccessibleFunctionRecord` + `AccessibleFunctionFlags` | `__swift5_acfuncs` 0x50 字节 = 4 条 |
| 3 | `CaptureDescriptor` / `CaptureTypeRecord` / `MetadataSourceRecord` | `__swift5_capture` 0x270 字节 = 35 条 |
| 4 | pattern 家族（value / class / partial / resilient / flags） | 107 个 `MP` 符号 |
| 5 | `FunctionTypeMetadata` 尾随对象 + 四个 flag 类型 | 4 个进程内函数类型 |

每一批的 baseline 都先用 Python 独立解码一遍二进制、再和生成器输出逐值对照，避免重演上一批
"生成器读到 Mach-O 头、baseline 全是 `0xfeedfacf`"那种静默错误。

## 验证

- 全量 `MachOSwiftSectionTests`：868 tests / 176 suites 通过（163.8s，原始退出码 0）。
- 其余目标（跳过 `IntegrationTests`）：通过。
- `regen-baselines` 全量重跑后 `git diff` 只剩本批新增/修改的 baseline 文件。

## 与提案的差异

- 提案里没写的一处顺手改动：`HeapLocalVariableMetadata.captureDescription` 原本声明成
  `Pointer<String?>`，实际指向 capture descriptor，改成了正确的目标类型（提案的"方案"一节
  已把它列为假设，用户未反对）。
- 四个函数类型 flag/enum 的**命名**在实现期偏离了 ABI 名，见下。

## 踩到的坑

1. **协议扩展里的 key path 拿不到存储属性偏移**。`GenericMetadataPatternProtocol` 的共享实现
   里写 `offset(of: \.instantiationFunction)`，key path 是对 Layout **协议**成型的，指向
   witness 而不是存储属性，`MemoryLayout.offset(of:)` 返回 nil ——
   `LocatableLayoutWrapper` 那里是 `!` 强解，所以**编译通过、运行时 trap**。最终形态是两个
   函数指针都由各 conformer 用 `resolvedDirectOffset(from:)` 在具体类型上读（见下面的收尾）。
2. **`readElement(at:)` 被推断成 `Optional<Pointer<…>>`**。`globalActorType` 直接
   `return try context.readElement(...)` 给一个 `ConstMetadataPointer<Metadata>?` 返回值，
   读的是另一种内存形状，**静默返回 nil**，测试里表现为"全局 actor 读不出来"。必须先用
   显式类型标注读成非可选再包起来。
3. **名字撞 `Demangling`**。`ExtendedFunctionTypeFlags` / `ParameterOwnership` /
   `FunctionMetadataDifferentiabilityKind` 在 `Demangling` 的 TypeDecoder 里已经存在，而
   `SwiftInspection` 同时 unqualified import 两个模块，直接 ambiguous。选择给本库这四个类型
   加 `Function` / `FunctionType` 前缀，而不是去 `SwiftInspection` 里加限定名——后者只解决
   本仓库，下游用户同时 import 两个模块照样撞。
4. **SwiftPM 增量链接吃旧 .o**。把协议扩展成员改成协议要求之后，`baseline-generator`
   链接失败，undefined symbol 指向已经不存在的协议扩展 getter。`touch` 相关 generator 源码
   强制重编即可（与 AGENTS.md 记过的 `MachOSymbols` 结构体布局变更需清理重建同一类）。

## 明确留给后续批次的

- 让 `implementationOffset`（或一个新 API）穿透 async / coro 记录到真函数。
- SwiftLayout 改用 pattern 里的值见证表。
- 解析 metadata source 的小语法。
- 按 `…Tu` / `…Twc` 符号名查 offset 的便利入口（按提案 0018 的分工属于 `SwiftInspection`）。

## 收尾（2026-09-11）：per-field offset 属性全部退役

用户审阅后指出这批里那一堆 `functionOffset` / `destroyOffset` / `patternOffset` …… 属性没有
意义——每一个都是同样的三行（判空、取字段位置、加存储的增量），而 key path 本身已经在调用点
写出了字段名。落地形态是 `MachOPointers` 里一个共享 helper：

```swift
extension LocatableLayoutWrapper {
    public func resolvedDirectOffset(from keyPath: KeyPath<Layout, RelativeDirectRawPointer>) -> Int?
}
```

连带处理的三件事：

1. 提案 0018 的五个既有 `implementationOffset`（`MethodDescriptor` /
   `MethodOverrideDescriptor` / `MethodDefaultOverrideDescriptor` / `ProtocolRequirement` /
   `ResilientWitness`）是公开 API，**名字保留**，实现改成一行。
2. `TypeGenericContextDescriptorHeader` 与 `SingletonMetadataInitialization` 的 Layout 字段
   从裸 `RelativeOffset`（`Int32`）改成 `RelativeDirectRawPointer`——它们本来就是相对直接
   指针，不改的话这五个属性用不上 helper，会成为仅剩的手写特例。
3. 被删掉的属性文档里那些"null 是有意义的"事实（null relocation function 表示走
   `swift_relocateClassMetadata`、null ivar destroyer 表示不需要、union 字段的判据）全部搬到
   对应 Layout 字段的注释上，没有丢。

测试侧：被删成员对应的 `@Test func` 合并进各 Suite 的 `layout()`，断言一条不少；
`registeredTestMethodNames` 同步收缩。全量重跑 `regen-baselines` 后 diff 只剩每个 baseline 里
那一行注册名列表——**没有任何数值漂移**，这正是纯重构该有的样子。

## 收尾之二（2026-09-11）：纯转发属性也删掉

用户接着指出 `classFlags` 这类属性同样不用写——`LayoutWrapper` 是 `@dynamicMemberLookup`，
`layout` 的字段本来就能以 `record.field` 直接读。按这个原则删掉的有：

- 纯转发（类型完全一致）：`expectedContextSize`、`allocationSize`、`mallocTypeIdentifier`、
  `flags`、`classFlags` ×2、`patternFlags`、`FunctionTypeMetadata.flags`。
- 只做 `Int(...)` 加宽的：`offsetInWords` / `sizeInWords`、三个
  `…OffsetInWords`、`CaptureDescriptor` 的三个计数。这些按 `FieldDescriptor` /
  `TupleTypeMetadata` 的既有做法改成在使用点 `.cast()`；留着更糟——同名而类型不同的属性会
  **遮蔽** dynamic member，读代码的人看不出 `record.numberOfCaptureTypes` 到底是 `Int` 还是
  `UInt32`。

保留的是真正有内容的访问器：解码位域的（`isDistributed`、`hasExtraDataPattern`、
`metadataKind`…）、做指针算术的（`size`、`partialPatternsOffset`、`actualSize`…）、
以及 indirectable 指针那一路（`valueWitnessesOffset` / `valueWitnessesIsIndirect`，它有
"间接时不落在本镜像内"的真实逻辑，不是三行模板）。

**一个当场证伪的假设**：我以为 dynamic member lookup 在存在类型上也能用，于是先把
`GenericMetadataPatternProtocol.patternFlags` 删了。编译器直接拒绝——
`member 'patternFlags' cannot be used on value of type 'any GenericMetadataPatternProtocol'`，
因为 key path 的 root 是关联类型。那条断言各具体 Suite 的 `layout()` 本来就覆盖了，所以最终
是从协议 Suite 里移除，而不是把属性加回来。

测试侧同样把被删成员的 `@Test` 合并进 `layout()`（协议 Suite 没有 `layout()`，并入
`hasExtraDataPattern()`），`registeredTestMethodNames` 同步收缩。重跑 `regen-baselines` 后
diff 仍只有注册名列表那一行，**没有数值漂移**。
