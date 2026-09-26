# Substitution Maps（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/substitution-maps.tex`（《Compiling Swift Generics》一书的「Substitution Maps」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `cab5c62e`，2026-01-05）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是整套 **substitution algebra**（`⊗`、composition、identity / empty substitution map）的定义处，同目录的 `SwiftGenericsOpaqueResultTypes.md` 以及本库一系列文档反复引用的就是它。本库在「读回来」的方向上把这套代数重做了一遍：静态布局引擎从 mangled name 里恢复 bound generic 的实参、纯语法地代入到字段类型上（不调 metadata accessor），特化类型的渲染也按 context substitution map 的规则绑定。对应关系见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)；译文本身不夹带本库实现细节，只在个别地方以「译注」标出。
>
> **术语**：书中定义的术语一律保留英文（substitution map、type substitution、input / output generic signature、replacement type、interface type、context substitution map、identity substitution map、empty substitution map、substitution map composition、specialized type、superclass type、SIL type lowering、abstraction pattern、re-abstraction thunk、loadable / address-only……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Type Parameter Order 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。原书的 `T` 对应 `τ_0_0`，`U` 对应 `τ_0_1`，`V` 对应 `τ_0_2`；嵌套一层的参数写 `τ_1_0` |
> | `Σ`、`Σ_1`、`Σ_2`、`Σ′` | substitution map。写成 `{τ_0_0 ↦ Int}`；若 input generic signature 有 conformance requirement，分号后再列 conformance，写成 `{τ_0_0 ↦ Int; [τ_0_0: Equatable] ↦ [Int: Equatable]}` |
> | `↦` | 「替换成」。左边是 canonical 的 generic parameter，右边是 replacement type |
> | `{}` | **empty substitution map**（不存任何 replacement type 与 conformance） |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `T`，即 **type substitution** |
> | `Σ_1 ⊗ Σ_2` | **substitution map composition**（先 `Σ_1` 后 `Σ_2`） |
> | `Type(G)` | generic signature `G` 的 interface type 全体 |
> | `Sub(G → H)` | input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 全体 |
> | `1_G` | `G` 的 **identity substitution map**（把每个 generic parameter 映到它自己） |
> | `Fwd_G` | `G` 的 **forwarding substitution map**（把每个参数映到自己的 primary archetype；本章只提到它，定义在 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)）） |
> | `⟦T⟧`、`⟦T⟧_G` | type parameter `T` 的 **primary archetype** |
> | `X_d` | 声明 `d` 的 **declared interface type** |
> | `[X: P]` | 类型 `X` 对 protocol `P` 的一个 conformance |
> | `superclass` | 从类型到它 superclass type 的**部分**映射 |
> | `Hom(A, B)` | category 里从对象 `A` 到对象 `B` 的 morphism 全体 |
> | `L(Y, X)` | 以 abstraction pattern `Y` 对 formal type `X` 做 SIL type lowering 得到的 lowered type |
> | `∈`、`→`、`≠` | 属于、映射到、不等 |

---

Substitution map 是描述对 generic declaration 的**引用**的语义对象。如果把 generic signature 看成声明与其使用方之间的一份**合同**，那么上一章的 derived requirement 形式系统给出的是合同的一侧：在一个 generic declaration 的**函数体内部**，我们从「具体的 replacement type 无论是什么，都必须满足 generic signature 显式声明的那些 requirement」这个假设出发，推导出各种随之成立的结论。本章把注意力转向合同的另一侧——使用方那一侧，这就引出了对 **type substitution** 的研究。

### Input generic signature

一张 substitution map 的「形状」由它的 **input generic signature** 决定。本章主要讨论最简单的情形，即这个 generic signature 不带任何 requirement；一般情形稍后会做个概述。后续几章会解释 requirement 与 substitution 如何相互作用。

**例.** 我们看看这个 generic function，并设想一下它的调用方：

```swift
func combine<T, U>(_ t: T, _ u: U) -> (T, Array<U>) {
  return (t, [u])
}
```

这个 generic signature 有两个 generic parameter，没有 requirement。把它记作 `G`：

```
G := <T, U>，也就是 <τ_0_0, τ_0_1>
```

假设我们用下面这两个值调用它，结果的类型是什么？

```swift
let t: Optional<Int> = 3
let u: String = "Hello world"

let result = combine(t, u)  // what is the return type of this call?
```

把函数声明的参数类型与实参表达式的类型逐一匹配，expression type checker 就能推出 `T` 必须是 `Optional<Int>`，`U` 必须是 `String`。这给了我们一张 substitution map，记作 `Σ`：

```
Σ := {τ_0_0 ↦ Optional<Int>,
      τ_0_1 ↦ String}
```

我们书写 substitution map 的记法，是按顺序列出 input generic signature 的每个 generic parameter 的 **replacement type**。Type substitution 不看 type sugar，为了提醒自己这一点，我们在「`↦`」左边写的是 canonical 的 generic parameter type。Substitution map 通常命名为 `Σ`，或者它的变体 `Σ_1`、`Σ_2`、`Σ′` 等等。

回忆 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 讲过的，类型有树状结构，所以 `Σ` 里这两个 replacement type 在内存里大致长这样：

```
Optional<Int>            String
└── Int
```

> 译注：原书此处是两张 TikZ 图（左边 `Optional<Int>` 的两层树，右边单节点 `String`），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

现在，要算出「`result`」的推断类型：注意函数声明的返回类型是 tuple type `(τ_0_0, Array<τ_0_1>)`，我们把它叫做 **original type**。这个类型含有 `G` 的 generic parameter。要得到 **substituted type**，我们把 original type 里每一处 `τ_0_0` 和 `τ_0_1` 都换成它的 replacement type。于是 substituted type 是 `(Optional<Int>, Array<String>)`。下面这张图演示了这次变换。

**图：Type substitution**

```
Original type:                       Substituted type:

(τ_0_0, Array<τ_0_1>)                (Optional<Int>, Array<String>)
├── [τ_0_0]                 ⇒        ├── Optional<Int>
└── Array<τ_0_1>                     │   └── Int
    └── [τ_0_1]                      └── Array<String>
                                         └── String
```

（方括号标出的是被替换掉的 type parameter，对应原图里的灰底节点。）

> 译注：原书此处是一张由两张 TikZ 图组成的插图（左右两棵类型树夹一个 `⇒`），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

这个操作就叫 **type substitution**。在看形式化的算法之前，先引入一点记法。仍取上面的 `Σ`，我们把这次 type substitution 记成下面这样——`⊗` 运算符左边是 original type，右边是 substitution map：

```
(τ_0_0, Array<τ_0_1>) ⊗ Σ = (Optional<Int>, Array<String>)
```

上面的例子演示了「观察」type substitution 的一种办法：写一个 generic function 声明，用一串 generic argument type 调用它，然后看这次调用的返回类型。下面是另一个类似的小技巧。

**例.** 考虑对一个 generic type alias 做 type resolution：

```swift
typealias Foo<T, U> = (T, Array<U>)

let x: Foo<Optional<Int>, String> = ...
```

这里我们用与前面相同的 generic argument 引用 `Foo`，因此得到的是同一张 substitution map `Σ`。要 resolve「`x`」上的类型标注，我们把 `Σ` 应用到 `Foo` 的 underlying type 上：

```
(τ_0_0, Array<τ_0_1>) ⊗ Σ = (Optional<Int>, Array<String>)
```

既然 alias 的 underlying type 和引用处的 generic argument 都是任意的，我们就可以用 generic type alias 编码出任意一次 type substitution 操作。Generic type alias 的 type resolution 会在 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Identifier Type Representations 一节和 Member Type Representations 一节讨论。

### Output generic signature

到目前为止的例子里，substitution map 的 replacement type 都是 fully concrete 的。要观察一张 replacement type 里含有 type parameter 的 substitution map，我们可以从另一个 generic declaration 的函数体里去引用一个 generic declaration。如果 `Σ` 的 replacement type 里出现的所有 type parameter 都是 `H` 的 valid type parameter，我们就说 generic signature `H` 是 substitution map `Σ` 的 **output generic signature**。

**例.** 下面这段里，generic 的 `callee()` 函数是从 `caller()` 的函数体里被引用的：

```swift
func callee<T>(_ value: T) -> Array<T> {
  return [value]
}

func caller<X, Y>(_ x: X, y: Y) -> Array<(X, Y)> {
  return callee((x, y))  // call here
}
```

这次调用表达式传进去的实参是一个 tuple 值，所以 `τ_0_0` 的 replacement type 是 tuple type `(τ_0_0, τ_0_1)`：

```
(τ_0_0, τ_0_1)
├── [τ_0_0]
└── [τ_0_1]
```

> 译注：原书此处是一张 TikZ 图（tuple 类型的两层树），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

Input generic signature 是 `callee()` 的 generic signature：

```
G := <τ_0_0>
```

Output generic signature 是 `caller()` 的 generic signature：

```
H := <τ_0_0, τ_0_1>
```

这是那张 substitution map：

```
Σ := {τ_0_0 ↦ (τ_0_0, τ_0_1)}
```

现在把 `Σ` 应用到 `callee()` 的返回类型上，得到 substituted type：

```
Array<τ_0_0> ⊗ Σ = Array<(τ_0_0, τ_0_1)>
```

下面这张图演示了这次变换。

**图：Type substitution with output generic signature**

```
Original type:            Substituted type:

Array<τ_0_0>              Array<(τ_0_0, τ_0_1)>
└── [τ_0_0]        ⇒      └── (τ_0_0, τ_0_1)
                              ├── [τ_0_0]
                              └── [τ_0_1]
```

> 译注：原书此处是一张由两张 TikZ 图组成的插图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

接下来引入一点记法，把一个我们已经见过的概念形式化：

**定义.** 设 `G` 是一个 generic signature。我们用 `Type(G)` 记 `G` 的 **interface type** 集合。具体来说，这个集合包含：

- `G` 的所有 valid type parameter。
- 所有 nominal type，由非 generic 的 nominal type declaration 构成。
- 所有 generic nominal type，由 generic nominal type declaration 与取自 `Type(G)` 的各种 generic argument 组合构成。
- 所有 structural type——function type、tuple type、metatype 之类——由 `Type(G)` 的元素构成。

我们也可以谈论「把某个固定 generic signature 的 interface type 映到另一个 generic signature 的 interface type」的那些 substitution map 的全体：

**定义.** 设 `G` 与 `H` 是 generic signature。我们用 `Sub(G → H)` 记 input generic signature 为 `G`、output generic signature 为 `H` 的所有 substitution map 的集合。

这些都是无限集合，所以实现里并不把它们具体造出来；它们只是帮助我们理解 type substitution 的记法工具。一个重要而微妙的点是：**output generic signature 并不存在 substitution map 自身里**，它是由使用方式隐含决定的。因此我们必须时刻记住这些集合之间的关系，小心不要把 output generic signature 「搞混」。

假设给定一个 `Σ ∈ Sub(G → H)`。注意 `Σ` 的 replacement type 都是 `Type(H)` 的元素；进一步，如果取某个 `X ∈ Type(G)`，把 `X` 里出现的每个 type parameter 都换成 `Type(H)` 的一个元素，变换后的类型同样会是 `Type(H)` 的元素。特别地，`X ⊗ Σ ∈ Type(H)`，于是可以把 type substitution 看成下面这个集合之间的映射：

```
Type(G) ⊗ Sub(G → H) ⟶ Type(H)
```

我们把 type substitution 建模成一个作用在类型与 substitution map 上的**二元运算**，而不是用「`Σ(T)`」这种把 substitution map 当作一元函数的「应用式」记法。理由很快就会清楚：我们还会遇到 `⊗` 运算符的另外几种形态，它们让我们能写出更复杂的表达式。`⊗` 的这几种形态之间由各种恒等式关联起来，这些恒等式定义了 **type substitution algebra**。

下面这个 **type substitution** 的算法，把我们前面看到的结构性变换形式化了。它还调用了若干子例程来处理 dependent member type 和 archetype 的情形，这些留到后面补全。

