# Building Generic Signatures（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/building-generic-signatures.tex`（《Compiling Swift Generics》一书的「Building Generic Signatures」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本库从二进制里读到的 requirement 是**已经最小化并排好序**的结果——本章讲的就是编译器怎么从源码语法走到那个结果：requirement 的 decomposition 与 desugaring（`some Sequence<Int>` 怎么拆成一条 conformance 加一条 same-type）、well-formed 的判据、minimization 的不变量、以及 requirement 的 canonical 排序规则。本库读 opaque type descriptor 与 generic context 时看到的逐条 requirement，正是本章末尾那套排序的产物；对应关系见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（generic signature、requirement、requirement minimization、requirement inference、desugaring、decomposition、well-formed requirement、reduced requirement、minimal requirement、conflicting requirement、derived requirement、type parameter、requirement signature、protocol component……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Reduced Type Parameters 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。原书行文里的 `T` 对应 `τ_0_0`，`U` 对应 `τ_0_1`，`V` 对应 `τ_0_2` |
> | `[T: P]` | conformance requirement：`T` conform to protocol `P`。右边是 class 时它是 superclass requirement，右边是 `AnyObject` 时它是 layout requirement |
> | `[T == U]` | same-type requirement。右边是 concrete type 时叫 concrete same-type requirement |
> | `[Self.U: Q]_P` / `[Self.U == Self.V]_P` | protocol `P` 的 **associated requirement**（写在 `P` 的 requirement signature 里的那些） |
> | `T.[P]A` | **bound** dependent member type：`T` 的成员 `A`，且已绑定到 protocol `P` 的 associated type declaration |
> | `T.A` | **unbound** dependent member type：只有名字，还没绑定到具体的 associated type declaration |
> | `G ⊢ X` | 在 generic signature `G` 里能推导出 `X`（`X` 是一条 derived requirement，或一个 valid type parameter） |
> | `G_P` | protocol `P` 的 **protocol generic signature**，即 `<Self where Self: P>` |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 / requirement `T`；`P ⊗ T` 是 global conformance lookup |
> | `Σ` | substitution map。写成 `{τ_0_0 ↦ Int; [τ_0_0: Sequence] ↦ [Int: Sequence]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `Type(H)`、`Req(H)`、`Sub(G → H)` | generic signature `H` 的 interface type 集合、requirement 集合；input 为 `G`、output 为 `H` 的 substitution map 集合 |
> | `⟦H⟧` | `H` 的 primary generic environment（其中的类型是 archetype 而非 type parameter） |
> | `T ≤ U`、`T < U` | type parameter order 下的比较（定义见 `generic-signatures.tex` 的 Reduced Type Parameters 一节） |
> | `⊥` | 两个 requirement 在 requirement order 下**不可比** |
> | `ℕ` | 自然数集合 |
> | `T*`、`T_*` | 与 `T` 同一等价类里的 bound / unbound 代表元 |
> | `X′`、`C′` | 把类型 `X`、`C` 里的 `Self` 结构性替换成 `T` 之后得到的类型 |
>
> **推导（derivation）的写法**：原书把每一步写成「结论 + 右侧的（规则名 所用前提的编号）」。中译一律用编号列表，右侧括号里给规则名和前提编号，例如 `3. [τ_0_0: Base]    (AssocConf 2)` 表示第 3 步由规则 **AssocConf** 作用在第 2 步上得出。各规则的完整定义见 `derived-requirements-summary.tex`（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)）（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)）。

---

从用户写下的 requirement 构建出一个 generic signature，这件事我们此前一直含糊带过，现在该把它讲清楚了。我们要补上的，是从「声明 generic parameter 和写 requirement 的语法」（见 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 的 Generic Parameters 一节与 Requirements 一节，中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）到「generic signature 这个语义对象」（见 `generic-signatures.tex`，中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）之间缺失的那几步。

一个 generic signature 里的 requirement 必须是 reduced、minimal 的，而且要按特定方式排序（形式定义见本章 Requirement Minimization 一节）。所以要构建 generic signature，我们必须把用户写的 requirement 转换成一组**等价的**、额外满足这些不变量的 requirement。我们从构建 generic signature 的几个入口开始，一层层剥开：

- **generic signature request** 为源码里写下的声明惰性地构建 generic signature。这是一个多步过程：我们调用 type resolution，把语法表示变成用户写的 requirement，再分阶段处理它们、得到 minimal requirement。下面会看到这个 request 如何分解声明的各种语法形式，然后把大部分工作委派给 **inferred generic signature request**。
- **abstract generic signature request** 从一个「已经存在」但未必 minimal 的 requirement 列表构建 generic signature。它跳过 name lookup 和 type resolution，但处理 requirement 的方式与前者相似。
- 所有 generic signature 最终都由 **primitive constructor** 创建。它接受已知满足必要不变量的 generic parameter 和 requirement，只负责分配并初始化这个语义对象。

  在泛型实现之外，primitive constructor 只在少数几处使用——那些地方已经知道 requirement 满足必要条件。例如从 serialized module 反序列化一个 generic signature 时，我们知道它在序列化的那一刻就满足这些不变量。

  我们还用 primitive constructor 来构建 protocol `P` 的 **protocol generic signature** `<Self where Self: P>`，因为按定义它就满足这些不变量。除此之外，凡是要「从头」构建 generic signature 的地方，一律改用 **abstract generic signature request**。

- **requirement signature request** 为源码里写下的 protocol 惰性地构建 requirement signature。流程类似 inferred generic signature request：先 resolve 用户写的 requirement，再做 minimization。requirement signature request 没有「abstract」版本，因为 requirement signature 永远依附于某个具名的 protocol declaration。

下面逐个细看这几个 request。

### Generic signature request

有两种简单情形先行处理：

1. 如果这个声明是一个 protocol 或一个 unconstrained protocol extension，我们用 primitive constructor 构建 protocol generic signature `<Self where Self: P>`。

2. 一个既没有 generic parameter list、也没有 trailing `where` clause 的声明，直接继承其父上下文的 generic signature。如果这个声明位于 source file 的 top level，就返回 empty generic signature；否则对父上下文递归求值 **generic signature request**。

其余所有情况下，generic signature request 都会启动更底层的 **inferred generic signature request**，并向它传入一串参数：

1. 父上下文的 generic signature（若有）。

   嵌套声明的 generic signature 是在父上下文的基础上，追加额外的 generic parameter 和 requirement。

2. 当前 generic context 的 generic parameter list（若有）。

   前两项输入至少要给出一个；既没有父 signature、又没有要添加的 generic parameter，那结果必然是 empty generic signature，调用方对这种情况的处理方式是压根不求值这个 request。

3. 当前 generic context 的 trailing `where` clause（若有）。

   inferred generic signature request 会调用 type resolution，把这里写的 requirement representation 解析成 requirement。

4. 任何要额外添加的 requirement。

   这让我们可以用一种简写语法声明 constrained extension：把一个 generic nominal type、或一个「透传式」的 generic type alias 写成 extended type（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)） 的 Constrained Extensions 一节）。

5. 一组可用于 requirement inference 的类型。

   如果我们要构建的是 function 或 subscript 声明的 generic signature，这就是该声明的参数类型和返回类型；否则为空（见本章 Requirement Inference 一节）。

6. 一个用于诊断的 source location。

### Inferred generic signature request

有个未必可信的说法：「inferred generic signature request」这个名字之所以这么取，是因为下面的步骤之一叫「requirement inference」；但这个 request 在任何实质意义上都不是在「推断」generic signature。它做的事是通过一个多步过程，把用户写的 requirement 变换成 minimal、reduced 的形式，流程如下图：

```
 Syntactic representations          Inference sources
            │                               │
            ▼                               ▼
  Requirement resolution           Requirement inference
            │                               │
            └───────────────┬───────────────┘
                            ▼
                 Requirement desugaring
                            │
                            ▼
                 Desugared requirements
                            │
                            ▼
                Requirement minimization
                            │
                            ▼
                    Generic signature
```

> 译注：原书此处是一张 TikZ 图（标题为「Overview of the inferred generic signature request」），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

1. **Requirement resolution** 从 generic parameter 的 inheritance clause 里写的 constraint type、以及 trailing `where` clause 里的 requirement representation，构建出用户写的 requirement。这发生在 structural resolution stage（见 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)）），所以 resolve 出来的 requirement 里可能含有 unbound dependent member type，它们会在 requirement minimization 阶段归约成 bound dependent member type。

   type resolution 失败时，诊断在这里发出。

2. **Requirement inference**（见本章 Requirement Inference 一节）允许某些 requirement 在源码里省略不写——只要它们能被推断出来。这些推断出的 requirement 会加进用户写的 requirement 列表。

3. **Decomposition and desugaring**（见本章 Decomposition and Desugaring 一节）变换前两个阶段收集到的 requirement：把 conformance requirement 和 same-type requirement 改写成更简单的形式，并检出那些恒真或恒假的平凡 requirement。

   某条 requirement 按写法恒不成立时，诊断在这里发出。

4. **Requirement minimization** 才是真正见功夫的地方。本章 Requirement Minimization 一节会讲它建立起来的不变量；等到 `basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)） 里从 desugared requirement 构建 requirement machine 时，我们会再回到这个话题。

   若没有任何 substitution map 能满足按写法得到的 generic signature，诊断在这里发出；这时我们说这个 signature 含有**conflicting requirement**。

> 译注：本库读到自相矛盾的 requirement（或读不出 requirement 该有的形状）时不会崩，而是把这次降级作为事件派发给宿主，由宿主决定记到哪里——与编译器在这四个阶段各自发诊断是同一类分工，见 [EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)。

上面提到的诊断，都发在该声明的 source location 上——这个位置是随 request 一起传进来的。这个 source location 还用于另一条诊断，算是一种人为限制。拿到 generic signature 之后，我们要确保每一个**最内层**的 generic parameter 都是 reduced type。如果某个 generic parameter 不是 reduced 的，那它必然等价于某个 concrete type 或某个更靠前的 generic parameter；它起不到任何作用，应该删掉。我们在 `-language-mode 6` 下诊断为 error，在更早的 language mode 下诊断为 warning：

```swift
// error: same-type requirement makes generic parameter `T' non-generic
func add<T>(_ lhs: T, _ rhs: T) -> T where T == Int {
  return lhs + rhs
}
```

这条限制只针对最内层的 generic parameter，所以下面这样是允许的：

```swift
struct Outer<T> {
  func f() where T == Int {...}
}
```

这样也允许：

```swift
extension Outer where Element == Int {
  func f() {...}
}
```

### Abstract generic signature request

这个 request 从调用方提供的一组 generic parameter 和 requirement 构建 generic signature。流程比前者简单：

```
      Requirements
           │
           ▼
 Requirement desugaring
           │
           ▼
 Requirement minimization
           │
           ▼
   Generic signature
```

> 译注：原书此处是一张 TikZ 图（标题为「Overview of the abstract generic signature request」），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

它的输入是：一个可选的父 generic signature、一组要添加的 generic parameter type、一组要添加的 requirement。前两项至少要给出一个；若既没有父 generic signature 又没有要添加的 generic parameter，结果就是 empty generic signature，调用方应当通过压根不求值这个 request 来处理这种情况。

和 inferred generic signature request 一样，abstract generic signature request 会对 requirement 做 decomposition、desugaring 和 minimization；正因如此，它比直接用 primitive constructor 更可取。这个 request 常常是这样被调用的：先把某个原始 generic signature 的每条 requirement 应用一张 substitution map，得到一串 substituted requirement，再把它们交给这个 request。它用在好几个地方：

- 计算 opaque type declaration 的 generic signature（见 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)），中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）。
- 计算 opened existential type 的 generic signature（见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)） 的 Existential Archetypes 一节）。
- 检查子类声明的 method override 是否满足超类中被覆盖方法的 generic requirement。

这个 request 不做 requirement inference，也不发任何诊断；取而代之的是返回一个 error 值，由调用方自行检查。

> 译注：`some P` 的那张 opaque result generic signature，正是由这个 request 构造出来的——本库从 opaque type descriptor 里逐字节读回的，就是它的产物，见 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md) 的 Opaque result generic signatures 一节与 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

> 译注：以下三小节在原书中包在 `\iffalse ... \fi` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

当子类覆盖超类的某个方法时，type checker 必须确保子类方法与超类方法兼容，才能保证子类实例在动态意义上可以和超类实例互换。如果超类和子类都不是 generic 的，兼容性检查只需比较两个非 generic 声明的完全具体的参数类型与返回类型。否则，superclass substitution map 又一次扮演关键角色，因为这个兼容关系必须把超类方法的类型**投影**到子类里，才能与 override 做有意义的比较。

### Non-generic overrides

简单的情形是：超类或子类是 generic 的，但超类方法自己没有定义 generic parameter——既没有显式写，也没有通过 Requirements 一节讲的 opaque parameter 引入。我们把这样的方法称为「non-generic」，哪怕它所在的类是 generic 的。于是一个 non-generic 方法与其父上下文（在这里是一个 class）具有相同的 generic signature。在 non-generic 的情形里，superclass substitution map 就足以刻画超类方法的 interface type 与其 override 之间的关系。

```swift
class Outer<T> {
  class Inner<U> {
    func doStuff(_: T, _: U) {}

    func doGeneric<A: Equatable>(_: A) {}
  }
}

class Derived<V>: Outer<Int>.Inner<(V, V)> {
  func doStuff(_: Int, _: (V, V)) {}

  override func doGeneric<A>(_: A) {}
}
```

上面这段代码里，`Derived` 覆盖了 `Outer.Inner` 的 `doStuff()` 方法。把 `doStuff()` 的 interface type 去掉第一层 function application，剩下 `(T, U) -> ()`；对它应用 `Derived` 的 superclass substitution map，得到最终结果：

```
(T, U) -> () ⊗ {T ↦ Int, U ↦ (V, V)} = (Int, (V, V)) -> ()
```

这恰好正等于 `Derived` 中子类方法 `doStuff()` 的 interface type（同样不含 self clause）。类型完全匹配的 override 是合法的。（实际上参数类型和返回类型还允许一定的 variance，只是从泛型的角度看不太有意思，所以这里给个速览：override 可以**收窄**返回类型、**放宽**参数类型。这意味着用一个返回 `T` 的方法去覆盖一个返回 `Optional<T>` 的方法是合法的，因为 `T` 总能通过一次 injection 变成 `Optional<T>`。同理，若 `A` 是 `B` 的超类，一个返回 `A` 的方法可以被覆盖为返回 `B`，因为 `B` 永远是一个 `A`。在方法参数位置上是一套对偶的规则；若原方法接受 `Int`，override 可以接受 `Optional<Int>`，等等。）

### Generic overrides

在 non-generic 的情形里，直接把 superclass substitution map 应用到超类方法的 interface type，就告诉了我们「这个超类方法在子类里应该是什么类型」；这之所以成立，是因为超类方法与超类本身有相同的 generic signature。一旦不再要求如此，问题就复杂起来了，而下面这些细节直到 Swift 5.2 才被理清（SR-4206：Override checking does not properly enforce requirements）。

超类（相应地，override）方法的 generic signature，是在超类（相应地，子类）自身的 generic signature 上追加额外的 generic parameter 和 requirement 构建出来的。为了把这四张 generic signature 联系起来，我们把 superclass substitution map 推广成所谓的 **attaching map**。一旦能算出 attaching map，把它应用到超类方法的 interface type 上，就得到一个 substituted type，可以像先前那样与 override 的 interface type 比较。不过，这一步虽然仍然必要，却不再充分——我们还需要比较超类方法与其 override 的**generic signature**是否兼容。attaching map 在这里同样有用。

最内层 generic parameter 个数不同的 override，立刻就能判定为非法，无需进一步检查。（有意思的是 generic parameter 的**名字**无关紧要：generic parameter 由 depth 和 index 唯一确定，而不是名字。）一旦确定两张 generic signature 的最内层参数个数相同，我们就能在两个 generic parameter 列表之间定义一个一一对应：保持 index 不变，但可能改变 depth。

我们通过「扩展」superclass substitution map 来构建 attaching map：为超类方法的最内层 generic parameter 补上 replacement type，按上面那个对应关系映到子类方法的 generic parameter。除了新的 replacement type 之外，如果超类方法引入了 conformance requirement，attaching map 还会存放 superclass substitution map 里没有的那些 conformance。

**算法（Compute attaching map for generic method override）.** 输入：超类方法的 generic signature `G`、superclass declaration `B`、某个 subclass declaration `D`。输出：`G` 的一张 substitution map。

1. 把 `R` 初始化为空的 replacement type 列表。
2. 把 `C` 初始化为空的 conformance 列表。
3. 令 `G′` 为 `B` 的 generic signature，令 `T` 为 `D` 的 declared interface type。
4. （平凡情形）若 `D = B`，返回 `G`。
5. （Remapping）令 `S` 为 `T` 对 `B` 的 declaration context 的 context substitution map。
6. （Replacements）对 `G` 的每个 generic parameter，检查它在 `G′` 中是否是一个合法的 generic parameter。若是，则它是超类的 generic parameter，于是应用 `S` 并把 replacement type 记入 `R`。否则它是超类方法的最内层 generic parameter：把该参数的 depth 减去 `B` 的 generic context depth、再加上 `D` 的 generic context depth，然后把一个 depth 已调整、index 不变的新 generic parameter type 记入 `R`。
7. （Conformances）对 `G` 的每条 conformance requirement `[T: P]`，先检查 `T` 在 `G′` 中是否是合法类型，以及 `T` 在 `G′` 中是否 conform to `P`。若是，就在 `S` 里查找 conformance `[T: P]` 并把结果记入 `C`。否则这是一条 `G` 有而 `G′` 没有的新 conformance requirement，把对 `P` 的 abstract conformance 记入 `C`。
8. （Return）由 `R` 和 `C` 构造出 `G` 的 substitution map 并返回。

**例.** 继续上面 `doGeneric()` 的例子：超类方法在 depth 2 上定义了一个 generic parameter `A`，而在 `Derived` 的子类方法里「同一个」参数的 depth 是 1。为清楚起见，attaching map 用 canonical type 写出（否则它会把 `A` 替换成 `A`，而两边的 `A` 含义不同）：

```
{τ_0_0 ↦ Int,
 τ_1_0 ↦ (τ_0_0, τ_0_0),
 τ_2_0 ↦ τ_1_0;
 [τ_1_0: Equatable] ↦ [(τ_0_0, τ_0_0): Equatable]}
