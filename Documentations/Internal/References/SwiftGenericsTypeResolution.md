# Type Resolution（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/type-resolution.tex`（《Compiling Swift Generics》一书的「Type Resolution」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `efeab417`，2026-03-22）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章讲编译器怎么把**语法层面**的 type representation（`Array<Int>`、`T.Element` 这种写出来的东西）变成**语义层面**的 type——先 name lookup 找到 type declaration，再按上下文拼一张 substitution map 代进去，最后检查 generic argument 满不满足 requirement。本库走的是同一条路的另一个方向：从 mangled name 出发，按 descriptor 找 metadata accessor、按 requirement 顺序凑 witness table，最终得到一个类型。两边的中间概念（declared interface type、context substitution map、requirement 检查、解析失败的降级）几乎一一对应，所以这一章是读 `MetadataReader` / `RuntimeMetadataTypeBuilder` 那条线最直接的背景材料。
>
> **术语**：书中定义的术语一律保留英文（type representation、type resolution stage、structural / interface resolution stage、unqualified lookup、qualified lookup、declared interface type、context substitution map、protocol substitution map、superclass substitution map、substituted requirement、unbound dependent member type、unbound generic type、placeholder type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Generic Signature Queries 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。`τ_0_0` 是最外层第一个参数，protocol 里的 `Self` 也是它 |
> | `⟦T⟧` | type parameter `T` 的 **primary archetype**（把 interface type 映进 generic environment 之后得到的那种类型） |
> | `X_d` | declaration `d` 的 **declared interface type** |
> | `[T: P]` | conformance requirement，也用来指类型 `T` 对 protocol `P` 的那个 conformance 本身 |
> | `[T: C]` | superclass requirement（`C` 是 class type） |
> | `[T: AnyObject]` | layout requirement |
> | `[T == U]` | same-type requirement |
> | `Σ`、`Σ_a`、`Σ_[T: P]` | substitution map。写成 `{Self ↦ T; [Self: P] ↦ [T: P]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `T` |
> | `R ⊗ Σ` | **requirement substitution**：把 `Σ` 应用到 requirement `R`，得到一条 substituted requirement |
> | `P ⊗ X` | global conformance lookup：查 `X` 对 `P` 的 conformance |
> | `Element ⊗ [X: Sequence]` | type witness projection：从 conformance `[X: Sequence]` 里取 associated type `Element` 的 type witness |
> | `Type(G)`、`Type^ctx(G)` | generic signature `G` 的 interface type 集合、contextual type（archetype）集合 |
> | `Sub(G → H)`、`Sub^ctx(G → H)` | input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 集合（replacement type 分别为 interface type / contextual type） |
> | `Req(G)`、`Req^ctx(G)` | 两边类型都取自 `Type(G)` / `Type^ctx(G)` 的 requirement 全体 |
> | `H ⊢ [T: P]` | requirement `[T: P]` 可从 generic signature `H` 推导出来 |
> | `<<error type>>` | error type，解析失败时返回的那个哨兵类型 |

---

Type resolution 把 parser 产出的语法层面的 **type representation**，变成 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）讲的那些语义层面的 type。Type representation 是树结构。叶子节点是不带 generic argument 的 **identifier type representation**，例如 `Int`。带子节点的包括 **member type representation**，它递归地存着一个 base type representation，例如 `T.Element`。此外还有 function type、metatype、tuple、existential 各自的 type representation；它们都有子节点，形状与对应的 type 一致。最后，identifier 与 member type representation 还可以带上 generic argument 形式的子节点，例如 `Array<Int>`。本章的主要目标之一，就是搞清楚 type resolution 如何从「一个指向 type declaration 的引用」加「一串 generic argument」构造出 generic nominal type。

> 译注：本库做的是反方向的同一件事——从 mangled name 出发，把符号里的那棵树变回具体类型。`MetadataReader` 负责读回来，`RuntimeMetadataTypeBuilder` 负责按 descriptor 找 metadata accessor、按 requirement 顺序凑 witness table，最后拿到一个活的 `Any.Type`。见 [MetadataReaderRefactoring.md](../MetadataReaderRefactoring.md) 与 [MetadataReaderCacheRetirement.md](../MetadataReaderCacheRetirement.md)。

Type resolution 构造 **resolved type** 时，除了看 type representation 本身，还要看描述「这个 type representation 写在哪儿」的上下文信息：

1. Identifier type representation 靠对其 identifier 做 unqualified lookup 来解析；这依赖 type representation 的 source location。例如某个 type representation 可能指向当前 scope 里声明的一个 generic parameter。
2. 某些 type representation 的解析还对**语义位置**敏感。例如出现在参数位置的 function type representation，除非标了 `@escaping`，否则解析成 non-escaping function type；在其它任何位置，function type representation 一律解析成 escaping function type。这个行为是 Swift 3 引入的（SE-0103）。

上下文信息编码在 **type resolution context** 里，包含下面这些：

1. 写下这个 type representation 的那个 **declaration context**。它会传给 identifier type representation 的 unqualified lookup。完整解析 dependent member type 还需要这个 declaration context 的 generic signature。
2. 一个 **type resolution context** 加一组 **type resolution flags**，两者合起来编码这个 type representation 在其 declaration context 内部的语义位置。
3. 一个 **type resolution stage**，它规定 type resolution 能不能查询这个 declaration context 的 generic signature。我们用 type resolution 去**构造** generic signature，而 type resolution 又要用 generic signature 去解析 dependent member type、检查 generic argument。分阶段解析把某些语义检查推迟到 generic signature 可用之后，从而打破这个 request 循环。

两个 type resolution stage 分别是 **structural** resolution stage 和 **interface** resolution stage；我们说「在某个 stage **里**解析一个类型」：

1. Structural resolution stage 不使用当前 declaration context 的 generic signature，因此它不校验 type parameter，也不检查 generic argument。
2. Interface resolution stage 先请求当前 context 的 generic signature，再针对这个 signature 发起 generic signature query 来做语义检查。

**generic signature request** 要从用户写下的 requirement 构造 generic signature，为此它会解析各式各样的 type representation，具体见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）。这件事必须在 structural resolution stage 做。

**interface type request** 在 interface resolution stage 解析 type representation，用语义上良构的类型拼出一个 value declaration 的 interface type。由于它在 interface stage 解析类型，**interface type request** 依赖于 **generic signature request**。

Structural resolution stage 与 interface resolution stage 有两处不同：

- 在 structural resolution stage 里，对 associated type 的引用解析成 **unbound dependent member type**，对无效 member type 的引用不报诊断。这一点在本章 Member Type Representations 一节展开。
- 在 structural resolution stage 里，不检查 generic argument 是否满足 generic nominal type 的 requirement。检查 generic argument 的办法在本章 Generic Arguments 一节讲。

泛型实现「下游」的所有 type resolution 调用都必须用 interface resolution stage，以免放进无效类型。至于那些在 structural stage 解析过的 type representation——尤其是 generic declaration 的 inheritance clause 和 trailing `where` clause——要发出完整的诊断，靠的是 **type-check primary file request** 重新走一遍这些 type representation，在 interface resolution stage 再解析一次。

Structural resolution stage 虽然跳过了一部分语义检查，却仍然可能产出诊断；name lookup 可能解析不出某个 identifier，一些较简单的语义不变量也照样强制执行，例如检查 generic argument 的**个数**对不对。正因如此，必须小心：同一个无效的 type representation 在两个 stage 各解析一次时，不能把同一条诊断报两遍。

通行的做法是让每个 type representation 存一个「invalid」标志位；报完错之后，type resolution 置上这个标志位，并返回一个 error type 作为 resolved type。如果一个已标记为无效的 type representation 又被解析一次，type resolution 立刻再返回一个 error type，既不走访这个 type representation，也不发出任何新诊断。一个 type representation 只能从 valid 变成 invalid，永远不会变回去。

## Identifier Type Representations

**identifier type representation** 是单个 identifier，它命名了某个外层 scope 里的一个 type declaration。我们从该 type representation 的 source location 出发，用 unqualified lookup 找到 **resolved type declaration**（见 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）的 Name Lookup 一节）。然后构造 resolved type：随 type declaration 的种类不同，它会是 nominal type、type alias type、generic parameter type 或 dependent member type。下面先看几个例子，再讲一般原理。

> 译注：本库也有一套「按名字找类型」的机制，只不过找的是 Mach-O 镜像里的 type descriptor：先在根镜像的 `__swift5_types` 里找，miss 了再按依赖闭包的广度优先顺序逐个镜像折进来。规则见 [MachODependencies.md](../Modules/MachODependencies.md) 与 [StaticLayoutDependencyClosure.md](../StaticLayoutDependencyClosure.md)。

### Nominal types.

一个顶层的非 generic **nominal type declaration** 只声明一个类型，我们在 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）里把它叫做 declared interface type。下面这个 type representation 解析成标准库声明的 struct type `Int`：

```swift
var x: Int = ...
```

如果一个 nominal type declaration 带 generic parameter list，那它对每一种可能的 generic argument 列表都声明出一个新类型。identifier 和 member type representation 都可以带一串 generic argument；generic argument 怎么施加、怎么检查，见本章 Generic Arguments 一节。

当 resolved type declaration 的 generic parameter 在该 type representation 的词法作用域里可见时，我们允许省略 generic argument；此时 resolved type 的 generic **argument** 就取 resolved type declaration 的 generic **parameter**。换句话说，resolved type 就是这个 nominal type declaration 的 declared interface type，不附加任何 substitution map。例如：

```swift
struct Outer<T> {
  // Interface type of `x' is `Optional<Outer<T>.Inner>'
  var x: Inner?

  class Inner {
    // Interface type of `y' is `Outer<T>'
    var y: Outer
  }

  struct GenericInner<U> {
    // Return type of `f' is `Outer<T>.GenericInner<U>'
    func f() -> GenericInner {}
  }
}
```

本章 Unbound Generic Types 一节会讲另一种可以省略 generic argument 来引用 generic nominal type 的特殊情形。

回忆 `compilation-model.tex` 的 Name Lookup 一节和 `declarations.tex`：unqualified lookup 依次走访每一层外层 scope，若该 scope 是一个 nominal type declaration，我们就以这个 nominal type 为 base type 尝试一次 qualified lookup。如果这个 base type 是 class type，qualified lookup 还会沿 superclass 继承链往上走。

于是，我们的 identifier type representation 有可能指向某个外层 nominal type declaration 的 superclass 的 member type。这种情况下，declared interface type 会用到当前 scope 里不可见的 type parameter。要得到最终的 resolved type，我们要对 declared interface type 应用一张 substitution map。

如果我们找到的是 base type 的直接 superclass 的成员，就用 superclass type 的 context substitution map。（一般情形用 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Subclassing 一节里的 Get superclass type for declaration 算法。）下面这个例子里，在 `Derived` 内部对 `Inner` 做 unqualified lookup，找到的是 `Base` 的成员。`Base` 的 generic parameter `T` 在 `Derived` 里恒为 `Int`，所以从 `Derived` 看 `Base` 的成员时要应用的那张 superclass substitution map 是 `{T ↦ Int}`：

```swift
class Base<T> {
  struct Inner {}
}

