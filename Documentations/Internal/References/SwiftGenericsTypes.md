# Types（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/types.tex`（《Compiling Swift Generics》一书的「Types」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这一章讲编译器内部怎么把「类型」表示成一棵树——有哪些 type kind、每种 kind 的 structural component 是什么、sugar 与 canonical type 的区别、三层类型相等性。本库从二进制里 demangle 出来的 `Node` 树，正是这套类型树被 mangler 序列化之后的形态，`Node.Kind` 与本章列举的 `TypeKind` 基本一一对应；本库的打印器、静态布局引擎、`MetadataReader` 都是在「反方向」重走这一章的构造与拆解操作。对应关系以「译注」标出，译文正文不夹带本库实现细节。
>
> **术语**：书中定义的术语一律保留英文（type representation、type kind、structural component、nominal type、generic parameter type、dependent member type、type parameter、interface type、archetype、contextual type、constraint type、sugared type、canonical type、reduced type、metatype、existential type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Reduced Type Parameters 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的小节按原书的英文标题引用。
>
> **图表处理**：原书本章有 17 个 TikZ 图环境、合并双栏后共 14 张图（多数是版面两侧的小图），这里一律降级为 ASCII 树图，每张图后附一行降级译注。图的原貌见官方 PDF 的 Types 一章。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter 的 canonical 写法。原书里 `Dictionary` 的 `Key` 对应 `τ_0_0`，`Value` 对应 `τ_0_1` |
> | `T.[P]A` | **bound** dependent member type：base type 是 `T`，成员是 protocol `P` 里声明的 associated type `A` |
> | `T.A` | **unbound** dependent member type：base type 是 `T`，成员只是一个标识符 `A`，还没绑到具体的 associated type declaration 上 |
> | `⟦T⟧` | type parameter `T` 在上下文给定的某个 generic environment 里的 **archetype** |
> | `⇒` | 蕴含。`(1) ⇒ (2)` 表示第一层相等性成立则第二层也成立 |

---

对类型的推理，是静态类型语言实现中的核心问题。在 Swift 里，`Int`、`Array<String>`、`(Bool) -> ()` 这些不同的语法形式都表示对类型的引用。**type representation** 是源码里写下的类型标注的语法形态，由 parser 构造出来。**type** 则是更高层的语义对象。类型由 type representation 经 **type resolution** 构造而来，也可以直接搭建和拆解。

假设文本 `Array<Int>` 出现在语言文法允许的位置上。首先，lexer 把输入文本切成 `Array`、`<`、`Int`、`>` 这几个 token。接着 parser 逐个检查 token，建出一个 type representation。

解析出来的 type representation `Array<Int>` 是一棵树，它把标识符 `Array` 和 type representation `Int` 组合在一起。后者是个叶子节点，只存了一个标识符。作为语法对象，type representation 只存标识符，这些标识符和真正的 type declaration 没有任何关系。树节点的「形状」由该 type representation 的 **kind** 决定，每种 kind 对应文法里的一条产生式。

```
一个 type representation：

  Array<Int> ────→ "Array"  ┐
      │                     │
      ↓                     ├─ 只是标识符
     Int     ────→ "Int"    ┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

要解析这个 type representation，我们先用 name lookup 找到 `Array` 和 `Int` 的 type declaration，再由它们构造出 generic nominal type `Array<Int>`。

Generic nominal type `Array<Int>` 指向 `Array` 的 type declaration，并且带一个子节点存放它的 generic argument，也就是类型 `Int`。后面这个类型同样指向 `Int` 的声明，而不只是一个标识符。

```
一个 type：

  Array<Int> ────→ struct Array  ┐
      │                          │
      ↓                          ├─ 真正的 type declaration
     Int     ────→ struct Int    ┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

类型和 type representation 一样按 **kind** 分类。每种 kind 都有一个构造操作，从 **structural component** 造出新类型，也有相应的操作把已有类型拆开。

### Categorization by kind

Type representation kind 来自文法里的各种产生式，比如标识符、函数 type representation `(Int) -> ()`、元组 type representation `(Bool, String)` 等等。后两种分别解析成 function type 和 tuple type，但总体上 type kind 比 type representation kind 更细，看标识符 type representation 就能体会到这一点：一个标识符 type representation `Element` 可以解析成好几种不同 kind 的类型，下面看其中几种。

一种可能是这个标识符指向一个 nominal type declaration。这时解析出来的类型是一个 **nominal type**，指向该声明。

```
Element         ──→  struct Element
(nominal type)       (nominal declaration)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

```
struct Element {...}
var x: Element
```

接下来 type checker 就可以做进一步的 qualified lookup 去找 `x` 的成员、查询这个 struct 的 stored property 以确定它的布局，等等。

另一种可能是这个标识符指向外层作用域里的某个 generic parameter，这时解析出来的类型是一个 **generic parameter type**。

```
Element
(generic parameter type，depth 0，index 0)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

```swift
struct Container<Element> {
  var x: Element
}
```

Generic parameter 声明在挂到某个声明上的 generic parameter list 里，作用域是该声明的 body，并且可以由一对整数——**depth** 与 **index**——唯一确定。Generic parameter type 也能存一个名字，但这个名字只在打印到 diagnostic 里时才有意义。

还有一种可能是这个标识符指向一个 type alias declaration。这时返回的是一个特殊的 **type alias type**，它包住 **underlying type** `Int`。它在各方面的行为都和 `Int` 一样，唯一的区别是打印回去时是 `Element`。

