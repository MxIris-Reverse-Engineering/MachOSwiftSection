# Draft - interface 与 dump 给 existential 写上 `any`，并修好 constrained existential 字段的类型

- **状态**: In Progress
- **创建日期**: 2026-11-11
- **最后更新**: 2026-11-11
- **关联提案**: swift-demangling 的精简提案 `draft-existential-any`（`Evolutions/draft-existential-any.md`，同名分支），加 `DemangleOptions.useExistentialAny`。同一套做法的先例是 [0064-module-selectors](0064-module-selectors.md) 与 swift-demangling 的 `0017-module-selectors`。
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
- `OpaqueTypeResolving.opaqueType(forNode:index:usesModuleSelectors:)` 的布尔参数换成一个 `DemangleOptions`（`spellingOptions:`），只认拼写类选项——集合 `DemangleOptions.interfaceSpellingOptions`，即 `useModuleSelectors` 与 `useExistentialAny`。opaque type 约束里的实参由 provider 自己打印，这样 `some Sequence<any Equatable>` 里的 `any` 才印得出来，以后再加拼写开关也不用再改签名；协议名本身只认模块选择器。这是源码不兼容的改动，但实现方只有本库的 provider，RuntimeViewer 只构造它。`SwiftDeclarationPrinter` 上同名的公开方法保留旧签名，标为废弃并转发到新签名。

**dump**：CLI 默认带上 `useExistentialAny`，`--disable-existential-any` 关闭；与其他 demangle 选项一样走 `DemangleOptionGroup`，三个预设都生效。`DumpRequest.demangleOptions` 的默认值同步加上，测试用的 `DemangleOptions.test` 也加上，dump 快照因此记录新写法。dump 里的 constrained existential 沿用上游的写法 `any …Boxed<Self.Boxed.Wrapped == Swift.Int>`，与 dump 里符号那几行一致；interface 仍写成 `any …Boxed<Swift.Int>`。

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

1. ✅ swift-demangling：`DemangleOptions.useExistentialAny` 与 `NodePrinter` 的改动、打印测试、该仓库的精简提案（`feature/existential-any`）。全量 651 个测试在 Ultra 上跑，与官方 demangler 逐字节对照的语料测试全过；只有新测试里 5 个可选类型用例的期望写错（`.default` 不合成 `?`），改用 `.interface` 并补两个 `XSq` 用例后通过。
2. ✅ bug 修复：`ConstrainedExistentialFieldTests`（interface、ABI 快照）与 `ConstrainedExistentialFieldDumpTests` 修复前 3 个测试全部失败，症状正是 `var boxed: Swift.Int` 与 `symbolic existential type (non-unique) 0x0 <Swift.Int>`；修复后相关的 43 个套件、209 个测试只剩两份快照不符，差异正好是这两个字段，已更新。
3. ✅ interface：打印配置、打印上下文、`TypeNodePrintable` / `BoundGenericNodePrintable`、opaque type provider 的拼写参数、`InterfaceRequest` 与 CLI 开关。
4. ✅ dump：`DemangleOptionGroup` 的开关、`DumpRequest` 与测试预设的默认值。
5. ✅ 现编 fixture `ExistentialAnyFixture` 与 `ExistentialAnyInterfaceTests`（26 个形状 × 开关两种状态）、`ExistentialAnyDumpTests`，命令映射测试。第一轮全量测试 2842 个测试 / 543 个套件：新测试全过，失败的是 12 份 fixture 快照、`FinalKeywordICFRegressionTests` 里 SourceEditor 的 `languageService`（协议类型，现在写 `any`），以及 `FileMappingTests.readersOfOneCacheFileShareOneMapping`。12 份快照重新录制，共 202 行变化，去掉 `any`、括号并把 `.Protocol` 当 `.Type` 之后与旧快照逐字节相同；SourceEditor 的期望改成 `any`。`readersOfOneCacheFileShareOneMapping` 是全量并发下的偶发：基线与候选单独跑都通过（候选连跑三次），与本改动无关。另补 `constrainedExistentialMetatypeIsLaidOutAsAMetatype`：把三处修复文件换回修复前的版本，它报 40 字节（值容器），修复后是 16 字节。
6. ✅ 验证与文档，都在 JHs-Mac-Studio-Ultra（macOS 27.2，Xcode 26.6）上跑；本库只让 swift-demangling 走本分支的本地副本，其余依赖两侧解析成同一份远端发布版（MachOKit 0.55.102、MachOKitExtensions 1.3.3、MachOObjCSection 0.8.206、swift-semantic-string 0.6.0）。
   - 全量 `swift test --skip IntegrationTests`：2843 个测试 / 543 个套件。失败只有两条，单独跑都通过：`FileMappingTests.readersOfOneCacheFileShareOneMapping` 在基线（`next` 577eadf2 + swift-demangling `next` 6489476）的全量里同样失败，是基线已有的并发偶发；`BoundedConcurrentMapTests.cancellationStopsSubmittingPendingElements` 只在三个任务同跑、负载 60 以上那一轮超出它一分钟的时限，前两轮候选与基线的全量都通过。
   - 渲染 A/B，基线同上，各预构建一次 release 后带 `--skip-build` 跑，96 对（归档 cache 15.5 与 26.6、iOS 16.4–26.5 模拟器、MachOImage 腿）。候选关掉 `any`（`--disable-existential-any` / `--no-existential-any` / `bareExistentials`）时 42 对逐字节一致，54 对共 185 行不同，全部来自 constrained existential 的修复：基线把这类字段印成实参（ActivityKit 的 `[Swift.String : Foundation.DataSwift.Never]`、SwiftUICore 的 `var base: A`），候选印出 `any Combine.Subject`、`any SwiftUI.Keyframes<A>`，另有 SwiftUICore 三处 `any AnimationFinishingDefinition<A>.Type` 的布局注释由 40 字节改为 16 字节。候选打开 `any` 再跑一遍，与关掉时相比改动 50207 行，去掉 `any`、括号并把 `.Protocol` 当 `.Type` 之后 96 对逐字节相同。
   - 关掉 `any` 那一轮暴露一处缺括号：可选的 constrained existential 元类型印成 `any …<A>.Type?`，已改为 `(any …<A>.Type)?` 并加测试。
   - A/B 脚本自己的单元测试 17 个全过（含新加的两个）。
   - 文档：演进账本、`Modules/SwiftInterface.md`、`StaticLayoutEngine.md`、`SystemFrameworkRenderingVerification.md`、`AGENTS.md`、`AgentPlugins/swift-section` 的 skill（其中点名的开关逐个对过各子命令的 `--help`）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-11 | Created as Draft | 用户确认 interface 与 dump 都改成写 `any`，并修好 `any Boxed<Int>` 字段印成 `Swift.Int` 的 bug |