class Derived: Base<Int> {
  // Interface type of `x' is `Base<Int>.Inner'
  var x: Inner = ...
}
```

注意 qualified lookup 也会走访所 conform 的 protocol。虽然我们不允许把 nominal type declaration 嵌套进 protocol 及其 extension，但 associated type declaration 和 type alias declaration 是可以这样看到的。下一节讲 member type representation 时会看到这件事怎么用 substitution map 表达。

还有一种可能：protocol 或 protocol extension 对 `Self` 施加了一条 superclass requirement。此时这个 superclass 的成员同样对 unqualified lookup 可见。`Self` 的 superclass bound 不可能牵涉它自己或它的 member type，所以它必然是一个 fully-concrete type。我们于是当作对这个具体类型做了一次 qualified lookup 来处理。接着上面的例子：在 `Self` 继承自 `Derived` 的 protocol `Proto` 的 extension 里，我们可以引用 `Base.Inner`：

```swift
protocol Proto: Derived {}

extension Proto {
  // Return type of `f' is `Base<Int>.Inner'
  func f() -> Inner {}
}
```

### Generic parameters.

只要有任何一层外层 declaration context 带 generic parameter list，unqualified lookup 就能找到其中的 generic parameter declaration。

```swift
struct G<T> {
  func f<U>(...) {
    var x: T = ...    // Canonical type of `x' is τ_0_0
    var y: U = ...    // Canonical type of `y' is τ_1_0
  }
}
```

Resolved type 就是这个 generic parameter declaration 的 declared interface type，也就是对应的那个 generic parameter type。

### The identifier Self.

说到 `Self`：在 protocol 或 protocol extension 内部，它指的是那个名叫 `Self` 的隐式 generic parameter，也就是 `τ_0_0`（见 `declarations.tex` 的 Protocols 一节）。我们像解析任何其它具名 generic parameter 的引用那样解析它：

```swift
protocol Proto {
  // Return type of `f' is the `Self' generic parameter of `Proto'
  func f() -> Self
}
```

在 struct 或 enum 声明（以及它们的 extension）的 source range 内部，`Self` 是这个 nominal type declaration 的 declared interface type 的简写。它根本不是 generic parameter type，而是一个 nominal type，generic 与否都有可能：

```swift
struct Outer<T> {
  // Return type of `f' is `Outer<T>'
  func f() -> Self {}
}
```

在 class 声明（或其 extension）的 source range 内部，`Self` 代表 **dynamic `Self` type**，它把这个 class 的 declared interface type 包在里面：

```swift
extension Outer {
  class InnerClass {
    // Return type of `f' is the dynamic Self type of
    // `Outer<T>.InnerClass'
    func f() -> Self {}
  }
}
```

我们此前在 `types.tex` 的 Special Types 一节描述过 dynamic `Self` type。从历史上看，Swift 起初只在 protocol 里有 `Self`、只在 class 里有 dynamic `Self`，而且后者只能出现在方法的返回类型里。Swift 5.1 允许在更多位置写出 dynamic `Self`，也允许在 struct 和 enum 声明里引用「静态的」`Self`（SE-0068）。

### Type aliases.

Identifier type representation 也可以指向 type alias declaration，这是上面 nominal type declaration 那套行为的推广。同样地，我们取 type alias declaration 的 declared interface type，并可能对它应用一张 substitution map。不同的是：nominal type declaration 的 declared interface type 是一个 nominal type，而 type alias declaration 的 declared interface type 是一个 **type alias type**。这是一种 sugared type，canonically 等于该 type alias declaration 的 underlying type。

如果被命名的 type alias declaration 处在 local context 里，resolved type 就是它的 declared interface type，不施加任何 substitution map：

```swift
func f<T>() {
  typealias A = (Int, T)

  // Interface type of `a' is canonically equal to `(Int, T)'
  let a: A = ...
}
```

如果 resolved type alias declaration 是某个外层 type declaration 的 superclass 的成员，我们就必须应用一张 substitution map，跟解析 superclass 里找到的 nominal type时一模一样：

```swift
class Base<T> {
  typealias InnerAlias = T?
}

class Derived: Base<Int> {
  // Return type of `f' is canonically equal to `Optional<Int>'
  func f() -> InnerAlias {}
}
```

正如 `substitution-maps.tex` 的 Nested Nominal Types 一节所说，nominal type declaration 不能作为 protocol 或 protocol extension 的成员，但 type alias declaration 可以。我们把它叫做 **protocol type alias**。在任何 conform 到该 protocol 的 nominal type declaration 的作用域里，unqualified lookup 都能找到这样一个 type alias declaration。下一节讲 member type representation 时再细谈 protocol type alias。

### Associated types.

如果 identifier type representation 位于某个 protocol 或 protocol extension 的 source range 内，该 protocol 的 associated type declaration 对 unqualified lookup 可见。Resolved type 是这个 associated type declaration 的 declared interface type，也就是一个绕着「`Self`」的 dependent member type：

```swift
protocol Pair {
  associatedtype A
  associatedtype B

  // Interface type of `a' is `Self.[P]A'
  var a: A { get }

  // Interface type of `b' is `Self.[P]B'
  var b: B { get }
}
```

Associated type declaration 在该 protocol 的 conforming type 内部同样可见。回忆一下，associated type 可以由 generic parameter、member type declaration 或推断来 witness（见 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Type Witnesses 一节）。当 type witness 是 generic parameter 或 member type 时，unqualified lookup 总会**先**找到那个 witness，再轮到 associated type declaration。但如果 type witness 是推断出来的，unqualified lookup 找到的就是 associated type declaration：

```swift
struct S: Pair {
  // Explicit type witness:
  typealias A = Int

  // Inferred type witness:
  // typealias B = String

  var a: A  // resolved type is canonically equal to `Int'
  var b: String  // `B == String' is inferred from `b'

  // Return type of `f' and `g' is canonically equal to `String'
  func f() -> B {}
  func g() -> B {}
}
```

注意 `f()` 和 `g()` 的返回类型相同，但这两个 type representation 的解析方式略有不同。假设我们先计算 `f()` 的 interface type（另一种顺序也可能出现，取决于程序其余部分怎么组织）。

解析 `f()` 的返回类型时，我们找到 `Pair` 的 associated type declaration `B`。Type resolution 做一次 global conformance lookup 找到 concrete conformance `[S: Pair]`，然后从这个 conformance 里投影出 `B` 的 type witness。这会求值 **type witness request**，而该 request 会在 `S` 内部**合成**出 type alias `B`。`S.B` 的 declared interface type（canonically 等于 `String`）就作为 type witness 返回。

解析 `g()` 的返回类型时，我们找到的是刚刚合成出来的 type alias `S.B`。这说明 associated type inference 对 `S` 的 member lookup table 有副作用，不过它实际上起的是一种惰性缓存的作用：第一次查找触发了这个成员的合成。关于 associated type inference 的更多细节见 `conformances.tex` 的 Associated Type Inference 一节。

### Modules.

**module declaration** 是一种特殊的 type declaration，只能用作 member type representation 的 base。单独写一个 module 名是错误：

```swift
_ = Swift.self  // error: expected module member name after module name
```

当然，`import` 声明后面通常就跟一个光秃秃的 module 名，但它们的解析走的不是 type resolution。

### Summary.

如果 resolved type declaration 处在 local context 里，或者处在某个 source file 的顶层，那 resolved type 就是它的 declared interface type。否则，我们是通过向某个外层 nominal type 或 extension 做 qualified lookup 才找到这个 resolved type declaration 的。这种情况下，resolved type declaration 可能是外层 nominal 的**直接**成员，也可能是某个 superclass 或 protocol 的成员。在直接成员这种情形下，或者我们从一个 protocol 出发、找到另一个 protocol 的成员时，我们同样返回该成员的 declared interface type。其余情况，我们构造一张 output generic signature 为「外层 nominal type 或 extension 的 generic signature」的 substitution map，把它应用到成员的 declared interface type，得到 resolved type：

- **superclass 情形**：取外层 nominal 的 superclass bound 和该成员的 parent class declaration，构造 superclass substitution map。
- **protocol 情形**：取外层 nominal 的 declared interface type 和该成员的 parent protocol，从 conformance 构造 protocol substitution map。（我们前面把这件事描述成「从 conformance 投影一个 type witness」而不是「应用一张 substitution map」；下一节把这些概念进一步统一之后，还会再谈 protocol 情形。）

### Source ranges.

在 scope tree 里，一个 nominal type 或 extension 声明实际上定义了**两个** scope，一个嵌在另一个里面。较小的那个 source range 只包含**声明体**，从「`{`」到「`}`」。较大的那个 source range 从该声明的起始关键字算起（例如「`class`」或「`extension`」），一直到「`}`」。特别地，`where` clause 在较大的 source range 之内、较小的 source range 之外。在 protocol 或 protocol extension 内部，该 protocol 的 associated type 成员（以及 type alias 成员）在两个 scope 里都始终可见：

```swift
// This is OK; `Element' resolves to `Self.[Collection]Element'
extension Collection where Element == Int {...}
```

而在 nominal type declaration 内部，generic parameter declaration 在较大的 scope 里可见，member type 却只有在声明体里才看得到：

```swift
// `A' cannot be referenced here:
struct G<T> where A: Equatable {  
  typealias A = T