```
Element              Int
(type alias type) ──→ (nominal type)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

```swift
typealias Element = Int
var x: Element
```

除了 type resolution 之外，type representation 在编译器里的戏份不多，所以我们把它推迟到 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 再谈，眼下只关注 type。就目前而言，只需要知道 type resolution 不过是构造类型的诸多机制之一：expression checker 通过求解一个 constraint system 来构造类型，而泛型系统通过 substitution 构造类型，这是另外两个例子。

### Structural components

一个类型由若干 structural component 构造出来，它们可能是别的类型，也可能是非类型信息。常见的例子有：nominal type，由一个指向声明的指针加一串 generic argument type 组成；tuple type，有元素类型和标签；function type，含参数类型、返回类型，以及 `@escaping`、`inout` 这类额外的位。本章后半部分会把所有 type kind 及其 structural component 讲全。

类型一旦创建就不可变。说一个类型**包含**另一个类型，意思是后者作为 structural component 出现在前者里，可能嵌套好几层。我们还会经常说**替换**某个类型里包含的一个类型，这该理解成：构造一个与原类型同 kind 的新类型，除被替换的那个之外保留全部 structural component。原类型永远不会被直接改写。

更一般地，可以这样变换一个类型：按 kind 把它拆开，递归地变换每个 structural component，再由新的 component 组出一个同 kind 的新类型。先预告一下 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）：若 `Element` 是一个 generic parameter type，那么把 `Array<Element>` 里的 `Element` 换成 `Int` 就得到 `Array<Int>`，这叫 **type substitution**。编译器提供了各种工具来简化「按 type kind 做递归遍历与变换」的实现，type substitution 就是这类变换的一个例子。

> 译注：本库拿到的是这棵类型树被 mangler 序列化之后再 demangle 回来的形态——一棵 `Node` 树。结构完全同构：`Node.Kind` 对应本章的 type kind，子节点对应 structural component，「不可变、整棵替换」这条纪律在本库里同样成立（`NodeReference` 走 intern 后共享，任何改写都是重建）。索引与共享机制见 [MachOSymbols.md](../Modules/MachOSymbols.md) 与 [SharedNodeStoreMigration.md](../SharedNodeStoreMigration.md)。

### Canonical types

两个类型可以拼写不同，语义上却等价：

- Swift 语言为一些常用类型定义了简写，比如 `Optional<T>` 写成 `T?`、`Array<T>` 写成 `[T]`、`Dictionary<K, V>` 写成 `[K: V]`。
- Type alias declaration 为某个已有的 underlying type 引入一个新名字，效果等同于把 underlying type 原样写在 type alias 的位置上。举例来说，标准库声明了 type alias `Void`，其 underlying type 是 `()`。
- 同一类性质的另一种「虚构」是保留 generic parameter 的名字。源码里写下的 generic parameter type 有名字，比如 `Element`，打印到 diagnostic 里时也该原样打回去，但在内部，它们在自己的 generic signature 里是由一对整数——depth 与 index——唯一确定的。详见 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 的 Generic Parameters 一节。

这些构造就是所谓的 **sugared type**。一个 sugared type 有一个按其 structural component 展开的、更原始的脱糖形式。编译器在 type resolution 阶段构造 type sugar，并在变换类型时尽可能保留它。在 diagnostic 里保留 sugar 尤其有用，复杂的 type alias 之类的场合更是如此。

**canonical type** 是递归地不含任何 sugared type 的类型。Type sugar 在绝大多数情况下没有语义效果。举例来说，为同一个函数定义两个只在 sugared type 上不同的 overload 是没有意义的。正因如此，许多类型上的操作会先算出 canonical type，好在分情况讨论时不必再考虑 sugared type。类型检查之后，SILGen、IRGen 这些编译器 pass 只处理 canonical type。Swift runtime 也只把 canonical type 具体化成 runtime type metadata。

编译器可以通过 **canonicalization** 把任意类型变成 canonical type，这个过程递归地把 sugared type 换成其脱糖形式；这样一来 `[(Int?, Void)]` 就变成了 `Array<(Optional<Int>, ())>`。这个操作非常便宜：每个类型都缓存了一个指向其 canonical type 的指针，按需计算（所以类型并不像前面说的那样完全不可变；但这种可变性从外部观察不到）。

> 译注：二进制里留下的只有 canonical 形态——mangler 处理的就是 canonical type，所以 `T?` 与 `Optional<T>` 在符号里没有区别，源码到底写了哪一种无法从二进制恢复。本库对此的做法是在打印侧**重新加糖**（上游 demangler 的 `.synthesizeSugarOnTypes` 选项，CLI 的 `--synthesize-sugar-on-types`），把 `Swift.Optional<T>` 打回 `T?`、`Swift.Array<T>` 打回 `[T]`：这是一次按规则的再糖化，不是对原始拼写的还原。同类「尖括号糖在二进制里脱成了 requirement、只能按规则倒推」的讨论见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md) §2.1。

有一个值得一提的场合，type checker 的行为**确实**依赖 type sugar：变量的默认初始化。如果一个变量的类型声明成了 sugared optional type `T?`（`T` 为某类型），那么在没有给出初值表达式时，它的初值表达式会被当作 `nil`。把类型写成 `Optional<T>` 就能避开这个默认初始化行为：

```swift
var x: Int?
print(x)  // 打印 `nil'

var y: Optional<Int>
print(y)  // error: use of uninitialized variable `y'
```

另一个例外是用 generic type alias 做 requirement inference（见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Requirement Inference 一节）。

### Type equality

类型是唯一分配的，这一点靠它们的不可变性得以成立。类型 `(Int) -> ()` 在一次编译中有唯一的指针标识；在 tuple type `((Int) -> (), (Int) -> ())` 内部，两个元素类型在内存里是同一个指针值。由此定义出类型上的三层相等性：

1. **Type pointer equality** 检查两个类型作为树是否完全相同。
2. **Canonical type equality** 检查两个类型在去掉 sugar 之后是否相同。
3. **Reduced type equality** 检查两个类型相对于某个 generic signature 是否有相同的 reduced type——这个说法后面会精确化。

每一层相等性都蕴含下一层，即 `(1) ⇒ (2)`、`(2) ⇒ (3)`。若两个类型都是 canonical 的，(1) 与 (2) 重合；若两个都是 reduced 的，(1)(2)(3) 三者重合。Type pointer equality 很少用到，恰恰是因为它太严了：我们通常不希望仅因 sugar 不同就把两个类型看作不同。

下面这张图（原书的「Some examples of type equality」）展示了如下 extension 声明里的类型相等性，其中 `Dictionary` 的 `Key`（`τ_0_0`）与 `Value`（`τ_0_1`）两个 generic parameter 被一条 same-type requirement 声明为等价：

```
sugared types            canonical types          reduced types

Key?              ┐
                  ├──→  Optional<τ_0_0>  ┐
Optional<Key>     ┘                      │
                                         ├──→  Optional<τ_0_0>
Value?            ┐                      │
                  ├──→  Optional<τ_0_1>  ┘
Optional<Value>   ┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

```swift
extension Dictionary where Key == Value {
  func foo(a: Key?, b: Optional<Key>, c: Value?, d: Optional<Value>) {}
}
```

来看 `Key?`、`Optional<Key>`、`Value?`、`Optional<Value>` 这四个类型：

- 在 type pointer equality 下，四个两两不同。
- 前两个的 canonical type 是 `Optional<τ_0_0>`。因此前两个在 canonical type equality 下相等。
- 后两个的 canonical type 是 `Optional<τ_0_1>`。同样地，它们彼此在 canonical type equality 下相等（但与前两个不同）。
- 一旦把这个 extension 的 generic signature 纳入考虑，就只剩一个 reduced type 了，因为两个 canonical type 都经由那条 same-type requirement 归约到 `Optional<τ_0_0>`。于是最初那四个类型在 reduced type equality 下全部相等。

Reduced type equality 的含义是「作为一条或多条 same-type requirement 的推论而等价」。我们会在 `generic-signatures.tex` 的 Valid Type Parameters 一节用 derived requirement 的形式化框架定义 type parameter 之间的这种等价关系，再在同章的 Generic Signature Queries 一节推广到所有 interface type。给出 reduced type equality 的判定过程是本书的主要成果之一，关键进展在 `monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 The Normal Form Algorithm 一节与 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)）。

## Fundamental Types

上面看了类型总体上的一些行为，也非正式地介绍了几种 kind。现在我们把所有 kind 讲全，从泛型实现视角下最重要的那些开始。

### Nominal types

**nominal type** 由非泛型的 struct、enum 或 class 声明所声明，比如 `Int`。**generic nominal type** 由泛型的 struct、enum 或 class 声明所声明。它们的 structural component 如下：

- 一个指向 nominal type declaration 的指针。
- 一个 **parent type**，当该 nominal type declaration 嵌套在另一个 nominal type declaration 里时才有。
- 一串 **generic argument**，当该 nominal type declaration 是泛型的时候才有。

Parent type 记录了外层 nominal type declaration 的 generic argument。例如，有了下面这些声明，我们就能构造出 nominal type `Outer<Float>.Inner`：

```
Outer<Float>.Inner
      │
      │ parent type
      ↓
  Outer<Float>
      │
      │ generic argument
      ↓
    Float
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

```swift
struct Outer<T> {
  struct Inner {}
}
```

一个 nominal type declaration 定义了一族 nominal type，它们共享同一个声明和同样的 parent type 结构，但 generic argument 不同。这一族里的每个类型都是该 nominal type declaration 的一个 **specialized type**。

