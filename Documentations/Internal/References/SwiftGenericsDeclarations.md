# Declarations（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/declarations.tex`（《Compiling Swift Generics》一书的「Declarations」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `8992ea82`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本库从 `__swift5_types`、`__swift5_protos`、`__swift5_proto` 三个 section 里读回来的东西，正是这一章描述的那几类声明——nominal type declaration、protocol declaration（连同它的 associated type 与 associated requirement）、以及 extension 所承载的 conformance。书讲的是「源码怎么写出这些声明」，本库做的是反方向：从 descriptor 把它们还原成源码拼写。因此这一章里的 declared interface type、interface type、`self` parameter 的形状、generic parameter 的 depth/index 坐标、requirement 的四种 kind，都是本库 interface 生成路径每天在处理的对象。译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（declaration、value declaration、type declaration、declaration context、interface type、declared interface type、nominal type declaration、generic parameter declaration、requirement、constraint type、`where` clause、associated type declaration、associated requirement、primary associated type、opaque parameter、captured value、closure conversion、storage declaration……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Requirement Signatures 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 canonical generic parameter type。源码里写 `T`、`U` 的，canonical 形式分别是 `τ_0_0`、`τ_0_1` |
> | `[T: P]` | **conformance requirement**：`T` 的 replacement type 必须 conform to `P` |
> | `[T: C]` | **superclass requirement**：`T` 的 replacement type 必须是 class `C` 的子类 |
> | `[T: AnyObject]` | **layout requirement**：`T` 的 replacement type 在运行时必须表示为单个 reference-counted 指针 |
> | `[T == U]` | **same-type requirement**：`T` 与 `U` 的 replacement type 必须 canonically 相等 |
> | `[…]_P` | 下标写 protocol 名，表示这是 protocol `P` 陈述的 associated requirement，例如 `[Self.Element == Self.Iterator.Element]_Sequence` |
> | `∅` | 空集 |
> | `C ← C ∪ {d}` | 把 `d` 并进集合 `C`；`←` 是赋值 |
> | `PARENT(d)` | 包含声明 `d` 的那个 declaration context |
> | `≠` | 不等于 |

---

**Declaration** 是 Swift 程序的构件。在 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)） 里我们看到，用户的整个程序是一棵层级树根部的 module declaration，**file unit** 是它的直接子节点。现在我们会看到，一个 file unit 持有一串 **top-level declaration**，它们对应源文件里的几大分块，而这些声明内部还可以继续嵌套别的声明。我们会像 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 对 type 所做的那样，把各种声明整理成一套分类。然后聚焦于声明 generic parameter 和陈述 requirement 的语法形式——它们是所有 generic declaration 共有的。最后以函数、闭包和 captured value 的讨论收尾。

先从声明分类里两条最主要的分界说起：

1. **Value declaration** 是可以从 expression 里按名字引用的声明，变量、函数之类都属于此。每个 value declaration 都有一个 **interface type**，也就是我们赋给「引用这个声明的那个表达式」的类型。
2. **Type declaration** 是可以从 type representation 里按名字引用的声明，struct、type alias 等等属于此。Type declaration 声明一个类型，称为该 type declaration 的 **declared interface type**。

并非所有声明都是 value declaration。Extension declaration 给一个已有的 nominal type declaration 添加成员（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)）），但 extension 本身没有名字。**Top-level code declaration** 持有写在源文件顶层的语句和表达式，同样地，它在语义上也没有名字。

### Declaration contexts

每个声明都被包含在某个 **declaration context** 里，而 declaration context 就是任何**包含**声明的东西。看这个程序：

```swift
func squares(_ nums: [Int]) -> [Int] {
  return nums.map { x in x * x }
}
```

参数声明 `x` 是闭包表达式 `{ x in x * x }` 的子节点，而不是外层函数声明的直接子节点。所以 closure expression 是 declaration context，却不是 declaration。反过来，parameter declaration 是 declaration，却不是 declaration context。最后，`squares()` 函数本身既是 declaration 也是 declaration context。

### Type declarations

由于 Swift 的文法允许 type representation 出现在表达式内部，每个 type declaration **同时**也是 value declaration。Type declaration 的 interface type 是由它的 declared interface type 构成的 metatype。这句话读起来拗口，但它背后的想法每个 Swift 程序员都熟悉。考虑一个带类型标注和初值的全局变量：

```swift
struct Horse {}
let myHorse: Horse = Horse()
```

Struct 声明 `Horse` 在这里被引用了两次：第一次在 `:` 后面的类型标注里，第二次在 `=` 后面的初值表达式里。在类型标注中，`Horse` 指的是 `Horse` 的 **declared interface type**，也就是 nominal type `Horse`；我们是在声明「`myHorse` 变量存放一个类型叫这个名字的值」。第二次引用来自初值表达式，指的是**类型本身**作为一个值，所以用的是它的 **interface type**，即 metatype `Horse.Type`。（回忆 `types.tex` 的 More Types 一节那张图。）再往下，这个 metatype 值是一个 call expression 的 callee，而那是「调用名为 `init` 的 constructor 成员」的简写。写得更显式一些就是：

```swift
let myHorseType: Horse.Type = Horse.self
let myHorse: Horse = myHorseType.init()
```

### Nominal type declarations

由 `struct`、`enum`、`class` 关键字声明；Swift 5.5 还加进了 `actor`，在我们看来它就是一个 class（SE-0306）。Nominal type declaration 是 declaration context，它们所包含的声明称为 **member declaration**。函数成员通常叫 **method**，成员变量叫 **property**，**member type declaration** 就是字面上的意思。

Struct 和 class 可以包含一种特殊的 property declaration，叫 **stored property declaration**。Struct 值直接存放它的 stored property，而 class 值是一个指向堆上 box 的引用，box 里装着它的 stored property。Enum 类型的值则在若干元素中恰好存一个；enum declaration 里没有 stored property，取而代之的是用 `case` 关键字引入的 **enum element declaration**。

Nominal type declaration 的成员对 name lookup 可见（见 `compilation-model.tex` 的 Name Lookup 一节），在该 nominal type declaration 自己的作用域内（unqualified lookup）和作用域外（qualified lookup）都是如此。下面这段代码展示了三个后面会细讲的特性：

- class 可以继承一个 superclass type，superclass 的成员在 subclass 里也可见（见 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Subclassing 一节）。
- nominal type declaration 可以 conform to protocol（见 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)））。
- extension 给已有的 nominal type declaration 添加成员（见 `extensions.tex`）。

**代码清单（Name lookup 的几种行为）.**

```swift
class Form { static func callee1() {} }
protocol Shape { static func callee2() }
extension Shape { static func callee3() {} }

struct Square: Shape {
  class Circle: Form {
    static func caller() {
      ...  // unqualified lookup from here
    }
  }
}
```

`caller()` 的函数体可以用单个标识符引用 `callee1()`、`callee2()` 或 `callee3()`。要解析这个标识符，unqualified lookup 必须遍历这几个 declaration context，从左上角出发：

```
  func caller()  --parent-->  class Circle  --parent-->  struct Square
                                    |                          |
                               superclass                 conforms to
                                    v                          v
                                class Form              protocol Shape
                                                               |
                                                           extension
                                                               v
                                                        extension Shape
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

关于 name lookup，我们在 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 和 `extensions.tex` 的 Direct Lookup 一节还会再说。

Nominal type declaration 声明一个带有自己名字和身份的新类型（所以叫「nominal」）。Nominal type declaration 的 declared interface type 称作 nominal type，我们在 `types.tex` 的 Fundamental Types 一节谈过：

```swift
struct Universe {     // declared interface type: Universe
  struct Galaxy {}    // declared interface type: Universe.Galaxy