**算法（Substitute type）.** 输入一个类型 `X` 和一张 input generic signature 为 `G` 的 substitution map `Σ`。输出 `X ⊗ Σ`。

1. （Type parameter）若 `X` 是一个 type parameter `T`：
   1. 若 `isValidTypeParameter(G, T)` 为 false，返回 error type。
   2. 若 `T` 是 generic parameter type，返回 `Σ` 里 `T` 的 replacement type。
   3. 若 `T` 是 dependent member type，套用 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 dependent member type substitution 算法，返回其结果。
2. （Archetype）若 `X` 是 primary archetype `⟦T⟧_G`，返回 `T ⊗ Σ`（见 `archetypes.tex` 的 Primary Archetypes 一节）。若 `X` 是 opaque archetype，调用 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)） 的 Opaque Archetypes 一节所给的算法（中译见 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）。若 `X` 是 existential 的，调用 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)） 的 Existential Archetypes 一节所给的算法。
3. （Base case）若 `X` 既不含 type parameter 也不含 archetype：返回 `X`。
4. （Recurse）对 `X` 的每个子结点递归地应用 `Σ`，再用这些 substituted 后的子类型构造一个新类型，保留 `X` 里那些非类型的结构性成分。

**图：Type substitution with dependent member type**

```
Original type:                Substituted type:

Array<τ_0_0.Element>          Array<Int>
└── ┌──────────────────┐      └── Int
    │ [τ_0_0.Element]  │  ⇒
    │ └── [τ_0_0]      │
    └──────────────────┘
```

（虚线框圈住的是被当作一个不可分原子替换掉的整段 dependent member type。）

> 译注：原书此处是一张由两张 TikZ 图组成的插图，左图用虚线框强调 `τ_0_0.Element` 连同它的 base 一起被整体替换；这里用 ASCII 图转述，图的原貌见官方 PDF 对应章节。

### Dependent member types

如果一个 generic signature 声明了对带 associated type 的 protocol 的 conformance requirement，那么除了 generic signature 里显式写出的 generic parameter 之外，它的 valid type parameter 还包括从这些 conformance requirement **derive** 出来的全部 dependent member type。

```swift
func extract<S: Sequence>(_ s: S) -> Array<S.Element> {...}
let mySet: Set<Int> = [1, 2, 3]
let x = extract(mySet)
```

一张 substitution map 会为它 input generic signature 的每条 conformance requirement 记录一个 **root conformance**。在对 `extract()` 的这次调用里，substitution map 是：

```
Σ := {τ_0_0 ↦ Set<Int>;
      [τ_0_0: Sequence] ↦ [Set<Int>: Sequence]}
```

Type substitution 把 dependent member type 当作一个不可分的原子元素，一次性把它整体换成一个 substituted type（我们**不**递归进它的 base type）。在 `conformances.tex` 的 Abstract Conformances 一节我们会看到，这个 substituted type 是从 substitution map 里存的某个 conformance 算出来的。这里先不解释：

```
Array<τ_0_0.Element> ⊗ Σ = Array<Int>
```

上面那张图演示了这次变换。

> 译注：本库读 conformance descriptor 时，associated type witness 的归属正是这一步的「读回来」形态——从哪个 conformance 投影出 `Element` 的 type witness，决定了 extension 容器里那条 `typealias` 归谁。见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

### Archetypes

在 `archetypes.tex` 里我们会遇到 **archetype**——一种把 type parameter 与 generic signature 组合在一起的替代表示。Archetype 有三种。就 type substitution 而言，**primary** archetype 的行为与它所代表的 type parameter 一致。**Opaque** 与 **existential** archetype 的 substitution 则不同，分别在 `opaque-result-types.tex` 的 Opaque Archetypes 一节和 `existential-types.tex` 的 Existential Archetypes 一节描述。

### Substitution failure

如果 original type 里含有一个在 substitution map 的 input generic signature 中无效的 type parameter，type substitution 会输出 error type。此外，若 substitution map 的 replacement type 里含有 error type，或者 substitution map 里存的某个 conformance 无效，type substitution 也可能产生 error type。这叫做 **substitution failure**，它表明用户程序里别处已经诊断出了一个错误。只要诊断出错误，编译器就不会继续走到 SILGen，所以类型检查之后不应该再出现 error type。

### Other requirements

Conformance requirement 是特殊的，因为 substitution map 直接记录了它是如何满足每一条 conformance requirement 的。其余 requirement 则只是待检查的条件。举例来说，如果 input generic signature 声明了一条 same-type requirement，那么这个 generic signature 的 substitution map 就必须**满足**这条 requirement，意思是把 substitution map 应用到等式两边应当产生 canonically equal 的 substituted type。如果一张 substitution map 满足其 input generic signature 的所有 derived requirement，我们就说它是 **well-formed** 的。检查 requirement 是否被满足的算法，会在 `type-resolution.tex` 的 Generic Arguments 一节讨论。

## Nominal Types

现在我们来看 nominal type declaration、nominal type 与 substitution map 三者之间的关系。考虑下面这组声明：

```swift
struct Bacon<T, U> {
  struct Lettuce<V> {
    struct Tomato {
      var t: T
      var u: U
      var v: V
    }
  }
}
```

（`Tomato` 的那几个 stored property 马上就会用到。）有了这些声明，我们就能写出各种 nominal type，例如下面「`x`」的类型：

```swift
let x: Bacon<Int, Bool>.Lettuce<Float>.Tomato = ...
```

在实现里，`Bacon<Int, Bool>` 被归类为 generic nominal type，而 `Int` 和 `Bacon<Int, Bool>.Lettuce<Float>.Tomato` 都「只是」nominal type——但后者的 **parent** 是一个 generic nominal type。我们说一个 **specialized type** 是这样一种 nominal type：它自己是 generic 的，或者它有一个 generic 的 parent。等价地说，一个 nominal type 是 specialized 的，当且仅当它的声明有非空的 generic signature。

> 译注：本库把这件事落在渲染层：一个 specialized 的 `TypeDefinition` 会按 concrete argument 绑定渲染成 `Box<Int>` 而不是 `Box<T>`，字段类型也按对应的 substitution 代入。见 [SpecializedInterfaceBoundRenderingRestoration.md](../SpecializedInterfaceBoundRenderingRestoration.md)。

如果把 specialized type `Bacon<Int, Bool>.Lettuce<Float>.Tomato` 各层嵌套上的 generic argument 收集起来，我们就能为 `Tomato` 这个声明的 generic signature——也就是 `<τ_0_0, τ_0_1, τ_1_0>`——构造一张 substitution map：

```
Σ := {τ_0_0 ↦ Int, τ_0_1 ↦ Bool, τ_1_0 ↦ Float}
```

回忆 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 讲过的，每个 nominal type declaration 都有一个 declared interface type。对 `Tomato` 来说，它是 `Bacon<τ_0_0, τ_0_1>.Lettuce<τ_1_0>.Tomato`。现在我们看到，把 substitution map `Σ` 应用到 `Tomato` 的 declared interface type 上，得到的正是我们那个 specialized type：

```
Bacon<τ_0_0, τ_0_1>.Lettuce<τ_1_0>.Tomato ⊗ Σ
    = Bacon<Int, Bool>.Lettuce<Float>.Tomato
```

我们说 `Σ` 是这个 specialized type 的 **context substitution map**。下面这张图演示了这次变换。

**图：Applying the context substitution map**

```
Declared interface type:

Bacon<τ_0_0, τ_0_1>.Lettuce<τ_1_0>.Tomato
└── Bacon<τ_0_0, τ_0_1>.Lettuce<τ_1_0>
    ├── Bacon<τ_0_0, τ_0_1>
    │   ├── [τ_0_0]
    │   └── [τ_0_1]
    └── [τ_1_0]

Specialized type:

Bacon<Int, Bool>.Lettuce<Float>.Tomato
└── Bacon<Int, Bool>.Lettuce<Float>
    ├── Bacon<Int, Bool>
    │   ├── Int
    │   └── Bool
    └── Float
```

> 译注：原书此处是一张由两张 TikZ 图上下叠放组成的插图（上为 declared interface type 的类型树，下为 specialized type 的类型树，结构逐点对应），这里用 ASCII 树转述；图的原貌见官方 PDF 对应章节。

### Context substitution map

假设有两个 generic signature `G` 与 `H`，以及一个 generic signature 为 `G` 的 nominal type declaration `d`。用 `X_d` 记 `d` 的 declared interface type。如果再给我们一个由 `d` 构成的 specialized type，记作 `X ∈ Type(H)`，那么 `X` 的 context substitution map 就是满足下面这个恒等式的**唯一**一张 substitution map `Σ ∈ Sub(G → H)`：

```
X_d ⊗ Σ = X
```

Context substitution map 不只是一个数学把戏，它还解释了「`foo.bar`」这类 member reference expression 的类型。回忆 `Tomato` 声明了三个 stored property `t`、`u`、`v`，interface type 分别是 `τ_0_0`、`τ_0_1`、`τ_1_0`。考虑这段代码：

```swift
let x: Bacon<Int, Bool>.Lettuce<Float>.Tomato = ...
let xt = x.t
let xu = x.u
let xv = x.v
```

要推出 `xt`、`xu`、`xv` 的类型，只需把 substitution map `Σ` 应用到每个 stored property 的 interface type 上：

```
τ_0_0 ⊗ Σ = Int
τ_0_1 ⊗ Σ = Bool
τ_1_0 ⊗ Σ = Float
```

> 译注：本库的静态布局引擎做的就是这一步的离线版本：从 mangled 的 bound generic 引用里按「外层到内层」收集每层的实参，建立 `(depth, index) → Node` 的映射，再纯语法地代进字段的 type node——不调 metadata accessor、不查 protocol witness table。见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Identity substitution map

那么 `X_d`（也就是 `d` 的 declared interface type）自己的 context substitution map 是什么？如果 `Σ` 满足 `X_d = X_d ⊗ Σ`，那么特别地，`Σ` 把 `G` 的每个 generic parameter 都替换成它自己。我们把它叫做 `G` 的 **identity substitution map**，记作 `1_G`。注意 `1_G ∈ Sub(G → G)`。例如，若 `G` 是上面 `Tomato` 的 generic signature，则：

```
1_G := {τ_0_0 ↦ τ_0_0, τ_0_1 ↦ τ_0_1, τ_1_0 ↦ τ_1_0}
```

如果 `G` 声明了一条或多条 conformance requirement，那么 `G` 的 identity substitution map 还会为每条 conformance requirement 记录一个对应的 **abstract conformance**。这保证了把 `1_G` 应用到一个 dependent member type 上不会改变它。Abstract conformance 在 `conformances.tex` 的 Abstract Conformances 一节讨论。

例如，若 `G := <τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence>`：

```
1_G := {τ_0_0 ↦ τ_0_0;
        [τ_0_0: Sequence] ↦ [τ_0_0: Sequence],
        [τ_0_1: Sequence] ↦ [τ_0_1: Sequence]}
```

一般地，若 `X` 是 `Type(G)` 里的任意一个 interface type，则 `X ⊗ 1_G = X`。换句话说，把 identity substitution map 应用到 `G` 的任何 interface type 上都不改变它。（当 original type 是含 archetype 的 contextual type 时这一条不成立，因为那样的类型并不是 `Type(G)` 的元素。Archetype substitution 见 `archetypes.tex` 的 Primary Archetypes 一节；那里还会遇到另一张 substitution map——**forwarding substitution map**——它在 contextual type 上扮演 identity 的角色。）

### Empty substitution map

像 `Int` 这样 generic signature 为空的 nominal type declaration，只声明了一个不带任何 generic argument 的 nominal type。这个类型的 context substitution map 叫做 **empty substitution map**，因为它既不存 replacement type 也不存 conformance。我们把它记作 `{}`。

