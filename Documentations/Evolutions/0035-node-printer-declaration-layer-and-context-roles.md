# 0035 - NodePrinter 补声明层协议、Context 按层拆角色

- **状态**: Implemented
- **创建日期**: 2026-09-18
- **最后更新**: 2026-09-19
- **关联提案**: [0015](0015-type-name-resolver-role-split.md)（delegate 侧的角色化拆分，本案对 printer 自身状态用同一手法）、[0034](0034-interface-printer-node-kind-parity.md)（最近一次大面积触碰这组文件；本案不改任何 `case` 的输出）
- **实现分支**: `feature/node-printer-declaration-layer`，worktree `.worktrees/MachOSwiftSection-NodePrinterDeclarationLayer`，从 `next` 切出

## 摘要

`SwiftPrinting/NodePrintables/` 把类型表达式的打印按节点家族拆成五个带默认实现的协议，由 `InterfaceNodePrintable` 串成责任链，这一层成立。问题在上面一层 `SwiftPrinting/NodePrinter/`：`VariableNodePrinter` / `SubscriptNodePrinter` / `FunctionNodePrinter` 三个 struct 没有对应的协议中间层，声明级逻辑（`final` / `override` / `static` 修饰符、从 `global` 到实体节点的解包链、`targetNode` 包 `.static`、`isProtocol` 探测、`where` 子句、`{ get set }` 访问器块、`boundGenericFunction` 拆分）各抄一遍，三个文件约六成的行互为副本；四个 struct 又各自平铺同样的 9 个状态字段。另外，现有的 `Context` associatedtype 只装了 `isAllocator` / `isBlockOrClosure` 两个只对当前节点生效的提示，五层里只有 FunctionType 一层读它，其余四层收下即丢，而每层真正都要的那些状态反而散在 printer 的字段上。

本提案做两件事。一，补一个 `MemberDeclarationNodePrintable` 协议，把上述声明级逻辑收成默认实现，三个 struct 只留自己的 flag 和一个 `printDeclaration(_:)`。二，`Context` 改为 printer 上一个存储的可变状态，按层拆成角色协议，每个 `*NodePrintable` 只声明自己读写的那几个属性；原来的两个每次调用提示改成普通参数 struct `NodePrintOptions`。输出逐字节不变，7 处构造调用点与 28 处测试构造的签名不变，全部涉及类型为 internal，无公开 API 变更。

## 方案

### 1. 声明层协议 `MemberDeclarationNodePrintable`

新文件 `NodePrintables/MemberDeclarationNodePrintable.swift`，继承 `InterfaceNodePrintable`：

- **requirement**：`isFinal` / `isOverride` / `isClassMember` 三个只读 flag；`static var declarationNodeKinds: Set<Node.Kind>`（Variable 为 `[.variable]`，Subscript 为 `[.subscript]`，Function 为 `[.function, .boundGenericFunction, .allocator, .constructor]`）；`mutating func printDeclaration(_ node: Node) async throws`。
- **默认实现**：
  - `printRoot(_:)`：写 `final` / `override`，进入解包链，返回 `target`。
  - 解包链：`.global` 跳过 `needsSkipFirstNodeKinds`；`.static` 写 `class` / `static` 并把 `isStatic` 作为**参数**带下去（不再是存储状态）；`.methodDescriptor` / `.protocolWitness` / `.getter` / `.setter` 透传；命中 `declarationNodeKinds` 则先 `enterDeclaration(_:isStatic:)` 再 `printDeclaration(_:)`；其余抛 `MemberDeclarationPrintError.unsupportedNode(_:expected:)`；变量节点既无 `identifier` 也无 `privateDeclName` 时抛同一枚举的 `missingIdentifier(_:)`。
  - `enterDeclaration(_:isStatic:)`：设 `context.targetNode`（`isStatic` 时包一层 `.static`，用的是原节点）与 `context.isProtocol`（探测用 `boundGenericFunction` 里层的实体节点，因为它自己的第一个孩子是函数而不是上下文；这与原 Function / Subscript 的行为一致）。
  - `printWhereClause(of:)`、`printAccessorBlock(hasSetter:indentation:)`、`splitBoundGenericFunction(_:) -> (function: Node, genericArguments: Node?)`。
- `TypeNodePrinter` 不是成员声明，仍直接 conform `InterfaceNodePrintable`。

### 2. Context 改为存储状态并按层拆角色

`NodePrintable` 的 requirement 从 9 个收成 `target` / `context` / `delegate` 三个；`printName` 的 `context: Context?` 参数改为 `options: NodePrintOptions`。各层在自己的文件里声明只含自己读写属性的角色协议，并以 `where Context: XxxContext` 约束：