  func solarSystem() {
    struct Planet()   // declared interface type: Planet
  }
}
```

`Galaxy` struct 的 declared interface type 是 `Universe.Galaxy`，而 `Planet` 的 declared interface type 就是 `Planet`，没有 parent type。这反映了语义上的差别：`Galaxy` 作为 `Universe` 的成员对 qualified lookup 可见，而 `Planet` 只在 `solarSystem()` 的作用域内对 unqualified lookup 可见；我们称它为 **local type declaration**。Nominal type 嵌套的更多细节见 `substitution-maps.tex` 的 Nested Nominal Types 一节。

> 译注：这里说的 nominal type declaration，在编译产物里就是 `__swift5_types` 这个 section 里的一条 type context descriptor；「declared interface type 带不带 parent type」这个区别，在 descriptor 里表现为 parent 指针指向外层 context descriptor 还是指向一个 anonymous context。本库如何在不动 symbol index、不动 demangler 的前提下读这些 descriptor，见 [SelfContainedABILayer.md](../SelfContainedABILayer.md)。

### Type alias declarations

由 `typealias` 关键字引入。**Underlying type** 写在 `=` 的右边：

```swift
typealias Hands = Int  // one hand is four inches
func measure(horse: Horse) -> Hands {...}
let metatype = Hands.self
```

Type alias declaration 的 declared interface type 是一个 type alias type。这个 type alias type 的 canonical type 就是它的 underlying type。因此，如果我们在诊断信息里打印 `measure()` 的返回类型，会打印成 `Hands`，但除此之外它的行为和 `Int` 毫无二致。

和所有 type declaration 一样，type alias declaration 的 interface type 是它的 declared interface type 的 metatype。上面这段里，表达式 `Hands.self` 的 metatype type 是 `Hands.Type`。这是一个 sugared type，canonically 等于 `Int.Type`。

Type alias 虽然是 declaration context，但它唯一能包含的声明是 generic parameter declaration——前提是这个 type alias 本身是 generic 的。

### Other type declarations

至此我们看过了头两种 type declaration。接下来的两节会在此基础上展开，去看 generic parameter、protocol 和 associated type 的声明。到那时，我们对 Swift 泛型的深入探索才算真正开始。下面列出所有 type declaration 的种类和它们的 declared interface type，每种给一个代表性的样本：

| **Type declaration** | **Declared interface type** |
|---|---|
| Nominal type declaration：<br>`struct Horse {...}` | Nominal type：<br>`Horse` |
| Type alias declaration：<br>`typealias Hands = Int` | Type alias type：<br>`Hands`（canonically `Int`） |
| Generic parameter declaration：<br>`<T: Sequence>` | Generic parameter type：<br>`T`（canonically `τ_0_0`） |
| Protocol declaration：<br>`protocol Sequence {...}` | Protocol type：<br>`Sequence` |
| Associated type declaration：<br>`associatedtype Element` | Dependent member type：<br>`Self.Element` |

## Generic Parameters

各种声明都可以带一个 **generic parameter list**，我们把它们叫做 **generic declaration**。先看那些 generic parameter list 直接写在源码里的：struct、enum、class、type alias、函数、constructor 和 subscript。所有这些情形下，**parsed generic parameter list** 都是跟在 generic declaration 名字后面的 `<...>` 语法：

```swift
struct Outer<T> {...}
```

这个列表里每一个逗号分隔的元素都是一条 **generic parameter declaration**；它是一种 type declaration，声明一个 generic parameter type。Generic parameter declaration 的作用域覆盖其 parent declaration（即带这个 generic parameter list 的那个声明）的整个 source range。带 generic parameter list 的声明可以嵌套在另一个 generic declaration 内部；每个内层 generic declaration 实际上同时被自己的 generic parameter 和所有外层声明的 generic parameter 所参数化。因此 unqualified lookup 能「看见」所有外层的 generic parameter declaration。

在我们的分类里，任何可以带 generic parameter list 的声明种类同时也是 declaration context，因为它包含别的声明——即它的 generic parameter declaration。如果一个 declaration context 至少有一个 parent context 带 generic parameter list，我们就说它是一个 **generic context**。

Generic parameter declaration 的名字在 unqualified lookup 之后就不起作用了。取而代之的是，我们给每条 generic parameter declaration 分配一对整数（更准确地说是自然数，它们非负），即 **depth** 和 **index**：

- depth 选定一个 generic parameter list；最外层 generic parameter list 声明的 generic parameter 位于 depth 0，每向内嵌套一层 generic parameter list，depth 加一。
- index 在一个 generic parameter list 内部选定某个 generic parameter；同级的 generic parameter declaration 从零开始连续编号。

我们在上面的 `Outer` struct 里写几个嵌套的 generic declaration。下面这段里，`two()` 在 `T` 和 `U` 上是 generic 的，而 `four()` 在 `T`、`V`、`W` 和 `X` 上是 generic 的：

```swift
struct Outer<T> {
  func two<U>(u: U) -> T {...}

  struct Both<V, W> {
    func four<X>() -> X {...}
  }
}
```

当 type resolution 解析 `two()` 返回类型里那个写作 `T` 的 type representation 时，它输出一个 generic parameter type；比如出现在诊断信息里，这个类型会打印成 `T`。这是一个 sugared type。每个 generic parameter type 还有一个只记录 depth 和 index 的 canonical 形式，我们把 canonical generic parameter type 记作 `τ_d_i`，其中 `d` 是 depth、`i` 是 index。两个 generic parameter type canonically 相等，当且仅当它们的 depth 和 index 相同。这样做是可靠的，因为在词法作用域内部，depth 和 index 已经无歧义地确定了一个 generic parameter。

我们把 `two()` 里可见的所有 generic parameter 列出来：

| | | |
|---|---|---|
| **Name：** | `T` | `U` |
| **Depth：** | 0 | 1 |
| **Index：** | 0 | 0 |
| **Type：** | `τ_0_0` | `τ_1_0` |

再列 `four()` 的：

| | | | | |
|---|---|---|---|---|
| **Name：** | `T` | `V` | `W` | `X` |
| **Depth：** | 0 | 1 | 1 | 2 |
| **Index：** | 0 | 0 | 1 | 0 |
| **Type：** | `τ_0_0` | `τ_1_0` | `τ_1_1` | `τ_2_0` |

`two()` 的 generic parameter `U` 与 `four()` 的 generic parameter `V` 有相同的 declared interface type `τ_1_0`。这不成问题，因为它们各自 parent declaration（`two()` 与 `Both`）的 source range 并不相交。

按 depth 编号这件事，在嵌套 generic nominal type declaration 的 declared interface type 里看得最清楚。例如 `Outer.Both` 的 declared interface type 就是 generic nominal type `Outer<τ_0_0>.Both<τ_1_0, τ_1_1>`。

### Implicit generic parameters

有时 generic parameter list 并不写在源码里。每个 protocol declaration 都有一个 generic parameter list，其中只有一个名为 `Self` 的 generic parameter（见本章 Protocols 一节）；而每个 extension declaration 都有一个从被扩展类型那里克隆来的 generic parameter list（见 `extensions.tex`）。这些 implicit generic parameter 可以在其作用域内按名字引用，和 parsed generic parameter list 里的 generic parameter declaration 一样（见 `type-resolution.tex` 的 Identifier Type Representations 一节）。

函数、constructor 和 subscript 声明还可以用 `some` 关键字声明 **opaque parameter**，并且可以和 generic parameter list 组合使用：

```swift
func pickElement<E>(_ elts: some Sequence<E>) -> E {...}
```

一条 opaque parameter 同时声明了三样东西：一个参数值、一个作为该值类型的 generic parameter type，以及这个类型必须满足的一条 requirement。这里我们可以在函数体内的表达式里引用 `elts`，但没法在 type representation 里给 `elts` 的**类型**起名。不过从 expression 上下文里，opaque parameter 的类型可以通过 `type(of:)` 这个特殊形式拿到，它产出一个 metatype 值，从而可以在这些类型上调用 static 方法。

**Generic parameter list request** 把 opaque parameter 追加到 parsed generic parameter list 后面，所以按 index 顺序它们排在 parsed generic parameter 之后。在 `pickElement()` 里，generic parameter `E` 的 canonical type 是 `τ_0_0`，而与 `elts` 关联的那个 opaque parameter 的 canonical type 是 `τ_0_1`。Opaque parameter declaration 同时还陈述了一个 constraint type，它对这个无名 generic parameter 施加一条 requirement。这一点我们下一节再讲。注意，当 `some` 出现在函数的**返回类型**里时，它声明的是一个 **opaque result type**，那是一个相关但不同的特性（见 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)），中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）。

在 `generic-signatures.tex` 里，我们会讨论 generic signature：一个把「参数化某个声明的所有 generic parameter」收集起来的数据结构，与表层语法无关。

## Requirements

Generic declaration 的 requirement 约束了调用方能提供哪些 generic argument type。这给 generic declaration 的 type parameter 赋予了新的能力，使它们得以抽象那些满足这些 requirement 的具体类型。在理论和实现中，我们都用下面这套编码来表示 requirement。

**定义.** 一条 **requirement** 是一个三元组，由一个 **requirement kind**、一个 subject type `T`（通常是 type parameter），以及一条随 requirement kind 而定的信息构成：

- **conformance requirement** `[T: P]` 表示 `T` 的 replacement type 必须 conform to `P`，而 `P` 必须是 protocol type、protocol composition type 或 parameterized protocol type。
- **superclass requirement** `[T: C]` 表示 `T` 的 replacement type 必须是某个 class type `C` 的子类。
- **layout requirement** `[T: AnyObject]` 表示 `T` 的 replacement type 在运行时必须表示为单个 reference-counted 指针。
- **same-type requirement** `[T == U]` 表示 `T` 与 `U` 的 replacement type 必须 canonically 相等。

当我们在一段自足的代码片段里看具体的 requirement 实例时，前三种 kind 共用同一套记法不会产生歧义，因为右边所引用的类型已经决定了 requirement kind。而当我们抽象地谈论 requirement 时，会在写出 `[T: P]` 或 `[T: C]` 之前先明确说明 `P` 是某个 protocol、`C` 是某个 class。

### Constraint types

在引入「完全一般地陈述 requirement」的 trailing `where` 子句语法之前，先看一种简写：在 generic parameter declaration 的 inheritance clause 里陈述一个 **constraint type**：

```swift
func allEqual<E: Equatable>(_ elements: [E]) {...}
```

Generic parameter declaration `E` 声明了 generic parameter type `τ_0_0`，同时也陈述了 constraint type `Equatable`。这是标准库里声明的一个 protocol，所以陈述出来的 requirement 是 conformance requirement `[τ_0_0: Equatable]`。更一般地说，constraint type 是下面之一：

1. protocol type，例如 `Equatable`。
2. parameterized protocol type，例如 `Sequence<String>`。
3. protocol composition type，例如 `Sequence & MyClass`。
4. class type，例如 `NSObject`。
5. `AnyObject` **layout constraint**，它把可能的具体类型限制为那些表示为单个 reference-counted 指针的类型。

前三种情形陈述出来的是 conformance requirement。其余情形则是 superclass requirement 或 layout requirement。所有情形下，requirement 的 subject type 都是该 generic parameter 的 declared interface type。

**例.** 注意 `open()` 的 generic parameter `B` 陈述的 constraint type 是 `Box<C>`，而它引用了第二个 generic parameter `C`：

```swift
func open<B: Box<C>, C>(box: B) -> C {
  return box.contents!
}

