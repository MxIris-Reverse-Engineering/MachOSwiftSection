# Extensions（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/extensions.tex`（《Compiling Swift Generics》一书的「Extensions」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是全书与本库（MachOSwiftSection）对应关系最密的一章之一。二进制里没有「extension descriptor」这种东西——编译器把 extension 的成员摊平成普通符号，把 extension 上声明的 conformance 变成一条 protocol conformance descriptor。本库反过来做：按 (extended type, protocol, `where` 指纹, retroactive) 四元组把成员归拢回 extension 容器，靠符号扫描恢复 protocol extension 的 default implementation，并把 conditional conformance 的 `where` 子句当作容器身份的一部分。对应关系见 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md) 与 [PerConformanceAttribution.md](../PerConformanceAttribution.md)；译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（extension、extended type、extension binding、direct lookup、member lookup table、lazy member loader、iterable declaration context、constrained extension、unconstrained extension、pass-through type alias、conditional conformance、conditional requirement、specialized conformance、normal conformance、default witness、declared interface type、self interface type、well-formed substitution map……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Member Type Representations 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本 + Unicode）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 canonical generic parameter type。原书的 `T` 记作 `τ_0_0`，`U` 记作 `τ_0_1` |
> | `[T: P]` | conformance requirement（`T` conform 到 protocol `P`），也用来记一个具体的 conformance |
> | `[T == U]` | same-type requirement；右边是 concrete type 时称 concrete same-type requirement |
> | `X_d` | nominal type declaration `d` 的 **declared interface type**（把每个 generic parameter 映到它自己得到的那个类型） |
> | `T.[Q]A` | bound dependent member type：指向 protocol `Q` 的 associated type declaration `A` |
> | `Σ` | substitution map。写成 `{τ_0_0 ↦ Int; [τ_0_0: Equatable] ↦ [Int: Equatable]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `T`（或应用到 requirement、conformance 上） |
> | `⟨P] ⊗ X` | **global conformance lookup**：查 `X` 对 protocol `P` 的 conformance |
> | `⟨P\|A ⊗ [X: P]` | **type witness projection**：从 conformance `[X: P]` 里取 associated type `A` 的 type witness。原书的宏只开不闭（左尖括号、中间一竖、右边没有收口），本文照原样保留 |
> | `⟦T⟧` | type parameter `T` 的 **primary archetype**；`⟦G⟧` 是 generic signature `G` 的 generic environment |
> | `1_⟦H⟧` | `H` 的 **forwarding substitution map**（把每个 generic parameter 映到它自己的 primary archetype） |
> | `Type(⟦G⟧)`、`Conf(⟦G⟧)` | `⟦G⟧` 的 contextual type 集合、conformance 集合 |
> | `∈` | 集合记号：属于 |

---

Extension 给已有的 nominal type declaration 添加成员。我们把这个 nominal type declaration 称作该 extension 的 **extended type**。Extended type 可以来自同一个 source file、main module 的另一个 source file，最一般的情形下还可以来自别的 module。Extension 本身是 declaration，但它**不是** `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）意义上的 value declaration——也就是说，extension 自身无法按名字被引用。取而代之的是：对 qualified name lookup 而言，extension 的成员就像 extended type 自己的成员那样可见。

考虑一个含有两个 struct declaration（`Outer` 与 `Outer.Middle`）的 module：

```swift
public struct Outer<T> {
  public struct Middle<U> {}
}
```

第二个 module 可以声明一个 `Outer.Middle` 的 extension，给它加上一个名为 `foo()` 的方法和一个名为 `Outer.Middle.Inner` 的嵌套类型：

```swift
extension Outer.Middle {
  func foo() {}
  struct Inner<V> {}
}
```

如果第三个 module 随后同时 import 前两个 module，它看到的 `Outer.Middle.foo()` 和 `Outer.Middle.Inner` 就跟定义在 `Outer.Middle` 内部时一模一样。

> 译注：二进制里没有 extension 自己的 descriptor——成员被摊平成普通符号，只有 extension 上声明的 conformance 会留下一条 protocol conformance descriptor。本库因此按 (extended type, protocol, `where` 指纹, retroactive) 四元组把成员重新归拢进 extension 容器，见 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md) 与 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

### Extensions and generics.

Extended type 的 generic parameter declaration 在 extension 体的 scope 里可见。每个 extension 都有一个 generic signature，用来描述它的成员的 interface type。**Unconstrained extension** 的 generic signature 与 extended type 的相同。Extension 也可以通过 `where` 子句给它的 generic parameter 追加 requirement，这就声明了一个带自己的 generic signature 的 **constrained extension**（见本章 Constrained Extensions 一节）。最后，extension 可以声明对某个 protocol 的 conformance——回忆一下，这会声明一个对 global conformance lookup 可见的 normal conformance。若该 extension 是 unconstrained 的，这本质上等价于把 conformance 声明在 extended type 上；若是 constrained 的，这个 conformance 就成了 **conditional conformance**（见本章 Conditional Conformances 一节）。

我们先借上面的嵌套类型 `Outer.Middle` 及其 extension，仔细看看 extension 的 generic parameter list。回忆 `declarations.tex` 的 Generic Parameters 一节讲的 nominal type 的 generic parameter 是怎么回事：它们的名字按词法作用域限定在类型声明体内，而每个 generic parameter 由它的 depth 与 index 唯一确定。我们可以用下面这样的图来表示 nominal type declaration `Outer.Middle` 的 declaration context 嵌套关系与 generic parameter list：

```
source file
└── struct Outer ─────→ generic parameter list <T>
    └── struct Middle ─→ generic parameter list <U>
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。原图把父子关系画成从子声明指向父声明的箭头，这里改用缩进表示同一层关系；横向箭头表示「该声明持有这个 generic parameter list」。

我们制造出一种假象，让 extended type 作用域里的每一个 generic parameter 在 extension 内部也可见，办法是**克隆** generic parameter declaration。克隆出来的声明与原件同名、同 depth、同 index，但它们的父节点是这个 extension。这保证了在 extension 内部按名字查一个 generic parameter 时，找到的那个与 extended type 里同名的那个有相同的 depth 和 index。

由于同一个 generic parameter list 里的所有 generic parameter 都有相同的 depth，一个 extension 可能有多个 generic parameter list——extended type 每一层 depth（也就是每一层 generic context 嵌套）各一个。我们用一个「outer list」指针把这些克隆出来的 generic parameter list 串起来。最内层的那个 generic parameter list 就是这个 extension「那个」generic parameter list，也是链表的头；它克隆自 extended type。它的 outer list 克隆自 extended type 的父 generic context（如果有的话），依此类推。最外层的 generic parameter list 的 outer list 为空。在我们这个 `Outer.Middle` 的 extension 上，情况如下：

```
                                  generic parameter list <T>
                                            ↑
                                            │ outer list
                                            │
source file                                 │
└── extension Outer.Middle ───→ generic parameter list <U>
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。竖直箭头就是原图里从 `<U>` 指向 `<T>` 的 outer list 指针。

Unqualified name lookup 按名字查找 generic parameter declaration 时会沿着 outer list 指针往外走。现在看看我们例子里的嵌套类型 `Inner`，它自己声明了一个 generic parameter list：

```swift
extension Outer.Middle {
  struct Inner<V> {}
}
```

如果一个 extension 声明了嵌套的 generic 类型，那么该嵌套类型的 generic parameter 的 depth 比 extension 最内层 generic parameter list 的 depth 大一。于是 `Inner` 的 generic parameter `V` 的 depth 是 2、index 是 0。在 `Outer.Middle.Inner` 的体内，三个 generic parameter list 全都可见：