  // `A' can be referenced here:
  var a: A = ...
}
```

关于从 protocol context 做 name lookup，此前的讨论见 `declarations.tex` 的 Protocols 一节。

## Member Type Representations

**member type representation** 由一个 **base** type representation 加一个 identifier 组成，在具体语法里用「`.`」连起来。Base 可以是 identifier type representation，也可以递归地是另一个 member type representation。Base 本身也可以带 generic argument。解析 member type representation 的一般过程是这样的：先递归解析 base type representation；然后发起一次 qualified lookup（见 `compilation-model.tex` 的 Name Lookup 一节），在 resolved base type 内部寻找一个叫这个名字的 member type declaration。这样找到 resolved type declaration，再对它应用一张 substitution map 算出 resolved type。

这样得到的 resolved type 包括 nominal type、dependent member type 和 type alias type。下面我们逐一考察各种 base type，描述它们各自的 member type，从而把这些行为分门别类。

### Module base.

当 base 是一个命名 module 的 identifier 时，member type representation 指的是这个 module 里的一个顶层 type declaration：

```swift
var x: Swift.Int = ...
```

能这样被引用的 type declaration，就是那些能出现在 module 顶层的：nominal type 和 type alias。Resolved type 就是该声明的 declared interface type。

### Type parameter base.

正如本章开头所暗示的，base 为 type parameter 时，member type 的解析行为取决于 type resolution stage。我们先讲 interface resolution stage，尽管它在时间上是后发生的，因为它实现的是「完整」行为。

**Interface resolution stage.** 在这个 stage 里，我们相对于当前 declaration context 的 generic signature 来解读这个 type parameter。施加在这个 type parameter 上的 requirement 给出一串 protocol，可能还有一个 superclass bound 或一个具体类型。这些类型的 member type declaration，就是我们这个 type parameter 的 member type declaration。它包括：

1. 所有 conform 的 protocol 里的 associated type declaration。
2. 所有 conform 的 protocol 及其 extension 里的 type alias declaration。
3. 具体 superclass type 的 member type（如果有的话）。
4. 如果这个 type parameter 被一条 same-type requirement 钉死在某个具体类型上，那还包括该具体类型的成员。

我们通过收集 `getRequiredProtocols()`、`getSuperclassBound()` 和 `getConcreteType()` 这三个 generic signature query 的结果（见 `generic-signatures.tex` 的 Generic Signature Queries 一节），得到 qualified lookup 必须进去查的那一串类型。

第一种情形——qualified lookup 找到一个 associated type declaration——极其重要；这正是我们在 type resolution 里递归构造 type parameter 的方式。如果某个 type parameter `T` conform 到一个 protocol，比如说 `Provider`，而这个 protocol 声明了一个 associated type `Entity`，那么解析「`T.Entity`」时，我们会通过向 `Provider` 做 qualified lookup 找到 associated type declaration `Entity`。

```swift
protocol Provider {
  associatedtype Entity
}

struct G<T: Provider> {
  var x: T.Entity = ...
}
```

要从 `Self.[Provider]Entity`（也就是 `Entity` 这个 associated type 的 declared interface type）得到 resolved type `T.[Provider]Entity`，我们必须把 `Self` 换成 `T`。做法是应用 **protocol substitution map**，它用 abstract conformance `[T: Provider]` 满足 protocol generic signature `G_Provider`：

```
Σ_[T: Provider] := {Self ↦ T; [Self: Provider] ↦ [T: Provider]}
```

把 `Σ_[T: Provider]` 应用到 `Self.[Provider]Entity`，就从这个 conformance 里投影出了 type witness，用的是我们已经见过几次的那个等式（例如 `conformances.tex` 的 Abstract Conformances 一节）：

```
Self.[Provider]Entity ⊗ Σ_[T: Provider]
  = Entity ⊗ [Self: Provider] ⊗ Σ_[T: Provider]
  = Entity ⊗ [T: Provider]
  = T.[Provider]Entity
```

第二种情形——在 base 里找到的是一个 protocol type alias——与此密切相关。Resolved type 同样是把 type alias 的 underlying type 里所有出现的 `Self` 换成 member type representation 的 resolved base type 得到的。下面我们把事情稍微搞复杂一点：用 dependent member type `T.Element` 而不是 generic parameter `T` 作为 base type：

```swift
protocol Subscriber {
  associatedtype Parent: Provider
  typealias Content = Self.Parent.Entity  // or just Parent.Entity
}

func process<T: Sequence>(_: T) where T.Element: Subscriber {
  // Interface type of `x' is canonically equal to
  // `T.Element.Parent.Entity'
  let x: T.Element.Content = ...
}
```

上面这个行为可以解释成：把 protocol substitution map 应用到该 type alias declaration 的 declared interface type：

```
Self.[Subscriber]Parent.[Provider]Entity ⊗ Σ_[T.Element: Subscriber]
  = T.[Sequence]Element.[Subscriber]Parent.[Provider]Entity
```

这个例子里 protocol type alias 的 underlying type 是一个 type parameter，但它也可以是一个递归地含有 type parameter 的具体类型。

对 associated type declaration 的引用和对 protocol type alias 的引用，解析规则是同一条：把一张 protocol substitution map 应用到 resolved type declaration 的 declared interface type。我们刚才假定 base type 是 type parameter，所以那张 protocol substitution map 是从一个 abstract conformance 构造的。很快我们会看到，当 base type 是具体类型时，我们照样能引用 associated type declaration 和 protocol type alias，只不过那时 protocol substitution map 是从一个 concrete conformance 构造的。

**Structural resolution stage.** 在讨论受 superclass 或具体类型 requirement 约束的 type parameter base 之前，先花点篇幅说说 structural resolution stage。在 structural resolution stage 里，我们手上没有 generic signature，所以既不能做 generic signature query，也不能做 qualified lookup。取而代之，base 为 type parameter 的 member type representation 一律解析成由 base type 和 identifier 拼出来的 **unbound dependent member type**。首先我们需要一个真正会触发 structural resolution 的例子。拿前面声明过的 `Provider` protocol，写一个带 trailing `where` clause 的函数：

```swift
func f<T: Provider>(_: T) where T.Entity: Equatable {...}
```

**generic signature request** 在 structural resolution stage 解析 type representation `T.Entity`，得到 unbound dependent member type `T.Entity`。我们有两条用户写下的 requirement，用它们来构造 generic signature：

```
{[T: Provider], [T.Entity: Equatable]}
```

Requirement minimization 会把第二条 requirement 改写成含有 bound dependent member type `T.[Provider]Entity` 的那条，于是我们得到下面这个 generic signature：

```
<T where T: Provider, T.[Provider]Entity: Equatable>
```

到这一步 `f()` 已经有了 generic signature，因此函数内部出现的 type representation 就可以在 interface resolution stage 解析了。把使用 unbound dependent member type 的 requirement 改写成使用 bound dependent member type 的 requirement，这件事的完整理据见 `building-generic-signatures.tex` 的 Requirement Minimization 一节。

Bound 与 unbound dependent member type 我们在 `generic-signatures.tex` 的 Bound Type Parameters 一节讨论过。把 structural resolution stage 产出的 unbound dependent member type 转换成 bound dependent member type 的办法是：先检查 `isValidTypeParameter()` 这个 generic signature query，再走 `getReducedType()`。第一步检查是必要的，因为 unbound dependent member type 作为一个纯语法构造，有可能根本没命名任何一个有效的 member type。不过通常的情形是：整个 type representation 会在 interface resolution stage 被重新解析一遍，届时一个无效的 type parameter 会解析成 error type 并报出诊断。特别地，每个声明的 trailing `where` clause 里的 type representation 都会被 **type-check primary file request** 重新走访一遍——它按源码顺序遍历所有顶层声明并发出进一步的诊断。

现在把 `f()` 改一改，加上那条无效的 requirement `[T.Foo: Equatable]`：

```swift
func f<T: Provider>(_: T)
    where T.Entity: Equatable, T.Foo: Equatable {...}
```

这条无效 requirement 会被 requirement minimization 丢掉，**generic signature request** 不报任何诊断。真正报出这个无效 member type representation `T.Foo` 的是 **type-check primary file request**：当我们在 interface resolution stage 重新走访这个 `where` clause 时，qualified lookup 会在 `Provider` 里找不到名叫 `Foo` 的 member type。无效 requirement 如何被诊断，我们会在 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节接着讨论。

接下来看函数 `g()`，它在 trailing `where` clause 里引用了前面见过的 protocol type alias `Content`：

```swift
func g<T: Sequence>(_: T)
    where T.Element: Subscriber, T.Element.Content: Equatable {...}
```

这里我们构造出 requirement `[T.Element.Content: Equatable]`，其 subject type 是 unbound dependent member type `T.Element.Content`。确实，它根本不是一个 type alias type。正如我们在 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Protocol Type Aliases 一节会学到的，protocol type alias 会引入 rewrite rule，而 reduced type 的计算会把这个 unbound dependent member type 替换成该 protocol type alias 的 underlying type。这里我们得到的 generic signature 里，有一条 requirement 的 subject type 相当长：

```
[T.[Sequence]Element.[Subscriber]Parent.[Provider]Entity: Equatable]
```

Type alias 也可以出现在 protocol extension 里。但这样的 alias 不能从那些在 structural resolution stage 解析的位置引用，尤其是 trailing `where` clause。后面会看到，protocol extension 里的 type alias 不定义 rewrite rule，所以上面那种归约做不了。这个情形是事后才被发现的——当这个 type representation 在 interface resolution stage 被重新走访时：

```swift
extension Provider {
  typealias Object = Entity
}

// error: `Object' was defined in extension of protocol `Provider'
// and cannot be referenced from a `where' clause
struct G<T: Provider> where T.Object: Equatable {}
```

**剩下的情形.** 最后收尾这种情况：base 是 type parameter，该 type parameter 受一条具体的 same-type requirement 或 superclass requirement 约束，而 resolved type declaration 是这个具体类型的成员。我们从这个 type declaration 计算 resolved type 的办法，是当作 base type 就是那个具体类型或 superclass bound（而不是用户写下的那个 type parameter）来处理。同样地，如果这个 type representation 还要在 structural resolution stage 解析一遍，各种限制就会冒出来。「concrete contraction」这一趟 pass 让其中一部分情形能正常工作（见 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 的 Concrete Contraction 一节）。

### Concrete base.

现在考虑这样一个 member type representation：它的 base 解析出来不是 type parameter。有意思的可能性只有两种：base type 是 nominal type，或者是 dynamic `Self` type——因为 function type 之类根本没有 member type。（dynamic `Self` type 会被直接拆掉，还原成它底下的 nominal type，于是最内层 class 声明的 member type 可以写成「`Self.Foo`」来引用，这或许比几乎等价的「`Foo`」稍微显式一点。）

和 type parameter 那种情形不同，这里我们不查当前 context 的 generic signature，直接向 base type 做 qualified lookup。当 base 和 member type declaration 都是非 generic 的 nominal type、且 member type 是 base 的直接成员时，resolved type 就是该成员的 declared interface type。成员也可能是在某个 superclass 里找到的，而不是 base 的直接成员。上一节有个几乎一模一样的例子，那里对 `Inner` 的引用是写在 `Derived` 声明体里的 identifier type representation：

```swift
class Base<T> {
  struct Inner {}
}

class Derived: Base<Int> {}