class Box<Contents> {
  var contents: Contents? = nil
}
```

这体现了 scope tree 的一个性质：generic parameter 在 generic declaration 的整个 source range 内都可见，**包括 generic parameter list 自身内部**。于是 `open()` 这个声明陈述了 superclass requirement `[τ_0_0: Box<τ_0_1>]`。下面是 `open()` 的一种可能用法，这里先不作解释：

```swift
struct Vegetable {}
class FarmBox: Box<Vegetable> {}
let vegetable: Vegetable = open(box: FarmBox())
```

### Opaque parameters

一条 opaque parameter declaration 写成 `some` 关键字后跟一个 constraint type（见本章 Generic Parameters 一节）。这给 opaque parameter declaration 所引入的那个 generic parameter type 指定了一条 conformance、superclass 或 layout requirement。例如下面两个声明是等价的：

```swift
func pickElement<E>(_ elts: some Sequence<E>) -> E {...}
func pickElement<E, S: Sequence<E>>(_ elts: S) -> E {...}
```

我们后面会看到 constraint type 还出现在其它若干位置上，而且所有情形里，它陈述的都是一条带某个特定 subject type 的 requirement：

1. 在 protocol 或 associated type 的 inheritance clause 里（见本章 Protocols 一节）。
2. 在返回位置上跟在 `some` 关键字后面，此时它声明一个 opaque result type（见 `opaque-result-types.tex`）。
3. 跟在引入 existential type 的 `any` 关键字后面（见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)）），只有一个例外：constraint type 不能单独是一个 class（比如 `any MyClass & Equatable` 是允许的，而 `any MyClass` 就只是 `MyClass`）。

### Trailing where clauses

Requirement 也可以在附加于 generic declaration 的 `where` 子句里陈述。这比单靠 generic parameter 的 inheritance clause 所能表达的更一般。

`where` 子句的一个条目定义一条 requirement，其 subject type 是显式写出来的，这样 dependent member type 也能成为 requirement 的约束对象；下面我们陈述了两条 requirement，`[τ_0_0: Sequence]` 和 `[τ_0_0.Element: Comparable]`：

```swift
func isSorted<S>(_: S) where S: Sequence, S.Element: Comparable {...}
```

`where` 子句还可以陈述 same-type requirement。下一个例子里，我们用 inheritance clause 语法陈述了两条 conformance requirement，另外还有一条 conformance requirement，以及 same-type requirement `[τ_0_0.Element == τ_0_1.Element]`：

```swift
func merge<S1: Sequence, S2: Sequence>(_: S1, _: S2) -> [S1.Element]
    where S1.Element: Comparable, S1.Element == S2.Element {...}
```

注意，函数的 `where` 子句里没有办法引用 opaque parameter 的类型，但任何使用 opaque parameter 的声明都总能改写成使用具名 generic parameter 的等价形式，所以一般性并没有损失。

我们在 `types.tex` 里见过，parser 读到源码里的类型标注时，构造出一个 type representation——一个较低层的语法对象，必须经过 type resolution 才能得到 type。类似地，requirement 也有其语法形式，称为 **requirement representation**。Parser 在读 `where` 子句时构造 requirement representation。语法实体与语义实体之间的关系如下图：

```
  Requirement representation  --resolves to-->  Requirement
             |                                      |
          contains                              contains
             v                                      v
     Type representation      --resolves to-->      Type
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

Requirement representation 只有两种，因为在右边的 type representation 被 resolve 出来之前，`:` 这种形式无法区分 conformance、superclass 和 layout requirement：

1. **constraint requirement representation** `T: C`，其中 `T` 和 `C` 都是 type representation。
2. **same-type requirement representation** `T == U`，其中 `T` 和 `U` 都是 type representation。

回忆一下，conformance requirement 右边是 protocol type、protocol composition type 或 parameterized protocol type（见 `types.tex` 的 Fundamental Types 一节）。当右边是 protocol composition 时，我们把这条 requirement 分解成若干更简单的 requirement，composition 的每个成员各一条。例如若 `MyClass` 是一个 class，那么 requirement `[τ_0_0: Sequence & MyClass]` 会拆成 `[τ_0_0: Sequence]` 和 `[τ_0_0: MyClass]`，后者是一条 superclass requirement。空的 protocol composition，也就是写作 `Any` 的那个，是一个平凡情形；在 `where` 子句里陈述一条对 `Any` 的 conformance requirement 什么也不做，但这是允许的。Parameterized protocol type 同样会分解，详见本章 Protocols 一节。

下一节我们会引入一套关于 derived requirement 的形式系统，在那里我们会假定只剩下「对 protocol type 的 conformance requirement」，并且 requirement 的 subject type 永远是 type parameter 而非任意类型。`building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Decomposition and Desugaring 一节会说明我们如何消除这些不必要的一般性。

### Contextually-generic declarations

嵌套在另一个 generic declaration 内部的 generic declaration 可以陈述一个 `where` 子句，而不引入自己的 generic parameter。这叫做 **contextually-generic declaration**：

```swift
enum LinkedList<Element> {...}