```
                                  generic parameter list <T>
                                            ↑
                                            │ outer list
                                            │
source file                                 │
└── extension Outer.Middle ───→ generic parameter list <U>
    └── struct Inner ─────────→ generic parameter list <V>
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

Extension 的 **declared interface type** 就是 extended type 的 declared interface type；extension 的 **self interface type** 就是 extended type 的 self interface type。这两个概念只在 extended type 是 protocol 时才分开：那种情况下 declared interface type 是 protocol type，而 self interface type 是 protocol 的 `Self` type。

### Other behaviors.

Extension 成员的行为大体上跟写在 extended type 内部一样，但有几处差别：

- **Protocol extension** 的成员不像 protocol declaration 的成员那样是施加给具体类型的 requirement；它们是真有函数体的。

  一个 protocol extension 成员，如果名字和 interface type 都与某条 protocol requirement 相同，它就充当 **default witness**——当 conforming type 没有为这条 requirement 提供自己的 witness 时就用它：

  ```swift
  protocol P {
    func f()
  }

  extension P {
    func f() {
      print("default witness for P.f()")
    }
  }

  struct S: P {}

  S().f()  // calls the default witness for P.f()
  ```

  > 译注：本库从二进制恢复 default implementation 时，走的是**符号扫描**而不是逐条 requirement 解析——后者在 identical code folding 把多个字节相同的实现折叠到同一地址之后会丢成员，符号扫描是它的超集。扫描得到的 extension block 被挂到 `ProtocolDefinition.defaultImplementationExtensions` 上渲染，见 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)。

- struct 和 class 的 extension 不能添加 stored property，只能添加 computed property：

  ```swift
  struct S {
    var x: Int
  }

  extension S {
    var y: Int  // stored property: error
    var flippedX: Int { return -x }  // computed property: okay
  }
  ```

  所有 stored property 都必须被所有已声明的 constructor 初始化；如果 extension 能引入原 module 此前不知道的 stored property，这条不变量就破了。另一个原因是：struct 或 class 的 stored property layout 是在该 struct 或 class 声明被 emit 时算出来的，没有任何机制让 extension 事后改动这个 layout。

- Extension 不能给 enum declaration 添加新的 case，原因与 stored property 类似；那么做会同时把 `switch` 语句的静态穷尽性检查和 enum 的内存 layout 计算搞复杂。

- Extended type 是 class 时，extension 的方法隐含为 `final`，且不允许 override 来自 superclass 的方法。对非 `final` class 方法的调用是通过 **vtable**（挂在 class 的 runtime metadata 上的一张函数指针表）分派的，而没有任何机制让 extension 往 vtable 里加新条目或替换已有条目。

  > 译注：这条正是本库恢复 `final` 关键字的依据的另一面——在 vtable header 可读的非 actor class 里，没有 vtable method descriptor 的成员当初就是声明成 `final` 的（extension 成员天然落在这一侧）。恢复规则与它的四道闸门见 [FinalKeywordAndLazyAccessorTypeRecovery.md](../FinalKeywordAndLazyAccessorTypeRecovery.md)。

- 嵌套在 extension 里的类型，规则与嵌套在 nominal type 里的类型相同（见 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）的 Nested Nominal Types 一节）。struct、enum 或 class 的 extension 可以包含嵌套的 struct、enum 或 class，而 protocol extension 不行——正如 protocol 本身也不行。Extension 自身必须位于 source file 的顶层，但 extended type 可以嵌套在另一个 nominal type（或 extension）里面。

## Extension Binding

Extension 的 extended type 由紧跟在 `extension` 关键字后面的 type representation 给出。Extension 的成员是通过 **extension binding** 这个过程变得对 qualified lookup 可见的：它把 extension 的 type representation 解析成 extended type，并把该 extension 的成员加进 extended type 的 name lookup table。

麻烦之处在于，一个 extension 的 extended type 可能**自身**就声明在另一个 extension 里面。由于 extension 与嵌套类型之间存在顺序依赖，extension binding 不能简单地按源码顺序一趟扫完所有 extension declaration。取而代之的是跑多趟：某个 extension 绑定失败不是致命错误，失败的 extension 会被推迟到后续 extension 成功绑定之后再试一次。这个过程一直迭代到不动点。

**算法（Bind extensions）.** 输入是 main module 里全部 extension 的列表，顺序任意。

1. 把所有 extension declaration 入队到 pending list。
2. 清空 delayed list。
3. 清除标志位。
4. （Check）若 pending list 为空，跳到第 6 步。
5. （Resolve）从 pending list 取出一个 extension，尝试解析它的 extended type。解析成功就把该 extension 与解析出的 nominal type declaration 关联起来，并置上标志位；解析失败就把它加进 delayed list，不发任何 diagnostic，也不动标志位。回到第 4 步。
6. （Retry）若标志位已置上，把 delayed list 的全部内容搬回 pending list，清空 delayed list，清除标志位，回到第 4 步。否则返回。

这种由 worklist 驱动的 extension binding 算法是 Swift 5 引入的。更老的编译器版本试图一趟绑定完所有 extension，成败取决于声明顺序。这个错误行为曾是史上被报告次数最多的 bug 之一（SR-631：Extensions in different files do not recognize each other）。

### Invalid extensions.

如果 extension binding 解析不出某个 extension 的 extended type，它就一直留在 delayed list 上，不发任何 diagnostic。Invalid extension 要等到后面 **type-check primary file request** 访问所有 primary file、再次尝试解析各 extension 的 extended type 时才被诊断。

Extension binding 用的是一种受限得多的 type resolution，因为我们只需要把 type representation 解析到一个 **type declaration**，而不是一个 **type**。这个 type declaration 必须是 nominal type declaration，所以 extended type 通常写成 **identifier** 或 **member** type representation（见 `type-resolution.tex` 的 Identifier Type Representations 与 Member Type Representations 两节）。Extension binding 在类型检查流程里跑得很早，紧接在 parsing 与 import resolution 之后。我们在 extension binding 里既不能构建 generic signature 也不能检查 conformance，因为那些 request 都假定 extension binding 已经做完了——它们会毫无顾忌地用 qualified lookup 去找任意 extension 的成员。

尤其是，extension binding 找不到编译器合成的声明，包括 associated type inference 造出来的 type alias。它也不能做 type substitution；这就排除了对 underlying type 本身是 type parameter 的 generic type alias 做 extension。

如果 extension binding 失败，而 **type-check primary file request** 后来访问该 extension 时却成功解析出了 extended type，我们就发一个专门的 diagnostic，并辅以若干额外检查来定制措辞。若普通 type resolution 返回的是一个 underlying type 为 nominal type `Bar` 的 type alias type `Foo`，type checker 就发出「extension of type `Foo` must be declared as an extension of `Bar`」这条 diagnostic。即便此刻我们已经知道 extended type 应该是什么，还是必须报错：现在再去绑定这个 extension 已经太晚了，因为别的 name lookup 可能已经做过，而它们可能错失了这个 extension 的成员。

**例.** 一个对合成出来的 type alias 做 extension 的非法例子：

```swift
protocol Animal {
  associatedtype FeedType
  func eat(_: FeedType)
}

struct Horse: Animal {
  func eat(_: Hay) {}
}

// error: extension of type `Horse.FeedType' must be declared as an
// extension of `Hay'
extension Horse.FeedType {...}
```

Extension binding 解析不出 `Horse.FeedType`，因为这个 type alias 不是源码里写出来的，在 extension binding 运行时它还不存在。然而当 **type-check primary file request** 后来访问这个 extension 时，type resolution 会触发 associated type inference，后者会从 witness `Horse.eat(_:)` 合成出这个 type alias。我们于是给出一条 diagnostic，指引用户去写那个在 extension binding 阶段就能找到的正确 extended type。

**例.** 一个对 underlying type 为 type parameter 的 type alias 做 extension 的非法例子：

```swift
typealias G<T: Sequence> = T.Element

