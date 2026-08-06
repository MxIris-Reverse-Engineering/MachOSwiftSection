# 嵌套字段偏移展开的环守卫（Nested Field-Offset Cycle Guard）

## 动机

用户在 RuntimeViewer 里对 Xcode 的 `DVTIconKit` 生成 Swift interface 时"死循环"：
应用挂住不返回，日志里 `walkNestedExpandedFieldOffsets reached nested field-offset
depth limit 16 — truncating expansion of …` 一条接一条地刷，1362 条之后仍在增长，
lldb 抓下来约 20 条线程全部堵在 demangle 上。

它不是真的死循环——深度上限 16 保证每条路径会终止。它是**指数级的路径枚举**，乘上
每个节点极高的固定开销，合起来跑不完。

### 根因一：有环的类型图上只做深度截断

`RuntimeFieldLayoutBackend.walkNestedExpandedFieldOffsets` 沿字段类型递归下钻，唯一
的约束是 `depth >= nestedFieldOffsetExpansionDepthLimit`（16）。深度上限约束的是
"走多深"；一旦类型图**有环**，爆炸的是"有多少条路径"，深度上限对此无能为力。

`DVTIconKit` 的图确实有环。从二进制符号可以直接读出两端的种类：

```
_$s10DVTIconKit35GeneratedIconPrimitiveReferenceSpecVMn   ← V = struct
_$s10DVTIconKit31GeneratedIconPrimitiveValueSpecOMn       ← O = enum
```

struct 持有 `Optional<GeneratedIconPrimitiveValueSpec<String>>`，而这个 enum 有一个
`reference` case，payload 就是那个 struct。遍历器于是在两者之间反复横跳直到第 16 层。
日志里各类型的截断计数（66 / 87 / 87 / 118 / 153 / 153 / 205 / 206 / 271）呈线性递推
增长，正是路径计数而非节点计数的形状。

### 根因二：`indirect` case 被当成内联 payload 下钻

上面那个环之所以能存在，是因为 enum 的递归 case 是 `indirect` 的——值类型的字段图想
成环，**只能**经过 indirect case（内联的自包含会是无限大小，根本编译不过）。

`indirect` case 的存储是一个堆 box 指针，声明的 payload 类型并**不**布置在该 case 的
偏移上。`walkNestedEnumPayloadFieldOffsets` 却直接按声明类型下钻，于是：

- 打印出的嵌套偏移指向根本不存在的内存；
- 环因此闭合。

同一文件里的 `enumPayloadSize` / `enumPayloadExtraInhabitantCount` 早就正确处理了这个
标志位，`SwiftLayout` 的 `EnumLayoutBridge`（第 185 / 250 行）也是；只有这两处字段展开
遍历是例外。

## 范围

两条路径各有一份独立实现，都改：

| 文件 | 引擎 |
|---|---|
| `Sources/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift` | 运行时（`MachOImage`，进程内 metadata） |
| `Sources/SwiftLayout/NestedFieldOffsetTree.swift` | 静态（`MachOFile`，离线描述符） |

两者不共享代码，因此各自需要自己的守卫与回归测试。

## 关键设计与取舍

### 环检测按「路径」而非「全局」

守卫持有的是**当前根到本节点这条路径上已经打开的类型集合**，而不是一个全局 visited 集。

这是有意的：同一个类型经由两个**不同字段**到达时，两处都必须完整展开（`String` 挂在两
个不同属性下面就是两棵真实的子树）。只有"重新进入一个在我上方仍然打开的类型"才是环，
也只有这种情况被切断。全局 visited 会把第二次出现的 `String` 整个吞掉，输出就残缺了。

两个引擎的 key 不同，因为它们手里的东西不同：

- 运行时路径用 `ObjectIdentifier(metatype)`——metatype 指针天然区分特化。
- 静态路径用**打印出来的类型名**，这样 `Box<Int>` 和 `Box<String>` 不会被当成同一个。
  名字在 `makeNode` 里本来就要算（用作 `typeName`），所以没有额外开销。

### 深度上限保留

深度上限没有被替换掉，它继续兜"无环但很深"的情况。两者约束的是不同的东西，缺一不可：
深度上限管深度，环守卫管路径数。`nestedFieldOffsetExpansionDepthLimit == 16` 的钉值
测试（`NestedFieldOffsetExpansionDepthLimitTests`）保持不变。

### `indirect` case 报告但不下钻

和 class 引用的处理完全一致：节点照常打印（case 名、类型名、偏移都还在），只是没有
子节点。不是整个跳过——跳过会让输出里凭空少一个 case。

### 两道守卫的分工（以及为什么都留着）

在**格式良好**的值类型字段图上，环只可能经过 indirect case，所以实际生效、真正消除
`DVTIconKit` 爆炸的是守卫二。

守卫一（路径环检测）是纵深防御，防的是**解析出错**造成的假环：
`resolveNestedMetatype` 有一条不带 context 的兜底解析
（`RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName)`），在真实二进制上
可能落到一个同名的别的类型上，制造出源语言根本不允许的环。它的代价只是一个 `Set`。

**这一点在测试上是诚实的**：本次的 fixture 无法单独触发守卫一（造不出不经 indirect
的值类型环），所以没有为它单独写测试。回归测试端到端地覆盖了两道守卫共同作用下的行为。

## 影响面