// Interface type of `x' is Base<Int>.Inner
var x: Derived.Inner = ...
```

Superclass 是 generic 的，所以我们对 `Inner` 的 declared interface type 应用 superclass substitution map，得到「作为 `Derived` 的成员的 `Inner`」的 resolved type：

```
Base<T>.Inner ⊗ {T ↦ Int} = Base<Int>.Inner
```

接下来，假设我们想直接把 `Inner` 当作 `Base` 的成员来引用。`Base` 这个 class 是 generic 的，而我们还没讲解析 type representation 时 generic argument 怎么施加，不过先假定我们已经会解析这里的 base type 了：

```swift
var y: Base<String>.Inner = ...
```

给定 generic nominal type `Base<String>`，我们把 `Base<String>` 的 context substitution map 应用到 `Inner` 的 declared interface type，来解析上面写下的 member type representation——之所以能这么做，是因为 `Inner` 与 `Base` 的 generic signature 相同：

```
Base<T>.Inner ⊗ {T ↦ String} = Base<String>.Inner
```

从某种意义上说，上面这些 substitution 都是平凡的，因为被引用的成员是一个 nominal type declaration，算 resolved type 无非就是把 base type 的 generic argument 原样搬过来。然而，当成员是一个 **type alias declaration** 时，我们实际上可以编码出任意的 substitution。每一种 base type 的选择都定义出一张可能的 substitution map，它随后被应用到该 type alias 的 underlying type 上，而 underlying type 可以是其 generic signature 下的任何合法 interface type。我们在 `substitution-maps.tex` 里引入 substitution map 时提到过，解析 type alias 成员的类型正是 substitution map 在语言中自然出现的场合之一。下面就来看几个 type alias 成员的例子。

这个 type alias 可能声明在 base 的一个 constrained extension 里。如果这个 constrained extension 引入了新的 conformance requirement，那么该 type alias declaration 的 underlying type 就可能引用被扩展类型的 generic signature 里没有的新 type parameter。回忆 `Optional` 类型只有一个 generic parameter `Wrapped`，我们声明下面这个 constrained extension：

```swift
extension Optional where Wrapped: Sequence {
  typealias OptionalElement = Optional<Wrapped.Element>
}

// Interface type of `x' is `Optional<Int>'
var x: Optional<Array<Int>>.OptionalElement = ...
```

`Optional<Array<Int>>` 的 context substitution map 是 `{Wrapped ↦ Array<Int>}`，它对这个 constrained extension 的 generic signature 来说不是一张有效的 substitution map，因为 requirement `[Wrapped: Sequence]` 没有对应的 conformance。把这张 substitution map 应用到我们那个 type alias 的 underlying type，会触发 substitution failure 并返回 error type，因为没有这个 conformance 就没法解析 type parameter `Wrapped.[Sequence]Element` 的替换类型：

```
Optional<Wrapped.[Sequence]Element> ⊗ {Wrapped ↦ Array<Int>}
  = <<error type>>
```

正确的做法是：构造 base type 的 context substitution map，但用的是这个 constrained extension 的 generic signature。这会用 global conformance lookup 来解析那个 conformance：

```
Σ := {Wrapped ↦ Array<Int>;
      [Wrapped: Sequence] ↦ [Array<Int>: Sequence]}
```

现在把 `Σ` 应用到我们那个 type alias 的 underlying type，就通过从 conformance 投影 type witness 得到了预期的结果：

```
Optional<Wrapped.[Sequence]Element> ⊗ Σ = Optional<Int>
```

如果换成一个不 conform 到 `Sequence` 的 `Wrapped` 类型，例如 `Optional<Float>.OptionalElement`，我们同样得到 substitution failure，于是 resolved type 变成 error type。下一节会讲这种 type representation 如何被诊断出来。

为了把「base 为具体类型的 member type representation」讲完，最后考虑这种可能：被命名的成员是某个已 conform 的 protocol 里声明的 associated type 或 protocol type alias。解析「base 为 type parameter」的 protocol 成员时，我们用的是由「该 type parameter 对该 protocol 的 abstract conformance」构造出来的 protocol substitution map。Base 为具体类型时做法相同，只是这次 protocol substitution map 是从一个 **concrete** conformance 构造的。

下面这段里，`Tomato` conform 到 `Plant`，所以我们可以把 protocol type alias `Food` 当作 `Tomato` 的成员来访问：

```swift
struct Ketchup {}
struct Pasta<Flavor> {}

protocol Plant {
  associatedtype Sauce
  typealias Food = Pasta<Sauce>
  consuming func process() -> Sauce
}

struct Tomato: Plant {
  consuming func process() -> Ketchup {...}
}

// Interface type of `x' is canonically equal to `Ketchup'
var x: Tomato.Sauce = ...

// Interface type of `y' is canonically equal to `Pasta<Ketchup>'
var y: Tomato.Food = ...
```

先后解析「`x`」和「`y`」的 interface type 时，两次的 resolved type declaration 都是 `Plant` 的成员，所以我们从 normal conformance `[Tomato: Plant]` 构造 protocol substitution map `Σ_[Tomato: Plant]`：

```
Σ_[Tomato: Plant] := {Self ↦ Tomato; [Self: Plant] ↦ [Tomato: Plant]}
```

要解析「`x`」的 interface type，我们把 `Σ_[Tomato: Plant]` 应用到 `Sauce` 的 declared interface type `Self.[Plant]Sauce`。这等价于从这个 conformance 里投影 `Sauce` 的 type witness，得到 resolved type `Ketchup`：

```
Self.[Plant]Sauce ⊗ Σ_[Tomato: Plant]
  = Sauce ⊗ [Self: Plant] ⊗ Σ_[Tomato: Plant]
  = Sauce ⊗ [Tomato: Plant]
  = Ketchup
```

要解析「`y`」的 interface type——那里的 type representation 是 `Tomato.Food`——我们把 `Σ_[Tomato: Plant]` 应用到 `Food` 的 underlying type `Pasta<Self.[Plant]Sauce>`，它会递归地变换其中含有的 type parameter：

```
Pasta<Self.[Plant]Sauce> ⊗ Σ_[Tomato: Plant]
  = Pasta<Ketchup>
```

> 译注：本库把 conformance 归属到具体的 extension 容器、并从 witness 里还原 associated type 的办法，见 [PerConformanceAttribution.md](../PerConformanceAttribution.md) 与 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)；离线场景下从 `__swift5_assocty` 取 type witness 的那条路见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)（`DependentMemberTypeBridge` 一节）。

### Protocol base.

这真的只是一个有趣的边角情形。当一个 protocol type alias 的 underlying type 不依赖 protocol 的 `Self` type 时，它作为 protocol type **本身**的 member type 是可见的。上面那个 `Food` protocol type alias 不能作为 protocol type `Plant` 的成员被引用，因为 `Food` 的 underlying type 含有 `Self`，而 `Plant` 不是 `Self` 的合法替换类型——`Plant` 并不 conform 到 `Plant`！Type resolution 必须拒绝 member type representation「`Plant.Food`」：

```swift
// error: cannot access type alias `Food' from `Plant'; use a
// concrete type or generic parameter base instead
var x: Plant.Food = ...
```

同理，associated type 成员**永远**不能用 protocol base 来引用，比如「`Plant.Sauce`」；它的 declared interface type **总是**含有 `Self`。不过，如果某个 protocol type alias 的 underlying type 不含 `Self`，那这个 type alias 不过是另一个全局可见、不依赖 conformance 的类型的快捷写法。我们允许这样的引用，因为不需要做任何 substitution：

```swift
protocol Pet {
  typealias Age = Int
}

// `Pet.Age' is just another spelling for `Int'
func celebratePetBirthday(_ age: Pet.Age) {}
```

由于 type substitution 的一些特殊之处，本身也是 generic 的 protocol type alias 一律被当作依赖 `Self`，哪怕其 underlying type 并不引用 `Self`，所以它们不能用 protocol base 来引用。（在 structural resolution stage 里，generic type alias 也不能用 type parameter base 来引用。也许最好的办法是干脆别把 generic type alias 塞进 protocol 里。）

### General principle.

设 `H` 是当前 context 的 generic signature，`T` 是我们这个 member type representation 的 resolved base type（由一次递归的 type resolution 调用得到）。我们先看 base type `T` 是什么，再做 qualified lookup：

- 如果 `T` 是 type parameter，我们在「针对 `T` 和 `H` 做 generic signature query 得到的那串 nominal type declaration」里查。
- 如果 `T` 是 nominal type，我们进 `T` 的 nominal type declaration 里查。

如果 qualified lookup 失败，或者找到不止一个 type declaration，我们就报错。否则，设 `d` 是 resolved type declaration，其 declared interface type 为 `X_d`、generic signature 为 `G`。我们构造一张 substitution map `Σ ∈ Sub(G → H)`，再算 `X_d ⊗ Σ` 得到最终的 resolved type。`Σ` 由 base type `T` 和关于 `d` 的 parent context 的信息构造，分三种情形：

- **direct 情形**：`d` 是 `T` 的 nominal type declaration 的直接成员，`Σ` 就是 `T` 的 context substitution map。
- **superclass 情形**：`d` 是 `T` 的某个 superclass 的成员，`Σ` 是由 `T` 和 `d` 的 parent class 构造出的 superclass substitution map。
- **protocol 情形**：`d` 是某个 protocol `P` 的成员——`T` 是具体类型时经由 conformance，`T` 是 type parameter 时经由 protocol inheritance——而 `Σ` 是 `T` 对 `P` 的那个 conformance 的 protocol substitution map `Σ_[T: P]`，该 conformance 由 global conformance lookup 找到。

如果 base type `T` 是一个受具体 same-type requirement 或 superclass requirement 约束的 type parameter，那么在计算上面那个 `Σ` 之前，我们先把 `T` 换成由针对 `H` 的 generic signature query 得到的对应具体类型。

上面三种情形里，`d` 都可能定义在一个施加了更多 conformance requirement 的 constrained extension 里。构造 `Σ` 时，这些额外的 conformance 一律通过 global conformance lookup 解析（见 `conformances.tex` 的 Conformance Lookup 一节）。

这张东西叫做 **context substitution map for a declaration context**（某个 declaration context 的 context substitution map）。这个概念推广了 `substitution-maps.tex` 的 Nominal Types 一节里「某个类型的 context substitution map」——那是类型自身的固有属性，与 declaration context 无关。如果 `T` 是 nominal type 而 `d` 是 `T` 的 nominal type declaration 的直接成员，那么「`T` 对 `d` 的 parent context 的 context substitution map」就等于「`T` 的 context substitution map」。

类型对某个 declaration context 的 context substitution map，在给函数体里的 member reference expression（形如「`foo.bar`」）做类型检查时也会出现。此时 qualified lookup 会找到任何名叫 `bar` 的成员，而不只是 type declaration，而该表达式的类型就是把对应的 context substitution map 应用到 `bar` 的 interface type 算出来的。

### History.

在 Swift Evolution 之前的年代，protocol 里的 associated type declaration 是用 `typealias` 关键字声明的，protocol type alias 并不存在。Swift 2.2 为声明 associated type 引入了单独的 `associatedtype` 关键字，给语言里的 protocol type alias 腾出位置（SE-0011）。Protocol type alias 随后作为 Swift 3 的一部分被引入（SE-0092）。

### Caching the type declaration.

算出 identifier 或 member type representation 的 resolved type 之后，我们把 resolved type declaration 塞回该 type representation 里存着，当作一种缓存。如果这个 type representation 又被解析一次（比如先在 structural stage、后在 interface stage 各一次），我们就跳过 name lookup，直接从存下来的 type declaration 计算 resolved type。这个优化在过去收益更大，那时 type resolution 实际上有**三**个 stage。第三个 stage 负责把 interface type 解析成 archetype，但它后来被 generic environment 上的 **map type into environment** 操作吸收掉了。解析文本形式的 SIL 时我们也会预先填充这个缓存，给某些 type representation 直接指派一个 type declaration。否则 name lookup 找不到这些声明，原因是 SIL 语法的一些古怪之处，这里就不展开了。

## Generic Arguments

Identifier 与 member type representation 都可以配上 generic argument，而每个 generic argument 递归地又是一个 type representation：

```swift
Array<Int>
Dictionary<String, Array<Int>>
Big<Int>.Small<String>
```

要解析一个带 generic argument 的 type representation，我们先用 name lookup 找到 resolved type declaration，然后做几步非 generic 情形里没有的额外工作。设 `d` 是 resolved type declaration，`G` 是 `d` 的 generic signature，`G′` 是 `d` 的 parent context 的 generic signature。如果 parent generic signature `G′` 为空，那我们引用的就是一个顶层 generic declaration，例如 `Array<Int>`。（如果 `G` **也**为空，那 `d` 其实根本不是 generic 的；下面会报错。）注意这里有好几项新的语义检查，每一项都可能报错并返回 error type：

1. 我们检查 `d` 有 generic parameter list，并确认 generic argument 的个数正确。
2. 我们递归解析所有 generic argument 的 type representation，拼出一个 generic argument type 的数组。
3. 我们用这些 generic argument type 为 `G` 构造一张 substitution map `Σ`。
4. 我们检查 `Σ` 满足 `G` 的所有 explicit requirement。
5. 我们计算 substituted type `X_d ⊗ Σ`，其中 `X_d` 是 `d` 的 declared interface type，得到最终的 resolved type。

设 `H` 是这个 type representation 所在的 declaration context 的 generic signature。第 1 步的检查查的是 `d` 的 generic parameter list；它是一个语法构造，描述的是我们在 `declarations.tex` 的 Generic Parameters 一节见过的 `G` 的最内层 generic parameter。这不需要知道 `G` 或 `H`，所以我们在 interface resolution stage 和 structural resolution stage 里都做这项检查。第 4 步的 requirement 检查同时需要 `G` 和 `H` 的知识，所以只在 interface resolution stage 里做。这项检查怎么做本身就是一个话题，我们马上会转向它。

> 译注：本库在代入 generic argument 时也要做同样性质的校验——参数个数、每个参数能不能解析、requirement 满不满足——做法见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)。区别在于：本库拿到的是二进制里已经定好的实参，校验失败时不报错而是就地降级。

我们希望 resolved type 是 `H` 下的一个 interface type，即 `X_d ⊗ Σ ∈ Type(H)`。既然 `X_d ∈ Type(G)`，我们要构造的就是一个 `Σ ∈ Sub(G → H)`。上一节处理的是 `d` 不引入任何新 generic parameter 或 requirement、但可能身处 generic context 的情形。那时 resolved type 是 `X_d ⊗ Σ′`，其中 `Σ′` 是 `T` 相对于 `d` 的 declaration context 的 context substitution map。一般情形下 `Σ′ ∈ Sub(G′ → H)` 而非 `Sub(G → H)`，两者的「差别」在于：`G` 的 substitution map 还必须定下 `d` 的最内层 generic parameter，并 witness 任何新增的 conformance requirement；所以我们在 `Σ′` 的基础上加进第 2 步得到的 generic argument type、并解析它们的 conformance，就构造出了 `Σ ∈ Sub(G → H)`。

说了半天，意思就是：type declaration 的递归嵌套产生了 type representation 的递归嵌套。Type resolution 在每一层嵌套上，通过往上一层的 substitution map 里添加新的 generic argument，构造出该层的 substitution map。

**例.** 假设我们要解析下面「`x`」的 interface type：

```swift
struct Big<T> {
  struct Small<U, V> {}
}