// error: extension of type `G<Array<Int>>' must be declared as an
// extension of `Int'
extension G<Array<Int>> {...}
```

Extension binding 解析不出 `G<Array<Int>>`，因为这需要执行一次依赖于 conformance `[Array: Sequence]` 的 type substitution：

```
T.Element ⊗ {T ↦ Array<Int>; [T: Sequence] ↦ [Array<Int>: Sequence]}
  = Int
```

另一种「extension binding 失败但 **type-check primary file request** 能解析出 extended type」的情形，是这个类型根本不是 nominal type。此时 type checker 发出兜底的「non-nominal type cannot be extended」diagnostic：

```swift
typealias Fn = () -> ()

// error: you wish
extension Fn {
  ...
}
```

Extension binding 算法在最坏情况下是平方复杂度——每趟扫过 pending list 只能绑定恰好一个 extension。不过只有不切实际的代码例子才会触发这种病态行为。实际上，第一趟会绑定所有「extended type 不嵌套在别的 extension 里」的 extension，第二趟会绑定「extended type 嵌套在第一趟已绑定的 extension 里」的那些，这已经覆盖了正常用户程序中的绝大多数情况。

**例.** 下面这个 extension 排列顺序需要四趟才能绑定完；只要再加嵌套类型，迭代次数可以任意增大：

```swift
struct Outer {}

extension Outer.Middle.Inner {}  // bound in 3rd pass

extension Outer.Middle {  // bound in 2nd pass
  struct Inner {}
}

extension Outer {  // bound in 1st pass
  struct Middle {}
}

extension DoesNotExist {}  // remains on delayed list
```

第一趟里，`Outer.Middle.Inner` 和 `Outer.Middle` 这两个 extension 都失败，但我们成功绑定了 `Outer` 的 extension。第二趟仍然绑不定 `Outer.Middle.Inner` 的 extension，但绑定了 `Outer.Middle` 的。最后第三趟绑定了 `Outer.Middle.Inner` 的 extension。注意前三趟里每一趟都至少绑定成功了一个 extension。非法的 `DoesNotExist` extension 在前三趟之后都还留在 delayed list 上。由于第四趟没有任何进展，算法停止。稍后我们会走到 diagnostic 那条路径上，它用普通 type resolution 去解析 `DoesNotExist`，于是浮出「unknown type」这个错误。

### Local types.

因为 extension 只能出现在 source file 的顶层，extended type 最终必须从顶层可见。这就允许对嵌套在别的顶层类型里的类型做 extension，却排除了对嵌套在函数或其他 local context 里的 local type 做 extension——因为从 source file 的顶层根本没办法给一个 local type 命名。（一个有意思的后果是：local type 没法 conditionally conform 到 protocol，因为声明 conditional conformance 的唯一办法就是写一个 extension！）

## Direct Lookup

现在我们来细看 **direct lookup**——在某个 nominal type 及其 extension 里按给定名字查找 value declaration 的那个原语操作。它最早出现在 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）的 Name Lookup 一节里，作为 qualified name lookup 底下的那一层——qualified name lookup 会对 base type、它 conform 的各 protocol、以及它的各 superclass 分别做 direct lookup。

Nominal type declaration 和 extension 都是 **iterable declaration context**，意思是它们内部含有 member declaration。在讨论 direct lookup 之前，先看看我们要求一个 iterable declaration context 列出它的成员时会发生什么。这是一个惰性操作，第一次被调用时才触发实际工作：

- 从源码 parse 出来的 iterable declaration context 由 delayed parsing 填充；parser 第一次读 source file 时会跳过 iterable declaration context 的体，只记下它的 source range。要求列出成员时，才回去重新 parse 那段 source range，从 parse 出的表示构造出各个 declaration（见 `compilation-model.tex` 的 Delayed Parsing 一节）。
- 来自二进制 module 和 imported module 的 iterable declaration context 则配有一个 **lazy member loader**，作用类似。要求 lazy member loader 列出全部成员，它就会从反序列化记录或 imported Clang declaration 构建出对应的 Swift declaration。Lazy member loader 也能只查找带**特定**名字的那些 declaration（下面会讲）；这是更常见的操作，因为它高效得多。

### Member lookup table.

每个 nominal type declaration 都关联着一张 **member lookup table**，direct lookup 用的就是它。这张表把每个 identifier 映到一串同名的 value declaration（多个 value declaration 可以同名，因为 Swift 允许基于类型的重载）。Member lookup table 里的这些声明被理解为一个或多个 iterable declaration context 的成员，而这些 iterable declaration context 恰好就是类型声明本身加上它的全部 extension。它们可能来自混杂的不同 module 种类。比如说，nominal type 本身可能是从 imported Objective-C module 来的一个 Objective-C class，一个 extension 声明在某个二进制 Swift module 里，另一个 extension 定义在 main module 里、从源码 parse 而来。

这张 lookup table 是惰性填充的，有点像一台状态机。假设现在要求我们对某个给定名字 `X` 做一次 direct lookup。如果这是对这张表的第一次查找，我们先用所有**已 parse** 的 iterable declaration context 里的**全部**成员填表，这可能触发 delayed parsing。Member lookup table 的每个条目还存了一个「complete」位。这批初始填入的条目的「complete」位**没有**置上，因为每个条目此刻只含有从源码 parse 出来的那些成员。接着，若有任何 iterable declaration context 来自二进制或 imported module，direct lookup 就请求各自的 lazy member loader 有选择地只加载名为 `X` 的那些成员。（已 parse 的 declaration context 不提供这种粒度，因为不把它们全部 parse 一遍就没办法找到某个特定成员。）Lazy member loader 干完活之后，`X` 这个 lookup table 条目就完整了，于是我们置上它的「complete」位。若后续某次 direct lookup 碰到的 member lookup table 条目「complete」位已经置上，就立刻返回该条目里存的那串 declaration，不再去问 lazy member loader。

这套 **lazy member loading** 机制保证了：只有在一次编译会话中真正被引用到的成员，才会从序列化的和 imported 的 iterable declaration context 里加载出来。

**代码清单（A class implemented in Objective-C, with an extension written in Swift）.**

```objc
// a.h
@interface NSHorse: NSObject
- (void) trot: (int) x;
- (void) canter: (float) x;
@end
```

```swift
// b.swift
import HorseKit

extension NSHorse {
  func walk(_: Float) {}
  func trot(_: Float) {}
}
```

```swift
// c.swift
import HorseKit

