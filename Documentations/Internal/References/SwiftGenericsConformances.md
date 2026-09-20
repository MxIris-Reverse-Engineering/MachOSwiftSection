# Conformances（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/conformances.tex`（《Compiling Swift Generics》一书的「Conformances」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是本库处理 conformance 的直接依据。编译器写进二进制的 conformance descriptor（`__swift5_proto` 一节）就是本章 normal conformance 的落盘形态，本库按 (target, protocol, where 指纹, retroactive) 把它归属到 extension 容器；本章的 type witness 对应 `__swift5_assocty` 记录，associated conformance 对应 witness table 里的槽位。译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（conformance、normal conformance、specialized conformance、inherited conformance、abstract conformance、self conformance、invalid conformance、conforming type、type witness、value witness、associated conformance、conformance lookup table、global conformance lookup、local conformance lookup、conformance substitution map、output generic signature、root conformance、conformance path、associated type inference、retroactive conformance、protocol substitution map……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Derived Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按内容引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `X_d` | nominal type declaration `d` 的 **declared interface type**（泛型参数原样保留的那个形态，例如 `Array<τ_0_0>`） |
> | `[X_d: P]` | **normal conformance**：`X_d` 对 protocol `P` 的那条实际声明 |
> | `[X: P]` | 类型 `X` 对 `P` 的一条 conformance。`X` 是带具体 generic argument 的类型时它是 **specialized conformance**，是 type parameter 时它是 **abstract conformance** |
> | `[T: P]` | type parameter `T` 对 `P` 的 **abstract conformance**（同一记法也用来写 conformance requirement，两套形式体系在这里是一回事） |
> | `[A == B]`、`[T: C]` | same-type requirement、superclass requirement |
> | `[Self.U: Q]_P` | protocol `P` 的一条 **associated conformance requirement**。原书在 type substitution algebra 里把它写成 `⟨Self.U: Q]`，本译文统一用带下标的方括号形式 |
> | `[Self.Element == Self.Iterator.Element]_Sequence` | 同理，`Sequence` 的一条 associated same-type requirement |
> | `P ⊗ X` | **global conformance lookup**：查 `X` 对 `P` 的 conformance。原书写作 `⟨P] ⊗ X`（`⟨P]` 是 protocol generic signature 的记号） |
> | `A ⊗ [X: P]` | **type witness projection**：从 conformance `[X: P]` 里取 associated type `A` 的 type witness。原书写作 `⟨P\|A ⊗ [X: P]`，`⟨P\|A` 是「`P` 的 associated type declaration `A`」 |
> | `[Self.U: Q]_P ⊗ [X: P]` | **associated conformance projection**：从 `[X: P]` 里取 associated conformance requirement `[Self.U: Q]_P` 的见证 conformance |
> | `X ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `X` |
> | `[X: P] ⊗ Σ` | **conformance substitution**：把 `Σ` 应用到 conformance |
> | `Σ₁ ⊗ Σ₂` | substitution map composition |
> | `Σ` | substitution map，写成 `{τ_0_0 ↦ Int; [τ_0_0: Equatable] ↦ [Int: Equatable]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `Σ_[X: P]` | **protocol substitution map**：`P` 的 protocol generic signature `<Self where Self: P>` 上的 substitution map，由一个 replacement type `X` 与一条 `[X: P]` 组成 |
> | `1_G` | generic signature `G` 的 identity substitution map |
> | `Type(G)` | `G` 的 interface type 全体 |
> | `Sub(G, H)` | input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 全体（样板译文 `SwiftGenericsOpaqueResultTypes.md` 写作 `Sub(G → H)`，是同一个东西） |
> | `Conf(G)` | output generic signature 为 `G` 的 conformance 全体；`Conf_P(G)` 是其中对 `P` 的那些 |
> | `Proto` | 全体 protocol 的集合 |
> | `AssocType_P`、`AssocConf_P` | `P` 的全体 associated type declaration、全体 associated conformance requirement |
> | `G ⊢ [T: P]` | requirement `[T: P]` 可从 generic signature `G` 推出 |
> | `τ_0_0`、`τ_0_1` | depth 0、index 0 / 1 的 generic parameter |
> | `T.[P]A` | **bound dependent member type**：`T` 经 `P` 的 associated type `A` 得到的成员类型 |
> | `∅`、`∪`、`↦`、`⊢`、`∨`、`∧`、`¬` | 空集、并集、映射、可推出、逻辑或、逻辑与、逻辑非 |

---

Conformance 把类型与它所遵循的 protocol 关联起来。更确切地说，一条 **conformance** 描述的是它的 conforming type 如何 **witness**（见证）一个 protocol 的各条 requirement。我们先看 conformance 的表示，再讨论 conformance lookup。最后，由于 conformance 在 type substitution 里也起着重要作用，我们会补上上一章讨论 substitution map 时留下的缺口——说明我们如何用 conformance 来代入 dependent member type。

Conformance 分三种：

1. **concrete conformance** 记录一个 nominal type 遵循某个 protocol。这种情况下我们知道这条 conformance 最初的声明，因而也知道它全部的 witness。
2. **abstract conformance** 记录一个 type parameter 或 archetype 满足某条 conformance requirement，但我们不知道它是「怎样」满足的（见本章 Abstract Conformances 一节）。
3. **invalid conformance** 记录某个类型并不遵循。

Concrete conformance 又进一步分成四种：

1. **normal conformance** 表示一条 conformance 在某个 nominal type 或 extension 上的实际声明。
2. **specialized conformance** 表示一条施加了 substitution map 的 normal conformance（见本章 Conformance Substitution 一节）。
3. **inherited conformance** 表示子类从父类那里继承来的 conformance。
4. **self conformance** 表示一个 existential type 对它自己那个 protocol 的 conformance。这只有在特殊情形下才可能（见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)） 的 Self-Conforming Protocols 一节）。

> 译注：本库读回来的 conformance 只有这里的 normal conformance 一种形态——二进制里的 conformance descriptor 记录的就是「哪个 nominal type 遵循哪个 protocol，以及它的各条 witness」。specialized / inherited / abstract 这三种都是编译期在内存里临时构造的中间结果，不落盘。本库如何把读到的 conformance 归属到 extension 容器，见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

### Normal conformances

在语言层面，一条 normal conformance 是靠在 nominal type 或 extension 的 inheritance clause 里写出 protocol 名字来声明的：

```swift
struct Horse: Animal {...}

struct Cow {...}
extension Cow: Animal {...}
```

当 `X_d` 是 nominal type declaration `d` 的 declared interface type，且 `d` 遵循 `P` 时，我们把这条 normal conformance 记作 `[X_d: P]`。上面我们声明了两条 normal conformance，`[Horse: Animal]` 和 `[Cow: Animal]`。

一条 normal conformance 由下面这些部分构成：

- **conforming type**，即该 nominal type declaration 的 declared interface type。
- 被遵循的 **protocol declaration**。
- 声明这条 normal conformance 的 **conforming context**，要么是 nominal type declaration 本身，要么是它的某个 extension。这是一个 declaration context（见 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)））。
- conforming context 的 **generic signature**。如果 conformance context 是一个 constrained extension，这个 generic signature 会比 nominal type 自己的 generic signature 多出若干 requirement；这时我们说得到的是一条 **conditional conformance**（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)） 的 Conditional Conformances 一节）。
- protocol 声明的每个 associated type 各有一个 **type witness**。它是一个用这条 conformance 的 generic signature 书写的 interface type（见本章 Type Witnesses 一节）。
- protocol 的每条 associated conformance requirement 各有一条 **associated conformance**。它是另一条 conformance，其 subject type 恰如其分。别的用处不说，单是这一点就让我们能从一条对 derived protocol 的 conformance 回溯出同一类型对 base protocol 的 conformance（见本章 Associated Conformances 一节）。
- protocol 的每条 value requirement 各有一个 **value witness**。它是一个 value declaration 引用加上一张 substitution map。这个 value declaration 要么是 conforming nominal type 的成员，要么来自某个 extension、某个 superclass，或某个 protocol extension。

每个 nominal type 和 extension declaration 都有一份 **local conformance** 列表，即写在该声明 inheritance clause 里的那些 normal conformance。在我们的例子里，`[Horse: Animal]` 是 nominal type declaration `Horse` 的一条 local conformance，而 `[Cow: Animal]` 是 `Cow` 那个 extension 的 local conformance。在 SILGen 里，我们为每个 primary file 中每个声明的每条 local conformance 生成一张 witness table。

此外，每个 nominal type declaration 还有一份 **conformance lookup table**。下一节的 global conformance lookup 就是靠它来**找到**一条 conformance 的。我们在这张表里收集 nominal type 本身及其全部 extension 上的 local conformance。在 Swift 里 conformance 是可继承的，所以 class 的 conformance lookup table 还有一个额外行为：它同时收集其 superclass、superclass 的 superclass ……上的所有 conformance。为了保证这样一条从 superclass 继承来的 conformance 有正确的 conforming type，我们需要一点额外的记账工作。

> 译注：本库把「每张 witness table 对应一条 local conformance」这件事反过来用：它从二进制里扫出 conformance descriptor，再按 protocol 与 where 指纹把成员归回到对应的 extension 容器里去，见 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md)。

### Inherited conformances

下面 `Square` 是 `Polygon` 的子类，所以它继承了 normal conformance `[Polygon: Shape]`：

```swift
protocol Shape {}
class Polygon: Shape {}
class Square: Polygon {}
```

在为子类构建 conformance lookup table 时，我们把每条 superclass conformance 包进一个新的 **inherited conformance** 结构里，它由子类类型和 superclass conformance 两部分组成：

```
┌────────────────────────┐        ┌────────────────────────┐
│ inherited conformance  │ ─────→ │ normal conformance     │
│ Square: Shape          │        │ Polygon: Shape         │
└────────────────────────┘        └────────────────────────┘
             │
             ↓
┌────────────────────────┐
│ conforming type        │
│ Square                 │
└────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

我们把这条 inherited conformance 记作 `[Square: Shape]`。它的行为与 superclass conformance `[Polygon: Shape]` 完全一致，只有一点不同：问它的 conforming type 时，拿回来的是 `Square` 而不是 `Polygon`。在下文 `Mid` 那个例子里我们会看到，当 superclass declaration 带 generic parameter 时，还能出现更复杂的行为。

## Conformance Lookup

要找出某个给定类型对某个 protocol 的 conformance，主要机制叫 **global conformance lookup**。我们用分情形讨论来实现它。

**算法（Global conformance lookup）.** 以一个类型 `X` 和一个 protocol `P` 为输入。若存在则输出 conformance `[X: P]`，否则输出 invalid conformance。

- 若 `X` 是某个 nominal type declaration `d` 的 declared interface type：到 `d` 的 conformance lookup table 里找一条 normal 或 inherited conformance，找到就返回，否则返回 invalid conformance。
- 若 `X` 是别的某种 specialized type：先递归地查它的 declared interface type `X_d` 对 `P` 的 conformance，然后把 `X` 的 context substitution map 应用到这条 conformance `[X_d: P]` 上（见本章 Conformance Substitution 一节）。
- 若 `X` 是一个 type parameter：为 `X` 和 `P` 构造 abstract conformance（见本章 Abstract Conformances 一节）。
- 若 `X` 是任何其他种类的类型：返回 invalid conformance。

我们可以用 global conformance lookup 来回答「某个类型到底遵不遵循」这种是非题——做一次查找，看结果是不是 invalid conformance 之外的东西。我们也可以把任何一条有效的 conformance `[X: P]` 拆开，拿回 conforming type `X` 和 protocol `P`。我们用一张 commutative diagram 把这种拆解与 global conformance lookup 联系起来：

```
              look up conformance
       X  ──────────────────────────→  [X: P]
          ←──────────────────────────
              get conforming type
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。这张图断言的是：两个方向互为逆运算——从 `X` 查出 conformance 再取回 conforming type，与从 conformance 取出 `X` 再查一遍，都应该回到出发点。

如果我们从一个类型 `X` 出发，查出对 `P` 的 conformance，再从这条 conformance 里取出 conforming type，我们会得到一个与 `X` canonically equivalent 的类型。（这两个类型可能是不同的指针，因为 conformance lookup 并不总是保留 type sugar。）

反方向要微妙一些。如果我们从一条 conformance `[X: P]` 出发，取出 conforming type `X`，再查 `X` 对 `P` 的 conformance，我们希望找回**同一条** conformance。若这条性质成立，我们就说 global conformance lookup 是 **coherent** 的。我们采取最简单的做法：只在「每一对（类型，protocol）**至多**有一条 conformance」时才承诺 coherence。

### Coherence

当一条 conformance 声明在某个 extension 上时，我们允许被扩展的类型、被遵循的 protocol 和这个 extension 本身分属不同的 module。这有三种可能。第一，我们可以让自己的类型遵循另一个 module 的 protocol：

```swift
struct MyType {...}
extension MyType: Hashable {...}
```

我们也可以让另一个 module 的类型遵循我们自己的 protocol：

```swift
protocol MyProtocol {...}
extension Int: MyProtocol {...}
```

最后，conforming type 和被遵循的 protocol 可以都声明在我们之外的 module 里。这叫做 **retroactive conformance**，自 Swift 6 起编译器会对此告警（SE-0364）：