struct From<X: Sequence> {
  var x: Big<X.Iterator>.Small<X.Element, Int> = ...
}
```

为了展示嵌套 type declaration 与 generic parameter depth 之间的联系，我们用 canonical type 来做。我们解析的是 `From` 内部的一个 type representation，而 generic argument 里确实含有 `From` 的 generic signature 的 type parameter，其 canonical 形式是 `<τ_0_0 where τ_0_0: Sequence>`。

我们先解析 base type representation `Big<X.Iterator>`。Resolved type declaration 是 `Big`。由于 `Big` 的 parent context 的 generic signature 为空，`Big` 的 generic parameter 的 canonical type 是 `τ_0_0`。我们从这个 generic argument 构造出 substitution map `{τ_0_0 ↦ τ_0_0.Iterator}`。代入后得到 resolved base type：

```
Big<τ_0_0> ⊗ {τ_0_0 ↦ τ_0_0.Iterator} = Big<τ_0_0.Iterator>
```

接下来，我们向 base type 做 qualified lookup，解析出 member type declaration `Small`。`Small` 的 generic parameter `U` 和 `V` 出现在 depth 1，所以它们声明的 generic parameter type 是 `τ_1_0` 和 `τ_1_1`。我们取 base type 的 context substitution map（刚才看到是 `{τ_0_0 ↦ τ_0_0.Iterator}`），把我们的 generic argument 作为 `τ_1_0` 和 `τ_1_1` 的替换类型插进去：

```
Σ := {τ_0_0 ↦ τ_0_0.Iterator,
      τ_1_0 ↦ τ_0_0.Element,
      τ_1_1 ↦ Int}
```

代入后得到最终的 resolved type：

```
Big<τ_0_0>.Small<τ_1_0, τ_1_1> ⊗ Σ
  = Big<τ_0_0.Iterator>.Small<τ_0_0.Element, Int>
```

注意左边那个 `τ_0_0` 是相对于 resolved type declaration 的 generic signature 来解读的，而右边的 `τ_0_0` 相对的是 `From` 的 generic signature。

### Checking generic arguments.

回到本节开头的第 4 步：我们手上有一张 substitution map `Σ ∈ Sub(G → H)`，要判定 `Σ` 是否满足 `G`（被引用的 type declaration 的 generic signature）的 requirement。我们把 `Σ` 应用到 `G` 的每一条 explicit requirement 上，得到一串 **substituted requirement**。一条 substituted requirement 是一个关于具体类型的断言，非真即假；接下来我们逐条检查它，用 global conformance lookup、canonical type 比较等等，下面会讲。只要有任何一条 substituted requirement 不被满足，我们就报错。检查 substituted requirement 是一项通用操作，不只 type resolution 在用；本节末尾会讨论它的其它应用场景。

我们的 generic argument type 可以含有 `H`（当前 context 的 generic signature）的 type parameter，而检查 substituted requirement 可能引出关于 `H` 的问题。为了不用额外把 `H` 传进去，我们要求 substituted requirement 里的类型改用 **archetype** 来表达（参见 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)） 的 Primary Archetypes 一节温习）。于是我们一开始就把 `Σ` 映进 `H` 的 primary generic environment，此后一律假定 `Σ ∈ Sub^ctx(G → H)`。

**定义.** 我们用 `Req(G)` 记左右两边的类型都含有 `G` 的 type parameter 的 requirement 全体（`G` 的所有 explicit 和 derived requirement 都是 `Req(G)` 的元素，但里面还有多得多的东西）。同样地，用 `Req^ctx(H)` 记那些用 `H` 的 primary archetype 写出来的 requirement。

于是我们把 **requirement substitution** 定义成 `⊗` 的一个新「重载」：

```
Req(G) ⊗ Sub^ctx(G → H) → Req^ctx(H)
```

Requirement substitution 必须按 requirement kind 分别处理，把 `Σ` 应用到给定 requirement `R` 里出现的每一个 type parameter。下面一律用 `T` 表示该 requirement 的 subject type，所以 `T ∈ Type(G)`：

- 对 **conformance requirement** `[T: P]`，我们把 `Σ` 应用到 `T`。Protocol type `P` 保持不变，因为它不含任何 type parameter：

  ```
  [T: P] ⊗ Σ := [(T ⊗ Σ): P]
  ```

- 对 **superclass requirement** `[T: C]`，我们既把 `Σ` 应用到 `T`，也应用到 superclass bound `C`——后者可能是一个含有 `G` 的 type parameter 的 generic class type：

  ```
  [T: C] ⊗ Σ := [(T ⊗ Σ): (C ⊗ Σ)]
  ```

- 对 **same-type requirement** `[T == U]`，我们把 `Σ` 应用到两边；`U` 要么是 type parameter，要么是一个可能含有 `G` 的 type parameter 的具体类型：

  ```
  [T == U] ⊗ Σ := [(T ⊗ Σ) == (U ⊗ Σ)]
  ```

- 对 **layout requirement** `[T: AnyObject]`，我们把 `Σ` 应用到 `T`。右边在 substitution 下不变：

  ```
  [T: AnyObject] ⊗ Σ := [(T ⊗ Σ): AnyObject]
  ```

拿到一条 substituted requirement 之后，就可以检查它是否被满足了。在讲怎么检查之前，先看几个例子来说明下面要做的事。

**例（concat）.** 先看看 type resolution 如何解析 `A` 和 `B` 的 underlying type：

```swift
struct Concat<T: Sequence, U: Sequence> where T.Element == U.Element {}

// (1) all requirements satisfied
typealias A = Concat<String, Substring>

// (2) `T.Element == U.Element' unsatisfied
typealias B = Concat<Array<Int>, Set<String>>
```

解析 type alias `A` 的 underlying type 时，我们构造出这张 substitution map：

```
Σ_a := {τ_0_0 ↦ String,
        τ_0_1 ↦ Substring;
        [τ_0_0: Sequence] ↦ [String: Sequence],
        [τ_0_1: Sequence] ↦ [Substring: Sequence]}
```

我们把 `Σ_a` 应用到 `Concat` 的 generic signature 里的每一条 explicit requirement：

```
[τ_0_0: Sequence] ⊗ Σ_a = [String: Sequence]
[τ_0_1: Sequence] ⊗ Σ_a = [Substring: Sequence]
[τ_0_0.Element == τ_0_1.Element] ⊗ Σ_a = [Character == Character]
```

前两条 substituted requirement 断言它们的 subject type conform 到 `Sequence`。我们可以做一次 global conformance lookup 来检查，两次都返回了有效的 concrete conformance，于是判定两条 requirement 都被满足。最后一条 substituted requirement 断言 `Character` 与 `Character` 是同一个类型，这看起来也是对的。所以 `Σ_a` 满足 `Concat` 的 generic signature，我们成功构造出 resolved type `Concat<String, Substring>`。

解析 type alias `B` 的 underlying type 时，我们发现它是无效的：

```
Σ_b := {τ_0_0 ↦ Array<Int>,
        τ_0_1 ↦ Set<String>;
        [τ_0_0: Sequence] ↦ [Array<Int>: Sequence],
        [τ_0_1: Sequence] ↦ [Set<String>: Sequence]}