func ride(_ horse: NSHorse) {
  horse.walk(1.0)
  horse.trot(2.0)
  horse.walk(1.0)
}
```

**例.** 上面这份代码清单展示了 lazy member loading。注意以下几点：

- `NSHorse` 这个 class 本身是在一个头文件里用 Objective-C 声明的。假设这个头文件属于 `HorseKit` module，被那两个 Swift 源文件 import。
- Swift 源文件 `b.swift` 声明了一个 `NSHorse` 的 extension。假设它是当前 frontend job 的 secondary file。
- Swift 源文件 `c.swift` 声明了一个函数，函数里调用了 `NSHorse` 上的若干方法。在我们这个例子里，它必须是这个 frontend job 的 primary file。
- class 里的 `trot()` 方法与 extension 里的 `trot()` 方法 interface type 不同，所以它们是两个同名但互不相同的重载方法。

编译器先 parse 这两个 Swift 源文件，由于 extension 出现在 secondary file 里，delayed parsing 会跳过它的体。接着执行 extension binding，把 `NSHorse` 的 extension 与 imported 的 `NSHorse` class declaration 关联起来。最后我们类型检查 `ride()` 函数的体，因为它出现在 primary file 里。类型检查函数体里的表达式会对 `NSHorse` 做三次 direct lookup，依次是名字 `walk`、`trot`，最后又是 `walk`。

（`walk`）表一开始是空的，所以必须先用所有已 parse 的 iterable declaration context 的成员填充它。这会触发 extension 的 delayed parsing，往 member lookup table 里加进两个条目：

| **Name** | **Declarations** | **Complete?** |
|---|---|---|
| `walk` | `NSHorse.walk` in extension of `NSHorse` | ✗ |
| `trot` | `NSHorse.trot` in extension of `NSHorse` | ✗ |

此刻两个条目都不完整，因为我们还没有到 class 自身内部去找成员——那个 class 是 imported 的，没有被 parse。Direct lookup 接下来就干这件事：请求与该 class declaration 关联的 lazy member loader 加载任何名为 `walk` 的成员。这个 class 没有定义这样的成员，于是我们只是把 member lookup table 的该条目标记为完整：

| **Name** | **Declarations** | **Complete?** |
|---|---|---|
| `walk` | `NSHorse.walk` in extension of `NSHorse` | ✓ |
| `trot` | `NSHorse.trot` in extension of `NSHorse` | ✗ |

Direct lookup 把 `NSHorse.walk()` 返回给 type checker。

（`trot`）虽然 member lookup table 里已经有一个名为 `trot` 的条目，但它不完整，于是我们再次求助于该 class declaration 的 lazy member loader。这一次，class 里也含有一个同名成员。这个 `trot` 方法从 Objective-C import 进来，被加进 member lookup table：

| **Name** | **Declarations** | **Complete?** |
|---|---|---|
| `walk` | `NSHorse.walk` in extension of `NSHorse` | ✓ |
| `trot` | `NSHorse.trot` in extension of `NSHorse`<br>`NSHorse.trot` in class `NSHorse` | ✓ |

Direct lookup 现在把 `NSHorse.trot()` 的两个重载都返回给 type checker。

（`walk`）第三次查找发现对应的 member lookup table 条目已经完整，于是立刻返回其中已存的 declaration，不再求助 lazy member loader。注意 `NSHorse` 的 `canter` 方法从头到尾没被引用过，所以它压根不需要被 import。

> 译注：原书此处是三张由 `\LookupTableEntry` / `\LookupTableElt` 宏排出来的查找表插图——每个条目是一个无边框方框，框里每条 declaration 各自装在一个圆角灰底小方块（pill）里，「Complete?」列用 `×` / `✓` 符号。这里用三张 Markdown 表格转述，方框与 pill 的视觉层次被摊平成单元格文本（同一单元格里的多条 declaration 用换行分隔）；图的原貌见官方 PDF 对应章节。

### History.

Lazy member loading 是 Swift 4.1 引入的，为的是避免在反序列化或 import 那些从未被引用的成员上做无用功。当多个 frontend job 对同一批反序列化或 imported 的 nominal type 做 direct lookup 时，提速最为明显。在 lazy member loading 引入之前，加载这批公共类型全部成员的开销会在各 frontend job 之间成倍叠加。

## Constrained Extensions

Extension 可以给 extended type 的 generic parameter 施加它自己的 requirement；我们把这种 extension 叫做 **constrained extension**。这些 requirement 永远是叠加式的：constrained extension 的 generic signature 由 extended type 的 generic signature 加上这些新 requirement 构建而成。于是，constrained extension 的成员只在满足这些 requirement 的那些 extended type 的 specialization 上可用。声明 constrained extension 有三种写法：

1. 用 `where` 子句；
2. 把带 generic argument 的 generic nominal type 写成 extended type；
3. 把 generic type alias type 写成 extended type（有若干限制）。

情形 1 是最一般的形式；情形 2 和情形 3 也都可以用 `where` 子句写出相应的 requirement 来表达。不落在这三种情形里的 extension，在需要与 constrained extension 区分时，有时被称作 **unconstrained extension**。Unconstrained extension 的 generic signature 与 extended type 的 generic signature 相同。

下面是一个 `Set` 的 constrained extension，它把 `Element` 类型约束成 `Int`：

```swift
extension Set where Element == Int {...}
```

`Set` 的 generic signature 是 `<Element where Element: Hashable>`。加上 same-type requirement `[Element == Int]` 之后，`[Element: Hashable]` 这条 requirement 就冗余了（因为 `Int` conform 到 `Hashable`），所以这个 extension 的 generic signature 变成 `<Element where Element == Int>`。

这个例子说明：虽然 constrained extension 的 requirement 抽象地蕴含 extended type 的 requirement，但它们并不是后者的「语法」超集——`[Element: Hashable]` 这条 requirement 并没有出现在 constrained extension 的 generic signature 里，因为加入 `[Element == Int]` 之后它变冗余了。

> 译注：这正是本库把 `where` 子句的**指纹**而不是「requirement 的字面集合」当作 extension 容器身份组成部分的原因：`where` 子句一变，容器身份就翻转，ABI diff 会把它报成 removed + added 而不是 modified，`@retroactive` 同理。见 [ABIDiffDesignAndLimitations.md](../ABIDiffDesignAndLimitations.md) 与 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

在 Swift 的早期，这个 extension 根本不被支持，因为编译器不允许 generic parameter 与 concrete type 之间存在 same-type requirement；只有 dependent member type 才可以被置成具体类型。这条限制在 Swift 3 里被解除，而本书描述的许多概念——最重要的是 substitution map 与 generic environment——都是在这项工作中引入的。

### Extending a generic nominal type.

对带 generic argument 的 generic nominal type 做 extension，是「用 `where` 子句把每个 generic parameter 约束到一个 concrete type」的简写。这些 generic argument 类型必须是完全具体的；它们不能引用 extended type declaration 的 generic parameter。前面那个例子用这种语法可以写得更简洁：

```swift
extension Set<Int> {...}
```

一个 underlying type 为 generic nominal type 的非 generic type alias type 也可以这么用：

```swift
typealias StringMap = Dictionary<String, String>
extension StringMap {...}
```

这个简写是 Swift 5.7 引入的（SE-0361：Extensions on bound generic types）。

### Extending a generic type alias.

一个 generic type alias 若满足下面三个条件，就称作 **pass-through type alias**：

1. 该 generic type alias 的 underlying type 必须是 generic nominal type；
2. 该 type alias 的 generic parameter 个数必须与 underlying type declaration 的相同；
3. 该 type alias 必须把 underlying type declaration 的每个 generic parameter 都代换成该 type alias 中与之对应的 generic parameter（这里的「对应」指的是 depth 与 index 相同）。

Pass-through type alias 本质上等价于它的 underlying generic nominal type，只不过它可以通过 `where` 子句引入额外的 requirement。对 pass-through type alias 做 extension，等价于对 underlying nominal type 做一个声明了这些额外 requirement 的 constrained extension。注意 pass-through type alias 并不要求把自己的 generic parameter 起成与 underlying type 相同的名字，这一点略有些令人困惑：type alias declaration 所用的名字对 extension 来说完全无关紧要——extension 的 generic parameter list 永远克隆自被 extend 的那个 nominal type，而不是 type alias。

**例.** 虽然这是一个普遍有用的特性，但「可以 extend pass-through type alias」这个能力当初是为了在标准库的一次具体改动之后维持源码兼容性才做的。

标准库定义了一个名为 `Range` 的 generic struct，只有一个 conform 到 `Comparable` 的 generic parameter `Bound`：

```swift
struct Range<Bound: Comparable> {...}
```

在 Swift 4.2 之前，标准库还有一个独立的 `CountableRange` 类型，带着一套不同的 requirement：

```swift
struct CountableRange<Bound: Stridable>
    where Bound.Stride: SignedInteger {}
```

`Stridable` protocol 继承自 `Comparable`，所以满足 `CountableRange` 各 requirement 的 generic argument 也一定满足 `Range` 的各 requirement。这两个类型之间唯一的区别是 `CountableRange` 比 `Range` conform 到更多的 protocol。在 conditional conformance 加入语言之后，把 `CountableRange` 作为一个独立类型保留下去就不再有意义了。为了保持源码兼容，Swift 4.2 用一个 generic type alias 替换掉了 `CountableRange`：

```swift
typealias CountableRange<Bound: Stridable> = Range<Bound>
    where Bound.Stride: SignedInteger