```swift
extension String.UTF8View: Hashable {...}
// warning: extension declares a conformance of imported type
// `UTF8View' to imported protocol `Hashable'; this will not
// behave correctly if the owners of `Swift' introduce this
// conformance in the future
```

要绕开这条告警，用户必须表明这确实是他们想要的，办法是给这条 conformance 加上 `@retroactive` 属性：

```swift
extension String.UTF8View: @retroactive Hashable {...}
```

使用不当时，retroactive conformance 会造成同一对 conforming type 与 protocol 存在两条 **overlapping** conformance 的局面。这会导致行为不一致。

假设我们在一个公共 module 里声明了具体类型 `MyKey`，然后另外两个 module 都 import 了 `MyKey` 并各自声明了一条 `MyKey` 对 `Hashable` 的 retroactive conformance。如果下游某个 module 把这三个 module 都 import 进来，那么两条 `MyKey` 对 `Hashable` 的 normal conformance 都是可见的。编译器会挑它先找到的那一条，但不同次调用之间这可能并不一致。

在运行期，配上 library evolution，我们会撞上同样的问题。假设某个厂商在一个共享库里发布了 `MyKey`，而第三方在自己的二进制里定义了一条 `MyKey` 对 `Hashable` 的 retroactive conformance。如果厂商随后更新库、把 `MyKey` 对 `Hashable` 的 conformance 加了进去，而客户端没有重新编译就运行自己的二进制，那么两张 witness table 对 Swift runtime 都是可见的。把 `MyKey` 动态转换（dynamic cast）成 `Hashable` 时，可能会用上其中任意一条 conformance 的 witness table。

避免使用 `@retroactive` 基本上能排除这种可能，但并不能彻底堵死，因为与 library evolution 结合时，subclassing 同样能引入 overlapping conformance。假设某个厂商发布了一个共享库，其中声明了一个 open class 和一个 protocol：

```swift
public protocol Crop {}

open class Hay {}
```

客户端可以声明自己的 `Hay` 子类，因为它是 `open` 的。客户端还可以让自己这个 `Hay` 的子类遵循 `Crop`，而无需在 conformance 上写 `@retroactive` 属性，因为 conforming type 就是客户端 module 里的那个子类：

```swift
import Farm

class Alfalfa: Hay {}
extension Alfalfa: Crop {}
```

现在，如果厂商在库的后续版本里又给 `Hay` 加上了对 `Crop` 的 conformance，而客户端没有重新编译就运行自己的二进制，那么客户端二进制在运行期就会观察到两条 overlapping 的 `Alfalfa` 对 `Crop` 的 conformance：一条从 `Hay` 继承而来，一条是 `Alfalfa` 自己的 local conformance。

### Future directions

要把语言实现扩展到「即使存在 overlapping conformance 也能保证正确性」，是一项大工程，因为那需要在编译器和 runtime 里做若干架构级改动。

Global conformance lookup 操作需要一条消歧规则，也许要把额外的 source location 信息考虑进来。编译器里依赖 coherence 的那些部分需要重新设计成「每次查找只做一遍、把结果存下来备用」，而不是随手再查一次、并假定会找到同一条 conformance。

举个例子，当我们解析源码里写出的一个 generic nominal type 时，我们会做一次 global conformance lookup，以确认其 generic argument 满足该 nominal type 的 conformance requirement。如果之后又需要这个 generic nominal type 的 context substitution map，我们目前会再调一次 global conformance lookup，来填充这张 substitution map 里的 conformance。要避开第二次查找，可以改变 generic nominal type 的表示方式——存一张 substitution map，而不是只存 generic argument。

运行期的 dynamic cast 也有类似的挑战。一种可行的设计是把 retroactive conformance 完全排除在 dynamic cast 行为之外。另一种是引入一个新的 runtime 入口点来做 dynamic cast，它把具体化后的 lexical environment 考虑进来，从而让共享库能用自己的私有 conformance，而不改变链接它的那些二进制的行为。

## Conformance Substitution

这一节我们会看到，substitution map 可以应用到 normal、specialized 和 inherited conformance 上。在本章 Abstract Conformances 一节里我们还会把它推广到 abstract conformance。这个操作叫做 **conformance substitution**，与 type substitution 相对应。

开始之前，我们先用 `⊗` 运算符的一种新形式，把 global conformance lookup 纳入 type substitution algebra。给定一个类型 `X` 和一个 protocol `P`，我们把 global conformance lookup 的结果记作 `P ⊗ X`。回忆一下，若 `d` 是一个遵循 `P` 的 nominal type declaration，`X_d` 是 `d` 的 declared interface type，那么上面的 Global conformance lookup 算法输出的是 `X_d` 对 `P` 的 normal conformance：

```
P ⊗ X_d := [X_d: P]
```

### Normal conformances

现在假设 `X` 是一个以 `d` 为声明的 generic nominal type，但 generic argument 是任意的，所以 `X` 未必等于 `X_d`。我们用 type substitution algebra 来算出 `P ⊗ X`。由 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Nominal Types 一节可知，我们可以把 `X` 拆成 declared interface type `X_d` 和一张 substitution map `Σ`——后者叫做 `X` 的 context substitution map。于是有：

```
P ⊗ X = P ⊗ (X_d ⊗ Σ)
```

为了把右边进一步化简，我们要以一种让 `⊗` 成为**结合运算**的方式来定义它。这个假设是合理的，因为我们已经见过 `⊗` 作用在类型和 substitution map 上时是结合的。确实，回忆一下，若 `X` 是类型，`Σ₁`、`Σ₂`、`Σ₃` 是 substitution map，我们证明过下面两式的运算次序无关紧要：

```
X ⊗ (Σ₁ ⊗ Σ₂) = (X ⊗ Σ₁) ⊗ Σ₂
Σ₁ ⊗ (Σ₂ ⊗ Σ₃) = (Σ₁ ⊗ Σ₂) ⊗ Σ₃
```

为了给 global conformance lookup 得到相应的恒等式，我们**定义**：

```
P ⊗ (X_d ⊗ Σ) := (P ⊗ X_d) ⊗ Σ
```

上式里我们已知 `P ⊗ X_d = [X_d: P]` 是 normal conformance，于是现在看出：global conformance lookup 必须把 `X` 的 context substitution map 应用到 normal conformance `[X_d: P]` 上——这正是 Global conformance lookup 算法所做的事：

```
P ⊗ X = [X_d: P] ⊗ Σ
```

当我们把一张非 identity 的 substitution map `Σ` 应用到 normal conformance `[X_d: P]` 上时，我们用 `[X_d: P]` 和 `Σ` 构造出一条 **specialized conformance**。我们把它记作 `[X: P]`，其中 `X = X_d ⊗ Σ`。我们称 `Σ` 为 `[X: P]` 的 **conformance substitution map**。

当 `Σ` 恰好是 conforming context 的 generic signature 的 identity substitution map 时，我们不必构造 specialized conformance，直接返回原来的 normal conformance 就行；也就是 `[X_d: P] ⊗ 1_G := [X_d: P]`。

### Output generic signatures

在往下走之前，我们先引入一个新概念。我们给每条 conformance 关联一个 **output generic signature**：

- normal conformance 的 output generic signature 是 conformance context（nominal type 本身，或某个 extension）的 generic signature。
- specialized conformance 的 output generic signature 是其 conformance substitution map 的 output generic signature。
- inherited conformance 的 output generic signature 是其底下那条 superclass conformance 的 output generic signature。

output generic signature 为 `G` 的 conformance 全体记作 `Conf(G)`。它与 `substitution-maps.tex` 的记法这样对应：上面的定义蕴含着，若 `[X: P] ∈ Conf(G)`，则 `X ∈ Type(G)`。反过来，若某个 `X ∈ Type(G)` 遵循 `P`，那么由 Global conformance lookup 算法的定义，`P ⊗ X ∈ Conf(G)`。

到目前为止我们只见过 substitution map 应用到 normal conformance 上，但很快我们就会推广这一点，对任意 concrete conformance `[X: P] ∈ Conf(G)` 和 substitution map `Σ ∈ Sub(G, H)` 定义出 `[X: P] ⊗ Σ ∈ Conf(H)`。

**例.** 标准库声明了一条 `Array` 对 `Sequence` 的 conformance。如果我们查 `Array<τ_0_0>` 对 `Sequence` 的 conformance，拿回来的就是这条 normal conformance，因为 `Array<τ_0_0>` 正是 `Array` 的 declared interface type：

```
Sequence ⊗ Array<τ_0_0> = [Array<τ_0_0>: Sequence]
```

接下来考虑 `Array<Int>` 如何遵循 `Sequence`。我们注意到：

```
Array<Int> = Array<τ_0_0> ⊗ {τ_0_0 ↦ Int}
```

Global conformance lookup 会把这张 substitution map 应用到那条 normal conformance 上：

```
Sequence ⊗ Array<Int>
    = Sequence ⊗ (Array<τ_0_0> ⊗ {τ_0_0 ↦ Int})
    = (Sequence ⊗ Array<τ_0_0>) ⊗ {τ_0_0 ↦ Int}
    = [Array<τ_0_0>: Sequence] ⊗ {τ_0_0 ↦ Int}
    = [Array<Int>: Sequence]
```

我们把这条 specialized conformance 记作 `[Array<Int>: Sequence]`，但它在内存里的结构长这样：

```
┌────────────────────────────┐        ┌────────────────────────────┐
│ specialized conformance    │ ─────→ │ normal conformance         │
│ Array<Int>: Sequence       │        │ Array<τ_0_0>: Sequence     │
└────────────────────────────┘        └────────────────────────────┘
               │
               ↓
┌────────────────────────────┐
│ substitution map           │
│ τ_0_0 ↦ Int                │
└────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Specialized conformances

现在假设给定一条 specialized conformance `[X_d: P] ⊗ Σ₁ ∈ Conf(H)`，其中 `Σ₁ ∈ Sub(G, H)`，而我们想把另一张 substitution map `Σ₂ ∈ Sub(H, I)` 应用到这条 specialized conformance 上。为此，我们用 `[X_d: P]` 和 `Σ₁ ⊗ Σ₂ ∈ Sub(G, I)` 构造一条新的 specialized conformance，于是 `[X_d: P] ⊗ (Σ₁ ⊗ Σ₂) ∈ Conf(I)`。这把 conformance substitution 与 substitution map composition 联系了起来，也延续了 `⊗` 是结合运算这个一贯的做法：

```
([X_d: P] ⊗ Σ₁) ⊗ Σ₂ := [X_d: P] ⊗ (Σ₁ ⊗ Σ₂)
```

### Inherited conformances

最后，我们可以把 substitution map 应用到 inherited conformance 上。假设 `[C: P]` 是一条 inherited conformance，其 conforming type 为 `C ∈ Type(G)`，superclass conformance 为 `[C': P] ∈ Conf(G)`，其中 `C'` 是 `C` 的一个 superclass type。若 `Σ ∈ Sub(G, H)` 是一张 substitution map，那么 `[C: P] ⊗ Σ ∈ Conf(H)` 就是由 `C ⊗ Σ` 和 `[C': P] ⊗ Σ` 构造出的那条 inherited conformance。

**例.** 考虑下面的 `Mid`，它从 `Top` 继承了对 `P` 的 conformance：

```swift
protocol P {}
class Top<T>: P {}
class Mid<X, Y>: Top<(Y, X)> {}
```

`Mid` 的 superclass type 是 `Top<(τ_0_1, τ_0_0)>`，其 context substitution map 为：

```
Σ₁ := {τ_0_0 ↦ (τ_0_1, τ_0_0)}
```

在构建 `Mid` 的 conformance lookup table 时，我们查 superclass type `Top<(τ_0_1, τ_0_0)>` 对 `P` 的 conformance，拿到一条带上述 substitution map 的 specialized conformance。随后我们把这条 specialized conformance 包进一条 inherited conformance，好给它正确的 conforming type `Mid<τ_0_0, τ_0_1>`。我们把得到的结构记进表里：

