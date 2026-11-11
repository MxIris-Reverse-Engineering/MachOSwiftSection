# Draft - interface 与 dump 给 existential 写上 `any`，并修好 constrained existential 字段的类型

- **状态**: Accepted
- **创建日期**: 2026-11-11
- **最后更新**: 2026-11-11
- **关联提案**: swift-demangling 一侧另起一份精简提案（slug 同为 `existential-any`，开工时创建），加 `DemangleOptions.useExistentialAny`。同一套做法的先例是 [0064-module-selectors](0064-module-selectors.md) 与 swift-demangling 的 `0017-module-selectors`。
- **实现分支 / PR**: 本库与 swift-demangling 都是 `feature/existential-any`

## 摘要

本库印 existential 类型时不写 `any`：`any P` 印成 `P`，`(any Error)?` 印成 `Swift.Error?`，`(any P).Type` 印成 `P.Protocol`，只有带 primary associated type 实参的 `any P<X>` 带 `any`。编译器从 SE-0335 起写 `.swiftinterface` 时，除了 `Any` 和 `AnyObject` 都写 `any`，Swift 6.4 也没有关掉它的选项（macOS 27.2 SDK 的 Foundation 接口里有 550 处）；`Collection` 这类有 associated type 的协议不写 `any`，编译器还会警告 "use of protocol 'Collection' as a type must be written 'any Collection'"。本提案让 interface 与 dump 默认照编译器的规则写 `any`。顺带修一个印错类型的 bug：存储属性 `any Boxed<Int>` 在 interface 里印成 `Swift.Int`，在 dump 里印成 `symbolic existential type (non-unique) 0x0 <Swift.Int>`，看不出是哪个协议。

## 方案

**写法**照编译器（`ExistentialType::get`、`TypePrinter::visitAnyMetatypeType`、`isSimpleUnderPrintOptions`）：

| 源码 | 现在 | 改后 |
|---|---|---|
| `any P`、`any P & Q` | `P`、`P & Q` | `any P`、`any P & Q` |
| `any C & P`、`any P & AnyObject` | `C & P`、`P & Swift.AnyObject` | `any C & P`、`any P & Swift.AnyObject` |
| `Any`、`AnyObject` | `Any`、`Swift.AnyObject` | 不变 |
| `(any P)?`、`(any P.Type)?` | `P?`、`P.Type?` | `(any P)?`、`(any P.Type)?` |
| `any P.Type`、`any (P & Q).Type` | `P.Type`、`P & Q.Type` | `any P.Type`、`any (P & Q).Type` |
| `Any.Type`、`AnyObject.Type` | `Any.Type`、`Swift.AnyObject.Type` | `any Any.Type`、`any Swift.AnyObject.Type`（编译器就这么写，SDK 里有 16 处 `any Any.Type`） |
| `(any P).Type` | `P.Protocol` | `(any P).Type` |
| `any P<X>` | 已带 `any` | 不变；在元类型里写成 `any P<X>.Type`，不重复写 `any` |

**swift-demangling**：新选项 `DemangleOptions.useExistentialAny`，命名照 `useModuleSelectors`，取自 SE-0335 的 upcoming feature `ExistentialAny`。不进任何预设，预设的输出仍与 Apple 的 demangler 逐字节一致。`NodePrinter` 按上表处理 `protocolList`、`protocolListWithClass`、`protocolListWithAnyObject`、`existentialMetatype`、`metatype` 与 `constrainedExistential`；选项打开时，可选类型与元类型的括号按带 `any` 的写法判断。发版后本库抬依赖下限。

**interface**：

- `SwiftDeclarationPrintConfiguration.usesExistentialAny`，默认打开；`InterfaceRequest.usesExistentialAny` 同名；CLI 用 `interface --no-existential-any` 关闭。
- 打印上下文照 `usesModuleSelectors` 的路子在创建时读一次；`TypeNodePrintable` 与 `BoundGenericNodePrintable` 按上表改；委托给上游打印器的地方带上新选项。
- `OpaqueTypeResolving.opaqueType(forNode:index:usesModuleSelectors:)` 的布尔参数换成一个 `DemangleOptions`，只认拼写类选项（`useModuleSelectors`、`useExistentialAny`）。opaque type 约束里的实参由 provider 自己打印，这样 `some Sequence<any Equatable>` 里的 `any` 才印得出来，以后再加拼写开关也不用再改签名。这是源码不兼容的改动，但实现方只有本库的 provider，RuntimeViewer 只构造它。

**dump**：CLI 默认带上 `useExistentialAny`，`--disable-existential-any` 关闭；与其他 demangle 选项一样走 `DemangleOptionGroup`，三个预设都生效。`DumpRequest.demangleOptions` 的默认值同步加上。dump 里的 constrained existential 沿用上游的写法 `any …Boxed<Self.Boxed.Wrapped == Swift.Int>`，与 dump 里符号那几行一致；interface 仍写成 `any …Boxed<Swift.Int>`。

