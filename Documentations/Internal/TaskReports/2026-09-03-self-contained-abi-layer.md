# 2026-09-03 ABI 层自包含：MachOSwiftSection 与符号索引分家

## 问题

用户在一次「整个库能否全 async 化」的调研中顺手提出：「ABI 不能反向依赖 SymbolIndexStore，ABI 接口应该自包含」。核实结果：`MachOSwiftSection` 对 `MachOSymbols` 有两条通道——五个描述符的 `RelativeDirectPointer<Symbols?>` 字段经 `Symbols` 的 `Resolvable` 实现走 `SymbolIndexStore.shared`，一次 ABI 访问触发整镜像符号扫描；`SymbolOrElementPointer` 把 `MachOSymbols.Symbol` 带进每一种上下文指针。提案 [draft-self-contained-abi-layer](../../Evolutions/draft-self-contained-abi-layer.md)。

## 调研

- 五个描述符（`MethodDescriptor`、`MethodOverrideDescriptor`、`MethodDefaultOverrideDescriptor`、`ProtocolRequirement`、`ResilientWitness`）的字段与访问器；`Symbols.resolve` → `machO.symbols(offset:)` → `SymbolIndexStore.shared.symbols(for:in:)` → 未建表就当场建。
- `ReadingContext` 腿没有符号服务，落到 `Resolvable` 默认的 `context.readElement(at:)`，把机器码按 `Symbols` 结构体读出来；三处 fixture 测试只断言「不为 nil」。
- MachOKitUI 在渲染 Swift section 前把 `MachOSymbols.Symbol.resolvesSymbolUsingIndexStore` 强行置 false（`MachOSwiftSectionDetailBuilder.swift:18-20`）——下游为此付过代价的证据。
- `MachOSwiftSection` 对 `Demangling` 的依赖只剩三处字符串帮手：`isSwiftSymbol`、`stripManglePrefix`、`cModule` / `objcModule`。
- 上层调用方：`SwiftDump` 三个 dumper、`SwiftDeclaration` 三个定义类、`MetadataReader` 一处、`OpaqueType+` 一处、三个 baseline 生成器、四个 fixture 套件。下游 RuntimeViewer 无影响，SymbolViewer 无影响（不用搬走的值类型），MachOKitUI 一行。

## 澄清提问（完整档，四轮）

1. 自包含到**包图级别**（否决代码级别）；`implementationSymbols` 扩展落 **`SwiftInspection`**。
2. 用户反问「下沉有意义吗」，答复：不下沉则包图级别不成立；随后确认**下沉** `MachOResolving`，`MachOSymbolPointers` 并入 `MachOPointers`。
3. 上游 swift-demangling 的执行器提案由本人起草（属另一提案）。
4. 用户口头批准「你这边弄 ABI」，状态置 Accepted → In Progress。

## 实际执行

worktree `.worktrees/MachOSwiftSection-SelfContainedABI`，分支 `feature/self-contained-abi-layer`，基于 `next` f3782248。