```

Substitution map `Σ_b` 不满足那条 same-type requirement，因为 `Array<Int>` 和 `Set<String>` 对 `Sequence` 的 conformance 有不同的 `Element` type witness：

```
[τ_0_0.Element == τ_0_1.Element] ⊗ Σ_b = [Int == String]
```

我们报出这个失败，拒绝 `B` 的声明。

**例.** 还用上面的 `Concat`，但这次在一个 generic context 里带着 generic argument 引用它。设 `G` 是 `Concat` 的 generic signature，`H` 是 `OuterGeneric` 的 generic signature。我们要解析「`x`」的 interface type：

```swift
struct OuterGeneric<C: Collection> {
  var x: Concat<C, C.SubSequence> = ...
}
```

我们把 generic argument 映进 `H` 的 primary generic environment，构造出 `Σ ∈ Sub^ctx(G → H)`：

```
Σ := {τ_0_0 ↦ ⟦C⟧,
      τ_0_1 ↦ ⟦C.SubSequence⟧;
      [τ_0_0: Sequence] ↦ [⟦C⟧: Sequence],
      [τ_0_1: Sequence] ↦ [⟦C.SubSequence⟧: Sequence]}
```

注意原先那几条 requirement 含有 `G` 的 type parameter，而 substitution 之后牵涉的是 `H` 的 primary archetype：

```
[τ_0_0: Sequence] ⊗ Σ = [⟦C⟧: Sequence]
[τ_0_1: Sequence] ⊗ Σ = [⟦C.SubSequence⟧: Sequence]
[τ_0_0.Element == τ_0_1.Element] ⊗ Σ = [⟦C.Element⟧ == ⟦C.Element⟧]
```

前两条 requirement 我们靠对各自的 archetype 做一次 global conformance lookup 来检查。回忆 `archetypes.tex` 的 Local Requirements 一节，这实现为一次针对该 archetype 的 generic signature 的 generic signature query。事实上，从 `Collection` 的 associated requirement `[Self: Sequence]` 和 `[Self.SubSequence: Collection]` 出发，我们可以推导出 `H ⊢ [C: Sequence]` 和 `H ⊢ [C.SubSequence: Sequence]`。Global conformance lookup 成功，输出一对 abstract conformance：

```
Sequence ⊗ ⟦C⟧ = [⟦C⟧: Sequence]
Sequence ⊗ ⟦C.SubSequence⟧ = [⟦C.SubSequence⟧: Sequence]
```

（其实我们也可以对 `Σ` 本身做一次 local conformance lookup 来检查 `Σ` 满足某条 conformance requirement。）

第三条是 same-type requirement，所以我们把 `Σ` 应用到两边；由于两边都是 dependent member type，我们从各自的 abstract conformance 投影一个 type witness：

```
τ_0_0.Element ⊗ Σ = Element ⊗ [⟦C⟧: Sequence]
τ_0_1.Element ⊗ Σ = Element ⊗ [⟦C.SubSequence⟧: Sequence]
```

这两次 type witness projection 构造出 dependent member type `τ_0_0.Element` 和 `τ_0_0.SubSequence.Element`，并把它们映进 `H` 的 generic environment。由于 `H ⊢ [τ_0_0.Element == τ_0_0.SubSequence.Element]`，两者在 `H` 里映到同一个 reduced type，因此也定义同一个 archetype：

```
Element ⊗ [⟦C⟧: Sequence] = ⟦C.Element⟧
Element ⊗ [⟦C.SubSequence⟧: Sequence] = ⟦C.Element⟧
```

我们那条 substituted same-type requirement 的两边 canonically 相等，于是可以断定 `G` 的所有 requirement 都被满足，我们这个 type representation 是有效的。

**算法（Check requirement）.** 输入一条 substituted requirement `R ∈ Req^ctx(H)`，其中 generic signature `H` 并不显式给出；`R` 可以含有 `H` 的 primary archetype，但不能含有 type parameter。若 `R` 被**满足**返回 true，否则返回 false。下面一律用 `X` 表示 `R` 的具体 subject type，所以 `X ∈ Type^ctx(H)`。我们按 requirement kind 分情形处理：

- 对 **conformance requirement** `[X: P]`，我们做 global conformance lookup `P ⊗ X`。有三种可能的结果：

  1. 如果得到一个 abstract conformance，那必然是因为 `X` 是 `H` 的某个 archetype，其 type parameter conform 到 `P`。返回 true。
  2. 如果得到一个 concrete conformance，它可能是 conditional 的（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)） 的 Conditional Conformances 一节）。这些 conditional requirement 同样是 `Req^ctx(H)` 里的 substituted requirement，我们递归调用本算法来检查它们。如果所有 conditional requirement 都被满足（或者压根没有），返回 true。
  3. 如果得到一个无效的 conformance，或者上面那步 conditional requirement 检查失败了，返回 false。

- 对 **superclass requirement** `[X: C]`，按如下步骤处理：

  1. 如果 `X` 是一个与 `C` canonically 相等的 class type，返回 true。
  2. 如果 `X` 和 `C` 是同一个 class declaration 的两个不同的 generic class type，返回 false。
  3. 如果 `X` 没有 superclass type（见 `substitution-maps.tex` 的 Subclassing 一节），返回 false。
  4. 否则，设 `X′` 是 `X` 的 superclass type，对 superclass requirement `[X′: C]` 递归应用本算法。

- 对 **layout requirement** `[X: AnyObject]`，我们检查 `X` 是不是 class type、是不是满足 `AnyObject` layout constraint 的 archetype、或者是不是一个 `@objc` existential；若是则返回 true，否则返回 false。（existential 的表示见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)）。）

- 对 **same-type requirement** `[X == Y]`，我们检查 `X` 与 `Y` 是否 canonically 相等。

### Contextually-generic declarations.

一个带 trailing `where` clause 却没有 generic parameter list 的 type declaration，我们在 `declarations.tex` 的 Requirements 一节把它叫做 **contextually-generic declaration**。处在 constrained extension 里的非 generic 声明在概念上与之类似；constrained extension 见 `extensions.tex` 的 Constrained Extensions 一节。这两种情形里，被引用声明的 generic signature `G` 与其 parent context 的 generic signature `G′` 共享同样的 generic parameter，但 `G` 多了几条 `G′` 里没有的 requirement。虽然这时没有 generic argument 可施加，我们仍然要接着检查 `Σ` 满足 `G` 的 requirement。

**例.** 下面的 `Inner` 演示第一种情形：

```swift
struct Outer<T: Sequence> {
  struct Inner where T.Element == Int {}
}

// all requirements are satisfied
typealias A = Outer<Array<Int>>.Inner

// `T.Element == Int' is unsatisfied
typealias B = Outer<Array<String>>.Inner
```

第二个 type alias `B` 最终是无效的。Base `Outer<Array<String>>` 能顺利解析，但这个 member type representation 失败了，因为下面这条 substituted requirement 不被满足（其中 `Σ` 取 base type 的 context substitution map）：

```
[τ_0_0.Element == Int] ⊗ Σ = [String == Int]
```

**例.** 还剩一个细节要说。用上面那个 concat 例子里的 `Concat` 类型，考虑下面这个 type alias：

```swift
// (3) `T: Sequence' unsatisfied;
// `T.Element == U.Element' substitution failure
typealias C = Concat<Float, Set<Int>>
```

我们得到下面这张 substitution map；注意它含有一个无效的 conformance：

```
Σ := {τ_0_0 ↦ Float,
      τ_0_1 ↦ Set<Int>;
      [τ_0_0: Sequence] ↦ （无效）,
      [τ_0_1: Sequence] ↦ [Set<Int>: Sequence]}
```

我们把这张 substitution map 应用到 generic signature 的每一条 requirement：

```
[τ_0_0: Sequence] ⊗ Σ = [Float: Sequence]
[τ_0_1: Sequence] ⊗ Σ = [Set<Int>: Sequence]
[τ_0_0.Element == τ_0_1.Element] ⊗ Σ = [<<error type>> == Int]
```

第一条 conformance requirement 不被满足，会被报出来。那条 same-type requirement 在 substitution 之后含有 error type，不需要报诊断；事实上，它的失败是第一条 conformance requirement 不被满足的后果。

应用完 substitution map、但还没用上面那个算法检查 substituted requirement 之前，我们先找 error type。Substituted requirement 里出现 error type，说明发生了下面几种问题之一：

1. 某个 generic argument type 含有 error type，意味着 type resolution 早先已经报过错了。
2. 原来的类型是一个 dependent member type，而代入后的 base type 并不 conform 到该 member type 的 protocol。这意味着更早的某条 conformance requirement 没被满足，因此也已经报过了。
3. 一个 normal conformance 的声明本身可能因为某个无效或缺失的 type witness 而含有 error type，这种情况下投影 type witness 就可能输出一个 error type；同样地，我们在检查那个 conformance 时就已经报过错了。

所有这些情形下诊断都已经发出过，所以这条 requirement 本身不需要再报。我们在 `substitution-maps.tex` 里把这个叫做 **substitution failure**。

**算法（Check substitution map）.** 取两个输入：

1. 一张 substitution map `Σ ∈ Sub^ctx(G → H)`。
2. 一个由 `Req(G)` 的元素组成的列表。（检查一个 type representation 的 generic argument 时，这就是 generic signature `G` 的那些 explicit requirement。）

输出一个 **unsatisfied** 列表和一个 **failed** 列表。如果两个输出列表都为空，那么所有输入 requirement 都被 `Σ` 满足。

1. （Setup）初始化两个输出列表，一开始都为空。
2. （Done）如果输入列表为空，返回。
3. （Next）从输入列表里取下一条 requirement `R`，计算 `R ⊗ Σ`。
4. （Failed）如果 `R ⊗ Σ` 含有 error type，把 `R` 挪进 failed 列表。
5. （Check）用 `R ⊗ Σ` 调用上面的 Check requirement 算法。如果该 requirement 不被满足，把 `R` 挪进 unsatisfied 列表。
6. （Loop）回到第 2 步。

> 译注：`opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)） 就是用这个算法去检查 underlying type substitution map 满足 opaque result generic signature 的 requirement 的，见同目录的 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md) 的 Inferring the underlying type 一节。

如果 unsatisfied 列表里有 requirement，type resolution 就在这个 generic type representation 的 source location 上报出一串错误，每条未满足的 requirement 一条。Failed 列表里的 requirement 被丢掉，因为如前所述，另一条诊断已经发出过了。只要有至少一条 requirement 属于 unsatisfied 或 failed，resolved type 就变成 error type；这维持了一个不变量：type resolution 的使用者不会遇到任何不满足 generic requirement 的类型——唯一的重要例外就是 error type 自己！