```
┌────────────────────────────┐    ┌────────────────────────────────┐    ┌────────────────────────────┐
│ inherited conformance      │ ─→ │ specialized conformance        │ ─→ │ normal conformance         │
│ Top<τ_0_0, τ_0_1>: P       │    │ Top<(τ_0_1, τ_0_0)>: P         │    │ Top<τ_0_0>: P              │
└────────────────────────────┘    └────────────────────────────────┘    └────────────────────────────┘
              │                                   │
              ↓                                   ↓
┌────────────────────────────┐    ┌────────────────────────────────┐
│ conforming type            │    │ substitution map               │
│ Mid<τ_0_0, τ_0_1>          │    │ τ_0_0 ↦ (τ_0_1, τ_0_0)         │
└────────────────────────────┘    └────────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。另外，原书这张图里 inherited conformance 那个方框、以及下文“我们先从 `Mid` 的 conformance lookup table 里找到那条 inherited conformance”一句，写的都是 `Top<τ_0_0, τ_0_1>: P`；但前一句正文明说包这一层就是为了给它正确的 conforming type `Mid<τ_0_0, τ_0_1>`（图下方的 conforming type 方框也写着 `Mid`）。两处相左，疑为原书笔误，应以 `Mid<τ_0_0, τ_0_1>: P` 为准；译文正文保留原书写法。

假设我们向 global conformance lookup 索要 `Mid<Int, Bool>` 对 `P` 的 conformance。我们需要 `Mid<Int, Bool>` 的 context substitution map：

```
Σ₂ := {τ_0_0 ↦ Int, τ_0_1 ↦ Bool}
```

我们先从 `Mid` 的 conformance lookup table 里找到那条 inherited conformance `[Top<τ_0_0, τ_0_1>: P]`，然后把 `Σ₂` 应用上去；这又会把 `Σ₂` 分别应用到它的子类类型 `Mid<τ_0_0, τ_0_1>` 和 specialized conformance `[Top<(τ_0_1, τ_0_0)>: P]` 上。对后者，我们注意到 `Σ₁ ⊗ Σ₂ = {τ_0_0 ↦ (Bool, Int)}`：

```
Mid<τ_0_0, τ_0_1> ⊗ Σ₂ = Mid<Int, Bool>
[Top<(τ_0_1, τ_0_0)>: P] ⊗ Σ₂ = [Top<(Bool, Int)>: P]
```

最终结果是这条相当曲折的 inherited conformance `[Mid<Int, Bool>: P]`：

```
┌────────────────────────────┐    ┌────────────────────────────────┐    ┌────────────────────────────┐
│ inherited conformance      │ ─→ │ specialized conformance        │ ─→ │ normal conformance         │
│ Mid<Int, Bool>: P          │    │ Top<(Bool, Int)>: P            │    │ Top<τ_0_0>: P              │
└────────────────────────────┘    └────────────────────────────────┘    └────────────────────────────┘
              │                                   │
              ↓                                   ↓
┌────────────────────────────┐    ┌────────────────────────────────┐
│ conforming type            │    │ substitution map               │
│ Mid<Int, Bool>             │    │ τ_0_0 ↦ (Bool, Int)            │
└────────────────────────────┘    └────────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Summary

我们来把目前用过的 `⊗` 运算符的各种形式过一遍。我们可以代入类型（见 `substitution-maps.tex`）：

```
Type(G) ⊗ Sub(G, H) ⟶ Type(H)
```

我们可以代入 conformance（即本节）：

```
Conf(G) ⊗ Sub(G, H) ⟶ Conf(H)
```

我们可以复合 substitution map（见 `substitution-maps.tex` 的 Composition 一节）：

```
Sub(G, H) ⊗ Sub(H, I) ⟶ Sub(G, I)
```

我们可以查找 conformance，其中 `Proto` 是全体 protocol 的集合（见本章 Conformance Lookup 一节）：

```
Proto ⊗ Type(G) ⟶ Conf(G)
```

此外我们还看到，`⊗` 运算符是结合的，所以表达式的结果从来不需要靠括号来消歧。

## Type Witnesses

要遵循一个带 associated type 的 protocol，nominal type declaration 必须为每个 associated type 声明一个 **type witness**。在源码语言里有四种方式声明 type witness：

1. 用一个与 associated type 同名的 **member type declaration**——也就是嵌套的 nominal type 或 type alias declaration。这个成员类型可以是 conforming nominal type 的子节点、它某个 extension 的子节点，或者当 conforming type 是 class 时，它某个 superclass 的子节点。
2. 用 **associated type inference**，即通过考察 protocol 里每条 value requirement 的候选 value witness来推断 type witness。
3. 用一个与 associated type 同名的 **generic parameter**。
4. 用 associated type declaration 上的 **default type witness**（如果有的话）。这是其他办法都失败时的兜底。

**例.** 我们来看四个遵循下面这个 protocol 的 nominal type declaration，每个演示上面四种情形之一：

```swift
protocol Pet {
  associatedtype Toy = Int
  func play(_: Toy)
}
```

开始之前，我们先为 `play()` 添加一个可用于任意 `Toy` 的 default witness，这样 conforming type 就不必各自提供实现：

```swift
extension Pet {
  func play(_: Toy) {}
}
```

我们的第一个类型 `Chicken` 显式声明了一个名为 `Toy` 的成员类型，而 `play()` 则依赖 default witness。这是上面的情形 1：

```swift
struct Chicken: Pet {
  struct Toy {}
}
```

另一边，`Cat` 没有显式见证 `Toy`，但与 `Chicken` 不同，它有自己的 `play()` 实现，接受一个 `String`。我们靠 associated type inference 推出 type witness 必须是 `String`。这是情形 2：

```swift
struct Cat: Pet {
  // synthesized: typealias Toy = String
  func play(_: String) {}
}
```

Associated type inference 会为每个推断出的 associated type 合成一个 type alias 成员，所以我们在程序别处可以像显式声明过 `Cat` 的成员 type alias `Toy` 那样引用 `Cat.Toy`。现在考虑 `Dog`，它用一个名为 `Toy` 的 generic parameter 来见证 `Pet` 的 associated type。这是情形 3：

```swift
struct Dog<Toy>: Pet {
  // synthesized: typealias Toy = Toy
}
```

当我们检查 conformance `[Dog: Pet]` 时，我们合成一个名为 `Toy` 的 type alias 成员，其 underlying type 就是 `Dog` 那个同样叫 `Toy` 的 generic parameter。虽然 generic parameter declaration 本身不作为**成员**可见，但这里我们有一个恰好同名的 type alias，所以 type representation `Dog<Ball>.Toy` 实际上解析成 `Ball`：

```swift
struct Ball {}

// same as play(_: Ball):
func play(_: Dog<Ball>.Toy)
```

（不过，如果 `Dog` 没有声明对 `Pet` 的 conformance，就不会有这个 type alias，type resolution 在解析 `Dog<Ball>.Toy` 时会诊断出错误。type resolution 与 associated type inference 的相互作用，在 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Member Type Representations 一节有进一步讨论。）

最后同样重要的是 `Horse`，它既没有声明名为 `Toy` 的成员类型，也没有实现 `play()`。我们用 `Toy` 的 default type witness，也就是在 `Pet` 里声明的 `Int`。这是情形 4：

```swift
struct Horse: Pet {
  // synthesized: typealias Toy = Int
}
```

### Normal conformances

每条 normal conformance 都含有一张表，把 protocol 的 associated type declaration 映射到这条 conformance 的 type witness。这张表由 **type witness request** 惰性填充，该 request 尝试用 qualified lookup 解析单个 type witness，处理的是情形 1。

若不存在这样的成员类型声明，我们接着求值 **type witnesses request**，它尝试通过 associated type inference 同时解析这条 normal conformance 里的全部 type witness。这条代码路径实现的是情形 2，但也实现情形 3 和情形 4——用户可能不会觉得后两者属于 associated type inference 的一部分。Associated type inference 将在本章 Associated Type Inference 一节讨论。

当一条 conformance 声明在某个 frontend job 的 secondary file 里时，只有在类型检查别的东西时确实需要，我们才解析它的 type witness。反过来，当一条 conformance 声明在 primary file 里时，我们还会把 **conformance checker** 作为 type-check primary file request 的一部分跑起来。Conformance checker 解析全部 type witness 与 value witness，并执行各种额外检查。如果 conformance checker 没有发出任何诊断，我们就知道这条 conformance 提供了一整套完整的 type witness 与 value witness，可以进入代码生成阶段了。

### Projection

我们用 `⊗` 运算符的一种新形式，把 type witness 纳入 type substitution algebra。假设 `[X_d: P]` 是一条 normal conformance，且 `P` 声明了一个 associated type `A`。我们用记号 `A` 指代这个 associated type declaration（原书写作 `⟨P|A`），并把 `A` 的 type witness 记作下面这个表达式：

```
A ⊗ [X_d: P]
```

**例.** 我们可以用新记法把上面 `Pet` 那个例子总结如下：

```
Toy ⊗ [Chicken: Pet]      = Chicken.Toy
Toy ⊗ [Cat: Pet]          = String
Toy ⊗ [Dog<τ_0_0>: Pet]   = τ_0_0
Toy ⊗ [Horse: Pet]        = Int
```

### Specialized conformances

一旦我们要求 `⊗` 是结合运算，specialized conformance 的 type witness 就被完全决定了。假设 `X = X_d ⊗ Σ`，且 `[X: P] = [X_d: P] ⊗ Σ` 是一条 specialized conformance。要从这条 specialized conformance 里投影出某个 `A` 的 type witness，我们把 conformance substitution map `Σ` 应用到底下那条 normal conformance 中 `A` 的 type witness 上：

```
A ⊗ ([X_d: P] ⊗ Σ) := (A ⊗ [X_d: P]) ⊗ Σ
```

**例.** 标准库的 normal conformance `[Array<τ_0_0>: Sequence]` 这样见证 `Sequence` 的 `Element` 和 `Iterator` 两个 associated type：

```
Element ⊗ [Array<τ_0_0>: Sequence]
    = τ_0_0
Iterator ⊗ [Array<τ_0_0>: Sequence]
    = IndexingIterator<Array<τ_0_0>>
```

回忆上文那条 specialized conformance `[Array<Int>: Sequence]`。要得到它的 type witness，我们施加 conformance substitution map `{τ_0_0 ↦ Int}`：

```
Element ⊗ [Array<Int>: Sequence]
    = τ_0_0 ⊗ {τ_0_0 ↦ Int}
    = Int

Iterator ⊗ [Array<Int>: Sequence]
    = IndexingIterator<Array<τ_0_0>> ⊗ {τ_0_0 ↦ Int}
    = IndexingIterator<Array<Int>>
```

有一条重要的不变量：出现在 normal 或 specialized conformance 的 type witness 里的任何 type parameter，在该 conformance 的 output generic signature 里都是有效的。换句话说，若 `[X: P] ∈ Conf(G)` 且 `A` 是 `P` 的一个 associated type，则 `A ⊗ [X: P] ∈ Type(G)`。（等讲到 abstract conformance 时，我们会看到这条性质在那里同样成立。）把上面这些总结一下：若记 `AssocType_P` 为某个固定 protocol `P` 的全体 associated type declaration，`Conf_P(G)` 为 `Conf(G)` 中只对 `P` 的那些 conformance 构成的子集，那么对每个 protocol `P`，**type witness projection** 给了我们 `⊗` 运算的这种新形式：

```
AssocType_P ⊗ Conf_P(G) ⟶ Type(G)
```

> 译注：本库对应的是 type witness 的**读回**方向：conformance 的 associated type witness 编译后落在 `__swift5_assocty` 一节，本库的静态布局引擎靠它把 `C.Index`、`C.Element` 这类 associated-type 字段解成具体类型，见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)（`DependentMemberTypeBridge` 一节）。

最后我们来看 global conformance lookup 与 type witness projection 之间的关系。若 `X = X_d ⊗ Σ` 遵循 `P`，且 `P` 声明了一个 associated type `A`，那么解析 type representation「`X.A`」的一种办法是先做 global conformance lookup，再做 type witness projection：

```
A ⊗ P ⊗ X_d ⊗ Σ
```

这个表达式有四种加括号的方式，其中三种对应 `⊗` 的合法组合：

```
(1)  ((A ⊗ (P ⊗ X_d)) ⊗ Σ)
(2)  (A ⊗ ((P ⊗ X_d) ⊗ Σ))
(3)  (A ⊗ (P ⊗ (X_d ⊗ Σ)))
```

我们约定 `X_d.A` 表示 `[X_d: P]` 中 `A` 的 type witness，`X.A` 表示 `[X: P]` 中 `A` 的 type witness。那么上面三种组合必定都输出 `X.A`，因为我们在每一处都把 `⊗` 定义成了结合的：

1. 我们可以先查 `X_d` 对 `P` 的 conformance，从这条 normal conformance 投影出 type witness `X_d.A`，再把 `Σ` 应用到这个 type witness 上，得到 `X.A`。
2. 我们可以先查 `X_d` 对 `P` 的 conformance，把 `Σ` 应用到这条 normal conformance 上得到一条 specialized conformance，再投影出 type witness `X.A`。
3. 我们可以先把 `Σ` 应用到 `X_d` 上，查 `X` 对 `P` 的 conformance，再投影出 type witness `X.A`。

我们也可以用一张 commutative diagram 来展示这件事。三种求值次序各自对应从 `X_d` 到 `X.A` 的三条不同路径之一：

```
              Σ
   X_d  ────────────→   X
    │                   │
  P │                   │ P
    ↓                   ↓
[X_d: P] ───────────→ [X: P]
    │          Σ        │
  A │                   │ A
    ↓                   ↓
  X_d.A ────────────→  X.A
               Σ
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。这张图断言的是：从左上角 `X_d` 走到右下角 `X.A`，无论先查 conformance、先投影 type witness 还是先代入 `Σ`，结果都相同。

把这件事落到具体处：用上面例子里 `[Array<Int>: Sequence]` 的 `Element` type witness，我们得到下图——因为「`Array<Int>.Element`」解析成 `Int`：

```
                      {τ_0_0 ↦ Int}
   Array<τ_0_0>  ──────────────────────→   Array<Int>
        │                                      │
Sequence│                                      │Sequence
        ↓                                      ↓
[Array<τ_0_0>: Sequence] ────────────→ [Array<Int>: Sequence]
        │              {τ_0_0 ↦ Int}           │
 Element│                                      │Element
        ↓                                      ↓
      τ_0_0  ──────────────────────────────→  Int
                      {τ_0_0 ↦ Int}
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。这是上一张图在 `Array` / `Sequence` 上的具体实例。