```

### The override signature

之所以叫 attaching map，是因为它让我们得以把超类方法的 generic signature 与子类类型的 generic signature「粘」到一起，构建出子类方法**应有的** generic signature，也就是所谓的 **override signature**。随后就可以把这张应有的 generic signature 与子类方法**实际的** generic signature 做比较。

子类方法实际的 generic signature 由三部分构成：

1. 子类类型的 generic signature
2. 子类方法的最内层 generic parameter
3. 子类方法额外施加的 generic requirement

应有的 generic signature 算法与之类似，只是第三步换成：把 attaching map 应用到**超类**方法的每条 requirement 上，由此得到额外的 requirement。

**算法（Compute override generic signature）.** 输入：超类方法的 generic signature `G`、superclass declaration `B`、某个 subclass declaration `D`。输出：一张新的 generic signature。

1. 把 `P` 初始化为空的 generic parameter type 列表。
2. 把 `R` 初始化为空的 generic requirement 列表。
3. 令 `S` 为由 Compute attaching map for generic method override 算法对 `G`、`B`、`D` 算出的 attaching map。
4. （父 signature）令 `G″` 为 `D` 的 generic signature。（在上一个算法里，`G′` 指的是 `B` 的 generic signature。）
5. （额外参数）对 `G` 中每个位于最内层 depth 的 generic parameter，应用 `S`。按构造，结果仍是一个 generic parameter type；把它记入 `P`。
6. （额外 requirement）对 `G` 的每条 requirement 应用 `S`，把结果记入 `R`。
7. （Return）由 `G″`、`P`、`R` 构建一张 minimized generic signature 并返回。

为了让 override 履行超类方法的契约，它应当接受超类方法所接受的任意一组合法的具体类型实参。不过 override 可以更宽松。正确的关系是：**实际** override signature 的每条 generic requirement 都必须被**应有**的 override signature 满足，反过来则不必。这里用的机制，与 conditional conformance 的 conditional requirement 检查（见 `extensions.tex` 的 Conditional Conformances 一节）是同一套：一张 signature 的 requirement 可以被映射到另一张 signature 的 primary generic environment 的 archetype 上。这样一来 requirement 里的类型就变具体了，于是可以对 substituted requirement 检查 `isSatisfied()` 谓词。

**例.** 在上面那段 method override 的代码里，超类方法的 generic signature 是 `<T, U, A where A: Equatable>`。generic parameter `A` 属于方法，另外两个来自超类的 generic signature。override signature 把超类方法的最内层 generic parameter 及其 requirement，与子类的 generic signature `<V>` 粘在一起，得到 `<V, A where A: Equatable>`。这与 `Derived` 中 `doStuff()` 实际的 override generic signature `<V, A>` 不同，但实际 signature 的 requirement 被应有的 signature 满足了。

### Requirement signature request

这个 request 为给定的 **protocol component**（即一个或多个相互递归的 protocol 的集合，见 `basic-operation.tex` 的 Protocol Components 一节）构建 requirement signature。求值函数一开始会求值两个下级 request，收集每个 protocol 里用户写下的 requirement：

- **structural requirements request** 从 protocol 的 inheritance clause、associated type 的 inheritance clause、protocol 的 associated type 上的 `where` clause，以及 protocol 自身的 `where` clause 中收集 associated requirement。语法的说明见 `declarations.tex` 的 Protocols 一节。
- **type alias requirements request** 收集 protocol type alias 并把它们转换成 same-type requirement。进一步的讨论见 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Protocol Type Aliases 一节。

requirement signature request 拿到这些用户写的 associated requirement 后，对它们做 decomposition、desugaring 和 minimization，方式与 generic signature 的 requirement 基本一样。requirement signature 同样有 primitive constructor，它是 requirement signature request 的最后一步。从 serialized module 读入一个 protocol 之后我们也用它，因为那些 requirement 在序列化时就已经是 minimal 的了。

### Protocol inheritance clauses

查找 protocol 的成员时，name lookup 还必须访问它继承的 protocol。看这个例子：

```swift
protocol Base {
  associatedtype Other: Base
  typealias Salary = Int
}

protocol Good: Base {
  typealias Income = Salary
}
```

`Good` 里 `Income` 的 underlying type 指的是 `Base` 里的 `Salary`。protocol 之间的继承关系编码在 protocol 的 requirement signature 里。一个 conform to `Good` 的 concrete type 也必须 conform to `Base`，所以 `Good` 有一条 associated conformance requirement `[Self: Base]`。然而 name lookup 不能发起 generic signature query，因为构建 requirement signature 依赖 type resolution，而 type resolution 又依赖 name lookup。为了避免 request cycle，name lookup 必须直接解读 protocol 的 inheritance clause，不与泛型机制打交道。这带来一个小小的限制，下面就说它。

一个普遍事实是：protocol 的继承关系是**传递的**，所以下面这个 `Most` 也继承自 `Base`——因为 `Most` 继承 `Good`，而 `Good` 继承 `Base`：

```swift
protocol Most: Good {}
```

要理解这一行为，可以在 protocol generic signature `G_Most` 里为 requirement `[τ_0_0: Base]` 写出一个推导。我们从 `[τ_0_0: Most]` 出发，依次应用 associated conformance requirement `[Self: Good]_Most` 和 `[Self: Base]_Good`：

```
1. [τ_0_0: Most]     (Conf)
2. [τ_0_0: Good]     (AssocConf 1)
3. [τ_0_0: Base]     (AssocConf 2)
```

当 protocol 之间的继承关系是 inheritance clause 的**语法性**推论时，我们总能写出上面这样每一步的 subject type 都是 `τ_0_0` 的推导。这就是为什么对 `Good` 的 name lookup 知道要去 `Base` 里找。反过来，我们也可以构造出这样的 protocol 声明：`[τ_0_0: Base]` 是 `τ_0_0` 与另一个 type parameter 之间某条 same-type requirement 的**非平凡**推论。比如下面我们有 `G_Bad ⊢ [τ_0_0: Base]`，但这一点并不显然，因为 protocol 的 inheritance clause 里什么都没写：

```swift
protocol Bad {
  associatedtype Tricky: Base where Self == Tricky.Other
  typealias Income = Salary  // error
}
```

我们诊断一个 error，因为无法把 `Salary` 解析成 `Bad` 的成员。要理解原因，注意 `G_Bad ⊢ [τ_0_0: Base]` 的推导用到了 associated same-type requirement `[Self == Self.Tricky.Other]_Bad`，所以它不是该 protocol 语法性 inheritance clause 的推论：

```
1. [τ_0_0: Bad]                             (Conf)
2. [τ_0_0.Tricky: Base]                     (AssocConf 1)
3. [τ_0_0.Tricky.Other: Base]               (AssocConf 2)
4. [τ_0_0 == τ_0_0.Tricky.Other]            (AssocSame 1)
5. [τ_0_0: Base]                            (SameConf 3 4)
```

有一条专门的代码路径检出这个问题，并发出一个 warning 解释来龙去脉。构建完 protocol 的 requirement signature 之后，**type-check primary file request** 会验证：凡是已知由 `Self` 满足的 conformance requirement，都确实出现在该 protocol 的 inheritance clause 里，或出现在 subject type 为 `Self` 的 `where` clause 条目里。

在我们这个例子里，我们发现了 `G_Bad` 里那条出人意料的 derived requirement `[τ_0_0: Base]`，但到这个时候再去重试那次失败的 `Salary` name lookup 已经太晚了。编译器转而建议用户在 `Bad` 的 inheritance clause 里显式写明它继承自 `Base`：

```
$ swiftc bad.swift