| 文件 | 角色协议 | 属性与读写权限 |
|---|---|---|
| `NodePrintable.swift` | `NodePrintableContext` | `dependentMemberTypeDepth { get }`（`shouldPrintContext` 读） |
| `TypeNodePrintable.swift` | `TypeNodePrintableContext` | `targetNode { get }`（`printOpaqueReturnType` 读） |
| `DependentGenericNodePrintable.swift` | `DependentGenericNodePrintableContext` | `isProtocol { get }`、`dependentMemberTypeDepth { get set }`、`packExpansionDepth { get }`、`knownPackParameterNames { get set }` |
| `FunctionTypeNodePrintable.swift` | `FunctionTypeNodePrintableContext` | `packExpansionDepth { get set }`、`knownPackParameterNames { get set }` |
| `InterfaceNodePrintable.swift` | `InterfaceNodePrintableContext`（继承上面四个） | `associatedtype Target: NodePrinterTarget`、`printDepth { get set }`、`printCache: [ObjectIdentifier: Target] { get set }` |
| `MemberDeclarationNodePrintable.swift` | `MemberDeclarationNodePrintableContext` | `isProtocol { get set }`、`targetNode { get set }` |

- `BoundGenericNodePrintable` 不碰任何状态，不设角色协议。
- 两层同时声明 `knownPackParameterNames` 是刻意的：FunctionType 在 `printPackExpansion` 写，DependentGeneric 在 `printGenericSignature` 写、在 `printDependentGenericParamType` 读，各自声明自己的权限，最终由一个存储属性同时满足两边。`isProtocol` 在 DependentGeneric 只有 `get`，在声明层才有 `set`，谁能改一眼可见。
- 具体类型 `struct InterfaceNodePrinterContext<Target: NodePrinterTarget>`，同时 conform `InterfaceNodePrintableContext` 与 `MemberDeclarationNodePrintableContext`，7 个存储属性全在这里。四个 printer 各写 `typealias Context = InterfaceNodePrinterContext<SemanticString>` 与 `var context = Context()`。`InterfaceNodePrintable` 以 `where Context: InterfaceNodePrintableContext, Context.Target == Target` 把两个 associatedtype 对齐。
- 性能：`context` 是具体 struct 的存储属性，经 requirement 修改走 modify accessor 原地改，`printCache` 与 `knownPackParameterNames` 不会因此多一次 CoW 复制。协议扩展里用计算属性转发旧名字才会有那个问题，本案不做转发。

### 3. 每次调用的提示改为 `NodePrintOptions` 参数

```swift
struct NodePrintOptions: Equatable {
    var asPrefixContext = false
    var isAllocator = false
    var isBlockOrClosure = true
    static let `default` = NodePrintOptions()
}
```

- `printName(_:options:)` 是唯一 requirement；protocol requirement 不能带默认参数，所以扩展提供一个无 options 的 `printName(_:)` 便捷重载，原来的四个重载合成这一个。
- `canCache` 的条件从「`!asPrefixContext && context == nil && …`」改为「`options == .default && …`」，语义等价。
- 删掉旧的 `NodePrintableContext` 空标记协议、旧 `InterfaceNodePrintableContext`、`FunctionTypeNodePrintableContext` 里的 `init()` 要求，以及 `printLabelList` 里 `var context = Context()` 那段构造。

### 4. 顺带清理

- `printName` 家族的 `-> Node?` 返回值与 `@discardableResult`：所有路径都返回 nil，是上游 `NodePrinter` 的化石，删。
- `shouldPrintContext` 的 `.module` 分支两侧都返回 true，删分支。
- 三个单 case 的 `Error` enum 合成 `MemberDeclarationPrintError`。
- `printGenericSignature` 末尾注释掉的 `where` 块删掉，`where` 子句统一归 `printWhereClause(of:)`。
- 两个目录内的缩写标识符改全名（`o` / `r` / `c` / `s` / `S` / `t` / `pdn` / `prot` / `sig` / `dt` / `depType` / `gpDepth` / `c0` / `c1` / `numGenericParams` / `diffKind` / `argIndex` 等）。

### 5. 改完后每个 printer 的形状