- 输出变化仅限于**此前就是错的**那部分：`indirect` case 底下不再打印它那些并不在该
  偏移上的"嵌套字段"；有环的类型不再重复展开同一条链。
- 无环类型的输出逐字不变（`acyclicNestingStillFullyExpands` 钉住这一点）。
- 性能：`DVTIconKit.GeneratedIconIconSpec` 从跑不完变成即时返回。fixture 上运行时路径
  从 892 行降到几十行。

## 回归测试

fixture 新增 `Tests/Projects/SymbolTests/SymbolTestsCore/RecursiveIndirectFieldLayout.swift`，
复刻 `DVTIconKit` 的形状：struct `ReferenceSpec` ↔ 逐 case `indirect` 的泛型 enum
`ValueSpec<Value>`，外加一个无环但三层深的 `AcyclicNesting` 作为对照。

| 测试套件 | 引擎 |
|---|---|
| `Tests/SwiftDeclarationRenderingTests/RecursiveNestedFieldOffsetExpansionTests.swift` | 运行时 |
| `Tests/SwiftLayoutTests/RecursiveNestedFieldOffsetTreeTests.swift` | 静态 |

各四个测试：树有界、单条路径上类型不重复、indirect case 是叶子、无环嵌套不被削。

修复前的实测（把两个源文件 stash 掉、只留 fixture 与测试）：8 个测试 6 个失败，
共 925 个 issue，运行时路径展开 892 行。失败信息直接打印出那条环：

```
type repeats on one path:
  ValueSpec<String> → ReferenceSpec → Optional<ValueSpec<String>> → ValueSpec<String>
```

### fixture 的一个刻意选择：逐 case `indirect`，而非整个 enum `indirect`

最初写成 `public indirect enum ValueSpec<Value>`，结果撞上一个**无关**的既有缺陷：
整个 enum `indirect` 会让每个 payload 都装箱，于是布局与 `Value` 无关——一个
argument-independent 的泛型 multi-payload enum，而本仓库的 `SwiftLayout` 引擎直到上游
`4eeb3b4` 才为这类 enum 采用编译器记录的 spare-bits 布局
（见 [TaskReports/2026-08-05-generic-fixed-mpe-spare-bits.md](TaskReports/2026-08-05-generic-fixed-mpe-spare-bits.md)）。
在落后于该提交的基线上，`WholeTypeLayoutVsRuntimeTests` 会报 `ReferenceSpec`
runtime 40 / static 56。

改成逐 case `indirect` 后 `literal(Value)` 仍是内联 payload，布局重新依赖实参，fixture
就不再碰这条无关的轴。附带两个好处：更贴近 `DVTIconKit`（那边也只有递归 case 装箱），
以及能验证守卫读的是**每个 case 的标志位**而不是整个 enum 的属性。

## 「以前修过吗」

修过——同一类问题，不同路径，而且教训没有被带过来。

- **2026-05-16**（[TaskReports](TaskReports/2026-05-16-fix-swiftinterface-print-path-dag-explosion.md)）：
  SwiftInterface **打印**路径上报过一模一样的"死循环"，根因同样是"不是死循环，是把
  DAG 当树展开"（实测 394,062 次节点访问）。当时的方案是 memoization + Apple 式
  MaxDepth 兜底，报告里白纸黑字写着候选方案 D「Apple-style MaxDepth 单一兜底 …… 对本
  死循环无效」。
- **2026-06-10**（PR #88，[TaskReports](TaskReports/2026-06-10-pr88-nested-recursion-depth-limit.md)）：
  三周后动了 `walkNestedExpandedFieldOffsets` 这一段，做的是把硬编码的 `16` 抽成常量、
  加 `os_log` 警告、加钉值测试——**只把深度上限诊断化了，没有意识到深度上限本身不足以
  约束**，尽管五月的报告已经给出了这个结论。

也就是说：这次不是回归，是那次修复的教训停在了打印路径上，没有横移到字段偏移展开路径。
本文档与两个回归套件补上这一步。

## 横向排查

按"同一个错误往往被复制在多处"的要求，两个模式都做了全库排查：

- **漏检 `isIndirectCase`**：全库读 enum payload record 的地方逐一核对——
  `EnumLayoutBridge`（185 / 250）、`enumPayloadSize`、`enumPayloadExtraInhabitantCount`
  都已正确处理；`SwiftDump.EnumDumper`、`SwiftPrinting`、`SwiftDiffing`、
  `SwiftDeclaration.TypeDefinition` 读该标志是为了打印 `indirect` 关键字，语义不同。
  遗漏的就是本次修的两处，没有第三处。
- **类型图递归缺环检测**：`SwiftSpecialization` 的
  `deriveNestedSpecializedTypeChildren`（同样是 `depth < 16`）遍历的是嵌套类型**声明**
  树（`struct A { struct B }`），天然无环，深度上限对它是充分的——不属于同一类，不改。

## 已知限制

- 环守卫按路径作用，因此**无环但高度共享的 DAG** 仍可能被按路径展开。真实类型图的
  共享分支很浅，目前没有观察到问题；若将来出现，正确的解法是 memoization（缓存每个
  类型的子树渲染结果），与 2026-05-16 在打印路径上采用的方案同构。
- 静态路径的 key 是打印出的类型名。两个不同类型若打印出完全相同的全限定名（跨模块同名
  且模块名也被省略时），会被误判为同一个。运行时路径按 metatype 指针，无此问题。