bad.swift:8:22: error: cannot find type `Salary' in scope
  typealias Income = Salary
                     ^~~~~~
bad.swift:6:10: warning: protocol `Bad' should be declared to refine
`Base' due to a same-type constraint on `Self'
protocol Bad {
         ^
```

标准库的 `SIMDScalar` protocol 就固化了这类错误。`SIMDScalar` 的 `Self` 类型必须通过一条 associated same-type requirement，同时 conform to `Equatable`、`Hashable`、`Encodable` 和 `Decodable`：

```swift
public protocol SIMDScalar {
  ...
  associatedtype SIMD2Storage: SIMDStorage
    where SIMD2Storage.Scalar == Self
  ...
}

public protocol SIMDStorage {
  associatedtype Scalar: Codable, Hashable
  ...
}
```

然而这些 requirement 并没有写在 `SIMDScalar` 的 inheritance clause 里。由于 protocol 的 inheritance clause 是 Swift ABI 的一部分，这个遗漏到今天已无法修补，所以 type checker 在构建标准库时专门把这条 warning 压掉了。

## Requirement Inference

考虑一个返回某个 collection 中不重复元素的函数：

```swift
func uniqueElements<S: Sequence>(_ seq: S) -> Set<S.Element>
    where S.Element: Hashable {...}
```

在 resolve 这个函数的返回类型时，我们必须确认 generic argument `τ_0_0.Element` 满足标准库里 `Set` 类型声明的 generic signature 中的那些 requirement：

```swift
struct Set<Element: Hashable> {...}
```

唯一那条 substituted requirement 是满足的（见 `type-resolution.tex` 的 Generic Arguments 一节），因为 `uniqueElements()` 的 generic signature 含有 requirement `[τ_0_0.Element: Hashable]`。事实上，这条 requirement **必须**是我们这个函数 generic signature 的一部分，否则返回类型——进而整个函数声明——根本就不合法。**requirement inference** 这个特性让我们可以把这条 requirement 省略掉：

```swift
func uniqueElements<S: Sequence>(_ seq: S) -> Set<S.Element>
    /* where S.Element: Hashable */ {...}
```

这些 **inferred requirement** 并不是 `generic-signatures.tex` 的 Derived Requirements 一节意义上的 derived requirement。它们与用户写的 requirement 并肩出现在 generic signature 里，并不是其它 requirement 的推论。上面两种 `uniqueElements()` 的写法真的是完全一样的，尤其是它们有**相同的** generic signature，其中带一条显式的 conformance requirement `[τ_0_0.Element: Hashable]`。generic signature 的消费方既不知道、也不关心 requirement inference 的存在。

### Inferred requirements

构建一个声明的 generic signature 时，我们通过访问写在下面这些特定位置上的 type representation 来收集 inferred requirement：

1. function 与 subscript 声明的参数类型和返回类型——前提是我们拿到的 generic declaration 正是这两者之一。在 `uniqueElements()` 的例子里，我们从函数的返回类型推断出 requirement。

2. 出现在 generic parameter declaration 的 inheritance clause 里的类型。唯一有意思的情形是 generic superclass bound。下面 `Foo` 的 generic signature 有一条显式的 superclass requirement `[τ_0_0: Base<τ_0_1>]`，以及一条 inferred requirement `[τ_0_1: Equatable]`，后者写在被注释掉的 `where` clause 里：

   ```swift
   class Base<T: Equatable> {...}
   struct Foo<T: Base<U>, U>
       /* where U: Equatable */ {...}
   ```

3. 出现在 `where` clause 的 requirement 内部的类型，例如 same-type requirement 的右边。这里我们得到 inferred requirement `[τ_0_1: Hashable]`：

   ```swift
   struct Foo<T: Sequence, U>
       where T.Element == Set<U> /*, U: Hashable */ {...}
   ```

4. Swift 6 引入的 typed throws 特性（SE-0413）允许指定一个函数抛出的错误类型。对 function、subscript 和 constructor 声明，我们以该声明的 thrown error type 为 subject type，推断出一条对 `Error` 的 conformance requirement：

   ```swift
   func f<E>(_: Int) throws(E) /* where E: Error */ {...}
   ```

   如果 requirement inference 在其它任何位置遇到 function type，它同样会考察那里的 thrown error type：

   ```swift
   func f<E>(_: () throws(E) -> ()) /* where E: Error */ {...}
   ```

（从这份清单可以看出，出现在声明**体**里的类型不参与 requirement inference；否则就相当不妙了——比如一个函数的 interface type 竟然要先对函数体做类型检查才能确定。）

我们在 structural resolution stage 解析上面列举的每个 type representation，因为当前声明的 generic signature 还不知道——我们正在构建它。设 `H` 是正在构建的那张 generic signature；我们仍然可以抽象地谈论 `H`，只是不能定义任何依赖于对 `H` 发起 generic signature query 的具体东西。解析出来的类型里可能含有 `H` 的 type parameter，所以它是 `Type(H)` 的元素。从解析出来的类型出发，我们递归遍历它的子类型来得到一组 inferred requirement。我们寻找那些属于 generic nominal type 或 generic type alias type 的子节点，并从每一个里提取出一张 substitution map：

- 对 generic nominal type，取它的 context substitution map（见 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Nominal Types 一节，中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）。
- 对 generic type alias type，取存在该类型内部的那张 substitution map。

把这张 substitution map 记作 `Σ`，令 `G` 为 `Σ` 的 input generic signature——也就是被引用的 nominal type 或 type alias 声明的 generic signature。`Σ` 的 output generic signature 是 `H`，所以 `Σ ∈ Sub(G → H)`。接下来我们就像在检查 generic argument 那样，把 `Σ` 应用到 `G` 的每条 requirement 上，得到一条属于 `Req(H)` 的 substituted requirement。（回忆一下，在 interface stage 检查 generic argument 时我们处理的是 archetype，所以那时得到的是 `Req(⟦H⟧)` 里的东西；而这里我们要的是让 substituted requirement 谈论 type parameter。）

在此前见过的所有例子里，inferred requirement 的 subject type 都是 `H` 的一个 type parameter，于是这条 inferred requirement 原封不动地加进 `H`。先剧透一下下一节：substitution 之后，requirement 的 subject type 有可能是**完全具体**的类型。比如下面我们得到一条毫无用处的 inferred requirement `[Int: Hashable]`：

```swift
func f<T>(_: T, _: Set<Int>) {}
```

这条 requirement 根本不是在说 `f()` 的 type parameter 的任何事情，它只是「恒真」，所以不影响 `f()` 的 generic signature。有了 conditional conformance，还会出现更复杂的场景。下一个例子里，inferred requirement 是 `[τ_0_0: Hashable]`：

```swift
func f<T>(_: Set<Array<T>>) /* where T: Hashable */ {}
```

从 generic nominal type `Set<Array<τ_0_0>>` 我们得到 inferred conformance requirement `[Array<τ_0_0>: Hashable]`。标准库声明了一条 `Array` 对 `Hashable` 的 conditional conformance，条件是元素类型 `Hashable`。我们把原来那条 requirement 替换成这个 conformance 的 conditional requirement，于是得到 `[τ_0_0: Hashable]`。

一般来说，当一条 requirement 的 subject type 不是 type parameter 时，我们就反复把它改写成一组（可能为空的）更简单的 requirement，直到只剩下谈论 type parameter 的 requirement 为止；这个 **requirement desugaring** 过程就是下一节的内容。

desugaring 之后，inferred requirement 被传给 requirement minimization，在那里它们可能变成 redundant 的。举例来说，用户可能把所有 inferred requirement 都显式重写一遍——就像我们最开始那版 `uniqueElements()`——这些重复的 requirement 会被 requirement minimization 消掉。还能构造出更精致的 redundant inferred requirement 的例子。下面我们推断出 requirement `[τ_0_0.Iterator: IteratorProtocol]`，但它不是 `f()` 的 generic signature 的显式 requirement，因为它可以从 `[τ_0_0: Sequence]` 推导出来：

```swift
struct G<T: IteratorProtocol> {}

func f<T: Sequence>(_: T) -> G<T.Iterator> {...}
```

当然，用户完全可以出于求稳把这条 redundant requirement 在 `where` clause 里再显式写一遍，那样它就变成了某种意义上的「双重冗余」。

### Outer generic parameters

一个声明的 outer generic parameter 也可以受到 inferred requirement 的约束。考虑一个带三个方法的 generic struct：

```swift
struct G<T, U> {
  func f<V>(_: Set<U>, _: V) /* where U: Hashable */ {}
  func f(_: Set<U>) where T: Equatable /*, U: Hashable */ {}
  func f(_: Set<U>) {}  // error!
}
```

只有当声明有 generic parameter **或**有 `where` clause 时，我们才做 requirement inference，所以前两个方法里我们推断出 `[τ_0_1: Hashable]`。第三个方法直接继承了这个 struct 的 generic signature，所以那条 requirement 不被满足，我们诊断一个 error。

### Generic type aliases

对 generic type alias 的引用解析成一个 sugared type alias type（见 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 的 More Types 一节，中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）。这个 sugared type 出现在诊断消息里时按用户所写的样子打印，但它 canonically 等于它的 substituted underlying type，其它方面也表现得像后者。所以下面这里，`x` 的 interface type 打印成 `OptionalElement<Array<Int>>`，但它 canonically 等于它的 substituted underlying type `Optional<Int>`：

```swift
typealias OptionalElement<T: Sequence> = Optional<T.Element>

let x: OptionalElement<Array<Int>> = ...
```

上面我们构造 substituted underlying type `Optional<Int>` 的办法，是把一张「把 `τ_0_0` 替换成 `Array<Int>`」的 substitution map 应用到该 type alias 声明的 underlying type `Optional<T.Element>` 上。这就给出了 type alias type 的三个 structural component：对某个 type alias 声明的引用、一个 substituted underlying type、以及一张 substitution map。这张 substitution map 用于打印 sugared type 的 generic argument。对我们眼下的话题至关重要的是：requirement inference **也**会考察这张 substitution map，这使它成为少数几个「sugared type 的出现**确实**具有语义效果」的语言特性之一。在下面这个例子里，我们从考察 `OptionalElement<τ_0_0>` 推断出 requirement `[τ_0_0: Sequence]`：

```swift
func maybePickElement<T>(_ sequence: T) -> OptionalElement<T>
```

还有一件主要属于理论趣味的事实：一个 type alias 的 underlying type 完全可以根本不提及该 type alias 的 generic parameter type。在 parameterized protocol type 被加进语言之前，有人发现了一个有趣的小把戏来模拟出类似的东西：

```swift
typealias SequenceOf<T, E> = Any
    where T: Sequence, T.Element == E
```

`SequenceOf` 的 underlying type 就是 `Any`，而它的 generic signature 有两条 requirement：`[τ_0_0: Sequence]` 和 `[τ_0_1 == τ_0_0.Element]`。现在，我们可以把这个 type alias 写在某个 generic parameter declaration 的 inheritance clause 里：

```swift
func sum<S: SequenceOf<S, Int>>(_: T) {...}
```

这条 inheritance clause 条目引入了 requirement `[τ_0_0: Any]`；它毫无作用，因为 `Any` 是空的 protocol composition。然而 requirement inference 还会访问 type alias type `SequenceOf<S, Int>`，这才是整个把戏的所在。这个 type alias type 带有下面这张 substitution map：

```
Σ := {τ_0_0 ↦ τ_0_0, τ_0_1 ↦ Int; [τ_0_0: Sequence] ↦ [τ_0_0: Sequence]}
```

把 `Σ` 应用到 `SequenceOf` 的 generic signature 上，得到我们那两条 inferred requirement：

```
[τ_0_0: Sequence] ⊗ Σ = [τ_0_0: Sequence]
[τ_0_1 == τ_0_0.Element] ⊗ Σ = [τ_0_1 == Int]
```

这些 requirement 熬过了 minimization，出现在 `sum()` 的 generic signature 里。我们得到的 generic signature，与下面两种写法得到的完全相同：

```swift
func sum<S: Sequence<Int>>(_: T) {...}
func sum<S: Sequence>(_: T) where S.Element == Int {...}
```

### Protocols

与 inferred generic signature request 不同，requirement signature request **不做** requirement inference；所有施加在 concrete conforming type 上的 associated requirement 都必须在源码里显式写出。例如下面我们必须写出 `[Self.Particle: Hashable]` 这条 requirement，否则出现在 same-type requirement 里的类型 `Set<Self.Particle>` 就不满足 `Set` 的 `[τ_0_0: Hashable]` requirement：

```swift
protocol Cloud {
  associatedtype Particle /* must be : Hashable */
  associatedtype Particles: Sequence
      where Particles.Element == Set<Particle>  // error
}
```

这条限制的技术原因如下。在构建一个 protocol 的 requirement signature 之前，我们必须先构造出 **protocol dependency graph**。这张图（我们会在 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 Recursive Conformances 一节遇到它）编码了每个 protocol 与出现在其 associated conformance requirement 右边的那些 protocol 之间的关系。它的一条关键性质是：这张图只靠 name lookup 操作就能恢复出来，不需要对别的 requirement signature 或 generic signature 发起 query。如果我们允许在 protocol 里做 requirement inference，这条性质就不再成立了：我们可以像上面那样定义 `Cloud` 而不显式提及 `Hashable`，于是 protocol dependency graph 就会有一条「不显然」的边关系。

## Decomposition and Desugaring

在进入 requirement minimization 之前，我们要先消掉 requirement 定义里一些不必要的一般性。先回顾一下我们此刻的处境：

- 如果我们在求值 **inferred generic signature request**，那么我们大致走到了上文那张流程图的一半：已经收集到一组用户写的和推断出的 requirement，它们共同刻画了某个 generic declaration 的 type parameter。
- 如果我们在求值 **abstract generic signature request**，那么我们**就从这里开始**：如第二张流程图所示，调用方直接把一组 requirement 作为输入交给我们。

在 derived requirement 的形式体系里，conformance requirement 的右边永远是一个 protocol type；可在语法里我们还能写 protocol composition type 或 parameterized protocol type。这类 conformance requirement 必须被拆开——这就是 **requirement decomposition**。我们还记得 derived requirement 的左边永远是一个 type parameter，而 requirement inference（甚至用户本人）却可以写出 subject type 是任意类型的 requirement。这类 requirement 同样要被拆成零条或多条更简单的 requirement，这就是 **requirement desugaring**。

### Decomposition

这一步把 `declarations.tex` 的 Requirements 一节与 Protocols 一节里的语法糖形式化。举例来说，标准库定义了 `Codable` 这个 type alias，它的 underlying type 是两个 protocol `Decodable` 和 `Encodable` 的 composition：

```swift
typealias Codable = Decodable & Encodable
```

我们可以在一个 generic parameter 的 inheritance clause 里写出对 `Codable` 的 conformance：

```swift
func ride<Horse: Codable>(_: Horse) {}
```

要理解上面这段，只需把 `[τ_0_0: Decodable & Encodable]` 分解成两条 conformance requirement `[τ_0_0: Decodable]` 和 `[τ_0_0: Encodable]`。conformance requirement 的右边还可能是 parameterized protocol type，它是一串 same-type requirement 的语法糖——把该 protocol 的每个 primary associated type 约束到对应的 generic argument 上：

```swift
func search<E, S: Sequence<E>>(...) {}
```

上面写下的 conformance requirement `[τ_0_1: Sequence<τ_0_0>]` 分解成两条 requirement：`[τ_0_1: Sequence]` 和 `[τ_0_1.[Sequence]Element == τ_0_0]`。

> 译注：这正是本库读 opaque type descriptor 时看到的形态——`some Sequence<Int>` 在二进制里没有「parameterized protocol type」这种东西，只有一条 conformance requirement 加一条 same-type requirement。把 same-type requirement 归属回正确的 protocol（SE-0346 的 primary associated type 顺序在运行时不留痕迹）是本库单独处理的一件事，见 [OpaquePrimaryAssociatedTypeAttribution.md](../OpaquePrimaryAssociatedTypeAttribution.md) 与 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

下面我们把 requirement decomposition 写成算法。它基本上是上面内容的复述，外加一些细节和两个边界情形。

**算法（Decompose conformance requirement）.** 输入：一组 conformance requirement。输出：一组等价的新 requirement，其中所有 conformance requirement 的右边都是 protocol type。

1. 初始化一个空列表用来收集输出的 requirement。
2. 把所有输入 requirement 加入 worklist。
3. （Check）若 worklist 为空，返回输出列表。
4. （Loop）从 worklist 里取出一条 conformance requirement `[T: X]`，其中 `X` 是一个「protocol 样」的类型，属于下面三种之一。
5. （Base case）若 `X` 是 protocol type，输出 conformance requirement `[T: X]`。
6. （Composition）若 `X` 是 protocol composition type `M_1 & ... & M_n`，就访问每个成员 `M_i ∈ X`。若 `M_i` 是 class type，输出 superclass requirement `[T: M_i]`；若 `M_i` 是 `AnyObject`，输出 layout requirement `[T: AnyObject]`；否则 `M_i` 要么是 protocol type，要么还能继续分解——把 conformance requirement `[T: M_i]` 加入 worklist。
7. （Parameterized）若 `X` 是 parameterized protocol type `P<B_1, ..., B_n>`，其 base protocol type 为 `P`、generic argument 为 `B_i`，按如下方式分解这条 requirement：

   a. 输出 conformance requirement `[T: P]`。

   b. 对 `P` 的每个 primary associated type `A_i`，把 `T` 的 protocol substitution map 应用到 `A_i` 的 declared interface type 上：

   ```
   Self.[P]A_i ⊗ {Self ↦ T; [Self: P] ↦ [T: P]} = T.[P]A_i
   ```

   输出 same-type requirement `[T.[P]A_i == G_i]`。

8. （Error）若 `X` 是其它任何东西，我们就碰上了一条非法 requirement，例如 `[T: Int]`。诊断一个 error。
9. （Next）回到第 3 步。

第 7 步里 `T` 通常是一个 type parameter，于是 substituted type 就是 dependent member type `T.[P]A_i`。我们的算法依靠 type substitution 来顺带应付 `T` 是 concrete type 的情形。当 `T` 是 concrete type 时，每条新引入的 same-type requirement 的 subject type 必须是 concrete conformance `[T: P]` 中 `A_i` 的 type witness。例如给定 `[Array<τ_0_0>: Sequence<Int>]`，我们输出 `[Array<τ_0_0>: Sequence]` 和 `[τ_0_0 == Int]`。老实说这是个相当无聊的边界情形。有人可能以为 requirement inference 会触发这种场景：

```swift
typealias G<T: Sequence<Int>> = T
func f<E>(_: G<Array<E>>) {}
```

然而我们是先构建 `G` 的 generic signature 的，所以等轮到构建 `f()` 的 generic signature 时，requirement `[τ_0_0: Sequence<Int>]` 早就被分解过了；在 requirement inference 里访问 `G<Array<τ_0_0>>` 时，我们代入的是 `G` 已经分解、脱糖（实际上还已经最小化）的那些 requirement。事实上，触发它的唯一办法是直接手写出来：

```swift
func f<E>(_: Array<E>) where Array<E>: Sequence<Int> {}
```

decomposition 有一个更有用的应用。**abstract generic signature request** 会做 decomposition，以应付 `opaque-result-types.tex` 里的 opaque result type 和 `existential-types.tex` 里的 existential type。我们推敲这两类类型的办法，就是用这个 request 构建出一张描述该类型的「辅助」generic signature。`some` 或 `any` 关键字之后的 constraint type 定义了一条 conformance requirement，这条 requirement 必须由同一个算法来分解，我们才能解读 `any Sequence<Int>` 或 `some Equatable & AnyObject` 这样的东西。

### Desugaring

requirement inference 是一个有用模式的多个实例之一：把一张 substitution map 应用到某个 generic signature 的 minimal requirement 上，再从这些 substituted requirement 构建出一张新的 generic signature。比如我们就是这样用 **abstract generic signature request** 来检查 class method override 的。当原始 requirement 是 minimal 的时候，substituted requirement 已经是分解好的；但这样一条 requirement 的左边仍有可能不是 type parameter，而是 substitution 引入的 concrete type。

做个思想实验有助于理解「左边不是 type parameter 的 requirement」意味着什么。若某条 requirement `R` 的 subject type 是一个 interface type、未必是 type parameter，我们就没法用 derived requirement 形式体系来描述它。但我们仍然可以把一张 substitution map `Σ` 应用到 `R` 上，然后用 `type-resolution.tex` 的 Check requirement 算法检查 substituted requirement `R ⊗ Σ` 是否被满足；该算法里没有任何一步依赖于**原始** requirement 的 subject type 是 type parameter。

我们要把 `R` 变换成一组更简单的 requirement `{R_1, ..., R_n}`，使得对**每一张** substitution map `Σ`，`R ⊗ Σ` 被满足当且仅当对所有 `i ≤ n` 都有 `R_i ⊗ Σ` 被满足。当然实现里我们不会去遍历所有可能的 substitution map，这只是个思想实验。只要我们相信下面的变换维持了这条性质，就可以断定：把 `R` 换成 `{R_1, ..., R_n}` 不会改变 generic signature 的含义。

这条规则本质上就决定了 **requirement desugaring** 的实现。先考虑一条完全不含 type parameter 的 requirement，例如 `[Int: Hashable]` 或 `[Int == String]`。应用 substitution map 永远改变不了它，所以它要么恒真、要么恒假；我们可以用 Check requirement 算法检查它：

- 如果这条 requirement 被满足，我们就可以删掉它——也就是把它换成**空**的 requirement 集合——而不破坏我们的不变量。这条 requirement 没有带来任何新东西。
- 反过来，如果它不被满足，那唯一的出路就是把它换成另一个同样不可满足的东西，所以我们只能诊断一个 error 并放弃。

第二种情形值得多说几句。一个 requirement 无法被任何 substitution map 满足的 generic declaration，本质上是毫无用处的；本章 Requirement Minimization 一节会讲到，我们会设法发现「两条 requirement 相互冲突、无法同时满足」的情况。而在这里，requirement desugaring 检出的是一条 requirement 与**它自己**冲突这种平凡情形。

接下来考虑左边含有 type parameter 的 conformance requirement，比如 `[Array<τ_0_0>: Sequence]` 或 `[Array<τ_0_0>: Hashable]`。用 global conformance lookup，我们可以找到 subject type 对这个 protocol 的 concrete conformance。若这个 conformance 是 invalid 的，我们就有一个平凡冲突；若它是 unconditional 的，这条 requirement 就平凡地被满足。

如果这里拿到的是一条 conditional conformance，我们的不变量**别无选择**，只能把原来那条 requirement 换成这个 conformance 的 conditional requirement（unconditional conformance 的 conditional requirement 集合为空，所以其实只有这一条规则）。举例来说，因为 `Array` 对 `Hashable` 的 conditional conformance，我们知道：对任意 substitution map `Σ`，`Array<τ_0_0> ⊗ Σ` conform to `Hashable` 当且仅当 `τ_0_0 ⊗ Σ` conform to `Hashable`。因此 `[Array<τ_0_0>: Hashable]` 必须脱糖成 `[τ_0_0: Hashable]`，这就解释了我们先前是怎么从 `Set<Array<τ_0_0>>` 推断出 `[τ_0_0: Hashable]` 的：

```swift
func f<T>(_: Set<Array<T>>) /* where T: Hashable */ {}
```

最后，要给一条 same-type requirement 脱糖，我们考虑四种可能：

1. 两边都是 type parameter。
2. 左边是 type parameter，右边是 concrete type。
3. 左边是 concrete type，右边是 type parameter。
4. 两边都是 concrete type。

前两种情形已经是正确形式，做完了。第三种情形可归约到第二种，因为我们可以把两边交换——毕竟 same-type requirement 也是在说两边有相同的 reduced type，而这个关系是对称的。第四种情形下我们面对的是这样的东西：

```
[Dictionary<τ_0_0, Bool> == Dictionary<Int, τ_0_1>]
```

我们希望把它脱糖成两条 requirement：

```
[τ_0_0 == Int]
[Bool == τ_0_1]
```

第一条输出已经脱糖完毕；第二条要翻转一下，然后就做完了。反过来，假设给我们的是 `[Array<τ_0_0> == Set<τ_0_0>]`。没有任何 substitution map 能把两边变成同一个类型，所以这条 requirement 永远无法被满足。由此得到一般规则。

要让两个 concrete type 在所有 substitution 下都等价，它们只能在某些特定方面有所不同。两个类型**匹配（match）**，是指它们有相同的 kind、相同数量的 structural component type，以及完全相等的非类型信息（例子包括 nominal type 的 declaration、tuple 的标签、function parameter 的 value ownership kind，等等）。我们的匹配定义**不是**递归的，所以 `Array<Array<Int>>` 和 `Array<Set<Int>>` 仍然算匹配，因为最外层一切都对得上；但它们的两个子节点 `Array<Int>` 和 `Set<Int>` 则不匹配。

如果一条 same-type requirement 里的两个类型不匹配，我们就有一个冲突，于是诊断一个 error 并放弃。否则两个类型的子节点数量相等；我们并行遍历子节点，构造出一组与原 requirement 等价的更简单的 same-type requirement。这是一个递归过程：其中某些 requirement 可能还需要进一步脱糖，或者导致新的冲突，如此往复。

**算法（Desugar same-type requirement）.** 输入：一条任意的 same-type requirement。输出：一组 desugared requirement，以及一组 conflicting requirement。

1. 初始化空的输出列表和冲突列表。
2. 把输入 requirement 加入 worklist。
3. （Next）从 worklist 取出下一条 requirement `[T == U]`。
4. （Abstract）若 `T` 和 `U` 都是 type parameter，把 `[T == U]` 加入输出列表。
5. （Concrete）若 `T` 是 type parameter 而 `U` 是 concrete，输出 `[T == U]`。
6. （Flipped）若 `T` 是 concrete 而 `U` 是 type parameter，输出 `[U == T]`。
7. （Redundant）若 `T` 和 `U` canonically 相等，那么下面也生成不出任何非平凡的东西，直接跳到第 10 步。
8. （Recurse）若 `T` 和 `U` 匹配，令 `T_1 ... T_n` 与 `U_1 ... U_n` 分别是 `T` 和 `U` 的子节点。对每个 `1 ≤ i ≤ n`，把 `[T_i == U_i]` 加入 worklist。
9. （Conflict）若 `T` 和 `U` 不匹配，把 `[T == U]` 加入冲突列表并诊断。
10. （Loop）若 worklist 为空，返回；否则回到第 3 步。

接下来是给任意 requirement 脱糖的算法。它在 Decompose conformance requirement 算法之后运行，所以我们假设 conformance requirement 已经分解过了。注意这个算法是怎么推广 Check requirement 算法里那个「requirement 是否被满足」的检查的：如果我们给一条不含任何 type parameter 的 requirement 脱糖，那么冲突列表为空当且仅当这条 requirement 被满足。

**算法（Desugar requirement）.** 输入：一条任意的 requirement。输出：一组 desugared requirement，以及一组 conflicting requirement。

1. 初始化空的输出列表和冲突列表。
2. 把输入 requirement 加入 worklist。
3. （Next）从 worklist 取出下一条 requirement。若该 requirement 的 subject type 是 type parameter，把它加入输出列表并跳到第 5 步。
4. （Desugar）否则 subject type 是 concrete type。按 requirement kind 分别处理：

   a. 对 **conformance requirement** `[T: P]`，执行 global conformance lookup `P ⊗ T`：

      i. 若拿到一个 concrete conformance，把它的 conditional requirement（若有）加入 worklist。

      ii. 若拿到一个 invalid conformance，把 `[T: P]` 加入冲突列表。

   b. 对 **superclass requirement** `[T: C]`：

      i. 若 `T` 和 `C` 是同一个 class declaration 的两个 specialization，把 same-type requirement `[T == C]` 加入 worklist。

      ii. 若 `T` 没有 superclass type（见 `substitution-maps.tex` 的 Subclassing 一节），那 `T` 不可能是 `C` 的子类；把 `[T: C]` 加入冲突列表。

      iii. 否则令 `T′` 为 `T` 的 superclass type，把 superclass requirement `[T′: C]` 加入 worklist。

   c. 对 **layout requirement** `[T: AnyObject]`，concrete type `T` 里含有的任何 type parameter 都不影响结果，直接套用 Check requirement 算法即可。若不被满足，把 `[T: AnyObject]` 加入冲突列表。

   d. 对 **same-type requirement** `[T == U]`，套用 Desugar same-type requirement 算法，并把结果加进输出列表和冲突列表。

5. （Loop）若 worklist 为空，返回；否则回到第 3 步。

冲突列表里的 requirement 会被诊断成 error。输出列表里的 requirement 则具备了可供 minimization 使用的正确脱糖形式。重新表述一遍：

**定义.** 一条 **desugared requirement** 是满足下列条件的 requirement：

1. 左边是一个 type parameter。
2. 若它是 conformance requirement，右边是一个 protocol type。

## Well-Formed Requirements

经过 desugaring 与 decomposition，用户写的 requirement 现在已经是可以用 derived requirement 形式体系来推敲的形式了。到目前为止，除了要求 requirement 在**语法上**良构之外，我们没有对「一切推导之源」的那些 explicit requirement 施加任何限制。下一节会精确陈述 generic signature 的各项不变量，但在那之前，我们得先给理论补上一个「**语义上**良构的 requirement」的概念。事实证明，诊断某些畸形的 generic signature 正需要它。

为了引出良构性这个概念，我们回到 `generic-signatures.tex` 的 Derived Requirements 一节里 **valid type parameter** 的想法，具体来说是看 valid type parameter 的**前缀**。考虑下面的 type parameter `τ_0_0.Element.Element`：

```swift
struct Concat<C: Collection> where C.Element: Collection {
  let x: C.Element.Element = ...
}
```

一个 type parameter 是另一个 type parameter 的**前缀（prefix）**，是指它等于后者的 base type，或 base type 的 base type，任意嵌套层数皆可。所以 `τ_0_0.Element` 和 `τ_0_0` 是 `τ_0_0.Element.Element` 的两个前缀。从用户的角度看，如果 `C.Element.Element` 是一句可以写进程序的有意义的话，那 `C.Element` 当然也应该是！这提示了任何「好」的 generic signature 都该具备的一条合理性质：**valid type parameter 的每一个前缀本身也是 valid type parameter**。不过这还不是我们的最终条件，我们要进一步推广。

当我们说一个 type parameter `T` 在 generic signature `G` 里是 valid 的，意思是我们有一个推导 `G ⊢ T`。只有少数几条推导规则能推出 type parameter，我们也可以这样刻画它们：

**命题.** 设 `G` 是一个 generic signature，`T` 是一个 type parameter。

- 若 `T` 是一个 generic parameter，则 `T` valid 当且仅当它出现在 `G` 里。
- 若 `T` 是一个 unbound dependent member type `U.A`，则 `T` valid 当且仅当存在某个 protocol `P` 声明了名为 `A` 的 associated type，且 `G ⊢ [U: P]`。
- 若 `T` 是一个 bound dependent member type `U.[P]A`，则 `T` valid 当且仅当 `G ⊢ [U: P]`，其中 `P` 是 `[P]A` 所指的 associated type declaration 的父 protocol。

如果我们手上的 generic signature 具备「`T` 的每个前缀也 valid」这条性质，那么在上面 `T` 是 dependent member type 的情形里，`[U: P]` 的 subject type `U` 是 `T` 的一个前缀，所以 `U` 必然 valid。我们说一条 requirement `[U: P]` 是 **well-formed** 的，如果它的 subject type `U` 是 valid 的。有了这个良构性概念，就能用一个更一般的说法把「前缀有效性」囊括进来：**每一条 derived conformance requirement 都必须是 well-formed 的**。换句话说，我们希望对所有 `U` 和 `P`，`G ⊢ [U: P]` 都蕴含 `G ⊢ U`。

再进一步推广，考虑 type substitution。设 `G` 是这样一个 generic signature：它的某条 derived requirement（未必是 conformance requirement）里含有一个非法的 type parameter。由 Check requirement 算法可知，没有任何 substitution map `Σ` 能满足这条 requirement——因为应用 `Σ` 之后，那个非法的 type parameter 会变成 error type。回忆 `extensions.tex` 里 well-formed **substitution map** 的定义，我们得出结论：`G` 根本不可能有任何 well-formed substitution map！为排除这种情况，我们把条件推广到所有 requirement kind。

**定义.** 一条 requirement 相对于 generic signature `G` 是 **well-formed** 的，如果该 requirement 中含有的所有 type parameter 都是 `G` 的 valid type parameter：

- **conformance requirement** `[T: P]` 是 well-formed 的，如果 `G ⊢ T`。
- **superclass requirement** `[T: C]`（用 `{C_1, ..., C_n}` 表示 `C` 中含有的 type parameter 集合）是 well-formed 的，如果 `G ⊢ T` 且对所有 `1 ≤ i ≤ n` 有 `G ⊢ C_i`。
- **layout requirement** `[T: AnyObject]` 是 well-formed 的，如果 `G ⊢ T`。
- **same-type requirement** `[T == U]`（用 `{U_1, ..., U_n}` 表示 `U` 中含有的 type parameter 集合）是 well-formed 的，如果 `G ⊢ T` 且对所有 `1 ≤ i ≤ n` 有 `G ⊢ U_i`。（若右边的 `U` 本身就是一个 type parameter，这个集合平凡地就是 `{U}`。）

下面我们会同时谈到「derived」和「well-formed」两种 requirement，所以在把读者彻底绕晕之前，先把区别讲透。回忆 `Concat` 的 generic signature：

```
<τ_0_0 where τ_0_0: Collection, τ_0_0.Element: Collection>
```

我们**推导不出** `[τ_0_0.Element.Element: Hashable]`，因为这个 signature 里没有任何东西是 `Hashable` 的。然而这条 requirement 无疑是 well-formed 的，因为 `τ_0_0.Element.Element` 在我们的 generic signature 里是一个 valid type parameter。所以说：derived requirement 是可证明**为真**的；well-formed requirement 则是作为一个**问题**说得通。于是从前缀有效性出发，我们抵达了最终的表述：我们希望自己的 generic signature 只证明那些说得通的东西！

**定义.** 一个 generic signature `G` 是 **well-formed** 的，如果 `G` 的所有 derived requirement 都是 well-formed 的。

这个定义没有直接给出检查良构性的算法。一般而言，一个 generic signature 的 derived requirement 是无穷集合，我们没法把它们一一枚举。这个两难很快就会解决。

注意，若对某个 protocol `P` 有 `G ⊢ [T: P]`，那么 `G` 的良构性就隐含地依赖于 `P` 的 associated requirement 的良构性；我们是相对于 `G` 的 **protocol dependency set**（即那些可以出现在 derived conformance requirement 右边的 protocol）来解读 `G` 的。这个话题会在 `basic-operation.tex` 的 Protocol Components 一节回来；眼下我们可以保守地把这个集合取为**全体** protocol。

还有一件事。为推动良构 generic signature 的定义而证得的那个结果，后面还用得上，所以在此重新陈述留存：

**命题.** 设 `G` 是一个 well-formed generic signature，`T` 是 `G` 的一个 valid type parameter。那么 `T` 的每一个前缀也是 `G` 的 valid type parameter。

### Diagnostics

现在给一个**不**良构的 generic signature 的例子。回到 `Concat` 类型，只是这次我们「忘了」写 `C` 必须 conform to `Collection`：

```swift
struct Bad<C /* : Collection */> where C.Element: Collection {}
```

尽管如此，从 explicit requirement `[τ_0_0.Element: Collection]` 出发，我们仍能推出别的 requirement 和 valid type parameter；随便挑几条：

```
1. [τ_0_0.Element: Collection]                    (Conf)
2. [τ_0_0.Element: Sequence]                      (AssocConf 1)
3. [τ_0_0.Element.Iterator: IteratorProtocol]     (AssocConf 2)
4. τ_0_0.Element.Iterator.Element                 (AssocName 3)
```

derived requirement (1) 和 (2) 不是 well-formed 的，因为它们的 subject type 不是 valid type parameter；而 valid type parameter (4) 有一个非法的前缀 `τ_0_0.Element`。显然 `Bad` 应当被编译器拒绝。那么实际类型检查 `Bad` 时发生了什么？回忆 `type-resolution.tex` 里的 type resolution stage。我们先在 structural resolution stage 解析 requirement `[τ_0_0.Element: Collection]`，得到一条 subject type 是 unbound dependent member type 的 requirement。此刻我们还不知道这条 requirement 不良构。

构建完 `Bad` 的 generic signature 之后，我们会再访问一次 `where` clause，这次在 interface resolution stage 解析那条 requirement。由于 subject type 不是 valid type parameter，type resolution 诊断一个 error 并返回 error type：

```
bad.swift:1:23: error: `Element' is not a member type of type `C'
struct Bad<C> where C.Element: Sequence {}
                      ^
```

接下来定义「一条 associated requirement 良构」是什么意思：

**定义.** protocol `P` 的一条 associated requirement 是 **well-formed** 的，如果它对 protocol generic signature `G_P` 而言是一条 well-formed requirement；也就是说，它含有的所有 type parameter 在 `G_P` 里都是 valid type parameter。

一个 generic signature 可能依赖源码里写的 protocol，也可能依赖来自 serialized module 的 protocol。对源码里写的 protocol，type resolution 会在 requirement signature 构建完毕后、于 interface resolution stage 再访问一遍它们的 associated requirement，以检查其良构性。来自 serialized module 的 protocol 则已经具备良构的 associated requirement，因为它们在序列化之前就已检查过。于是，只要 type resolution 没诊断出任何 error，所有用户写的 requirement 就都是良构的。下面这条定理说，这是 main module 中所有 generic signature 都良构的**充分条件**。

**定理.** 假设 generic signature `G` 满足下列条件：

- `G` 的每一条 explicit requirement都是 well-formed 的。
- 对每个使得存在某个 `T` 满足 `G ⊢ [T: P]` 的 protocol `P`，`P` 的每一条 associated requirement 都是 well-formed 的（相对于 protocol generic signature `G_P`）。

那么 `G` 的每一条 **derived** requirement 都是 well-formed 的；换言之，`G` 是 well-formed 的。

要证明这条定理，我们得先扩充推敲推导的手段。首先回忆 `generic-signatures.tex` 的 Requirement Signatures 一节里的 protocol generic signature。若 `P` 是任意 protocol，它的 generic signature（记作 `G_P`）只有一条 requirement `[Self: P]`。一如既往，protocol 的 `Self` 类型是 `τ_0_0` 的语法糖。

protocol generic signature 刻画了由该 protocol 的 requirement signature 所生成的结构。这些就是在该 protocol 及其 unconstrained extension 的声明内部可见的 valid type parameter 与 derived requirement。这些 type parameter 都以 protocol 的 `Self` 类型为根，而这些 derived requirement 谈论的正是这些以 `Self` 为根的 type parameter。不严格地说：凡是我们能在 `G_P` 里对 protocol `Self` 类型说的话，对另一张满足 `G ⊢ [T: P]` 的 generic signature `G` 里的任意 type parameter `T` 也都应当成立。下面把这一点讲精确。

举例来说，我们可能先在 `Collection` 的 protocol extension 里定义一个算法，再从另一个 generic function 里调用它：

```swift
extension Collection {
  func myComplicatedAlgorithm() {...}
}

func anotherAlgorithm<C: Collection>(_ c: C, _ index: C.Element.Index)
    where C.Element: Collection {
  c[index].myComplicatedAlgorithm()
}
```

`anotherAlgorithm()` 的 generic signature 与前面的 `Concat` 相同，记作 `G`。对 `myComplicatedAlgorithm()` 的那次引用带有这张 substitution map：

```
{Self ↦ τ_0_0.Element;
 [Self: Collection] ↦ [τ_0_0.Element: Collection]}
```

input generic signature 是 `G_Collection`，output generic signature 是 `G`，所以为了让泛型「跑得通」，我们会期待：把这张 substitution map 应用到 `G_Collection` 的某个 valid type parameter 或 derived requirement 上，应当在 `G` 里得到一个 valid type parameter 或 derived requirement。

假设 `myComplicatedAlgorithm()` 的函数体里用到了 `Self.SubSequence.Index` conform to `Comparable` 这件事。我们可以推导出这条 requirement，以及 `Self.SubSequence.Index` 的有效性（于是这条 requirement 是良构的）：

```
1. [Self: Collection]                             (Conf)
2. [Self.SubSequence: Collection]                 (AssocConf 1)
3. Self.SubSequence.Index                         (AssocName 2)
4. [Self.SubSequence.Index: Comparable]           (AssocConf 2)
```

我们把 substitution map 应用到 (3) 和 (4) 上。当然，我们还没解释过怎么把 substitution map 应用到 dependent member type 上！那要留到下一章；眼下先做个简化假设：我们执行的是把 `Self` 语法性地替换成 `τ_0_0.Element`。于是得到：

```
τ_0_0.Element.SubSequence.Index
[τ_0_0.Element.Self.SubSequence.Index: Comparable]
```

要证明第一个是 `G` 的 valid type parameter、第二个是 `G` 的 derived requirement，只需拿原来在 `G_Collection` 里的推导，把其中的 `Self` 通篇换成 `τ_0_0.Element`：

```
1. [τ_0_0.Element: Collection]                            (Conf)
2. [τ_0_0.Element.SubSequence: Collection]                (AssocConf 1)
3. [τ_0_0.Element.SubSequence.Index: Comparable]          (AssocConf 2)
```

这之所以行得通，是因为 `[τ_0_0.Element: Collection]` 是 `G` 的一条 **explicit** requirement，所以还不够一般。假设我们从一条更复杂的 **derived** conformance requirement 出发，比如同一张 signature 里的 `G ⊢ [τ_0_0.Indices: Collection]`：

```
1. [τ_0_0: Collection]                            (Conf)
2. [τ_0_0.Indices: Collection]                    (AssocConf 1)
```

要为 `G ⊢ [τ_0_0.Indices.SubSequence.Index: Comparable]` 构造推导，我们先把那条基本步骤 `[Self: Collection]` 替换成 `G ⊢ [τ_0_0.Indices: Collection]` 的**整个推导**，再在其余各步里把 `Self` 代换成 `τ_0_0.Indices`：

```
1. [τ_0_0: Collection]                                    (Conf)
2. [τ_0_0.Indices: Collection]                            (AssocConf 1)
3. [τ_0_0.Indices.SubSequence: Collection]                (AssocConf 2)
4. [τ_0_0.Indices.SubSequence.Index: Comparable]          (AssocConf 3)
```

protocol generic signature 有两条基本推导步骤，所以我们也可能遇到一个以 `Self` 的 **Generic** 基本步骤开头的推导。例如可以在 `G_Collection` 里推导出 requirement `[Self == Self]`：

```
1. Self                    (Generic)
2. [Self == Self]          (Reflex 1)
```

要得到推导 `G ⊢ [τ_0_0.Indices == τ_0_0.Indices]`，我们利用「`τ_0_0.Indices` 是 `G` 的 valid type parameter」这一事实，把 `Self` 的那条基本推导步骤替换成 `G ⊢ τ_0_0.Indices` 的整个推导：

```
1. [τ_0_0: Collection]                         (Conf)
2. τ_0_0.Indices                               (AssocName 1)
3. [τ_0_0.Indices == τ_0_0.Indices]            (Reflex 2)
```

现在陈述一般性的结果。我们在证明上面那条定理时需要它，稍后在 `conformance-paths.tex` 的 Validity and Existence 一节证明「每条 derived conformance requirement 都有特定形式的推导」时也需要它。

**引理（Formal substitution）.** 设 `G` 是任意 generic signature。假设对某个 type parameter `T` 和 protocol `P` 有 `G ⊢ T` 与 `G ⊢ [T: P]`。那么，取 `G_P` 的一个 valid type parameter 或 derived requirement，把其中的 `Self` 通篇替换成 `T`，得到的就是 `G` 的一个 valid type parameter 或 derived requirement，只不过根换成了 `T`。即：

- 若 `G_P ⊢ Self.U`，则 `G ⊢ T.U`。
- 若 `G_P ⊢ R`，则 `G ⊢ R′`，其中 `R′` 是把 `R` 里的 `Self` 替换成 `T` 得到的 substituted requirement。

**证明.** 设想我们要为上面这件事写一个**算法**。输入是：一个 generic signature `G`、一对推导 `G ⊢ T` 与 `G ⊢ [T: P]`，以及 `G_P` 里的某个推导。我们逐步访问 `G_P` 里的推导，把它改写成 `G` 里的推导。先看 `G_P` 的基本推导步骤：

```
Self                    (Generic)
[Self: P]               (Conf)
```

这两条分别被替换成 `T` 和 `[T: P]` 的**整个推导**：

```
T                       (...)
[T: P]                  (...)
```

对其余所有推导步骤，我们把该步骤陈述中出现 `Self` 的地方通通换成 `T`。这就给出了 `G` 里所需的推导。

关于上面这个证明，再说几句。要做到完全严格，我们应该逐条过一遍 inference rule，论证替换在每种情形下都输出一个有意义的推导步骤。我们不打算这么做，因为我们会在上面那条定理的证明里演示这种穷尽式的分情形讨论。最后请注意，本引理假设了 `[T: P]` 是良构的，因为我们需要 `G ⊢ T`；但我们**特意没有**假设 `G` 本身良构。事实上我们要用这条引理去证那条定理，所以那样的假设会造成循环论证。

### Structural induction

假设 `P(n)` 是关于自然数的某条性质，我们想证明它对所有 `n ∈ ℕ` 都成立。我们可以用**归纳法**论证，把证明写成两部分：

- **基础情形（base case）**：`P(0)` 为真。
- **归纳步骤（inductive step）**：我们**假设** `P(n)` 对某个固定但任意的 `n` 为真，然后据此证明 `P(n+1)` 为真。

举例来说，设 `P(n)` 是命题「`0+1+2+⋯+n = n(n+1)/2`」。我们可以用归纳法证明它恒真：

- 要证 `P(0)`，把 `n = 0` 代入公式。左边是零，右边是 `n(n+1)/2 = 0(0+1)/2 = 0`。
- 要证归纳步骤，我们假设 `P(n)`，即 `0+1+2+⋯+n = n(n+1)/2`，然后两边同加 `n+1`。右边化简如下，于是 `P(n+1)` 成立：

  ```
  n(n+1)/2 + (n+1) = (n² + n + 2n + 2)/2 = (n² + 3n + 2)/2 = (n+1)(n+2)/2
  ```

归纳法证明有点像一份「菜谱」，告诉我们怎么为某个具体的 `n ∈ ℕ` 推导出一个证明。比如我们想证 `P(2)`：先写下基础情形 `P(0)`；然后用 `n = 0` 的归纳步骤，得知 `P(0)` 蕴含 `P(1)`，而 `P(0)` 为真，故 `P(1)` 为真；接着用 `n = 1` 的归纳步骤，断定 `P(2)` 为真。用这份「菜谱」，我们可以这样为任意 `n` 构造出证明。

归纳法证明是 **Peano arithmetic**（自然数的一套形式系统）的一条公理。可以这样理解它：归纳法是说，从「0」出发反复应用**后继函数** `1+` 就能到达任何自然数。注意这种自然数编码方式有多像一个 Swift enum：

```swift
enum Nat {
  case zero
  indirect case successor(Nat)
}
```

例如 `3 = 1+(1+(1+0))`，也就是：

```swift
let three: Nat = .successor(.successor(.successor(.zero)))
```

现在回到 derived requirement 形式体系。我们的陈述都是有限的数据结构；虽然它们比 `Nat` 的实例复杂，但它们具备同样的本质特征：

- **基本陈述**——generic parameter 和 explicit requirement——扮演数字 0 的角色。
- 其余每一条陈述都是对先前一条或多条陈述应用某条固定的 inference rule 生成的。inference rule 类比于把数字加一的后继函数。

若 `P` 是关于 requirement 和 type parameter 的某条性质，`G` 是某个 generic signature，我们可以用**结构归纳法（structural induction）**证明 `P` 对 `G` 的所有 derived requirement 和 valid type parameter 都成立。结构归纳法证明有两部分：

- **基础情形**确立 `P(D)` 对每一条基本陈述 `D` 成立。回忆这些基本陈述就是 `G` 的每个 generic parameter 对应的 **Generic** 步骤，以及 `G` 的每条 explicit requirement 对应的步骤。
- **归纳步骤**：我们有一个以 `D_1, …, D_n` 为假设、以 `D` 为结论的推导步骤。我们假设 `P(D_1), …, P(D_n)` 成立，然后论证 `P(D)` 必然随之成立。我们可以对各条 inference rule 做分情形讨论，逐一处理每种 inference rule。

如果我们只想证明关于 derived requirement 的命题，上面的方案要略作修改：基础情形不再需要考虑 **Generic** 步骤，但 **Reflex** 步骤**变成了**一个基础情形，因为它的假设都不是 requirement。下面这个证明（我们现在终于可以写出来了）用的就是这个修改过的方案。

**证明（上面那条定理）.** 给定一条满足 `G ⊢ R` 的 requirement `R`，以及 `R` 中含有的一个 type parameter，我们必须为这个 type parameter 构造出一个推导。

**基础情形.** 基本陈述根本没有假设：

```
[T: P]                  (Conf)
[T == U]                (Same)
[T == X]                (Concrete)
[T: C]                  (Super)
[T: AnyObject]          (Layout)
```

由基本陈述证明的 requirement 是 `G` 的 explicit requirement。定理的第一条假设就是 `G` 的所有 explicit requirement 都良构，所以做完了。**Reflex** inference rule 是另一个基础情形，因为它的假设是一个 type parameter 而不是 requirement：

```
[T == T]                (Reflex T)
```

假设 `G ⊢ T`，按定义即可推出结论 `[T == T]` 良构。

**归纳步骤.** 我们必须逐一处理每种 inference rule。先看一个 **AssocBind** 步骤，其中 `T` 是某个 type parameter、`P` 是某个 protocol、`A` 是某个 associated type：

```
[T.[P]A == T.A]         (AssocBind [T: P])
```

结论是一条含有两个 type parameter（`T.[P]A` 和 `T.A`）的 derived same-type requirement。我们可以用 **AssocDecl** 和 **AssocName** 从 conformance requirement `[T: P]` 推出这两者：

```
1. [T: P]               (...)
2. T.[P]A               (AssocDecl 1)
3. T.A                  (AssocName 2)
```

> 译注：原书这里第 3 步写的是 `(AssocName 2)`，而 **AssocName** 规则的前提应当是一条 conformance requirement（即第 1 步），第 2 步是一个 type parameter；正文也说「我们可以用 AssocDecl 和 AssocName 从 conformance requirement `[T: P]` 推出这两者」。疑为编号笔误，以正文说法为准（两步都应引用第 1 步）。

接下来看 **SameName** 和 **SameDecl** 两条推导步骤：

```
[T.A == U.A]            (SameName [U: P] [T == U])
[T.[P]A == U.[P]A]      (SameDecl [U: P] [T == U])
```

这里有四个 type parameter 要推导：`T.A`、`T.[P]A`、`U.A` 和 `U.[P]A`。我们先从 `[U: P]` 推出 `[T: P]`，再分别对 `[T: P]` 和 `[U: P]` 应用 **AssocDecl** 与 **AssocName**：

```
1. [U: P]               (...)
2. [T == U]             (...)
3. [T: P]               (SameConf 1 2)
4. T.A                  (AssocName 3)
5. T.[P]A               (AssocDecl 3)
6. U.A                  (AssocName 1)
7. U.[P]A               (AssocDecl 1)
```

要处理由 protocol `P` 的 associated requirement 生成的那些推导步骤，我们必须动用定理的第二条假设，以及上面那条 Formal substitution 引理。最简单的情形是 **AssocConf** 或 **AssocLayout** 步骤：

```
[T.U: Q]                (AssocConf [Self.U: Q]_P [T: P])
[T.U: AnyObject]        (AssocLayout [Self.U: AnyObject]_P [T: P])
```

由归纳假设有 `G ⊢ T`。我们要证 `G ⊢ T.U`。右边那条 requirement 是把某条 associated conformance requirement `[Self.U: Q]_P` 里的 `Self` 替换成 `T` 得到的。按假设，这条 associated requirement 相对于 `G_P` 是良构的，所以我们有推导 `G_P ⊢ Self.U`。Formal substitution 引理的所有条件都满足，于是我们能构造出推导 `G ⊢ T.U`。

对于 associated same-type requirement `[Self.U == Self.V]_P`，我们重复同样的构造来推出 `G ⊢ T.U` 和 `G ⊢ T.V`：

```
[T.U == T.V]            (AssocSame [Self.U == Self.V]_P [T: P])
```

如果面对的是 concrete same-type requirement `[Self.U == X]_P` 或 superclass requirement `[Self.U: C]_P`，我们同样用 Formal substitution 引理推出出现在 `X′` 和 `C′` 里的每个 type parameter——这里 `X′` 和 `C′` 分别表示把 `X` 和 `C` 里的 `Self` 结构性替换成 `T` 得到的类型：

```
[T.U == X′]             (AssocConcrete [Self.U == X]_P [T: P])
[T.U: C′]               (AssocSuper [Self.U: C]_P [T: P])
```

最后，其余所有推导步骤都具备这样的性质：出现在结论里的 type parameter 已经出现在它们的假设里，所以由归纳假设，这条 derived requirement 是良构的：

```
[U == T]                (Sym [T == U])
[T == V]                (Trans [T == U] [U == V])
[T: P]                  (SameConf [U: P] [T == U])
[T == X]                (SameConcrete [U == X] [T == U])
[T: C]                  (SameSuper [U: C] [T == U])
[T: AnyObject]          (SameLayout [U: AnyObject] [T == U])
```

归纳完成。

形式上，结构归纳法依赖一个 well-founded order（见 `generic-signatures.tex` 的 Reduced Type Parameters 一节），所以我们会用推导上的「包含」序。不过「递归算法」这个视角对我们来说已经够用了。自然数上的归纳法在入门书里有讲（Grimaldi 1998，《Discrete and Combinatorial Mathematics: An Applied Introduction》）；形式逻辑中的结构归纳法可参考 Bradley 与 Manna 2007 年的《The Calculus of Computation: Decision Procedures with Applications to Verification》。我们还会在 `conformance-paths.tex` 的 Validity and Existence 一节研究 conformance path、在 `monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 A Swift Connection 一节把有限表现的 monoid 编码成 protocol、以及最后在 `symbols-terms-and-rules.tex` 里给出 Requirement Machine 的正确性证明时，再次用到推导上的结构归纳法。

在结束本节之前，我们回到 `generic-signatures.tex` 的 Bound Type Parameters 一节里的 bound 与 unbound type parameter，并证明最后一个结果。我们此前声称：type parameter 的每个等价类里都同时含有一个 bound 代表元和一个 unbound 代表元。这其实需要「我们的 generic signature 是良构的」这个假设。

**定理.** 设 `G` 是一个 well-formed generic signature，`T` 是 `G` 的一个 valid type parameter。那么 `T` 的等价类里还含有两个 type parameter（未必唯一），记作 `T*` 和 `T_*`，使得：

1. `T*` 是一个 bound type parameter，
2. `T_*` 是一个 unbound type parameter，
3. `T*` 与 `T_*` 和 `T` 有相同的 type parameter length，
4. 在 type parameter order 下有 `T* ≤ T ≤ T_*`。

此外，若 `T` 是一个 reduced type parameter，则 `T*` canonically 等于 `T`，因而 `G` 的每个 reduced type parameter 都是 bound type parameter。

**证明.** 我们对 type parameter `T` 的 length 作归纳。基础情形里我们证明该性质对所有 generic parameter 成立；归纳步骤里我们证明，只要某个 dependent member type 的 base type 具备该性质，它本身也具备。

**基础情形.** 若 `T` 是一个 generic parameter type `τ_d_i`，我们可以把 `T*` 和 `T_*` 都取成 `T`，于是 `T* ≤ T ≤ T_*` 成立。然后推导两次平凡的 same-type requirement：

```
1. τ_d_i                      (Generic)
2. [τ_d_i == τ_d_i]           (Reflex 1)
3. [τ_d_i == τ_d_i]           (Reflex 1)
```

**归纳步骤.** 假设 `T` 是一个 dependent member type，对某个 `U` 和 `P` 的 associated type `A`，它要么是 `U.[P]A`（bound），要么是 `U.A`（unbound）。因为 `T` valid，所以 `G ⊢ [U: P]`；又因为 `[U: P]` 良构，所以 `G ⊢ U`。`U` 的 length 比 `T` 小一，于是归纳假设给出一对 same-type requirement `[U == U*]` 和 `[U == U_*]`，且 `U* ≤ U ≤ U_*`。我们令 `T* := U*.[P]A`、`T_* := U_*.A`，并通过 **SameDecl**、**AssocBind** 和 **SameName** 推出三条新的 same-type requirement：

```
1. [U.[P]A == T*]             (SameDecl [U == U*] [U: P])
2. [U.[P]A == U.A]            (AssocBind [U: P])
3. [U.A == T_*]               (SameName [U == U_*] [U: P])
```

由 `generic-signatures.tex` 的 Reduced Type Parameters 一节中 type parameter order 的定义，还可以看出：

```
T* ≤ U.[P]A < U.A ≤ T_*
```

若 `T` 是 bound dependent member type `U.[P]A`，那么 `[T == T*]` 已经作为 (1) 得到，但我们还得推出 `[T == T_*]`：

```
4. [T == T_*]                 (Trans 2 3)
```

若 `T` 是 unbound dependent member type `U.A`，情况正好相反：`[T == T_*]` 已经作为 (3) 得到，但我们要用 **Sym** 和 **Trans** 推出 `[T == T*]`：

```
5. [U.[P]A == T]              (Sym 2)
6. [T == T*]                  (Trans 5 1)
```

> 译注：原书第 5 步写成 `[U.[P]A == T]`，但 **Sym** 作用在第 2 步 `[U.[P]A == U.A]` 上应得 `[U.A == U.[P]A]`（此分支中 `T` 即 `U.A`，故应为 `[T == U.[P]A]`）；也只有这样才能与第 1 步 `[U.[P]A == T*]` 经 **Trans** 接出第 6 步的 `[T == T*]`。疑为两个参数写反的笔误，以推导能接上的那个版本为准。

归纳完成。要证明定理的第二部分，我们进一步假设 `T` 是 reduced 的。由前面的论证，我们得到一个 bound type parameter `T*` 满足 `T* ≤ T`。另一方面，reduced type parameter 是其等价类中的最小元，所以 `T ≤ T*`。于是当 `T` reduced 时，`T*` canonically 等于 `T`。

## Requirement Minimization

前面两张流程图里的最后一步叫 **requirement minimization**。要完成 generic signature 的构建，我们必须把那串 desugared requirement 变换成一串 **minimal** requirement。这些 minimal requirement 随后连同流程一开始收集到的 generic parameter type 列表一起交给 primitive constructor，我们的 generic signature 就成了！

由于 generic signature 在 Swift ABI 中扮演核心角色，值得抽象地描述一遍 requirement minimization 问题——这就是本节的目标。实现本身要到 Requirement Machine 那一部分才会揭晓：先从 desugared requirement 构建一个 convergent rewriting system（见 `symbols-terms-and-rules.tex` 的 Rules 一节），再做 rewrite rule minimization（见 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)））。本节的材料基于 Doug Gregor 2018 年关于 `GenericSignatureBuilder` 的早期文档《Generic Signatures》。

