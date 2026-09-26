# Archetypes（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/archetypes.tex`（《Compiling Swift Generics》一书的「Archetypes」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：archetype 是「自带 generic signature 的 type parameter」——不需要额外上下文就能回答「它 conform 到哪些 protocol、superclass 是什么、有没有 class 约束」。本库在没有运行时的情况下判断一个泛型参数能不能定下布局，问的正是同一批问题：`ClassBoundGenericParameterAnalysis` 从 requirement signature 里挖出的，就是本章所说的 local requirement 中「签名本身已经钉死」的那部分。本章的 type parameter graph 则给了 reduced type 与等价类一个直观形状，本库读 `__swift5_assocty` 解析 associated type field 时走的就是这张图上的边。对应关系在个别地方以「译注」标出；译文正文不夹带本库的实现细节。
>
> **术语**：书中定义的术语一律保留英文（archetype、primary archetype、generic environment、contextual type、interface type、local requirement、type parameter graph、reduced type、potential archetype、forwarding substitution map、global conformance lookup、union-find……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Generic Signature Queries 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。原书的 `T` 对应 `τ_0_0`，`U` 对应 `τ_0_1` |
> | `⟦T⟧` | type parameter `T` 的 **primary archetype**。需要指明它属于哪个声明 `d` 的 generic environment 时写 `⟦T⟧_d` |
> | `in(...)`、`out(...)` | 把类型**映入** / **映出** generic environment（interface type ↔ contextual type）。需要指明是哪个 signature 的 environment 时写 `in_H(...)`、`out_H(...)` |
> | `Type(G)`、`Type^ctx(G)` | generic signature `G` 的 interface type 集合、contextual type 集合（原书记作 `Type(G)` 与 `Type(⟦G⟧)`） |
> | `Sub(G → H)`、`Sub^ctx(G → H)` | input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 集合，replacement type 分别为 interface type / contextual type |
> | `1_G`、`Fwd_G` | `G` 的 identity substitution map、forwarding substitution map（原书把后者记作 `1_⟦G⟧`） |
> | `⊗` | 施加运算：`X ⊗ Σ` 是对类型施加 substitution map，`Σ ⊗ Σ′` 是 substitution map composition，`P ⊗ X` 是 global conformance lookup |
> | `[T: P]`、`[T: C]`、`[T: AnyObject]` | conformance requirement / superclass requirement / layout requirement；也用来写一个具体的 conformance |
> | `[T == U]`、`[T == X]` | same-type requirement |
> | `G ⊢ [T: P]` | requirement `[T: P]` 可从 `G` 推导出来 |
> | `[P]A` | protocol `P` 的 associated type `A`；`T.[P]A` 是以 `T` 为 base 的 dependent member type |
> | `[Self.U: Q]_P` | protocol `P` 的一条 associated conformance requirement |
> | `src(e)`、`dst(e)` | 有向图中边 `e` 的起点与终点 |
> | `FORWARD(t)`、`TYPE(t)`、`PROTO(t)`、`MEMBERS(t)` | potential archetype `t` 的四个字段（见本章 The Archetype Builder 一节） |

---

一个 archetype 把一个 reduced type parameter 和一个 generic signature 打包在一起，这两样语义对象我们在 `generic-signatures.tex` 里见过。这种表示是**自描述**的，所以它不需要额外上下文就能回答 protocol conformance 之类的问题。于是 archetype 在很多方面表现得像一个具体类型；它是满足其 type parameter 各条 requirement 的那个「最一般」的具体类型。（回忆一下，type parameter 本质上只是一个**名字**，要解释它还得另外配一个 generic signature。）Archetype 是把 type parameter **映入一个 generic environment** 得到的，而 generic environment 是从 generic signature 派生出来的对象。同一个 generic signature 可以实例化出多个 environment，每个 environment 生成一族互不相同的 archetype。其中恰好有一个是 **primary** generic environment，它产生的 archetype 叫 **primary archetype**。我们先讲这一种。

Primary generic environment 在 type parameter 与 primary archetype 之间定下一组对应关系：

- **映入一个 environment**：递归地把给定 interface type 里的 type parameter 换成它们在给定 primary generic environment 里的 archetype。
- **映出一个 environment**：递归地把 primary archetype 换回它们的 reduced type parameter。

映入 environment 得到的类型里不再含有 type parameter，取而代之的可能是 primary archetype。这种类型我们叫 **contextual type**。

在 generic 函数体里出现的表达式中，contextual type 和 primary archetype 取代了 interface type 的位置，但 archetype 并不作为一个独立概念浮到语言模型层面上来——它只是一次表示形式的变化。SILGen 把表达式下降成消费和产生 SIL value 的 SIL 指令，所以 SIL value 的类型也是 contextual type。最后，当 IRGen 为一个 generic 函数生成代码时，archetype 变成一个个**值**，代表调用方传进来的 runtime type metadata。

我们会看到，interface type 上的各种操作——比如 generic signature query 和 type substitution——在 contextual type 的世界里都有对应物。从实用角度讲，搞懂这些对编译器开发者很重要。Archetype 的表示方式还会引出本章 The Type Parameter Graph 一节的 **type parameter graph**，它给了我们一个看待 generic signature 的新角度。最后，在本章 The Archetype Builder 一节，我们会简述 Swift 3 那套泛型实现的历史：它建立在构造有限 type parameter graph 之上，archetype 在那里是唯一的事实来源。

### Nesting

一个嵌套的 generic 声明，只要它的 generic signature 与外层不同（因为它引入了新的 generic parameter 或新的 requirement），就会引入一个全新的 primary generic environment；我们**不**从外层作用域「继承」primary archetype。所有 primary archetype，包括代表外层 generic parameter 的那些，都由最内层的 environment 实例化。（如果内层声明既没声明新的 generic parameter 也没声明新的 requirement，它的 generic signature 与父上下文相同，因而 generic environment 也相同。）

这使我们能正确建模那种「对外层 generic parameter 施加新 requirement」的嵌套声明，也就是 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）的 Requirements 一节讨论过的情形。Swift 3 之前不支持这种写法，因为那时外层的 primary archetype 是被复用的。下面这个简单程序展示了这一行为：

```swift
struct Box<T> {
  var contents: T?

  mutating func take() -> T {
    let value: T = self.contents!
    self.contents = nil
    return value
  }
  
  func compare(_ other: T) -> Bool where T: Equatable {
    guard let value: T = self.contents else { return false }
    return value == other
  }
}
```

`take()` 和 `compare()` 的 generic signature 并不相同：`take()` 继承 struct `Box` 的 generic signature，`compare()` 则多加了一条 conformance requirement。类型写法「`T`」在它出现的所有源码位置都解析到**同一个** generic parameter type `T`（即 `τ_0_0`）。然而这个 generic parameter 在两个函数各自的 generic environment 里映到了两个不同的 archetype。于是表达式「`self.contents`」在 `take()` 和 `compare()` 里的类型其实是不一样的。我们用记号 `⟦T⟧_d` 表示把 type parameter `T` 映入某个声明 `d` 的 generic environment 所得的 archetype。这里我们有两个 archetype：

1. `⟦T⟧_take`，它不 conform 到任何 protocol。
2. `⟦T⟧_compare`，它 conform 到 `Equatable`。