```

在 Swift 4.1 里，下面是两个不同 nominal type 的 extension：

```swift
extension Range {...}

extension CountableRange {...}
```

从 Swift 4.2 起，第二个 extension 被解释成「经由 pass-through type alias `CountableRange` 做出的 `Range` 的 constrained extension」：

```swift
extension Range
    where Bound: Stridable,
          Bound.Stride: SignedInteger {...}
```

**例.** 下面这些 type alias 都不是 pass-through type alias。

1. 这个 type alias 的 underlying type 不是 nominal type：

   ```swift
   typealias A<T> = () -> T
   ```

2. 这个 type alias 的 generic parameter 个数不对：

   ```swift
   typealias B<Value> = Dictionary<AnyHashable, Value>
   ```

3. 这个 type alias 没有把 underlying type 的第二个 generic parameter 代换成该 type alias 的第二个 generic parameter：

   ```swift
   typealias C<Key, Value> = Dictionary<Key, (Value) -> Int>
   ```

## Conditional Conformances

写在 nominal type 或 unconstrained extension 上的 conformance，为该 nominal type 的所有 specialization 实现了 protocol 的各条 requirement，我们把它叫做 **unconditional** conformance。声明在 **constrained** extension 上的 conformance 则是所谓的 **conditional conformance**：它只为那些满足该 extension 的 requirement 的 extended type specialization 实现 protocol requirement。Conditional conformance 是 Swift 4.2 引入的（SE-0143：Conditional conformances）。

举例来说，数组有一个天然的相等概念，定义在元素类型的相等操作之上。但我们并不要求每个数组的元素类型都是 `Equatable`。取而代之的是，我们声明 `Array` 对 `Equatable` 的一个 conditional conformance，只针对那些元素类型为 `Equatable` 的数组：

```swift
struct Array<Element> {...}

extension Array: Equatable where Element: Equatable {
  func ==(lhs: Self, rhs: Self) -> Bool {
    guard lhs.count == rhs.count else { return false }

    for i in 0..<lhs.count {
      // `Element: Equatable' conditional requirement is used here
      guard lhs[i] == rhs[i] else { return false }
    }

    return true
  }
}
```

更复杂的 conditional requirement 也可以写。我们在 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Conformance Lookup 一节讨论过 overlapping conformance 与 coherence，conditional conformance 继承了其中一条重要限制：一个 nominal type 对一个 protocol 仍然只能 conform 一次，即便那个 conformance 是 conditional 的；特别地，overlapping conditional conformance 不被支持，我们会发出 diagnostic：

```swift
struct G<T> {}

protocol P {}

extension G: P where T == Int {}
extension G: P where T == String {}  // error
```

> 译注：本库把这条「一个类型对一个 protocol 只能 conform 一次」的事实用在了容器归属上：conformance 是按 (target, protocol, `where` 指纹, retroactive) 四元组归属到 extension 容器的，一个 conformance 的增删是**容器级**事件，而 witness 的重新绑定才报 `.modified`。`@retroactive` 属于身份的一部分，翻转它等同于换了一个容器。见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

### Computing conditional requirements.

Conditional conformance 存着一串 **conditional requirement**。设 `G` 是声明该 conformance 的 constrained extension 的 generic signature，`H` 是 conforming type 的 generic signature，那么 `G` 必定满足 `H` 的所有 requirement。若反过来也成立，我们得到的就是一个 unconditional conformance。否则，该 conformance 的 conditional requirement 恰好就是 `G` 中那些不被 `H` 满足的 requirement。一个简单例子是 `Dictionary` 对 `Equatable` 的 conditional conformance：

```swift
extension Dictionary: Equatable where Value: Equatable {...}
```

`Dictionary` 的 generic signature 是 `<Key, Value where Key: Hashable>`。我们这个 constrained extension 的 generic signature 有两条 requirement：

```
<Key, Value where Key: Hashable, Value: Equatable>
```

第一条 requirement 已经被 `Dictionary` 自身的 generic signature 满足了；第二条就是我们这个 conformance 的 conditional requirement。

我们计算 conditional requirement 的办法，是把 `G` 的各条 requirement 连同 forwarding substitution map `1_⟦H⟧` 一起交给 `type-resolution.tex` 的 Check substitution map 算法。该算法输出一串 failed 和 unsatisfied 的 requirement。不过它们其实既不是真的「failed」也不是真的「unsatisfied」；把这两串接起来，恰恰就是我们这条 normal conformance 的 conditional requirement 列表。

其中「failed」那一类对应的是：conditional requirement 的 subject type 根本不是 `H` 的一个合法 type parameter。下面 `[T.Element: Hashable]` 这条 requirement 的 subject type 是 `T.Element`，而 `T.Element` 是由 `[T: Sequence]` 定义出来的，后者自己又是一条 conditional requirement，所以 `[G: Sequence]` 有两条 conditional requirement：

```swift
struct G<T> {}

extension G: Sequence where T: Sequence, T.Element: Hashable {...}
```

### Specialized conditional conformances.

接着 `conformances.tex` 的 Conformance Lookup 一节往下说，我们现在来描述 substitution 与 conditional conformance 的关系。设 `X_d` 是某个 nominal type declaration `d` 的 declared interface type，且 `d` **无条件地** conform 到 `P`；又设 `X = X_d ⊗ Σ` 是 `d` 在某张 substitution map `Σ` 下的一个 specialized type。那么查 `X` 对 `P` 的 conformance，返回的是一个 conformance substitution map 为 `Σ` 的 specialized conformance：

```
⟨P] ⊗ X = [X_d: P] ⊗ Σ
```

但若 `[X_d: P]` 是 conditional 的，我们就不能取 `Σ` 为 `X` 的 context substitution map。`[X_d: P]` 的 type witness 里可能含有该 constrained extension 的 type parameter，而不只是 conforming type 的；然而 `X` 的 context substitution map 的 generic signature 是 conforming type 的。我们改为定义 `Σ` 是 `X` 相对于该 constrained extension 的 generic signature 的 context substitution map，做法见 `type-resolution.tex` 的 Member Type Representations 一节。的确，我们处在与 member type resolution 完全相同的处境里——当被引用的 type declaration 声明在一个 constrained extension 里时，我们必须多做几次 global conformance lookup 才能把 substitution map 填满。

Specialized conformance `[X: P]` 的 conditional requirement，就是把 `Σ` 应用到 `[X_d: P]` 的每一条 conditional requirement 上得到的 substituted requirement。这使得对每一条 conditional requirement `R`，下面这张图都交换：

```
                            apply Σ
        [X_d: P] ─────────────────────────────→ [X: P]
            │                                      │
     get    │                                      │    get
 conditional│                                      │conditional
 requirement↓                                      ↓requirement
            R ─────────────────────────────────→ R ⊗ Σ
                            apply Σ
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。这张图断言的是：从 normal conformance 先取 conditional requirement 再代入 `Σ`，与先代入 `Σ` 得到 specialized conformance 再取它的 conditional requirement，结果相同。

考虑标准库里的 conformance `[Array<τ_0_0>: Equatable]`。`Array` 的 generic signature 是 `<τ_0_0>`，没有任何 requirement；而 conformance context 是那个 signature 为 `<τ_0_0 where τ_0_0: Equatable>` 的 constrained extension。`Array<Int>` 相对于该 constrained extension 的 context substitution map 是：

```
Σ := {τ_0_0 ↦ Int;
      [τ_0_0: Equatable] ↦ [Int: Equatable]}
```

我们把这张 substitution map 与那条 normal conformance 复合，得到一个 specialized conditional conformance，记作 `[Array<Int>: Equatable]`：

```
[Array<τ_0_0>: Equatable] ⊗ Σ = [Array<Int>: Equatable]
```