requirement minimization 的关键行为可以归纳成三条：

1. type substitution 只接受 bound dependent member type。为了确保我们能把一张 substitution map 应用到某个 generic signature 的 requirement 上（比如 `type-resolution.tex` 的 Check substitution map 算法就要这么干），每条 requirement 都被改写成使用 bound dependent member type 的形式。

2. generic signature 刻画了 generic function 的调用约定、nominal type metadata 的布局、符号名的 mangling，等等。为确保无关紧要的语法变动不影响 ABI，generic signature 里的每条 requirement 都被 **reduce** 成尽可能简单的形式，redundant requirement 被丢弃以得到一份 **minimal** 列表，并且这份列表按 canonical order 排序。

3. 我们需要检出并诊断那些带有 **conflicting requirement**、无法被任何 well-formed substitution map 满足的 generic signature。有了这一条，我们才能假设：只要类型检查期间没发出诊断，main module 里的所有 generic signature 就都是可满足的。

> 译注：第 2 条那份「canonical order」正是本库在二进制里看到的 requirement 顺序——descriptor 里逐条存的就是排序后的结果，本库不重排、只按序读回，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

### Equivalence of requirements

在 derived requirement 形式体系里，一个 generic signature 无非就是一串 requirement。上一节我们看到，我们对这些 requirement 唯一真正需要的假设，就是它们是 desugared requirement。于是，交给 minimization 的那些 desugared requirement，连同 generic parameter type 列表，在我们的理论里已经构成一个 generic signature 了。