表达式 type checker 知道这件事，而且不需要手工把当前上下文的 generic signature 一路传下去，因为它操作的是 archetype 而不是 type parameter。

### Generic environment kinds

Generic environment 有三种。每一种的实例都按输入参数的组合做唯一化分配：

- 前面已经说过，每个 generic signature 恰好有一个 **primary generic environment**，产生 primary archetype。

  ```
  ┌─ primary generic environment ──────────────┐
  │  generic signature                         │
  └────────────────────────────────────────────┘
  ```

  > 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

  Primary generic environment 为了打印 archetype 时好看，保留了 generic parameter 的 sugar 名字，所以一个 primary generic environment 依赖于它那个 generic signature 的**指针身份**：两个 canonically 相等但 type sugar 不同的 generic signature，会实例化出两个不同的 primary generic environment。

- 当一个声明带有 opaque result type 时，我们可以创建一个 **opaque generic environment**，它由 owner declaration 的 generic signature 的一张 substitution map 参数化：

  ```
  ┌─ opaque generic environment ───────────────────────────────┐
  │  opaque result declaration   │   substitution map          │
  └────────────────────────────────────────────────────────────┘
  ```

  > 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

  与 primary archetype 不同，**opaque archetype** 不受 owner declaration 词法作用域的限制；只要 owner declaration 可见，它们就能出现在那里。它们在 substitution 下的行为也不一样。Interface type 里出现 opaque archetype 是合法的，尤其是 owner declaration 自己的返回类型里就含有一个。细节见 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）。

  > 译注：本库从二进制里把 `some P` 还原成源码拼写，走的正是 opaque generic environment 这条线——opaque type descriptor 记录 underlying type，引用点记录那张 substitution map。见 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md) 与 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

- 当一个 existential value 在 call expression 处被打开时，会创建一个 **existential generic environment**。从这种 environment 实例化出来的 **existential archetype** 代表存放在该 existential value 内部的那个具体 payload。

  ```
  ┌─ existential generic environment ──────────────────────────────────┐
  │  generic signature   │   constraint type   │   unique ID           │
  └────────────────────────────────────────────────────────────────────┘
  ```

  > 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

  每个 opening expression 都拿到一个新的 unique ID，因而也拿到一个新的 existential generic environment。在 AST 里，existential archetype 不能「逃出」它的 opening expression；在 SIL 里，它们由一条 opening 指令引入，同样受控制流图上支配关系的作用域限制。Existential type 我们会在 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)） 里讨论。

### Archetype equality

关于 contextual type 的几点说明：

1. 每个 primary archetype 都是 contextual type。更一般地，contextual type 是一个含有 primary archetype 的具体类型，比如由 primary archetype `⟦T⟧` 构成的 `Array<⟦T⟧>`。
2. 像 `Array<Int>` 这样完全具体的类型，既是 interface type 又是 contextual type。
3. 像 `Array<τ_0_0>` 这样的 interface type **不是** contextual type。
4. 一个 contextual type 里出现的 primary archetype 永远只来自同一个 generic environment。
5. 来自非 primary generic environment 的 archetype 可以同时出现在 interface type 和 contextual type 里，不过现在先不管它们。

下面设 `G` 是一个 generic signature，照旧把 `G` 的全部 interface type 的集合记作 `Type(G)`。现在我们再约定：`Type^ctx(G)` 是所有含 `G` 的 primary archetype 的 contextual type 的集合。这样，映入和映出 environment 就可以理解成给了我们一对函数：

```
in  : Type(G)     ⟶ Type^ctx(G)
out : Type^ctx(G) ⟶ Type(G)
```

在 `generic-signatures.tex` 的 Valid Type Parameters 一节，我们在 `G` 的 valid type parameter 上定义了 reduced type equality 关系；在同一文件的 Generic Signature Queries 一节，我们又通过 reduced type 的递归定义把它推广到整个 `Type(G)`。Archetype 的 type parameter 是 reduced type，这一点在类型等价上意味着：

1. 若对 type parameter `T` 与 `U` 有 `G ⊢ [T == U]`，则 `in(T)` 与 `in(U)` 给出指向同一个 archetype 的两个相等指针。在 archetype 上，reduced type equality、canonical type equality 和 type pointer equality 这三种关系是重合的。

2. 若对某个 type parameter `T` 与具体类型 `X` 有 `G ⊢ [T == X]`，我们就定义 `in(T) := in(X)`。被钉死到某个具体类型的 type parameter 不用 archetype 表示；我们改为递归地映入那个具体类型。

3. 若 `T` 是某个 interface type，则 `out(in(T))` 与用 `generic-signatures.tex` 的 Compute reduced type 算法算出的 `T` 的 reduced type canonically 相等。

4. 若两个 interface type 在 reduced type equality 下等价，则对应的 contextual type 在 canonical type equality 下等价。

合起来看，`in` 操作加上 canonical type equality 忠实地表示了一个 generic signature 的等价类结构。接下来我们看 archetype 如何把剩下的 generic signature query 也一并吸收进来。

## Local Requirements

要理解一个 type parameter `T ∈ Type(G)` 的行为，可以去看所有能从 `G` 推导出来、且 subject type 为 `T` 的 conformance requirement、superclass requirement 和 layout requirement。用 `generic-signatures.tex` 的 Generic Signature Queries 一节那些 query 就能把它们取出来，但那些 query 要同时接收一个 `G` 和一个 `T`——也就是说调用方必须自己记着 `G`。如果我们手上换成一个代表 `G` 中的 `T` 的 archetype，就可以直接查阅记录在 archetype 自身里的一份 **local requirement** 清单。下面我们假装手上是一个 primary archetype `⟦T⟧ ∈ Type^ctx(G)`，但本节说的一切对其他种类的 archetype 同样成立。一个 archetype `⟦T⟧` 记录下面这些东西：

- **Required protocols**：所有使 `G ⊢ [T: P]` 成立的 protocol `P` 的列表。这是 `getRequiredProtocols()` 这个 generic signature query 的结果。
- **Superclass bound**：一个使 `G ⊢ [T: C]` 成立的 class type `C`。这是 `getSuperclassBound()` query 的结果。
- **Requires class flag**：`G ⊢ [T: AnyObject]` 时为真。这是 `requiresClass()` query 的结果。
- **Layout constraint**：比上一条更细的视角，用来区分 Objective-C 与 Swift 原生的引用计数。这是 `getLayoutConstraint()` query 的结果。

创建 archetype 时，我们用 `getLocalRequirements()` 这个 generic signature query 一次性把上面所有信息收齐。