extension LinkedList {
  func sum() -> Element where Element: AdditiveArithmetic {...}
}
```

把 `where` 子句挂在类型的某个成员上，与把该成员移到一个 constrained extension 里（见 `extensions.tex` 的 Constrained Extensions 一节），两者在语义上没有区别，所以上面这段等价于：

```swift
extension LinkedList where Element: AdditiveArithmetic {
  func sum() -> Element {...}
}
```

不过出于历史原因，这两种声明的 mangled symbol name 并不相同，所以上面这个改写不是一次 ABI 兼容的变换。

> 译注：正因为 mangled name 不同，本库在从二进制还原时也无法把两者合并——一个成员到底当初写成「带 `where` 子句的成员」还是「constrained extension 里的成员」，是可以从符号里区分出来的。本库把 extension 容器按 (protocol, where-fingerprint, retroactive) 三元组归并、并按 conformance 归属成员的做法，见 [ExtensionContainerUnification.md](../ExtensionContainerUnification.md) 与 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。

在 `generic-signatures.tex` 里我们会看到，一个声明的 generic signature 记录了它的全部 requirement，无论这些 requirement 是否在源码里陈述过。

### History

本节描述的语法是逐步演进过来的：

- `where` 子句过去写在 `<` 和 `>` 之内，Swift 3 把它移到了现在这个「trailing」位置（SE-0081）。
- Generic type alias 在 Swift 3 引入（SE-0048）。
- 含 class type 的 protocol composition 在 Swift 4 引入（SE-0156）。
- Generic subscript 在 Swift 4 引入（SE-0148）。
- 由于实现上的限制，直到 Swift 3，`where` 子句才能陈述约束外层 generic parameter 的 requirement；而 contextually-generic declaration 直到 Swift 5.3 才被允许（SE-0261）。
- Opaque parameter declaration 在 Swift 5.7 引入（SE-0341）。

## Protocols

`protocol` 关键字引入一条 **protocol declaration**，它是一种特殊的 nominal type declaration。Protocol 的成员（type alias 除外）都是 requirement，必须由 conforming type 里对应的成员来 witness。Protocol 的 property、subscript 和 method 称为 **value requirement**。它们没有函数体，但除此之外和具体 nominal type 的 member declaration 一样。Protocol declaration 的 declared interface type 是一个 protocol type。

每个 protocol 都有一个 implicit generic parameter list，其中只有一个名为 `Self` 的 generic parameter，它抽象的是 conforming type。`Self` 的 declared interface type 永远是 `τ_0_0`；protocol 不能嵌套在其它 generic context 里（见 `substitution-maps.tex` 的 Nested Nominal Types 一节），也不能声明任何别的 generic parameter。

`associatedtype` 关键字引入一条 **associated type declaration**，它只能出现在 protocol 内部。它的 declared interface type 是一个 dependent member type（见 `types.tex` 的 Fundamental Types 一节）。具体来说，protocol `P` 里一个 associated type `A` 的 declared interface type，是由 `Self` 这个 base type 和 `A` 一起构成的 bound dependent member type，记作 `Self.[P]A`。一个 conform to「带 associated type 的 protocol」的 nominal type，必须为每个 associated type 声明一个 type witness（见 `conformances.tex` 的 Type Witnesses 一节）。

Protocol 还可以对 `Self` 及其 dependent member type 施加 **associated requirement**。Conforming type 连同它的 type witness 必须共同满足这些 associated requirement。语言里有若干种陈述 associated requirement 的方式，我们现在逐个过一遍。

### Protocol inheritance clauses

一个 protocol 可以带 inheritance clause，里面是一到多个逗号分隔的 constraint type。每个 inheritance clause 条目都陈述一条 subject type 为 `Self` 的 associated requirement。这些是 conforming type 自身为了 conform 而必须额外满足的 requirement。

一条 subject type 为 `Self` 的 associated conformance requirement 建立起一种 **protocol inheritance** 关系。陈述这条 requirement 的 protocol 叫 **derived protocol**，右边的那个 protocol 叫 **base protocol**。我们说 derived protocol **inherit**（有时也说 **refine**）自 base protocol。对一个 protocol 做 qualified lookup 时会遍历它所有的 base protocol（对具体 nominal type 则是遍历它所 conform 的每个 protocol 的所有 base protocol）。

例如标准库的 `Collection` protocol 通过陈述 associated requirement `[Self: Sequence]` 而 inherit 自 `Sequence`：

```swift
protocol Collection: Sequence {...}
```

Protocol 可以通过在 inheritance clause 里陈述一个 `AnyObject` layout constraint，把 conforming type 限制为那些具有 reference-counted 指针表示的类型：

```swift
protocol BoxProtocol: AnyObject {...}
```

Protocol 也可以把 conforming type 限制为某个 superclass 的子类：

```swift
class Plant {}
class Animal {}
protocol Duck: Animal {}
class MockDuck: Plant, Duck {}  // error: not a subclass of Animal
```

如果 associated layout requirement `[Self: AnyObject]` 要么被显式陈述、要么是某条别的 associated requirement 的推论，我们就说这个 protocol 是 **class-constrained** 的。关于 protocol inheritance clause 与 name lookup 的语义，我们在 `generic-signatures.tex` 的 Requirement Signatures 一节、`type-resolution.tex` 的 Identifier Type Representations 一节以及 `building-generic-signatures.tex` 里还会细说。

### Primary associated types

Protocol 可以用一种形似 generic parameter list 的语法，声明一串 **primary associated type**：

```swift
protocol IteratorProtocol<Element> {
  associatedtype Element
  mutating func next() -> Element?
}
```

Generic parameter list 引入的是新的 generic parameter declaration，而 primary associated type 列表里的条目引用的是**已经存在**的 associated type declaration——要么在这个 protocol 自己身上，要么在某个 base protocol 上。

对一个带 primary associated type 的 protocol 的引用，可以配上一串 generic argument type（每个 primary associated type 一个），构成一个 **parameterized protocol type**。出现在 conformance requirement 右边时，parameterized protocol type 分解成「一条对该 protocol 的 conformance requirement，外加一串 same-type requirement」。下面两段是等价的：

```swift
func sumOfSquares<I>(_: I) -> Int
    where I: IteratorProtocol<Int> {...}
func sumOfSquares<I>(_: I) -> Int
    where I: IteratorProtocol, I.Element == Int {...}
```

更多细节见 `building-generic-signatures.tex` 的 Decomposition and Desugaring 一节。Parameterized protocol type 和 primary associated type 是在 Swift 5.7 加进语言的（SE-0346）。

### Associated requirements

Associated type declaration 可以带 inheritance clause，里面是一到多个逗号分隔的 constraint type。每个条目定义一条作用在该 associated type declaration 的 declared interface type 上的 requirement，所以下面这行给出了 `[Self.Data: Codable]` 和 `[Self.Data: Hashable]`：

```swift
associatedtype Data: Codable, Hashable
```

Associated type declaration 也可以带 trailing `where` 子句，从而完全一般地陈述 associated requirement。标准库的 `Sequence` protocol 同时展示了 primary associated type 和 associated requirement：

```swift
protocol Sequence<Element> {
  associatedtype Iterator: IteratorProtocol
  associatedtype Element where Element == Iterator.Element

  func makeIterator() -> Iterator
}
```

`Self.Iterator` 上那条 associated conformance requirement 本可以改用 `where` 子句来陈述：

```swift
associatedtype Iterator where Iterator: IteratorProtocol
```

`where` 子句还可以直接挂在 protocol 自己身上；这与把它挂在 associated type declaration 上没有语义差别：

```swift
protocol Sequence where Iterator: IteratorProtocol,
                        Element == Iterator.Element {...}
```

最后，我们还可以用 `Self` 显式限定这些 member type：

```swift
protocol Sequence where Self.Iterator: IteratorProtocol,
                        Self.Element == Self.Iterator.Element {...}
```

所有写法陈述的都是同样那两条 associated requirement。我们的记法是给 associated requirement 加一个下标，标出是哪个 protocol 陈述了这条 requirement：

```
[Self.Iterator: IteratorProtocol]_Sequence
[Self.Element == Self.Iterator.Element]_Sequence
```

把在一个 protocol `P` 里陈述 associated requirement 的所有办法总结一下：

- protocol 自身可以陈述一个 inheritance clause。每个条目定义一条 subject type 为 `Self` 的 conformance、superclass 或 layout requirement。
- associated type declaration `A` 可以陈述一个 inheritance clause。每个条目定义一条 subject type 为 `Self.[P]A` 的 conformance、superclass 或 layout requirement。
- 任意的 associated requirement 都可以在 trailing `where` 子句里陈述，这些 `where` 子句挂在 protocol 上或它的任一 associated type 上，任意组合皆可。

一个 protocol 的 associated requirement 被收集进它的 requirement signature，我们会看到这个东西在某种意义上与 generic signature 对偶（见 `generic-signatures.tex` 的 Requirement Signatures 一节）。具体类型如何满足 requirement signature，将在 `conformances.tex` 里讨论。

> 译注：本章说的「protocol 的 value requirement 与 associated requirement」，落到二进制里就是 protocol descriptor 后面跟的那张 requirement 表。系统框架的 protocol 通常被 strip 掉符号，本库因此把这些槽位按位置投影成 `pwtslot:<offset>` 记录（保留 kind、isInstance、isAsync、hasDefaultImplementation 这几个 flag），使得在零符号的情况下仍能看出 protocol witness table 形状的变化；做法与它的局限见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

### Self requirements

Protocol 的 method 或 subscript requirement 的 `where` 子句不能约束 `Self` 或它的 associated type。例如下面这个 protocol 会被拒绝，因为对于一个 `Element` 类型**不**是 `Comparable` 的具体 conforming type 来说，根本没法实现 `minElement()` 这条 requirement：

```swift
protocol SetProtocol {
  associatedtype Element  // we want `where Element: Comparable' here
  func minElement() -> Element where Element: Comparable  // error
}
```

### History

较早的 Swift 版本允许 protocol 和 associated type 在 inheritance clause 里陈述 constraint type，但那时还不存在更一般的 associated requirement。Associated requirement 是在 Swift 4 把 trailing `where` 子句语法推广到 associated type 和 protocol 之后才有的（SE-0142）。

## Functions

一条 function declaration 可以出现在源文件的顶层、作为 nominal type 或 extension 的成员（这种我们叫 method declaration），或者作为嵌在另一个函数内部的 **local function**。本节先描述 function declaration 的 interface type 怎么算出来，最后讨论闭包表达式和 local function 如何 capture 值。

**Interface type request** 计算 function declaration 的 interface type。它是一个 function type 或 generic function type，由该函数各个 parameter declaration 的 interface type、它的返回类型以及它的 generic signature（如果有）构造而成。没有写返回类型时，返回类型就是空的 tuple type `()`：

```swift
func f(x: Int, y: String) -> Bool {...}
// Interface type: (Int, String) -> Bool

func g() {...}
// Interface type: () -> ()
```

### Method declarations

除了参数列表里声明的形式参数之外，一条 method declaration 还有一个 implicit 的 `self` parameter，用来接收 member reference expression 里 `.` 左边的那个值。Method declaration 的 interface type 是这样一个 function type：它接收 `self` parameter，返回另一个函数，后者再接收该 method 的形式参数。function type 的 `->` 语法是右结合的，所以 `A -> B -> C` 意思是 `A -> (B -> C)`：

```swift
struct Universe {
  func wormhole(x: Int, y: String) -> Bool {...}
  // Interface type: (Universe) -> (Int, String) -> Bool

  static func bigBang() {}
  // Interface type: (Universe.Type) -> () -> ()