我们把满足刚才所述那些附加条件的 generic signature 定义为 **minimal** generic signature。我们把 requirement minimization 理解成一个数学**函数**：输入一个 generic signature，输出一个 minimal generic signature。在实现里，所有 generic signature 都来自 requirement minimization，所以所有 generic signature 实际上都是 minimal 的。为了给这个变换找到依据，我们引入 **equivalent** generic signature 的概念。两个 generic signature 等价，是指它们生成相同的**理论（theory）**，也就是它们有相同的 valid type parameter 集合与 derived requirement 集合。特别地请注意：若两个 generic signature `G_1` 与 `G_2` 等价，则 `G_1` 良构当且仅当 `G_2` 良构。

**命题.** 任意两个满足下列条件的 generic signature `G_1` 与 `G_2` 是**等价的**，即它们生成相同的理论：

1. `G_1` 与 `G_2` 有相同的 generic parameter type 列表。
2. `G_1` 的每条 explicit requirement 都能在 `G_2` 中推导出来。
3. `G_2` 的每条 explicit requirement 都能在 `G_1` 中推导出来。

**证明.** 我们先论证 `G_1` 的理论是 `G_2` 的理论的子集，再反过来论证一遍，由此证明两者生成相同的理论。

假设给定一个推导 `G_1 ⊢ D`，其中 `D` 要么是 `G_1` 的一个 valid type parameter、要么是一条 derived requirement。我们要证明 `D` 也是 `G_2` 的 valid type parameter 或 derived requirement。能出现在 `G_1 ⊢ D` 里的基本推导步骤，就是由 `G_1` 的 generic parameter 和 explicit requirement 所定义的那些。我们可以机械地从 `G_1 ⊢ D` 构造出 `G_2 ⊢ D` 的推导，从而得出结论：