把每个 generic argument 都取成对应的 generic parameter type，得到的那个 specialized type 就是该 nominal type declaration 的 **declared interface type**。它是「万能」的：任何 specialized type 都可以由 declared interface type 出发、给每个 generic parameter type 指派一个 replacement type 而得到。这样的指派叫做 **substitution map**，而由某个 specialized type 的 generic argument 定义出来的那张 substitution map，就是它的 **context substitution map**（见 `substitution-maps.tex` 的 Nominal Types 一节）。最后，当该 nominal type declaration 及其所有 parent 都不是泛型时，这个声明只定义出一个 **fully-concrete** 的 specialized type，其 context substitution map 为空。

```
declared interface type：

Outer<τ_0_0>.Inner
      │
      │ parent type
      ↓
  Outer<τ_0_0>
      │
      │ generic argument
      ↓
    τ_0_0
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Generic parameter types

generic parameter type 抽象的是调用方提供的一个 generic argument。Generic parameter type 由 generic parameter declaration 声明，见 `declarations.tex` 的 Generic Parameters 一节。Sugared 形态引用该声明，打印出来是声明的名字；canonical 形态只存一个 depth 和一个 index。要注意别把 canonical 的 generic parameter type 打印到 diagnostic 里，免得把 `τ_1_2` 这种记法摆到用户面前。（把 canonical generic parameter type 变回 sugared 形态的做法，见 `generic-signatures.tex` 的 Source Code Reference 一节末尾。）

### Dependent member types

dependent member type 抽象的是某个满足 associated type requirement 的具体类型。它有两个 structural component：

- 一个 base type，它是一个 generic parameter type 或另一个 dependent member type。
- 一个标识符（这时它是 **unbound** dependent member type），或者一个 associated type declaration（这时它是 **bound**）。

`type-resolution.tex` 里会讲 type resolution 的两个阶段。Unbound dependent member type 出现在 **structural resolution stage**：那时我们正在解析 `where` 子句里的 requirement，好喂给 generic signature 的构造过程。一旦拿到 generic signature，我们就进入 **interface resolution stage**，其他地方写下的 dependent member type 会被完整解析成 bound 形态。

若 `T` 是 base type、`P` 是一个 protocol、`A` 是这个 protocol 里声明的一个 associated type，我们把 bound dependent member type 记作 `T.[P]A`，unbound 的记作 `T.A`。Base type `T` 可以是另一个 dependent member type，于是得到 `τ_0_0.[P]A.[Q]B` 这样的递归结构。下图（原书的「Bound and unbound dependent member types」）用 bound 与 unbound 两个 dependent member type 展示这一点：

```
bound                                 unbound

τ_0_0.[P]A.[Q]B ──→ associatedtype B  τ_0_0.A.B ──→ "B"    ┐
      │                          ┐          │             │
      │ base type                │          │ base type   ├─ 只是标识符
      ↓                          ├─ 真正的  ↓             │
  τ_0_0.[P]A  ──→ associatedtype A│  声明  τ_0_0.A ──→ "A" ┘
      │                          ┘          │
      │ base type                           │ base type
      ↓                                     ↓
    τ_0_0                                 τ_0_0
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

**type parameter** 是一个 generic parameter type 或 dependent member type（后者的 base 又是一个 type parameter）。**interface type** 是可能含有 type parameter、但本身不一定就是 type parameter 的类型。本书有相当篇幅在讲清 type parameter，关键议题包括：

- Type parameter 的语义合法性（见 `generic-signatures.tex` 的 Derived Requirements 与 Valid Type Parameters 两节）。
- Generic signature query（见 `generic-signatures.tex` 的 Generic Signature Queries 一节）。
- Dependent member type 的 substitution（见 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Abstract Conformances 一节与 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)））。
- 带 bound 与 unbound type parameter 的 type resolution（见 `type-resolution.tex`）。

最后说一句术语上的事。这里「dependent」的用法来自 C++，指的**不是**「lambda cube」意义下那种依赖于值的 dependent type。

> 译注：本库读到的 `dependentMemberType` 节点几乎都是 bound 形态（mangling 里带 protocol 限定），`SwiftLayout` 的 `DependentMemberTypeBridge` 就是按这个结构去 `__swift5_assocty` 里查 conformance 的 associated type witness，再把 base 自己的 generic argument 代回去，从而把 `C.Index` 这类字段算出真实布局。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Archetype types

Type parameter 的含义来自某个 generic signature 的 requirement；某种意义上它们只是外部实体的「名字」。**archetype** 则是一种「自描述」的替代表示。Archetype 由 **generic environment** 实例化出来，后者存着一个 generic signature 以及其他信息（见 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)））。**contextual type** 是可能含有 archetype、但本身不一定就是 archetype 的类型。

Archetype 出现在表达式和 SIL 指令里。Archetype 还用来表示对 opaque result type 的引用（见 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)） 的 Opaque Archetypes 一节，中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）以及 existential 内部 payload 的类型（见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)） 的 Existential Archetypes 一节）。在 diagnostic 里，archetype 打印成它所代表的那个 type parameter。我们把 type parameter `T` 在上下文可知的某个 generic environment 里的 archetype 记作 `⟦T⟧`。

我们上面考察的这些基本 type kind——nominal type、type parameter 和 archetype——**正是能 conform to protocol 的那些 Swift 类型**。换句话说，它们能出现在 conformance requirement 的左边，各自的细节稍后在 `conformances.tex` 的 Conformance Lookup 一节给出。另一类重要的是 **constraint type**，它们**是出现在 conformance requirement 右边的那些类型**。Constraint type 本身永远不会是能产出值的表达式的类型。（不过值可以有 existential type，后者包着一个 constraint type，下面就会看到。）

