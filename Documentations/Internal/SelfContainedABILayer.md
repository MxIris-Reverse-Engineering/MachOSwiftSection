# ABI 层自包含：MachOSwiftSection 与符号索引分家

提案：[draft-self-contained-abi-layer](../Evolutions/draft-self-contained-abi-layer.md)。本文记录落地后的形态，以及那些从签名上看不出来、下次维护会踩的决策。

## 改了什么

| 之前 | 之后 |
|---|---|
| `MachOSwiftSection` 依赖 `MachOFoundation` 伞模块（含 `MachOSymbols`、`MachODependencies`）和 `Demangling`，并把伞模块整个再导出 | 只依赖新的底层伞模块 `MachOBase`（`MachOKitExtensions` + `MachOReading` + `MachOResolving` + `MachOPointers` + `Utilities`）并再导出它；`Package.swift` 上看不到符号索引与 demangler |
| 五个描述符的 Layout 字段是 `RelativeDirectPointer<Symbols?>`，访问器 `implementationSymbols(in:)` 一调就建整镜像符号索引 | 字段是 `RelativeDirectRawPointer`，访问器 `implementationOffset: Int?`（纯指针算术）与 `implementationAddress(in context:)`；`ProtocolRequirement` 用 `defaultImplementation…` 前缀 |
| `implementationSymbols(in:)` 家族在 ABI 层 | 同名扩展在 `SwiftInspection`（`Extensions/Descriptor+ImplementationSymbols.swift`），实现是拿偏移问 `machO.symbols(offset:)`；只有 MachO 一条腿 |
| `Symbol` / `Symbols` / `SymbolOrElement` 在 `MachOSymbols`，`Symbols` 是 `AsyncResolvable` | 三个纯值类型在 `MachOResolving`；`Symbols` 不再是 `Resolvable`；`Symbol` 走索引库的 `resolve(from:in:)` 与 `resolvesSymbolUsingIndexStore` 作为扩展留在 `MachOSymbols` |
| `SymbolOrElementPointer` 独占一个 `MachOSymbolPointers` target | 并入 `MachOPointers`，target 删除 |
| `String.isSwiftSymbol` / `stripManglePrefix`、`cModule` / `objcModule` 来自 `Demangling` | 本模块自有 `hasSwiftManglingPrefix` / `strippingSwiftManglingPrefix`（`Extensions/String+.swift`）与 `CImportedModuleNames`（`Models/Mangling/`），`ManglingPrefixTests` 钉住与 demangler 一致 |

分层由编译器守：`MachOSwiftSection` 的依赖列表里没有 `MachOSymbols` 与 `Demangling`，回归就是编译错误。

## 从签名看不出来的决策

### 为什么多了一个 `MachOBase` 伞模块

`MachOSwiftSection` 里 163 个文件写着 `import MachOFoundation`。把它们改成四五行显式 import 是同样的信息量却多了几百行 diff，而且以后每个新文件都要重复一遍。`MachOBase` 把「ABI 层允许看到的一切」定义成一个名字，`MachOFoundation` 变成 `MachOBase` 加符号索引加依赖解析。下游 `import MachOSwiftSection` 仍能拿到指针与 reader 类型（`MachOSwiftSection` 再导出 `MachOBase`），拿不到的只有 `MachOSymbols` 与 `MachODependencies`。

### 为什么 `ReadingContext` 那条腿没有符号形态

`ReadingContext` 没有任何符号服务可用。旧的 `implementationSymbols(in context:)` 因此落到 `Resolvable` 的默认 `context.readElement(at:)`，把函数入口的机器码按 `Symbols` 结构体（一个 `Int` 加一个数组引用）读出来。修前的红测试（`MethodDescriptorTests`，对旧 API 比对两条腿的 `offset`）给出的数字：context 腿 -2999674702252736512，MachO 腿 5624。它没崩只是因为读出的假数组指针恰好是非规范地址，运行时的 retain / release 会跳过它。三处 fixture 测试只断言「不为 nil」，永远绿。现在 context 腿给的是 `implementationAddress(in:) -> Context.Address?`，`MachOContext` 上就是偏移本身，测试断言它等于 `implementationOffset`。