1. 由第一条假设，每个推出 `G_1` 的 generic parameter 的 **Generic** 步骤，本身已经是 `G_2` 的合法 **Generic** 步骤，所以原样保留。
2. 由第二条假设，`G_1` 的每条 explicit requirement 所对应的基本步骤，在 `G_2` 里都有一个推出同一条 requirement 的**推导**。我们把每个基本步骤替换成它的推导。
3. 其余所有推导步骤原样保留。

这就是 `G_2` 里的一个推导，于是 `G_1` 的理论是 `G_2` 的理论的子集。要得到另一个方向的包含，把 `G_1` 和 `G_2` 交换、在第 2 步里改用第三条假设，同样论证一遍即可。

请注意我们**不会**去尝试删除「redundant generic parameter」。比如 `<T, U where T: Sequence, U == T.Element>` 与 `<T where T: Sequence>` 在某种更宽泛的意义上也算「等价」，因为前一个理论里的任何推导都能通过把 `U` 换成 `T.Element` 变换成后者的推导。后者也更「minimal」，因为带这张 signature 的函数的调用约定只需传 `T` 的 type metadata，而不必同时传 `T` 和 `U`。既然我们不走这个方向，我们的等价概念就把「原始 generic signature 与 minimal generic signature 拥有完全相同的 generic parameter type 列表」这件事内建了进去。

我们希望 requirement minimization 输出一个等价的 minimal generic signature，但有两个重要的例外要记住：

1. 若某些原始 requirement 不是良构的，我们就没法把它们改写成使用 bound dependent member type 的形式，于是只好把它们丢掉，此时 minimal generic signature 描述的是一个更小的理论。这没关系；type resolution 早已诊断过 error，我们不会走到代码生成那一步。
2. 我们的 derived requirement 形式体系并没有解释 superclass、layout 和 concrete same-type requirement 的全部已实现行为。若这些 requirement kind 出现在 generic signature 的 explicit requirement 里、或出现在某个 protocol 的 associated requirement 里，minimization 就可能输出一个理论不同的 generic signature。后面会看到这类例子。

插一句：上面这条命题和上一节最后那条关于 bound / unbound 代表元的定理，终于让我们能够解释——为什么在推导里，我们可以视场合把 explicit requirement 写成含 bound **或** unbound dependent member type 的形式。的确，有时我们为省地方省掉 `[P]`，有时为了明确又把它写上。结果表明这无关紧要：只要出发点的那些 explicit requirement 是良构的，两份列表就能互相推导，并抵达同一个理论。

### Reduced requirements

现在我们朝着 minimal generic signature 的定义推进。考虑这个函数：

```swift
func uniqueElements1<T: Sequence>(_: T) -> Int
    where T.Element: Hashable {}
```

构建 `uniqueElements1()` 的 generic signature 时，type resolution 在 structural resolution stage 给出两条用户写的 requirement：

```
{[T: Sequence], [T.Element: Hashable]}
```

第二条的 subject type 是一个 unbound dependent member type，由 generic parameter type `T` 和标识符 `Element` 构成。我们可以把第二条换成 `[T.[Sequence]Element: Hashable]`；后者的 subject type 是 bound dependent member type，由 `T` 和 `Sequence` 的 associated type declaration `Element` 构成。为证明这么做站得住脚，我们可以从 `[T.Element: Hashable]` 推出 `[T.[Sequence]Element: Hashable]`：

```
1. [T.Element: Hashable]                       (Conf)
2. [T: Sequence]                               (Conf)
3. [T.[Sequence]Element == T.Element]          (AssocBind 2)
4. [T.[Sequence]Element: Hashable]             (SameConf 1 3)
```

反过来也行：

```
1. [T.[Sequence]Element: Hashable]             (Conf)
2. [T: Sequence]                               (Conf)
3. [T.[Sequence]Element == T.Element]          (AssocBind 2)
4. [T.Element == T.[Sequence]Element]          (Sym 3)
5. [T.Element: Hashable]                       (SameConf 1 4)
```

这就是我们用 `-debug-generic-signatures` 标志测试这个例子时看到的 generic signature 的由来：

```
<T where T: Sequence, T.[Sequence]Element: Hashable>
```

现在注意，第二条 conformance requirement 的 subject type 不只是 bound 的，它还是 **reduced** 的。这提示了一个更强的条件。我们本可以把对 `Hashable` 的 conformance 写成以 `T.Iterator.Element` 为 subject type：

```swift
func uniqueElements2<T: Sequence>(_: T) -> Int
    where T.Iterator.Element: Hashable {}
```

用 `-debug-generic-signatures` 测一下就会看到，`uniqueElements2()` 与 `uniqueElements1()` 有相同的 generic signature。我们从这两条 requirement 出发：

```
{[T: Sequence], [T.Iterator.Element: Hashable]}
```

同样可以证明下面这份列表与它等价：

```
{[T: Sequence],
 [T.[Sequence]Iterator.[IteratorProtocol]Element: Hashable]}
```

然而，由于 `Sequence` 里那条 associated same-type requirement，`T.Iterator.Element` 的 reduced type 就是 `T.[Sequence]Element`，所以我们实际上可以在不改变理论的前提下把第二条 conformance requirement 进一步简化：

```
{[T: Sequence], [T.[Sequence]Element: Hashable]}
```

这就是一份 **reduced** requirement 列表，因为每一条的 subject type 在我们的 generic signature 里都是 reduced type parameter。下面给出 reduced requirement 的一般定义。接下来有一个重要区分：type parameter 之间的 same-type requirement（`[T.A == T.B]`），与右边是 concrete type 的 same-type requirement（`[T.A == Array<T.B>]`）——我们把它们当作本质上两种不同的 requirement 看待。下面这个定义对每种 requirement kind 都直截了当，唯独 type parameter 之间的 same-type requirement 例外。

**定义.** 设 `G` 是一个 generic signature，`R` 是 `G` 的一条 explicit requirement。若下列条件成立，我们称 `R` 是一条 **reduced requirement**：

- 对 **conformance requirement** `[T: P]`：`T` 是 reduced type parameter。
- 对 **layout requirement** `[T: AnyObject]`：`T` 是 reduced type parameter。
- 对 **superclass requirement** `[T: C]`：`T` 和 `C` 都是 reduced type。
- 对 **same-type requirement** `[T == X]`（其中 `X` 是 **concrete type**）：`T` 是 reduced type parameter 且 `X` 是 reduced type。
- 对 **same-type requirement** `[T == U]`（其中 `U` 是 **type parameter**）：

  1. 在 type parameter order 下有 `T < U`。
  2. `T` 要么是 reduced type parameter，要么与 `G` 中另一条（explicit）same-type requirement 的右边完全相同。
  3. `T` 不与 `G` 中任何 same-type requirement 的左边完全相同。
  4. `U` 具备这样的性质：任何满足 `U′ < U` 的推导 `G ⊢ [U′ == U]` 都必须用到 explicit requirement `[T == U]` 本身；也就是说，`U` 无法被 `G` 中任何其它 requirement 进一步 reduce。

对于 type parameter 之间的 same-type requirement，我们不能简单地说两边都是 reduced type parameter，因为那样唯一可能的情况是：对某个 reduced type parameter `T` 有一条平凡的 same-type requirement `[T == T]`。举个例子就清楚了。回忆 `generic-signatures.tex` 的 Valid Type Parameters 一节里那个有趣的 protocol：

```swift
protocol N {
  associatedtype A: N
}
```

现在考虑这两个 generic struct：

```swift
struct Hook1<T, U> where U: N, T == T.A, T.A == U.A {}
struct Hook2<T, U> where U: N, T == T.A, U.A == T {}
```

我们先看 `Hook1`，但会看到两者其实有相同的 generic signature。构建 `Hook1` 的 generic signature 时，我们从这些用户写的 requirement 出发：

```
{[U: N], [T == T.A], [T.A == U.A]}
```

和先前一样，我们推出一份只含 bound dependent member type 的等价列表：

```
{[U: N], [T == T.[N]A], [T.[N]A == U.[N]A]}
```

这份 requirement 列表已经是 reduced 且 minimal 的，于是得到这张 generic signature：

```
<T, U where U: N, T == T.[N]A, T.[N]A == U.[N]A>
```

为更好地理解这张 generic signature，注意我们可以推出 `[T: N]`：

```
1. [U: N]                     (Conf)
2. [U.[N]A: N]                (AssocConf 1)
3. [T.[N]A == U.[N]A]         (Same)
4. [T.[N]A: N]                (SameConf 1 3)
5. [T == T.[N]A]              (Same)
6. [T: N]                     (SameConf 4 5)
```

> 译注：原书第 4 步写的是 `(SameConf 1 3)`。**SameConf** 的两个前提应是 `[U: P]` 与 `[T == U]`；这里与第 3 步 `[T.[N]A == U.[N]A]` 相配的是第 2 步 `[U.[N]A: N]`，而非第 1 步 `[U: N]`。疑为编号笔误，应作 `(SameConf 2 3)`。

`T` 和 `U` 都 conform to `N`，所以各有一个名为 `A` 的成员类型；但由于那些 same-type requirement，这些成员类型都等价于 `T`。于是我们得到这张 type parameter graph：

```
   ┌── .A ──┐
   │        │
   └──→ T ←──────── .A ──────── U
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。图里 `T` 有一条标着 `.A` 的自环（`T.A` 回到 `T` 自己），另有一条从 `U` 指向 `T` 的 `.A` 边（`U.A` 也等价于 `T`）。

接下来看 `Hook2`，它只在第二条 same-type requirement 的写法上不同。我们用 bound dependent member type 写出 `Hook2` 的 requirement：

```
{[U: N], [T == T.[N]A], [U.[N]A == T]}
```

最后一条不是 reduced 的，因为 `U.[N]A > T`。不过我们可以从 `[U.[N]A == T]` 推出 reduced 的那条 `[T.[N]A == U.[N]A]`：

```
1. [U.[N]A == T]              (Same)
2. [T == T.[N]A]              (Same)
3. [U.[N]A == T.[N]A]         (Trans 1 2)
4. [T.[N]A == U.[N]A]         (Sym 3)
```

反过来也行：

```
1. [T.[N]A == U.[N]A]         (Same)
2. [T == T.[N]A]              (Same)
3. [T == U.[N]A]              (Trans 1 2)
4. [U.[N]A == T]              (Sym 3)
```

这说明 `Hook1` 和 `Hook2` 实际上有相同的 minimal generic signature，用 `-debug-generic-signatures` 可以确认这一点。

这个测试用例背后有一小段历史。我们推导 `[T: N]` 时用到了 same-type requirement `[T == T.A]`，它含有 `T` 的一个成员类型。这对 `GenericSignatureBuilder` 来说太难推敲了，所以过去我们只接受 `Hook2` 而不接受 `Hook1`——尽管按 Swift ABI 的规则，`Hook1` 才是 requirement 写成 reduced 形式的那一个。这个 bug 在 Requirement Machine 里得到了修复。

### Minimal requirements

下面是先前那个函数的又一个变体：

```swift
func uniqueElements3<T: Sequence>(_: T) -> Int
    where T.Element: Hashable,
          T.Iterator: IteratorProtocol,
          T.Element: Equatable {}