  mutating func teleport() {}
  // Interface type: (inout Universe) -> () -> ()
}
```

`self` parameter 的 interface type 和 ownership specifier 按下面的方式导出：

- 先取该 method 的 parent declaration context 的 **self interface type**。在 struct、enum 或 class 里，它与 declared interface type 相同。在 protocol 里，它是 protocol 的 `Self` type（见本章 Protocols 一节）。在 extension 里，self interface type 就是被扩展类型的 self interface type。
- 如果这个 method 声明在 class 内部，并且它返回 dynamic `Self` type，我们就把 `self` 的类型包进 dynamic `Self` type 里（见 `types.tex` 的 Special Types 一节）。
- 如果这个 method 是 `static` 的，我们再把 `self` 的类型包进一个 metatype 里。
- 如果这个 method 是 `mutating` 的，我们就以 `inout` 方式传递 `self` parameter。

**图（方法调用 `universe.wormhole(x: 1, y: "hi")`）.**

```
  call: universe.wormhole(x: 1, y: "hi")
   |
   +-- self call: universe.wormhole
   |    |
   |    +-- callee: Universe.wormhole
   |    +-- declaration reference: universe
   |
   +-- argument list: (x: 1, y: "hi")
        |
        +-- literal: 1
        +-- literal: "hi"
```

> 译注：原书此处是一张 TikZ 语法树图，这里用 ASCII 树转述；图的原貌见官方 PDF 对应章节。

我们来把 method declaration 的 interface type 和抽象语法树里 method 调用表达式的结构对照一下（就是上面那张图）：

- 外层表达式的 callee 是 `universe.wormhole`，它本身又是一个 call expression，所以我们必须先求值这个内层 call expression。

  内层 call expression 把实参 `universe` 应用到 `Universe.wormhole()` 的 `self` parameter 上。这代表了 method lookup。内层 call expression 的返回类型是 `(Int, String) -> Bool`。
- 外层 call expression 把实参列表 `(x: 1, y: "hi")` 应用到内层 call expression 的结果上。这代表 method 调用本身，返回类型是 `Bool`。

这次多出来的函数调用会在 SILGen 里消失：在那里我们把 method 下降为一个 SIL 函数，它一次性接收所有形式参数和 `self` parameter。

一次 partially-applied method reference，比如 `universe.wormhole`，也可以当作类型为 `(Int, String) -> Bool` 的值来使用。它绑定了 `self` parameter，但并不调用该 method。我们的处理办法是把这次 method reference 包进一个闭包里，由闭包去调用该 method；这个闭包与 method reference 类型相同。用 lambda calculus 的术语说，这就是所谓的 **η-expansion**：

```swift
{ x, y in universe.wormhole(x: x, y: y) }
```

而 unapplied 的形式 `Universe.wormhole` 则脱糖成一个「返回闭包的闭包」：

```swift
{ mySelf in { x y in mySelf.wormhole(x: x, y: y) } }
```

这种脱糖简化了 SILGen，因为我们只需要为「一次性传入所有形式参数和 `self` 的 fully-applied method 调用」实现下降逻辑。

除 protocol requirement 之外，源语言里所有 function declaration 后面都必须跟一个函数体。函数体里可以包含语句、表达式和其它声明。（与 type 和 declaration 不同，本书不会穷举所有的语句和表达式。）下面这个例子展示了几种 call expression：

```swift
struct Example {
  func instanceMethod() {}
  static func staticMethod() {}

  struct Lookup {
    func innerMethod() {}

    func test() {
      instanceMethod()  // bad
      staticMethod()    // ok
      innerMethod()     // ok
    }
  }