## Abstract Conformances

**abstract conformance** 表示一个 type parameter 对某个 protocol 的 conformance。若 `T` 是 type parameter，`P` 是 protocol，global conformance lookup 在收到 `T` 与 `P` 时构造一条 abstract conformance：

```
P ⊗ T := [T: P]
```

我们说一条 abstract conformance `[T: P]` 在 generic signature `G` 里是 **valid** 的，如果 conformance requirement `[T: P]` 可以从 `G` 推出（见 `generic-signatures.tex` 的 Derived Requirements 一节）。因此，我们那两套形式体系用同一个记号 `[T: P]` 同时表示 conformance requirement 和 abstract conformance，并不会产生歧义。

我们将用 abstract conformance 来补上 `substitution-maps.tex` 里 Substitute type 算法中尚未解释的那一部分，也就是：如何把 substitution map 应用到 bound dependent member type 上。在此之前，我们必须先定义 abstract conformance 上的 type witness projection 与 conformance substitution。假设 `G ⊢ [T: P]`，且 `P` 声明了一个 associated type `A`。在 `generic-signatures.tex` 的 Bound Type Parameters 一节我们见过，可以对 `[T: P]` 的一个推导施加 **AssocDecl** 推理规则，从而推出 bound dependent member type `T.[P]A`：

1. `[T: P]` —— （……）
2. `T.[P]A` —— （**AssocDecl** 前提 1）

在 type substitution algebra 里，`[T: P]` 同时也是一条有效的 abstract conformance，于是很自然地，我们把 dependent member type `T.[P]A` 定义为这条 conformance 里 `A` 的 type witness：

```
A ⊗ [T: P] := T.[P]A
```

每一个 bound dependent member type 都能这样写出来，这揭示了 derived requirements 形式体系与 type substitution 之间的紧密联系。

**例.** 回忆 `generic-signatures.tex` 里那个 `firstTwoEqual()` 函数。设 `G` 为该函数的 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                τ_0_0.[Sequence]Element: Equatable,
                τ_0_0.[Sequence]Element == τ_0_1.[Sequence]Element>
```

我们可以把 `τ_0_0.[Sequence]Element` 和 `τ_0_1.[Sequence]Element` 分别表达成某条 abstract conformance 的 type witness：

```
Sequence ⊗ τ_0_0 = [τ_0_0: Sequence]
Element ⊗ [τ_0_0: Sequence] = τ_0_0.[Sequence]Element

Sequence ⊗ τ_0_1 = [τ_0_1: Sequence]
Element ⊗ [τ_0_1: Sequence] = τ_0_1.[Sequence]Element
```

像这样把 dependent member type 分解开来，能让我们理解「把 substitution map 应用到这种类型上」时到底发生了什么：

```
T.[P]A ⊗ Σ := (A ⊗ [T: P]) ⊗ Σ
```

由于我们要求 `⊗` 是结合的，右边只有一种解释：

```
(A ⊗ [T: P]) ⊗ Σ := A ⊗ ([T: P] ⊗ Σ)
```

我们是在把 substitution map `Σ` 应用到 abstract conformance `[T: P]` 上，然后从这条代入后的 conformance 里投影出一个 type witness 作为最终结果。这种新形式的 conformance substitution 叫做 **local conformance lookup**——之所以与 global conformance lookup 相对应地这么叫，是因为它扮演的角色类似。

虽然要到 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 我们才会研究 local conformance lookup 的实现，但现在就已经可以完整**规定**它的行为了。设 `[T: P]` 与 `Σ` 如上。由于 `[T: P] = P ⊗ T`，我们也有：

```
[T: P] ⊗ Σ = (P ⊗ T) ⊗ Σ = P ⊗ (T ⊗ Σ)
```

换句话说，对 `[T: P]` 在 `Σ` 中做 local conformance lookup，必须找到与「对 `T ⊗ Σ` 查它对 `P` 的 conformance」**同一条** conformance。

### Substitution maps

给定任何一条有效的 abstract conformance，local conformance lookup 必须能从 substitution map 里恢复出对应的代入后 conformance。确实，上一章我们提过，substitution map 除了 replacement type 之外还存 conformance——当它的 input generic signature 带有 conformance requirement 时。现在我们可以把这件事展开讲。

假设有一张 substitution map `Σ ∈ Sub(G, H)`。对应于 `G` 的一条**显式** conformance requirement `[T: P]` 的那条 abstract conformance，叫做 **root abstract conformance**。对 `G` 的每条 root abstract conformance，substitution map `Σ` 都含有一条 subject type 为 `T ⊗ Σ`、protocol 为 `P` 的 conformance；我们把这些叫做 `Σ` 的 **root conformance**。对 root abstract conformance 做 local conformance lookup 很容易描述：把 `Σ` 应用到 `G` 的一条 root abstract conformance上，就是从 `Σ` 里投影出对应的 root conformance：

```
[T: P] ⊗ {…, [T: P] ↦ [X: P], …} := [X: P]
```

当语言里引用一个 generic declaration 时，它的 generic argument 要么显式给出，要么被推断出来。一旦有了这份 replacement type 列表，我们就为它补上一份 root conformance 列表，构成一张 substitution map。要得到每条 root conformance，我们取该声明 generic signature 中每条 conformance requirement 的 subject type，代入我们的 replacement type，再做一次 global conformance lookup。这种构造方式保证了每条 root conformance 的 output generic signature 与描述 `Σ` 各 replacement type 的那个 generic signature 相同。因此，若 `Σ` 属于 `Sub(G, H)`，则 `Σ` 的每条 root conformance 都必须属于 `Conf(H)`。

先把「abstract conformance 不是 root abstract conformance 时 local conformance lookup 该怎么办」这个问题放一放，我们现在可以描述 `substitution-maps.tex` 中 Substitute type 算法缺的那一种情形了：

**算法（Substitute dependent member type）.** 以一个 dependent member type `T.[P]A` 和一张 substitution map `Σ` 为输入。该 dependent member type 必须是这张 substitution map 的 input generic signature 里的 valid type parameter。输出代入后的类型 `T.[P]A ⊗ Σ`。

1. 设 `A` 为该 dependent member type 引用的 associated type declaration。（本算法不接受 unbound dependent member type。）
2. 设 `P` 为含有该 associated type declaration 的 protocol。
3. 设 `T` 为该 dependent member type 的 base type parameter。
4. 用 `conformance-paths.tex` 的 Local conformance lookup 算法执行 local conformance lookup `[T: P] ⊗ Σ`。
5. 从这条 conformance 里投影出 `A` 的 type witness并返回。

我们也把 substitution map composition `Σ₁ ⊗ Σ₂` 推广到 `Σ₁` 带 root conformance 的情形——办法是把 `Σ₂` 应用到 `Σ₁` 的每条 root conformance 上：

```
Σ₁ ⊗ Σ₂ := {…, [T: P] ↦ [X: P] ⊗ Σ₂, …}
```

也就是说，若 `Σ₁` 把 root abstract conformance `[T: P]` 送到某条 conformance `[X: P]`，那么必有 `[T: P] ⊗ (Σ₁ ⊗ Σ₂) = [X: P] ⊗ Σ₂`。最后我们指出，对任何 generic signature `G`，identity substitution map `1_G` 的 root conformance 恰好就是 `G` 的那些 root **abstract** conformance：

```
1_G := {…, [T: P] ↦ [T: P], …}
```

**例.** 接着上面 `firstTwoEqual()` 那个例子，假设我们用 `Array<Int>` 和 `Set<Int>` 调用它：

```swift
func doIt(_ s1: Array<Int>, _ s2: Set<Int>) {
  if firstTwoEqual(s1, s2) {...}
}
```

这次调用的 substitution map `Σ` 如下，它有三条 root conformance：

```
Σ := { τ_0_0 ↦ Array<Int>,
       τ_0_1 ↦ Set<Int>;
       [τ_0_0: Sequence] ↦ [Array<Int>: Sequence],                    (1)
       [τ_0_1: Sequence] ↦ [Set<Int>: Sequence],                      (2)
       [τ_0_0.[Sequence]Element: Equatable] ↦ [Int: Equatable] }      (3)
```

我们来说说构造 `Σ` 时是怎么填这些 root conformance 的。前两条 conformance requirement 的 subject type 分别是 `τ_0_0` 和 `τ_0_1`，所以我们查 `τ_0_0 ⊗ Σ` 与 `τ_0_1 ⊗ Σ` 对 `Sequence` 的 conformance：

```
Sequence ⊗ (τ_0_0 ⊗ Σ) = [Array<Int>: Sequence]    (1)
Sequence ⊗ (τ_0_1 ⊗ Σ) = [Set<Int>: Sequence]      (2)
```

第三条 conformance requirement 的 subject type 是 `τ_0_0.[Sequence]Element`。我们可以把这个 dependent member type 写成一条 root abstract conformance 的 type witness：

```
τ_0_0.[Sequence]Element = Element ⊗ [τ_0_0: Sequence]
```

要代入这个 dependent member type，我们从 root conformance (1) 里投影出 `Element` 的 type witness，得到 `Int`。然后查它对 `Equatable` 的 conformance，得到最后一条 root conformance (3)：

```
Equatable ⊗ τ_0_0.[Sequence]Element ⊗ Σ
    = Equatable ⊗ Element ⊗ ([τ_0_0: Sequence] ⊗ Σ)
    = Equatable ⊗ Element ⊗ [Array<Int>: Sequence]
    = Equatable ⊗ (τ_0_0 ⊗ {τ_0_0 ↦ Int})
    = Equatable ⊗ Int
    = [Int: Equatable]                                  (3)
```

Type parameter `τ_0_0.Element` 与 `τ_0_1.Element` 在 `G` 里是等价的，所以我们预期 `τ_0_1.[Sequence]Element ⊗ Σ` 也应当等于 `Int`。确实，一旦知道 `[Set<τ_0_0>: Sequence]` 中 `Element` 的 type witness 是 `τ_0_0`，就有：

```
τ_0_1.[Sequence]Element ⊗ Σ
    = Element ⊗ ([τ_0_1: Sequence] ⊗ Σ)
    = Element ⊗ [Set<Int>: Sequence]
    = τ_0_0 ⊗ {τ_0_0 ↦ Int}
    = Int
```

我们这张 substitution map 满足那条 same-type requirement。比方说，如果 `τ_0_1` 的 replacement type 换成 `Set<String>`，这条就不再成立了。「检查一张 substitution map 是否满足其 input generic signature 的 requirement」这个问题，将在 `type-resolution.tex` 的 Generic Arguments 一节讨论。最后，虽然 `G` 要求两个 `Sequence` 有相同的 `Element`，但对它们的 `Iterator` 类型并无这样的要求。确实，`Σ` 把它们映到了不同的具体类型：

```
τ_0_0.[Sequence]Iterator ⊗ Σ = IndexingIterator<Array<Int>>
τ_0_1.[Sequence]Iterator ⊗ Σ = IndexingIterator<Set<Int>>
```

### Protocol substitution maps

在 `generic-signatures.tex` 里我们见过，protocol declaration `P` 有 generic signature `<Self where Self: P>`，称为 **protocol generic signature**，简记为 `G_P`。我们有时需要为 `G_P` 指定一张 substitution map。这叫做 **protocol substitution map**，它由单个 replacement type `X` 和一条 `X` 对 `P` 的 conformance 组成。我们把它记作 `Σ_[X: P]`：

```
Σ_[X: P] := {Self ↦ X;  [Self: P] ↦ [X: P]}
```

把 `Σ_[X: P]` 应用到 `Self` 上输出 conforming type，而把它应用到 dependent member type `Self.[P]A`（`A` 是 `P` 的某个 associated type）上，则输出这条 conformance 里 `A` 的 type witness：

```
Self ⊗ Σ_[X: P] = X
Self.[P]A ⊗ Σ_[X: P] = A ⊗ [Self: P] ⊗ Σ = A ⊗ [X: P]
```

## Associated Conformances

除了为每个 associated type 提供 type witness 之外，一条 normal conformance 还必须满足 protocol requirement signature 里的每条 associated requirement（见 `generic-signatures.tex` 的 Requirement Signatures 一节）。我们在 conformance checker 里检查 associated requirement——也就是在访问 primary file 中声明的每条 normal conformance 时。requirement 一般是如何被检查与诊断的，将在 `type-resolution.tex` 的 Generic Arguments 一节讨论；本节专注于 associated conformance requirement，它对 type substitution 尤为重要。

假设 `d` 是一个遵循 `P` 的 nominal type declaration，于是我们有一条 normal conformance `[X_d: P]`，而 `P` 声明了一条 associated conformance requirement `[Self.U: Q]_P`。要检查这条 requirement，我们必须把 requirement 的 subject type `Self.U` 里的 `Self` 换成 `X_d`，再检查代入后的类型遵循 `Q`。Type parameter `Self.U` 是相对于 `P` 的 protocol generic signature 书写的，所以我们把 protocol substitution map `Σ_[X_d: P]` 应用到 `Self.U` 上，随后做 global conformance lookup：

```
Q ⊗ (Self.U ⊗ Σ_[X_d: P])
```

得到的结果就是见证 associated conformance requirement `[Self.U: Q]_P` 的那条 **associated conformance**。在每条 normal conformance 内部，我们记着一张它的 associated conformance 表，按其 protocol 的 associated conformance requirement 索引。我们由 **associated conformance request** 惰性填充这张表。该 request 接收一条 normal conformance 和一条 associated conformance requirement 作为输入，然后照上面的步骤走：先把 protocol substitution map 应用到 requirement 的 subject type 上，再做一次 global conformance lookup。

> 译注：associated conformance 在二进制里就是 witness table 开头那几个指向其他 witness table 的槽位。OS 框架的符号被剥掉之后，本库无法恢复每条 protocol requirement 的名字，改为按槽位偏移投影出 `pwtslot:` 记录来做 ABI 比对，见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

### Projection

在 type substitution algebra 里，我们把一条 associated conformance requirement 记作 `[Self.U: Q]_P`。**Associated conformance projection** 给了我们 `⊗` 运算符的这种新形式。对 normal conformance，投影就是求值上面那个 associated conformance request：

```
[Self.U: Q]_P ⊗ [X_d: P] := Q ⊗ (Self.U ⊗ Σ_[X_d: P])
```

`⊗` 的结合律决定了 specialized conformance `[X: P] = [X_d: P] ⊗ Σ` 上的 associated conformance projection。我们先从底下那条 normal conformance `[X_d: P]` 投影出 associated conformance，再把 `Σ` 应用到这条 conformance 上：

```
[Self.U: Q]_P ⊗ [X: P]
    = [Self.U: Q]_P ⊗ ([X_d: P] ⊗ Σ)
    = ([Self.U: Q]_P ⊗ [X_d: P]) ⊗ Σ