### 为什么不给 `MachOSymbols` 留 `typealias Symbol`

`MachOFoundation` 同时再导出 `MachOSymbols` 与 `MachOResolving`。若 `MachOSymbols` 里有 `public typealias Symbol = MachOResolving.Symbol`，所有 `import MachOFoundation` 的文件里不限定的 `Symbol` 都有歧义风险。限定名 `MachOSymbols.Symbol` 的已知调用方只有 MachOKitUI 一处（`MachOSwiftSectionDetailBuilder.swift`），改一行即可。

### 为什么 `symbols(offset:) async` 是删除而不是废弃

它与同步版逐字相同，本想标 deprecated 留一版。但 async 上下文里编译器优先绑定 async 重载并要求 `await`，`if let symbols = machO.symbols(offset:)` 这种链式条件在 `ProtocolDefinition.index` 等四处直接报错。两个重载不能共存，只能删。

### `Symbol.resolve(from:in:)` 为什么还在

`MetadataReader` 的 `MachOContext.lookupSymbol` 与 `SwiftDeclarationRendering` 的 `OpaqueType+` 仍用它，且它承载 `resolvesSymbolUsingIndexStore` 开关（MachOKitUI 会置 false）。它现在是 `MachOSymbols` 里 `Symbol` 的静态扩展方法，不再是 `Resolvable` 要求：语义是「查」不是「读」。

### `ResilientWitness.implementationAddress(in:)` 的两个形态

原有的 MachO 版是调试用的地址字符串格式化器，随 `implementationOffset` 变 `Int?` 一起变成 `String?`。新增的 context 版返回 `Context.Address?`。两者同名、靠参数类型区分（`MachOFile` / `MachOImage` 不是 `ReadingContext`，`MachOContext` / `InProcessContext` 不是 `MachOSwiftSectionRepresentableWithCache`），覆盖不变量按成员名登记一次即可。

### 靠再导出拿到符号模块的文件

`MachOSwiftSection` 不再带出 `MachOSymbols` / `MachODependencies` 后，仓库内 12 个源码文件与若干测试文件补了显式 `import MachOFoundation` / `import MachOResolving`，`Package.swift` 里 16 个 target 补上原本只靠传递拿到的 `.target(.MachOFoundation)`（`SwiftInspection`、`SwiftDump`、`SwiftDeclaration`、`SwiftIndexing`、`SwiftPrinting`、`swift-section` 与十个测试 target）。这些依赖本来就在用，只是没声明。

## 下游迁移

| 调用点 | 改法 |
|---|---|
| `try d.implementationSymbols(in: machO)` | 去掉 `try`，文件补 `import SwiftInspection` |
| `d.implementationSymbols(in: context)` | 删除；要位置用 `try d.implementationAddress(in: context)` |
| `try Symbols.resolve(from: offset, in: machO)` | `machO.symbols(offset: offset)`（`MachOSymbols`） |
| `MachOSymbols.Symbol` 限定名 | 不限定，或 `MachOResolving.Symbol` |
| `import MachOSymbolPointers` | 删除（并入 `MachOPointers`） |
| 经 `import MachOSwiftSection` 间接用 `SymbolIndexStore` 等 | 补 `import MachOFoundation` |
| `ResilientWitness.implementationOffset` | 现在是 `Int?` |

## 验证

- `MachOSwiftSectionTests` 723 测试 / 161 套件全绿（五个重生成的 baseline、覆盖不变量、`ManglingPrefixTests`）；全量 1617 测试仅两个已知 flaky 的墙钟并行度断言假失败，单独重跑全绿。
- 渲染 A/B 78 对输出逐字节一致：系统 dyld cache、iOS 15.5 / 18.5 / 18.6 / 26.5 模拟器运行时、进程内 MachOImage 三条路径的 dump 与 interface。默认输出与布局注释均不经过被改动的符号路径以外的逻辑，结果符合预期。
- 过程复盘：[TaskReports/2026-09-03-self-contained-abi-layer.md](TaskReports/2026-09-03-self-contained-abi-layer.md)。