```

我们得到这份 reduced requirement 列表：

```
{[T: Sequence], [T.[Sequence]Element: Hashable],
 [T.[Sequence]Iterator: IteratorProtocol],
 [T.[Sequence]Element: Equatable]}
```

第三条和第四条没带来任何新东西，因为它们可以从另外两条推导出来。于是 `uniqueElements3()` 与 `uniqueElements1()`、`uniqueElements2()` 有相同的 minimal generic signature。（过去我们会把 redundant requirement 诊断成 warning，但这在 Swift 5.7 里被移除了，所以现在它们就只是被丢掉。）

**定义.** 设 `G` 是一个 generic signature。

- `G` 的一条 explicit requirement `R` 是 **redundant requirement**，如果我们能只用其余的 requirement、不把 `R` 当作基本陈述引用，写出一个推导 `G ⊢ R`。
- 我们称 `G` 是 **minimal** generic signature，如果 `G` 的每条 explicit requirement 都是 reduced 的，且没有任何一条 explicit requirement 是 redundant 的。

下一个例子表明，一份 reduced requirement 列表可能有不止一个**互不相同**的 minimal 子集。我们声明三个只在 conformance requirement 上有差别的 generic struct；读者不妨再用 `-debug-generic-signatures` 试一下：

```swift
struct Knot1<T, U> where T: N, T == U.A,       U == T.A {}
struct Knot2<T, U> where       T == U.A, U: N, U == T.A {}
struct Knot3<T, U> where T: N, T == U.A, U: N, U == T.A {}
```

先看 `Knot1` 的 generic signature。type resolution 为 `Knot1` 产出下面这份用户写的 requirement 列表：

```
{[T: N], [T == U.A], [U == T.A]}
```

对应的 reduced requirement 列表是：

```
{[T: N], [T == U.[N]A], [U == T.[N]A]}
```

这份列表是 minimal 的，于是 `Knot1` 得到下面这张 generic signature：

```
<T, U where T: N, T == U.[N]A, U == T.[N]A>
```

注意我们有一条 explicit requirement `[T: N]`，而且还能推出 `[U: N]`：

```
1. [T: N]                     (Conf)
2. [T.[N]A: N]                (AssocConf 1)
3. [U == T.[N]A]              (Same)
4. [U: N]                     (SameConf 2 3)
```

现在给出 `Knot1` 的 type parameter graph。它的 requirement 看上去和 `Hook1` 相似，因为我们同样有两个各带一个名为 `A` 的成员类型的等价类；但 same-type requirement 的作用方式不同。每个成员类型 `A` 现在都把我们带到**对面**那个等价类：

```
        ──── .A ────→
   T                     U
        ←──── .A ────
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。图里是一对反向的 `.A` 边：`T.A` 等价于 `U`，`U.A` 等价于 `T`。

再看 `Knot2`。这是它的 reduced requirement 列表：

```
{[T == U.[N]A], [U: N], [U == T.[N]A]}
```

这份列表同样是 minimal 的，于是 `Knot2` 得到下面这张 generic signature：

```
<T, U where T == U.[N]A, U: N, U == T.[N]A>
```

在 `Knot2` 里，我们有一条 explicit requirement `[U: N]`，并且能推出 `[T: N]`：

```
1. [U: N]                     (Conf)
2. [U.[N]A: N]                (AssocConf 1)
3. [T == U.[N]A]              (Same)
4. [T: N]                     (SameConf 2 3)
```

我们已经证明 `[T: N]` 和 `[U: N]` 各自在 `Knot1` 和 `Knot2` 里都能推导出来。加上其余 explicit requirement 完全相同，于是我们看到：有两张互不相同的 minimal generic signature 生成了同一个理论。

最后看 `Knot3`。它的 reduced requirement 是：

```
{[T: N], [T == U.[N]A], [U: N], [U == T.[N]A]}
```

与 `Knot1`、`Knot2` 不同，`Knot3` 的 reduced requirement 不是 minimal 的，因为 `[T: N]` 和 `[U: N]` 可以互相推导。遇到这种情况，requirement minimization 倾向于删掉 type parameter order 下 subject type 较大的那条 redundant requirement。

在本例中，这意味着我们先删掉 `[U: N]`。我们推导 `[T: N]` 时用到了 `[U: N]`，所以按上面那条关于等价的命题，我们可以把 explicit requirement `[U: N]` 替换成它的推导，从而得到 `[T: N]` 的一个新推导：

```
1. [T: N]                     (Conf)
2. [T.[N]A: N]                (AssocConf 1)
3. [U == T.[N]A]              (Same)
4. [U: N]                     (SameConf 2 3)
5. [U.[N]A: N]                (AssocConf 4)
6. [T == U.[N]A]              (Same)
7. [T: N]                     (SameConf 5 6)
```

我们已经无法从**其余**的 requirement 推出 `[T: N]` 了，因为上面这个 `[T: N]` 的推导正是以 `[T: N]` 的基本推导步骤开头的。于是，删掉 `[U: N]` 之后，explicit requirement `[T: N]` 不再 redundant，而 `Knot3` 的 generic signature 与 `Knot1` 相同：

```
<T, U where T: N, T == U.[N]A, U == T.[N]A>
```

`Knot2` 与另外两个的 generic signature 不同，这件事其实源自 `GenericSignatureBuilder` 的一个怪癖，而这个行为如今已是 Swift ABI 的一部分。那种能保证唯一性的、更强形式的 requirement minimization，实现起来反而**更简单**。这个历史遗留行为造成的一个小麻烦，会在 `minimization.tex` 的 Conformance Minimization 一节说明。

从理论角度看还有另一个缺点。对 type parameter，我们可以通过比较 reduced type 来检查等价性；但我们无法通过比较 minimal generic signature 来检查两份 requirement 列表是否「理论等价」，因为 minimal generic signature 不唯一。不过实践中似乎没什么地方需要这种等价性检查——这一点和 type parameter 不同，后者的 reduced type equality 检查到处都是。

我们确实维持的那条重要不变量（比如它是让 textual interface 能工作的前提）是**幂等性（idempotence）**：意思是当我们第一次从用户写的 requirement 走到 minimal requirement 时，允许在多个 minimal 子集之间做选择；但若把这份输出拿来**再次**构建一张 generic signature，我们必须得到**同一张** minimal generic signature。这也为 `basic-operation.tex` 里「安装（install）」requirement machine 的那项优化提供了依据。

### Conflicting requirements

上一节我们把 well-formed substitution map 与 well-formed generic signature 两个概念联系了起来：一个 generic signature 要想有任何 well-formed substitution map，必要条件是它本身是 well-formed generic signature。

如果我们把语言限制到只有 conformance requirement 和 type parameter 之间的 same-type requirement 这个子集，那么这个条件也是充分的——也就是说我们能为一个良构的 generic signature 机械地构造出一张 well-formed substitution map。我们先声明一个单一的 concrete nominal type，叫它 struct `S`，并让 `S` conform to 我们的 generic signature `G` 所依赖的每个 protocol `P_i`：

- `P_i` 的任何 method、variable 和 subscript requirement，都可以用调用 `fatalError()` 的桩实现来做 witness。
- `P_i` 的任何 associated type，都可以用 `S` 的 type alias 成员来做 witness，把它们的 underlying type 声明成 `S`。

然后我们构建 `G` 的一张 substitution map：把每个 generic parameter type 替换成 `S`，把每条 conformance requirement 替换成对应的 normal conformance `[S: P_i]`。`G` 的每条 derived requirement，要么对某个 type parameter `T` 和 protocol `P_i` 形如 `[T: P_i]`，要么对一对 type parameter `T` 和 `U` 形如 `[T == U]`。应用我们的 substitution map，总是得到 `[S: P_i]` 或 `[S == S]`，两者无论如何都被满足，所以我们的 substitution map 是 well-formed 的。

一旦加上 superclass、layout 和 concrete same-type requirement，情况就复杂了。当 type parameter 被要求具有特定的 concrete type 时，我们没法把整个 generic signature「坍缩」成一个点。确实，如前所述，**conflicting requirement** 可能导致我们的 generic signature 无法被**任何** substitution map 满足。还有另一重复杂之处：虽然我们能写出涉及这些「奇异」requirement kind 的推导，但某些 inference rule 是缺失的。type substitution 代数会填上其中一部分缺口。

假设 `Σ` 是一张所有 replacement type 都完全具体的 substitution map，于是我们可以把 `Σ` 应用到一条 requirement 上，再用 Check requirement 算法检查它是否被满足。进一步假设我们能推出两条 concrete same-type requirement，它们有相同的 subject type parameter `T`（`T` 属于 `G`）：

```
1. [T == X_1]                 (...)
2. [T == X_2]                 (...)
```

（注意在我们现有的 inference rule 下，每条 requirement 要么是 explicit 的，要么是某个 protocol 的 associated requirement 代换 `Self` 之后的结果；目前没有别的途径去「复合」出 concrete same-type requirement。）我们可以把 `Σ` 应用到这两条 requirement 上，得到一对 substituted requirement：

```
[T ⊗ Σ == X_1 ⊗ Σ]    与    [T ⊗ Σ == X_2 ⊗ Σ]
```

若 `Σ` 是一张 well-formed substitution map，它必须同时满足这两条 substituted requirement；也就是说 `T ⊗ Σ` 必须 canonically 等于 `X_1 ⊗ Σ`，同时 `T ⊗ Σ` 也必须 canonically 等于 `X_2 ⊗ Σ`。而 canonical type equality 是传递的，于是 `X_1 ⊗ Σ` 必须 canonically 等于 `X_2 ⊗ Σ`。

换言之，`Σ` 良构的一个必要条件是：它必须满足 requirement `[X_1 == X_2] ⊗ Σ`。现在，`[X_1 == X_2]` 并不是 `G` 的一条 derived requirement，因为它两边都是 concrete type。不过，若用户直接写下这样一条 requirement，我们知道该怎么办：套用 Desugar same-type requirement 算法。如果在这里照做，每一种可能的结果都会告诉我们关于 `G` 的更多信息：

- 若 `X_1` 与 `X_2` 在脱糖算法所用的意义上不匹配，那就没有任何 substitution map `Σ` 能同时满足 `[T == X_1]` 和 `[T == X_2]`，于是这两条 requirement 相互冲突，`G` 必须被拒绝。

- 否则，我们总能得到一份更简单的 requirement 列表 `{R_1, ..., R_n}`，它具备这样的性质：`Σ` 满足 `[X_1 == X_2]` 当且仅当对所有 `1 ≤ i ≤ n` 都满足 `R_i`。若两条原始 derived requirement 中有一条其实是 `G` 的 explicit requirement，我们就可以把它换成 `{R_1, ..., R_n}`，而不改变这张 generic signature 的「本意」。（不过这**可能**改变理论——但那只是因为我们的理论缺了一些 inference rule，前面已经说过了。）

回忆 `generic-signatures.tex` 里那个关于 concrete type query 的例子。我们声明一个带两个 associated type 的 protocol `Foo`，外加一条 associated same-type requirement `[Self.A == Array<Self.B>]_Foo`：

```swift
protocol Foo {
  associatedtype A where A == Array<B>
  associatedtype B
}
```

现在考虑这个函数：

```swift
func f1<T: Foo>(_: T) where T.A == Array<Int> {}
```

我们能推出两条涉及 `T` 的 concrete same-type requirement：第一条是 explicit 的，第二条是 `Foo` 里那条 associated same-type requirement 的推论：

```
1. [T.A == Array<Int>]                  (Concrete)
2. [T: Foo]                             (Conf)
3. [T.A == Array<T.B>]                  (AssocConcrete 2)
```

按上面的讨论，满足这些 requirement 的 substitution map 还必须满足 `[Array<Int> == Array<T.B>]`，它脱糖成 `[T.B == Int]`。事实上我们可以把那条 explicit same-type requirement 换成这条脱糖后的 requirement，于是最终的 generic signature 是：

```
<T where T: Foo, T.[Foo]B == Int>
```

注意按上面那条关于等价的命题，这两份 requirement 列表**并不**等价，因为我们无法从第一份推出 `[T.B == Int]`；等到 derived requirement 形式体系被彻底补全之后，它们应当变成等价的：

```
{[T: Foo], [T.A == Array<Int>]}
{[T: Foo], [T.B == Int]}
```

接下来我们把例子稍作改动，得到一对 conflicting requirement，可以看到我们诊断出一个 error：

```swift
func f2<T: Foo>(_: T) where T.A == Set<Int> {}

// error: no type for `T.A' can satisfy both `T.A == Set<Int>' and
// `T.A == Array<T.C>'
```

如果**两条** same-type requirement 都是 explicit 的呢？我们换用这个 protocol：

```swift
protocol Foe {
  associatedtype X
  associatedtype Y
}
```

于是可以定义这个函数：

```swift
func f3<T: Foe>(_: T) where T.X == Set<T.Y>, T.A == Set<Int> {}
```

在 `f3()` 里，我们可以把**任意一条** requirement 换成 `[T.X == Int]` 而不改变 generic signature 的「含义」；但由于第一条 requirement 的 subject type 不是 reduced 的，我们先换掉它。于是得到下面这张 generic signature：

```
<T where T: Foe, T.[Foe]X == Set<Int>, T.[Foe]Y == Int>
```

> 译注：这两个例子里原书有几处笔误：`f2` 的错误信息写的是 `T.A == Array<T.C>`，但 `Foo` 只声明了 `A` 和 `B`，按上下文应为 `Array<T.B>`；`f3` 的 `where` 子句第二条写的是 `T.A == Set<Int>`，而 `Foe` 只有 `X` 和 `Y`，按上下文（以及给出的 generic signature）应为 `T.X == Set<Int>`；紧随其后的「换成 `[T.X == Int]`」按最终 signature 应为 `[T.Y == Int]`。照译原文，以上下文与最终 generic signature 为准。

**定义.** 设 `G` 是一个 well-formed generic signature。若 `G` 有一对 derived requirement `R_1` 与 `R_2`，使得对任意 substitution map `Σ`，`R_1 ⊗ Σ` 与 `R_2 ⊗ Σ` 中至少有一条总是不被满足，那么 `R_1` 与 `R_2` 就是 **conflicting requirement**。我们也可以用 requirement desugaring 来刻画 conflicting requirement：

1. 对两条 concrete same-type requirement `[T == X_1]` 和 `[T == X_2]`，我们用 Desugar same-type requirement 算法给「合成」的 requirement `[X_1 == X_2]` 脱糖。脱糖要么检出一个冲突，要么产出一份更简单的 requirement 列表来替换两条原始 requirement 之一，此时我们可以再找一遍冲突。
2. 对一条 concrete same-type requirement `[T == X]` 和一条 superclass requirement `[T: C]`，我们给 `[X: C]` 脱糖。脱糖成功当且仅当 `X` 是一个 class type 且是 `C` 的子类，否则就检出一个冲突。
3. 对一条 same-type requirement `[T == X]` 和一条 layout requirement `[T: AnyObject]`，我们给 `[X: AnyObject]` 脱糖。这成功当且仅当 `X` 是任意一种 class type。
4. 对一条 same-type requirement `[T == X]` 和一条 conformance requirement `[T: P]`，我们给 `[X: P]` 脱糖。这成功当且仅当 `X` conform to `P`。
5. 对两条 superclass requirement `[T: C_1]` 和 `[T: C_2]`，我们必须考察 `C_1` 与 `C_2` 的 declaration 之间的 superclass 关系：

   a. 若 `C_1` 的 class declaration 是 `C_2` 的 declaration 的子类，我们给 `[C_1: C_2]` 脱糖，此时 `[T: C_2]` 变成 redundant。

   b. 若 `C_2` 的 class declaration 是 `C_1` 的 declaration 的子类，我们给 `[C_2: C_1]` 脱糖，此时 `[T: C_1]` 变成 redundant。

   c. 若两个 declaration 彼此无关，我们就有一个冲突。

6. 对一条 superclass requirement `[T: C]` 和一条 layout requirement `[T: AnyObject]`，我们给 `[C: AnyObject]` 脱糖；它恒被满足，不可能冲突。
7. 对一条 superclass requirement `[T: C]` 和一条 conformance requirement `[T: P]`，我们给 `[C: P]` 脱糖。若 `C` conform to `P`，那条 conformance requirement `[T: P]` 变成 redundant。但若 `C` 不 conform to `P`，那也不算冲突；这张 generic signature 只是要求 `T` 是 `C` 的一个**同时还** conform to `P` 的子类。

若 `G` 没有任何一对 conflicting requirement，我们就称它是 **conflict-free** 的。

编译器对 superclass、layout 和 concrete same-type requirement 的实现，要到 `property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)） 里才会细查；本节我们只看几个例子。