> 译注：本库遇到解析不出来的东西时走的是同一种取舍：不抛出、不编造，就地降级成一个诚实的标记（`FieldResolution.unknown(...)`、`Field offset: unknown (<reason>)`），并把降级本身作为事件报给宿主，见 [EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)。编译器的 error type 是「已经报过错了，别再报」的哨兵，本库的降级标记是「这里算不出来，原因是 X」的记录，两者扮演的角色相同。

### There's more.

Check substitution map 算法还用在别的地方：

1. 检查 normal conformance `[X_d: P]` 的声明时（其中 `X_d` 是某个 nominal type declaration `d` 的 declared interface type），我们必须判定给定的那组 type witness 是否满足 `P` 的 associated requirement。换句话说，我们取 protocol substitution map `Σ_[T: P]`，把它应用到 `P` 的每一条 associated requirement 上（见 `generic-signatures.tex` 的 Requirement Signatures 一节）。
2. 当一个具体类型 `X` 通过 conditional conformance conform 到 protocol `P` 时，我们检查 `X` 的 context substitution map 是否满足 `[X: P]` 的 conditional requirement。这在 `extensions.tex` 的 Conditional Conformances 一节描述。
3. 一个 conditional conformance 的 conditional requirement 本身，也是在对该 conformance 的声明做类型检查时用同一个算法算出来的。我们问的是：constrained extension 的 generic signature 里，哪些 requirement **不**被被扩展类型的 generic signature 满足。
4. 检查子类的方法是不是超类方法的良构 override 时，问的是子类方法的 generic signature 是否满足超类方法 generic signature 的每一条 requirement（见 `building-generic-signatures.tex`）。

还有两个相关的问题，它们走的是不同的代码路径，但推理 requirement 的方式和上面是一样的：

1. 对一个 generic function 的引用做类型检查时，expression type checker 把 generic requirement 翻译成 constraint；这些 constraint 交给 constraint solver 求解，并为这次调用构造出一张 substitution map。这与 type resolution 里引用一个 generic type declaration 时发生的事情完全类似。
2. Requirement inference 是构造新 generic signature 过程中的一步，它**添加** requirement 以确保某些 substituted requirement 会被满足（见 `building-generic-signatures.tex` 的 Requirement Inference 一节）。

## Unbound Generic Types

我们在 `types.tex` 的 Special Types 一节引入过：**unbound generic type** 表示一个不带 generic argument、指向某个 generic type declaration 的引用，而 **placeholder type** 表示某一个缺失的 generic argument。

只有 type resolution context 允许时，unbound generic type 和 placeholder type 才会出现。这些 context 就是那些「缺失的 generic argument 可以靠别的机制补上」的语法位置，例如靠 expression type checker 推断某个表达式的类型。

下面这些 type resolution context 允许 unbound generic type 或 placeholder type 出现，每种 context 各有自己的处理方式：

1. 带初值表达式的 variable declaration 的类型标注，可以在各种嵌套位置上出现 unbound generic type 或 placeholder type：

   ```swift
   let callback: () -> (Array) = { return [1, 2, 3] }
   let dictionary: Dictionary<Int, _> = { 0: "zero" }
   ```

   缺失的 generic argument 会在计算该 variable declaration 的 interface type 时从初值表达式推断出来。

2. 写在表达式里的类型，例如 metatype 值（`GenericType.self`）、构造器调用的被调方（`GenericType(...)`）、cast 的目标类型（`x as GenericType`）。所有这些情形里，generic argument 都从周围的表达式推断。

3. extension 声明的 extended type 通常就写成一个 unbound generic type：

   ```swift
   struct GenericType<T: Sequence> {...}
   extension GenericType {...}
   ```

   我们在 `extensions.tex` 的 Constrained Extensions 一节会看到，给 extended type 写上 generic argument 也是有意义的，它是一串 same-type requirement 的简写。Placeholder type 不能出现在这里。

4. type alias declaration 的 underlying type 可以含有 unbound generic type（但不能含 placeholder type）。这是「一个转发自己 generic argument 的 generic type alias」的简写，所以在上面 `GenericType` 的前提下，下面两行等价：

   ```swift
   typealias GenericAlias = GenericType
   typealias GenericAlias<T: Sequence> = GenericType<T>
   ```

   如果一个 type alias 的 underlying type 是 unbound generic type，它就不能再有自己的 generic parameter list，反之亦然。此外，只有最外层的那个 type representation 才可以解析成 unbound generic type。所以下面两行都是无效的：

   ```swift
   typealias WrongGenericAlias<T> = GenericType
   typealias WrongFunctionAlias = () -> (GenericType)
   ```

注意前两种 context 允许任何 type representation 解析成 unbound generic type，哪怕它出现在嵌套位置上；而后两种里，只有最顶层的 type representation 才能解析成 unbound generic type。

### A limitation.

Unbound generic type 既可以指向 nominal type declaration，也可以指向 type alias declaration。但是，指向 type alias declaration 的 unbound generic type 不能作为某个 nominal type 的 parent type。不提供 generic argument 就访问一个 generic type alias 的 member type 是错误的——哪怕在同一个位置上，指向 nominal type declaration 的 unbound generic type 是可以出现的：

```swift
struct GenericType<T> {
  struct Nested {
    let value: T
  }
}

typealias GenericAlias = GenericType

_ = GenericType.Nested(value: 123)        // OK
_ = GenericAlias<Int>.Nested(value: 123)  // OK

_ = GenericAlias.Nested(value: 123)       // error
_ = GenericAlias<Int>.Nested(value: 123)  // OK
```

### A future direction.

如果说 type representation 是语法的、type 是语义的，那 unbound generic type 就卡在一个古怪的中间位置。它们由 type resolution 产出、指向 type declaration，却并不真的活过类型检查。等一切尘埃落定，表达式里的 generic argument 要么被解析出来，要么被换成 error type。我们其实可以把 unbound generic type 从实现里去掉：重做 type resolution，让它接受一个「补上缺失 generic argument」的回调，凡是允许出现 unbound generic type 或 placeholder type 的 context 各自提供自己的回调。例如 expression type checker 提供的回调就返回一个新鲜的 type variable type。这套回调模型今天已经部分实现了，只不过现有的回调全是平凡的；回调的存在只是在告诉 type resolution：这个位置上允许出现 unbound generic type。

## Source Code Reference

关键源文件：

- `include/swift/AST/TypeResolutionStage.h`
- `lib/Sema/TypeCheckType.h`
- `lib/Sema/TypeCheckType.cpp`

Type resolution 的使用者必须先创建一个 `TypeResolutionOptions`，再由它创建一个 `TypeResolution` 实例。后者定义了 `resolveType()` 方法，把一个 `TypeRepr *` 解析成一个 `Type`。我们先从 `TypeResolutionOptions` 及其组成部分 `TypeResolverContext` 和 `TypeResolutionFlags` 讲起。

**`TypeResolutionOptions`（class）**：编码 type resolution 的语义行为，由一个 base context、一个 current context 和一组 flag 组成。Base context 和 context 最初是相同的。当 type resolution 递归进入一个嵌套的 type representation 时，它保留 base context、可能改变 current context，并清掉 `Direct` 标志。于是 base context 编码的是该 type representation 的整体语法位置，而 context 编码的是当前这个 type representation 所扮演的角色。

- `TypeResolutionOptions(TypeResolutionContext)` 用给定的 base context 创建一个新实例，不带任何 flag。
- `getBaseContext()` 返回 base `TypeResolverContext`。
- `getContext()` 返回当前的 `TypeResolverContext`。
- `getFlags()` 返回 `TypeResolutionFlags`。

**`TypeResolverContext`（enum class）**：type resolution context，编码一个 type representation 所处的位置：

- `TypeResolverContext::None`：不需要任何特殊的类型处理。
- `TypeResolverContext::GenericArgument`：generic nominal type 的 generic argument。
- `TypeResolverContext::ProtocolGenericArgument`：parameterized protocol type 的 generic argument。
- `TypeResolverContext::TupleElement`：tuple element type 的元素。
- `TypeResolverContext::AbstractFunctionDecl`：函数声明参数列表的 base context。
- `TypeResolverContext::SubscriptDecl`：subscript 声明参数列表的 base context。
- `TypeResolverContext::ClosureExpr`：闭包表达式参数列表的 base context。
- `TypeResolverContext::FunctionInput`：function type 或函数声明中某个参数的类型。
- `TypeResolverContext::VariadicFunctionInput`：function type 或函数声明中某个 variadic 参数的类型。它与上一条的区别在于，嵌套的 function type 默认变成 `@escaping`。
- `TypeResolverContext::InoutFunctionInput`：function type 或函数声明中某个 `inout` 参数的类型。
- `TypeResolverContext::FunctionResult`：function type 或函数声明的结果类型。
- `TypeResolverContext::PatternBindingDecl`：pattern binding declaration 里某个 pattern 的类型。
- `TypeResolverContext::ForEachStmt`：`for` 语句中某个变量的类型。
- `TypeResolverContext::ExtensionBinding`：extension 声明的 extended type。
- `TypeResolverContext::InExpression`：出现在表达式 context 里的类型。
- `TypeResolverContext::ExplicitCastExpr`：`as` cast 表达式的目标类型。
- `TypeResolverContext::EnumElementDecl`：enum element 参数列表的 base context。
- `TypeResolverContext::EnumPatternPayload`：enum element pattern 的 payload 类型。它会微调 tuple element label 的行为。
- `TypeResolverContext::TypeAliasDecl`：非 generic type alias 的 underlying type。
- `TypeResolverContext::GenericTypeAliasDecl`：generic type alias 的 underlying type。
- `TypeResolverContext::ExistentialConstraint`：existential type 的 constraint type（见 `existential-types.tex`）。
- `TypeResolverContext::GenericRequirement`：`where` clause 里某条 conformance requirement 的 constraint type。
- `TypeResolverContext::SameTypeRequirement`：`where` clause 里某条 same-type requirement 的 subject type 或 constraint type。
- `TypeResolverContext::ProtocolMetatypeBase`：protocol metatype 的 instance type，形如 `P.Protocol`。
- `TypeResolverContext::MetatypeBase`：具体 metatype 的 base type，形如 `T.Type`。
- `TypeResolverContext::ImmediateOptionalTypeArgument`：optional sugared type（形如 `T?`）的 payload 类型。它只用来裁剪一部分诊断。
- `TypeResolverContext::EditorPlaceholderExpr`：editor placeholder 的类型。
- `TypeResolverContext::Inherited`：具体类型的 inheritance clause。
- `TypeResolverContext::GenericParameterInherited`：generic parameter 的 inheritance clause。
- `TypeResolverContext::AssociatedTypeInherited`：associated type 的 inheritance clause。
- `TypeResolverContext::CustomAttr`：引用 property wrapper 或 result builder 的自定义 attribute 的类型。

**`TypeResolutionFlags`（enum class）**：一组用来控制各种边角行为的 flag：