这是空 generic signature **唯一**可能的 substitution map。若 `G` 是空 generic signature，那么 interface type 集合 `Type(G)` 就是所有不含任何 type parameter 的 fully-concrete type 的集合。Empty substitution map 不改变这样的类型，例如 `Int ⊗ {} = Int`。

不要把 empty substitution map 与某个非空 generic signature 的 identity substitution map 混为一谈。只要 original type 里含有任何 type parameter，应用 empty substitution map 都会把它们换成 error type：

```
τ_0_0.Element ⊗ {} = <<error type>>
```

## Nested Nominal Types

我们已经看到，generic signature 和 substitution map 用的是一种把所有外层 generic parameter 收拢到一起的**扁平**表示，而 nominal type 有一种递归结构，反映的是其 nominal type declaration 的词法嵌套关系。为一个 nominal type 构造 context substitution map 时，我们必须能在这两种表示之间来回翻译；特别是，我们必须能为 signature 的每个 generic parameter 都还原出一个 generic argument。这就对 nominal type declaration 之间**如何嵌套**施加了一些限制：

1. Struct、enum 和 class 不能嵌套在 generic 的 local context 里。
2. Struct、enum 和 class 不能嵌套在 protocol 或 protocol extension 里。
3. Protocol 不能嵌套在其他 generic context 里。

### Types in generic local contexts

这条限制源于一个事实：nominal type declaration 只能为**外层的 nominal type context** 编码 generic argument。如果一个 nominal type declaration 的 parent context 是一个不是类型的 generic context，那么这个 nominal type declaration 只声明单独一个不带任何 generic argument 的 nominal type。这使得我们无法正确地建模下面这段代码，它在今天是被拒绝的：

```swift
func f<T>(t: T) {
  struct Nested {  // error
    let t: T

    func printT() {
      print(t)
    }
  }
  
  Nested(t: t).printT()
}
```

局部类型声明 `Nested` 有一个类型为 `τ_0_0` 的 stored property，而 `τ_0_0` 是外层声明 `f()` 的 generic parameter。但 `Nested` 只声明了单独一个 nominal type，同样写作 `Nested`。这个类型既没有 parent type 也没有任何 generic argument，因为它并不嵌套在另一个 nominal type 内部。这意味着我们没有办法在 context substitution map 里填出 `τ_0_0` 的 replacement type：

```
Nested ⊗ {τ_0_0 ↦ ???} = Nested
```

如果我们用两种 generic argument type 调用 `f()`，SIL optimizer 可能会决定对其中一次或两次调用做特化：

```swift
func g() {
  f(t: 123)
  f(t: "hello")
}
```

我们会构造出把 `τ_0_0` 分别替换为 `Int` 或 `String` 的 substitution map，并把这张 substitution map 应用到 `f()` 函数体里出现的每一条 SIL 指令上。为了让 stored property 访问得到正确的 substituted type，我们必须能表示出 `Nested` 的这两个互不相同的 specialization。因此，我们其实希望 `Nested` 的 declared interface type 能为外层的 generic parameter 存一个 generic argument，也就是说，概念上我们希望能写出类似这样的东西：

```
<τ_0_0>.Nested ⊗ {τ_0_0 ↦ Int} = <Int>.Nested
```

Runtime type metadata 的表示本来就设计成存一张扁平的 generic argument 列表，和 generic signature 或 substitution map 一样。所以解除这条限制虽然需要编译器一侧的一些工程投入，但它会是一项可向后部署、且 ABI 兼容的改动。

### Types in protocol contexts

今天我们不允许 struct、enum 和 class 声明出现在 protocol 和 protocol extension 内部。解除这条限制有两种办法，区别在于这个 nominal type declaration 该不该捕获 protocol 的 `Self` 类型。看下面这个 protocol 和紧随其后的 protocol extension。注意 `Box` 有一个类型为 `τ_0_0.Contents` 的 stored property，因为 `Contents` 这个 associated type 的声明在 `Holder` 的词法作用域里是可见的：

```swift
protocol Holder {
  associatedtype Contents
  var contents: Contents { get }
}

extension Holder {
  struct Box {  // error today
    let contents: Contents  // depends on the outer Self
  }
  
  var box: Box {
    return Box(contents: contents)
  }
}
```

今天我们拒绝嵌套的 struct `Box`，但有一种可能的解释会允许这段代码。在这个模型里，`Box` 的 declared interface type 类似于「`τ_0_0.Box`」，但那并不是一个 dependent member type，而是一个 parent type 为 **type parameter** 的 nominal type。每个 conform to `Holder` 的 nominal type 都会获得一个名为 `Box` 的新成员类型声明，而 `Self` 的 generic argument 就是这个 parent type。也就是说，如果我们让类型 `Foo` conform to `Holder` 并调用 `box()`，得到的会是一个类型为 `Foo.Box` 的值：

```swift
struct Foo: Holder {
  typealias Contents = Int
}

let x: Foo.Box = Foo.box(123)  // imaginary
```

这样一来，`Foo.Box` 的 context substitution map 就是那个 conformance 的 protocol substitution map：

```
τ_0_0.Box ⊗ {τ_0_0 ↦ Foo; [τ_0_0: Holder] ↦ [Foo: Holder]} = Foo.Box
```

在这个模型下，把 `Box` 当作 protocol 自身的成员来引用是讲不通的，也就是说 `Holder.Box` 不会是合法的。

另一种办法则禁止嵌套类型声明捕获 protocol 的 `Self` 类型。这种情况下，嵌套类型声明的 generic signature **不**包含 protocol 的 `Self` 类型，于是上面那样写的 `Box` 会因为它那个 stored property 而被禁止。在这个模型里，protocol 只是充当一个命名空间，嵌套类型不以任何其他方式依赖这个 protocol；那么嵌套类型就可以作为 protocol 类型自身的成员来引用，比如 `Holder.Box`。

### Protocols in generic contexts

历史上，protocol 只能声明在源文件的最外层。Swift 5.10（SE-0404）放宽了这一点，允许 protocol 任意嵌套在其他声明里面，只要那些声明不是 generic 的：

```swift
enum E {
  protocol P {}  // allowed as of SE-0404
}

struct S: E.P {}
```

不过，protocol 仍然被禁止出现在 generic declaration 内部：

```swift
struct G<T>(_: T) {
  protocol P {  // error
    func f() -> T  // because what would this mean?
  }
}
```

如果一个 protocol 可以像这样依赖外层的 generic parameter，那么它的 protocol generic signature 除了 `Self` 之外还会含有那些参数及其 requirement。Haskell 把这个叫做 **multi-parameter type class**。

实际效果是，一个 generic protocol 的每一种 specialization 都会是一个不同的类型，而同一个具体的 conforming 类型可以 conform to 这个 generic protocol 的多个 specialization，每个 conformance 有各自不同的实现：

```swift
struct S: G<Int>.P {...}
struct S: G<String>.P {...}
```

这会是一次重大变更。今天，一条 conformance requirement `[T: P]` 实质上是关于这个 type parameter 的一元谓词——一个非真即假的陈述。而对一个 generic protocol 的 conformance 则是一种更一般的关系，它关联了**多个** type parameter，这些参数全都「参与」到这个 conformance 里。这至少意味着要把上一章那套形式系统连同 Part IV（Requirement Machine）的大部分内容彻底重想一遍。想对这个特性带来的复杂度再有个概念，可参阅 Sulzmann、Schrijvers 与 Stuckey 2006 年的《Principal Type Inference for GHC-Style Multi-parameter Type Classes》。

> 译注：原书这段示例代码 `struct G<T>(_: T) { ... }` 不是合法的 Swift 写法（struct 声明后不应跟参数列表），疑为笔误；此处照译原文，语义以「一个 generic struct `G<T>` 内部嵌套 protocol `P`」为准。

## Composition

假设有三个 generic signature `G`、`H`、`I`，以及一对 substitution map `Σ_1 ∈ Sub(G → H)`、`Σ_2 ∈ Sub(H → I)`。取任意一个 interface type `X ∈ Type(G)`，把 `Σ_1` 应用到 `X` 上得到 `X ⊗ Σ_1 ∈ Type(H)`。再把 `Σ_2` 应用到 `X ⊗ Σ_1` 上，就得到 `Type(I)` 的这个元素：

```
(X ⊗ Σ_1) ⊗ Σ_2
```

现在来想想，怎样才能一步就从 `X` 走到 `(X ⊗ Σ_1) ⊗ Σ_2`。

**定义.** Substitution map `Σ_1` 与 `Σ_2` 的 **composition**，记作 `Σ_1 ⊗ Σ_2`，定义为满足下述恒等式（对一切 `X ∈ Type(G)`）的唯一那张 substitution map：

```
X ⊗ (Σ_1 ⊗ Σ_2) := (X ⊗ Σ_1) ⊗ Σ_2
```

由于 `(X ⊗ Σ_1) ⊗ Σ_2 ∈ Type(I)`，可知 `Σ_1 ⊗ Σ_2 ∈ Sub(G → I)`；也就是说，`Σ_1 ⊗ Σ_2` 的 input generic signature 是 `Σ_1` 的 input generic signature，而 `Σ_1 ⊗ Σ_2` 的 output generic signature 是 `Σ_2` 的 output generic signature。Substitution map composition 给出了这样一个集合之间的映射：

```
Sub(G → H) ⊗ Sub(H → I) ⟶ Sub(G → I)
```

简单地说：把两张 substitution map 的 composition 应用到一个 interface type 上，结果与先后应用第一张、第二张是一样的。下面看怎么构造 `Σ_1 ⊗ Σ_2`。先假设 `Σ_1` 的 input generic signature `G` 不声明任何 conformance requirement，于是 `Σ_1` 的行为完全由它的 replacement type 决定：

```
Σ_1 := {…, τ_d_i ↦ (τ_d_i ⊗ Σ_1), …}
```

要构造 `Σ_1 ⊗ Σ_2`，我们把 `Σ_2` 应用到 `Σ_1` 的每一个 replacement type 上：

```
Σ_1 ⊗ Σ_2 := {…, τ_d_i ↦ ((τ_d_i ⊗ Σ_1) ⊗ Σ_2), …}
```

于是对 `G` 的所有 generic parameter `τ_d_i`，下面这个恒等式立即成立，而它完全确定了 `Σ_1 ⊗ Σ_2`：

```
τ_d_i ⊗ (Σ_1 ⊗ Σ_2) = (τ_d_i ⊗ Σ_1) ⊗ Σ_2
```

在 `G` 声明了一条或多条 conformance requirement 的一般情形下，`Σ_1` 还存了一张 **root conformance** 列表。此时 substitution map composition 还需要把 `Σ_2` 应用到 `Σ_1` 的每一个 root conformance 上，才能正确构造出新的 substitution map。Conformance substitution 会在 `conformances.tex` 的 Conformance Substitution 一节解释。

**例（compose substitution maps）.** Substitution map composition 能帮我们推理链式 member reference expression 的类型，比如下面「`x`」的类型：

```swift
struct Outer<T> {
  var inner: Inner<Optional<T>, Bool>
}

struct Inner<T, U> {
  var value: (T, U)
}

let outer: Outer<Int> = ...
let x = outer.inner.value  // What is the type of `x'?
```

先看 `Outer` 的「`inner`」这个 stored property 的类型。把它的 context substitution map 记作 `Σ_1`：

```
Σ_1 := {τ_0_0 ↦ Optional<τ_0_0>, τ_0_1 ↦ Bool}
```

注意 `Σ_1` 的 input generic signature 是 `Inner` 的 generic signature——也就是被引用的那个声明——而 `Σ_1` 的 output generic signature 是 `Outer` 的 generic signature，即引用所在的那个声明。

接着看全局变量「`outer`」的类型。把它的 context substitution map 记作 `Σ_2`：

```
Σ_2 := {τ_0_0 ↦ Int}
```

`Σ_2` 的 input generic signature 是 `Outer` 的 generic signature，恰是 `Σ_1` 的 output generic signature，所以这两张 substitution map 可以 compose：

```
Σ_1 ⊗ Σ_2 = {τ_0_0 ↦ Optional<Int>, τ_0_1 ↦ Bool}
```

最后，看 `Inner` 的「`value`」这个 stored property 的 interface type，它是 tuple type `(τ_0_0, τ_0_1)`。表达式「`outer.inner.value`」的类型可以从这个 original type 用两种方式推出来：依次应用两张 substitution map，或者应用它们的 composition：

```
(τ_0_0, τ_0_1) ⊗ Σ_1 ⊗ Σ_2
    = (Optional<τ_0_0>, τ_0_1) ⊗ Σ_2
    = (Optional<Int>, Bool)