| 2026-11-11 | 默认打开，配置与 CLI 都留关闭的开关 | 用户要的是改掉现在的写法；Swift 6.4 的编译器写接口文件时总是写 `any`，没有关掉的选项。0064 的模块选择器默认关闭，是因为那是 Swift 6.4 才有的新写法，SwiftUI 自己也关掉了 |
| 2026-11-11 | bug 在解析阶段修，不在两个打印器里各修一遍 | 改一处，dump、interface、ABI diff 与布局引擎拿到同一个正确的节点，还让 ABI diff 分得开协议不同的字段；代价是 ABI 快照格式升版 |
| 2026-11-11 | `Any.Type` 写成 `any Any.Type` | 照编译器，SDK 接口里就是这么写的 |
| 2026-11-11 | opaque type 的拼写参数并成一个 `DemangleOptions` | 两个布尔开关并成选项集合，以后再加拼写开关不用改签名 |
| 2026-11-11 | Draft → Accepted：用户批准，开始实现；补上落地步骤 | 精简提案原先没有拆步骤，按方案拆成六步，每步各自能构建、能测 |
| 2026-11-11 | 两个打印器里，「外层已经写了 `any`」的位置（existential 元类型的实例、`any P<X>` 的协议列表）直接印协议成员，不经带缓存的 `printName` | 两个打印器都按节点身份缓存打印片段，而 `any` 是唯一取决于父节点的写法：同一个 protocol list 节点在别处带 `any`、在这里不带，经 `printName` 会互相串用缓存。swift-demangling 有测试覆盖两种顺序 |
| 2026-11-11 | swift-demangling 的 `nestedNameOptions`（特化参数、宏名里的嵌套名字）也透传 `useExistentialAny` | 与 `useModuleSelectors` 同理，一行里不该混两种写法 |
| 2026-11-11 | dump 里的 constrained existential 用上游写法 `any …Boxed<Self.Boxed.Wrapped == Swift.Int>`，与同一份 dump 里 getter 符号那行一致 | 代回实参后的节点与 getter 符号里的节点同形，上游打印器对两者给出同一种写法 |
| 2026-11-11 | 静态布局引擎原先给 `any P<X>.Type` 的分支永远走不到（先找到的是内层的 constrained existential），会按值容器而不是元类型布局；随修复改为按元类型布局 | 修复后字段直接是 `existentialMetatype(constrainedExistential)`，走普通的元类型路径；`extendedExistentialLayout` 只留给没经过 `SymbolicDemangler` 的树，并复用同一个解析函数 |
| 2026-11-11 | interface 打印器遇到没解析出类型的 shape，交给上游打印器原样写出，不再印实参 | 把实参当成类型印出来是一个看起来对、实际错的类型；上游的原文至少名副其实 |
| 2026-11-11 | 特化器的诊断文字（`displayName(of:)`）也写 `any` | 它的约定是「照 interface 的写法」，interface 默认写 `any` 了 |
| 2026-11-11 | 两处已知缺口留作后续，这次不改：未展开 opaque 引用拼成 `@_opaqueReturnTypeOf("$s…", n) __<…>` 时，尖括号里的实参按 `.default` 打印；「展开的字段偏移」注释里嵌套字段的类型名在离线与进程内两条路径上都按 `.default` 打印 | 两处都不跟打印配置的拼写走，模块选择器当初同样没接；一处只在独立文件里 opaque 引用展开失败、实参又是 existential 时才碰到，另一处是注释里的类型名而不是声明本身。要接得把拼写选项一路传进 `OpaqueReferenceSpelling` 与 SwiftLayout 的 `NestedFieldOffsetTree`，超出这次的范围 |
| 2026-11-11 | 开关关掉时，可选的 constrained existential 元类型也加括号：`(any P<Int>.Type)?` | constrained existential 无论开关都写 `any`，它的元类型同样以 `any` 开头；A/B 里 SwiftUICore 的 `finishingDefinition` 印成 `any …<A>.Type?`，不是合法的 Swift。上游打印器在选项关闭时保持与官方 demangler 一致，不改 |
| 2026-11-11 | 实现完成，待用户看过后收尾。配套文档：不另写使用指南或实现说明，写法规则在提案与 swift-demangling 的 README，实现要点在 `AGENTS.md` 与模块文档；新术语：无 | 落地步骤六步全部完成并验证 |