- `TypeResolutionFlags::AllowUnspecifiedTypes`：允许在压根没提供 type representation 的情况下让 type resolution 成功。用在解析那些可以省略的类型标注上，例如 variable declaration 的类型和闭包参数的类型。
- `TypeResolutionFlags::SILType`：用在解析那些可以出现 lowered SIL type（例如 SIL function type）的位置上。
- `TypeResolutionFlags::SILMode`：用在解析那些出现普通 AST type、但写在文本形式 SIL 里的位置上；它启用一些特殊语法，例如表示 dynamic `Self` type 的 `@dynamic_self`。
- `TypeResolutionFlags::FromNonInferredPattern`：解析 pattern binding 里显式写出的类型标注时，压掉「变量绑定的类型被推断成 `()` 或 `Never`」这类警告——那种推断通常意味着程序员写错了，除非类型是显式写出来的。
- `TypeResolutionFlags::Direct`：解析最外层 type representation 时置上，type resolution 递归进子节点时清掉。它允许某些不能嵌套在其它 type representation 里的 type representation 出现，例如 `inout` 参数类型的 `inout T`。
- `TypeResolutionFlags::SilenceDiagnostics`：关掉诊断，type resolution 失败时只返回一个 error type。用在 pattern 解析里——那时还不知道一个 pattern 指的是类型还是别的什么成员。
- `TypeResolutionFlags::AllowModule`：允许只有一个 component 的 identifier type representation 解析成 `ModuleType`，这通常是禁止的。
- `TypeResolutionFlags::AllowUsableFromInline`：让标了 `@usableFromInline` attribute 的 internal type declaration 可见，`@_specialize` attribute 的实现要用它。
- `TypeResolutionFlags::DisallowOpaqueTypes`：阻止 opaque parameter declaration 出现在某些本来允许它的 context 里，例如 parameterized protocol type `any P<some Q>` 的 generic argument。
- `TypeResolutionFlags::Preconcurrency`：解析对标了 `@preconcurrency` attribute 的 type alias 的引用时，把该 type alias 的 underlying type 里出现的 function type 上的 `@Sendable` 和 global actor attribute 剥掉。

> 译注：`some` 在返回位置上被解析成 opaque archetype 的全过程，见同目录的 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)；本库从二进制还原 `some P` 的对应实现见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

**`TypeResolution`（class）**：初始化好 options 之后，使用者必须调用两个工厂方法之一来创建这个类的实例，具体调哪个取决于想要的 type resolution stage。两个方法都接受一个 `DeclContext`、一个 `TypeResolutionOptions`，以及一对用于解析 placeholder type 和 unbound generic type 的回调：

- `forStructural()` 创建一个 structural resolution stage 的 type resolution。
- `forInterface()` 创建一个 interface resolution stage 的 type resolution。

拿到实例之后，主要能做的事当然就是解析类型：

- `resolveType()` 接受一个 `TypeRepr *`，返回一个 `Type`。

这个类的另一种用法，是调用一个静态工具方法：它创建一个 interface resolution stage 的新 type resolution，解析一个 type representation，再把它映进某个 generic environment 得到一个 contextual type。Expression type checker 用它来解析出现在表达式 context 里的类型：

- `resolveContextualType()`

`resolveType()` 的实际实现会用到这些 getter 方法：

- `getDeclContext()` 返回这个 type representation 所在的 declaration context。
- `getASTContext()` 返回全局的 AST context 单例。
- `getStage()` 返回当前的 `TypeResolutionStage`。
- `getOptions()` 返回当前的 `TypeResolutionOptions`。
- `getGenericSignature()` 在 interface resolution stage 下返回当前的 `GenericSignature`。

**`TypeResolutionStage`（enum class）**：编码 type resolution stage：

- `TypeResolutionStage::Structural`
- `TypeResolutionStage::Interface`

**`ResolveTypeRequest`（class）**：`TypeResolution::resolveType()` 这个入口的实现会求值 `ResolveTypeRequest`。这个 request 虽然不缓存，但它借助 request evaluator 基础设施来检测并报告循环的 type resolution。求值函数用一个 visitor 类按 kind 拆解给定的 type representation。

**`TypeResolver`（class）**：一个递归 visitor，是 type resolution 实现的内部构件。这个 visitor 的各个方法实现了每一种 type representation 的 type resolution。

### Type Representations

关键源文件：

- `include/swift/AST/TypeRepr.h`
- `lib/Sema/TypeCheckType.cpp`

**`TypeRepr`（class）**：type representation 的抽象基类。这套类层次的形状与 `TypeBase`、`Decl`、`ProtocolConformance` 等相仿。

Type representation 存着一个 source location 和一个 kind：

- `getLoc()`、`getSourceRange()` 返回这个 type representation 的 source location 和 source range。
- `getKind()` 返回 `TypeReprKind`。

每个 `TypeReprKind` 对应 `TypeRepr` 的一个子类。子类的实例支持通过 `isa<>`、`cast<>` 和 `dyn_cast<>` 这几个模板函数做安全的向下转换：

```cpp
if (auto *indentRepr = dyn_cast<IdentTypeRepr>(typeRepr))
  ...

auto *funcRepr = cast<FunctionTypeRepr>(typeRepr);
...

assert(isa<ArrayTypeRepr>(typeRepr));
```

### Identifier Type Representations

**`DeclRefTypeRepr`（class）**：identifier 与 member type representation 的抽象基类。

- `getNameRef()` 返回那个 identifier。
- `getGenericArgs()` 返回 generic argument 的 type representation 数组（如果写了的话）。

回忆一下，type representation 会缓存 name lookup 找到的 type declaration，以加速「同一个 type representation 被两个 type resolution stage 各解析一次」的情形：

- `getBoundDecl()` 返回缓存的 type declaration。
- `getDeclContext()` 只对第一个 component 有效，返回 unqualified lookup 当初找到该 type declaration 的那个外层 declaration context。
- `setValue()` 记录一个缓存的 type declaration，以及找到它的那个 declaration context。

注意 `getDeclContext()` 不总是等于该 type declaration 自己的 declaration context，因为这个 type declaration 可能是该 declaration context 所 conform 的 protocol 或其 superclass 的成员，是间接够到的。不过，那个 declaration context 始终是该 type representation 所在的某一层外层 declaration context。

**`IdentTypeRepr`（class）**：`DeclRefTypeRepr` 的子类。表示形如 `Int` 或 `Array<Int>` 的东西。

### Unqualified Lookup

关键源文件：

- `lib/Sema/TypeCheckType.cpp`
- `lib/Sema/TypeCheckNameLookup.cpp`

**`resolveTopLevelIdentTypeComponent()`（function）**：解析一个 identifier type representation 的第一个 component。它执行一次 unqualified lookup、对结果消歧、处理 `Self` 引用这个特殊情形、在提供了 generic argument 时施加它们，并报告错误。

**`TypeChecker::lookupUnqualifiedType()`（function）**：对 unqualified lookup 的一层包装，只考虑 type declaration。

**`getSelfTypeKind()`（function）**：判定给定 context 里的 `Self` 指的是最内层的 nominal type declaration、最内层 class 声明的 dynamic `Self` type，还是在这里说出 `Self` 本身就是无效的。

**`resolveTypeDecl()`（function）**：把一个对 type declaration 的 unqualified 引用解析成一个类型。它处理「在某个类型自己的 context 里引用该类型、省略 generic argument 时推定为对应 generic parameter」这一行为，也处理各种边角情形：被引用的 type declaration 是另一个 nominal type（例如 superclass 或所 conform 的 protocol）的嵌套类型，因而需要做 substitution。

### Member Type Representations

**`MemberTypeRepr`（class）**：`DeclRefTypeRepr` 的子类，表示一个 member type representation。

- `getBase()` 返回 base type representation。

### Qualified Lookup

关键源文件：

- `lib/Sema/TypeCheckType.cpp`
- `lib/Sema/TypeCheckNameLookup.cpp`

**`resolveNestedIdentTypeComponent()`（function）**：解析一个 identifier type representation 的后续 component。它执行一次 qualified lookup、对结果消歧、在提供了 generic argument 时施加它们，并报告错误。

**`TypeResolver::resolveDependentMemberType()`（function）**：实现那个特殊行为——type parameter 的 member type 在 structural resolution stage 里直接解析成一个 unbound dependent member type，而在 interface resolution stage 里经由 name lookup 解析成 bound dependent member type 或 type alias type。

**`TypeChecker::lookupMemberType()`（function）**：对 qualified lookup 的一层包装，只考虑 type declaration；当 base type 是具体类型而找到的是一个 associated type declaration 时，它还会解析具体类型的 type witness。

**`TypeChecker::isUnsupportedMemberTypeAccess()`（function）**：判定某次 member type 访问是否无效。这包括那些古怪情形，例如访问一个指向 type alias 的 unbound generic type 的 member type（见本章 Unbound Generic Types 一节），或者在 base type 就是 protocol 本身的情况下访问一个依赖 `Self` 的 protocol type alias（见本章 Member Type Representations 一节）。

### Applying Generic Arguments

- `include/swift/AST/Requirement.h`
- `lib/AST/Requirement.cpp`
- `lib/Sema/TypeCheckGeneric.cpp`

**`applyGenericArguments()`（function）**：给定一个 type declaration 和一串 generic argument，构造出一个 nominal type 或 type alias type。在 interface resolution stage 里，它还会检查这些 generic argument 满足该 type declaration 的 generic signature 的 requirement。

**`TypeResolution::applyUnboundGenericArguments()`（method）**：`applyGenericArguments()` 拆出来的一块，负责从 base type 和 generic argument 构造 substitution map，并检查一个 generic declaration 的 requirement。

**`TypeResolution::checkContextualRequirements()`（method）**：`applyGenericArguments()` 拆出来的一块，负责从 base type 构造 substitution map，并检查 contextually-generic declaration 的 requirement。

**`Requirement`（class）**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。Requirement substitution：

- `subst()` 把一张 substitution map 应用到这条 requirement 上，返回 substituted requirement。

检查 requirement：

- `checkRequirement()` 回答单条 requirement 是否被满足，实现的是上面的 Check requirement 算法。任何 conditional requirement 都通过调用方提供的一个 `SmallVector` 返回，调用方随后必须递归检查这些 requirement。
- `checkRequirements()` 检查一个数组里的每条 requirement；如果其中有的带自己的 conditional requirement，那些也一并检查。当调用方需要检查某个条件却不想发出诊断时，这个方法实现的就是上面的 Check substitution map 算法。例如 `checkConformance()` 就用它来检查 conditional requirement，见 `extensions.tex` 的 Source Code Reference 一节。

**`checkGenericArgumentsForDiagnostics()`（function）**：用 `Requirement::checkRequirement()` 实现 Check substitution map 算法的一个变体，额外记录用于诊断的信息。Type resolution 和 conformance checker 都用它。

---

> 译自 `docs/Generics/chapters/type-resolution.tex`（swift-6.4.0-RELEASE，`efeab4171c3`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
