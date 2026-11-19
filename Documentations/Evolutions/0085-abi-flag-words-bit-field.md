# 0085 - ABI 层的 flag word 改用 `@BitField`，修掉三个读错位的访问器

- **状态**: Implemented
- **创建日期**: 2026-11-05
- **最后更新**: 2026-11-05
- **所属愿景**: 无
- **关联提案**: FrameworkToolbox 的 [0015-bit-field-macro](https://github.com/Mx-Iris/FrameworkToolbox/blob/main/Documentations/Evolutions/0015-bit-field-macro.md)（宏本身，以本仓库为第一个使用方）
- **实现分支 / PR**: `feature/abi-flag-words-bit-field`（worktree `.worktrees/MachOSwiftSection-ABIFlagWordsBitField`，基于 `next` 463b2209），2026-11-05 合入 `next`；MachOKitUI 的对应改动 `feature/optional-flag-word-kinds` 同日合入它的 `main`
- **配套文档**: 无

## 摘要

ABI 层照 Swift 运行时的 C++ 头文件（`swift/ABI/MetadataValues.h`）手写了 24 个 flag word 类型。其中 17 个在一个整数里同时装着单个的标志位和多位字段，手写成四种风格：`OptionSet` 加 static、仓库自己的 `FlagSet` 协议加 `Bits` 常量、私有掩码常量、每个 case 是一个掩码的枚举。三个访问器把位读错了：

- `ExistentialTypeFlags.classConstraint` 只掩码、不移位，读到 `Any` 这类不限定 class 的 existential 就崩（`InProcessMetadataPicker` 的注释专门交代测试要绕开它）。
- `ProtocolDescriptorFlags.classConstraint` 同样漏了移位，那一位是 1 时就崩。
- `FunctionTypeFlags.convention` 既不掩码也不移位，把整个 flag word 直接转成 `UInt8`：不超过 255 时读到的是参数个数那几位，超过 255 就崩。

三处从 2025-10 首次提交起就在，本仓库的生产代码没有调用方，但都是公开 API。FrameworkToolbox 的提案 0015 加了 `@BitField`，即 C++ `FLAGSET_DEFINE_FLAG_ACCESSORS` / `FLAGSET_DEFINE_FIELD_ACCESSORS` 在 Swift 里的对应物：属性上只写占哪几位，移位、掩码和类型转换由宏与重载决议生成。本提案把这 17 个类型的访问器改成 `@BitField` 声明，三个 bug 随之修掉（先写复现测试）；另把 `ClassFlags` 与 `InvertibleProtocolSet` 改用 `@FlagSet`。

## 方案

以下都是未经询问就采用的假设，错了在批准前指出即可。

**前提**：FrameworkToolbox 发出同时包含 `@FlagSet` 与 `@BitField` 的版本（下一个是 0.17.0），本仓库 `Package.swift` 的下限从 `from: "0.4.0"` 抬到这个版本，`Package.resolved` 跟着更新。

**先写复现测试，再迁移。** 三个 bug 各一条测试，修复前会崩（单独运行确认），修复后通过，永久保留：

- `ExistentialTypeFlags`：读 `Any.self` 的 metadata，`classConstraint` 是 `.any`。同时删掉 `InProcessMetadataPicker` 与 `ExistentialTypeFlagsBaselineGenerator` 里「必须改用 `AnyObject.self`」的绕路说明。
- `ProtocolDescriptorFlags`：原始值 `0x2` 读成 `.any`。
- `FunctionTypeFlags`：分别读一个 Swift 闭包、`@convention(c)` 与 `@convention(block)` 函数的 metadata，`convention` 与之相符。

**迁移范围。** 每个访问器只剩 `@BitField(bits: …)` 加原来的名字与类型，位置照抄现在的掩码；17 个类型的每个位都已对照过 Swift 6.4 的 C++ 头文件，除上面三处外没有错位。

| 类型 | 迁移后 |
|---|---|
| `ContextDescriptorFlags` | kind、version、kind-specific flags 的原始值与三个 Bool；三个 `OptionSet` static 保留 |
| `TypeContextDescriptorFlags` | 全部；新增 `metadataInitialization` 字段，三个 `has…MetadataInitialization` 由它推出 |
| `ProtocolContextDescriptorFlags`、`AnonymousContextDescriptorFlags`、`ExtraClassDescriptorFlags` | 全部 |
| `MethodDescriptorFlags`、`ProtocolRequirementFlags`、`GenericRequirementFlags` | kind 与各个位；`isCoroutine`、`isAsync` 这类推导属性照旧手写 |
| `ProtocolConformanceFlags`、`GenericEnvironmentFlags`、`ExistentialTypeFlags`、`ProtocolDescriptorFlags`、`FunctionTypeFlags` | 全部 |
| `FunctionParameterTypeFlags`、`FunctionTypeExtendedFlags`、`ValueWitnessFlags`、`GenericMetadataPatternFlags`、`KeyPathComponentHeader` | 字段与位；哨兵值、按值比较的推导属性照旧手写 |

**公开 API 的变化：非可选的枚举字段。** 13 个字段现在是 `Kind(rawValue: …)!` 强制解包，`@BitField` 不接受「认不得就崩」，必须二选一：

- 会随编译器增长的 kind 改成可选：`MethodDescriptorFlags.kind`、`ProtocolRequirementFlags.kind`、`GenericRequirementFlags.kind`、两个 `TypeReferenceKind` 字段、`specialProtocol` / `specialProtocolKind`、`dispatchStrategy`、`convention`。本仓库约 30 处调用跟着改：`switch` 补一个 `nil` 分支，写清认不得的 kind 怎么办（dump 里照实印出原始值，不猜）；`== .sameType` 这类比较不用改。
- 只有一位、两种取值都已定义的三个 `classConstraint` 写 `default:`，类型不变。
- `ContextDescriptorFlags.kind` 现在就回落到 `.unknown`，写成 `default: ContextDescriptorKind.unknown`，类型不变。
- 下游：MachOKitUI 约 5 处要改，其中 `"\(requirement.flags.kind)"` 改成可选后会印出 `Optional(…)`，要显式处理；RuntimeViewer 与 swift-decompiler 没有直接用到这些字段。

**`@FlagSet` 的两处。**

- `ClassFlags`：从「每个 case 是一个掩码的枚举」改成 `OptionSet`，装得下多个位的组合。`ClassFlags.hasCustomObjCName.rawValue` 这类写法照旧编得过；对它的 `switch` 与可失败的 `init(rawValue:)` 不再成立，本仓库没有这样的用法。
- `InvertibleProtocolSet`：`InvertibleProtocolKind` 挪进结构体成为 `Flag`，旧名留一个 typealias；`hasCopyable` / `hasEscapable` 保留。
- `@FlagSet` 生成的 static 不在源码里，按语法扫描公开成员的覆盖率检查看不到它们，`CoverageAllowlistEntries` 与相关 baseline 里登记的名字跟着改。`@BitField` 不受影响：属性声明还在源码里。

**不迁移。**

- `MetadataRequest`：它要 setter，宏的第一版不生成；现在的手写版没有问题。
- 存储不叫 `rawValue` 的四处（`GenericParamDescriptor`、`EnumDescriptor`、`BuiltinTypeDescriptor`、`MultiPayloadEnumDescriptor`）：宏只读 `rawValue`。
- 已经正确的三个纯单比特 `OptionSet`（`FieldRecordFlags`、`GenericContextDescriptorFlags`、`AccessibleFunctionFlags`）。
- 仓库自己的 `FlagSet` / `MutableFlagSet` 协议保留：迁移后的类型照旧声明遵循，`flag(bit:)` 的调用方不受影响，`MetadataRequest` 还在用 `MutableFlagSet`。

**顺手记下、不在这次范围。** `ProtocolConformanceFlags.hasNonDefaultSerialExecutorIsIsolatingCurrentContext` 读的第 20 位只在 2025 年 3–4 月的 Swift 主线上存在过，6.1 到 6.3 的正式版头文件里都没有，读出来永远是 0：保留这个公开属性，在文档注释里写明。`ProtocolRequirementFlags` 缺 C++ 有的 `extraDiscriminator`；`TypeContextDescriptorFlags.classAreImmdiateMembersNegative` 的名字拼错了，改名要走废弃流程。

**验证。** 全量测试在 Ultra 上跑；渲染 A/B 验证（读取栈的大改动之后必须做）预期逐字节一致——三个读错的访问器都不在 `dump` / `interface` 的输出路径上，认不得的 kind 在系统框架里也不该出现。

**文档。** 演进账本记一节；`CLAUDE.md` 里 ABI 层那一段加一条「flag word 的访问器用 `@BitField` 声明，不手写掩码」；`SelfContainedABILayer.md` 判断要不要提一句。

## 落地步骤

每一步各自能构建、测试通过，单独提交。

- [x] 1. 依赖下限抬到包含两个宏的 FrameworkToolbox 版本；三条复现测试，确认修复前失败。
- [x] 2. 迁移 17 个类型，三个 bug 随之修掉；改成可选的字段的调用方跟着改；覆盖率清单与 baseline。
- [x] 3. `ClassFlags`、`InvertibleProtocolSet` 改用 `@FlagSet`；覆盖率清单。
- [x] 4. 全量测试与渲染 A/B；文档；给 MachOKitUI 提一份对应的改动。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-05 | Created as Draft | 调研 ABI 层能否用宏收掉样板时发现：17 个混排 flag word 手写成四种风格，三个访问器读错位；能表达这种形状的 `@BitField` 已在 FrameworkToolbox 0015 落地 |
| 2026-11-05 | 三个读错位的访问器不单独修，随迁移一起修 | 用户选定。迁移后它们由宏生成，单独修一遍等于改两次；在那之前它们没有生产调用方 |
| 2026-11-05 | `@FlagSet` 只用在 `ClassFlags` 与 `InvertibleProtocolSet` | 用户选定。`ClassFlags` 现在装不下组合，`InvertibleProtocolSet` 的种类枚举与集合是两处定义；另外三个纯单比特类型现在就是对的，改了只是统一写法，还要改覆盖率清单 |
| 2026-11-05 | 宏放在 FrameworkToolbox，不放本仓库的 `MachOMacros` | 用户选定。MachOObjCSection 等仓库也在读二进制里的 flag word |
| 2026-11-05 | 会随编译器增长的 kind 改成可选，三个 `classConstraint` 与 `ContextDescriptorFlags.kind` 写 `default:` | 用户选定。认不得的值不再让读取它的程序崩溃；代价是本仓库约 30 处、MachOKitUI 约 5 处调用跟着改。另一条路是私有的可选属性外包一层手写的强制解包，调用方不用改，但认不得的值照旧崩，没选 |
| 2026-11-05 | 前提已就位：FrameworkToolbox 发出 0.17.0 | 用户批准发版。0.17.0 同时包含 `@FlagSet`（0014）与 `@BitField`（0015） |
| 2026-11-05 | 用户批准，开始实现 | — |
| 2026-11-05 | 实测三条复现测试在修复前都让进程停下 | 在 Ultra 上用 Xcode 26.6 逐条跑：`ExistentialTypeFlags` 与 `FunctionTypeFlags` 报 `Not enough bits to represent the passed value`，`ProtocolDescriptorFlags` 报强制解包遇到 `nil`；迁移后三条都通过 |
| 2026-11-05 | `GenericRequirementDescriptor.content` 与 `ProtocolConformanceDescriptor.typeReference` 遇到认不得的 kind 照旧停下，改成带说明的 `preconditionFailure` | 两者的返回类型（`GenericRequirementContent`、`TypeReference`）没有能装下未知 kind 的 case，以前是 `kind` 的强制解包在这里停，现在 `kind` 本身能安全读取，停在真正无法往下的地方。要让它们也不停，得给两个枚举加分支，是另一次改动 |
| 2026-11-05 | `ExistentialTypeMetadata.representation` 把 `case .none` 写成 `case .some(.none)` | `SpecialProtocolKind` 自己有 `none` case，字段改成可选后，裸写的 `.none` 会被编译器当成 `nil`，只给警告、语义悄悄变了；全仓库只有这一处 |
| 2026-11-05 | dump 里认不得的方法 kind 印成 `[unknown kind, flags 0x…]`；协议要求的 kind token 认不得时是 `unknown` | 不猜，照实印出原始的 flag word；kind token 以前遇到这种情况会崩，所以没有已持久化的 key 用到它 |
| 2026-11-05 | baseline 生成器对改成可选的字段强制解包，baseline 文件不变 | fixture 里只有本库认得的 kind；生成器是维护者手动跑的工具，遇到认不得的值当场停下比写进一个哨兵值好查 |
| 2026-11-05 | 改了公开属性的类型之后先清掉构建产物再编 | 增量构建没有重编源码没变、却用到 `MethodDescriptorFlags.kind` 的 `VTableSlotAttributionTests.swift`，链接时还在找旧的非可选 getter；与 `CLAUDE.md` 里「改了 MachOSymbols 的结构布局要 clean」同一类 |
| 2026-11-05 | `InvertibleProtocolKind` 成为 `InvertibleProtocolSet.Flag` 的 typealias，raw value 从 `UInt8` 变成 `UInt16` | `@FlagSet` 生成的 `rawValue` 取 `Flag` 的原始类型，而集合存的是 16 位；唯一的调用方 `SymbolicDemangler` 经 `UInt64(…rawValue)` 读它，不受影响 |
| 2026-11-05 | `InvertibleProtocolSet` 的 Suite 只登记 `hasCopyable` / `hasEscapable` | `rawValue`、`init(rawValue:)` 与两个 static 改由 `@FlagSet` 生成，不在源码里，按语法扫描的覆盖率检查找不到它们，登记了就报「登记了不存在的成员」；Suite 里对它们的测试照旧保留、照旧运行 |
| 2026-11-05 | MachOKitUI 的对应改动放在它的 `feature/optional-flag-word-kinds`，经一个 `kindDescription` 帮手显示，认不得时写 `unknown` | 那 6 处都是把 kind 直接插进字符串，改成可选后不会编译失败，只会印出 `Optional(…)`；帮手收的是 `Kind?`，非可选的值会自动提升，所以对新旧两版 MachOSwiftSection 都能编。在 Ultra 上用只放这两个仓库的沙盒（`git archive`，`USING_LOCAL_DEPENDENCIES=1`，MachOSwiftSection 解析为本地 `fileSystem`）编过 `MachOKitUICore`（`--traits SwiftSection`）；MachOKitUI 还没有 `.worktrees/` 的忽略规则，加在本地的 `.git/info/exclude`，不改它受版本控制的 `.gitignore` |
| 2026-11-05 | 文档：演进账本记一节，`AGENTS.md` 的 ABI 层一段加了 flag word 的规则；`SelfContainedABILayer.md` 不改 | ABI 层早就经 MachOBase → Utilities 引入 FrameworkToolbox 的宏（`@CaseCheckable`、`@AssociatedValue`），这次没有新的依赖边；没有新术语 |
| 2026-11-05 | 不另写使用指南或实现说明 | 宏的用法与契约在 FrameworkToolbox 的 `BitField.md`；本仓库要遵守的写法（可选的 kind、`default:`、`.some(.none)`、改类型后先清构建产物）已写进 `AGENTS.md`，没有别的维护者会踩、代码里又看不出的决策 |
| 2026-11-05 | 实现完成，待用户看过后收尾 | 都在 Ultra 上用 Xcode 26.6 跑：全量 `swift test --skip IntegrationTests` 2,784 个测试全过；渲染 A/B 96 对逐字节一致，覆盖归档 cache、模拟器文件、进程内 `MachOImage` 三条读取路径；两份手改的 baseline 经 `regen-baselines` 重新生成后没有差异；MachOKitUI 对本分支编过 |
| 2026-11-05 | 落地，编号 0085，状态改 Implemented | 用户决定直接收尾，合入 `next` 时远端没有新提交，沿用上一行那次验证。摘要承诺的都已做到；留作后续的只有 `GenericRequirementDescriptor.content` 与 `ProtocolConformanceDescriptor.typeReference` 遇到认不得的 kind 仍会停下（见上文）。可选字段里裸写 `.none` 的陷阱同时补进了 FrameworkToolbox 的 `BitField.md`，那是宏的调用方都会踩的；不另配指南或实现说明、没有新术语的判断不变 |