(τ_0_0, τ_0_1) ⊗ (Σ_1 ⊗ Σ_2)
    = (τ_0_0, τ_0_1) ⊗ {τ_0_0 ↦ Optional<Int>, τ_0_1 ↦ Bool}
    = (Optional<Int>, Bool)
```

### Commutative diagrams

一张 **commutative diagram**（交换图）展示一组对象与操作，每个操作由一条带标签的箭头表示。当我们说这张图**交换**时，意思是：只要有两条起点相同、终点也相同的路径，那么沿任一路径依次执行其上的操作，最终得到的结果相同。例如，上面那条 substitution map composition 的定义可以用这张图来表示：

```
              Σ_1
      X ──────────────→ X ⊗ Σ_1
        ╲                  │
         ╲                 │ Σ_2
Σ_1 ⊗ Σ_2 ╲                ↓
           ╲──→ (X ⊗ Σ_1) ⊗ Σ_2
```

这张图断言的是：从 `X` 出发，先走 `Σ_1` 再走 `Σ_2`，与一步走 `Σ_1 ⊗ Σ_2`，落到同一个类型上——这恰好就是 composition 的定义式。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

后面还会见到更有意思的交换图。

### Identity substitution map

我们在上文 Nominal Types 一节见过：每个 generic signature 都有一张 identity substitution map。只要我们把 generic parameter 原样转发给另一个 generic declaration 作实参，identity substitution map 就会出现。现在来看 identity 在 composition 下的表现，有两种情形。

若 `Σ ∈ Sub(G → H)`，我们可以在**左边**把 `Σ` 与 identity substitution map `1_G` 复合。这会把 `Σ` 应用到 `1_G` 的每个 replacement type 上，而那不过是依次投影出 `Σ` 的每个 replacement type；于是我们装配出一张与 `Σ` 完全相同的 substitution map：

```
1_G ⊗ Σ = Σ                                              (1)
```

我们也可以在**右边**把 `Σ` 与 `1_H` 复合。这会把 `1_H` 应用到 `Σ` 的每个 replacement type 上。由前面关于 identity substitution map 的讨论可知，这不改变 `Σ` 的 replacement type，所以同样得到：

```
Σ ⊗ 1_H = Σ                                              (2)
```

> 译注：原书这两个公式的编号都写成了 `(1)`，但紧接着的正文说「(1) 仍然成立，而 (2) 不成立」，可见第二式本应编号为 `(2)`，疑为笔误；此处按 `(1)`/`(2)` 编号译出。

这里补一句关于 primary archetype 的话——它要到 `archetypes.tex` 才正式登场。我们对 `Sub(G → H)` 的定义是刻意构造的，它排除了那些 replacement type 含有 primary archetype 的 substitution map。如果把这类 substitution map 也考虑进来，那么 (1) 仍然成立，但 (2) 不成立。在 `archetypes.tex` 的 Primary Archetypes 一节我们会看到，此时扮演 identity 角色的是另一张 substitution map——**forwarding substitution map**，而这类类型我们称为 **contextual type**。

### Order of operations

有一个我们不加证明就直接陈述的事实：substitution map composition 是一个**结合**运算。也就是说，若 `Σ_1`、`Σ_2`、`Σ_3` 是任意三张使得下面各次 composition 都有定义的 substitution map，则：

```
(Σ_1 ⊗ Σ_2) ⊗ Σ_3 = Σ_1 ⊗ (Σ_2 ⊗ Σ_3)
```

举例来说，这意味着当 `X` 是任意 interface type 时，下面所有表达式必定产生同一个 substituted type：

```
((X ⊗ Σ_1) ⊗ Σ_2) ⊗ Σ_3
(X ⊗ Σ_1) ⊗ (Σ_2 ⊗ Σ_3)
(X ⊗ (Σ_1 ⊗ Σ_2)) ⊗ Σ_3
X ⊗ ((Σ_1 ⊗ Σ_2) ⊗ Σ_3)
X ⊗ (Σ_1 ⊗ (Σ_2 ⊗ Σ_3))
```

因此，我们的记法里可以放心省掉括号而不致歧义：

```
X ⊗ Σ_1 ⊗ Σ_2 ⊗ Σ_3
```

### Categorically speaking

这一小节别处用不到，但值得简单提一句：有一种数学抽象刚好刻画了 substitution map composition 的性质。一个 **category**（范畴）由一组 **object**（对象）和一组 **morphism**（态射）构成。一个 morphism 有一个 **source** 对象和一个 **destination** 对象，source 为 `A`、destination 为 `B` 的全体 morphism 记作 `Hom(A, B)`。这些 morphism 必须满足若干公理：

1. 对每个对象 `A`，存在一个 **identity morphism** `1_A ∈ Hom(A, A)`。
2. 若 `f ∈ Hom(A, B)` 且 `g ∈ Hom(B, C)`，则存在一个 morphism `g ∘ f ∈ Hom(A, C)`，称为 `g` 与 `f` 的 **composition**。（常规记法 `g ∘ f` 与函数应用写在左边时的 `g(f(x))` 保持一致。）
3. Composition 与 identity 相容：若 `f ∈ Hom(A, B)`，则 `f ∘ 1_A = 1_B ∘ f = f`。
4. Composition 是结合的：若 `f ∈ Hom(A, B)`、`g ∈ Hom(B, C)`、`h ∈ Hom(C, D)`，则 `h ∘ (g ∘ f) = (h ∘ g) ∘ f`。

举例来说，我们可以这样定义 **the category of interface types**：

- 对象是各个集合 `Type(G)`，每个 generic signature `G` 一个。
- Substitution map 是 morphism，`Hom` 就是 `Sub`。
- Morphism `Σ ∈ Sub(G → H)` 的 source 是 `Type(G)`。
- Morphism `Σ ∈ Sub(G → H)` 的 destination 是 `Type(H)`。
- Identity substitution map 是 identity morphism。
- Morphism composition `g ∘ f` 就是 substitution map composition `f ⊗ g`。

它恰好是一个 **concrete** category——每个对象都是集合，每个 morphism 都是集合之间的函数——不过一般情况下不必如此。在编程中我们常常在处理数据结构和高阶函数时碰到范畴论；这方面一本极好的入门读物是 Milewski 2018 年的《Category Theory for Programmers》。

## Subclassing

Swift 语言支持 **subclassing**，也叫 **inheritance**（继承）。做一些铺垫之后，我们会用 type substitution algebra 来描述 subclassing 与泛型之间的相互作用。这在后面几章讨论 superclass requirement 的语义时会派上用场。由于 superclass requirement 并不是 Swift 泛型核心模型的必要组成部分，读者第一遍读时可以放心跳过本节。

当某个 class declaration（称为 **subclass**）在它的 inheritance clause 里写出一个 **superclass type** 时，就建立起了一种继承关系。与 C++ 不同，Swift 不允许多重继承，所以一个 class declaration 至多有一个 superclass type。与 Java 也不同，Swift 的继承层次根部没有一个特殊的 `Object` 类，所以完全没有 superclass type 的 class declaration 很常见。

**例.** 先看 superclass 和 subclass 都不是 generic 的情形。下面 `Apple` 和 `Banana` 都写出了 superclass type `Fruit`：

```swift
class Fruit {
  func eat() {...}
  func juice() {...}
}

class Apple: Fruit {
  override func eat() {...}
}

class Banana: Fruit {}

let f: Fruit = Apple()  // implicit conversion from Apple to Fruit
f.eat()                 // vtable-dispatched call to Apple.eat()
```

在 expression type checker 看来，`Apple` 和 `Banana` 是 `Fruit` 的 **subtype**。正因如此，我们才能把 `Apple()` 构造器调用的结果赋给类型为 `Fruit` 的变量 `f`。这可以用一张 class hierarchy diagram 来表示：

```
        Fruit
        ↑   ↑
       ╱     ╲
   Apple     Banana
```

> 译注：原书此处是一张 TikZ 类层次图，这里用 ASCII 图转述；箭头由 subclass 指向 superclass。图的原貌见官方 PDF 对应章节。

Qualified lookup 会沿着类层次向上走，所以对 `Apple` 或 `Banana` 的 qualified lookup 也会找到 `Fruit` 的成员。此外，subclass 可以 **override** 其 superclass 中声明的方法、属性和 subscript。上面 `Apple` 就用自己的实现 override 了 `Fruit.eat()`。

一个 `Fruit` 的实例在运行时可能实际上是一个 `Apple`，所以对一个静态类型为 `Fruit` 的值调用 `eat()`，必须经由存在对象头部的 **vtable** 来派发。`Fruit` 的 vtable 指向 `Fruit` 自己对 `eat()` 与 `juice()` 的原始实现，而 `Apple` 的 vtable 把 `eat()` 那一格换成指向 `Apple.eat()` 的指针。

**例.** 接下来，假设我们声明一个 `Fruit` 的 generic subclass。注意我们 override 了 `Fruit.eat()` 来打印 `τ_0_0` 的具体 replacement type：

```swift
class Pear<T>: Fruit {
  override func eat() {
    print(T.self)
  }
}
```

有了上面的 `Pear`，我们可以构造出各种 generic class type，比如 `Pear<Int>`、`Pear<Bool>` 等等；它们都是把某张 substitution map 应用到 declared interface type `Pear<τ_0_0>` 上得到的。这个例子的关键事实是：`Pear` 的每一种 specialization 都有**同一个** superclass type `Fruit`，因为 `Pear` 的 superclass type 并不依赖它的 generic parameter `τ_0_0`。因此在 expression type checker 看来，`Pear` 的所有 specialization 都是 `Fruit` 的 subtype。现在完整的类层次图是无限的，不过这里给出其中一部分：

```
                    Fruit
            ↑         ↑         ↑
           ╱          │          ╲
  Pear<Int>      Pear<Bool>      Pear<τ_0_0>
```

> 译注：原书此处是一张 TikZ 类层次图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

这个例子实现的是一种叫 **type erasure**（类型擦除）的设计模式。取任意 `X` 的一个 `Pear<X>` 类型的值，我们总能把它转换成 `Fruit` 类型的值，于是就把 generic argument `X` 从结果值的静态类型里**擦掉**了。这使得类型 `X` 可以动态变化。下面 `f` 的静态类型只是 `Fruit`，但其中所存值的动态类型要么是 `Pear<Int>` 要么是 `Pear<String>`，取决于一次任意检查的结果：

```swift
let someCondition: Bool = ...
let p1 = Pear<Int>()
let p2 = Pear<String>()
let f: Fruit = (someCondition ? p1 : p2)
```

在 `existential-types.tex` 里我们会学到 **existential type**，那是语言内建的另一种更一般的类型擦除机制，建立在 protocol 之上。

### Generic superclasses

有意思的情形出现在 subclass 与 superclass 都是 generic 的时候。一个 class declaration 的 superclass type 是一个 interface type，所以它可以含有来自 subclass 的 generic signature 的 type parameter。例如：

```swift
class StoneFruit<T> {}
class Mango<U>: StoneFruit<Array<U>> {}
```

在某些场合我们完全不关心 generic argument，此时我们说 `Mango` 的 **superclass declaration** 是 `StoneFruit`。但完整的关系体现在：`Mango` 的 superclass **type** 是 `StoneFruit<Array<τ_0_0>>`。我们也可以求一个 class **type** 的 superclass type——所谓 class type，指的是带一串 generic argument 的、对某个 class declaration 的特化引用。这是用「把一张 substitution map 应用到 class declaration 的 superclass type 上」来定义的。

**算法（Get superclass type）.** 输入一个 class type `C`。返回 `C` 的 superclass type；若 `C` 没有 superclass type 则返回 null。

1. 令 `c` 为 `C` 的 class declaration。若 `c` 没有 superclass type，返回 null。
2. 令 `S` 为 `c` 的 superclass type。
3. 令 `Σ` 为 `C` 的 context substitution map。
4. 返回 `S ⊗ Σ`。

**例.** Class type `Mango<Int>` 是把 substitution map `{τ_0_0 ↦ Int}` 应用到 declared interface type `Mango<τ_0_0>` 上得到的。要算 `Mango<Int>` 的 superclass type，我们把这张 substitution map 应用到该声明的 superclass type `StoneFruit<Array<τ_0_0>>` 上：

```
StoneFruit<Array<τ_0_0>> ⊗ {τ_0_0 ↦ Int} = StoneFruit<Array<Int>>
```

下面这张类层次图展示了 `Mango<Int>` 与 `Mango<Bool>` 这两个类型之间的关系（或者说，它们之间没有关系）：

```
StoneFruit<Array<Int>>          StoneFruit<Array<Bool>>
          ↑                                ↑
          │                                │
     Mango<Int>                       Mango<Bool>