```

我们也为 abstract conformance 定义 associated conformance projection。回忆一下，若 `G ⊢ [T: P]` 且 `[Self.U: Q]_P` 是 `P` 的一条 associated requirement，我们可以施加 **AssocConf** 推理规则推出 conformance requirement `[T.U: Q]`，其中 `T.U` 表示把 `Self.U` 里的 `Self` 换成 `T` 所得的 type parameter：

1. `[T: P]` —— （……）
2. `[T.U: Q]` —— （**AssocConf** 前提 1）

因此，`[T.U: Q]` 是一条有效的 abstract conformance；而且事实上，它正是 abstract conformance `[T: P]` 中对应于 `[Self.U: Q]_P` 的那条 associated conformance，所以我们定义：

```
[Self.U: Q]_P ⊗ [T: P] := [T.U: Q]
```

记 `AssocConf_P` 为 `P` 的全体 associated conformance requirement 的集合，并回忆 `Conf_P(G)` 是 `Conf(G)` 中对 `P` 的那些 conformance 构成的子集。Associated conformance projection 给了我们 `⊗` 这个二元运算的又一种新形式：

```
AssocConf_P ⊗ Conf_P(G) ⟶ Conf(G)
```

`⊗` 的最后一种变体在 `type-resolution.tex` 的 Generic Arguments 一节描述。type substitution algebra 的完整总结见 `type-substitution-summary.tex`（中译 [SwiftGenericsSubstitutionAlgebra.md](SwiftGenericsSubstitutionAlgebra.md)）。

### Protocol inheritance

回忆一下，当 protocol `P` 继承自另一个 protocol `Q` 时，我们用一条 associated conformance requirement `[Self: Q]_P` 来表示这件事（见 `declarations.tex` 的 Protocols 一节）。这种情况下，给定任何一条对 derived protocol 的 conformance `[X: P]`，我们都能投影出 conforming type 相同、但指向 base protocol `Q` 的那条 conformance：

```
[Self: Q]_P ⊗ [X: P] = [X: Q]
```

**例.** 我们在 `generic-signatures.tex` 里描述过继承自 `Sequence` 的 `Collection` protocol。标准库的 `Array` 不止遵循 `Sequence`，也遵循 `Collection`。考虑 specialized conformance `[Array<Int>: Collection]`。我们可以从 `[Array<Int>: Collection]` 投影出 `[Self: Sequence]_Collection`，这会把我们带回上文那条 specialized conformance `[Array<Int>: Sequence]`：

```
[Self: Sequence]_Collection ⊗ [Array<Int>: Collection]
    = [Self: Sequence]_Collection ⊗ [Array<τ_0_0>: Collection] ⊗ {τ_0_0 ↦ Int}
    = [Array<τ_0_0>: Sequence] ⊗ {τ_0_0 ↦ Int}
    = [Array<Int>: Sequence]
```

现在，设 `Σ` 是 `[Array<Int>: Collection]` 的 protocol substitution map，也就是把 `τ_0_0` 换成 `Array<Int>`。我们要把 `Σ` 应用到 `G_Collection` 的 type parameter `τ_0_0.[Sequence]Element` 上：

```
τ_0_0.[Sequence]Element ⊗ Σ
    = Element ⊗ [τ_0_0: Sequence] ⊗ Σ
```

这一次，`[τ_0_0: Sequence]` 不是我们这个 generic signature 的显式 requirement，所以 `[Array<Int>: Sequence]` 不是 `Σ` 的 root conformance。Local conformance lookup 必须多走一步。下面是 `G_Collection ⊢ [τ_0_0: Sequence]` 的一个推导：

1. `[τ_0_0: Collection]` —— （**Conf**）
2. `[τ_0_0: Sequence]` —— （**AssocConf** 前提 1）

在 type substitution algebra 里，这是一条关于 abstract conformance 的陈述：

```
[Self: Sequence]_Collection ⊗ [τ_0_0: Collection] = [τ_0_0: Sequence]
```

我们为 `G_Collection` 里的 `[τ_0_0: Sequence]` 找到了一条 **conformance path**。conformance path 告诉 local conformance lookup：怎样从 substitution map 里的一条 root conformance 出发，投影出一连串 associated conformance，从而拿到代入后的 conformance：

```
τ_0_0.[Sequence]Element ⊗ Σ
    = Element ⊗ [Self: Sequence]_Collection ⊗ [τ_0_0: Collection] ⊗ Σ
                └───────────── conformance path ──────────────┘
```

我们先求值 `[τ_0_0: Collection] ⊗ Σ`，从 `Σ` 里取出 root conformance。然后投影出 associated conformance `[Array<τ_0_0>: Sequence]`，再从那里投影出 `Element` 的 type witness，得到 `Int`：

```
τ_0_0.[Sequence]Element ⊗ Σ = Int
```

`conformance-paths.tex` 会证明，对任意 abstract conformance，我们总能找到一条 conformance path。

**例.** 在上文 `Array` 的 type witness 那个例子里我们看到，`[Array<τ_0_0>: Sequence]` 用在 `Array<τ_0_0>` 处特化的 `IndexingIterator` 来见证 `Iterator` 这个 associated type：

```
Iterator ⊗ [Array<τ_0_0>: Sequence]
    = IndexingIterator<Array<τ_0_0>>
```

现在回忆一下，`Sequence` protocol 声明了 associated conformance requirement `[Self.Iterator: IteratorProtocol]_Sequence`。如果我们从上面这条 conformance 里投影出这条 requirement，就得到 `IndexingIterator<Array<τ_0_0>>` 对 `IteratorProtocol` 的 specialized conformance：

```
[Self.Iterator: IteratorProtocol]_Sequence ⊗ [Array<τ_0_0>: Sequence]
    = IteratorProtocol ⊗ IndexingIterator<Array<τ_0_0>>
    = [IndexingIterator<Array<τ_0_0>>: IteratorProtocol]
```

一如既往，这条 specialized conformance 由下面两部分构成：

1. normal conformance `[IndexingIterator<τ_0_0>: IteratorProtocol]`。
2. `IndexingIterator<Array<τ_0_0>>` 的 context substitution map。

我们先看 (1)。标准库的 `IndexingIterator` 类型很有意思，因为它是拿一条对 `Collection` 的 abstract conformance 来实现 `IteratorProtocol` 的各条 requirement 的；也就是说，它可以充当**任何** `Collection` 的 `Iterator` type witness：

```swift
struct IndexingIterator<Elements: Collection>: IteratorProtocol {
  typealias Element = Elements.Element
  mutating func next() -> Element? {
    ...
  }
}
```

`IndexingIterator` 的 generic signature 就是 `G_Collection`，只有一条 conformance requirement。(1) 里 `Element` 的 type witness 是一个 dependent member type：

```
Element ⊗ [IndexingIterator<τ_0_0>: IteratorProtocol]
    = τ_0_0.[Sequence]Element
```

现在考虑 substitution map (2)，我们把它叫做 `Σ`。它的 input generic signature 是 `G_Collection`，output generic signature 是 `Array` 的那个，也就是 `<τ_0_0>`：

```
Σ := { τ_0_0 ↦ Array<τ_0_0>;
       [τ_0_0: Collection] ↦ [Array<τ_0_0>: Collection] }
```

我们来从 associated conformance (1) 里投影出 `Element` 的 type witness：

```
Element ⊗ [IndexingIterator<Array<τ_0_0>>: IteratorProtocol]
    = τ_0_0.[Sequence]Element ⊗ Σ
```

这与上一个例子类似，只不过我们把 `τ_0_0` 换成的是 `Array<τ_0_0>` 而不是 `Array<Int>`；除此之外可以用同一条 conformance path：

```
τ_0_0.[Sequence]Element ⊗ Σ
    = Element ⊗ [Self: Sequence]_Collection ⊗ [τ_0_0: Collection] ⊗ Σ
    = Element ⊗ [Array<τ_0_0>: Sequence]
    = τ_0_0
```

用 `Σ` 的 input 与 output generic signature 来说，这句话的意思是：`Array` 的 `Iterator` associated conformance 里的 `Element` associated type，是由 `Array` 的 `Element` generic parameter 见证的。在推导的过程中我们看到，这条 `Iterator` conformance 的 conformance substitution map 里含有 `[Array<τ_0_0>: Collection]`，而后者又通过一次 associated conformance projection 与 `[Array<τ_0_0>: Sequence]` 相联系，闭合成一个环：

```
┌────────────────────────────────────────────────────┐
│ normal conformance                                 │ ←──────────┐
│ Array<τ_0_0>: Collection                           │            │
└────────────────────────────────────────────────────┘            │
                     │ associated conformance projection          │
                     ↓                                            │
┌────────────────────────────────────────────────────┐            │
│ normal conformance                                 │            │
│ Array<τ_0_0>: Sequence                             │            │
└────────────────────────────────────────────────────┘            │
                     │ associated conformance projection          │
                     ↓                                            │
┌────────────────────────────────────────────────────┐            │
│ specialized conformance                            │ ───┐       │
│ IndexingIterator<Array<τ_0_0>>: IteratorProtocol   │    │       │
└────────────────────────────────────────────────────┘    │       │
                     │ underlying conformance              │       │
                     ↓                                     │       │
┌────────────────────────────────────────────────────┐    │       │
│ normal conformance                                 │    │       │
│ IndexingIterator<τ_0_0>: IteratorProtocol          │    │       │
└────────────────────────────────────────────────────┘    │       │
                                                           │       │
┌────────────────────────────────────────────────────┐    │       │
│ substitution map                                   │ ←──┘       │
│ τ_0_0 ↦ Array<τ_0_0>                               │            │
│ Array<τ_0_0>: Collection                           │ ───────────┘
└────────────────────────────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。图的整体形状是一个环：最上面的 `Array<τ_0_0>: Collection` 一路向下投影到 specialized conformance，后者指向自己的 substitution map，而这张 substitution map 里存的 conformance 又指回最上面那条，闭合成环。

我们在 `generic-signatures.tex` 的 Requirement Signatures 一节观察到 generic signature 与 requirement signature 之间存在结构上的对应。如果把 substitution map 与 conformance 的构成部分摆到一起看，两者之间也有类似的对应：

| Substitution map | Conformance |
|---|---|
| Replacement type：`τ_0_0 ⊗ Σ` | Type witness：`A ⊗ [X: P]` |
| Root conformance：`[T: P] ⊗ Σ` | Associated conformance：`[Self.U: Q]_P ⊗ [X: P]` |

于是我们得到 Swift 泛型实现里的四个基本语义对象：generic signature、requirement signature、substitution map、conformance。

## Associated Type Inference

本章最后一节讲 **associated type inference**。更准确的名字其实应该叫「type witness inference」，因为我们实际推断的是一条 conformance 里的 type witness；但现在这个名字就是我们在用的。下面并不是这项语言特性的完整描述，但足以当作快速参考，也足以演示一个重要的理论结果。

在本章 Type Witnesses 一节我们列出了语言里声明 type witness 的四种方式；associated type inference 处理其中的第 2、3、4 种。因此，只要我们无法靠对 conforming type 做 qualified lookup 解析出一条 normal conformance 里的至少一个 type witness，就会走到这里来。我们的做法如下：

1. 构建一个数据结构来描述我们的问题。
2. 求出这个数据结构所描述问题的全部解。
3. 分析找到的每个解，试着挑出最好的那个。
4. 如果成功，我们现在就拿到了这条 conformance 里的全部 type witness。

### The problem instance