```swift
struct VariableNodePrinter: MemberDeclarationNodePrintable {
    typealias Context = InterfaceNodePrinterContext<SemanticString>
    var target: SemanticString = ""
    var context = Context()
    private(set) weak var delegate: (any NodePrintableDelegate)?
    let isFinal, isOverride, isClassMember, isStored, hasSetter: Bool
    let indentation: Int
    static let declarationNodeKinds: Set<Node.Kind> = [.variable]

    init(isStored: Bool, isOverride: Bool, isClassMember: Bool = false, isFinal: Bool = false, hasSetter: Bool, indentation: Int, delegate: (any NodePrintableDelegate)? = nil)   // 签名不变

    mutating func printDeclaration(_ node: Node) async throws {
        // let / var、标识符、类型，然后 printAccessorBlock
    }
}
```

粗估：Variable 150 → 约 60 行，Subscript 149 → 约 50 行，Function 181 → 约 90 行，Type 38 → 约 25 行。

### 未询问即采用的假设

- 走 feature 分支加独立 worktree，不在 `next` 直落。`NodePrintables/` 每个文件都会动；in-flight 的 `draft-interface-hides-compiler-synthesized-members` 触碰过 `SwiftDeclarationPrinter+PropertyWrapperSynthesis.swift` 里的 `VariableNodePrinter` 构造，签名不变即零冲突。
- `target` 与 `delegate` 留在 printer 上，不进 Context（理由见决策日志）。
- 缩写改名限于 `NodePrinter/` 与 `NodePrintables/` 两个目录。
- 不另立实现说明，裁决记在本文决策日志。`Internal/Modules/` 目前没有 SwiftPrinting 的模块文档，不在本案新建。

### 验收

1. `USING_LOCAL_DEPENDENCIES=1 swift test --scratch-path /tmp/claude/SwiftPM/MachOSwiftSection --filter SwiftPrintingTests` 与 `--filter SwiftInterfaceTests` 全绿，以原始退出码为准。
2. 渲染 A/B 验证（AGENTS.md 规定触碰 printing 的大重构必跑）：按 [SystemFrameworkRenderingVerification.md](../Internal/SystemFrameworkRenderingVerification.md) 对真实系统框架跑三条 reader 路径的 `dump` + `interface`，与 `next` 基线逐字节一致。
3. `git diff --stat`：四个 printer 文件净减行；`NodePrintables/` 不新增 `case`、不改任何输出行为。

### 验收结果（2026-09-19，worktree `MachOSwiftSection-NodePrinterDeclarationLayer`）

| 项 | 结果 |
|---|---|
| 构建 | `swift build --build-tests` 通过，`NodePrint*` 无警告 |
| `SwiftPrintingTests` | 34 / 34 通过（改动前基线同为 34 / 34） |
| `SwiftInterfaceTests` | 201 个里 4 个失败，**改动前后失败集合完全相同**：`ProjectedOpaqueMemberWitnessTests` 四例的即时编译 fixture 报 `emitting module interface files requires '-language-mode'`，是工具链变化带来的既有问题，与打印器无关，不在本案处理 |
| 渲染 A/B | `Scripts/run-rendering-ab-verification.py`，**96 对全部逐字节一致**：归档 cache macOS 15.5 与 26.6（12 对）、模拟器 iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5（36 对）、进程内 MachOImage 当前系统六框架 image + file 双路（24 对），最大单文件 SwiftUICore interface 约 17.7 万行；`RenderingVerificationTests` 两侧各约 8 分钟通过 |
| 行数 | 四个 printer 150 / 149 / 181 / 38 → 64 / 51 / 97 / 24；`Sources/SwiftPrinting` 净减 246 行（含新增 162 行的 `MemberDeclarationNodePrintable.swift`） |