```

> 译注：原书此处是一张 TikZ 类层次图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

现在来看 `Mango<τ_0_0>` 的 superclass type。本章开头我们看到，declared interface type 的 context substitution map 就是 identity substitution map。确实，既然 `Mango<τ_0_0>` ⊗ `{τ_0_0 ↦ τ_0_0}` = `Mango<τ_0_0>`，那么 `Mango<τ_0_0>` 的 superclass type 就是 `StoneFruit<Array<τ_0_0>>`，与 `Mango` 这个声明的 superclass type 相同。

假设交给上面 Get superclass type 算法的 class type `C` 是某个 generic signature `H` 的一个 interface type，即 `C ∈ Type(H)`。若第 2 步里 `c` 的 generic signature 是 `G`，则第 1 步得到的 `Σ ∈ Sub(G → H)`。我们已经说过 `c` 的 superclass type `S` 是 `Type(G)` 的元素，所以结果 `S ⊗ Σ ∈ Type(H)`。也就是说，`C` 的 superclass type 若存在，它仍然是 `H` 的一个 interface type。

并非每个 interface type 都有 superclass type。于是对每个 generic signature `H`，我们得到下面这个**部分**的集合映射，记作「`superclass`」：

```
superclass : Type(G) → Type(G)
```

> 译注：原书这一行的正文说的是「对每个 generic signature `H`」，而公式两侧写的却都是 `Type(G)`，与上一段刚刚确立的 `C ∈ Type(H)`、`S ⊗ Σ ∈ Type(H)` 对不上，疑为笔误；此处照译原文，语义以 `superclass : Type(H) → Type(H)` 为准。

若 `C` 是一个 class type、`C′` 是 `C` 的 superclass type、`Σ` 是一张 substitution map，那么下面这张图是交换的：

```
                  Σ
      C  ────────────────→  C ⊗ Σ
      │                       │
 superclass              superclass
      ↓                       ↓
      C′ ────────────────→  C′ ⊗ Σ
                  Σ
```

这张图断言的是：「先取 superclass type，再代入 `Σ`」与「先代入 `Σ`，再取 superclass type」给出同一个类型——即 `superclass` 运算与 type substitution 可交换。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

**例.** 上一个例子可以重述成这样：

```
                          {τ_0_0 ↦ Int}
      Mango<τ_0_0>  ────────────────────→  Mango<Int>
           │                                    │
      superclass                           superclass
           ↓                                    ↓
StoneFruit<Array<τ_0_0>> ──────────────→ StoneFruit<Array<Int>>
                          {τ_0_0 ↦ Int}
```

这张图断言的是：对 `Mango<τ_0_0>` 先取 superclass 再代入 `{τ_0_0 ↦ Int}`，与先代入再取 superclass，都得到 `StoneFruit<Array<Int>>`。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

### Superclass substitution map

如果对一个 class type 的 qualified lookup 在类层次上往上走了一层或多层才找到某个成员，我们就需要为这次 member reference expression 构造正确的 substitution map。

**例.** 下面对一个 `Top<Int>` 类型的值调用 `method()` 时，这次调用的 substitution map 就是 `Top<Int>` 的 context substitution map，因为 `method()` 是 `Top` 的直接成员：

```swift
class Top<T> {
  func method() {}
}
Top<Int>().method()
```

但如果是在 `Top` 的某个 subclass 上调用 `method()`，情况就不同了：

```swift
class Mid<X, Y>: Top<(Y, X)> {}
class Bot: Mid<Int, Bool> {}
Bot().method()
```

Class type `Bot` 不是 generic 的，所以它的 context substitution map 是空的。然而我们需要的是 `method()` 的 generic signature `<τ_0_0>` 的一张 substitution map。注意从 `Bot` 出发，要走两跳才能到达 `method()` 的 parent context：先跳到 `Mid`，再跳到 `Top`。`Mid` 和 `Bot` 的 superclass type 如下：

```
superclass(Mid<τ_0_0, τ_0_1>) = Top<(τ_0_1, τ_0_0)> = Top<τ_0_0> ⊗ Σ_1
superclass(Bot)               = Mid<Int, Bool>      = Mid<τ_0_0, τ_0_1> ⊗ Σ_2
```

对应的两张 substitution map 是：

```
Σ_1 := {τ_0_0 ↦ (τ_0_1, τ_0_0)}
Σ_2 := {τ_0_0 ↦ Int, τ_0_1 ↦ Bool}
```

`Σ_1` 的 input generic signature 是 `Top` 的 generic signature，output generic signature 是 `Mid` 的 generic signature。同样，`Σ_2` 的 input generic signature 是 `Mid` 的 generic signature，output generic signature 是 `Bot` 的 generic signature，也就是空 generic signature。把这两张 substitution map 复合起来，得到：

```
Σ_1 ⊗ Σ_2 = {τ_0_0 ↦ (Bool, Int)}
```

这就是这次调用的 substitution map。特别地，当我们对一个 `Bot` 类型的值调用 `method()` 时，方法内部 `self` 参数的类型将是：

```
Top<τ_0_0> ⊗ Σ_1 ⊗ Σ_2 = Top<(Bool, Int)>
```

事实上，连续应用两次「`superclass`」也能得到同样的结果：

```
superclass(superclass(Bot)) = (Top<τ_0_0> ⊗ Σ_1) ⊗ Σ_2
```

我们可以把这件事一般化如下。给定一个 class type，外加被引用成员所属的那个 parent class declaration，我们必须沿着类层次往上走，一路收集 substitution，直到抵达那个 parent class。

**算法（Get superclass type for declaration）.** 输入一个 class type `C` 和一个 class declaration `d`。返回 `C` 相对于 `d` 的 superclass type。

1. 令 `c` 为 `C` 的 class declaration。若 `c = d`，返回 `C`。
2. 令 `S` 为 `c` 的 superclass type；若它没有 superclass type，则报告一次不变量违例。（那意味着 `d` 并不是原始 class type `C` 的 superclass，这种情况下 `d` 的成员本就不该作为 `C` 的成员可见。）
3. 令 `Σ` 为 `C` 的 context substitution map。置 `C ← S ⊗ Σ`，回到第 1 步。

注意这个算法返回的是「在被引用成员**内部**看到的」`self` 参数的类型。要得到这次引用的 substitution map，我们再向这个类型索取它的 context substitution map。这张 map 就是所谓的 **superclass substitution map**。

关于 subclassing 的讨论暂告一段落。在后面几节里我们还会更多地接触这个主题，特别是会看到它如何与 generic signature 里的 superclass requirement 交汇：

- `conformances.tex` 解释 subclass 如何从它的 superclass 继承 conformance。
- `archetypes.tex` 的 Local Requirements 一节解释当 archetype 的 type parameter 受一条 superclass requirement 约束时，archetype 的行为。
- `type-resolution.tex` 的 Identifier Type Representations 一节解释 type resolution 如何 resolve 一个指向 base type 的 superclass 中所声明成员类型的引用。
- `type-resolution.tex` 的 Generic Arguments 一节解释如何检查一张 substitution map 是否满足一条 superclass requirement。
- `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Decomposition and Desugaring 一节与 Requirement Minimization 一节解释「用户程序写出的一条 superclass requirement 是冗余的、或与另一条 requirement 冲突」是什么意思。

## SIL Type Lowering

本章最后，我们简单看一眼 SIL 的类型系统。回忆 SIL 是一种中间表示，由编译器的 SILGen pass 从 abstract syntax tree 构造出来。本节把出现在 abstract syntax tree 里的类型称为 **formal type**，以区别于 SIL 所用的 **lowered type**。把 formal type 翻译成 lowered type 的过程就是 **SIL type lowering**。

本节主要关心的是 SIL type lowering 与 type substitution 的关系。我们不指望在这里就把 SIL type lowering 完全弄明白，所以某些概念会被略去或不加解释。关于 SIL 与 SIL type 的更多细节，见《Swift Intermediate Language (SIL)》与《SIL Type Lowering》两份文档。读者也可以整节跳过，因为本书余下部分不需要这些材料。

### Loadable or address-only

大多数 formal type 同时也是 lowered type，此时 SIL type lowering 直接把原来的 formal type 返回。一个主要的例外与函数的类型有关。`types.tex` 的 More Types 一节讲的那种 function type（本节称之为 **formal** function type）与 SIL 里函数的类型不同，后者是一种不出现在 abstract syntax tree 里的类型：**SIL function type**。与 formal function type 相比，SIL function type 编码了更多关于 calling convention 的细节。我们先看其中一个细节。

SIL function type 显式地标明每个 **lowered parameter** 和 **result** 是可以通过寄存器传递，还是必须间接传递——即通过一个指向内存中某个值的指针。如果参数的 lowered type 是 **loadable** 的，它就直接传递；否则这个 lowered type 就是 **address-only** 的，必须间接传递。几乎所有 lowered type 都是 loadable 的，例外是下面这些：

1. Type parameter type 与 archetype type，在它们不受 `AnyObject` layout constraint 约束（见 `declarations.tex` 的 Requirements 一节）时是 address-only 的。

   （这类类型的值在编译期大小未知。）

2. Weak reference type（见 `types.tex` 的 Special Types 一节）是 address-only 的。

   （虽然一个 weak reference 只不过是某个 class 实例的地址，但每个 weak reference 所在的位置都必须时刻登记在 Swift runtime 里，所以它们只能「存在」于内存中。）

3. 声明是 **resilient** 的 struct type 与 enum type 是 address-only 的。

   （我们在 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)） 的 Module System 一节简单谈过 resilience 模型，更深入的讨论超出本书范围。细节见 Slava Pestov 2020 年的博文《Library evolution in Swift》与 Jordan Rose、Slava Pestov 的《Library Evolution》文档。）

4. 聚合类型是 address-only 的，例如元素含 address-only 类型的 tuple、stored property 含 address-only 类型的 struct、case 含 address-only 类型的 enum。

   （「是 address-only 的」这个性质对包含关系是**传递**的。）

5. Existential type（见 `existential-types.tex`）在不受 `AnyObject` 约束时是 address-only 的。

   （这类类型的值可以**装**一个 address-only 类型的值，所以 existential container 自身必须是 address-only 的。）

在讨论一般情形之前，先看几个例子。

**例（loadable 与 address-only）.** 标准库的 `Int` 与 `String` 类型是 loadable 的，下面这个 `Loadable` struct type 也是，因为它的 stored property 都是 loadable 的：

```swift
struct Loadable {
  var x: Int
  var y: String
}
```

另一方面，下面这个 `AddressOnly` struct 是 address-only 的，因为它含有一个 weak reference：