我们先看 protocol 的 **value requirement**——也就是它的 function、subscript 和 variable（或 property）成员。一条 value requirement 的 interface type 是相对于 protocol generic signature `<Self where Self: P>` 书写的。只有当一条 value requirement 的 interface type 提到某个 dependent member type `Self.[P]A`（其中 `A` 是我们正试图推断其 type witness 的 associated type 之一）时，我们才需要考虑它。按 Swift 语言的规则，conforming type 必须用某个与该 value requirement 同名、同种类的成员声明来见证它。若把 conforming type 代入 `Self`，witness 的 interface type 也必须与 value requirement 的 interface type 相匹配。特别地，若 value requirement 的 interface type 涉及某个 dependent member type `Self.[P]A`，那么 value witness 的 interface type 必须在同一位置含有 `A` 的 type witness。

在 associated type inference 里，我们还不知道 value requirement 到 value witness 的映射会是什么，当然也还不知道全部 type witness。不过至少，对每条 value requirement，我们可以做一次 qualified lookup，找出 conforming type 中那些——如果 interface type 能对得上的话——**可能**见证这条 value requirement 的成员。这就给了我们每条 value requirement 的一组 **candidate value witness**。

**例.** 我们的第一个例子涉及这个 protocol：

```swift
protocol Meal {
  associatedtype Chef
  associatedtype Main
  associatedtype Desert

  func eat(_: Main, _: Desert)
  func prepare(_: Chef) -> Desert
}
```

在下面这条 conformance 里，我们被要求推断全部三个 associated type：

```swift
struct Lunch: Meal {
  func eat(_: Int, _: Bool) {...}
  func eat(_: Bool, _: Float) {...}
  func eat(_: Int, _: Float) -> String {...}

  func prepare(_: Void) -> String {...}
  func prepare(_: String) -> Bool {...}
}
```

每个 candidate value witness 给我们一个 **partial solution**，也就是一串「associated type ↦ type witness」对，做法如下。我们把 requirement 的 interface type 与 witness 的 interface type 并排遍历。若它们在任何位置有差异，我们就否决这次配对——除非 requirement 的 interface type 在对应子节点处是一个 dependent member type `Self.[P]A`；这种情况下，我们往 partial solution 里加一条 **type witness assignment**。我们把来自同一条 value requirement 的各个 partial solution 收集成一个 **disjunction**。从所有 value requirement 得到的 disjunction 列表就是我们的 **problem instance**：

```
problem instance = disjunction 的列表 = partial solution 的列表的列表
```

我们这个 problem instance 的一个 **solution**，就是一种很特殊的 partial solution。若每个 associated type 都**至少**在「`↦`」左边出现过一次，我们说这个解是 **complete** 的；若每个 associated type 都**至多**在「`↦`」左边出现过一次，我们说它是 **consistent** 的。若一个解把某个 disjunction 里的某个 partial solution 作为子集包含在内，我们说它 **covers**（覆盖）了这个 disjunction。于是我们的目标可以这样陈述：给定一个 problem instance，*我们必须找到一个覆盖全部 disjunction 的 complete 且 consistent 的解*。

**例.** 给定上面 `Meal` / `Lunch` 那些声明，下表列出了每条 value requirement 与每个 candidate value witness 的 interface type：

| 名字 | Requirement | Witnesses |
|---|---|---|
| `eat(_:_:)` | `(Self.Main, Self.Desert) -> ()` | `(Int, Bool) -> ()` |
| | | `(Bool, Float) -> ()` |
| | | `(Int, Float) -> String` |
| `prepare()` | `(Self.Chef) -> Self.Desert` | `(Void) -> String` |
| | | `(String) -> Bool` |

考虑 `eat(_:_:)` 的第一个候选。如果它是 witness，那么把 value requirement 类型里的 `Self` 换成 `Meal` 应该给出 `(Int, Bool) -> ()`，而这只有在 `Main` 的 type witness 是 `Int`、`Desert` 的 type witness 是 `Bool` 时才可能。我们把这个 partial solution 记作 `{Main ↦ Int, Desert ↦ Bool}`。另一方面，`eat(_:_:)` 的第三个 candidate value witness 与 requirement 的返回类型不匹配，所以它不向这个 disjunction 贡献 partial solution。分析完全部 candidate value witness 之后我们看到，这个 problem instance 有两个 disjunction，每个 disjunction 里有两个 partial solution，每个 partial solution 里有两条 type witness assignment：

```
{{Main ↦ Int, Desert ↦ Bool}, {Main ↦ Bool, Desert ↦ Float}}
{{Chef ↦ Void, Desert ↦ String}, {Chef ↦ String, Desert ↦ Bool}}
```

我们可以手算解出这个实例：注意到 `Desert` 必须是 `Bool`、`Float`、`String` 之一。然而只有 `Bool` 在两个 disjunction 里都出现，所以 `Desert` 实际上就是 `Bool`。解只有一个，由第一个 disjunction 的第一个 partial solution 和第二个 disjunction 的第二个 partial solution 拼成：

```
{Main ↦ Int, Desert ↦ Bool} ∪ {Chef ↦ String, Desert ↦ Bool}
    = {Chef ↦ String, Main ↦ Int, Desert ↦ Bool}
```

这就定下了 conformance `[Lunch: Meal]` 里全部的 type witness**和** value witness。

当一个 candidate value witness 是某个 protocol extension 的成员时，我们能观察到更微妙的行为，因为此时 dependent member type 可以出现在匹配的**右边**。我们不打算在这里描述全部可能性，只给一个例子。

**例.** 我们将根据可能的 type witness assignment，判定 `P.f(_:_:)` 的三个 candidate value witness 中哪一个才是真正的 witness：

```swift
protocol P {
  associatedtype A
  associatedtype B
  func f(_: A, _: B)
  func g(_: B)
}

struct S: P {
  func f(_: String, _: Float) {}                                 // (1)
  func g(_: Bool) {}
}

extension P {
  func f(_: Int, _: B) {}                                        // (2)
  func f(_: Void, _: Array<B>) {}                                // (3)
}
```

下表列出每条 requirement 与每个 candidate witness 的 interface type：

| 名字 | Requirement | Witnesses |
|---|---|---|
| `f(_:_:)` | `(Self.A, Self.B) -> ()` | `(String, Float) -> ()` |
| | | `(Int, Self.B) -> ()` |
| | | `(Void, Array<Self.B>) -> ()` |
| `g(_:)` | `(Self.B) -> ()` | `(Bool) -> ()` |

考虑 `f(_:_:)` 的第二个候选。如果它是 witness，那么 `A` 必须是 `Int`，但关于 `B` 我们什么也说不出来。我们略去**同义反复**的赋值 `B ↦ B`，于是这个 partial solution 就只是 `{A ↦ Int}`。第三个候选看起来类似，但与第二个不同，它根本不向这个 disjunction 贡献 partial solution：我们无法表示赋值 `B ↦ Array<Self.[P]B>`，因为它实际涉及的是无穷类型 `Array<Array<Array<...>>>`。因此我们也不必考虑 `A ↦ Void` 的可能性。这样一来，`f(_:_:)` 的 disjunction 就只有两个 partial solution。下面是我们的 problem instance：

```
{{A ↦ String, B ↦ Float}, {A ↦ Int}}
{{B ↦ Bool}}
```

唯一的解是 `{A ↦ Int} ∪ {B ↦ Bool} = {A ↦ Int, B ↦ Bool}`。因此在这条 conformance 里，(2) 才是 `P.f(_:_:)` 真正的 witness。

> 译注：原书此处正文写的是「`foo(_:_:)` 的 disjunction 因此只有两个 partial solution」，但例子里的 requirement 叫 `f(_:_:)`，并无 `foo`，疑为笔误，以 `f(_:_:)` 为准。

### The solver

假设我们手上有一个 consistent 的 partial solution，它覆盖了 problem instance 里的一部分但不是全部 disjunction。要在问题上取得进展，我们可以挑一个尚未被覆盖的 disjunction，再从这个 disjunction 里挑一个 partial solution。如果这个 partial solution 与我们手上的一致，我们就能把解扩大一圈。到这一步，我们要么已经找到一个 complete 的解，要么把问题规模缩小了——还剩的 disjunction 少了一个。反过来，若我们所选 disjunction 里的全部 partial solution 都与我们的解不一致，那就说明某一步选错了，于是必须 **backtrack**（回溯）并做出不同的选择。这就是 associated type inference 求解器的基本思路。注意我们找到一个解之后并不停下，因为我们希望访问全部解并给它们排名，下文会讲到。

**算法（Associated type inference）.** 算法由一个递归的辅助过程和一个外层过程组成。递归辅助过程接收一个 disjunction 列表 `D`、一个 partial solution `S`，以及下一个待覆盖 disjunction 的下标 `i`。它访问所有包含 `S` 的 consistent 解。外层过程以 `S ← ∅` 和 `i ← 0` 调用递归过程；因此它访问所有覆盖 `D` 全部元素的 consistent 解。

1. 若 `i` 等于 `D` 的长度，我们就有了一个解 `S`。调用 visitor 并返回。
2. 否则，设 `D[i]` 为 `D` 中第 `i` 个 disjunction。令 `j ← 0`。
3. 若 `j` 等于 `D[i]` 的长度，就不再有包含 `S` 的解了。返回。
4. 否则，设 `D[i][j]` 为 `D[i]` 中第 `j` 个 partial solution。若 `S ∪ D[i][j]` 也是一个 consistent 的 partial solution，就以 `S ← S ∪ D[i][j]` 和 `i ← i+1` 递归。
5. 令 `j ← j+1`。回到第 3 步。

### Incomplete solutions

求解器会遍历每一个覆盖全部 disjunction 的 consistent 解，但某些解可能没有给每个 associated type 都赋值，这时我们得到的解 consistent 但不 complete。这种情况下，在放弃这个解之前，我们还会再试几招来补上缺失的 type witness：

1. 我们分析 protocol 的 associated same-type requirement，看这个 type witness 是否与某个已知的 type witness 等价。
2. 我们检查 conforming nominal type 是否声明了一个与该 associated type 同名的 generic parameter。
3. 我们找 default type witness——要么在我们正试图推断的那个 associated type declaration 上，要么在 conforming type 所遵循的其他某个 protocol 里某个同名的 associated type declaration 上。

下面我们逐一看这三种行为的例子。

**例.** 第一种行为处理的是相当常见的场景。假设我们有一条 `Sequence` conformance，其 `Element` 就是某个固定的具体类型。我们可以这样写：

```swift
struct Fibonacci: Sequence {
  struct Iterator: IteratorProtocol {
    mutating func next() -> Int? {...}
  }
  func makeIterator() -> Iterator {...}
}
```

先看那个嵌套类型声明。我们从 `IteratorProtocol` conformance 里的 `next()` 推出 `Element` 的 type witness：

```
Element ⊗ [Fibonacci.Iterator: IteratorProtocol] = Int
```

再看外层类型声明。`Sequence` protocol 只有一条 value requirement，它只能定下 `Iterator` 的 type witness：

```
Iterator ⊗ [Fibonacci: Sequence] = Fibonacci.Iterator
```

我们无法从 `Sequence` 的 value requirement 推出 `[Fibonacci: Sequence]` 里 `Element` 的 type witness，于是转而考虑 associated same-type requirement `[Self.Element == Self.Iterator.Element]_Sequence`。它的左边正是我们要推断的那个 type witness，而右边可以用目前已知的 type witness 解出来：

```
Element ⊗ [Self.Iterator: IteratorProtocol]_Sequence ⊗ [Fibonacci: Sequence] = Int
```

这让我们能断定 `Element ⊗ [Fibonacci: Sequence] = Int`。

**例.** 第二种行为有点古怪，因为只有在我们已经穷尽了「从 candidate value witness 推断」这条路**之后**，才会去尝试把 type witness 解析成一个 generic parameter。这一点在上文 `Pet` 那个例子里不明显，那里 `Dog` 这个 struct 恰好就是用 generic parameter `Toy` 见证了 associated type `Toy`。然而，我们可能遇到一个与 generic parameter 同名、却从某个 candidate value witness 得到了不同 type witness 的 associated type。这里有一个假想的 iterator，它从一组元素里产出全部排列：

```swift
struct Permutations<Element>: IteratorProtocol {
  // synthesized: typealias Element = Array<Element>
  func next() -> [Element]? {...}
}
```

这条 conformance 里 `Element` 的 type witness 是 `Array<τ_0_0>` 而不是 `τ_0_0`，尽管 generic parameter 的名字容易让人以为是后者。于是下面的 `Permutations<Int>.Element` 解析成 `Array<Int>`：

```swift
func inspect(_: Permutations<Int>.Element) {...}
```

**例.** 至于第三种行为，我们回忆上文 `IndexingIterator` 那个例子。我们看到 `IndexingIterator` 有一个有趣的性质：它能为**任意** `Collection` 见证 `Sequence` 的 `Iterator` associated type，所以它理应成为默认值。然而它不能成为所有 `Sequence` conformance 的默认值，因为它的 generic argument 必须是 `Collection`。标准库对此的建模办法，是让 `Collection` 重新陈述一遍 `Iterator`，以便给它一个 default type witness：

```swift
associatedtype Iterator = IndexingIterator<Self>
```

重新陈述一个继承来的 associated type declaration 并不改变 generic signature 的等价类结构，但它让 derived protocol 能为继承来的 associated type 提供更合适的 default type witness。于是，当我们被要求推断某条 `Sequence` conformance 里的 `Iterator` associated type，而 conforming type **同时**也遵循 `Collection` 时，我们就使用上面这个默认值。