这条 normal conformance 有唯一一条 conditional requirement `[τ_0_0: Equatable]`。我们对它应用 `Σ`，就得到这条 specialized conformance 的 conditional requirement：

```
[τ_0_0: Equatable] ⊗ Σ = [Int: Equatable]
```

### Global conformance lookup.

Global conformance lookup 故意**不**检查 conditional requirement，这样调用方就能问两个不同的问题：

1. 这个带着一串具体 generic argument 的 specialized type，conform 到该 protocol 吗？
2. 一串 generic argument 要满足哪些 requirement，才能让这个类型 conform？

需要第一种解读时，可以用一个便利入口，它把 global conformance lookup 与 `type-resolution.tex` 的 Check requirement 算法组合起来，去检查各条 conditional requirement。

检查 conditional requirement，比「在 conformance substitution map 里找有没有 invalid conformance」要微妙。「存在 invalid conformance」确实意味着某条 conditional requirement 没被满足；比如说，`Array<AnyObject>` 并不 conditionally conform 到 `Equatable`，因为 `AnyObject` 不是 `Equatable`，于是我们得到下面这条 specialized conformance：

```
⟨Equatable] ⊗ Array<AnyObject>
  = [Array<τ_0_0>: Equatable] ⊗ {τ_0_0 ↦ AnyObject;
                                 [τ_0_0: Equatable] ↦ invalid}
  = [Array<AnyObject>: Equatable]
```

然而，光看 substitution map 说不出其他种类的 conditional requirement 有没有被满足——比如 same-type requirement、superclass requirement 和 layout requirement。举例来说，`[Pair<Int, String>: Diagonal]` 的 conformance substitution map 里不含任何 invalid conformance，但它并不满足 conditional requirement `[τ_0_0 == τ_0_1]`：

```swift
protocol Diagonal {}
struct Pair<T, U> {}
extension Pair: Diagonal where T == U {}
```

因此，conditional requirement 必须一律交给 Check requirement 算法来检查，而不能用「翻 substitution map」这种「临时凑合」的办法。

### Protocol inheritance.

Protocol inheritance 被建模成施加在 `Self` 上的一条 associated conformance requirement，所以比如说 `Derived` 就有一条 associated conformance requirement `[Self: Base]`：

```swift
protocol Base {...}
protocol Derived: Base {...}
```

检查一条对 `Derived` 的 conformance 时，conformance checker 会确认 conforming type 满足 `[Self: Base]` 这条 requirement。当对 `Base` 的 conformance 是 unconditional 的时候，这总是成功的，因为 conformance declaration 同时**蕴含**了一条对 base protocol 的 unconditional conformance：

```swift
struct Pair<T, U> {}
extension Pair: Derived {...}
// implies `extension Pair: Base {}'
```

Nominal type 的 conformance lookup table 会合成这些被蕴含的 conformance，并把它们提供给 global conformance lookup。有了 conditional conformance 之后，这种被蕴含的 conformance 就不再被合成了——因为没办法猜出 conditional requirement 应该是什么。不过 conformance checker 仍然会检查 `Self` 上的那条 associated conformance requirement，所以在写 conditional conformance 时，用户必须先为每个 base protocol 显式声明一条 conformance。

假设我们希望 `Pair` 在 `[τ_0_0 == Int]` 时 conform 到 `Derived`：

```swift
extension Pair: Derived where T == Int {...}
```

除非同时还有一条 `Pair` 对 `Base` 的**显式** conformance，否则编译器会报错。声明 `Pair` 对 `Base` 的 conformance 有好几种可能的写法，最简单的是无条件地 conform：

```swift
extension Pair: Base {...}
```

如果对 `Base` 的 conformance 也是 conditional 的，事情就有意思了——因为这时只有当 `[Pair: Derived]` 的 conditional requirement 蕴含 `[Pair: Base]` 的 conditional requirement 时，对 `Derived` 的 conformance 才说得通。我们按下面的办法确立这个条件。这里有三个 generic signature 在起作用：

1. `Pair` 的 signature；记作 `H`。
2. 声明了对 `Base` 的 conformance 的那个 extension 的 signature；记作 `G_1`。
3. 声明了对 `Derived` 的 conformance 的那个 extension 的 signature；记作 `G_2`。

Conformance `[Pair: Derived]` 满足 `Derived` 的 associated conformance requirement `[Self: Base]`，当且仅当：任何满足 (3) 的 conditional requirement 的 `Pair` specialization 也满足 (2) 的 conditional requirement。在 conformance checker 里，这是「检查 associated requirement」这个一般情形的自然结果。

对每一条 associated requirement，我们先应用该 normal conformance 的 protocol substitution map，再应用该 conformance 的 generic signature 的 forwarding substitution map。在我们这个例子里，这给出下面这条 substituted requirement：

```
[Self: Base] ⊗ Σ_[Pair: Derived] ⊗ 1_⟦G_2⟧ = [Pair<⟦T⟧, Int>: Base]
```

接着，我们问 Check requirement 算法这条 substituted requirement 是否被满足。这会做一次 global conformance lookup 并检查它的 conditional requirement：

```
⟨Base] ⊗ Pair<⟦T⟧, Int> = [Pair<⟦T⟧, Int>: Base]
```

由于 `Pair<⟦T⟧, Int> ∈ Type(⟦G_2⟧)`，我们得到 `⟨Base] ⊗ Pair<⟦T⟧, Int> ∈ Conf(⟦G_2⟧)`。这条 conformance 的 conditional requirement，就是把 `G_2` 的 primary archetype 代进 `G_1` 的各条 requirement 得到的结果。我们必须检查它们是否被满足，才能判定对 `Derived` 的 conformance 是否合法。下面我们看 conformance `[Pair: Base]` 的三种不同定义，以及每一种如何影响 conformance `[Pair: Derived]` 的合法性。

> 译注：原书上面两个展示式里写的 `Pair<⟦T⟧, Int>`，与紧接着三个情形中使用的 substitution map `{τ_0_0 ↦ Int, τ_0_1 ↦ ⟦U⟧}` 相矛盾——后者对应的 specialized type 应是 `Pair<Int, ⟦U⟧>`（extension 写的是 `where T == Int`，所以被固定的是第一个 generic argument，自由的是第二个）。疑为原书笔误，以三个情形里的 substitution map 为准。

**情形 1.** `Base` conformance 的 conditional requirement 可能与 `Derived` 的完全相同：

```swift
extension Pair: Base where T == Int {...}
```

检查 `Derived` conformance 时，我们对 `Base` 的 conditional requirement `[τ_0_0 == Int]` 做代入：

```
[τ_0_0 == Int] ⊗ {τ_0_0 ↦ Int, τ_0_1 ↦ ⟦U⟧} = [Int == Int]
```

这条 substituted requirement 被满足，所以 conformance `[Pair: Derived]` 合法。

**情形 2.** `Base` conformance 的 conditional requirement 允许比 `Derived` 的约束**更松**：

```swift
extension Pair: Base where T: Equatable {...}
```

检查 `Derived` conformance 时，我们对 `Base` 的 conditional requirement `[τ_0_0: Equatable]` 做代入：

```
[τ_0_0: Equatable] ⊗ {τ_0_0 ↦ Int, τ_0_1 ↦ ⟦U⟧} = [Int: Equatable]
```

这条同样被满足，所以 conformance `[Pair: Derived]` 依然合法。

**情形 3.** 然而，`Base` 的 conditional requirement **不**允许比 `Derived` 的约束**更紧**：

```swift
extension Pair: Base where U: Equatable {...}
```

检查 `Derived` conformance 时，我们对 `Base` 的 conditional requirement `[τ_0_1: Equatable]` 做代入：

```
[τ_0_1: Equatable] ⊗ {τ_0_0 ↦ Int, τ_0_1 ↦ ⟦U⟧} = [⟦U⟧: Equatable]
```

在声明了 `Derived` conformance 的那个 extension 的 generic signature 里，archetype `⟦U⟧` 并**不** conform 到 `Equatable`。所以如果 `[Pair: Base]` 按上面那样声明，编译器就必须拒绝 conformance `[Pair: Derived]`。

### Termination.

Conditional conformance 能在编译期表达不终止的计算。下面这段代码取自一份至今尚未修复的 bug 报告（SR-6724：Swift 4.1 crash when using conditional conformance）：

```swift
protocol P {}