```swift
struct AddressOnly {
  weak var x: AnyObject?
}
```

对 generic nominal type 来说，判断一个类型是不是 address-only 需要用到 type substitution。

**例（lowering optional）.** 先看标准库的 `Optional` enum：

```swift
public enum Optional<Wrapped> {
  case none
  case some(Wrapped)
}
```

本节把由这个声明构成的 generic nominal type 称为「optional type」。（不要与 `types.tex` 的 More Types 一节里那个写作 `Int?` 的 optional sugared type 混淆——不过后者 desugar 之后就是前者。）

一个 optional type 的 generic argument 叫做这个 optional 的 **payload type**。在内存中，一个 optional type 的值必须大到足以存下 payload，外加一个标明当前选中的是 `none` 还是 `some` 的 tag 值。（这个 tag 有时也编码在 payload **内部**，见《Type layout》文档。）

一个 optional type 是 loadable 的，当且仅当它的 payload type 是 loadable 的。因此 `Optional<Int>` 是 loadable 的，而以前一个例子里的 `AddressOnly` 为 payload 的 `Optional<AddressOnly>` 是 address-only 的。

> 译注：这里的 tag「编码在 payload 内部」正是本库 enum 布局文档反复处理的 extra inhabitant 机制；本库既有运行期的精确投影，也有纯离线的公式推算。见 [SwiftEnumLayout_zh.md](../../SwiftEnumLayout_zh.md) 与 [RuntimeEnumCaseProjection.md](../RuntimeEnumCaseProjection.md)。

**例.** 接着看这个 enum 声明，它与 `Optional` 完全一样，只是「`some`」这个 case 被声明成了 `indirect`：

```swift
enum IndirectOptional<Wrapped> {
  case none
  indirect case some(Wrapped)
}
```

`indirect` 的 enum case 不是把 payload 内联存储，而是用单个引用计数指针表示，该指针指向一个堆上分配的 box。正因如此，`IndirectOptional<Int>` 和 `IndirectOptional<AddressOnly>` 都是 loadable 的。

**例.** 下面这个 generic struct 声明完全没有 stored property：

```swift
struct Phantom<T> {}
```

因此 `Phantom<Int>` 和 `Phantom<AddressOnly>` 都是 loadable 的。

**例.** 当一个类型含有 type parameter 时，它属于哪一类取决于引用它的 generic context：

```swift
func f<T, U: AnyObject>(_ t: T, _ u: U) {
  let x: Optional<T> = ...  // address-only
  let y: Optional<U> = ...  // loadable
}
```

`x` 的类型是 address-only 的，因为 `T` 无约束；而 `y` 的类型是 loadable 的，因为 `U` 受一条 `AnyObject` layout constraint 约束。

现在来看算法。按这里的写法，它同时接受 formal type 和 lowered type。在实际实现中它只作用于 lowered type，而且我们会用同样的方式顺带算出该类型布局的若干其他性质。

**算法（Decide if type is address-only）.** 输入一个类型 `X`；当 `X` 含有 type parameter 时，还要附带一个可选的 generic signature `G`。输出「loadable」或「address-only」之一。

1. 若 `X` 是一个 **type parameter**，记 `X = T`：求值 generic signature query `requiresClass(G, T)`。若查询结果为真，返回「loadable」，否则返回「address-only」。
2. 若 `X` 是一个 **archetype type**（见 `archetypes.tex`）：同上处理，但把 `G` 换成 archetype 内部所存的那个 generic signature。
3. 若 `X` 是一个 **weak reference type**，返回「address-only」。
4. 若 `X` 是一个 **struct type**，记 `X = X_d ⊗ Σ`，其中 `Σ` 是 context substitution map、`X_d` 是其 struct declaration `d` 的 declared interface type，那么对 `d` 的每一个 stored property：
   1. 令 `Y` 为该 stored property 的 interface type。
   2. 计算 substituted type `Y ⊗ Σ`。
   3. 递归检查 `Y ⊗ Σ` 是否 address-only。
   4. 若它是 address-only 的，立即返回「address-only」。

   否则，若所有 substituted 后的 stored property 类型都是 loadable 的，返回「loadable」。

5. 若 `X` 是一个 **enum type**：
   1. 检查该 enum declaration 是不是 `indirect`；若是，返回「loadable」。
   2. 否则按 struct 的情形处理，但只考虑那些**没有**声明为 `indirect` 的 enum case。

      （一个 `indirect` case 的 lowered type 永远是指向堆上分配的 box 的引用计数指针，而这种指针是 loadable 的。若 enum 自身是 `indirect` 的，我们就当作每个 case 都是 `indirect` 的来处理。）

6. 若 `X` 是一个 **tuple type**，递归检查 `X` 的每个元素类型是否 address-only。只要有任何一个是 address-only 的，返回「address-only」；否则返回「loadable」。
7. 若 `X` 是一个 **existential type**，检查该 existential type 是否满足 `AnyObject` layout constraint。若满足，返回「loadable」，否则返回「address-only」。
8. 若 `X` 是一个 **class type**、**metatype type** 或 **（SIL）function type**，返回「loadable」。

> 译注：本库的 `ExistentialLayoutBridge` 离线复刻的正是第 7 条所依赖的那套 existential container 尺寸规则（class-bound 与否决定容器宽度），`StaticLayoutCalculator` 则复刻了第 4、6 两条的聚合累加。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Exploding tuples

一个 formal function type 有零个或多个参数类型，以及**恰好一个**返回类型。这个返回类型可以是 tuple type，我们就是用它来建模「没有返回值」或「有多于一个返回值」的情形。

与 formal function type 一样，SIL function type 也有零个或多个 lowered parameter type；但与 formal function type 不同，SIL function type **还**有零个或多个 lowered result type。当一个 tuple type 出现在 formal function type 的参数列表或返回类型里时，SIL type lowering 会把它「炸开」（explode）成多个 lowered parameter 或 lowered result。

Lowered parameter 和 lowered result 都带有一个 **convention** 标注，它编码了两件事：值是在寄存器里直接传递还是通过内存间接传递，以及在调用过程中值的 ownership 如何变化：

1. 直接性由 lowered parameter 或 result 的类型决定；若类型是 loadable 的，我们**可以**直接传（但有时仍必须间接传，下文会看到）；当它是 address-only 时，就必须间接传。
2. 对 ownership 的讨论超出本书范围，细节见《SIL Type Lowering》文档。

SIL function type 还有一个整体的 convention 标记。可选的 convention 是 formal function type 那一组（见 `types.tex` 的 More Types 一节）的超集。对我们来说需要的是两个：`@convention(thin)`，用于不捕获值的函数（例如全局函数与方法）；`@convention(thick)`，用于捕获值的函数（例如 closure expression）。一个 thick function 值由一个函数指针加一个 **context** 组成，context 可用来存放被捕获的值——调用方把 context 作为一个额外参数传进去。最后，SIL function type 还有一个 generic signature。

**例.** 下面是一个有两个参数的函数声明，第二个参数是 tuple，其第二个元素是前面那个 address-only 的类型：

```swift
func foo(x: Int, y: (String, AddressOnly)) {}
```

编译器打印这个声明的 SIL function type 时用的记法如下（例如把上面的声明和先前的 `AddressOnly` struct 放进同一个源文件，然后用 `-emit-silgen` 标志构建）：

```
@convention(thin)
(Int, @guaranteed String, @in_guaranteed AddressOnly) -> ()
```

`Int` 参数没有 convention 标注，所以它是直接传的。`Int` 类型是 **trivial** 的，其值可以在不考虑 ownership 的情况下移动和复制。`String` 参数也是直接传的，但这次 `@guaranteed` convention 表明该字符串的 ownership 由调用方保留。最后，`AddressOnly` 参数是 address-only 的，所以用 `@in_guaranteed` convention 间接传值，同样由调用方保留 ownership。由于 `foo()` 没有写返回类型，这个 SIL function type 有零个 result。

**例.** 下面是一个返回 tuple 的 generic function：

```swift
func flip<T, U>(t: T, u: U) -> (U, T) {
  return (u, t)
}
```

它的 SIL function type 是：

```
@convention(thin)
<T, U> (@in_guaranteed T, @in_guaranteed U) -> (@out U, @out T)
```

两个参数都是间接传的，且由调用方保留 ownership（所以函数的实现实际上必须复制这些值）。这个 SIL function type 还间接返回两个 result（在机器层面，调用方提供一对足够大的返回缓冲区来容纳这两个结果）。

### Re-abstraction thunks

所以，要得到一个函数声明或 closure expression 的 SIL function type，我们取它的 interface type（那是一个 formal function type），把参数列表和返回类型里的 tuple 炸开，算出每个 parameter 和 result 属于哪一类，再做另外几件事，然后构造出我们的 SIL function type。当然，其中某些 parameter 和 result 类型本身也可能是 function type，我们会递归地把那些 function type 也 lower 掉。这已足以解释 SILGen 在直接调用函数与闭包时的行为，但还不是全部。

要弄明白一个函数值在 generic context 之间传递时会发生什么，我们得谈谈 **abstraction pattern**（抽象模式）。编译器里 SIL type lowering 这个操作接收的不只是一个 formal type，还有一个 abstraction pattern。

这个复杂性的来由如下。当一张 substitution map 被应用到一个 SIL function type 上时，SIL function type 里的 type parameter 会被替换成具体类型。然而，substitution **不会**改变这个 SIL function type 的 parameter 和 result 的直接性。如果某个原本的 type parameter 是 address-only 的、而它的 replacement type 是 loadable 的，那么得到的 SIL function type 就会与「直接把 substituted formal type lower 一遍」所得到的不同。通常，一个 closure expression 是以「自然的」abstraction pattern——也就是它自己的 formal type——发射出来的。要改变一个函数值的 abstraction pattern，SILGen 会把这个函数值包进一个 **re-abstraction thunk** 里。thunk 有两种：

1. **substituted-to-original thunk** 出现在把闭包传进一个 generic function 的时候。它把一个「以自身为 abstraction pattern lower 出来」的 function type，包成一个「以更一般的 abstraction pattern lower 出来」的 function type。
2. **original-to-substituted thunk** 出现在从一个 generic function 返回闭包的时候。它把一个「以更一般的 abstraction pattern lower 出来」的 function type，包成一个「以完全 substituted 的 abstraction pattern lower 出来」的 function type。

**例（abstraction pattern）.** 看这个颇为无聊的 generic function，它把一个闭包应用到一个值上并返回结果：

```swift
func apply<T>(_ x: T, _ fn: (T) -> T) -> T {
  return fn(x)
}
```

假设我们这样调用它，对应的 substitution map 是 `Σ := {τ_0_0 ↦ String}`：

```swift
let fn: (String) -> String = { $0.uppercased() }
let result = apply("hello world", fn)
```

如果把 `Σ` 应用到 `apply()` 的「`fn`」参数的 formal type 上，得到：

```
[(τ_0_0) -> τ_0_0] ⊗ Σ = (String) -> String
```

上面这个 formal type 与调用方作为实参传进来的那个 closure expression 的 formal type 完全相同。现在来看 lowered type。由于 `String` 是 loadable 的，把上面那个 formal type lower 掉会得到：

```
@convention(thick) (@guaranteed String) -> (@owned String)
```

另一方面，「`fn`」参数的 lowered type 是间接传参、间接返回结果的：

```
@convention(thick) <T> (@in_guaranteed T) -> (@out T)
```

最后，如果把 `Σ` 应用到这个 SIL function type 上，得到：

```
@convention(thick) (@in_guaranteed String) -> (@out String)
```

为了调和这个差异，SILGen 在把闭包交给 `apply()` 之前，先用一个 substituted-to-original thunk 把它包起来。这个 thunk 接收一个指向 `String` 的指针，把它 load 出来，用 load 到的值调用被包裹的闭包。闭包直接返回一个新的 `String`，thunk 在返回前把它存进间接结果缓冲区。