### Finishing up

如果上面这些产出了一个 complete 的解，我们还需要用 `type-resolution.tex` 的 Generic Arguments 一节里那个 Check substitution map 算法，检查我们的 type witness 赋值确实满足 protocol 的各条 associated requirement。若算法接受，我们就有了一个 **valid** 的解。就像 expression type checker 里那样（见 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 的 More Types 一节），我们收集全部 valid 解，然后考虑三种可能：

- **一个解**——给这条 conformance 里每个 associated type 赋 type witness 的方式唯一。
- **没有解**——从这条 conformance 推不出任何可能的 type witness 赋值。
- **多个解**——这条 conformance 里存在不止一种 consistent 的 type witness 赋值。

若只有一个解，我们就把这些 type witness 记进 conformance 并成功返回。多个解的情况下，我们先用一套启发式规则给这些解排名。举例来说，在其他条件相同的前提下，我们更偏好不涉及来自 protocol extension 的 candidate value witness 的解，因为这类候选通常本就是当作兜底实现来用的。若排名没能产生明确的赢家，我们就诊断一个歧义错误。

**例.** 下面这段里我们找到两个 valid 解 `{A ↦ Int}` 和 `{A ↦ Bool}`。没有理由偏好其中任何一个，于是我们诊断出错误：

```swift
protocol P {
  associatedtype A
  func f(_: A)
}

struct S: P {  // error
  func f(_: Int) {}
  func f(_: Bool) {}
}
```

**例.** 现行 associated type inference 实现的一个局限是，我们一次只考虑一条 conformance，所以会漏掉某些推断——如果 problem instance 能同时描述多条 conformance 的话，那些推断本来是可能做出来的。例如，下面我们无法推出 `Food` 必须是 `Int`：

```swift
protocol Base { associatedtype Food }

protocol Derived: Base { func eat(_: Food) }

struct Snack: Derived {
  func eat(_: Int) {}
}
```

这是一个由来已久的 bug；变通办法是在 `Derived` 里重新声明一遍 `Food`（SR-2235）。

### Boolean satisfiability

**Boolean formula**（布尔公式）是由变量 `x₁`、……、`xₙ` 和三种运算搭起来的表达式：`X ∨ Y`（disjunction，「或」）、`X ∧ Y`（conjunction，「与」）、`¬X`（negation，「非」）。给定一份把 1（真）或 0（假）赋给每个变量的 **assignment**（赋值），我们可以反复应用下面的规则来**求值**一个布尔公式：

```
 ∨ │ 0  1        ∧ │ 0  1        ¬ │
───┼─────       ───┼─────       ───┼───
 0 │ 0  1         0 │ 0  0        0 │ 1
 1 │ 1  1         1 │ 0  1        1 │ 0
```

若存在至少一份令公式求值为 1 的 **satisfying assignment**（可满足赋值），我们就说这个布尔公式是 **satisfiable**（可满足）的。**satisfiability problem**（可满足性问题），简称 SAT，问的就是给定的布尔公式是否可满足。下面我们将证明 associated type inference 能解 SAT——办法是把一个布尔公式编码成一条 conformance，让一份 valid 的 type witness 赋值对应一份真值的可满足赋值。

我们只需要考虑 SAT 问题的一种受限形式。我们约定：单个变量 `x` 或它的否定 `¬x` 叫做一个 **literal**（文字），而 **clause**（子句）是一个或多个 literal 的 disjunction，例如 `(¬x₁ ∨ x₂ ∨ ¬x₃)`。若一个公式是若干 clause 的 conjunction，我们说它处于 **conjunctive normal form**（合取范式），简称 CNF：

```
(¬x₁ ∨ x₂ ∨ x₃) ∧ (¬x₁ ∨ x₂ ∨ ¬x₃) ∧ (¬x₂ ∨ x₃) ∧ (x₁ ∨ x₂) ∧ (¬x₁ ∨ ¬x₂)
```

更精确地说，上面这个公式处于 3CNF——它还额外满足「没有任何 clause 含超过三个 literal」。事实上，任意布尔公式总能先转成 CNF、再转成 3CNF，且转换保持可满足性（或不可满足性）。因此就我们的目的而言，解 3SAT 就够了——SAT 问题限制在 3CNF 上的这一形式是众所周知的。

我们将把上面那个 3CNF 公式编码成一个 associated type inference 的实例，但显然这套编码对任意 3CNF 公式都成立。首先，我们需要一对 nominal type 来表示真和假：

```swift
struct T {}
struct F {}
```

然后我们声明一个对所有 3CNF 公式通用的 nominal type，叫 `Solver`，以及一个把我们这个具体 3CNF 公式的各条 clause 编码进去的 `Instance` protocol。最后，当我们写出 `Solver` 对 `Instance` 的 conformance 时，associated type inference 就会启动并解出 3SAT。我们先看 `Solver`：

```swift
struct Solver: Instance {
```

我们有两个 `literal(_:_:)` 的重载：

```swift
  func literal(_: T, _: F) {}
  func literal(_: F, _: T) {}
```

我们还有 `2³-1 = 7` 个 `clause(_:_:_:)` 的重载，对应每一组不全为假的真假三元组：

```swift
  func clause(_: T, _: F, _: F) {}
  func clause(_: F, _: T, _: F) {}
  func clause(_: T, _: T, _: F) {}
  func clause(_: F, _: F, _: T) {}
  func clause(_: T, _: F, _: T) {}
  func clause(_: F, _: T, _: T) {}
  func clause(_: T, _: T, _: T) {}
```

`Solver` 到此为止：

```swift
}
```

现在我们来填写 `Instance` protocol，在其中编码我们这个 3CNF 公式的变量与 clause。对每个变量 `xᵢ`，我们声明一个 associated type `XiP` 表示 literal `xᵢ`，再声明一个 associated type `XiN` 表示 literal `¬xᵢ`：

```swift
protocol Instance {
  associatedtype X1P; associatedtype X1N
  associatedtype X2P; associatedtype X2N
  associatedtype X3P; associatedtype X3N
```

我们还往 protocol 里加一串名为 `literal(_:_:)` 的方法，每个变量 `xᵢ` 一个，用来编码「`xᵢ` 与 `¬xᵢ` 是互补 literal」这个事实：

```swift
  func literal(_: X1P, _: X1N)
  func literal(_: X2P, _: X2N)
  func literal(_: X3P, _: X3N)
```

最后，我们加一串名为 `clause(_:_:_:)` 的方法，每条 clause 一个。要得到那三个参数类型，我们把 clause 里出现的每个 literal `xᵢ` 或 `¬xᵢ` 翻译成类型为 `XiP` 或 `XiN` 的参数；若某条 clause 的 literal 不足三个，就重复其中一个 literal。例如我们公式里的第一条 clause 是 `(¬x₁ ∨ x₂ ∨ x₃)`，它变成 `(_: X1N, _: X2P, _: X3P)`，以此类推：

```swift
  func clause(_: X1N, _: X2P, _: X3P)
  func clause(_: X1N, _: X2P, _: X3N)
  func clause(_: X2N, _: X3P, _: X3P)
  func clause(_: X1P, _: X2P, _: X2P)
  func clause(_: X1N, _: X2N, _: X2N)
}
```

上面这些为 Associated type inference 算法编码出了一串 disjunction：

1. 每个 `Instance.literal(_:_:)` 都以那两个 `Solver.literal(_:_:)` 重载为候选，所以每个 `XiP` 必须是 `T` 或 `F`，而 `XiN` 必须是它的否定。
2. 每个 `Instance.clause(_:_:_:)` 都以那七个 `Solver.clause(_:_:_:)` 重载为候选，于是我们得到一个 disjunction，其中每个 partial solution 都是该 clause 的一份可满足赋值——因为 clause 里至少有一个 literal 为真。

在我们这个例子里，associated type inference 找到唯一解，我们甚至能通过查看每个 `XiP` 的 type witness 把这份可满足赋值还原出来。例如，下面这行会打印 `(F, T, T)`：

```swift
print((Solver.X1P, Solver.X2P, Solver.X3P).self)
```

简单算一下就能确认 `{x₁ := 0, x₂ := 1, x₃ := 1}` 是一份可满足赋值：

```
(¬0 ∨ 1 ∨ 1) ∧ (¬0 ∨ 1 ∨ ¬1) ∧ (¬1 ∨ 1) ∧ (0 ∨ 1) ∧ (¬0 ∨ ¬1) = 1
```

关于如何解读我们这台「SAT 求解器」的输出，有一点需要注意。形式上，SAT 是一个答案为真或假的 **decision problem**（判定问题），它只问「是否**存在**至少一份可满足赋值」。而 associated type inference 会枚举**全部** valid 解并试图挑出最好的那个。我们这个示例公式不仅可满足，而且恰好有唯一的可满足赋值。一般而言，若 associated type inference 找到唯一解，**或者**因为有不止一个 valid 解而诊断出歧义，我们都能断定布尔公式可满足。若没有解，就没有可满足赋值。但这一切究竟**意味着**什么？

### Non-deterministic polynomial time

我们来到了理论计算机科学中最负盛名的思想之一。关于这个主题的经典教材是 Garey 与 Johnson 1979 年的《Computers and Intractability: A Guide to the Theory of NP-completeness》，而 MacCormick 2018 年的《What Can Be Computed?: A Practical Guide to the Theory of Computation》则是一本更平易的入门书。我们可以先描述一个解可满足性的**非确定性**算法。我们固定一种把真值赋值编码成符号串的方式；例如，按某个固定顺序写下赋给 `n` 个变量的 0 与 1。我们这个非确定性算法随后同时「猜出」全部 `2ⁿ` 份真值赋值，并把每份赋值与其他所有赋值并行地「检查」一遍——办法是求值公式得到真或假。只要至少一个线程输出成功，整个算法就输出成功，否则输出失败。

就非确定性算法而言，这一个是极其高效的。如果有人递给我们一份真值赋值，我们可以在 `O(n)` 步内**检查**它是不是一份可满足赋值，其中 `n` 是公式的长度。更一般地，若我们能用一个总在至多 `O(nᵏ)` 步内终止的算法检查给定解是否满足问题实例（`n` 是实例规模，`k` 是固定常数），我们就说这个判定问题属于 **non-deterministic polynomial time problems**（非确定性多项式时间问题）这一类，简称 NP。

我们要求检查阶段对所有输入都终止，这蕴含着它只使用有限的内存。在 1971 年的一篇论文里，Stephen A. Cook 用这个观察证明了：一个非确定性算法的执行可以用一个布尔公式来建模（这里的大致思路几乎就像是在搭一个有限的数字电路）。换句话说，**每一个** NP 问题都能翻译成一个布尔可满足性问题——而且重要的是，这套编码本身只花多项式的时间与空间（Cook 1971，《The complexity of theorem-proving procedures》）。

布尔可满足性是被发现的众多 **NP-complete** 问题中的第一个。NP-complete 问题是 NP 里「最难」的那批问题，因为 NP 中**其他**每一个问题都是它们的特例，而且它们彼此之间「一样难」。更一般地，若我们的问题能编码某个 NP-complete 问题，但我们的问题本身未必属于 NP，我们就只说这个问题是 **NP-hard** 的：

**定理.** Swift 的 associated type inference 是 NP-hard 的。

但这些问题为什么「难」？原因非常简单。没有机器能做到无限并行，所以我们没法真的按规定去**运行**一个非确定性算法——除非当然，我们把每一条可能的执行线程顺序地模拟一遍。特别地，看不出有什么办法能把一个非确定性**多项式时间**算法翻译成真实计算机上同样高效的确定性算法。

注意，上面那个 Associated type inference 算法的运行时间在最坏情况下是**指数级**的，原因是用了回溯搜索。我们可以做各种改进来缩小搜索空间，因而运行时间不必在**每个**实例上都是指数级。然而，如果我们真能设计出一个**总能**在多项式时间内解出 associated type inference 的算法，那么由上面那条定理，我们的算法将是相当了不起的——因为它能在多项式时间内解出**每一个** NP 问题。反过来，只要有人能证明**至少一个** NP 问题不能被确定性多项式时间算法解出，我们就能立刻对**每一个** NP-hard 问题下同样的结论，于是特别地，这将排除在多项式时间内解出 associated type inference 的可能性。

这当然就是著名的「P `=?` NP」问题，它至今仍未解决。关于这个问题的综述，见 Scott Aaronson 2017 年的《P `=?` NP》。

### Overload resolution

在现实的 Swift 程序里，associated type inference 每次面对的只有寥寥几条 requirement 和候选 witness，上面那个 Associated type inference 算法探索的搜索空间并不大。不过，这种「把 requirement 与候选 witness 相匹配」的做法，只是 expression type checker 所执行的 **overload resolution** 的一个特例。Swift 程序员有时会撞上那个问题的 NP-hardness——表现为 `the compiler is unable to type-check this expression in reasonable time`。也有人证明过 C♯ 语言里的 overload resolution 是 NP-hard 的（Eric Lippert 2007，《Lambda Expressions vs. Anonymous Methods, Part Five》），用的是与我们这套非常相似的 SAT 问题编码。

