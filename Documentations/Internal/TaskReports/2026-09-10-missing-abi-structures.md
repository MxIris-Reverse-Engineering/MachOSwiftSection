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
   `LocatableLayoutWrapper` 那里是 `!` 强解，所以**编译通过、运行时 trap**。改成协议要求由
   各 conformer 实现。
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