### More about abstraction patterns

就我们的目的而言，一个 abstraction pattern 无非就是那个「未经 substitution 的 formal type」，用来计算 SIL function type 里每个 parameter 和 result 的直接性。（实际上，abstraction pattern 还携带一个 **kind** 和一些附加信息，但这里不需要细到那个程度。）于是，一个 re-abstraction thunk 基本上就是一个包着另一个闭包的闭包。Thunk 的函数体接过每个参数、转发给被包裹的闭包，再把被包裹闭包的结果取回来返给 thunk 的调用方。在这个过程中，re-abstraction thunk 可以改变 parameter 与 result 的 convention。

这里还要提一个有用的 peephole 优化。很多时候，被 re-abstract 的闭包本身就是一个字面的 closure expression，此时 SILGen 能够直接以期望的 abstraction pattern 发射这个闭包，而不必立刻把它包进 thunk。这避免了一次不必要的堆分配。

### Opaque abstraction patterns

Type lowering 会「并行地」遍历 formal function type 与 abstraction pattern，以构造出 SIL function type。Abstraction pattern 必须与 formal type 形状相同，意思是 formal type 应当可以由 abstraction pattern 经 substitution 得到。举例来说，abstraction pattern `(Int, τ_0_1) -> τ_0_2` 与 formal type `(Int, (Bool, String) -> Float) -> Bool` 是相容的，但与 formal type `(Bool, Int, String) -> (Float, Float)` 不相容——后者的参数个数对不上，返回类型也对不上。

这种「并行分解」的实现基本上是显而易见的，唯一的例外是 abstraction pattern 由单个 type parameter 构成的时候。实现里把它称为 **opaque** abstraction pattern（不要与 opaque parameter 或 opaque result type 混淆）。这种情况下，我们以「最一般」的方式 lower 这个 formal function type：当作它的每一个 parameter 和 result 都是间接传的，并且不炸开 tuple。接下来三个例子会说明这一点。

**例.** 把 abstraction pattern 那个例子里的 `apply()` 函数改成接收一个闭包数组，同时把闭包的参数类型写成具体类型：

```swift
func apply1<T>(_ x: String, _ fns: [(String) -> T]) -> [T] {
  return fns.map { fn in fn(x) }
}
```

我们也可以反过来，把结果类型写成具体类型：

```swift
func apply2<T>(_ x: T, _ fns: [(T) -> String]) -> [String] {
  return fns.map { fn in fn(x) }
}
```

假设我们用一个装了大量闭包的数组来调用这两个函数：

```swift
let fns: [(String) -> String] = [
  { $0.uppercased() },
  /* and more... */
]
apply1("hello ", "world", fns)
apply2("hello ", "world", fns)
```

我们不希望在把数组传给 `apply1()` 和 `apply2()` 之前，逐个 re-abstract 数组里的每个闭包。取而代之的做法是：在把闭包存进一个 generic container 时，就把它 re-abstract 成最一般的形态，即 parameter 和 result 都是间接传的。具体是通过在存入数组前用一个 substituted-to-original thunk 包住每个闭包，而在从数组里取出时再用一个 original-to-substituted thunk 包一层来实现的。

> 译注：原书这两行调用给两参数的 `apply1` / `apply2` 传了三个实参（多出一个 `"world"`），疑为笔误；此处照译原文，语义以「用闭包数组 `fns` 调用这两个函数」为准。

这个实现模型有一个有意思的局限：re-abstraction thunk 会层层嵌套，导致内存占用可能没有上界。一位 Swift 开发者在论坛上报告过这个问题（Aleksandr 2024，《Value wrapped in a thunk recursively(?)》）。

**例.** 假设我们拿一个闭包数组，反复地把每个元素从数组里读出来，再原封不动地写回去：

```swift
var fns: [(String) -> String] = []

// Initialize the array
for n in 0 ..< 100 {
  array.append({ $0.lowercased() })
}

// Repeat this as many times as necessary
for _ in 0 ..< 1000 {
  for n in 0 ..< array.count {
    let fn = array[n]
    array[n] = fn
  }
}
```

每个读出来的元素都会被包上一个 original-to-substituted thunk，而这个 thunk 在写回数组同一位置之前又会被包上一个 substituted-to-original thunk。于是每一轮迭代都会在堆上分配一对 closure context，反复下去就会消耗任意多的内存。

> 译注：原书这段示例里变量声明的是 `fns`，循环体里用的却是 `array`，两处名字对不上，疑为笔误；此处照译原文，语义以「同一个闭包数组」为准。

对上面这种简单例子，我们可以检测出这种情形，要么在 SILGen 里就不发射冗余的 thunk，要么用一个 SIL optimizer pass 清理掉冗余 thunk。不过编译期的修复并不能彻底解决问题，因为我们只要把第二个「`for`」循环改成下面这样：

```swift
for _ in 0 ..< 1000 {
  for n in 0 ..< array.count {
    let fn = array[n]
    let fn2 = someFunction(fn)
    array[n] = fn2
  }
}
```

也许 `someFunction()` 只是原样返回它的实参，但如果它定义在另一个 module 里，编译器无从知晓这一点，因为它没法分析那个函数体，于是同样的问题又出现了。要彻底解决这个问题，就需要在构造 re-abstraction thunk 时做某种运行时检查，把多层嵌套的 thunk「塌缩」成一层。

最后一个例子说明，re-abstraction thunk 有时还需要把出现在 formal function type 的参数与结果里的 tuple type 炸开和合拢。

**例.** 考虑一个 formal type 为 `(String, (Int, Bool)) -> ()` 的闭包。以它自己的 formal type 作为 abstraction pattern，我们得到一个有三个参数、零个 result 的 SIL function type：

```
(@guaranteed String, Int, Bool) -> ()
```

然而，这个 function type 最一般的 lowered type 是下面这个：

```
(@in_guaranteed String, @in (Int, Bool)) -> (@out ())
```

后一个 lowered type 把那个两元素 tuple 当作单个间接参数来接收。它还间接返回一个空 tuple（空 tuple 值在内存里不占空间，所以其实没有什么可 load 或 store 的；不过 calling convention 仍然分配一个参数来充当间接结果缓冲区）。现在，如果要求我们发射一个 substituted-to-original thunk 来把第一个类型转换成第二个，那么这个 thunk 就必须炸开 tuple，从内存里 load 出两个元素，再把它们直接传给被包裹的闭包。反过来，original-to-substituted thunk 则必须把最后两个 lowered parameter 合拢成单个 tuple 值，以便间接传递。

### Optional payloads

大多数 generic nominal type 用的是一种不依赖 abstraction pattern 的统一表示，type lowering 收到这样的 formal type 时，直接把原 formal type 原样返回，忽略 abstraction pattern。特别地，generic nominal type 的 generic argument 本身并不会被 lower。

Optional type 是例外。（回忆前面 lowering optional 那个例子里 `Optional` 的声明。）Optional function type 特别常见，我们不希望每次把一个 function type 用 optional 包起来、或者把一个 optional function type 解包时，都付出分配一个 re-abstraction thunk 的代价。

因此，SIL type lowering 把 optional type 作为特例处理。当我们以一个 optional type 为 abstraction pattern 去 lower 一个 formal optional type 时，我们用 abstraction pattern 的 formal type 去 lower 它的 payload type，再用结果构造出一个 **lowered optional type**。

例如，考虑 formal type `Optional<(String) -> String>`。以它自己为 abstraction pattern 把它 lower 掉，会得到下面这个——注意 generic argument 变成了一个 SIL function type，而这个 SIL function type 是直接接收参数、直接返回结果的：

```
Optional<@convention(thick) (@guaranteed String) -> (@owned String)>
```

由于同一个 formal optional type 会随 abstraction pattern 的不同而映到若干个不同的 lowered optional type，optional type 的值有时也需要被 re-abstract。我们靠生成一个条件分支来做这件事：若当前选中的是「`none`」，就直接把这个空值返回；若当前选中的是「`some`」，就把 payload 包进一个 re-abstraction thunk，再把这个 thunk 包进一个新的 optional 值。

最后，我们可以来看 type lowering 算法了。

**算法（Lower type with abstraction pattern）.** 输入一个 formal type `X` 和一个 abstraction pattern `Y`；当 `Y` 含有 type parameter 时，还要附带一个可选的 generic signature `G`。返回一个 lowered type。Abstraction pattern 的结构必须与 formal type 匹配。

1. 若 `X` 是一个 **function type**：
   1. 并行遍历 `X` 与 `Y` 的 formal parameter：
      1. 以 `Y` 的对应 formal parameter type 为 abstraction pattern，lower 每个 formal parameter type。
      2. 对 `Y` 中任何是 tuple type 的 formal parameter，把 lower 后的类型炸开成多个 lowered parameter。
      3. 用上面的 Decide if type is address-only 算法为每个 lowered parameter type 算出它属于哪一类。
   2. 考虑 `X` 与 `Y` 的 formal result type：
      1. 以 `Y` 的 result type 为 abstraction pattern，lower `X` 的 formal result type。
      2. 若 `Y` 的 formal result type 是 tuple type，把 lower 后的 result type 炸开成多个 lowered result。
      3. 用 Decide if type is address-only 算法为每个 lowered result type 算出它属于哪一类。
   3. 把这些 lowered parameter type、lowered result type 及它们所属的类收集起来，构造出一个新的 SIL function type。
2. 若 `X` 是一个 **tuple type**，并行遍历 `X` 与 `Y` 的元素，lower 每个元素。把 lower 后的元素类型收集起来构造出一个 lowered tuple type，返回结果。
3. 若 `X` 是一个 **optional type**：
   1. 以 `Y` 的 payload type 为 abstraction pattern，lower `X` 的 payload type。
   2. 用这个 lower 后的 payload type 构造一个新的 optional type。
4. 若 `X` 是一个 **struct type**、**enum type**（`Optional` 除外，它在上面已处理）或 **class type**，返回 `X` 本身。（这种情况下 formal type 已经是 lowered type 了，我们忽略 abstraction pattern `Y`。）

### Substitution with lowered types

现在我们来考察「把一张 substitution map 应用到一个 lowered type 上」是什么意思。这是 SIL optimizer 里的常见操作；例如，它被用来生成 generic function 的 specialization。如果在调用点能看见函数的实现，优化器就可以克隆函数体里的每条 SIL 指令、并代入调用点的 substitution map，从而生成一份 specialization。

一张 substitution map 的 replacement type 永远是 formal type。当我们替换一个出现在 lowered type 里的 type parameter 时，如果它出现在某些特定位置上，我们有时必须把 replacement type 也 lower 掉。我们**总是**以 opaque abstraction pattern 来 lower replacement type。而需要这么做的位置，恰恰是上面 Lower type with abstraction pattern 算法会去 lower 一个出现在该处的 formal type 的那些位置。类型中的这种位置称为 **lowered position**。Lowered position 是递归定义的。整个原始 lowered type 本身就处于 lowered position。此外：

1. SIL function type 只能出现在 lowered position，并且它的所有 parameter 与 result 类型也都处于 lowered position。
2. 若一个 tuple type 出现在 lowered position，它的元素类型也处于 lowered position。
3. 若一个 optional type 出现在 lowered position，它的 generic argument 也处于 lowered position。

如果一个 type parameter 出现在任何其他位置上，它的 replacement type 不会被 lower，而是原样代入。

设 `Y` 是一个 abstraction pattern、`X` 是一个 formal type，并记 `L(Y, X)` 为 `X` 相对于 `Y` 的 lowered type。再让「`=`」表示 canonical type equality。在前面 abstraction pattern 那个例子里我们看到：以类型自身的 abstraction pattern 来 lower 它，一般来说与 type substitution 并不相容，即 `L(X, X) ⊗ Σ ≠ L(X ⊗ Σ, X ⊗ Σ)`。不过，确实存在一条把 type lowering 与 type substitution 联系起来的恒等式：当 abstraction pattern `Y` 保持未 substituted、而我们对等式两边都应用同一张 substitution map 时，下式永远成立：