下一个例子涉及 superclass requirement。generic class 的完整说明要等到 `substitution-maps.tex` 的 Subclassing 一节，而要演示 requirement minimization 的关键想法，我们只需要非 generic 的 class。既然这已经是个老套路了，我们就随大流用经典的面向对象「形状层次结构」，如下所示：

```
        Shape
        ╱    ╲
  Polygon    Star
     │
  Pentagon
```

> 译注：原书此处是一张 TikZ 图（排在页边的 wrapfigure），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。箭头方向是从超类指向子类。

我们还引入一个 `Canvas` protocol，它给自己的 associated type 加了一条 associated superclass requirement `[Self.Boundary: Polygon]_Canvas`：

```swift
class Shape {}
class Polygon: Shape {}
class Pentagon: Polygon {}
class Star: Shape {}

protocol Canvas {
  associatedtype Boundary: Polygon
}
```

第一个函数给 `C.Boundary` 施加了一个比 conformance requirement `[C: Canvas]` 所蕴含的更宽松的 superclass bound：

```swift
func h1<C: Canvas>(_: C) where C.Boundary: Shape {}
```

因为每个 `Polygon` 也是 `Shape`，requirement `[C.Boundary: Shape]` 是 redundant 的，所以我们只剩下 `[C: Canvas]`。

第二个函数收紧了 `C.Boundary` 的 superclass bound：

```swift
func h2<C: Canvas>(_: C) where C.Boundary: Pentagon {}
```

并非每个 `Polygon` 都是 `Pentagon`，所以 `h2()` 的 minimal generic signature 除了 `[C: Canvas]` 之外还包含 requirement `[C.[Canvas]Boundary: Pentagon]`。

最后，若我们试图施加一个无关的 superclass bound，就会得到一个诊断冲突的 error：

```swift
func h3<C: Canvas>(_: C) where C.Boundary: Star {}

// error: no type for `C.Boundary' can satisfy both `C.Boundary : Star'
// and `C.Boundary : Polygon'
```

最后一个例子考察 conformance requirement 与 concrete same-type requirement 之间的相互作用。考虑 `Box` 的 extension 的 generic signature：

```swift
struct Box<Contents: Sequence> {}
extension Box where Contents == Array<Int> {}
```

要构建这个 extension 的 generic signature，我们取 `Box` 的 generic signature 并加上 requirement `[Contents == Array<Int>]`，于是 requirement minimization 从这份列表开始：

```
{[Contents: Sequence], [Contents == Array<Int>]}
```

按上面那条 conflicting requirement 的定义，我们可以通过给 requirement `[Array<Int>: Sequence]` 脱糖来理解这两条 requirement 之间的相互作用。我们查了一下 conformance，发现这条 requirement 被满足，所以原来那条 `[Contents: Sequence]` 是 redundant 的。剩下的就是 same-type requirement `[Contents == Array<Int>]`，于是这个 extension 的 generic signature 是：

```
<Contents where Contents == Array<Int>>
```

这张 generic signature 显然生成了一个与原来那份（含 `[Contents: Sequence]` 的）requirement 列表不同的、小得多的理论。例如 dependent member type `Contents.Element` 在新的 generic signature 里不是 valid type parameter，正是因为我们推不出 `[Contents: Sequence]`。这又给出一个「requirement minimization 不保持 generic signature 等价性」的例子，原因是我们理论理解上的缺口。

这是 `GenericSignatureBuilder` 那些事后看来略显讨厌的行为之一；如果这里的 conformance requirement 不被当成 redundant，会更好一些。实际后果是：被 extend 的类型的 generic signature 里的某个 valid type parameter，在这个 extension 的 generic signature 里可能就不再 valid 了。`getReducedType()` 这个 generic signature query 的实现为此开了一个特例，通过尝试解析 concrete conformance 来照样放行这类 type parameter（见 `property-map.tex` 的 Generic Signature Queries 一节）。

> 译注：本库在读 extension 容器时同样要面对「这个 extension 的 requirement 到底归属哪条 conformance」的问题，处理方式见 [PerConformanceAttribution.md](../PerConformanceAttribution.md) 与 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)。

### Requirement order

拿到 minimal requirement 之后，最后一步是按 canonical 的方式给它们排序。按下面的定义，这个算法是一个**偏序**，因为它可能返回「`⊥`」；但这只会在两条 requirement 有相同 subject type、相同 kind，且不是 conformance requirement 时发生。对照上面那条 conflicting requirement 的定义可以看出，若两条 minimal requirement 具备这个性质，它们必定冲突。因此，一个 minimal 且 conflict-free 的 generic signature，其 requirement 可以无歧义地线性排序。

**算法（Requirement order）.** 输入两条 requirement，输出「`<`」「`>`」「`=`」「`⊥`」四者之一。

1. （Subject）用 type parameter order 算法（见 `generic-signatures.tex`）比较两条 requirement 的 subject type。若结果是「`<`」或「`>`」，返回该结果。否则两条 requirement 有相同的 subject type。
2. （Kind）比较它们的 kind。若 kind 不同，按下面的相对次序返回「`<`」或「`>`」：

   ```
   superclass < layout < conformance < same-type
   ```

   否则两条 requirement 有相同的 subject type 和相同的 kind。
3. （Protocol）若两者都是 conformance requirement，用 protocol order 算法（见 `generic-signatures.tex`）比较它们的 protocol，返回「`<`」「`=`」「`>`」之一。
4. （Incomparable）否则两条 requirement 有相同的 subject type 和 kind，且都不是 conformance requirement。返回「`⊥`」。

### Requirement signatures

一个 protocol 的 requirement signature 里的 associated requirement，其最小化方式与 generic signature 的 explicit requirement 完全一样。上面那条关于 generic signature 等价的命题，稍作调整就能改用在 requirement signature 上的等价关系来表述。（关键想法是：对 protocol `P` 的每条 associated requirement，我们都能在 protocol generic signature `G_P` 里推出对应的 requirement。）minimal 与 reduced 的 associated requirement 以同样方式定义，而 **requirement signature request** 总是输出一个 **minimal requirement signature**。我们可以用上面那条 conflicting requirement 的定义来描述 associated requirement 之间的冲突，最后用 Requirement order 算法给一个 requirement signature 里的 minimal associated requirement 排序。

主要的区别在于：我们必须把一组相互依赖的 protocol（即一个 **protocol component**）的所有 requirement signature **同时**最小化。这一点会在 `basic-operation.tex` 的 Protocol Components 一节再谈，并在 `minimization.tex` 的 Homotopy Reduction 一节看到一个例子。

## Source Code Reference

### Requests

关键源文件：

- `include/swift/AST/TypeCheckRequests.h`
- `lib/AST/RequirementMachine/RequirementMachineRequests.cpp`

头文件声明这些 request，求值函数则由 Requirement Machine 实现（见 `basic-operation.tex` 的 Source Code Reference 一节）。

**`GenericSignature::class`**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `get()` 是 primitive constructor，直接从一串 generic parameter 和 minimal requirement 构建出 generic signature。

**`GenericSignatureRequest::class`**：`GenericContext::getGenericSignature()` 方法（见 `generic-signatures.tex` 的 Source Code Reference 一节）求值这个 request；它要么返回父声明的 generic signature，要么带上适当的参数去求值 `InferredGenericSignatureRequest`。

**`InferredGenericSignatureRequest::class`**：从源码里写的 requirement 构建 generic signature 的那个 request evaluator request。它的参数在本章开头已经讨论过：

1. 父上下文的 `GenericSignature`（若有）。
2. 当前 generic context 的 `GenericParamList`（若有）。
3. 当前 generic context 的 `WhereClauseOwner`（若有）。
4. 一个存放任何额外要加的 requirement 的 `Requirement` 向量。
5. 一个可用于 requirement inference 的 `TypeLoc` 向量。
6. 一个标志，指示 generic parameter 是否可以受 concrete same-type requirement 约束。

**`WhereClauseOwner::class`**：对依附于某个声明的 `where` clause 的引用。这是 requirement resolution 用的一个包装类型，而 requirement resolution 是 `InferredGenericSignatureRequest` 中构建 generic signature 的第一步。它可以用下面几种东西之一来构造：

- 一个表示 generic declaration 的 `GenericContext`。
- 一个 `AssociatedTypeDecl`——它虽然不是 `GenericContext`，但同样可以带 `where` clause。
- 一个 `GenericParamList`——它只在 textual SIL 里才带 `where` clause。
- 一个表示 `@_specialize` 属性的 `SpecializeAttr`。
- 一个 `TrailingWhereClause` 实例，它是上面若干种东西的原始形式。

有一对方法用于处理 `where` clause 里的 requirement：

- `getRequirements()` 方法返回一个 `RequirementRepr` 数组，即 requirement 的解析后表示。
- `visitRequirements()` 方法接受一个回调和一个 `TypeResolutionStage`。它把每个 `RequirementRepr` 解析成一个 `Requirement`，并把两者一起传给回调。

`InferredGenericSignatureRequest` 和 `RequirementSignatureRequest` 调用 `visitRequirements()` 时传的是 `TypeResolutionStage::Structural`。

随后 `TypeCheckPrimaryFileRequest` 会再访问一遍每个 primary file 里的所有 `where` clause，这次传的是 `TypeResolutionStage::Interface`。我们就是这样诊断 `where` clause 里非法的 dependent member type 的。回忆一下，structural resolution stage 构建的是 unbound dependent member type，并不知道哪些 associated type declaration 是可见的。

**`AbstractGenericSignatureRequest::class`**：从一串 generic parameter 和 requirement 构建 generic signature 的那个 request evaluator request。结果是一个二元组：一张 generic signature 加一些 error flag。大多数调用方并不关心这些 error flag，所以它们改用下面这个函数。

**`buildGenericSignature()::function`**：包装 `AbstractGenericSignatureRequest` 的工具函数。它检查并丢弃返回的 error flag。若 `CompletionFailed` flag 被置位，它会中止编译器。另外两个 flag 被忽略。

**`GenericSignatureErrorFlags::enum class`**：`AbstractGenericSignatureRequest` 返回的 error flag。我们会在 `basic-operation.tex` 里再次遇到这些状况；它们会阻止这张 signature 的 requirement machine 被**安装**。

- `HasInvalidRequirements`：原始 requirement 不是 well-formed 的，或者彼此冲突。交给这个 request 的 requirement 中出现的任何错误，通常都意味着别处已经诊断过另一个错误（比如一个非法的 conformance），所以这个 flag 被置位对编译器的其余部分来说其实没什么可做的。由于缺少 source location 信息，这个错误也无法以友好的方式诊断出来。
- `HasConcreteConformances`：这张 generic signature 有非 redundant 的 concrete conformance requirement。这是一个内部 flag，用于阻止 requirement machine 被安装，它并不向调用方指示错误状态。讨论见 `minimization.tex` 的 Concrete Contraction 一节。
- `CompletionFailed`：completion 过程未能在最大步数内构造出一个 convergent rewriting system（见 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 里 Knuth-Bendix completion procedure 算法之后紧接着的那段关于 termination 的讨论）。这实际上是致命的，所以 `buildGenericSignature()` 这个包装函数在这种情况下会中止编译器。

**`RequirementSignature::class`**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `get()` 是 primitive constructor，直接从一串 minimal requirement 和 protocol type alias 构建出 requirement signature。

**`RequirementSignatureRequest::class`**：`ProtocolDecl::getRequirementSignature()` 方法（见 `generic-signatures.tex` 的 Source Code Reference 一节）求值这个 request；若该 protocol 在 main module 里就计算它的 requirement signature，若来自 serialized module 就反序列化它。

**`StructuralRequirementsRequest::class`**：`ProtocolDecl::getStructuralRequirements()` 方法求值这个 request，用以解析构成该 protocol 的 requirement signature 的那些用户写的 requirement。

**`TypeAliasRequirementsRequest::class`**：`ProtocolDecl::getTypeAliasRequirements()` 方法求值这个 request，用以收集一个 protocol 里的 type alias 声明，并把它们转换成构成该 protocol 的 requirement signature 的 requirement。

### Requirement Resolution

关键源文件：

- `include/swift/AST/Requirement.h`
- `lib/AST/RequirementMachine/RequirementLowering.cpp`

用户写的 requirement 被包进 `StructuralRequirement` 类型，它把一个 `Requirement` 和一个用于诊断的 source location 存在一起。`RequirementLowering.cpp` 里定义了几个构造 `StructuralRequirement` 实例的函数。`InferredGenericSignatureRequest` 直接调用这些函数；`RequirementSignatureRequest` 则委派给 `StructuralRequirementsRequest`，后者用它们来解析写在 protocol 声明里的 requirement。

**`rewriting::realizeRequirement()::function`**：调用 `WhereClauseOwner::visitRequirements()` 方法来解析写在 `where` clause 里的 requirement，并把结果包进 `StructuralRequirement` 实例。

**`rewriting::realizeInheritedRequirements()::function`**：解析一个 type declaration 的 inheritance clause 条目，然后以适当的 subject type 构建出 conformance、superclass 和 layout requirement，并把它们包进 `StructuralRequirement` 实例。

### Requirement Inference

关键源文件：

- `lib/AST/RequirementMachine/RequirementLowering.h`
- `lib/AST/RequirementMachine/RequirementLowering.cpp`

`realizeRequirement()` 和 `realizeInheritedRequirements()` 函数接受一个标志，指示是否应当执行 requirement inference；回忆一下，protocol 里不做 requirement inference，所以 `StructuralRequirementsRequest` 不传这个标志。

**`rewriting::inferRequirements()::function`**：递归遍历一个 `Type`，从其中含有的所有 generic nominal type 和 generic type alias type 构造出 `StructuralRequirement` 实例。

### Requirement Desugaring

关键源文件：

- `lib/AST/RequirementMachine/Diagnostics.h`
- `lib/AST/RequirementMachine/RequirementLowering.h`
- `lib/AST/RequirementMachine/RequirementLowering.cpp`

`realizeRequirement()` 和 `realizeInheritedRequirements()` 函数也执行 requirement desugaring。对 `AbstractGenericSignatureRequest` 而言，requirement desugaring 就是好戏开场的入口：它从一串 requirement 出发，而不是去解析用户写的 requirement representation。

**`rewriting::desugarRequirement()::function`**：建立起 desugared requirement 定义里的那些不变量——拆开 conformance requirement，并简化 subject type 是 concrete type 的 requirement。

**`RequirementError::class`**：表示 requirement desugaring 或 minimization 检出的一条 redundant 或 conflicting requirement。

### Requirement Minimization

关键源文件：

- `lib/AST/GenericSignature.cpp`

正如本章 Requirement Minimization 一节只描述了 minimization 的各项不变量，这里我们也只点出与检查这些不变量相关的代码。minimization 的实际实现见 `minimization.tex` 的 Source Code Reference 一节。

**`Requirement::class`**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `compare()` 实现 requirement order（即 Requirement order 算法），返回下列之一：
  - `-1`，若本 requirement 排在给定 requirement 之前；
  - `0`，若两条 requirement 相等；
  - `1`，若本 requirement 排在右侧那条之后。

  若两条 requirement 不可比，这个方法会 assert；一个例子是两条 superclass requirement 有相同的 subject type。不可比的 requirement 不应该出现在 generic signature 里。

**`GenericSignatureImpl::class`**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `verify()` 确保本 signature 里所有 explicit requirement 都是 desugared（见 desugared requirement 的定义）、reduced（见 reduced requirement 的定义）、minimal（见 minimal generic signature 的定义）且已排序（见 Requirement order 算法）的。任何违反都会报告一个 fatal error，即便在 no-assert 构建里也会让编译器崩溃——因为这样的 generic signature 压根就不该被构建出来。

---

> 译自 `docs/Generics/chapters/building-generic-signatures.tex`（swift-6.4.0-RELEASE，`2349b5f6cf9`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