A/B 的基线侧没有用 `next` worktree，而是同一 commit（829667b2）的临时 detached 检出 `.worktrees/MachOSwiftSection-ABBaseline`，跑完即删：`next` worktree 的 `Package.resolved` 是没开 `USING_LOCAL_DEPENDENCIES` 时生成的（MachOKit / swift-demangling 等钉在远端，swift-fileio 与 swift-fileio-extra 也比现在旧一版），在本案环境下构建会被 SwiftPM 就地重写。两侧 `Package.resolved` 逐字节一致后才开跑。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-18 | Created as Draft | 用户审阅 `NodePrinter/` 与 `NodePrintables/` 两目录，认可按节点家族拆协议的方向，但指出 Printer 一层重复代码多 |
| 2026-09-18 | 四个候选里选「补声明层协议」，而非最小抽 helper、单 struct 加 enum、会话 / 作用域 / 算法三分 | 与 `NodePrintables/` 既有手法一致，保留按种类分文件，零调用点改动；三分方案是终点形态但改动最大，且该模块近期提交密集，合并摩擦最小的方案优先。三分方案可日后从本案的默认实现演进过去 |
| 2026-09-18 | 9 个字段收进 `Context` 并按层拆角色协议，而非另立 `NodePrintTraversalState` | 用户本意是「每个 Printable 只知道自己需要的 Context」。现有 `Context` 恰好只装了一层要看的东西，所以其余四层没人用；改成状态载体后每层都有自己的切片 |
| 2026-09-18 | `isAllocator` / `isBlockOrClosure` / `asPrefixContext` 不进存储 Context，改为 `NodePrintOptions` 参数 | 三者只对当前节点生效。存到 context 上会漏给子节点：`printLabelList` 用 `isBlockOrClosure = false` 省掉函数声明的 `-> ()`，参数里的闭包 `(Int) -> Void` 也会看到 false 而打成 `(Int)`。现状靠中间 helper 不转发 context 才没漏，把它做成参数是把这个约束写明 |
| 2026-09-18 | `isStatic` 作为解包链参数传递，不进 Context | 只在解包链内部从 `.static` 节点流到终点，`enterDeclaration` 用过即弃，没有跨调用的生命周期 |
| 2026-09-18 | `target` 与 `delegate` 留在 printer 上 | `target` 是输出不是上下文，且在 `NodePrintables/` 有约 150 处调用；`delegate` 是 weak 引用，协议 requirement 表达不了 weak，保持现状最省 |
| 2026-09-18 | `NodePrintOptions.isBlockOrClosure` 默认 true | 现状 `context == nil` 时取 true、`Context()` 时取 false，两个「默认」不一致；`Context()` 只在 `printLabelList` 构造并立刻赋满两个值，旧默认值从未被观察到，改成 true 无行为变化 |
| 2026-09-18 | 用户批准提案（Accepted），随即开工（In Progress） | 聊天里逐项确认了方案、Context 角色划分与未询问即采用的假设；worktree `.worktrees/MachOSwiftSection-NodePrinterDeclarationLayer`，分支 `feature/node-printer-declaration-layer` 自 `next` 829667b2 切出 |
| 2026-09-19 | 四个 fixture 编译失败的 `SwiftInterfaceTests` 不在本案修 | 改动前后失败集合逐一相同，根因是 `-language-mode` 缺失这一工具链变化，横向属于测试基础设施而非打印器；单独立案更干净 |
| 2026-09-19 | 合入 `next`，落地编号 0035（远端 main / next 与本地的全局最大为 0034）；状态 Implemented | Implemented 的两问：不另立实现说明，裁决全在本决策日志，且两篇已有实现说明（PrinterNodeKindParity、FinalKeywordAndLazyAccessorTypeRecovery）指向旧布局的句子已同步；没有新术语需要进术语表，「角色协议」沿用 0015 的用法 |
| 2026-09-19 | 追记（合入后）：四个 printer 的 `Target` 泛型化，`Semantic*NodePrinter` 别名钉 `SemanticString`，`declarationNodeKinds` 改计算属性（泛型类型不能有 static 存储属性）；测试新增记录型 target `RecordingPrinterTarget` 与六个测试 | 用户追加。方案四列为终点形态的「Target 真泛型」提前兑现——Context 已是 `InterfaceNodePrinterContext<Target>`，只差 printer 自己。第二个 Target 让泛型参数不是摆设：`String` 与 `SemanticString` 渲染同文；记录型 target 断言 scope 推入弹出配对、bound generic 标点落在 barrier 下而名字落在各自 nominal 的 scope、`final` / `func` 带 `.printKeyword` 与标识符带 `.printIdentifier` + `parentKind`、memo 片段经 `append` 拼接——这些是纯文本快照看不见的契约。写 mock 时踩到并记进测试注释的一条：`append` 不合并事件就丢掉整棵 memoized 子树，正是 `NodePrinterTarget` 文档对 `append` 的警告 |
| 2026-09-18 | 三个都叫 context 的概念分开命名 | 存储状态叫 `Context`（沿用用户用词）；每次调用的参数叫 `NodePrintOptions`；上游 `NodePrintContext` 是给 target 做语义标注的，不动 |
| 2026-09-18 | 顺带把 A/B 验证脚本的归档 cache 常量从 `26.6.2` 改为 `26.6` | 归档卷又改了目录名（`26.6.2` → `26.6`，旁边新增 `27.0`）。脚本对不存在的目录静默跳过，不改的话 macOS 26 这条腿整段消失而报告照样「全部一致」，正是验证文档记录过的陷阱；文档同步补了一句 |