  func anotherMethod(x: Int) {
    struct Local {
      func test() {
        print(x)        // bad
      }
    }
  }
}
```

在 method 体内，对最内层 nominal type declaration 某个成员的 unqualified 引用，会被解释为带有隐含的 `self.` 限定。因此 instance method 可以这样引用别的 instance method，static method 可以这样引用别的 static method。

对外层 nominal type 某个成员的 unqualified 引用，只有当该成员是 static 的时候才成立，因为这里没有一个「外层的 `self` parameter」可以用来调用这个 method；嵌套类型的一个**值**并不包含其 parent 类型的**值**。

出于同样的原因，local type 内部的 method 不能引用声明在该 local type 之外的局部变量。（可以与 Java 的 inner class 对比：Java 的 inner class 可以声明为外层 class 的 `static` 成员或 instance 成员，而非 `static` 的 inner class 会从外层 class capture 一个 `this` 引用。嵌在方法里的 inner class 在 Java 里还能 capture 局部变量。）

> 译注：本章这里给出的「method 的 interface type 里 `self` 怎么出现、`static` 怎么包成 metatype」，是本库判断一个成员该打印成 `static` 还是 `class`、该不该加 `final` 的语义前提。Mangling 不区分 `static` 与 `class` 两种拼写，本库转而用「这个成员有没有 vtable method descriptor」这条 ABI 事实来还原关键字：见 [ClassMemberKeywordRecovery.md](../ClassMemberKeywordRecovery.md)（`class` 对 `static`）与 [FinalKeywordAndLazyAccessorTypeRecovery.md](../FinalKeywordAndLazyAccessorTypeRecovery.md)（`final` 的还原及其四重门槛）。

### Constructor declarations

Constructor declaration 用 `init` 关键字引入。Constructor 的 parent context 必须是 nominal type 或 extension。

从外面看，constructor 的 interface type 像一个返回该类型新实例的 static method；但在 constructor 内部，`self` 是正在被初始化的那个实例，所以 `self` 的 interface type 是该 nominal type 而不是它的 metatype。在 struct 或 enum 里，`self` 还是 `inout` 的。Constructor 可以用多种方式 delegate 到别的 constructor。为了用 call expression 来建模这种 delegation，**initializer interface type** 描述的是「在调用方提供的位置上做一次原地初始化」的类型：

```swift
struct Universe {
  init(age: Int) {...}
  // Interface type: (Universe.Type) -> (Int) -> Universe
  // Initializer interface type: (inout Universe) -> (Int) -> Universe
}
```

### Destructor declarations

用 `deinit` 关键字引入，只在 class 内部合法。Destructor 不能有 generic parameter list 或 `where` 子句。它的 interface type 就是一个没有形式参数、返回类型为 `()` 的 method 的类型。

### Local contexts

**Local context** 指任何不是 module、源文件、type declaration 或 extension 的 declaration context。Swift 允许变量、函数和类型声明出现在 local context 里。下面这些都是 local context：

- top-level code declaration。
- function declaration。
- closure expression。
- 如果一个变量本身不在 local context 里（例如它是某个 nominal type declaration 的成员），那么它的初值表达式定义一个新的 local context。
- subscript declaration 和 enum element declaration 是 local context，因为它们可以包含 parameter declaration（subscript declaration 还可以带 generic parameter list）。

Local function 和闭包可以 **capture** 外层作用域里其它 local declaration 的引用。我们用标准的 **closure conversion** 技术，把带 captured value 的函数下降成不带 captured value 的函数。这个过程可以理解为：给每个 captured value 引入一个额外的参数，然后遍历函数体，把对这些 captured value 的引用替换成对相应参数的引用。在 Swift 里，这是 SILGen 下降过程的一部分，而不是抽象语法树上一次单独的变换。

**Capture info request** 计算给定函数（以及它所有嵌套的 local function 和闭包表达式）所 capture 的值的列表。

考虑下面这三个嵌套函数，我们从内往外计算它们的 capture：

```swift
func f() {
  let x = 0, y = 0

  func g() {
    var z = 0
    print(x)

    func h() {
      print(y, z)
    }
  }
}
```

最内层的 `h()` capture 了 `y` 和 `z`。中间的 `g()` capture 了 `x`。它也 capture 了 `y`，因为 `h()` capture 了 `y`；但它没有 capture `z`，因为 `z` 是 `g()` 自己声明的。最后，`f()` 声明在顶层，所以它没有任何 capture。

可以总结成下表（集合记号的汇总见 `math-summary.tex`（中译 [SwiftGenericsMathSummary.md](SwiftGenericsMathSummary.md)））：

| **Function** | **Captures** |
|---|---|
| `f()` | `∅` |
| `g()` | `{x, y}` |
| `h()` | `{y, z}` |

**算法（Compute closure captures）.** 输入是一个闭包表达式或 local function `F` 的、已完成类型检查的函数体。输出是 `F` 的 capture 集合。

1. 把返回值初始化为空集，`C ← ∅`。
2. 递归遍历 `F` 已类型检查的函数体，处理其中每个元素：
3. （Declaration reference）如果 `F` 里有一个表达式按名字引用了某个局部变量或 local function `d`，令 `PARENT(d)` 表示包含 `d` 的那个 declaration context。它要么是 `F` 自己，要么是某个外层 local context——因为我们是从 `F` 出发用 unqualified lookup 找到 `d` 的。

   如果 `PARENT(d) ≠ F`，就置 `C ← C ∪ {d}`。
4. （Nested closure）如果 `F` 里有一个嵌套的闭包表达式或 local function `F′`，那么 `F′` 的所有不是由 `F` 声明的 capture，也都是 `F` 的 capture。

   递归计算 `F′` 的 capture。对 `F′` capture 的每一个满足 `PARENT(d) ≠ F` 的 `d`，置 `C ← C ∪ {d}`。
5. （Local type）如果 `F` 里有一个 local type，不要走进这个 local type 的子节点。Local type 不 capture 值；这一点我们在下一步里强制。
6. （Diagnose）递归遍历结束后，考察每个元素 `d ∈ C`。如果从 `F` 到 `d` 的 parent declaration context 路径上有一个 nominal type declaration，说明存在一次不被支持的「local type 内部的 capture」。报一个错误。
7. 返回 `C`。

Local function 之间还可以互相递归引用。看下面这几个函数，注意 `f()` 和 `g()` 是互相递归的：

```swift
func f() {
  let x = 0, y = 0, z = 0

  func g() { print(x); h() }
  func h() { print(y); g() }
  func i() { print(z); h() }
}
```

> 译注：原文这句写的是 `f()` 与 `g()`，但按代码，互相递归的其实是 `g()` 与 `h()`；译文照原文保留，这里只作提示。

在运行时，我们无法用「两个 closure context 各自持有对方」的方式来表示这种关系，因为那样两个 context 谁都不会被释放。

我们用第二个算法来得到 **lowered capture** 列表：把任何被 capture 的 local function 替换成它自己的 capture 列表，反复这样做直到不动点。最终列表里只剩变量声明。在上面这个例子里，各函数的 capture 与 lowered capture 如下：

| **Function** | **Captures** | **Lowered** |
|---|---|---|
| `f()` | `∅` | `∅` |
| `g()` | `{x, h()}` | `{x, y}` |
| `h()` | `{y, g()}` | `{x, y}` |
| `i()` | `{z, h()}` | `{x, y, z}` |

（有一个特殊情形：如果一组 local function 互相引用，但并不从外层 declaration context capture 任何别的状态，那它们的 lowered capture 会是空的，于是运行时无需分配任何 context。）

**算法（Compute lowered closure captures）.** 输入是一个闭包表达式或 local function `F` 的、已完成类型检查的函数体。输出是 `F` 传递地 capture 的变量声明集合。

1. 初始化集合 `C ← ∅`，它就是返回值。初始化一个空 worklist。初始化一个空的 visited 集合。把 `F` 加入 worklist。
2. 如果 worklist 空了，返回 `C`。否则从 worklist 里取出下一个函数 `F`。
3. 如果 `F` 在 visited 集合里，回到第 2 步。否则把 `F` 加入 visited 集合。
4. 用 Compute closure captures 算法计算 `F` 的 capture，考察每一个 capture `d`。如果 `d` 是一个局部变量声明，置 `C ← C ∪ {d}`。如果 `d` 是一个 local function declaration，把 `d` 加入 worklist。
5. 回到第 2 步。

以上把 `let` 变量的 capture 完全解释清楚了，但可变的 `var` 变量和 `inout` 参数还需要更多说明。

一个 **non-escaping** 闭包可以仅通过 capture 存储位置的内存地址来 capture 一个 `var` 或 `inout`。这是安全的，因为 non-escaping 闭包的寿命不可能超过该存储位置的动态存活期。

一个 `@escaping` 闭包同样可以 capture 一个 `var`，但这需要把这个 `var` 提升为一个带引用计数、堆上分配的 box，所有对该变量的访问都通过这个 box 间接进行。下面这个例子在每本 Lisp 教材里都能见到。每次调用 `counter()` 都在堆上分配一个新的计数值，并返回三个引用该 box 的闭包；box 本身被抽象完全隐藏起来：

```swift
func counter() -> (read: () -> Int, inc: () -> (), dec: () -> ()) {
  var count = 0  // promoted to a box
  return ({ count }, { count += 1 }, { count -= 1 })
}
```

在 Swift 3 之前，`@escaping` 闭包也被允许 capture `inout` 参数。为了让这件事安全，`inout` 参数的内容会先被复制进一个堆上分配的 box，闭包 capture 的是这个 box。然后在函数返回给调用方之前，box 的内容再被复制回去。这基本上等价于做下面这个变换，其中我们引入了 `_n`：

```swift
func changeValue(_ n: inout Int) {
  var _n = n  // copy the value

  let escapingFn = {
    _n += 1   // capture the box
  }

  n = _n      // write it back
}
```

在这个方案下，如果闭包的寿命超过了 `inout` 参数的动态存活期，那么此后闭包内部的写入就被悄悄丢弃了。这是用户困惑的来源，所以 Swift 3 索性禁止了 escaping 闭包 capture `inout`（SE-0035）。

在 SILGen 里，captured value 会在函数参数列表的末尾引入新的参数，而一个闭包值是通过对一个带 capture 的函数做**偏应用**（partial application）得到的。这产生一个具有所需类型的新函数值，于是那些 captured value 就被「切掉」了。在 IRGen 里，我们把一次偏应用下降为：先分配存放 capture 的空间（non-escaping function type 分配在栈上，`@escaping` 则在堆上），然后发射一个 thunk，它接收一个指向 context 的指针作为参数，从 context 里解出 captured value，再把它们作为独立的实参传给原函数。这个 thunk 连同 context 构成一个 **thick function** 值，代表这个闭包。

如果什么都没 capture（或者所有 captured value 的大小都是零字节），我们可以传一个空指针作为 context，不必做堆分配。如果恰好只有一个 captured value 并且它能表示为一个 reference-counted 指针，我们同样可以省掉这次分配，改为直接把这个 captured value 当作 context 指针传递。例如，如果一个闭包唯一的 capture 是某个 class type 的实例，那就什么都不用分配。如果唯一的 capture 是包着某个 `var` 的那个堆上 box，我们仍然必须为这个 `var` 分配 box，但省掉了第二次 context 分配。

## Storage

Storage declaration 表示可读可写的位置。

### Parameter declarations

函数、enum element 和 subscript 都可以带参数列表；每个参数由一条 parameter declaration 表示。Parameter declaration 是变量声明的一种。

### Variable declarations

不是参数的变量用 `var` 和 `let` 引入。一个变量要么是 **stored** 的，要么是 **computed** 的；computed 变量的行为由它的 **accessor declaration** 决定。变量的 **value interface type** 是它的值的类型。变量的 interface type 则是：取它的值的类型，如果该变量声明为 `weak` 或 `unowned`，再把它包进一个 reference storage type 里。

变量声明总是与一条 **pattern binding declaration** 一起创建，后者表示 Swift 里变量可以绑定到值的各种方式。一条 pattern binding declaration 由一到多个 **pattern binding entry** 构成。每个 pattern binding entry 有一个 **pattern** 和一个可选的 **initial value expression**。一个 pattern 声明零个或多个变量。

下面这条 pattern binding declaration 只有一个 entry，而且它不声明任何变量：

```swift
let _ = ignored()
```

下面这条 pattern binding declaration 只有一个 entry，其 pattern 声明了一个变量：

```swift
let x = 123
```

我们可以写更复杂的 pattern，例如绑定一个 tuple 的第一个元素而丢弃第二个：

```swift
let (x, _) = (123, "hello")
```

下面这条 pattern binding declaration 只有一个 entry，其 pattern 声明了两个变量 `x` 和 `y`：

```swift
let (x, y) = (123, "hello")
```

下面这条 pattern binding declaration 有两个 entry，分别声明 `x` 和 `y`：

```swift
let x = 123, y = "hello"
```

最后，这里是两条 pattern binding declaration，每条各有一个 entry，各声明一个变量：

```swift
let x = 123
let y = "hello"
```

当一条 pattern binding declaration 出现在 local context 之外时，它的每个 entry 都必须至少声明一个变量，所以下面两段都会被拒绝：

```swift
let _ = 123