```
L(Y, X) ⊗ Σ = L(Y, X ⊗ Σ)
```

**例.** 我们把 `{τ_0_0 ↦ Int, τ_0_1 ↦ [() -> String]}` 应用到一对 lowered type 上。先看 generic nominal type `Array<(τ_0_0, τ_0_1)>`。这两个 type parameter 都不在 lowered position 上，所以 type substitution 会不加 lower 地把它们替换掉，于是我们就得到 `Array<(Int, () -> String)>`。

现在假设我们把 `Σ` 应用到 `Optional<(τ_0_0, τ_0_1)>` 上。这两个 type parameter 都在 lowered position 上，所以 type substitution 会以 opaque abstraction pattern 去 lower 它们的 replacement type。可以看到 `Int` 保持不变，而 formal function type `() -> String` 变成了一个 SIL function type，我们得到：

```
Optional<(Int, @convention(thick) () -> (@out String))>
```

> 译注：原书这张 substitution map 里 `τ_0_1` 的 replacement type 写作 `[() -> String]`，方括号是原书用来把一个 function type 整体括起来以免歧义的排版手段，并不是 `Array` 的字面语法；译文保留方括号形态，含义是「`τ_0_1` 替换为 function type `() -> String`」。

### History

Swift 3.1 引入了针对 optional payload 的特殊 type lowering 支持与 re-abstraction；在此之前，optional type 与其他所有 generic nominal type 一样被 lower（John McCall 2016，《Abstract the object type of optional types》）。Function type 的**最一般形态**在 Swift 5 发生了变化，当时 `-swift-version 3` 模式被移除（如今 `-swift-version` 标志改名为 `-language-mode`，写作本书时支持的最低语言模式是 `4`）。正如我们在 `types.tex` 的 More Types 一节所见，Swift 3 并不区分「接收多个参数的 function type」与「接收单个 tuple type 参数的 function type」。因此在 Swift 3 里，function type 的最一般形态不得不把所有参数合拢成单个 tuple type 的间接参数，这有些低效。解决这个问题是放弃 Swift 3 源码兼容性的一大动因（Slava Pestov 2018，《SIL: Stop imploding parameter list into a single value with opaque abstraction pattern》）。最后，Swift 5.6 引入了那个 peephole 优化，使 SILGen 可以以任意 abstraction pattern 发射 closure expression，而不必立刻把它包进 substituted-to-original thunk（Joe Groff 2021，《SILGen: Emit literal closures at the abstraction level of their context. [take 3]》）。

## Source Code Reference

关键源文件：

- `include/swift/AST/SubstitutionMap.h`
- `include/swift/AST/Type.h`
- `include/swift/AST/Types.h`
- `lib/AST/SubstitutionMap.cpp`
- `lib/AST/TypeSubstitution.cpp`

**`Type`（class）**：另见 `types.tex` 的 Source Code Reference 一节。

- `subst()` 把一张 substitution map 应用到本 type 上，返回 substituted type。

**`TypeBase`（class）**：

- `getContextSubstitutionMap()` 返回本 type 的 context substitution map。

**`GenericSignature`（class）**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `getIdentitySubstitutionMap()` 返回本 generic signature 的 identity substitution map，即把每个 generic parameter 替换成它自己的那张。

**`SubstitutionMap`（class）**：一张 substitution map。与 `Type` 和 `GenericSignature` 一样，substitution map 是不可变且做了 unique 化的，而且一个 `SubstitutionMap` 的表示恰好塞进单个指针，所以按值传递的开销很低。

默认构造函数 `SubstitutionMap()` 构造出 empty substitution map。隐式的 `bool` 转换检测的是「非空 substitution map」。构造非空 substitution map 的那些入口点留到 `conformances.tex` 的 Source Code Reference 一节再讨论，因为那还牵涉到传入一个 conformance 数组，而我们还没介绍 conformance。

访问器方法：

- `empty()` 回答这是不是 empty substitution map；它是上述 `bool` 隐式转换的逻辑取反。
- `getGenericSignature()` 返回这张 substitution map 的 input generic signature。
- `getReplacementTypes()` 返回一个 `Type` 数组。
- `hasAnySubstitutableParams()` 回答这张 substitution map 的 input generic signature 里是否至少有一个没有被固定到具体类型上的 generic parameter（参见 `generic-signatures.tex` 的 Source Code Reference 一节里的 `GenericSignatureImpl::areAllParamsConcrete()` 方法）。

Replacement type 的递归性质：

- `hasPrimaryArchetypes()` 回答是否有任何 replacement type 含有 primary archetype。
- `hasOpenedExistential()` 回答是否有任何 replacement type 含有 existential archetype。
- `hasDynamicSelf()` 回答是否有任何 replacement type 含有 dynamic `Self` type。

如果一张 substitution map 的所有 replacement type 都是 canonical type、且所有 conformance 都是 canonical conformance，我们就说它是 **canonical** 的。把一张 substitution map 做 canonical 化，就是用原 substitution map 那些 canonical 化后的 replacement type 与 conformance 构造出一张新的 substitution map。

- `isCanonical()` 回答本 substitution map 所存的 replacement type 与 conformance 是否都是 canonical 的。
- `getCanonical()` 通过 canonical 化本 substitution map 的 replacement type 与 conformance 构造出一张新的 substitution map。

Substitution map composition（见上文 Composition 一节）：

- `subst()` 返回「本 substitution map 在左、给定 substitution map 在右」的 composition。

和 type 一样，substitution map 也有两级**相等性**：两张 substitution map 若其 replacement type 与 conformance 都是相等的指针，则它们本身是相等的指针。两张 substitution map 若其 canonical substitution map 是相等的指针，则它们 canonically equal；等价地说，若其 replacement type 与 conformance 都 canonically equal。`operator==` 的重载实现的是指针相等。Canonical 相等可以通过先把两边都 canonical 化来检测：

```cpp
if (subMap1.getCanonical() == subMap2.getCanonical())
  ...;
```

不过与 type 不同，检查两张 substitution map 是否相等是很少见的操作。它们被唯一化分配这件事，与其说是为了相等性比较，不如说更多是一种性能优化。

### Subclassing

**`ClassDecl`（class）**：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getSuperclass()` 返回本 class declaration 的 superclass type。

**`Type`（class）**：

- `getSuperclass()` 返回本 class type 的 superclass type。这就是上文的 Get superclass type 算法。
- `getSuperclassDecl()` 返回本 class type 的 superclass declaration。这就是上文的 Get superclass type for declaration 算法。

### SIL Types

关键源文件：

- `include/swift/AST/Types.h`
- `include/swift/SIL/SILType.h`
- `lib/SIL/IR/SILType.cpp`
- `lib/SIL/IR/SILFunctionType.cpp`

一个 lowered type 与一个 formal type 一样，都表示成 `CanType`。请注意：两者的区别**不是**静态强制的，必须小心不要把它们搞混。

**`TypeBase`（class）**：另见 `types.tex` 的 Source Code Reference 一节。有两个方法用来区分 formal type 与 lowered type：

- `isLegalFormalType()` 检查这是不是一个合法的 formal type。
- `isLegalSILType()` 检查这是不是一个合法的 lowered type。

**`SILValueCategory`（enum class）**：在实现里，一个类型是 loadable 还是 address-only 被称为该 lowered type 的「category」。

- `SILValueCategory::Object` 是 loadable 类型的 category。
- `SILValueCategory::Address` 是 address-only 类型的 category。

**`SILType`（class）**：把一个 lowered type 与它的 category 组合在一起。SIL type 可以被拆开：

- `getASTType()` 以 `CanType` 形式返回该 SIL type 的 lowered type。
- `getCategory()` 返回该 SIL type 的 category。

也可以由一个 lowered type 和一个 category 构造新的 SIL type：

- `SILType::getPrimitiveObjectType()` 是静态工厂方法，为给定的 lowered type 返回一个新的 object SIL type。该 lowered type 必须是 loadable 的。
- `SILType::getPrimitiveAddressType()` 是静态工厂方法，为给定的 lowered type 返回一个新的 address SIL type。

也可以直接用一个 lowered type 和一个 `SILValueCategory` 调用 `SILType` 的构造函数。

注意上述做法都要求手头已经有一个 lowered type；试图用一个并非 lowered type 的 formal type 去构造 SIL type，会触发运行时断言。要从 formal type 构造 SIL type，必须先把 formal type lower 掉，做法见下文。

SIL type 支持向下转型到表示各种 lowered type 的那些 `TypeBase` 子类。`SILType` 类声明了三个模板方法 `is<>()`、`getAs<>` 和 `castTo<>`。它们等价于先调用 `getASTType()`，再把结果传给 `types.tex` 的 Source Code Reference 一节讨论过的顶层模板函数 `isa<>`、`dyn_cast<>` 和 `cast<>`。

一个 SIL type 的打印形式：loadable 类型是 `$type`，address-only 类型是 `$*type`，其中 `type` 是其 lowered type 的打印形式。这种打印形式会出现在比如 `-emit-silgen` 的输出里。

**`SILFunctionType`（class）**：表示 SIL function type 的一个 `TypeBase` 子类。

- `getParameters()` 返回一个装着该函数 lowered parameter 的 `ArrayRef<SILParameterInfo>`。
- `getResults()` 返回一个装着该函数 lowered result 的 `ArrayRef<SILResultInfo>`。
- `getInvocationGenericSignature()` 返回该函数的 generic signature。

实际上，generic 的 SIL function type 的表示比我们这里描述的更复杂；见 Joe Groff 2019 年的论坛帖《Improving the representation of polymorphic interfaces in SIL with "substituted function types"》。

### SIL Type Lowering

关键源文件：

- `include/swift/SIL/AbstractionPattern.h`
- `include/swift/SIL/TypeLowering.h`
- `lib/SIL/IR/AbstractionPattern.cpp`
- `lib/SIL/IR/TypeLowering.cpp`

**`AbstractionPattern`（class）**：一个 abstraction pattern。

- `getKind()` 返回该 abstraction pattern 的 kind。可选的 kind 有哪些，见源码里的说明。
- `isTypeParameterOrOpaqueArchetype()` 返回这是不是一个 opaque abstraction pattern。
- `getType()` 返回该 abstraction pattern 的 formal type。

**`TypeConverter`（class）**：负责 SIL type lowering 的单例对象。

- `getLoweredType()` 接收一个表示 formal type 的 `CanType`，返回一个把 lowered type 与其 category 编码在一起的 `SILType`。
- `getTypeLowering()` 接收一个表示 formal type 的 `CanType`，返回一个 `TypeLowering` 对象，它除了 lowered type 之外还编码了 type lowering 算出的若干附加递归性质，例如该类型是否 trivial。

### Re-abstraction Thunks

关键源文件：

- `lib/SILGen/SILGenPoly.cpp`
- `lib/SILGen/SILGenThunk.cpp`

**`SILGenFunction`（class）**：这个类包含 SILGen 用来发射 SIL 函数的各种入口点。下面两个入口点发射 re-abstraction thunk：

- `emitOrigToSubstValue()` 把一个值从给定的 abstraction pattern re-abstract 成其 formal type 的「自然」abstraction pattern。若该值是 function type，这会发射一个 original-to-substituted thunk。
- `emitSubstToOrigValue()` 把一个值从其 formal type 的「自然」abstraction pattern re-abstract 成给定的 abstraction pattern。若该值是 function type，这会发射一个 substituted-to-original thunk。

### SIL Type Substitution

关键源文件：

- `lib/SIL/IR/SILTypeSubstitution.cpp`

**`SILType`（class）**：SIL type substitution。

- `subst()` 把一张 substitution map 应用到一个 SIL type 上。

**`SILTypeSubstituter`（class）**：用来实现上述操作的一个 `CanTypeVisitor` 实现。

---

> 译自 `docs/Generics/chapters/substitution-maps.tex`（swift-6.4.0-RELEASE，`cab5c62e`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