protocol Q {
  associatedtype A
}

struct G<T: Q> {}

extension G: P where T.A: P {}

struct S: Q {
  typealias A = G<S>
}

func takesP<T: P>(_: T.Type) {}
takesP(G<S>.self)  // called here
```

`takesP()` 函数的 generic signature 是 `<τ_0_0 where τ_0_0: P>`。最后一行以 `G<S>` 作为 `τ_0_0` 的 generic argument 调用这个函数。这次调用的 substitution map 还需要存一条 conformance `[G<S>: P]`，但这条 conformance 实际上构造不出来。Normal conformance `[G<τ_0_0>: P]` 声明在一个 constrained extension 上，其 generic signature 为：

```
<τ_0_0 where τ_0_0: Q, τ_0_0.[Q]A: P>
```

要从这条 normal conformance 构造出 specialized conformance `[G<S>: P]`，我们必须先构造 conformance substitution map。这张 substitution map 应当把 `τ_0_0` 映到 `S`，并存下一对 conformance：

```
Σ := {τ_0_0 ↦ S;
      [τ_0_0: Q] ↦ [S: Q],
      [τ_0_0.[Q]A: P] ↦ ???}
```

第一条 conformance 的 conforming type 是 `τ_0_0 ⊗ Σ = S`，所以第一条 conformance 就是 normal conformance `[S: Q]`。第二条 conformance 的 conforming type 是 `⟨Q|A ⊗ [S: Q] = G<S>`，所以第二条 conformance 恰恰就是 `[G<S>: P]`——正是我们此刻正在构造的那条 specialized conformance！然而在当前的模型里，一张 substitution map 不能与它所含的某条 specialized conformance 构成环。

现在，假设我们**能够**表示这种循环的 substitution map：

```
Σ := {τ_0_0 ↦ S;
      [τ_0_0: Q] ↦ [S: Q],
      [τ_0_0.[Q]A: P] ↦ [G<τ_0_0>: P] ⊗ Σ}
```

可惜，这仍然不足以让我们这个例子通过类型检查。接下来碰到的问题是检查 conditional requirement `[τ_0_0.[Q]A: P]`。应用 `Σ` 得到 substituted conditional requirement：

```
[τ_0_0.[Q]A: P] ⊗ Σ = [G<S>: P]
```

于是：`G<S>` conditionally conform 到 `P`，当且仅当 conditional requirement `[G<S>: P]` 被满足；而这条 conditional requirement 被满足，当且仅当 `G<S>` conditionally conform 到 `P`。到这里我们又一次陷入了循环。目前，编译器在构造 conformance substitution map 时会在这个例子上崩溃；希望本书未来的更新能描述这个 bug 最终是怎么通过施加迭代次数上限解决的。

我们这个例子只编码了一个无限循环，但 conditional conformance 实际上能表达任意计算。这一点已经在同样具有 conditional conformance 的 Rust 编程语言上被证明（Shea Leffler 2017，《Rust's Type System is Turing-Complete》）。我们会在 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 Recursive Conformances 一节研究另一种与之相关但不相同的「编译期不终止计算」编码方式。

### Soundness.

在一个合法的程序里，我们期望每张 substitution map 都正确地建模了它的 input generic signature。

**定义.** 设 `Σ` 是一张 input generic signature 为 `G` 的 substitution map，且它的 replacement type 都是**完全具体**的，也就是不含任何 type parameter。我们称 `Σ` 是 **well-formed** 的，如果对 `G` 的每一条 derived requirement `R`，按 Check requirement 算法判定，substituted requirement `R ⊗ Σ` 都被满足。

（我们要说明的是，对 replacement type 的这条限制并不是真正的限制；正如 `type-resolution.tex` 的 Generic Arguments 一节所见，我们可以先把 `Σ` 与某个 generic signature `H` 的 forwarding substitution map `1_⟦H⟧` 复合，把 type parameter 换成 archetype。）

如果 `G` 的 derived requirement 理论是无限的，我们就没法直接检查 `Σ` 是否 well-formed。Check substitution map 算法只检查 `Σ` 是否满足 `G` 的每一条**显式** requirement，而这件事本身是不够的。一个立刻就能给出的反例是：substituted requirement 依赖于一条本身不满足其 protocol 的 associated requirement 的 conformance。比如说，我们可以声明一个 conform 到 `Sequence` 的 `Bad` 类型，而它的 `Iterator` type witness 并不 conform 到 `IteratorProtocol`：

```swift
struct Bad: Sequence {
  typealias Iterator = Int  // error
}
```

Substitution map `Σ := {τ_0_0 ↦ Bad; [τ_0_0: Sequence] ↦ [Bad: Sequence]}` 满足其 generic signature 的所有显式 requirement，但它不满足 derived requirement `[τ_0_0.[Sequence]Iterator: IteratorProtocol]`。不过这并不成问题，因为我们在检查那条 conformance 时仍然会报错，程序终归会被拒绝。

遗憾的是，我们能写出一张不 well-formed 的 substitution map，而 Check substitution map 算法根本不产生任何 diagnostic——连 conformance checking 阶段也不产生。这暴露了 conditional conformance 的一个至今尚未修复的健全性漏洞。我们从两个 protocol 开始：

```swift
protocol Bar {
  associatedtype Beer
  func brew() -> Beer
}

protocol Pub {
  associatedtype Beer
  func pour() -> Beer
}
```

我们声明一个对「同时 conform 到 `Bar` 与 `Pub` 的类型」泛型的函数，于是它的 generic signature 是 `<τ_0_0 where τ_0_0: Bar, τ_0_0: Pub>`：

```swift
func both<T: Bar & Pub>(_ t: T) -> (T.Beer, T.Beer) {
  return (t.brew(), t.pour())
}
```

接着我们声明一个 `BrewPub` struct，并把一个 `BrewPub<Int>` 实例传给 `both()`：

```swift
struct BrewPub<T> {}
let result = both(BrewPub<Int>())
```

要让这次调用通过类型检查，`BrewPub` 必须 conform 到 `Bar` 和 `Pub`；先假定这两条 conformance 已经存在。这次调用的 substitution map 是：

```
Σ := {τ_0_0 ↦ BrewPub<Int>;
      [τ_0_0: Bar] ↦ [BrewPub<Int>: Bar],
      [τ_0_0: Pub] ↦ [BrewPub<Int>: Pub]}
```

现在，把 `Σ` 应用到 `τ_0_0.[Bar]Beer` 与 `τ_0_0.[Pub]Beer` 上，就是从各自的 conformance 里投影出 `Beer` 的 type witness：

```
τ_0_0.[Bar]Beer ⊗ Σ = ⟨Bar|Beer ⊗ [BrewPub<Int>: Bar]
τ_0_0.[Pub]Beer ⊗ Σ = ⟨Pub|Beer ⊗ [BrewPub<Int>: Pub]
```

要让 `Σ` 是 well-formed 的，这两个 type witness 必须 canonically equal——因为在 `both()` 的 generic signature 里，bound dependent member type `τ_0_0.[Bar]Beer` 与 `τ_0_0.[Pub]Beer` 都等价于 unbound dependent type `τ_0_0.Beer`。

如果 `BrewPub` 无条件地 conform 到这两个 protocol，重复声明检查规则会阻止我们把这两条 conformance 声明成带不同 type witness 的：

```swift
extension BrewPub: Bar {
  typealias Beer = Float
  func brew() -> Float { return 0.0 }
}