struct S {
  let _ = "hello"
}
```

Pattern 文法有一个古怪之处：typed pattern 和 tuple pattern 的组合方式并不像人们想的那样。如果 `let x: Int` 是一个 typed pattern，声明一个带类型标注 `Int` 的变量 `x`，而 `let (x, y)` 是一个 tuple pattern，声明两个变量 `x` 和 `y`，我们大概会以为 `let (x: Int, y: String)` 声明的是两个分别带类型标注 `Int` 和 `String` 的变量 `x` 和 `y`；实际发生的却是：我们得到一个 tuple pattern，它声明了两个**名叫** `Int` 和 `String` 的变量，绑定的是一个带**标签** `x` 和 `y` 的二元 tuple：

```swift
let (x: Int, y: String) = (x: 123, y: "hello")
print(Int)  // huh? prints 123
print(String)  // weird! prints "hello"
```

### Subscript declarations

Subscript 用 `subscript` 关键字引入。它们只能作为 nominal type 和 extension 的成员出现。Subscript 的 interface type 是一个接收 index 参数、返回 storage type 的 function type。Subscript 的 value interface type 就是这个 storage type。出于历史原因，subscript 的 interface type 里**不**包含 method declaration 那样的 `Self` 子句。Subscript 可以是 instance 成员也可以是 static 成员；static subscript 在 Swift 5.1 引入（SE-0254）。

### Accessor declarations

每条 storage declaration 都有一组 **accessor declaration**，它们是一种特殊的 function declaration。在 declaration context 的层级里，accessor declaration 是 storage declaration 的兄弟节点。Accessor 的 interface type 取决于 accessor 的种类。例如 getter 返回值，setter 则把新值作为参数接收。变量的 accessor 不接收任何其它参数；subscript 的 accessor 还会接收 subscript 的 index 参数。本书不再需要关于 accessor 和 storage declaration 的更多细节。

> 译注：这组 accessor declaration 在二进制里表现为一族独立的符号（`g`/`s`/`m` 等后缀），本库的 `DefinitionBuilder` 要把它们按所属成员重新分组，才能还原出「一个 computed property」而不是散落的若干函数；stored `var` 的 accessor 组一度在按字段名去重时被丢弃，以及 lazy 字段应当打印调用方可见的 getter 类型而非 `Optional` 存储类型这两件事，见 [FinalKeywordAndLazyAccessorTypeRecovery.md](../FinalKeywordAndLazyAccessorTypeRecovery.md)。

## Source Code Reference

关键源文件：

- `include/swift/AST/Decl.h`
- `include/swift/AST/DeclContext.h`
- `lib/AST/Decl.cpp`
- `lib/AST/DeclContext.cpp`

其它源文件：

- `include/swift/AST/DeclNodes.def`
- `include/swift/AST/ASTVisitor.h`
- `include/swift/AST/ASTWalker.h`

**`Decl`**（class）：声明的基类。下面这张图列出了它的各个子类，它们对应本章前面描述过的各种声明种类。

**图（`Decl` 类层级）.**

```
Decl
 +-- ValueDecl
 |    +-- TypeDecl
 |    |    +-- NominalTypeDecl
 |    |    |    +-- StructDecl
 |    |    |    +-- EnumDecl
 |    |    |    +-- ClassDecl
 |    |    |    +-- ProtocolDecl
 |    |    +-- TypeAliasDecl
 |    |    +-- AbstractTypeParamDecl
 |    |         +-- GenericTypeParamDecl
 |    |         +-- AssociatedTypeDecl
 |    +-- AbstractFunctionDecl
 |    |    +-- FuncDecl
 |    |    |    +-- AccessorDecl
 |    |    +-- ConstructorDecl
 |    |    +-- DestructorDecl
 |    +-- AbstractStorageDecl
 |         +-- VarDecl
 |         |    +-- ParamDecl
 |         +-- SubscriptDecl
 +-- ExtensionDecl
```

> 译注：原书此处是一张 TikZ 类层级图，这里用 ASCII 树转述；图的原貌见官方 PDF 对应章节。

这些实例永远分配在 `ASTContext` 的永久 arena 里，要么在声明被解析时分配，要么在被合成时分配。顶层的 `isa<>`、`cast<>` 和 `dyn_cast<>` 模板函数支持从 `Decl *` 动态转换到它的任一子类。

- `getDeclContext()` 返回这个声明的 parent `DeclContext`。
- `getInnermostDeclContext()`：如果这个声明本身也是一个 declaration context，就把它当作 `DeclContext` 返回；否则返回 parent `DeclContext`。
- `getASTContext()` 从一个声明取得那个单例 AST context。

### Visitors

要穷举处理每一种声明，最简单的办法是对 kind 做 switch，kind 是 `DeclKind` 枚举的一个实例：

```cpp
Decl *decl = ...;
switch (decl->getKind()) {
case DeclKind::Struct: {
  auto *structDecl = decl->castTo<StructDecl>();
  ...
}
case DeclKind::Enum:
  ...
case DeclKind::Class:
  ...
}
```

不过，和处理 type 时一样，用 visitor 模式往往更方便：继承 `ASTVisitor` 并重写各个 `visit<Kind>Decl()` 方法。Visitor 的 `visit()` 方法会代你完成上面那套 switch 加动态转换的操作，并调用相应的方法：

```cpp
class MyVisitor: public ASTVisitor<MyVisitor> {
public:
  void visitStructDecl(StructType *decl) {
    ...
  }
};

MyVisitor visitor;