这里我们不展开解释，但事实上，associated type inference 可以看作 **exact cover with colors**（带颜色的精确覆盖）问题、即 XCC 问题的一个实例。XCC 当然也是 NP-complete 的，但就像 SAT 一样，人们已经设计出能高效解出许多 XCC 实例的巧妙算法。如果 associated type inference 所花的时间在真实项目里哪天变得不容忽视，这会是一个可能的未来方向。求解 XCC 与 SAT 的算法在 Knuth 2022 年的《The Art of Computer Programming: Volume 4B: Combinatorial Algorithms》中有讨论。最后，关于 SAT 问题另一本好参考是 Schöning 与 Torán 2013 年的《The Satisfiability Problem: Algorithms and Analyses》。

```
* * *
```

## Source Code Reference

### Global Conformance Lookup

关键源文件：

- `include/swift/AST/ConformanceLookup.h`
- `lib/AST/ConformanceLookup.cpp`
- `lib/AST/ConformanceLookupTable.h`
- `lib/AST/ConformanceLookupTable.cpp`
- `include/swift/AST/DeclContext.h`

**`lookupConformance()`**（function）：执行一个类型对一个 protocol 的 global conformance lookup。注意，若这是一条 conditional conformance，本函数**不**检查 conditional requirement。要检查 conditional requirement，请改用 `extensions.tex` 的 Source Code Reference 一节里的 `checkConformance()`。

### Conformance Lookup Table

关键源文件：

- `lib/AST/ConformanceLookupTable.h`
- `lib/AST/ConformanceLookupTable.cpp`
- `include/swift/AST/DeclContext.h`

**`ConformanceLookupTable`**（class）：某个 nominal type declaration 的 conformance lookup table。每个 `NominalTypeDecl` 都有一份 conformance lookup table，但它不向 global conformance lookup 的实现之外暴露。

**`IterableDeclContext`**（class）：由 `NominalTypeDecl` 和 `ExtensionDecl` 继承的基类。

- `getLocalConformances()` 返回直接声明在这个 nominal type 或 extension 上的 local conformance 列表。

**`NominalTypeDecl`**（class）：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getAllConformances()` 返回声明在这个 nominal type、它的各个 extension 上，以及从它的 superclass（若有）继承来的全部 conformance 的列表。

### Operations on Conformances

关键源文件：

- `include/swift/AST/ProtocolConformanceRef.h`
- `include/swift/AST/ProtocolConformance.h`
- `lib/AST/ProtocolConformanceRef.cpp`
- `lib/AST/ProtocolConformance.cpp`

**`ProtocolConformanceRef`**（class）：一条 protocol conformance。它的表示塞得进单个指针，所以这个类型的值按值传递很便宜。invalid conformance 用空指针编码，对 invalid conformance 调用下面大多数操作都是错误。

通常 `ProtocolConformanceRef` 的实例是由 substitution 或 global conformance lookup 得到的。直接构造它们也是可以的：

- 要得到一条 invalid conformance，调用默认构造函数，或等价地调用静态方法 `ProtocolConformanceRef::forInvalid()`。
- 要包裹一条 concrete conformance，调用那个接收 `ProtocolConformance *` 的单参数构造函数。
- 要得到一条 abstract conformance，调用静态方法 `forAbstract()`。

`ProtocolConformanceRef` 可以被拆开：

- `isInvalid()` 检查这条 conformance 是否无效。
- `isAbstract()` 检查这条 conformance 是否是 abstract 的。
- `getAbstract()` 在这条 conformance 是 abstract 时返回其中存的 `AbstractConformance *`，否则断言失败。
- `isConcrete()` 检查这条 conformance 是否是 concrete 的。
- `getConcrete()` 在这条 conformance 是 concrete 时返回其中存的 `ProtocolConformance *`，否则断言失败。

通常我们并不关心一条 protocol conformance 是 abstract 还是 concrete，因为我们转而使用 `ProtocolConformanceRef` 下面这些对两者都适用的方法：

- `getType()` 返回 conforming type。
- `getProtocol()` 返回被遵循的 `ProtocolDecl`。
- `getTypeWitness()` 返回给定 associated type declaration 的 type witness。
- `getAssociatedConformance()` 返回被遵循 protocol 的某条 associated conformance requirement 所对应的 associated conformance。
- `subst()` 返回把一张 substitution map 应用到这条 conformance 上所得的新 protocol conformance。

与 `Type`、`GenericSignature`、`SubstitutionMap` 一样，conformance 是不可变的、且唯一分配的。因此可以用 `operator==` 重载来判断 conformance 相等。这一点取决于 type sugar，除非该 conformance 是 **canonical** 的。

- `isCanonical()` 回答这条 conformance 是否 canonical。
- `getCanonical()` 返回与它等价的 canonical conformance。

**`AbstractConformance`**（class）：一条 abstract protocol conformance。这个类很少被直接使用，因为它的两个操作在 `ProtocolConformanceRef` 上都有。

- `getType()` 返回 conforming type。
- `getProtocol()` 返回被遵循的 `ProtocolDecl`。

conforming type 与 protocol 都相同的 abstract conformance，作为指针也相等。一条 abstract conformance 是 canonical 的，当且仅当其 conforming type 是 canonical type。

**`ProtocolConformance`**（class）：一条 concrete protocol conformance。Concrete protocol conformance 总是按指针传递。Concrete conformance 可以带 conditional requirement；这一点在 `extensions.tex` 的 Conditional Conformances 一节和它的 Source Code Reference 一节有说明。

- `getType()` 返回 conforming type。
- `getProtocol()` 返回被遵循的 protocol。
- `getTypeWitness()` 返回某个 associated type 的 type witness。
- `getAssociatedConformance()` 返回 protocol requirement signature 里某条 conformance requirement 所对应的 associated conformance。
- `subst()` 返回把一张 substitution map 应用到这条 conformance 上所得的 protocol conformance。

`ProtocolConformance` 类是下面这个类层次的根：

```
ProtocolConformance
├── RootProtocolConformance
│   ├── NormalProtocolConformance
│   └── SelfProtocolConformance
├── InheritedProtocolConformance
└── SpecializedProtocolConformance
```

> 译注：原书此处是一张 TikZ 图（题为「The `ProtocolConformance` class hierarchy」），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

**`RootProtocolConformance`**（class）：`NormalProtocolConformance` 与 `SelfProtocolConformance` 的抽象基类。继承自 `ProtocolConformance`。

**`NormalProtocolConformance`**（class）：一条 normal protocol conformance。`RootProtocolConformance` 的子类。

- `getDeclContext()` 返回 conforming declaration context，要么是一个 nominal type declaration，要么是一个 extension。
- `getGenericSignature()` 返回 conforming context 的 generic signature。

normal conformance 总是 canonical 的。

**`InheritedProtocolConformance`**（class）：一条 inherited protocol conformance。`ProtocolConformance` 的子类。

- `getInheritedConformance()` 返回 base conformance，它必定是 normal 或 specialized 的。

一条 inherited conformance 是 canonical 的，当且仅当其 conforming type 是 canonical type 且其 base conformance 是 canonical conformance。

**`SpecializedProtocolConformance`**（class）：一条 specialized protocol conformance。`ProtocolConformance` 的子类。

- `getGenericConformance()` 返回底下那条 normal conformance。
- `getSubstitutionMap()` 返回 conformance substitution map。

一条 specialized conformance 是 canonical 的，当且仅当其 conformance substitution map 是 canonical 的。要把一条 specialized conformance 规范化，我们把其 substitution map 的各元素规范化，再构造一条新的 specialized conformance。

### Type Substitution

关键源文件：

- `include/swift/AST/SubstitutionMap.h`
- `lib/AST/TypeSubstitution.cpp`

**`SubstitutionMap`**（class）：我们在 `substitution-maps.tex` 的 Source Code Reference 一节讨论过 substitution map。回忆一下，一张 substitution map 存着一串 conformance，其 input generic signature 里的每条 conformance requirement 各一条。静态方法 `get()` 的三个重载用来构造 substitution map。它们的区别在于 replacement type 与 conformance 的给出方式：

`get(GenericSignature, ArrayRef<Type>, ArrayRef<ProtocolConformanceRef>)`：

用一个 input generic signature、一个 replacement type 数组和一个 conformance 数组构建新的 substitution map。第一个数组的元素与该 signature 的 generic parameter 一一对应，第二个数组的元素与该 signature 的 conformance requirement 一一对应。

`get(GenericSignature, ArrayRef<Type>, LookupConformanceFn)`：

用一个 input generic signature、一个 replacement type 数组和一个 conformance 数组构建新的 substitution map。这种形式不提供 conformance 数组，而是接收一个回调，对每条 conformance requirement 调用一次。

`get(GenericSignature, TypeSubstitutionFn, LookupConformanceFn)`：

通过调用一对回调来产出每个 replacement type 和 conformance，从而构建新的 substitution map。这个重载接收两个回调，分别被调用来产出每个 replacement type 和 conformance。

最后，静态方法 `getProtocolSubstitutions()` 在给定一条对某 protocol 的 conformance 时，为该 protocol 的 protocol generic signature 构建一张 protocol substitution map。

**`TypeSubstitutionFn`**（type alias）：`SubstitutionMap::get()` 第三种形式里 replacement type 回调的类型。

```cpp
using TypeSubstitutionFn
  = llvm::function_ref<Type(SubstitutableType *dependentType)>;
```

当这个回调与 `SubstitutionMap::get()` 一起使用时，参数类型总是 `GenericTypeParamType *`。

**`LookupConformanceFn`**（type alias）：`SubstitutionMap::get()` 的 conformance lookup 回调的类型签名。

```cpp
using LookupConformanceFn = llvm::function_ref<
    ProtocolConformanceRef(InFlightSubstitution &IFS,
                           CanType origType,
                           ProtocolDecl *proto)>;
```

其中 `origType` 与 `proto` 是正在构造的这张 substitution map 的 input generic signature 里某条 conformance requirement 的 subject type 与 protocol declaration。需要的话，可以用 `InFlightSubstitution` 实例这样恢复出代入后的 subject type：

```cpp
Type substType = origType.subst(IFS);
```

**`LookUpConformanceInModule`**（struct）：一个打算与 `SubstitutionMap::get()` 配合用作 conformance lookup 回调的回调。它以 `LookupConformanceFn` 的签名重载了 `operator()`，用给定 requirement 代入后的 subject type 和 protocol 执行一次 global conformance lookup。这个回调的实例不带参数构造。例如：

```cpp
auto subMap = SubstitutionMap::get(genericSig, replacementTypes,
                                   LookUpConformanceInModule());
```

**`LookUpConformanceInSubstitutionMap`**（struct）：一个打算与 `SubstitutionMap::get()` 配合用作 conformance lookup 回调的回调。它以 `LookupConformanceFn` 的签名重载了 `operator()`，往另一张 substitution map 里执行 local conformance lookup（见本章 Abstract Conformances 一节）。构造时需要另一张 `SubstitutionMap`。

例如，若 `genericSig` 与 `subMap` 的 input generic signature 相同、只是去掉了若干 requirement，我们可以这样为 `genericSig` 构造一张 substitution map：

```cpp
auto newMap = SubstitutionMap::get(
    genericSig,
    subMap.getReplacementTypes(),
    LookUpConformanceInSubstitutionMap{subMap});
```

**`TypeSubstituter::transformDependentMemberType()`**（method）：实现上面的 Substitute dependent member type 算法。

### Associated Type Inference

关键源文件：

- `lib/Sema/AssociatedTypeInference.cpp`

**`TypeWitnessRequest`**（class）：惰性解析一条 normal conformance 里单个 type witness 的 request evaluator request。先尝试 qualified lookup，失败则求值 `TypeWitnessesRequest`。

**`TypeWitnessesRequest`**（class）：解析一条 normal conformance 里全部 type witness 的 request evaluator request，先尝试查找，再走 associated type inference。

**`AssociatedConformanceRequest`**（class）：惰性查找一条从源码解析而来的 normal conformance 的某条 associated conformance 的 request evaluator request。它计算 requirement 代入后的 subject type 并调用 global conformance lookup。

**`InferredAssociatedTypesByWitness`**（struct）：一个 partial solution。

**`InferredAssociatedTypesByWitnesses`**（type alias）：一个 disjunction，表示为 partial solution 的 `llvm::SmallVector`。

**`InferredAssociatedTypesByWitnesses`**（type alias）：problem instance，表示为若干对（pair）的 `llvm::SmallVector`，其中每对的第一个元素是一条 value requirement，第二个是一个 disjunction。

> 译注：原书连续两条都写作 `InferredAssociatedTypesByWitnesses`，但说明的分明是两个不同的类型（一个是 disjunction，一个是 problem instance），疑为笔误；源码里后者实际叫 `InferredAssociatedTypes`。

**`AssociatedTypeInference`**（class）：associated type inference 求解器。

- `inferTypeWitnessesViaValueWitnesses()` 构建 problem instance，它由每条提到给定 associated type 集合的 value requirement 各贡献一个 disjunction 组成。
- `getPotentialTypeWitnessesFromRequirement()` 为一条 value requirement 构建一个 disjunction——办法是找出这条 requirement 的全部 candidate value witness，并为每一个构造一个 partial solution。
- `getPotentialTypeWitnessesByMatchingTypes()` 从一条 value requirement 与一个 candidate value witness 的配对中构建一个 partial solution。
- `solve()` 实现上面的 Associated type inference 算法。

---

> 译自 `docs/Generics/chapters/conformances.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