extension BrewPub: Pub {
  typealias Beer = String  // error: invalid redeclaration
  func pour() -> String { return "" }
}
```

但如果这两条 conformance 是 conditional 的，两个 type alias 彼此在对方的 constrained extension 里都不可见，于是它们不会被当成重复声明而拒绝。剩下要做的只是挑一组 conditional requirement，让我们的 generic argument 类型 `Int` 同时满足它们：

```swift
extension BrewPub: Bar where T: Equatable {
  typealias Beer = Float
  func brew() -> Float { return 0.0 }
}

extension BrewPub: Pub where T: ExpressibleByIntegerLiteral {
  typealias Beer = String
  func pour() -> String { return "" }
}
```

在 `both()` 的体内，我们假定对 `brew()` 与 `pour()` 的调用返回同一个类型。然而实际发生的是：一个返回 `Float`，另一个返回 `String`，其结果是未定义行为。有两种可能的解决办法：

1. 我们可以收紧 constrained extension 里 type alias 的重复声明检查规则，要求所有这类 type alias 都有 canonically equal 的 underlying type。这会把上面那两条 conditional conformance **判为非法而拒绝**。
2. 我们可以扩展 Check substitution map 算法，让它检测出「在给定 substitution map 下 type witness 互不相容」的 conformance。这会转而把上面写的那次对 `both()` 的**调用判为非法而拒绝**。

第二种办法更可取，我们会在 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 里回到这个问题。

## Source Code Reference

关键源文件：

- `include/swift/AST/Decl.h`
- `lib/AST/Decl.cpp`

**`ExtensionDecl`**：表示一个 extension declaration。

- `getExtendedNominal()` 返回 extended type declaration。若 extension binding 未能解析出 extended type，返回 `nullptr`。若 extension binding 还没访问过这个 extension，则触发断言。
- `computeExtendedNominal()` 实际求值那个「把 extended type 解析成 nominal type declaration」的 request。只被 extension binding 使用。
- `getExtendedType()` 返回源码里写出来的 extended type，它可能是 type alias type 或 generic nominal type。这里用的是普通 type resolution，所以只发生在 extension binding 之后。它用来实现本章 Constrained Extensions 一节开头描述的那些语法糖。
- `getDeclaredInterfaceType()` 返回 extended type declaration 的 declared interface type。
- `getSelfInterfaceType()` 返回 extended type declaration 的 self interface type。对 protocol extension 来说它与 declared interface type 不同：declared interface type 是 protocol type，而 self interface type 是 protocol 的 `Self` type。

### Extension Binding

关键源文件：

- `include/swift/AST/NameLookup.h`
- `lib/AST/Decl.cpp`
- `lib/AST/NameLookup.cpp`
- `lib/Sema/TypeChecker.cpp`

**`bindExtensions()`**：接受一个 `ModuleDecl *`（必须是 main module），实现本章的 Bind extensions 算法。

**`ExtendedNominalRequest`**：把 extended type 解析成 nominal type declaration 的那个 request evaluator request。它调用的是一种受限形式的 type resolution，不应用 generic argument，也不执行 substitution。

**`directReferencesForTypeRepr()`**：接受一个 `TypeRepr *` 以及该 extension 的父 declaration context（通常是一个 source file），返回一个 `TypeDecl *` 的向量。其中某些 type declaration 可能是 type alias declaration；下一个入口点会把一切彻底解析成一串 nominal type。

**`resolveTypeDeclsToNominal()`**：接受一串 `TypeDecl *`，输出一串 `NominalTypeDecl *`，办法是递归地用同一种受限形式的 type resolution 把所有 type alias declaration 解析成 nominal type。

若输出列表为空，说明 type resolution 失败、该 extension 无法绑定。若输出列表多于一项，说明 type resolution 给出了有歧义的结果。目前遇到这种情况，我们总是取输出列表里的第一个 nominal type declaration。

### Direct Lookup and Lazy Member Loading

关键源文件：

- `lib/AST/NameLookup.cpp`
- `include/swift/AST/LazyResolver.h`

**`DirectLookupRequest`**：实现 direct lookup 的那个 request evaluator request。入口点是 `NominalTypeDecl::lookupDirect()` 方法，它在 `compilation-model.tex` 的 Source Code Reference 一节介绍过。这个 request 不做缓存，因为 member lookup table 实际上已经在 request evaluator 之外实现了缓存。

要理解 `DirectLookupRequest::evaluate()` 的实现，可以从下面几个函数入手：

- `prepareLookupTable()` 把所有「没有 lazy loader 的 extension」的全部成员，以及「有 lazy loader 的 extension」中到目前为止已加载的成员，都加进表里，且不把任何条目标记为完整。
- `populateLookupTableEntryFromLazyIDCLoader()` 请求某个 lazy member loader 加载单个条目，并把它加进 member lookup table。
- `populateLookupTableEntryFromExtensions()` 把所有「没有 lazy member loader 的 extension」的全部成员加进表里。

**`MemberLookupTable`**：每个 `NominalTypeDecl` 都有一个 `MemberLookupTable` 实例，它把 declaration name 映到一串 `ValueDecl`。最重要的几个方法：

- `find()` 返回指向某个条目的迭代器，该条目可能不存在或不完整。
- `isLazilyComplete()` 回答某个条目是否完整。
- `markLazilyComplete()` 把某个条目标记为完整。

**`LazyMemberLoader`**：一个抽象基类，由各种 module 分别实现，用来查找顶层声明以及类型和 extension 的成员。对 main module，它查的是从源码构建出来的 lookup table；对序列化 module，它反序列化记录并据此构建 declaration；对 imported module，它从 Clang declaration 构造 Swift declaration。

### Constrained Extensions

关键源文件：

- `lib/Sema/TypeCheckDecl.cpp`
- `lib/Sema/TypeCheckGeneric.cpp`

`GenericSignatureRequest` 在 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Source Code Reference 一节介绍过。它委托给一对工具函数来实现 extension 的特殊行为。

**`collectAdditionalExtensionRequirements()`**：从 extended type 收集该 extension 的 requirement，这同时处理了 pass-through type alias 的 extension（`extension CountableRange {...}`）与 generic nominal type 的 extension（`extension Array<Int> {...}`）。

**`isPassthroughTypealias()`**：回答某个 generic type alias 是否满足「可以作为 extension 的 extended type」的那些条件。

### Conditional Conformances

关键源文件：

- `include/swift/AST/GenericSignature.h`
- `include/swift/AST/ProtocolConformance.h`
- `lib/AST/GenericSignature.cpp`
- `lib/AST/ProtocolConformance.cpp`
- `lib/Sema/TypeCheckProtocol.cpp`

**`checkConformance`**：一个工具函数，先调用 `lookupConformance()`（global conformance lookup，见 `conformances.tex` 的 Source Code Reference 一节），再用 `checkRequirements()` 检查各条 conditional requirement（`checkRequirements()` 见 `type-resolution.tex` 的 Source Code Reference 一节）。

`NormalProtocolConformance` 与 `SpecializedProtocolConformance` 这两个类在 `conformances.tex` 的 Source Code Reference 一节介绍过。

**`NormalProtocolConformance`**：

- `getConditionalRequirements()` 返回一个 conditional requirement 数组；当且仅当这是一条 conditional conformance 时它非空。

**`SpecializedProtocolConformance`**：

- `getConditionalRequirements()` 把 conformance substitution map 应用到底层 normal conformance 的每一条 conditional requirement 上。

**`GenericSignatureImpl`**：另见 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）的 Source Code Reference 一节。

- `requirementsNotSatisfiedBy()` 返回本 generic signature 中那些不被给定 generic signature 满足的 requirement 组成的数组。它用来计算 `NormalProtocolConformance` 的 conditional requirement。

---

> 译自 `docs/Generics/chapters/extensions.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