Decl *decl = ...;
visitor.visit(decl);
```

`ASTVisitor` 还为 `Decl` 层级里那些抽象基类定义了相应的方法，例如重写 `visitNominalTypeDecl()` 就能一次性处理所有 nominal type declaration。`ASTVisitor` 的适用面不止于访问声明；它同样支持访问语句、表达式和 type representation。

`ASTWalker` 实现了一种更复杂的形式。Visitor 访问的是单个声明，而 walker 会以前序遍历的方式走遍嵌套的声明、语句和表达式。

**`ValueDecl`**（class）：具名声明的基类。

- `getDeclName()` 返回该声明的名字。
- `getInterfaceType()` 返回该声明的 interface type。

### Type Declarations

**`TypeDecl`**（class）：type declaration 的基类。

- `getDeclaredInterfaceType()` 返回这个声明的一个实例的类型。

**`NominalTypeDecl`**（class）：nominal type declaration 的基类。同时也是一个 `DeclContext`。

- `getSelfInterfaceType()` 返回这条 nominal type declaration 的 self interface type（见本章 Functions 一节）。它与 declared interface type 相同，除非这是一条 protocol declaration：protocol 的 declared interface type 是一个 nominal type，而它的 self interface type 是 generic parameter `Self`。
- `getDeclaredType()` 返回这个声明的一个实例的类型，不带 generic argument。如果该声明是 generic 的，这是一个 unbound generic type。如果该声明不是 generic 的，它与 declared interface type 相同。在 generic parameter type 无关紧要时，诊断信息里偶尔会用它来代替 declared interface type。

**`TypeAliasDecl`**（class）：一条 type alias declaration。同时也是一个 `DeclContext`。

- `getDeclaredInterfaceType()` 返回该 type alias declaration 的 underlying type，外面包着 type alias type 的糖。
- `getUnderlyingType()` 返回该 type alias declaration 的 underlying type，不包 type alias type 的糖。

### Declaration Contexts

**`DeclContext`**（class）：declaration context 的基类。另见 `generic-signatures.tex` 的 Source Code Reference 一节。

顶层的 `isa<>`、`cast<>` 和 `dyn_cast<>` 模板函数同样支持从 `DeclContext *` 动态转换到它的任一子类。

有少数几个子类并不同时是 `Decl *` 的子类：

- `ClosureExpr`。
- `FileUnit` 及其各个子类，比如 `SourceFile`。
- 源码里还有另外几个不那么有意思的。

用来理解 declaration context 嵌套关系的方法：

- `getAsDecl()`：如果这个 declaration context 同时也是一条声明，就返回该声明，否则返回 `nullptr`。
- `getParent()` 返回 parent declaration context。
- `isModuleScopeContext()`：这是不是一个 `ModuleDecl` 或 `FileUnit`。
- `isTypeContext()`：这是不是一条 nominal type declaration 或一个 extension。
- `isLocalContext()`：这是不是「既不是 module scope context 也不是 type context」。
- `getParentModule()` 返回层级树根部的 module declaration。
- `getModuleScopeContext()` 返回最内层的、是 `ModuleDecl` 或 `FileUnit` 的那个 parent。
- `getParentSourceFile()` 返回最内层的、是源文件的那个 parent；如果这个 declaration context 不是从源码解析来的，返回 `nullptr`。
- `getInnermostDeclarationDeclContext()` 返回最内层的、同时也是一条声明的那个 parent，没有则返回 `nullptr`。
- `getInnermostDeclarationTypeContext()` 返回最内层的、同时也是 nominal type 或 extension 的那个 parent，没有则返回 `nullptr`。

作用在 type context 上的操作：

- `getSelfNominalDecl()`：如果这是一个 type context，返回其 nominal type declaration，否则返回 `nullptr`。
- `getSelfStructDecl()`：同上，但结果是 `StructDecl *` 或 `nullptr`。
- `getSelfEnumDecl()`：同上，但结果是 `EnumDecl *` 或 `nullptr`。
- `getSelfClassDecl()`：同上，但结果是 `ClassDecl *` 或 `nullptr`。
- `getSelfProtocolDecl()`：同上，但结果是 `ProtocolDecl *` 或 `nullptr`。
- `getDeclaredInterfaceType()` 视情况委派给 `NominalTypeDecl` 或 `ExtensionDecl` 上的同名方法。
- `getSelfInterfaceType()` 与之类似。

Generic parameter 与 requirement：

- `isGenericContext()`：这个 generic context 自己或它的某个 parent 是否带有 generic parameter list。
- `isInnermostContextGeneric()`：这个 declaration context **自身**是否带有 generic parameter list。与 `isGenericContext()` 对照着看。

### Generic Contexts

关键源文件：

- `include/swift/AST/GenericParamList.h`
- `include/swift/AST/Requirement.h`
- `lib/AST/GenericParamList.cpp`
- `lib/AST/NameLookup.cpp`
- `lib/AST/Requirement.cpp`

**`GenericContext`**（class）：`DeclContext` 的子类。可以带 generic parameter list 的那些声明种类的基类。另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `getParsedGenericParams()` 返回该声明的 parsed generic parameter list，没有则返回 `nullptr`。
- `getGenericParams()` 返回该声明完整的 generic parameter list，其中包含所有 implicit generic parameter。会求值一次 `GenericParamListRequest`。
- `hasGenericParamList()`：这个声明是否带有 generic parameter list。这等价于在 `DeclContext` 上调用 `isInnermostContextGeneric()`。与 `DeclContext::isGenericContext()` 对照着看。
- `getGenericContextDepth()` 返回该声明的 generic parameter list 的 depth；如果这个声明和它的任何外层声明都不是 generic 的，返回 `(unsigned)-1`。
- `getTrailingWhereClause()` 返回该声明的 trailing `where` 子句，没有则返回 `nullptr`。

序列化后的 generic context 里不保留 trailing `where` 子句。除了真的在构建 generic signature 的时候，大多数代码应当改看 `GenericContext::getGenericSignature()`（见 `generic-signatures.tex` 的 Source Code Reference 一节）。

**`GenericParamList`**（class）：一个 generic parameter list。

- `getParams()` 返回一个 generic parameter declaration 数组。
- `getOuterParameters()` 返回外层的 generic parameter list，把同一个 generic context 的多个 generic parameter list 串起来。只在嵌套 generic 类型的 extension 里用到。

**`GenericParamListRequest`**（class）：这个 request 为一个声明创建完整的 generic parameter list。由 `GenericContext::getGenericParams()` 发起。

- 对 protocol，它创建那个 implicit 的 `Self` parameter。
- 对函数和 subscript，它调用 `createOpaqueParameterGenericParams()`，遍历形式参数列表寻找 `OpaqueTypeRepr`。
- 对 extension，它调用 `createExtensionGenericParams()`，克隆被扩展 nominal 自身以及它所有外层 generic context 的 generic parameter list，并通过 `GenericParamList::getOuterParameters()` 把它们串起来。

**`GenericTypeParamDecl`**（class）：一条 generic parameter declaration。

- `getDepth()` 返回这条 generic parameter declaration 的 depth。
- `getIndex()` 返回这条 generic parameter declaration 的 index。
- `getName()` 返回这条 generic parameter declaration 的名字。
- `getDeclaredInterfaceType()` 返回这条声明的 sugared generic parameter type，它打印出来就是该 generic parameter 的名字。
- `isOpaque()`：这个 generic parameter 是否与某个 opaque parameter 关联。
- `getOpaqueTypeRepr()`：如果这是一个 opaque parameter，返回与之关联的 `OpaqueReturnTypeRepr`，否则返回 `nullptr`。
- `getInherited()` 返回这条 generic parameter declaration 的 inheritance clause。

序列化后的 generic parameter declaration 里不保留 inheritance clause。陈述在 generic parameter declaration 上的 requirement 属于对应 generic context 的 generic signature 的一部分，所以除了真的在构建 generic signature 的时候，大多数代码都改用 `GenericContext::getGenericSignature()`（见 `generic-signatures.tex` 的 Source Code Reference 一节）。

**`GenericTypeParamType`**（class）：一个 generic parameter type。

- `getDepth()` 返回这条 generic parameter declaration 的 depth。
- `getIndex()` 返回这条 generic parameter declaration 的 index。
- `getName()`：如果这是 sugared 形式，返回这条 generic parameter declaration 的名字，否则返回一个形如 `τ_d_i` 的字符串。

**`TrailingWhereClause`**（class）：trailing `where` 子句的语法表示。

- `getRequirements()` 返回一个 `RequirementRepr` 数组。

**`RequirementRepr`**（class）：trailing `where` 子句里一条 requirement 的语法表示。

- `getKind()` 返回一个 `RequirementReprKind`。
- `getFirstTypeRepr()` 返回一条 same-type requirement 的第一个 `TypeRepr`。
- `getSecondTypeRepr()` 返回一条 same-type requirement 的第二个 `TypeRepr`。
- `getSubjectTypeRepr()` 返回一条 constraint 或 layout requirement 的第一个 `TypeRepr`。
- `getConstraintTypeRepr()` 返回一条 constraint requirement 的第二个 `TypeRepr`。
- `getLayoutConstraint()` 返回一条 layout requirement 的 layout constraint。

**`RequirementReprKind`**（enum class）：`RequirementRepr::getKind()` 的返回类型。

- `RequirementRepr::TypeConstraint`
- `RequirementRepr::SameType`
- `RequirementRepr::LayoutConstraint`

**`WhereClauseOwner`**（class）：表示对某一组 requirement representation 的引用，这组表示可以被 resolve 成 requirement，例如一个 trailing `where` 子句。它被多个 request 使用，比如下面的 `RequirementRequest`，以及 `building-generic-signatures.tex` 的 Source Code Reference 一节里的 `InferredGenericSignatureRequest`。

- `getRequirements()` 返回一个 `RequirementRepr` 数组。
- `visitRequirements()` 逐条 resolve requirement representation，并用 `RequirementRepr` 和 resolve 出来的 `Requirement` 调用一个回调。

**`RequirementRequest`**（class）：这个 request 求值后可以 resolve 一个 `WhereClauseOwner` 里的单条 requirement representation。由 `WhereClauseOwner::visitRequirements()` 使用。

**`ProtocolDecl`**（class）：一条 protocol declaration。

- `getTrailingWhereClause()` 返回这个 protocol 的 `where` 子句，没有则返回 `nullptr`。
- `getAssociatedTypes()` 返回这个 protocol 里所有 associated type declaration 的数组。
- `getPrimaryAssociatedTypes()` 返回这个 protocol 里所有 primary associated type declaration 的数组。
- `getInherited()` 返回这个 protocol 的 inheritance clause。

序列化后的 protocol declaration 里不保留 trailing `where` 子句和 inheritance clause。除了真的在构建 requirement signature 的时候，大多数代码都改用 `ProtocolDecl::getRequirementSignature()`（见 `generic-signatures.tex` 的 Source Code Reference 一节）。

最后三个工具方法作用在 requirement signature 上，所以对反序列化得到的 protocol 也可以安全使用：

- `getInheritedProtocols()` 返回这个 protocol 直接 inherit 的所有 protocol 的数组，由 inheritance clause 算出。
- `inheritsFrom()` 判断这个 protocol 是否（可能是传递地）inherit 自给定的 protocol。
- `getSuperclassDecl()` 返回这个 protocol 的 superclass 声明。

**`AssociatedTypeDecl`**（class）：一条 associated type declaration。

- `getTrailingWhereClause()` 返回这个 associated type 的 trailing `where` 子句，没有则返回 `nullptr`。
- `getInherited()` 返回这个 associated type 的 inheritance clause。

序列化后的 associated type declaration 里不保留 trailing `where` 子句和 inheritance clause。作用在 associated type 上的 requirement 属于 protocol 的 requirement signature 的一部分，所以除了真的在构建 requirement signature 的时候，大多数代码都改用 `ProtocolDecl::getRequirementSignature()`（见 `generic-signatures.tex` 的 Source Code Reference 一节）。

### Function Declarations

**`AbstractFunctionDecl`**（class）：函数类声明的基类。同时也是一个 `DeclContext`。

- `getImplicitSelfDecl()`：如果这是一个 method，返回那个 implicit 的 `self` parameter，否则返回 `nullptr`。
- `getParameters()` 返回这个函数的参数列表。
- `getMethodInterfaceType()` 返回一个 method 去掉 `Self` 子句之后的类型。
- `getResultInterfaceType()` 返回这个函数或 method 的返回类型。

**`ParameterList`**（class）：`AbstractFunctionDecl`、`EnumElementDecl` 或 `SubscriptDecl` 的参数列表。

- `size()` 返回参数个数。
- `get()` 返回给定 index 处的 `ParamDecl`。

**`ConstructorDecl`**（class）：一条 constructor declaration。

- `getInitializerInterfaceType()` 返回 initializer interface type，在对 `super.init()` delegation 做类型检查时用到。

### Closure Conversion

关键源文件：

- `include/swift/AST/CaptureInfo.h`
- `include/swift/SIL/TypeLowering.h`
- `lib/AST/CaptureInfo.cpp`
- `lib/Sema/TypeCheckCaptures.cpp`
- `lib/SIL/IR/TypeLowering.cpp`

**`CaptureInfo`**（class）：一个不可变的 captured value 列表。

**`CaptureInfoRequest::evaluate`**（method）：计算 `CaptureInfo`。这就是 Compute closure captures 算法。

**`TypeConverter::getLoweredLocalCaptures()`**（method）：计算 lowered `CaptureInfo`。这就是 Compute lowered closure captures 算法。关于 SIL type lowering 与 `TypeConverter` 的讨论，见 `substitution-maps.tex` 的 SIL Type Lowering 一节和 Source Code Reference 一节。

### Storage Declarations

**`AbstractStorageDecl`**（class）：storage declaration 的基类。

- `getValueInterfaceType()` 返回被存储的值的类型，不带 `weak` 或 `unowned` 这类存储限定符。

**`VarDecl`**（class）：`AbstractStorageDecl` 的子类。

**`SubscriptDecl`**（class）：`AbstractStorageDecl` 和 `DeclContext` 的子类。

**`AccessorDecl`**（class）：`AbstractFunctionDecl` 的子类。

---

> 译自 `docs/Generics/chapters/declarations.tex`（swift-6.4.0-RELEASE，`8992ea82a23`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