**bug 修复**：字段记录里的 `any Boxed<Int>` 是一个 `symbolicExtendedExistentialType`，由 shape（`any Boxed<τ_0_0>`）和实参列表 `[Int]` 组成，两个打印器都只印了实参。改为在 `SymbolicDemangler` 解出类型之后，用 `GenericArgumentBinding` 把实参代回 shape，得到与 getter 符号里一样的 `constrainedExistential` 节点，dump、interface、ABI diff 拿到的都是正确的类型。连带：

- 原先协议不同、实参相同的两个字段在 ABI diff 里文字完全一样（都是 `symbolic existential type … <Swift.Int>`），字段换了协议查不出来；修复后能分开。
- ABI 快照里这类字段的文字变了，`ABISnapshotDocument.currentFormatVersion` 升到 12；旧快照读入时报版本不符，要重新生成。
- 静态布局引擎改为直接认 `constrainedExistential`（原先从 `symbolicExtendedExistentialType` 里往下找），布局数值不变。
- shape 读不出来时保留原节点，行为与现在一样。

**不动**：查找用的 key（固定预设打印，不带新选项）；ABI diff / snapshot / evolution 的写法（用 `.default` 预设，只有上面 bug 修复带来的字段文字变化）；TypeIndexing。RuntimeViewer 不用改代码，它取打印配置的默认值，升级后直接显示 `any`；要加设置项另议。

**测试与验证**：

- bug 先写复现测试，确认修复前失败。
- 新建现编 fixture（照 `ModuleSelectorFixture`），覆盖上表每一行，外加有 associated type 的 `any Collection`、`any Boxed<Int>` 字段、`(any Boxed<String>)?` 与 `some Sequence<any Equatable>`；interface 与 dump 各一组测试，开关关掉时输出与现在相同。
- swift-demangling 为每种节点补开关两种状态下的打印测试。
- 重新生成受影响的快照基线；全量测试在 Ultra 上跑。
- 渲染 A/B 跑两遍：候选关掉开关，应逐字节一致（constrained existential 字段那几行逐条核对）；打开开关，抽查差异只在 existential 的写法。候选一侧关开关，需要给 A/B 脚本和 MachOImage 那条腿各加一个入口；改完脚本重跑它自己的单元测试。
- CLI 加了 flag，同批更新 `AgentPlugins/swift-section` 的 skill。

**落地步骤**（每步各自构建通过、相关测试通过后提交）：

1. swift-demangling：`DemangleOptions.useExistentialAny` 与 `NodePrinter` 的改动、打印测试、该仓库的精简提案。
2. bug 修复：复现测试先红；`SymbolicDemangler` 代回实参，静态布局引擎认 `constrainedExistential`，ABI 快照格式升到 12，更新受影响的快照。
3. interface：打印配置、打印上下文、`TypeNodePrintable` / `BoundGenericNodePrintable`、opaque type provider 的拼写参数、`InterfaceRequest` 与 CLI 开关。
4. dump：`DemangleOptionGroup` 的开关、`DumpRequest` 的默认值。
5. 现编 fixture 与 interface / dump 测试，重新生成快照基线。
6. 验证与文档：全量测试、渲染 A/B（含脚本与 MachOImage 那条腿的关闭入口）、演进账本、模块文档、`AgentPlugins/swift-section` 的 skill。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-11 | Created as Draft | 用户确认 interface 与 dump 都改成写 `any`，并修好 `any Boxed<Int>` 字段印成 `Swift.Int` 的 bug |
| 2026-11-11 | 默认打开，配置与 CLI 都留关闭的开关 | 用户要的是改掉现在的写法；Swift 6.4 的编译器写接口文件时总是写 `any`，没有关掉的选项。0064 的模块选择器默认关闭，是因为那是 Swift 6.4 才有的新写法，SwiftUI 自己也关掉了 |
| 2026-11-11 | bug 在解析阶段修，不在两个打印器里各修一遍 | 改一处，dump、interface、ABI diff 与布局引擎拿到同一个正确的节点，还让 ABI diff 分得开协议不同的字段；代价是 ABI 快照格式升版 |
| 2026-11-11 | `Any.Type` 写成 `any Any.Type` | 照编译器，SDK 接口里就是这么写的 |
| 2026-11-11 | opaque type 的拼写参数并成一个 `DemangleOptions` | 两个布尔开关并成选项集合，以后再加拼写开关不用改签名 |
| 2026-11-11 | Draft → Accepted：用户批准，开始实现；补上落地步骤 | 精简提案原先没有拆步骤，按方案拆成六步，每步各自能构建、能测 |