1. **先写红测试**：`MethodDescriptorTests` 对旧 API 比对两条腿的 `offset`——context 腿 -2999674702252736512，MachO 腿 5624，修前失败。
2. **值类型下沉**：`Symbol` / `Symbols` / `SymbolOrElement` 移到 `MachOResolving`；`Symbols` 去掉 `AsyncResolvable`，`init` 改 `package`；`Symbol` 的索引库 `resolve` 与 `resolvesSymbolUsingIndexStore` 留在 `MachOSymbols` 作扩展；`SymbolOrElementPointer` 并入 `MachOPointers`，`MachOSymbolPointers` target 删除。
3. **新伞模块 `MachOBase`**（`MachOKitExtensions` + `MachOReading` + `MachOResolving` + `MachOPointers` + `Utilities`）；`MachOFoundation` 改为 `MachOBase` + `MachOSymbols` + `MachODependencies`；`MachOSwiftSection` 163 个文件 `import MachOFoundation` → `import MachOBase`，`Exported.swift` 只再导出 `MachOBase`。
4. **描述符改地址接口**：字段 `RelativeDirectRawPointer`，`implementationOffset: Int?`，`implementationAddress(in context:)`；`ResilientWitness.implementationAddress(in machO:)` 随之变 `String?`。
5. **`SwiftInspection` 补五个同名扩展**（`Extensions/Descriptor+ImplementationSymbols.swift`），调用方去掉 `try` / `Symbols.resolve`。
6. **摘 `Demangling`**：`hasSwiftManglingPrefix` / `strippingSwiftManglingPrefix` / `CImportedModuleNames` 本地化。
7. **依赖声明补齐**：16 个 target 补 `.target(.MachOFoundation)`（原本只靠传递），12 个源码文件与若干测试文件补显式 import。
8. **测试**：四个 fixture 套件改比对 `implementationOffset` 真值与 context 地址等价；`MethodDefaultOverrideDescriptor` 的哨兵登记与覆盖 allowlist 同步；新增 `ManglingPrefixTests`（与 demangler 逐字符串对照）；红测试由新 API 上的等价断言永久替代；五个 baseline 用插件重生成（`MethodDescriptor` 的实现偏移钉为 `0x15f8`）。
9. **文档**：提案决策日志、实现说明 `SelfContainedABILayer.md`、AGENTS.md 模块图与条目、`Documentations/README.md`、模块参考覆盖表、演进账本（节号落地时取）、`Changelogs/0.18.0.md`、`Version.swift` 0.17.1 → 0.18.0、CI 过滤清单加五个套件。

## 验证

- `swift build --build-tests`：全部 target 编译通过，`Sources/` 零新增警告。
- `swift test --filter MachOSwiftSectionTests`：723 测试 / 161 套件全绿，退出码 0。
- 全量 `swift test --skip IntegrationTests` 与渲染 A/B：见文末补记。

## 与计划的偏离

- 提案写 `symbols(offset:) async` 标 deprecated 留一版；实测两个重载不能共存，改为删除。
- 提案只点名 `isSwiftSymbol` 一处 `Demangling` 用法；实际还有 `stripManglePrefix` 与 `cModule` / `objcModule`，一并本地化。
- 提案没预见 `MachOBase`；它是「163 个文件换一行 import」与「包图级别」两个要求的交点。
- 提案没预见 16 个 target 从未声明对 `MachOFoundation` 的依赖。

## 验证结果补记

- 全量 `swift test --skip IntegrationTests`：1617 测试 / 302 套件，仅 `SharedCache.resolve under Swift Concurrency` 的 `differentKeysParallelViaTaskGroup` / `differentKeysParallelViaAsyncLet` 失败——已知 flaky（墙钟断言并行度，当时渲染 A/B 的 release 构建正在同机跑），单独重跑 5 测试全绿、退出码 0。
- 渲染 A/B（`Scripts/run-rendering-ab-verification.py`，基线 = 集成 worktree 的 `next` f3782248，候选 = 本分支；两侧 `Package.resolved` 逐项一致，均为远程 pin）：**78 对输出逐字节一致，0 差异**。覆盖当前系统 dyld cache（归档 cache 目录名与脚本期望不符，按文档回退到系统 cache）、模拟器运行时 iOS 15.5 / 18.5 / 18.6 / 26.5（15.5 上 SwiftUICore / SwiftData / ActivityKit 不在运行时内，按规则跳过）、进程内 MachOImage 三条路径的 dump 与 interface。
- 红测试证据留档：修前 `MethodDescriptorTests.implementationSymbolsContextLegAgreesWithMachOLeg` 失败（context 腿 `offset` -2999674702252736512 vs MachO 腿 5624）；修后由 `implementationAddress` 测试的 `imageAddress == implementationOffset == 0x15f8` 永久替代。
- 未做：模拟器 UI 验证（不适用）；下游 MachOKitUI 的一行改动（`MachOSymbols.Symbol.resolvesSymbolUsingIndexStore` → `Symbol.resolvesSymbolUsingIndexStore` + `import MachOSymbols`）待其仓库跟进。