> 译注：「哪些 type kind 能 conform」这条判据，在本库里落在离线布局引擎的取舍上：`ClassBoundGenericParameterAnalysis` 只从 requirement signature 里挖出「这个参数必是一个对象引用」「这个参数被钉成某个具体类型」这两类事实——它对应的正是 type parameter 作为 conformance 左边项时签名本身就确定的部分，不给实参也算得出。见 [SwiftLayout.md](../Modules/SwiftLayout.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Protocol types

protocol type 是最基本的一种 constraint type；任何其他 kind 的 constraint type 参与的 conformance requirement，总能拆成若干条更简单的 conformance requirement。Protocol type 是一种 nominal type，所以当 protocol declaration 嵌套在另一个 nominal type declaration 里时，它也会有 parent type。但与其他 nominal type 不同，protocol 不能嵌套在泛型上下文里（见 `substitution-maps.tex` 的 Nested Nominal Types 一节），所以 protocol type 本身及其任何 parent 都不会有 generic argument。因此，每个 protocol declaration 恰好对应一个 protocol type。

### Protocol composition types

protocol composition type 可以含任意多个 protocol type，外加至多一个 class type 或一条 `AnyObject` layout constraint：

```
P & Q
P & AnyObject
SomeClass<Int> & P
```

空的 protocol composition 写作 `Any`。如果 conformance requirement 的右边是一个 protocol composition type，我们会生成一串更简单的 requirement，composition 的每个成员一条（见 `building-generic-signatures.tex` 的 Decomposition and Desugaring 一节）。Swift 2.2 及更早用的语法是 `protocol<P, Q>`；Swift 3 引入了现代拼写（SE-0095）。所以如今 `Any` 是个特例，但它当年当然就是 `typealias Any = protocol<>`。

### Parameterized protocol types

parameterized protocol type 存着一个 protocol type 加一串 generic argument。作为 constraint type，它展开成一条 conformance requirement 外加一条或多条 same-type requirement，protocol 的每个 **primary associated type** 一条（见 `declarations.tex` 的 Protocols 一节）。它的书面形态看起来就像一个 generic nominal type，只不过被命名的声明是个 protocol，例如 `Sequence<Int>`。Parameterized protocol type 在 Swift 5.7 引入（SE-0346，该 evolution 提案里管它们叫「constrained protocol type」）。

## More Types

各种 **structural type** 同样可以由别的类型构造出来。（别和 **structural resolution stage** 产出的那些类型搞混，后者见 `type-resolution.tex`。）

### Existential types

existential type 有一个 structural component，即它的 **constraint type**。一个 existential value 是个容器，装着某个未知动态类型的值，只知道该类型满足这条约束；下面是 existential type `any (P & Q)` 的结构，它装的值同时 conform to `P` 和 `Q`：

```
any (P & Q)
(existential type)
      │
      │ constraint type
      ↓
    P & Q
(protocol composition type)
     ╱          ╲
 member        member
   ↓              ↓
   P              Q
(protocol type) (protocol type)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

`any` 关键字是 Swift 5.6 加的（SE-0335）；在此之前的 Swift 版本里，existential type 与 constraint type 在语言和实现中都是同一个概念。（为了源码兼容，不带 `any` 关键字的 constraint type 至今仍会解析成 existential type，除非它出现在 conformance requirement 的右边。）

Existential type 在 `existential-types.tex` 里详述。

### Metatype types

类型 `T` 可以作为 call expression `T(...)` 的被调用方，这是构造器调用 `T.init(...)` 的简写。它也能作为静态方法调用 `T.foo(...)` 的基，这时类型作为 `self` 参数传入。最后，它还能由表达式 `T.self` 直接引用。这几种情况里，类型都变成了一个**值**，而这个值本身必须有一个类型；这个类型就叫 **metatype**。类型 `T` 的 metatype 写作 `T.Type`，而 `T` 是这个 metatype 的 **instance type**。例如表达式 `Int.self` 的类型是 metatype `Int.Type`，其 instance type 是 `Int`。

```
Int.Type
(metatype type)
     │
     ↓
    Int
(nominal type)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

Metatype 有时也叫 **concrete metatype**，以区别于下面要介绍的 existential metatype。多数 concrete metatype 都是只有一个值的单例类型，那个值就是 instance type 自己。一个例外是：非 final class 的 class metatype，其值还包括该 class 的所有子类。

### Existential metatype types

existential metatype 是一个容器，装着某个未知的 concrete metatype，只知道后者的 instance type 满足那条 constraint type。

Existential metatype 和「instance type 是 existential 的 metatype」不是一回事，从语言语义上就能说明这一点。设 `P` 是一个 protocol、`S` 是一个 conform to `P` 的类型，那么 existential metatype `any P.Type` 可以装下值 `S.self`。而由于 existential type `any P` 并不 conform to `P`，值 `(any P).self` 就没法装进 existential metatype `any P.Type` 里。事实上，这个值的类型是 **concrete** metatype `(any P).Type`。下图（原书的「Existential metatype and metatype of existential」）对比了 `any P.Type` 与 `(any P).Type` 的递归结构：

```
any P.Type                      (any P).Type
(existential metatype type)     (metatype type)
      │                               │
      │ constraint type               │ instance type
      ↓                               ↓
      P                             any P
(protocol type)                 (existential type)
                                      │
                                      │ constraint type
                                      ↓
                                      P
                                (protocol type)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

> 译注：原书此处的图引用了上一张图的节点名（`(IntType) -- (Int)`），官方 PDF 里这条边会画错；此处按图的语义意图画作 `any P.Type → P`。

在 `any` 关键字引入之前，existential metatype 写作 `P.Type`，而 existential 的 concrete metatype 写作 `P.Protocol`。这曾是困惑的来源，因为当 `T` 不是 protocol 类型时，`T.Type` 在其他场合总是 concrete metatype。下表对比新旧语法：

| 旧语法 | 新语法 | Type kind |
|---|---|---|
| `(T).Type` | `(T).Type` | Concrete metatype（未变） |
| `P.Protocol` | `(any P).Type` | Existential 的 concrete metatype |
| `P.Type` | `any P.Type` | Existential metatype |

### Tuple types

tuple type 是一串元素类型加上可选的标签。如果元素类型的列表为空，就得到唯一的空 tuple type `()`。

```
(x: Int, y: Float)
(tuple type，labels: x:y:)
     ╱          ╲
    ↓            ↓
   Int         Float
(nominal type) (nominal type)
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

无标签的单元素 tuple type 根本构造不出来；`(T)` 解析成与 `T` 相同的类型。带标签的单元素 tuple type `(foo: T)` 在文法上是合法的，但会被 type resolution 拒掉。SILGen 在把一个 enum case 的 payload 具体化时（例如 `case person(name: String)`）会在内部造出这种类型，但它们不会作为表达式的类型出现。

### Function types

function type 是 call expression 中被调用方的类型。它含有一个参数列表、一个返回类型，以及若干非类型属性。这些属性包括函数的 effect、lifetime 和 calling convention。Effect 有 `throws` 和 `async`（后者来自 Swift 5.5 的并发模型，SE-0296）。Lifetime 为 non-escaping 的 function type 的值是二等公民：它们只能被传给另一个函数、被某个 non-escaping 闭包捕获，或者被调用。Escaping 的函数则一如既往还可以被返回，或者存进别的值里。四种 calling convention 是：

- 默认的 **thick** 约定，函数以一个函数指针加一份引用计数的 closure context 的形式传递。
- `@convention(thin)`：值是单个使用 Swift 调用约定的函数指针，**没有** closure context。Thin 函数不能有捕获。
- `@convention(c)`：值是单个函数指针，且参数类型与返回类型必须能在 C 里表示。同样不允许捕获。
- `@convention(block)`：值是一个 Objective-C block。允许捕获，但参数类型与返回类型必须能在 Objective-C 里表示。

参数列表里的每一项含有一个参数类型和若干非类型的位：

- **ownership specifier**，可能的取值对应默认所有权、`inout`、`borrowing` 或 `consuming`。

  `inout` 这一种是 Swift 可变值类型模型的关键；有兴趣的读者可参阅（Racordon 等，2022，《Mutable Value Semantics》）。另外两种是 Swift 5.9 引入的（SE-0377）。

- **variadic** 标志，这时参数类型必须是一个 array type。

  在对带 variadic 参数的函数值的调用做类型检查时，type checker 会把调用实参列表里的多个表达式收集进一个隐式的数组表达式。除此之外，一旦到了 SILGen 及更下层，variadic 参数的行为就和数组完全一样。

- `@autoclosure` 属性，这时参数类型必须是另一个形如 `() -> T` 的 function type（`T` 为某类型）。

  它指示 type checker 把调用方那边对应的实参当作类型 `T` 的值来处理，而不是当作 function type `() -> T`。这个实参随后会被包进一个隐式的闭包表达式里。在被调用方的函数体内，`@autoclosure` 参数的行为和普通的函数值完全一样，可以调用它来对调用方提供的表达式求值。

在 ML、Haskell 这类函数式语言里，所有 function type 在概念上都只取一个参数类型。Swift 不是这样。下图（原书的「Function type with two parameters, or a single tuple parameter」）展示了 `(Int, Float) -> Bool` 与 `((Int, Float)) -> Bool` 的区别：前者有两个参数，后者只有一个参数，其类型是 tuple type。

```
(Int, Float) -> Bool            ((Int, Float)) -> Bool
(function type，parameters: 2)  (function type，parameters: 1)
   ╱     │     ╲                     ╱              ╲
  ↓      ↓      ↓ result            ↓                ↓ result
 Int   Float   Bool           (Int, Float)          Bool
                              (tuple type)
                                ╱      ╲
                               ↓        ↓
                              Int     Float
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

为方便起见，type checker 定义了一种隐式转换，叫做 **tuple splat**，在「取单个 tuple 的 function type」与「取多个实参的 function type」之间转换。这种隐式转换只在把一个函数值作为实参传给某次调用时可用，并且只在该 function type 的参数列表能表示成一个 tuple 时可用（因此它不能带参数属性）。举个例子：

```swift
func apply<T, U>(fn: (T) -> U, arg: T) -> U {
  return fn(arg)
}

// Tuple splat conversion:
// - the type of (+) is (Int, Int) -> (),
// - but apply() expects ((Int, Int)) -> ().
print(apply(fn: (+), arg: (1, 2)))
```

Function type 的另一个微妙之处在于，argument label 是函数声明的**名字**的一部分，而不是函数声明的**类型**的一部分。闭包作为匿名函数，调用时永远不带 argument label。这也包括由对函数声明的未施用引用所构成的闭包——哪怕那个函数声明**确实**有 argument label：

```swift
func subtract(minuend x: Int, subtrahend y: Int) -> Int {
  return x - y
}

print(subtract(minuend: 3, subtrahend: 1))  // 打印 2

let fn1 = subtract  // declaration name can omit argument labels
print(fn1(3, 1))  // 打印 2

let fn2 = subtract(minuend:subtrahend:)  // full declaration name
print(fn2(3, 1))  // 打印 2
```

Swift function type 的演变史是语言演化的一个有趣案例。最初 Swift 遵循经典的函数式语言模型：function type 总是只有**一个**参数类型，而这个类型可以是 tuple type，以此模拟多参数函数。当年的 tuple type 还能包含 `inout` 元素和 variadic 元素，而且函数声明的 argument label 是该函数声明类型的一部分。这种「non-materializable」的 tuple type 的存在给整个类型系统引入了复杂性，argument label 在不同上下文里的行为也不一致。

带 argument label 引用声明名字的语法在 Swift 2.2 采纳（SE-0021）。随后，argument label 在 Swift 3 被从 function type 里拿掉（SE-0111）。「多参数函数」与「取单个 tuple 参数的函数」之间的区分，在 Swift 3 由 SE-0029 和 SE-0066 首次露头，到 Swift 4 才明确下来（SE-0110）。与此同时，Swift 4 还引入了「tuple splat」函数转换，好在旧行为确实方便的场合下模拟 Swift 3 的模型。举例来说，`Dictionary` 的元素类型是一个键值对，但调用 `Collection.map()` 时往往写一个取两个实参的闭包比写一个取单个 tuple 实参的闭包更顺手。

上述提案落地之后，编译器仍然在相当长一段时间里把 function type 建模成只有单个输入类型，尽管这一点对用户完全不可见。到 Swift 5 之后，function type 的表示才与语言的语义模型完全收敛。

请注意，虽然 metatype、tuple type 和 function type 在整个 Swift 语言里都扮演重要角色，但它们对泛型的形式化分析并不是必需的；只用 generic nominal type 和 type parameter 就能搭出一个玩具版的 Swift 泛型实现。事实上，从泛型模型的视角看，structural type 没有任何内在行为，充其量是可能包含一些能被代入的 type parameter。

本节最后转向 sugared type。Sugared 的 generic parameter type 在上文 Fundamental Types 一节已经讲过。剩下的几种 sugared type 里，type alias type 由用户定义，另外三种是语言内建的。

### Type alias types

type alias type 表示对一个 type alias declaration 的引用。它由一个可选的 parent type、一串 generic argument，以及代入后的 **underlying type** 组成。Type alias type 的 canonical type 就是那个代入后的 underlying type。仅当 type alias declaration 是另一个 type declaration 的成员时才有 parent type，仅当该 type alias 是泛型的时候才有 generic argument（见 `type-resolution.tex` 的 Identifier Type Representations 一节）。Parent type 与 generic argument 被 type resolution 保留下来，一是为了让 type alias type 能被忠实地打印出来，二是为了 requirement inference（见 `building-generic-signatures.tex` 的 Requirement Inference 一节）。

### Optional types

optional type 写作 `T?`（`T` 为某 **payload type**），其 canonical type 是 `Optional<T>`。

### Array types

array type 写作 `[E]`（`E` 为某元素类型），其 canonical type 是 `Array<E>`。

### Dictionary types

dictionary type 写作 `[K: V]`（`K` 为键类型、`V` 为值类型），其 canonical type 是 `Dictionary<K, V>`。

## Special Types

下面讨论剩下的几种类型，它们各有各的古怪。它们往往只在特定上下文里合法，有些甚至根本不表示任何值的类型。它们的意外出现常常成为反例和断言失败的来源。它们在 expression type checker 里都扮演重要角色，但同样地，纯从形式化的泛型模型视角看，它们并没有带来什么新东西。

### Generic function types

generic function type 的 structural component 与 function type 相同，只是额外存了一个 generic signature：

```
<S where S: Sequence> (S) -> S.Element
```

Generic function type 表示的是一个泛型 function 或 subscript 声明在施加 substitution 之前的 interface type。引用泛型 function 或 subscript 声明的表达式总是先施加 substitution，所以 Swift 语言里的**值**不可能有 generic function type。特别地，generic function type 不能作为另一个 function type 的参数或结果；Swift 的类型系统不支持 **higher-rank polymorphism**。带 higher-rank 类型的类型推断已知是不可判定的，见（Wells，1999，《Typability and type checking in System F are equivalent and undecidable》）与（Peyton Jones 等，2007，《Practical Type Inference for Arbitrary-Rank Types》）。

Generic function type 在计算 canonical type 时有一种特殊行为。由于 generic function type 携带一个 generic signature，一个 **canonical** generic function type 的参数类型与返回类型实际上是相对于这个 generic signature 的 **reduced** 类型（见 `generic-signatures.tex` 的 Reduced Type Parameters 一节）。

### Reference storage types

reference storage type 是带 `weak`、`unowned` 或 `unowned(unsafe)` 属性的变量声明的类型。这些修饰符改变了它们所作用的 class type、class-constrained archetype 或 class-constrained existential type 的引用计数行为。Reference storage type 作为变量声明的 interface type 出现，也作为 SIL 中值的类型出现。表达式的类型里永远不会含有 reference storage type。

> 译注：这三类 structural type 的**内存布局**，本库在离线侧算得出来。要点恰恰在于本节这句话：修饰符作用于「class type、class-constrained archetype 或 class-constrained existential type」——所以 `weak` 修饰的宽度由 referent 决定，`weak var x: (any P)?` 是 16 字节而不是一个字（witness table 字还在），普通类引用才是 8 字节。Existential 容器（opaque `32 + 8N`、class-bound `8·(1+N)`）与 metatype 的 thin / thick 判定同理。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Placeholder types

placeholder type 表示一个待 type checker 推断的 generic argument，书面形态是下划线 `_`。它们只能出现在少数几种受限的上下文里，且在类型检查之后不会出现在表达式的类型或声明的 interface type 中。Constraint solver 在求解 constraint system 时会把 placeholder type 换成 type variable。例如下面这里，局部变量 `myPets` 的 interface type 被推断为 `Array<String>`：

```swift
let myPets: Array<_> = ["Zelda", "Giblet"]
```

Placeholder type 是 Swift 5.6 引入的（SE-0315）。

### Unbound generic types

unbound generic type 比 placeholder type 出现得更早，可以看作后者的一个特例。Unbound generic type 写成对一个泛型 type declaration 的具名引用，不施加 generic argument。它的行为就像一个所有 generic argument 都是 placeholder type 的 generic nominal type。上一个例子里我们写的是带 placeholder type 的 generic nominal type `Array<_>`，换成 unbound generic type `Array` 也可以：

```swift
let myPets: Array = ["Zelda", "Giblet"]
```

Unbound generic type 在 diagnostic 里偶尔也有用：可以只打印一个 type declaration 的名字（比如 `Outer.Inner`），而不带上它 declared interface type 里的那些 generic parameter（比如 `Outer<T>.Inner<U>`）。Type resolution 处理 unbound generic type 的行为将在 `type-resolution.tex` 的 Unbound Generic Types 一节讨论。

### Dynamic Self types

当 class 里的某个方法声明返回类型为 `Self` 时，就出现 dynamic `Self` type。它保证返回值的**动态**类型必须与传给这次方法调用的 `self` 参数相同，而后者可能是 `self` 静态类型的某个子类。Dynamic `Self` type 有一个 structural component，即一个 class type。它在某些方面表现得像 existential type，但这只是 type checker 和 SILGen 里写死的行为。

注意，标识符 `Self` 只有在 class 内部才是这个含义。在 protocol 声明里，`Self` 是那个隐式的 generic parameter（见 `declarations.tex` 的 Protocols 一节）。在 struct 或 enum 声明里，`Self` 是其 declared interface type（见 `type-resolution.tex` 的 Identifier Type Representations 一节）。

下面这段代码（原书的「Dynamic `Self` type example」）演示了 dynamic `Self` type 的一些行为：

```swift
class Base {
  required init() {}
  
  func dynamicSelf() -> Self {
    // the type of `self' in a method returning `Self' is
    // the dynamic Self type.
    return self
  }

  func clone() -> Self {
    return Self()
  }
  
  func invalid1() -> Self {
    return Base()  // error
  }
  
  func invalid2(_: Self) {}  // error
}

class Derived: Base {}

let y = Derived().dynamicSelf()  // y has type `Derived'
let z = Derived().clone()  // z has type `Derived'
```

其中展示了两个非法情形：`invalid1()` 被拒是因为 type checker 无法证明返回类型总是 `self` 动态类型的一个实例；`invalid2()` 被拒是因为 `Self` 出现在逆变位置上。这个特性来自 Objective-C，在那里它叫 `instancetype`。

### Type variable types

type variable 表示某个表达式将来会被推断出的类型。**expression type checker** 递归遍历一个表达式来构建 **constraint system**：给每个子表达式分配新的 type variable，再记录下关联这些 type variable 的约束。然后 constraint solver 去搜索一个**解**，给每个 type variable 指派一个满足约束的具体类型。求解 constraint system 有三种可能的结果：

- **唯一解**——该表达式及其所有子表达式都是良类型的。
- **无解**——约束无法满足，该表达式非法。
- **多解**——该表达式有歧义，因为不止一种具体类型的指派能满足约束。

如果恰好有一个解，我们就用具体类型更新 AST 里的每个表达式。有多个解时，我们试着用启发式规则给这些解排序；如果其中一个明显「更好」，就按唯一解的情形继续。如果无解，或者有多个有歧义的解而没有哪个更好，我们就报错。

Type variable type 以及含有它们的结构不能活过 **constraint solver arena**，后者的生命周期限定在 expression type checker 对单个表达式的那一次调用内。**含有** type variable 的结构，例如其他类型和 substitution map，同样分配在 constraint solver arena 里。正因如此，type variable type 绝不能从 constraint solver arena 里「逃逸」出去。代码里用断言来排除 type variable type 的意外出现。

Type variable 打印出来是 `$Tn`，其中 `n` 是该 constraint system 内部递增的整数。想实地看看 type variable 和约束求解，一个办法是给编译器传 `-Xfrontend -debug-constraints` 标志。想进一步了解 expression type checker，见（Gregor、Yaskevich、Borla，《Type checker design and implementation》，`docs/TypeChecker.md`）与（Yaskevich，2019，《New diagnostic architecture overview》）。

### L-value types

l-value type 表示出现在赋值运算符左边（「l」即由此而来）、或作为函数调用中 `inout` 参数实参的表达式的类型。L-value type 包着一个 **object type**，即所存值的类型；它们打印成 `@lvalue T`，其中 `T` 是 object type，但这并不是语言里合法的语法。

L-value type 出现在类型检查过的表达式里。熟悉 C++ 的读者可以把 l-value type 类比成 C++ 的可变引用类型 `T &`——但和 C++ 不同，它们在源语言里并不直接可见。L-value type 不出现在 SIL 指令的类型里；SILGen 会把 l-value 访问下降成 accessor 调用或对内存的直接操作。

### Error types

error type 表示有错误的程序里的某个未知类型。Error type 有两种形态：要么包着另一个类型，要么是所谓的 singleton error type。某种意义上，error type 类似浮点运算里的「Not a Number」值。

Type substitution 在遇到非法 conformance 时返回 error type（见 `conformances.tex`）。这种情况下，error type 包着被代入的那个原类型，于是打印出来就是原类型，好让来自畸形 conformance 的类型在 diagnostic 里更好读。

Type resolution 在被解析的 type representation 以某种方式非法时返回 singleton error type。Singleton error type 打印成 `<<error type>>`。为避免让用户困惑，含有 singleton error type 的 diagnostic 不应该被发出。一般来说，任何类型里含有 error type 的表达式都不需要再报错，因为别处已经报过了。

### Built-in types

用户心目中的那些基础类型，比如 `Int` 和 `Bool`，其实是标准库里定义的 struct。这些 struct 包着各种 **built-in type**，后者是编译器直接理解的。Built-in type 不是 nominal type，所以不能含有成员、不能通过 extension 添加新成员，也不能 conform to protocol。Built-in type 的值用特殊的 **compiler intrinsic** 来操作。标准库把 built-in type 包进 nominal type，并在这些 nominal type 上定义调用 intrinsic 函数的方法与运算符，从而呈现出用户期待的那套真正接口。

举例来说，`Int` struct 定义了单个名为 `_value` 的 stored property，类型是 `Builtin.Int`。`Int` 上的 `+` 运算符的实现是：从一对 `Int` 值里取出各自的 `_value` stored property，调用 `Builtin.sadd_with_overflow_Int64` 这个 compiler intrinsic 把它们相加，最后把得到的 `Builtin.Int` 包进一个新的 `Int` 实例里。

Built-in type 及其 intrinsic 定义在特殊的 `Builtin` 模块里，这个模块由编译器自己构造，不是从源码构建出来的。只有在用 `-parse-stdlib` frontend 标志调用编译器时，`Builtin` 模块才可见；标准库就是带这个标志构建的，而用户代码从不直接和 `Builtin` 模块打交道。

## Source Code Reference

关键源文件：

- `include/swift/AST/Type.h`
- `include/swift/AST/Types.h`
- `lib/AST/Type.cpp`

其他源文件：

- `include/swift/AST/TypeNodes.def`
- `include/swift/AST/TypeVisitor.h`
- `include/swift/AST/CanTypeVisitor.h`

**`Type`（class）**：表示一个不可变、唯一化的类型。它设计成按值传递，只存一个实例变量，即一个 `TypeBase *` 指针。

`getPointer()` 方法返回这个指针。该指针不是 `const` 的，不过 `TypeBase` 及其任何子类都没有定义会改写状态的方法。指针可以是 `nullptr`；默认构造函数 `Type()` 构造出一个 null 类型的实例。对 null 类型调用大多数方法都会崩溃；只有隐式的 `bool` 转换和 `getPointer()` 是安全的。

`getPointer()` 方法只是偶尔用到，因为类型通常按 `Type` 传递而不是 `TypeBase *`，而且 `Type` 重载了 `operator->`，会把方法调用转发给那个 `TypeBase *` 指针。虽然类型上的大多数操作实际上是 `TypeBase` 上的方法，但也有几个方法定义在 `Type` 自己身上（这些用 `.` 而不是 `->` 调用）：

- **各种遍历**：`walk()` 是一个通用的先序遍历，回调返回一个三态值——继续、停止、或跳过一棵子树。在它之上建了两个更简单的变体：`findIf()` 接受一个布尔谓词，`visit()` 接受一个返回 void 的回调，因而没法中止遍历。
- **变换**：`transformWithPosition()` 与 `transformRec()`。前者最通用，后者改变回调的签名，忽略 `TypePosition` 参数。回调会被递归地施加到一个类型内部所含的所有类型上。它既可以选择把某个类型替换成新类型，也可以让某个类型保持不变、转而尝试变换它的子类型。
- **Substitution**：`subst()` 实现 type substitution，这是一种特别常见的变换，把 generic parameter 或 archetype 替换成具体类型（见 `substitution-maps.tex` 的 Source Code Reference 一节）。
- **打印**：`print()` 输出类型的字符串形式，带很多定制选项；`dump()` 以 s-expression 的形式打印类型的树结构。后者在调试器里调用或者临时插打印语句时极其有用。

`Type` 类显式地 delete 了 `operator==` 与 `operator!=` 的重载，以强制在指针相等与 canonical 相等之间作出明确选择。要对可能带 sugar 的类型检查 type pointer equality，先用 `getPointer()` 把两边都拆开，再比较 `TypeBase *` 值：

```cpp
if (lhsType.getPointer() == rhsType.getPointer())
  ...;
```

Canonical type equality 更常用。要检查 canonical type equality，调用 `TypeBase` 上的 `isEqual()` 方法。和指针相等检查不同，下面这种写法只在两个类型都非 `nullptr` 时才成立：

```cpp
if (lhsType->isEqual(rhsType))
  ...;
```

**`TypeBase`（class）**：type kind 层级的根。它的实例总是由 AST context 唯一化并分配，分配在永久 arena 或 constraint solver arena 里。实例通常包在 `Type` 里。各个子类对应不同 kind 的类型：

- `NominalType` 及其四个子类：
  - `StructType`
  - `EnumType`
  - `ClassType`
  - `ProtocolType`
- `BoundGenericNominalType` 及其三个子类：
  - `BoundGenericStructType`
  - `BoundGenericEnumType`
  - `BoundGenericClassType`
- `GenericTypeParamType`、`DependentMemberType`，即两种 type parameter 类型。
- `ArchetypeType` 及其三个子类：
  - `PrimaryArchetypeType`
  - `ExistentialArchetypeType`
  - `OpaqueArchetypeType`
- Constraint type：
  - `ProtocolCompositionType`
  - `ParameterizedProtocolType`
- Existential type：
  - `ExistentialType`
  - `ExistentialMetatypeType`
- Structural type `TupleType`、`MetatypeType`。
- `AnyFunctionType` 及其两个子类：
  - `FunctionType`
  - `GenericFunctionType`
- `SugarType` 及其四个子类：
  - `TypeAliasType`
  - `OptionalType`
  - `ArrayType`
  - `DictionaryType`
- `BuiltinType` 及其子类（这里面有一堆冷僻的，下面只列几个）：
  - `BuiltinRawPointerType`
  - `BuiltinVectorType`
  - `BuiltinIntegerType`
  - `BuiltinIntegerLiteralType`
  - `BuiltinNativeObjectType`
  - `BuiltinBridgeObjectType`
- `ReferenceStorageType` 及其两个子类：
  - `WeakStorageType`
  - `UnownedStorageType`
- 其余全部：
  - `DynamicSelfType`
  - `UnboundGenericType`
  - `PlaceholderType`
  - `TypeVariableType`
  - `LValueType`
  - `ErrorType`

每个具体子类都定义了一组静态工厂方法，通常叫 `get()` 或类似名字，接受 structural component 并构造出一个该 kind 的新的唯一化类型。还有一组以 `get` 打头的 getter 方法，用来投影出各 kind 类型的 structural component。把 `TypeBase` 每个子类的 getter 都列一遍纯属重复，它们全都能在 `include/swift/AST/Types.h` 里找到。

### Desugaring casts

`TypeBase *` 的子类可以在运行期通过 `is<>`、`castTo<>` 和 `getAs<>` 这几个模板方法识别。

要检查一个类型是不是某个特定 kind，用 `is<>`：

```cpp
Type type = ...;

if (type->is<FunctionType>())
  ...;
```

要有条件地把一个类型转成某个特定 kind，用 `getAs<>`，转换失败时它返回 `nullptr`：

```cpp
if (FunctionType *funcTy = type->getAs<FunctionType>())
  ...;
```

最后，要断言一个类型必定是某个 kind，用 `castTo<>`：

```cpp
FunctionType *funcTy = type->castTo<FunctionType>();
```

这几个模板方法会在类型是 sugared type 时先脱糖，而且它们永远不可能转换**到**一个 sugared type。这通常正是我们想要的，因为 type sugar 本就不该影响行为。举例来说，如果 `type` 是 `Swift.Void` 这个 type alias type，那么 `type->is<TupleType>()` 返回 true，因为除了打印到 diagnostic 里的时候，它在所有意义上就是一个 tuple（一个空 tuple）。

### Direct casts

另有三个顶层模板函数 `isa<>`、`dyn_cast<>` 和 `cast<>`，它们作用在 `TypeBase *` 上。把它们用在 `Type` 上是错误的；必须先用 `getPointer()` 显式把指针拆出来。这几个转换**不**脱糖，因而允许转换到 sugared type。当出于某种原因必须把 sugared type 与 canonical type 区分开时，用的就是这套机制：

```cpp
Type type = ...;

if (isa<OptionalType>(type.getPointer()))
  ...;
```

### Canonical types

`getCanonicalType()` 方法输出一个 `CanType`，包着这个 `TypeBase *` 的 canonical 形态。Canonical type 只计算一次并被 memoize，所以这个操作很便宜。真正的计算在 `computeCanonicalType()` 里做。最后，`isCanonical()` 方法检查一个类型是否已经是 canonical 的。

### Visitors

要穷尽地处理每一种 kind 的类型，最简单的办法是对 kind 做 switch，kind 是 `TypeKind` 枚举的一个实例：

```cpp
Type ty = ...;
switch (ty->getKind()) {
case TypeKind::Struct: {
  auto *structTy = ty->castTo<StructType>();
  ...
}
case TypeKind::Enum:
case TypeKind::Class:
  ...
}
```

不过多数情况下用 **visitor 模式**更方便：继承 `TypeVisitor` 并覆写各个 `visit<Kind>Type()` 方法。然后用一个类型去调 visitor 的 `visit()` 方法，它就会执行上面那套 switch 加动态转换的套路：

```cpp
class MyVisitor: public TypeVisitor<MyVisitor> {
public:
  void visitStructType(StructType *ty) {
    ...
  }
};

MyVisitor visitor;

Type ty = ...;
visitor.visit(ty);
```

`TypeVisitor` 还定义了对应 `TypeBase` 层级中各个抽象基类的方法，所以举例来说，你可以覆写 `visitNominalType()` 来一次性处理所有 nominal type。

`TypeVisitor` 在收到 sugared type 时会保留这个信息；例如访问 `Int?` 会调用 `visitOptionalType()`，而访问 `Optional<Int>` 会调用 `visitBoundGenericEnumType()`。在你的操作的语义不依赖 type sugar 这种常见场合下，可以改用 `CanTypeVisitor` 模板类。那里的 `visit()` 方法接受 `CanType`，所以 `Int?` 得先 canonical 化成 `Optional<Int>` 再传进去。

> 译注：本库的打印器承担的是同一件事的另一半——对 `Node.Kind` 做穷尽分派。这里有个本章没有的陷阱：C++ 那边漏一个 `case` 编译器会警告，而本库的 `dispatchPrintName` 漏一个 kind 时**什么都不写**，渲染照常完成，输出里只留下 `Predicate<>`、`-> ` 这样的语法残缺，没有异常也没有占位符。判据与常驻测试见 [PrinterNodeKindParity.md](../PrinterNodeKindParity.md)。

### Nominal types

`TypeBase` 上的下列方法先做一次脱糖转换到 nominal type（所以它们也接受 type alias type 或其他 sugared type），然后返回 nominal type declaration；若该类型不属于 nominal 这一类，则返回 `nullptr`：

- `getAnyNominal()` 返回 `UnboundGenericType`、`NominalType` 或 `BoundGenericNominalType` 的 nominal type declaration，否则返回 `nullptr`。
- `getNominalOrBoundGenericNominal()` 返回 `NominalType` 或 `BoundGenericNominalType` 的 nominal type declaration，否则返回 `nullptr`。
- `getStructOrBoundGenericStruct()` 返回 `StructType` 或 `BoundGenericStructType` 的 type declaration，否则返回 `nullptr`。
- `getEnumOrBoundGenericEnum()` 返回 `EnumType` 或 `BoundGenericEnumType` 的 enum declaration，否则返回 `nullptr`。
- `getClassOrBoundGenericClass()` 返回 `ClassType` 或 `BoundGenericClassType` 的 class declaration，否则返回 `nullptr`。
- `getNominalParent()` 返回 `UnboundGenericType`、`NominalType` 或 `BoundGenericNominalType` 所存的 parent type，否则返回 `nullptr`。

### Recursive properties

有若干谓词用来判定一个类型是否递归地含有具备某种性质的其他类型。它们在类型构造时就算好了，因此检查起来很便宜：

- `hasTypeVariable()` 判定该类型是分配在永久 arena 还是 constraint solver arena 里。
- `hasPrimaryArchetype()`、`hasOpaqueArchetype()`、`hasOpenedExistential()`。
- `hasTypeParameter()`。
- `hasUnboundGenericType()`、`hasDynamicSelf()`、`hasPlaceholder()`。
- `hasLValueType()` 判定该类型是否含有 l-value type。

### Utility operations

这些方法封装了一些常用的模式：

- `getOptionalObjectType()` 对由标准库的 `Optional` enum 声明构造出来的 generic nominal type `Optional<T>`，返回其 payload type `T`。对其他任何 kind 的类型，返回 null 类型。
- `getMetatypeInstanceType()` 在该类型是 `T.Type` 时返回 `T`，否则返回 `T` 本身（而不是 null 类型）。
- `mayHaveMembers()` 检查该类型是否是 nominal type、archetype、existential type 或 dynamic `Self` type。

### Recovering the AST context

所有非 canonical 的类型都指向它们的 canonical type，而 canonical type 指向 AST context。

- `getASTContext()` 从一个类型取回那个单例的 AST context。

**`CanType`（class）**：`CanType` 类包着一个已知是 canonical 的 `TypeBase *` 指针。指针可用 `getPointer()` 方法取回。它把各种方法转发给 `Type` 或 `TypeBase *`。从 `CanType` 到 `Type` 有隐式转换。反方向上，显式的单参数构造函数 `CanType(Type)` 会断言该类型是 canonical 的；不过多数时候用的是 `TypeBase` 上的 `getCanonicalType()` 方法。

`operator==` 与 `operator!=` 用来测试 `CanType` 的 type pointer equality。前面讲过的 `isEqual()` 方法实现的是 sugared type 上的 canonical 相等：它先把两边 canonical 化，再对得到的 canonical type 检查 type pointer equality。因此下面两行是等价的：

```cpp
if (lhsType->isEqual(rhsType)) ...;
if (lhsType->getCanonicalType() == rhsType->getCanonicalType()) ...;
```

`CanType` 类可以配合 `isa<>`、`cast<>` 和 `dyn_cast<>` 模板使用。后两者返回的不是真正的 `TypeBase` 子类，而是该子类对应的 **canonical type wrapper**。`TypeBase` 的每个子类都有一个对应的 canonical type wrapper；若子类叫 `FooType`，其 canonical wrapper 就叫 `CanFooType`。Canonical type wrapper 把 `operator->` 转发给具体的 `TypeBase` 子类，同时定义自己的方法（用 `.` 调用），用来投影出该类型中已知是 canonical 的那些 component。

举例来说，`FunctionType` 有一个返回 `Type` 的 `getResult()` 方法，于是 canonical type wrapper `CanFunctionType` 就有一个返回 `CanType` 的 `getResult()` 方法。Wrapper 的方法并不完备，用不用也不强制，因为你完全可以在投影出一个已知 canonical 的类型之后，显式调用 `CanType(Type)` 或 `getCanonicalType()`：

```cpp
CanType canTy = ...;
CanFunctionType canFuncTy = cast<FunctionType>(canTy);

// method on CanFunctionType: returns CanType(canFuncTy->getResult())
CanType canResultTy = canFuncTy.getResult();

// operator-> forwards to method on FunctionType: returns Type
CanType resultTy = CanType(canFuncTy->getResult());
```

**`AnyFunctionType`（class）**：`FunctionType` 与 `GenericFunctionType` 的基类。

- `getParams()` 返回一个 `AnyFunctionType::Param` 的数组。
- `getResult()` 返回返回类型。
- `getExtInfo()` 返回一个 `AnyFunctionType::ExtInfo` 实例，存着那些额外的非类型属性。

**`AnyFunctionType::Param`（class）**：表示 function type 参数列表里的一个参数。

- `getPlainType()` 返回该参数的类型。若该参数是 variadic 的（`T...`），返回的是元素类型 `T`。
- `getParameterType()` 同上，但若该参数是 variadic 的，返回的是类型 `Array<T>`。
- `isVariadic()`、`isAutoClosure()` 给出那些特殊行为。
- `getValueOwnership()` 返回一个 ownership specifier，编码为 `ValueOwnership` 枚举的实例。

**`ValueOwnership`（enum class）**：`AnyFunctionType::Param::getValueOwnership()` 的返回类型。

- `ValueOwnership::Default`
- `ValueOwnership::InOut`
- `ValueOwnership::Shared`
- `ValueOwnership::Owned`

**`AnyFunctionType::ExtInfo`（class）**：表示 function type 的那些非类型属性。

---

> 译自 `docs/Generics/chapters/types.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