> 译注：本库在没有运行时的情况下要判断「一个泛型参数能不能定下布局」，问的正是这几条 local requirement。`ClassBoundGenericParameterAnalysis` 一遍扫过 requirement signature，挖出的就是其中「不需要任何 generic argument 就已经钉死」的部分——class-bound（`layout(.class)` / superclass / class-bound protocol）以及被 same-type requirement 钉到具体类型上的参数。见 [SwiftLayout.md](../Modules/SwiftLayout.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Qualified name lookup

Archetype 可以充当 qualified name lookup（`compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）的 Name Lookup 一节）的 base type。可见的成员是：该 archetype 的 required protocol 的成员、superclass declaration 的成员，最后还有 superclass 那些具体 protocol conformance 的成员。这就解释了 base type 是 archetype 的 member reference expression 该怎么做类型检查。

### Global conformance lookup

看下面两个声明，配上 generic signature `<Box, Elt where Box: Base<Elt>, Box: Proto>`：

```swift
protocol OtherProto { func otherRequirement() }
protocol Proto { func requirement() }
class Base<Elt>: OtherProto { func otherRequirement() }
```

如果我们手上有一个类型为 `⟦Box⟧` 的值，那么调用 `requirement()` 必须经 witness table 派发；而调用 `otherRequirement()` 可以直接调到具体的 witness 上，哪怕我们并不知道 `⟦Box⟧` 的具体 replacement type 是什么。

也就是说，我们希望 global conformance lookup 在拿到 archetype `⟦Box⟧` 和 `Proto` 时返回一个 abstract conformance，而拿到 `OtherProto` 时返回一个具体的 conformance：

```
Proto      ⊗ ⟦Box⟧ = [⟦Box⟧: Proto]
OtherProto ⊗ ⟦Box⟧ = [Base<⟦Elt⟧>: OtherProto]
```

可见 abstract conformance 的 subject type 可以是 archetype，不限于 type parameter。还要注意第二个 conformance 是由 normal conformance `[Base<τ_0_0>: OtherProto]` 配上这张 conformance substitution map 得到的：

```
[Base<τ_0_0>: OtherProto] ⊗ {τ_0_0 ↦ ⟦Elt⟧}
    = [Base<⟦Elt⟧>: OtherProto]
```

replacement type 为 contextual type 的 substitution map 我们马上就会讲，但先把上面这套 global conformance lookup 的行为形式化。

回忆一下，面对一个 type parameter 时，`conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Global conformance lookup 算法返回一个 abstract conformance（见该文件的 Abstract Conformances 一节），并不检查这个 conformance 是否真的成立。现在我们把这个算法扩展到 archetype 上，得到一种更有用、能区分若干情形的行为。设 `⟦T⟧` 是一个 generic signature 为 `G` 的 archetype，`P` 是一个 protocol：

1. 若对某个 class type `C` 有 `G ⊢ [T: C]`，且 `C` conform 到 `P`，则该 archetype **具体地 conform** 到 `P`。Class type `C` 里可能含有 type parameter，所以 global conformance lookup 会在 `in(C)` 上递归调用自身：

   ```
   P ⊗ ⟦T⟧ := P ⊗ in(C) = [in(C): P]
   ```

   结果实际上还会再包一层 **inherited conformance**——回忆 `conformances.tex`，它的作用就是让这个 conformance 的 conforming type 变成 `⟦T⟧` 而不是 `in(C)`。

2. 若 `G ⊢ [T: P]`，则该 archetype **抽象地 conform**，于是 global conformance lookup 返回一个 abstract conformance：

   ```
   P ⊗ ⟦T⟧ := [⟦T⟧: P]
   ```

3. 否则 `⟦T⟧` 不 conform 到 `P`，global conformance lookup 返回一个 invalid conformance。

当一个 abstract conformance 的 subject type 是 archetype 时，我们规定 type witness projection 与 associated conformance projection 要把结果映入该 archetype 的 generic environment。复述一下：当 abstract conformance 的 subject type 是 type parameter `T` 时，`[P]A` 的 type witness 是 dependent member type `T.[P]A`，而 `[Self.U: Q]_P` 的 associated conformance 是 abstract conformance `[T.U: Q]`。所以当 subject type 是 archetype `⟦T⟧` 时，我们还必须把这个 type witness 或 associated conformance 映入 environment：

```
[P]A          ⊗ [⟦T⟧: P] := in(T.[P]A) = ⟦T.[P]A⟧
[Self.U: Q]_P ⊗ [⟦T⟧: P] := Q ⊗ in(T.U) = [⟦T.U⟧: Q]
```

> 译注：本库把 conformance 归属到具体的 extension 容器、并按 conformance 投影 protocol witness table 槽位时，处理的正是同一件事的「读回来」方向——witness 是具体的还是抽象的、type witness 该记在哪个 conformance 名下。见 [PerConformanceAttribution.md](../PerConformanceAttribution.md) 与 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

## Primary Archetypes

回忆一下，`Sub(G → H)` 是 input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 的集合，也就是说它们的 replacement type 都是 interface type。为了理解原始类型是 contextual type 时 type substitution 的行为，我们给 `⊗` 运算定义一种新形式：

```
Type^ctx(G) ⊗ Sub(G → H) ⟶ Type(H)
```

要把 substitution map `Σ` 施加到 contextual type `Y ∈ Type^ctx(G)` 上，我们先把这个 contextual type 映出它的 environment，再把 substitution map 施加到得到的 interface type 上：

```
Y ⊗ Σ = out(Y) ⊗ Σ
```

只要 `Σ` 的 replacement type 是 interface type，结果就一定是 interface type，与原始类型是 interface type 还是 contextual type 无关。

Substitution map 的 replacement type 也可以是 contextual type。这一点在 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Generic Arguments 一节很重要，所以先把记号引进来。我们把 replacement type 取自 `Type^ctx(H)` 的 substitution map 的集合记作 `Sub^ctx(G → H)`。这样，只要 `Σ` 的 replacement type 是 contextual type，结果就一定是 contextual type，同样与原始类型是 interface type 还是 contextual type 无关：

```
Type(G)     ⊗ Sub^ctx(G → H) ⟶ Type^ctx(H)
Type^ctx(G) ⊗ Sub^ctx(G → H) ⟶ Type^ctx(H)
```

Substitution map composition 也照此推广：

```
Sub(F → G)     ⊗ Sub^ctx(G → H) ⟶ Sub^ctx(F → H)
Sub^ctx(F → G) ⊗ Sub^ctx(G → H) ⟶ Sub^ctx(F → H)
```

### Forwarding substitution map

在表达式 type checker、SILGen 以及其他会出现 contextual type 的地方，有一张特殊的 substitution map 经常派上用场。设 `G` 是一个 generic signature，`G` 的 **forwarding substitution map** 记作 `Fwd_G`，它把 `G` 的每个 generic parameter `τ_d_i` 送到 `G` 的 primary generic environment 里对应的 contextual type `in(τ_d_i)`：

```
Fwd_G := {…, τ_d_i ↦ in(τ_d_i), …}
```

注意 `Fwd_G ∈ Sub^ctx(G → G)`。Forwarding substitution map 长得很像 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Composition 一节里的 identity substitution map `1_G ∈ Sub(G → G)`。回忆一下，后者把每个 generic parameter 送到它自己：

```
1_G := {…, τ_d_i ↦ τ_d_i, …}
```

若 `X ∈ Type(G)` 是 interface type、`Y ∈ Type^ctx(G)` 是 contextual type，我们可以把 `1_G` 和 `Fwd_G` 分别施加到它们身上：

```
X ⊗ 1_G   = X
X ⊗ Fwd_G = in(X)
Y ⊗ 1_G   = out(Y) ⊗ 1_G   = out(Y)
Y ⊗ Fwd_G = out(Y) ⊗ Fwd_G = in(out(Y)) = Y
```

换句话说：

- **identity substitution map** `1_G` 让 interface type 原样不动，同时把 contextual type 映出 environment。
- **forwarding substitution map** `Fwd_G` 让 contextual type 原样不动，同时把 interface type 映入 environment。

利用这一点，我们可以在 replacement type 为 contextual type 与为 interface type 的两种 substitution map 之间互相转换：在右边复合上 identity 或 forwarding substitution map 即可。若 `Σ ∈ Sub(G → H)` 而 `Σ′ ∈ Sub^ctx(G → H)`，则有：

```
Σ  ⊗ Fwd_H ∈ Sub^ctx(G → H)
Σ′ ⊗ 1_H   ∈ Sub(G → H)
```

而且，若 `X ∈ Type(G)`，则：

```
X ⊗ (Σ  ⊗ Fwd_H) = in_H(X ⊗ Σ)
X ⊗ (Σ′ ⊗ 1_H)   = out_H(X ⊗ Σ′)
```

最后，substitution map 还支持一个 **map replacement types out of environment** 操作，它比「复合上 identity substitution map」更直接：

```
out_H : Sub^ctx(G → H) ⟶ Sub(G → H)
```

### Invariants

在实现里，有一对谓词用来区分 interface type 和 contextual type：

- `hasTypeParameter()` 判断该类型是否含有 type parameter。
- `hasPrimaryArchetype()` 判断该类型是否含有 primary archetype。

某段编译器逻辑只接受 interface type、或者只接受 contextual type 时，就用这两个谓词检查前置条件。一般来说，断言的是**相反**那个条件的否定：只接受 interface type 的逻辑，应当断言给定类型不含 archetype；只接受 contextual type 的逻辑，应当断言该类型不含 type parameter。

## The Type Parameter Graph

设 `G` 是 generic signature `<τ_0_0 where τ_0_0: Sequence>`，考虑 type parameter `τ_0_0.Element`。理解 `in(τ_0_0.Element)` 的一种方式是：我们从 archetype `⟦τ_0_0⟧` 出发，沿一条标着「`.Element`」的边「跳」一步就到了 `⟦τ_0_0.Element⟧`。同理，要求 `in(τ_0_0.Iterator.Element)`，我们从 `⟦τ_0_0⟧` 出发先走一步到 `⟦τ_0_0.Iterator⟧`，再走一步——结果又落回 `⟦τ_0_0.Element⟧`，因为 `τ_0_0.Element` 正是 `τ_0_0.Iterator.Element` 的 reduced type：

```
                        .Iterator
        τ_0_0 ────────────────────────────→ τ_0_0.Iterator
            ╲                              ╱
    .Element ╲                            ╱ .Element
              ╲                          ╱
               ↘                        ↙
                     τ_0_0.Element
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

我们要定义一个叫 **type parameter graph** 的对象：在这张图里，valid type parameter 是**路径**，而 type parameter 的等价类（也就是 archetype）是**顶点**。两个等价的 type parameter 对应两条终点相同的路径。后面我们还会研究别的有向图，所以照例先给出抽象定义。

**定义（directed graph）.** 一个 **directed graph** 是一个二元组 `(V, E)`，由顶点集合 `V` 与边集合 `E` 组成，其中每条边 `e ∈ E` 都带有一个 **source** 顶点和一个 **destination** 顶点，分别记作 `src(e)` 与 `dst(e)`。

有些书（例如 Grimaldi 1998，《Discrete and Combinatorial Mathematics: An Applied Introduction》）把 directed graph 定义成「边就是一个顶点的有序对 `(src(e), dst(e))`」。那样就不允许两条边共用同一对起点和终点。我们的表述更一般，因为起点和终点只是边的**属性**，而边自己还可以另带一个**标签**。这在 Knauer 2019 的《Algebraic Graph Theory: Morphisms, Monoids and Matrices》里叫 **directed multi-graph**。

有限的 directed graph 可以这样画出来：每个顶点画成一个点，每条边画成一支从起点指向终点的箭头。如果 `V` 或 `E` 是无限的，我们就说 `(V, E)` 是一张 **infinite graph**。只要剩下的结构能以某种方式说清楚，我们仍然可以画出它的某个有限**子图** `(V′, E′)`，其中 `V′ ⊆ V` 且 `E′ ⊆ E`。

**定义（path）.** 设 `(V, E)` 是一张 directed graph。一条 **path** `p := (v, (e_1, …, e_n))` 从一个起点顶点 `v ∈ V` 出发，沿着零条或多条边 `(e_1, …, e_n)`（这些边不必互不相同）前进，且必须满足下列条件：

1. 若该路径至少含一条边，则第一条边的起点必须等于起点顶点：`src(e_1) = v`。
2. 若该路径至少含两条边，则后一条边的起点必须等于前一条边的终点：对 `0 < i ≤ n` 有 `src(e_{i+1}) = dst(e_i)`。

每条路径也有自己的**起点**与**终点**。若 `p := (v, (e_1, …, e_n))` 如上，则它的起点是 `v`；终点在边序列为空时仍是起点顶点 `v`，否则是最后一条边的终点：

```
src(p) := v

dst(p) := v          （n = 0 时）
          dst(e_n)   （n > 0 时）
```

一条路径的**长度**是它含有的边数。每个顶点 `v ∈ V` 都定义了一条 **empty path**（长度为零），记作 `1_v`，它以 `v` 为起点、后面跟一个空的边序列；按上面的定义有 `src(1_v) = dst(1_v) = v`。每条边 `e` 也定义了一条单元素路径（长度为一），起点为 `src(e)`、终点为 `dst(e)`。这条单元素路径同样可以记作 `e`，因为不论把 `e` 当作边还是当作路径，`src(e)` 与 `dst(e)` 的含义都一样。

**定义（cycle、acyclic、tree）.** 下面这套术语贯穿全书：

- **cycle** 是一条起点与终点相同的非空路径。
- 一张 directed graph 若不含 cycle，就称它是 **acyclic** 的（directed acyclic graph）。
- **tree** 是一张带有一个特别指定的 root 顶点的 directed graph，且满足：从 root 到其他每个顶点都恰有唯一一条路径。注意每棵 tree 都是 acyclic 的。

不难看出，这里对 tree 的定义与程序员熟悉的那个概念是一致的。

图论准备到这里就够了，可以定义我们真正关心的对象了。

**定义（type parameter graph）.** 设 `G` 是一个 generic signature。`G` 的 **type parameter graph** 是按如下方式构造的 directed graph：

- 顶点集合含有一个特别指定的 root 顶点。
- 顶点集合还为 `G` 的每个 type parameter 等价类含有一个顶点。每个这样的顶点以该等价类的 reduced type 标注（这个 reduced type 也可能是一个具体类型）。
- 边集合为 `G` 的每个 generic parameter `τ_d_i` 含有一条边。这条边的起点是 root，终点是相应 generic parameter type 所在的等价类。
- 另外还有一些边连接这样的顶点对：起点是某个 type parameter `U` 的等价类，终点是以 `U` 为 base type 的 dependent member type `U.A` 的等价类。每条这样的边以 associated type 的名字「`.A`」标注。

这张图的关键性质是：每个 valid type parameter `τ_d_i.A_1…A_n` 都定义了一条从 root 顶点到该 type parameter 所在等价类的路径——沿着标为「`τ_d_i`」「`.A_1`」等等的边走即可。注意两个 type parameter 属于同一个等价类，当且仅当对应的两条路径终点相同。若某个 type parameter 被钉死到一个具体类型，则它的路径终止于一个以该具体类型标注的顶点。

> 译注：图上的 `.A` 边，在二进制里的落点就是 `__swift5_assocty` 里的 associated type witness 记录。本库离线解析一个 associated type field（`C.Index`、`C.Element` 这类）时，`DependentMemberTypeBridge` 做的正是沿这条边走一步、再把 base 自己的 generic argument 代回去。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

**例.** 考虑下面两个 generic signature：

```
<τ_0_0, τ_0_1, τ_1_0>
<τ_0_0, τ_0_1, τ_1_0 where τ_0_0 == τ_0_1, τ_1_0 == Int>
```

第一个 signature 完全没有 requirement，每个 generic parameter 各自成一个等价类。它的 type parameter graph 是一棵树，画在左边。第二个 signature 把前两个参数并成一类，并把第三个钉到一个具体类型上。这次的图就不是树了，因为有两条从 root 出发、终点相同的路径。

```
（左）无 requirement —— 一棵 tree：

                       root
           τ_0_0  ╱      │ τ_0_1     ╲ τ_1_0
                 ↙       ↓            ↘
             τ_0_0     τ_0_1          τ_1_0


（右）τ_0_0 == τ_0_1、τ_1_0 == Int —— 不是 tree：

                       root
           τ_0_0  ╱   ╱ τ_0_1        ╲ τ_1_0
                 ↙   ↙                ↘
               τ_0_0                   Int
```

> 译注：原书此处是两张并排的 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

没有 conformance requirement 的话，能做的事不多，因为可用的顶点就那么几个。要生成更多顶点，得给带 associated type 的 protocol 加上 conformance requirement。

**例.** 我们回到 `generic-signatures.tex` 里那个用来说明 derived requirement 的 generic signature，但把 `[τ_0_0.Element: Equatable]` 这条 requirement 去掉（`Equatable` protocol 没声明任何 associated type，所以这条 requirement 不会在图里生成新的顶点或边）：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Element == τ_0_1.Element>
```

这个 generic signature 的等价类结构我们已经研究得很透了。Type parameter graph 给了我们一个看 member type 关系的新角度：

```
                                .Iterator
             ┌─ τ_0_0 ─→ τ_0_0 ───────────────→ τ_0_0.Iterator
             │              ╲                        ╱
             │      .Element ╲              .Element╱
             │                ↘                    ↙
    root ────┤                    τ_0_0.Element
             │                ↗                    ↖
             │      .Element ╱              .Element╲
             │              ╱                        ╲
             └─ τ_0_1 ─→ τ_0_1 ───────────────→ τ_0_1.Iterator
                                .Iterator
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

注意 `τ_0_0.Element`、`τ_0_1.Element`、`τ_0_0.Iterator.Element`、`τ_0_1.Iterator.Element` 这四个 type parameter 对应的路径终点都相同，因为它们属于同一个等价类 `⟦τ_0_0.Element⟧`。

**例.** 现在回到 `generic-signatures.tex` 里演示 **SameName** 推理规则的那个 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Iterator == τ_0_1.Iterator>
```

它的 type parameter graph 是：

```
             ┌─ τ_0_0 ─→ τ_0_0 ──────────────────────┐
             │              │ .Element               │ .Iterator
             │              ↓                        ↓
    root ────┤       τ_0_0.Element ←───────── τ_0_0.Iterator
             │              ↑          .Element      ↑
             │              │ .Element               │ .Iterator
             └─ τ_0_1 ─→ τ_0_1 ──────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

从上图可以看出，`τ_0_0.Element`、`τ_0_1.Element`、`τ_0_0.Iterator.Element`、`τ_0_1.Iterator.Element` 在这个 signature 里同样是等价的，和上一个例子一样。不过这里 `τ_0_0.Iterator` 与 `τ_0_1.Iterator` 的路径也终止于同一个顶点。

接下来的几个例子里，generic signature 都只有一个 generic parameter `τ_0_0`，所以为了让图简洁些，我们把那个特别指定的 root 顶点略去，改说 `τ_0_0` 的等价类就是 root。这让我们的表述略有变化：现在一个 type parameter 对应的路径少走一步，因为没有对应 `τ_0_0` 的那条边了。

下一个例子展示一张**无限**的 type parameter graph。在任何一次具体的编译会话里，真正被实例化出来的 archetype 集合，构成该 generic signature 的 type parameter graph 的一个任意大但有限的子图。

**例.** 回忆 `generic-signatures.tex` 里这个 protocol：

```swift
protocol N {
  associatedtype A: N
}
```

我们见过，protocol generic signature `G_N`（即 `<τ_0_0 where τ_0_0: N>`）定义了无穷多个等价类。它的 type parameter graph 叫做一条 **ray**，即一条无限路径：

```
   τ_0_0 ──.A──→ τ_0_0.A ──.A──→ τ_0_0.A.A ──.A──→ τ_0_0.A.A.A ──.A──→ ⋯
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

**例.** 现在改一下 `N`，给它加一条 associated same-type requirement：

```swift
protocol Z4 {
  associatedtype A: Z4 where Self == Self.A.A.A.A
}
```

和 `G_N` 一样，protocol generic signature `G_Z4` 仍然定义了无穷多个 valid type parameter，但等价类的集合现在是有限的，于是我们又回到了有限图的世界。它的 type parameter graph 就是 4 阶的 **cycle graph**：

```
                          τ_0_0
                     ↗              ╲
                .A ╱                  ╲ .A
                 ╱                      ↘
   τ_0_0.A.A.A                            τ_0_0.A
                 ↖                      ╱
                .A ╲                  ╱ .A
                     ╲              ↙
                        τ_0_0.A.A
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

举例来说，`τ_0_0.A` 与 `τ_0_0.A.A.A.A.A` 在这个 generic signature 里是等价的。注意，若一个 generic signature 的 theory 是无限的而等价类只有有限多个，简单数一数就知道至少有一个等价类必定是无限的。在 `G_Z4` 里，**每个**等价类都是无限的。

**例.** 回忆 `generic-signatures.tex` 里那个简化版的 `Collection` protocol：

```swift
protocol Collection: Sequence {
  associatedtype SubSequence: Collection
      where Element == SubSequence.Element
      where SubSequence == SubSequence.SubSequence
}
```

我们研究 protocol generic signature `G_Collection` 时见过，它定义了一个无限的 theory，但等价类只有有限多个。它的 type parameter graph 长这样：

```
       τ_0_0 ─────────── .Iterator ───────────→ τ_0_0.Iterator
         │  ╲                                        ╱
         │   ╲ .Element                     .Element╱
         │    ↘                                    ↙
  .SubSequence              τ_0_0.Element
         │    ↗                                    ↖
         │   ╱ .Element                     .Element ╲
         ↓  ╱                                         ╲
       τ_0_0.SubSequence ──── .Iterator ────→ τ_0_0.SubSequence.Iterator
         ↑ │
         └─┘ .SubSequence（自环）
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

等价类 `⟦τ_0_0.SubSequence⟧` 含有无穷多个 type parameter；和 `G_Z4` 一样，`G_Collection` 的 type parameter graph 含有一条长度为 1 的 cycle（有时称作 **loop**），我们可以沿它走任意多次，从而生成这个等价类里更多的 type parameter：

```
τ_0_0.SubSequence
τ_0_0.SubSequence.SubSequence
τ_0_0.SubSequence.SubSequence.SubSequence
...
```

其他那些无限等价类，则是先沿这条 cycle 走零次或多次、再走一条别的边得到的。一般来说，若一个 generic signature 的 theory 无限而等价类集合有限，则它的 type parameter graph 必定含有 cycle。不过等价类集合本身也无限时，这个结论就不成立了。

**例.** 真正的 `Collection` protocol 还声明了两个 associated type——`Index` 和 `Indices`——并对它们施加了一些 requirement，归结起来是这样：

```swift
protocol Indexable {
  associatedtype Index
  associatedtype Indices: Indexable
    where Index == Indices.Index
}
```

Protocol generic signature `G_Indexable` 定义了无穷多个等价类，`τ_0_0.Index` 所在的等价类也是无限的，然而这张图却是 acyclic 的：

```
  τ_0_0 ──.Indices──→ τ_0_0.Indices ──.Indices──→ τ_0_0.Indices.Indices ──.Indices──→ ⋯
    │                       │                            │                      │
    │ .Index                │ .Index                     │ .Index               │ .Index
    ↓                       │                            │                      │
  τ_0_0.Index ←─────────────┴────────────────────────────┴──────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

若 `v` 与 `w` 是某张 directed graph `(V, E)` 的两个顶点，当存在一条边 `e ∈ E` 满足 `src(e) = v` 且 `dst(e) = w` 时，我们说 `v` 是 `w` 的一个 **successor**；相应地，`w` 是 `v` 的一个 **predecessor**。Type parameter graph 里的顶点总是只有有限个 successor，因为共用同一个起点的所有边对应着互不相同的 associated type declaration。但上面 `Indexable` 的例子说明，对顶点的 **predecessor** 集合就不能这么说了——在 `G_Indexable` 里，顶点 `⟦τ_0_0.Index⟧` 有无穷多个 predecessor。

> 译注：原书这句里的 `src` 与 `dst` 写反了——紧随其后的 locally finite graph 定义把「`v` 的 successor」明确算成满足 `src(e) = v` 的那些边（即从 `v` 出去的边），而这句却说「`src(e) = v` 且 `dst(e) = w` 时 `v` 是 `w` 的 successor」。后文用来支撑结论的理由（共用同一**起点**的边对应互不相同的 associated type declaration）和 `Indexable` 的例子（`⟦τ_0_0.Index⟧` 有无穷多条**入**边）也都按「successor = 出边的终点、predecessor = 入边的起点」这一通行读法才讲得通，疑为笔误，以 locally finite graph 的定义为准。

**定义（locally finite graph）.** 一张 directed graph `(V, E)` 称为 **locally finite** 的，如果每个顶点的 successor 集合都是有限的，即对每个 `v ∈ V`，满足 `src(e) = v` 的边 `e ∈ E` 只有有限多条。

在 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 The Conformance Path Graph 一节，我们会遇到另一张能与 generic signature 关联起来的 locally finite directed graph，叫做 **conformance path graph**。

## The Archetype Builder

Generic environment 忠实地表示了一个 generic signature 的等价类：`in` 操作编码了 reduced type equality 关系，而它的 archetype 的 local requirement 编码了其余一切。今天，generic environment 是一种**派生**表示，意思是它架在 generic signature query 之上。过去并非如此——回到 Swift 3，archetype 才是最基本的原语。本节我们描述当年用来构造它们的 `ArchetypeBuilder` 算法。这套算法如今已经作废、不再是实现的一部分，但它自有一种优雅，而且搞懂它能为第四部 The Requirement Machine 的材料做好铺垫。

我们可以把 generic signature 按复杂度递增分成三族：

1. 具有**有限 theory** 的 generic signature，即 derived requirement 与 valid type parameter 都只有有限多个。上面那个 `τ_0_0.Element == τ_0_1.Element` 的例子属于这一族。
2. theory 无限、但 type parameter 的**等价类集合有限**的 generic signature。上面 `Z4` 与 `Collection` 的例子属于这一族。
3. **等价类集合无限**的 generic signature。上面 `N` 与 `Indexable` 的例子属于这一族，后面会看到它是最难对付的。

Swift 3 只能接受第一族，因为那时 protocol 被禁止对自己的 associated type 写 recursive conformance requirement（所以今天的 `Collection` protocol 当年根本没法表达）。总的来说，那时 protocol 的 associated requirement 形式要简单得多：protocol 可以声明继承关系，可以对自己的 associated type 施加 conformance requirement，但不支持 associated same-type requirement。另外，Swift 3 虽然允许 superclass requirement 和 concrete same-type requirement，但我们不去管它们——它们只是多一点记账工作，不是算法的核心。

### Potential archetypes

算法用一个叫 **potential archetype** 的数据结构来表示一个尚未成形的 type parameter 等价类。在内存里，一个 potential archetype `t` 存四个字段：

| 字段 | 内容 |
|---|---|
| `FORWARD(t)` | 一个可选的、指向另一个 potential archetype 的指针。 |
| `TYPE(t)` | 一个 type parameter。此字段创建后不可变。 |
| `PROTO(t)` | 一组 protocol type。 |
| `MEMBERS(t)` | 一组（identifier，指向 potential archetype 的指针）对。 |

一个 potential archetype `t` 始终代表一个固定的 type parameter `T`，也就是说在 `t` 的整个生命周期里 `TYPE(t) = T`。初始状态下有 `FORWARD(t) = null`、`PROTO(t) = ∅`、`MEMBERS(t) = ∅`。Potential archetype 在算法运行期间顺序分配，等整个 archetype builder 实例释放时一次性全部释放。

Archetype builder 维护下面这条不变式。任何 forwarding 指针为 null 的 potential archetype，代表它所在等价类的 reduced type parameter。这种情况下，`PROTO(t)` 是该等价类 conform 到的所有 protocol 的集合，`MEMBERS(t)` 列出该等价类在 type parameter graph 里的所有 successor。反之，若一个 potential archetype `t` 的 forwarding 指针非 null，则它指向同一等价类里的另一个 potential archetype，且那一个在 type parameter order 下排在它前面，即 `TYPE(FORWARD(t)) < TYPE(t)`。顺着这条链一路走下去，最终会到达 reduced type parameter。

下面先说明这条不变式是怎么建立起来的，再说明得到的数据结构如何实现各个 generic signature query。

### Eager expansion

Archetype builder 一上来先为每个声明出来的 generic parameter 创建一个 potential archetype，这些叫 **root** potential archetype。对应 dependent member type 的 potential archetype，则是在 conformance requirement 的**展开**过程中产生的。展开 conformance requirement 是 potential archetype 上两个主要操作中的第一个。由于 protocol 可以对自己的 associated type 施加 conformance requirement，这个展开过程是递归的。注意下面第 6b 步：我们必须捕获并诊断那些指向已见过的 protocol 的 recursive conformance requirement，才能保证算法终止——这当然正是「eager expansion」路线的主要局限。

**算法（Expand conformance requirement）.** 输入一个 potential archetype `t` 和一个 protocol `P`。有副作用。

1. 若 `FORWARD(t)` 非 null，令 `t ← FORWARD(t)`，必要时重复。
2. 若 `P ∈ PROTO(t)`，返回。
3. 否则，置 `PROTO(t) ← PROTO(t) ∪ {P}`。
4. 对 `P` 的声明的继承子句里出现的每个 protocol `Q`，对 `t` 和 `Q` 递归施加本算法。
5. 令 `T := TYPE(t)`。
6. 对 `P` 的每个 associated type declaration `A`：
   1. 若 `MEMBERS(t)` 里没有 `A` 的条目，就创建一个新的 potential archetype `v`，令 `TYPE(v) = T.A`，并把有序对 `(A, v)` 加进 `MEMBERS(t)`。

      否则，`MEMBERS(t)` 里已有一个条目 `(A, v)`，其中 `TYPE(v) = T.A`。
   2. 对 `A` 的声明的继承子句里列出的每个 protocol `Q`，先检查 `Q` 是否已经出现在此前递归调用访问过的 protocol 集合里；若是，报一条诊断。否则把 `Q` 加入已访问集合，并对 `v` 和 `Q` 递归施加本算法。

第二个主要操作是把两个 potential archetype 合并，以形成一个更大的等价类。它实现的是 same-type requirement。

**算法（Merge potential archetypes）.** 输入一对 potential archetype `t` 与 `u`。有副作用。

1. 若 `FORWARD(t)` 或 `FORWARD(u)` 非 null，顺着 forwarding 指针走到底。
2. 若 `t` 与 `u` 是指向同一个 potential archetype 的相等指针，返回。
3. 若在 `generic-signatures.tex` 的 Type parameter order 算法下有 `TYPE(u) < TYPE(t)`，先交换 `t` 与 `u`。（正是这一步最终保证了：`FORWARD(t) = null` 当且仅当 `TYPE(t)` 是 reduced type parameter。）
4. 置 `FORWARD(u) ← t`。
5. 置 `PROTO(t) ← PROTO(t) ∪ PROTO(u)`。
6. 令 `T := TYPE(t)`。
7. 对每个条目 `(A, w) ∈ MEMBERS(u)`：
   1. 若 `MEMBERS(t)` 里没有 `A` 对应的 potential archetype，就创建一个新的 potential archetype `v`，使 `TYPE(v) = T.A`，并把 `(A, v)` 加进 `MEMBERS(t)`。
   2. 否则，`MEMBERS(t)` 里已有一个条目 `(A, v)`，其中 `TYPE(v) = T.A`。
   3. 两种情况下都递归调用本算法，把 `v` 与 `w` 合并。

我们还需要一个辅助子过程，用来从 root 出发把任意一个 type parameter 解析成 potential archetype：

**算法（Resolve potential archetype）.** 输入 root potential archetype 的数组和一个 type parameter `T`。返回 `T` 对应的 potential archetype；若尚未创建则返回 null。

1. 若 `T` 是 generic parameter，令 `t` 为对应的 root potential archetype。若 `FORWARD(t)` 非 null，令 `t ← FORWARD(t)`，必要时重复。返回 `t`。
2. 否则 `T` 必定是某个 dependent member type `U.A`，base type 为 `U`、identifier 为 `A`。先递归调用本算法把 `U` 解析成 potential archetype `u`。
3. 若 `MEMBERS(u)` 里含有 `A` 对应的 potential archetype，令 `t` 为它。若 `FORWARD(t)` 非 null，令 `t ← FORWARD(t)`，必要时重复。返回 `t`。
4. 否则返回 null。此时 type parameter `T` 要么是非法的，要么是我们还没展开它推导过程里用到的某条 conformance requirement。

现在可以看主算法了。我们逐条访问源码里写出的 requirement，展开 conformance requirement，并把 same-type requirement 对应的两个 potential archetype 合并。这里有个小麻烦：requirement 的书写顺序是任意的，所以比如先处理 `[T.Element: Equatable]`、后处理 `[T: Sequence]` 的话，`T.Element` 的 potential archetype 可能还没被创建出来。这是允许的；若 Resolve potential archetype 算法返回 null，我们就把这条 requirement 加进「delayed requirement」列表，等其他 requirement 都试过一遍之后再重新处理它。

**算法（Historical `ArchetypeBuilder` algorithm）.** 输入一个 generic parameter 列表、一个 requirement 列表和若干 protocol declaration。输出一个 root potential archetype 数组。中间数据结构有三个：一个 pending requirement 列表、一个 delayed requirement 列表，以及一个记录「有无进展」的标志位。

1. （初始化）把所有 requirement 加进 pending 列表。把标志位置为 false。为每个 generic parameter 创建一个 root potential archetype。
2. （重新处理）若 pending 列表为空且标志位已置位，把 delayed 列表里的 requirement 全部挪到 pending 列表，并清除标志位。
3. （检查）若 pending 列表仍为空，跳到第 8 步。
4. （取出）从 pending 列表里取走一条 requirement。
5. （Conformance）对一条 conformance requirement `[T: P]`，调用 Resolve potential archetype 算法把 `T` 解析成 potential archetype。若该 potential archetype 不存在，把 `[T: P]` 加进 delayed 列表并置位标志。否则调用 Expand conformance requirement 算法展开这条 conformance requirement。
6. （Same-type）对一条 same-type requirement `[T == U]`，调用 Resolve potential archetype 算法把 `T` 和 `U` 各解析成一个 potential archetype。若其中任一不存在，把 `[T == U]` 加进 delayed 列表并置位标志。否则调用 Merge potential archetypes 算法合并这两个 potential archetype。
7. （重复）回到第 2 步。
8. （诊断）走到这里说明已经没有 pending requirement 了。任何还留在 delayed 列表上的 requirement，都引用了无法解析的 type parameter；把它们诊断为非法。

算法返回之后，只要我们没有诊断出非法的 recursive conformance，potential archetype 结构就编码了由输入 requirement 构建出来的那张有限 type parameter graph。到这一步就不再有展开或合并了；剩下那些没有 forwarding 指针的 potential archetype 被「冻结」成不可变的 archetype **类型**，由它们向编译器的其余部分描述这个 generic signature。虽然当年还没有 generic signature query 这回事，但我们可以这样把这套算法与今天的模型对上：

- `isValidTypeParameter(G, T)`：把 `T` 解析成 potential archetype `t`，检查 `t` 是否非 null。
- `getReducedType(G, T)`：把 `T` 解析成 potential archetype `t`，返回 `TYPE(t)`。
- `areReducedTypeParametersEqual(G, T, U)`：把 `T` 和 `U` 各解析成 potential archetype `t` 与 `u`，检查 `t` 和 `u` 是否为指向同一个 potential archetype 的相等指针。
- `requiresProtocol(G, T, P)`：把 `T` 解析成 potential archetype `t`，检查是否 `P ∈ PROTO(t)`。
- `getRequiredProtocols(G, T)`：把 `T` 解析成 potential archetype `t`，返回 `PROTO(t)`。

Archetype builder 是 **union-find**（又名 **disjoint set**）数据结构的一个实例（可参见 Knuth 1997，《The Art of Computer Programming: Volume 1: Fundamental Algorithms》第 2.3.3 节）。这种数据结构的一个实例定义了一个等价关系。从一堆单元素等价类出发，两个基本操作是 **union**（合并两个等价类）与 **find**（把一个元素解析到它所属的等价类）。在我们这里，Merge potential archetypes 算法就是 **union**，Resolve potential archetype 算法就是 **find**（而 Expand conformance requirement 算法里的展开则是我们自己额外加的东西）。

我们对这些算法的描述省略了若干标准的优化技巧；例如 **find** 顺着 forwarding 指针走的时候，通常还要把指针回写到原来的存储位置，以免后续查找反复遍历同一条链。

这类数据结构最早出现在编译器的早期历史中，用于实现「`EQUIV` 语句」——声明两个符号应当共用一个存储位置。这些语句因而在符号上定义了一个等价关系，而精心实现所带来的性能收益，Galler 与 Fisher 在 1964 年的《An improved equivalence algorithm》里已经指出。后续技术的综述见 Galil 与 Italiano 1991 年的《Data structures and algorithms for disjoint set union problems》。

### Lazy expansion

从理论角度看，archetype builder 的做法相当于把一个 generic signature 的所有 derived requirement 与 valid type parameter 穷举一遍，只是靠数据结构的选择稍微提高了点效率（Merge potential archetypes 算法在处理 member type 时的不对称性，意味着我们跳过了搜索空间里那些产生不出新东西的部分）。

Eager expansion 这套模型撑过了 Swift 4 引入 protocol `where` 子句（SE-0142）、也就是 associated requirement 的那一关，只做了相对较小的改动。而 Swift 4.1 引入 recursive conformance（SE-0157）则必须做一次较大的翻修。一旦 type parameter graph 变成无限的，Expand conformance requirement 算法那种急切展开 conformance requirement 的做法就说不通了。`ArchetypeBuilder` 随之被改名为 `GenericSignatureBuilder`，作为一次重新设计的一部分：递归展开改成按需进行，就发生在 Resolve potential archetype 算法的查找过程内部（Doug Gregor 2016 年的《Implementing Recursive Protocol Constraints》）。

在 lazy expansion 模型下，potential archetype 结构是高度可变的，因为 generic signature query 会在探索 type parameter graph 的新子图时创建新的 potential archetype、合并已有的 potential archetype。这种持续的变更使得多个 `GenericSignatureBuilder` 实例之间无法共享结构，于是每一个依赖复杂标准库 protocol（比如 `RangeReplaceableCollection`）的 generic signature，最终都会构造出自己那一份庞大的 potential archetype 图。这对编译器的内存占用和性能影响相当显著。

Lazy expansion 还有正确性问题。哪怕是第二族 generic signature——theory 无限但等价类集合有限的那些——也并不总能正常工作。上面 `Z4` 的例子恰好就是其中之一，后面在 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 里我们还会看到另一个。再往后还发现了一个更根本的问题。正如 `monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 The Word Problem 一节将要讲到的，第三族 generic signature——等价类集合无限的那些——里实际上存在使 reduced type equality 问题**不可判定**的 generic signature。任何正确的 Swift 实现都必须拒绝这样的 generic signature。而 `GenericSignatureBuilder` 在设计上就假装自己能接受任何 generic signature 并回答关于它的查询。Lazy expansion 是一条死路！这在当时相当出人意料，因为在没有 recursive conformance 的前提下，eager expansion 用一种直截了当的方式把 Swift 泛型彻底「解决」了。

这些问题促使人们去寻找一个健全且可判定的基础来承载 Swift 泛型，也就是后来的 Requirement Machine。正确的做法不是去增量地构造 type parameter graph 的有限子图，而是构造一个**收敛的重写系统**。它虽然更抽象，但其实比 lazy expansion 的 type parameter graph **简单**得多。和最初的 eager expansion 设计一样，这个重写系统是一个有限的数据结构，构造一次之后就保持不变。与 eager expansion 不同的是，重写系统能描述无限的等价类集合，而且在很多情况下，它还能在不穷举的前提下编码一个**有限**的等价类集合。当代的做法以及一份正确性证明，我们会在第四部 The Requirement Machine 里研究。

## Source Code Reference

**`GenericEnvironment`**：一个 generic environment。实例分配在 AST context 里，按指针传递。一个扁平数组把 generic parameter type 映到 archetype，另有一张独立的侧表存放 dependent member type 的映射。

- `getGenericSignature()` 返回这个 generic environment 的 generic signature。
- `mapTypeIntoContext()` 返回把一个 interface type 映入本 generic environment 所得的 contextual type。
- `getForwardingSubstitutionMap()` 返回一张把每个 generic parameter 映到它的 contextual type 的 substitution map——那个 contextual type 是一个 archetype，或者在该 generic parameter 被 same-type requirement 钉死到具体类型时，是那个具体类型。
- `getOrCreateArchetypeFromInterfaceType()` 是私有入口，把单个 type parameter 映成一个 archetype，第一次调用时创建该 archetype。这个方法使用 `getLocalRequirements()` 这个 generic signature query。

**`GenericSignature`**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `getGenericEnvironment()` 返回与这个 generic signature 关联的 primary generic environment。

**`TypeBase`**：另见 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）的 Source Code Reference 一节。

- `mapTypeOutOfContext()` 返回把这个 contextual type 映出它的 generic environment 所得的 interface type。

**`SubstitutionMap`**：另见 `substitution-maps.tex` 的 Source Code Reference 一节。

- `mapReplacementTypesOutOfContext()` 返回把这张 substitution map 的 replacement type 与 conformance 映出它们的 generic environment 所得的 substitution map。

**`ProtocolConformanceRef`**：另见 `conformances.tex` 的 Source Code Reference 一节。

- `mapConformanceOutOfContext()` 返回把这个 protocol conformance 映出它的 generic environment 所得的 protocol conformance。

**`DeclContext`**：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getGenericEnvironmentOfContext()` 返回包含这个 declaration context 的最内层 generic 声明的 generic environment。
- `mapTypeIntoContext()` 把一个 interface type 映入最内层 generic 声明的 primary generic environment。若至少有一个外层 declaration context 是 generic 的，它等价于：

  ```cpp
  dc->getGenericEnvironmentOfContext()->mapTypeIntoContext(type);
  ```

  为方便起见，`DeclContext` 版本的 `mapTypeIntoContext()` 还处理了外层没有任何 generic 声明的情形。这种情况下它原样返回输入类型，并先断言该类型不含任何 type parameter（因为出现在 generic 声明之外的 type parameter 是没有意义的）。

**`ArchetypeType`**：一个 archetype。

- `getName()` 返回这个 archetype 的名字，也就是它的 generic parameter type 或 associated type declaration 的名字。
- `getFullName()` 返回这个 archetype 的「带点」名字，看起来就像它的 type parameter 的字符串表示。

把一个 archetype 拆开来看：

- `getInterfaceType()` 返回这个 archetype 的 reduced type parameter。
- `getGenericEnvironment()` 返回这个 archetype 的 generic environment。
- `isRoot()` 回答它的 reduced type parameter 是不是一个 generic parameter type。

Local requirement（见本章 Local Requirements 一节）：

- `getConformsTo()` 返回这个 archetype 的 required protocol。这个集合不含继承来的 protocol。要真正检查一个 archetype 是否 conform 到某个特定 protocol，请用 global conformance lookup（见 `conformances.tex` 的 Source Code Reference 一节），而不是去翻这个数组。
- `getSuperclass()` 返回这个 archetype 的 superclass bound；没有的话返回空的 `Type`。
- `requiresClass()` 回答 requires class flag。
- `getLayoutConstraint()` 返回 layout constraint；没有的话返回空的 layout constraint。

**`PrimaryArchetypeType`**：`ArchetypeType` 的子类，表示一个 primary archetype。

---

> 译自 `docs/Generics/chapters/archetypes.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
