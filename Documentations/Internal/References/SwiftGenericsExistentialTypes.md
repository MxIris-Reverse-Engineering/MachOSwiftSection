# Existential Types（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/existential-types.tex`（《Compiling Swift Generics》一书的「Existential Types」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章讲 `any P` 这类 existential type——constraint type 怎么写、`ExistentialType` 怎么把它包起来、opened existential signature 与 existential archetype 是什么，以及一个 existential 值在运行期占哪几个字。最后这件事正是本库 `ExistentialLayoutBridge` 离线重算字段偏移时要复刻的规则（opaque `32 + 8N`、class-bound `8·(1+N)`、`any Error` 一个字），所以本章 Runtime Representation 一节与 [StaticLayoutEngine.md](../StaticLayoutEngine.md) 是逐条对应的。
>
> **重要提醒——本章在原书里尚未定稿**：`docs/Generics/README.md` 把「Existential Types」列在 "The following chapters are not yet written" 名下。正文的绝大部分包在 `\ifWIP` 条件块里，而 `generics.tex` 把 `\ifWIP` 定义成 `\iffalse`，所以**官方 PDF 根本不输出这些内容**——它们是作者的草稿，里面还留着 TODO、只写了一句占位话的算法、以及个别没写完或前后对不上的句子。译文按项目规约照译以备参考，每个草稿块开头都有标注。**不要把本章当成已定稿的权威说法**；需要确定结论时以编译器源码和 Swift Evolution 提案为准。
>
> **术语**：书中定义的术语一律保留英文（existential type、constraint type、protocol composition、existential archetype、opened existential signature、generalization signature、self-conforming protocol、witness table、layout constraint、implicit opening……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Generic Signature Queries 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter |
> | `<τ_0_0 where τ_0_0: P>` | 一个 generic signature：尖括号里先列 generic parameter，`where` 之后是 requirement |
> | `τ_0_0.[P]X` | reduced type parameter；方括号里的 `[P]` 指明 associated type `X` 由 protocol `P` 声明 |
> | `[A: P]` | 类型 `A` 对 protocol `P` 的 conformance requirement / conformance |
> | `A ↦ B` | 一条 substitution：把 `A` 替换成 `B` |
> | `{…; …}` | substitution map。分号前是 replacement type 部分，分号后是 replacement conformance 部分 |
> | `T_1`、`T_1'`、`G_1`、`S_1` | 讨论 generalization 不变量时的下标写法：原 existential 类型、generalize 之后的 constraint type、generalization signature、generalization substitution map |
> | `N` | Existential generalization 算法里的计数器，即下一个可用的 generic parameter index |

---

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

constraint type 是 `AnyObject` 和 `Any` 的 existential type 也可以不写 `any` 关键字。

提一下（Barik、Sridharan、Ramanathan、Chabbi 2019，《Optimization of Swift Protocols》）。

每个 Swift 开发者都知道，protocol 在这门语言里身兼两职：既作 generic constraint，又作值的类型。后一种用法的正式名字就是 existential type，也是本章的主题。可以把一个 existential type 想成一个容器，里面装的是满足某些 requirement 的值。Existential type 是从 Objective-C 借来的，自 Swift 诞生之初就以 protocol type 和 protocol composition 的形式存在。

这个特性有一段有意思的历史。最初能当类型用的 protocol 仅限于那些没有 associated type、也没有把 `Self` 放在非 covariant 位置的 requirement 的 protocol（后一条就把 `Equatable` 排除在外了）。这意味着 existential type 的实现一开始和泛型那一套相当割裂。随着 existential type 逐渐能表达更复杂的约束，protocol 的这两副面孔才慢慢合流。

Protocol composition 最初写作 `protocol<P, Q>`，表示一个同时 conform to `P` 和 `Q` 的类型的值。现代写法 `P & Q` 是 Swift 3 引入的（SE-0095）。带 superclass 项的 protocol composition 是 Swift 4 引入的（SE-0156）。把 existential type 写成 `any P`、以便和作为 constraint type 的 `P` 区分开，是 Swift 5.6 引入的（SE-0335）。紧接着 Swift 5.7 允许所有 protocol 都用作 existential type（SE-0309），并引入了 existential type 的 implicit opening（SE-0352）和 constrained existential type（SE-0353）。

一个 existential type 写成 `any` 关键字后跟一个 constraint type，后者这个概念此前已在 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）的 Requirements 一节定义过。出于美观考虑，如果 constraint type 是 `Any` 或 `AnyObject`，`any` 关键字可以省略——毕竟 `any Any` 或 `any AnyObject` 看着很怪。出于向后兼容，如果 constraint type 里出现的 protocol 都没有 associated type、也没有把 `Self` 放在非 covariant 位置的 requirement，`any` 同样可以省略。

### Type representation

Existential type 是 `ExistentialType` 的实例，它把一个 constraint type 包在里面。即便在 `any` 可以省略的那些情形下，只要 type resolution 是在一个期待「值的类型」的上下文里解析类型，它也会把 constraint type 包进 `ExistentialType`。如果 constraint type 是一个带 superclass 项的 protocol composition，或者是一个 parameterized protocol type，那么任意类型都可能作为 constraint type 的结构化组成部分出现。这意味着 existential type 的 constraint type 是会被 `Type::subst()` 代入的。例如下面 `foo` 和 `bar` 两个 property 的 interface type 就是含有 type parameter 的 existential type：

```swift
struct S<T> {
  var foo: any Sequence<T>
  var bar: any Equatable & C<T>
}

class C<T> {}
```

Existential metatype 写作 `any (P).Type`（`P` 是某个 constraint type），它是一个容器，装的是某个具体 metatype，其 instance type 满足一些 requirement。Existential metatype 由 `ExistentialMetatypeType` 的实例表示，它和 `ExistentialType` 一样包着一个 constraint type。而 existential 值本身的 metatype，也就是 `(any P).Type`，表示成一个 `MetatypeType`，其 instance type 是一个 `ExistentialType`。

特殊的 `Any` 类型能存放任意 Swift 值。这种「没有任何约束」表示成一个 constraint type 为空 protocol composition 的 existential type。`ASTContext::getAnyExistentialType()` 方法返回这个类型。

能存放任意引用计数指针的 `AnyObject` 类型，是一个 constraint type 为特殊 protocol composition 的 existential type，那个 composition 里存着一条 layout constraint。`ASTContext::getAnyObjectType()` 方法返回这个类型。标准库里的 `AnyClass` 则是 `AnyObject` 的 existential metatype 的一个 type alias：

```swift
typealias AnyClass = AnyObject.Type
```

## Existential Archetypes

**算法（Apply substitution map to existential archetype）.** Hello.

> 译注：原书这里只写了一句占位的 "Hello."，算法本体尚未写就。这个 `algorithm` 环境在源文件里位于所有 `\ifWIP` 块**之外**，所以它是本章唯一会进入官方 PDF 的内容——PDF 上就是一条标题为 "Apply substitution map to existential archetype"、正文只有 "Hello." 的算法。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

**opened existential signature** 是这样一个 generic signature：它的 substitution 描述了一个 existential type 里可能存放的具体类型。Opened existential signature 有两种形态，取决于 constraint type 里含不含 type parameter：

1. 如果 constraint type 不含 type parameter，opened existential signature 就是由单个受 constraint type 约束的 generic parameter `τ_0_0` 构成的 generic signature。注意，如果 constraint type 里含有 archetype，那么它们出现在 opened existential signature 里时，行为基本等同于具体类型。这个 generic parameter `τ_0_0` 被称为该 existential 的 **interface type**。
2. 如果 constraint type 含有来自某个 parent generic signature 的 type parameter，那么 opened existential signature 是往 parent generic signature 上再加一个 generic parameter 得到的。新参数的 depth 比 parent generic signature 最后一个 generic parameter 的 depth 大一。这种情形下，opened existential signature 的最后一个 generic parameter 就是该 existential 的 interface type。其实只要把 parent generic signature 看成空的，第一种情形就是第二种的特例。

`ASTContext::getOpenedArchetypeSignature()` 方法接受一个 existential type 和一个可选的 parent generic signature 作为参数，返回 opened existential signature。这是编译器里到处都在用的一个廉价操作，结果会缓存。

**例.** 几个不含 type parameter 的 constraint type 及其 existential signature。

1. Existential type `any Equatable` 的 existential signature 是：

   `<τ_0_0 where τ_0_0: Equatable>`

   你可能会想起来，这同时也是 `Equatable` protocol **声明**本身的 generic signature。对形如 `any P`（`P` 是一个 protocol）的所有 existential type 都是如此。

2. Existential type `any Equatable & Sequence` 的 existential signature 是：

   `<τ_0_0 where τ_0_0: Equatable, τ_0_0: Sequence>`

3. 假设有一个泛型类 `SomeClass<T>`，只有一个无约束的 generic parameter。那么 existential type `any Equatable & SomeClass<Int>` 的 existential signature 是：

   `<τ_0_0 where τ_0_0: SomeClass<Int>, τ_0_0: Equatable>`

4. Existential type `any Sequence<Int>` 的 existential signature 是：

   `<τ_0_0 where τ_0_0: Sequence, τ_0_0.[Sequence]Element == Int>`

**例.** 看这个例子：

```swift
func foo<T, U>(x: any Equatable & SomeClass<T>, y: any Sequence<U>) {
  let xx = x
  let yy = y
}

class SomeClass<T> {}
```

`foo()` 的 interface type 里出现了含 type parameter 的 existential type：

`<τ_0_0, τ_0_1> (any Equatable & SomeClass<τ_0_0>, any Sequence<τ_0_1>) -> ()`

Existential type `any Equatable & SomeClass<T>` 的 existential signature 是：

`<τ_0_0, τ_0_1, τ_1_0 where τ_1_0: SomeClass<τ_0_0>>`

Existential type `any Sequence<U>` 的 existential signature 是：

`<τ_0_0, τ_0_1, τ_1_0 where τ_0_1 == τ_1_0.[Sequence]Element, τ_1_0: Sequence>`

两个 signature 里，existential 的 interface type 都是 `τ_1_0`。

回忆一下 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)）：generic environment 一共有三种。我们见过 primary generic environment，它和 generic declaration 相关联；也在 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）的 Opaque Archetypes 一节见过 opaque generic environment，它由一个 opaque result declaration 加一张 substitution map 实例化而来。现在轮到第三种了：opened generic environment。Opened generic environment 由第一种形态（没有 parent generic signature）的 opened existential signature 创建。Opened generic environment 的 archetype 就是 **existential archetype**。

当表达式类型检查器遇到一个 call expression，其中一个 existential type 的实参被传给一个类型为 generic parameter 的形参时，这个 existential 值会被 **open**：把值投影出来，并从一个全新的 opened generic environment 里分配一个新的 existential archetype 给它。这个 call expression 会被改写——整个调用被包进一个 `OpenExistentialExpr`，后者存着两个子表达式。第一个子表达式是原先那个调用实参，求值得到 existential type 的值。Payload 值和 existential archetype 的作用域限于第二个子表达式，由它来消费这个 payload 值。原先的调用实参被换成一个 `OpaqueValueExpr`，其类型就是那个 existential archetype。这个 existential archetype 同时成为该调用 substitution map 里那个 generic parameter 的 replacement type。

举例来说，若 `animal` 是一个 `any Animal` 类型的值，那么调用 protocol 方法的表达式 `animal.eat()` 在 open 之前长这样：

```
CallExpr
├── SelfApplyExpr
│   ├── DeclRefExpr: Animal.eat()
│   └── DeclRefExpr: animal
└── ArgumentList
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

Open 之后，会为 generic signature `<τ_0_0 where τ_0_0: Animal>` 创建一个新的 opened generic environment。整个调用被包进一个 `OpenExistentialExpr`，调用的 `self` 实参变成了 `OpaqueValueExpr`，而对变量 `animal` 的引用上移到了 `OpenExistentialExpr`：

```
OpenExistentialExpr
├── CallExpr
│   ├── SelfApplyExpr
│   │   ├── DeclRefExpr: Animal.eat()
│   │   └── OpaqueValueExpr
│   └── ArgumentList
└── DeclRefExpr: animal
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

图里没画出来的是：`OpaqueValueExpr` 的类型是一个 existential archetype type，而把 `τ_0_0` 换成这个 existential archetype 的 substitution map 存在 `Animal.eat()` 的那个 `DeclRefExpr` 里。

如果你需要在表达式类型检查器之外自己做这件事，`GenericEnvironment::forOpenedExistential()` 方法可以创建一个全新的 opened generic environment。

## Runtime Representation

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

编译器分析 existential 的 constraint，从几种可能的表示里挑一种。`TypeBase::getExistentialLayout()` 方法返回一个 `ExistentialLayout` 实例，它编码了决定表示形式所需的信息。`ExistentialLayout` 上几个偶尔用得着的方法：

- **`getKind()`** 返回 `ExistentialLayout::Kind` 枚举的一个成员，取值是 `Class`、`Error` 或 `Opaque` 之一，分别对应下面几种表示。
- **`requiresClass()`** 返回这个 existential type 是否要求所存的具体类型必须是一个 class，也就是它用不用 class representation。
- **`getSuperclass()`** 返回 existential 的 superclass bound，它可能显式写在 protocol composition 里，也可能声明在某个 protocol 上。
- **`getProtocols()`** 返回 existential 的 protocol conformance。这个数组里的 protocol 按 protocol inheritance 最小化过，并按 canonical protocol order 排序（见 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）的 Protocol order 算法）。
- **`getLayoutConstraint()`** 返回 existential 的 layout constraint（如果有的话）。如果这个 existential 能存放任意 Swift 或 Objective-C class 实例，这里就是 `AnyObject` layout constraint；如果进一步知道 superclass bound 是一个 Swift native class，那就是更严格的 `_NativeClass` layout constraint。

上面这些方法里，有几个你也许在 `generic-signatures.tex` 的 Generic Signature Queries 一节、或者 `archetypes.tex` 讲 archetype 的 local requirement 时见过类似的。确实，大体上同样的信息也可以这么拿到：在 opened existential signature 里对 existential 的 interface type 提问；或者手头正好有一个 existential archetype 时，在这个 archetype 上调用类似的方法。不过有一处重要区别。在 generic signature 里，最小化算法会丢掉那些已被 superclass bound 满足的 protocol conformance requirement，opened existential signature 也照此办理；然而出于历史原因，计算 existential layout 时并不做这个变换。这意味着 `ExistentialLayout::getProtocols()` 给出的 protocol 列表，可能比 opened existential signature 上 `getConformsTo()` query 的结果多出几个 protocol。决定 existential type `any C & P` 运行期表示的，正是前者——来自 `ExistentialLayout` 的那份 protocol 列表。如果不用考虑 ABI 稳定性，这里本该改造成和 requirement 最小化一致的行为。

**例.** 看这几条定义：

```swift
protocol Q {}
protocol P: Q {}
class C: P {}

let x: any P & Q = ...
let y: any P & C = ...
```

先看 `x`。`any P & Q` 的 existential signature 是 `<τ_0_0 where τ_0_0: P>`；requirement `τ_0_0: Q` 被丢掉了，因为 protocol `P` 继承自 protocol `Q`。`ExistentialLayout` 里同样只存了 `P` 这一个 protocol。Existential type `any P & Q` canonicalize 成 `any P`。

再看 `y`。`any C & P` 的 existential signature 是 `<τ_0_0 where τ_0_0: C>`；注意 conformance requirement `τ_0_0: P` 被丢掉了，因为 class `C` 已经 conform to `P`。然而在 Swift 类型系统里 `any C & P` 和 `C` 仍是两个不同的类型，而且 `any C & P` 的运行期表示里存着 `C` 对 `P` 的 conformance 的 witness table，尽管 conformance requirement `τ_0_0: P` 并不出现在 opened existential signature 里。原因就是 `ExistentialLayout` 里的 protocol 列表不会因为 `C` conform to `P` 就把 `P` 丢掉，而是把 `P` 保留下来。

> 译注：这条「ExistentialLayout 不做 superclass 去重」的差异对本库有实际后果：本库数 witness table 字，数的是字段 mangled name 里 `ProtocolList` 列出的 protocol 个数，也就是 `ExistentialLayout` 这一侧的口径，而不是 opened existential signature 最小化之后的口径。（另一个方向上的例外是 marker protocol——`Sendable` 之类编译器已经从 mangled 字段名里剥掉了，所以列出来的每个 protocol 都实打实占一个字。）见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Opaque representation

这是最通用的表示，在其它专门表示都不适用时使用。它由一个三字宽的 buffer、所存具体类型的 type metadata、以及零个或多个 witness table 组成。如果所存的具体类型装得进这三个字的 buffer、且用的是默认对齐，值就直接存在 buffer 里；否则 buffer 里存一个指向 copy-on-write buffer 的指针，那个 buffer 的大小按具体类型来定。Witness table 列表的长度和顺序与 `ExistentialLayout::getProtocols()` 返回的 protocol 列表一致。

| 字 | 内容 |
|---|---|
| Word 1 | value buffer（占三个字） |
| Word 2 | |
| Word 3 | |
| Word 4 | type metadata |
| Word 5 | witness table #1 |
| Word 6 | witness table #2 |
| Word 7 | …… |

> 译注：这张表就是本库静态布局引擎里 opaque existential 的尺寸公式 `32 + 8N`（3 个 buffer 字 + 1 个 metadata 字 + 每个 protocol 1 个 witness 字）。本库的 `ExistentialLayoutBridge` 是从 runtime 的离线 lowering（RemoteInspection 的 `TypeLowering.cpp` 里的 `ExistentialTypeInfoBuilder`）移植过来的，见 [StaticLayoutEngine.md](../StaticLayoutEngine.md) 与模块参考 [SwiftLayout.md](../Modules/SwiftLayout.md)。

### Class representation

当已知具体类型是一个引用计数指针时用这种表示。此时不用三字的 value buffer，只存一个指针；type metadata 也不必单独存，因为它可以从堆分配的第一个字（所谓「isa pointer」）里取回。尾随的 witness table 和 opaque representation 里一样存放。

| 字 | 内容 |
|---|---|
| Word 1 | reference-counted pointer |
| Word 2 | witness table #1 |
| Word 3 | witness table #2 |
| Word 4 | …… |

> 译注：class representation 对应本库 `ExistentialLayoutBridge` 的 class-bound 分支，公式是 `8·(1+N)`（`AnyObject`、class 约束的 protocol、显式 superclass 三种情形都走这里）。这条规则还解释过本库修过的一个真实偏移 bug：`weak` / `unowned` / `unowned(unsafe)` 修饰的只是那一个对象引用字，后面的 witness table 字照样留在字段里，所以 `weak var x: (any P)?` 占 **16** 字节而不是 8 字节（`any P & Q` 则是 24，而 `AnyObject` 和 `@objc` protocol existential 因为不带 Swift witness table 才是 8）。旧实现对这三种 node kind 一律返回单字，于是 SwiftUICore `ViewResponder` 及其每一个子类的字段偏移全线错位。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Objective-C representation

这是 class representation 的一个特化变体，适用于 constraint type 点名的 protocol 全是 `@objc` protocol 的情形。此时不传任何 witness table，existential 值与对应的 Objective-C protocol type 布局兼容。

| 字 | 内容 |
|---|---|
| Word 1 | reference-counted pointer |

> 译注：本库判断一个 existential 是不是 class-bound，要去读每个 protocol descriptor 的 class 约束位；但 Swift 声明的 `@objc` protocol **不发 protocol descriptor**（不进 `__swift5_protos`），它在二进制里唯一的痕迹是 `__objc_protolist` 里的 ObjC protocol record（旧式 `_TtP<module><name>_` 名）。所以本库在 descriptor 查找落空后回退去查 `__objc_protolist`，命中就按本节这条规则处理：强制 class-bound，且不计 witness table 字。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Error representation

这是一种只用于 conform to `Error` 的类型的特殊表示。它只由一个引用计数指针构成。那块堆分配与 Objective-C 的 `NSError` 类布局兼容。具体的值和该 conformance 的 witness table 都存在这块堆分配里面。

| 字 | 内容 |
|---|---|
| Word 1 | reference-counted pointer |

> 译注：因此 `any Error` 在本库的静态布局引擎里就是一个字（8 字节）——具体值和 witness table 都在堆分配内部，容器本身只有那个指针。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Metatype representation

这种表示只用于 existential metatype。它存一个具体 metatype，后面跟零个或多个 witness table。

| 字 | 内容 |
|---|---|
| Word 1 | type metadata |
| Word 2 | witness table #1 |
| Word 3 | witness table #2 |
| Word 4 | …… |

Swift 的 metatype 值有相等的概念。Metatype 不是 nominal type，因此不能 conform to protocol，特别是不能 conform to `Equatable`（原注：不过说不定哪天就能了……）；即便如此，标准库还是为 `==` 运算符定义了一个接受一对 `Any.Type` 值的重载。你可能还记得前文说过，`Any.Type` 是一个没有任何约束的 existential metatype，所以它表示成指向运行期 type metadata 的单个指针。于是 metatype 的相等就可以实现成指针相等。这意味着运行期 type metadata 必须在构造上保证唯一。像 `Int` 这样 frozen 的定长类型有静态 emit 的 metadata，此后直接引用它即可，唯一性是平凡的。另一方面，泛型 nominal type 以及函数、元组这类 structural type 可以用任意 generic argument 实例化。由于这些实参本身已经递归地保证了唯一性，每种 type constructor 的 metadata 实例化函数会维护一张缓存，把迄今见过的所有 generic argument 映射到已实例化的类型。对给定的一组 generic argument，每个新实例只构造一次，唯一性由此得到保证。

**代码清单（演示运行期 metadata 唯一性的例子）.**

```swift
func concrete() -> Any.Type {
  return (Int, Int).self
}

func generic<T>(_: T.Type) -> Any.Type {
  return (T, T).self
}

print(concrete() == generic(Int.self))  // true
```

上面这段代码把同一个 metatype 构造了两次，一次在具体函数里，一次在泛型函数里：

- `concrete()` 函数把类型 `(Int, Int)` 编码成一个紧凑的 mangled 表示，传给运行期那个「从 mangled type 字符串实例化 metadata」的入口。这个入口在 demangle 完输入字符串之后，最终调用的是元组的 type constructor。
- `generic()` 函数接收 `Int` 的 type metadata 作为实参，直接调用元组的 type constructor，以 `T := Int` 这条替换来构造类型 `(T, T)`。两个函数返回相同的 `Any.Type` 值，因为对元组 type constructor 的两次调用返回的是同一个值。

在没有 constrained existential type 的年代，一个 existential type 的 type metadata 看起来就像一个 `ExistentialLayout`：一份最小化的、canonical 的 protocol 列表（可以为空）、一个可选的 superclass 类型、以及一条可选的 `AnyObject` layout constraint。这种布局没法编码任意的 generic requirement，所以不适用于 constrained existential type。Constrained existential type 的 metadata 用的是一种更通用的编码，它基于 opened existential signature。

> 译注：这种更通用的编码落到 mangled name 里，就是 `symbolicExtendedExistentialType` 节点（`symbolicExtendedExistentialType → …ShapeSymbolicReference → constrainedExistential → ProtocolList`）。本库读到这种节点时，取出内层的 `ProtocolList` 路由回普通 existential 的尺寸公式——因为**约束不改变容器大小**，`any Boxed<Int>` 和 `any Boxed` 的布局完全相同，requirement 列表只影响 metadata 的唯一化，不影响占几个字。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

**代码清单（引出 generalization signature 的例子）.**

```swift
protocol P<X, Y> {
  associatedtype X: Q
  associatedtype Y where X.T == Y
}

protocol Q {
  associatedtype T
}

struct ConcreteQ: Q {
  typealias T = Int
}

func concrete() -> Any.Type {
  return (any P<ConcreteQ, Int>).self
}

func generic<X: Q>(_: X.Type) -> Any.Type where X.T == Int {
  return (any P<X, Int>).self
}

print(concrete() == generic(ConcreteQ.self))
```

解决这个问题的第一个念头，也许是拿 opened existential signature 当作运行期 existential type metadata 的唯一化键。可惜，直接照搬 opened existential signature 的 requirement 并不能给你唯一性，因为 opened existential signature 还包含了 parent generic signature 的全部 generic parameter 和 requirement。上面「引出 generalization signature 的例子」给出的就是一个和前面类似的「具体 vs. 泛型」对照，只不过这回用的是 constrained existential type。

`concrete()` 里 `any P<ConcreteQ, Int>` 的 opened existential signature 是：

`<τ_0_0 where τ_0_0: P, τ_0_0.[P]X == ConcreteQ>`

注意第二条 same-type requirement `τ_0_0.[P]Y == Int` 不在这个 generic signature 里，因为它已由第一条 same-type requirement 加上 protocol `P` 中 `X` 与 `Y` 的关系推出来了。

`generic()` 里 `any P<X, Int>` 的 opened existential signature 是：

`<τ_0_0, τ_1_0 where τ_0_0 == τ_1_0.[P]X, τ_1_0: P, τ_0_0.[P]T == Int>`

把 substitution map `X := ConcreteQ` 应用到类型 `any P<X, Int>` 上，得到类型 `any P<ConcreteQ, Int>`。这提示我们：以 `X := ConcreteQ` 调用 `generic()`，应该产出和调用 `concrete()` 相同的 type metadata。

在编译器里，你当然可以按下面的办法把第二个 generic signature 变换成第一个。先把一张 substitution map 应用到第二个 signature 的每条 requirement 上：

```
{τ_0_0 ↦ ConcreteQ,
 τ_1_0 ↦ τ_0_0;
 [τ_1_0: P] ↦ [τ_0_0: P]}
```

这会得到一串代入后的 generic requirement：

| 原 requirement | 代入后的 requirement |
|---|---|
| `τ_0_0 == τ_1_0.[P]X` | `ConcreteQ == τ_0_0.[P]X` |
| `τ_1_0: P` | `τ_0_0: P` |
| `τ_0_0.[P]T == Int` | `Int == Int` |

把这些 requirement 连同只含一个 generic parameter `τ_0_0` 的参数列表一起喂给 `buildGenericSignature()`，我们就拿回了最初那个 signature：

`<τ_0_0 where τ_0_0: P, τ_0_0.[P]X == ConcreteQ>`

「先把 substitution map 应用到一个 generic signature 的 requirement 上，再用代入后的 generic requirement 建一个新的 generic signature」——这个两步走的套路在编译器里反复出现。`building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Requirement Inference 一节用的就是这个技术，后面在 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）的 Subclassing 一节，以及讲 value requirement 的那一章里还会再遇到它。不过在眼下这件事上，**它其实并没有解决我们的问题！**我们做的这套变换必须发生在运行期，因为 `generic()` 的实现得能对任意类型 `T` 做这件事。而教会运行时从头构建最小化的 canonical generic signature 并不现实——那等于要把编译器里很大一块逻辑在运行时再实现一遍。

> 译注：原书此处的两条交叉引用在源码树里都对不上：`classinheritance` 这个标签指的是 `substitution-maps.tex` 里的 Subclassing **一节**（不是一章），而 `valuerequirements` 在整个 `docs/Generics/` 下根本没有对应的 `\label`——推测是作者当时还没写的那一章。译文按上述理解转写。

于是，编译器不拿「最具体」的那个 opened existential signature 当唯一化键，而是构造一个「最泛化」的 signature，外加一张 substitution map。如果这张 substitution map 里的 replacement type 含有 type parameter，它们会在构造 existential type metadata 时于运行期从 generic context 里填入。最终得到的 generalization signature 加 substitution map，就是 existential type metadata 运行期实例化的唯一化键。这个算法实现在 `ExistentialGeneralization::get()` 里。

**算法（Existential generalization）.** 输入是一个 existential type 的 constraint type（其中可能含有 type parameter）。输出是一个新的 constraint type、一个新的 generic signature，以及这个 signature 的一张 substitution map。

1. 初始化 `N := 0`。
2. 把 `R` 初始化为空的 requirement 列表。
3. 把 `S` 初始化为空的 substitution 列表。
4. 按下面五种情形递归地 generalize 这个 constraint type：

   - **Protocol composition type**：对 protocol composition 的每一项递归执行第 4 步。
   - **Parameterized protocol type**：按顺序逐个 generalize 各个实参类型，并用 generalize 后的实参建一个新的 parameterized protocol type：
     1. 把实参类型换成 `τ_0_N`，
     2. 往 `S` 里加一条「把 `τ_0_N` 替换成该实参类型」的 substitution，
     3. `N` 加一。
   - **Generic class type**：按顺序逐个 generalize 各个实参类型，并用 generalize 后的实参建一个新的 generic class type：
     1. 把实参类型换成 `τ_0_N`，
     2. 往 `S` 里加一条「把 `τ_0_N` 替换成该实参类型」的 substitution，
     3. `N` 加一。

     设 `C` 为更新后这个 generic class type 的 context substitution map。对该 class 的 generic signature 的每一条 requirement，把 `C` 应用上去，并把代入后的 requirement 加进 `R`。
   - **Protocol type**：类型保持不变。
   - **Class type**：类型保持不变。
5. 如果 `N = 0`，说明这个类型没有任何可替换的实参，此时 `R` 和 `S` 都应为空。返回原来的 constraint type，配一个空的 generic signature 和空的 substitution map。
6. 否则，用参数 `τ_0_0` … `τ_0_(N-1)` 和 requirement `R` 建一个新的 generic signature。注意 generalize 后的 constraint type 是相对这个外层 generic signature 写出来的。再用这个新 generic signature 和 substitution 列表 `S` 建一张新的 substitution map。返回 generalize 后的 constraint type、generic signature 和 substitution map。

假设有两个 existential type `T_1` 和 `T_2`。对二者分别做 generalization，得到 `(T_1', G_1, S_1)` 和 `(T_2', G_2, S_2)`，三元组的分量依次是 generalize 后的 constraint type、generalization signature 和 generalization substitution map。如果 `T_2` 可以由 `T_1` 应用某张 substitution map `S` 得到，那么有：

1. 两边 generalize 后的 constraint type 和 generalization signature 相等，即 `T_1' = T_2'`，`G_1 = G_2`。
2. Substitution map `S_2` 可以由把 `S` 应用到 `S_1` 上构造出来。

这两条正是保证 existential type metadata 唯一性所必需的不变量。

**例.** 我们再看一遍「引出 generalization signature 的例子」。先从 `concrete()` 开始：对类型 `any P<ConcreteQ, Int>` 应用 Existential generalization 算法，得到 generalize 后的 constraint type `any P<τ_0_0, τ_0_1>`、generalization signature `<τ_0_0, τ_0_1>`，以及下面这张 substitution map：

```
{τ_0_0 ↦ ConcreteQ,
 τ_0_1 ↦ Int}
```

接下来是 `generic()`：对类型 `any P<X, Int>` 应用该算法，得到相同的 generalize 后 constraint type 和 signature，但 substitution map 不同：

```
{τ_0_0 ↦ X,
 τ_0_1 ↦ Int}
```

当以 substitution map `X := ConcreteQ` 调用 `generic()` 时，为唯一化键收集到的运行期 type metadata 在 `concrete()` 和 `generic()` 两边是相同的，两次调用于是产出同一个运行期 type metadata 指针。

**例.** 上一个例子里的 generalization signature 没有任何 generic requirement。而在下面「generalization signature 带 requirement 的例子」中，existential type 是一个含有 generic class type 的 protocol composition，这会在 generalization signature 里引入 requirement。对类型 `any Q<Int> & G<ConcreteP>` 应用 Existential generalization 算法，得到 generalize 后的 constraint type `any Q<τ_0_0> & G<τ_0_1>` 和下面这个 generalization signature：

`<τ_0_0, τ_0_1 where τ_0_1: P, τ_0_1.[P]X == τ_0_1.[P]Y>`

以及这张 substitution map：

```
{τ_0_0 ↦ Int,
 τ_0_1 ↦ ConcreteP;
 [τ_0_0: P] ↦ [ConcreteP: P]}
```

> 译注：原书此处与紧邻上方的 generalization signature 矛盾（signature 里的 conformance requirement 是 `τ_0_1: P`，而 `τ_0_0` 的 replacement type 是 `Int`，`Int` 并不 conform to `P`），疑为笔误，应作 `[τ_0_1: P] ↦ [ConcreteP: P]`；以 generalization signature 那一侧为准。

**代码清单（generalization signature 带 requirement 的例子）.**

```swift
protocol P {
  associatedtype X
  associatedtype Y
}

struct ConcreteP: P {
  typealias X = Int
  typealias Y = Int
}

class G<U: P> where U.X == U.Y {}

protocol Q<T> {
  associatedtype T
}

func concrete() -> Any.Type {
  return (any Q<Int> & G<ConcreteP>).self
}
```

## Self-Conforming Protocols

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

（SR-55：non-@objc existentials do not conform to their own protocol type）

初学者常有一个困惑：一般来说，Swift 里的 protocol 并不 conform to 它自己。外行的解释是这样的：existential type 是一个「盒子」，用来装一个具体类型未知的值；如果这个盒子要求值的类型 conform to 某个 protocol，那你没法把「盒子本身」再塞进另一个盒子里，因为它形状不对。本节就把这个说法讲精确。

在很多场合下，Swift 5.7 引入的 implicit existential opening（SE-0352）给出了绕开这个问题的优雅办法：

```swift
protocol Animal {...}

func petAnimal<A: Animal>(_ animal: A) {...}

func careForAnimals(_ animals: [any Animal]) {
  for animal in animals {
    petAnimal(animal)  // existential opened here in Swift 5.7;
                       // type check error in Swift 5.6.
  }
}
```

上面这段代码在 Swift 5.7 里能通过类型检查，因为 `careForAnimal()` 的 generic parameter `A` 的 replacement type 变成了来自 `animal` 的 payload 的 existential archetype。到了 Swift 5.7，当 generic parameter type 只是另一个类型的结构化子成分时，仍然能观察到 self-conformance 的缺席：

```swift
func petAnimals<A: Animal>(_ animals: [A]) {...}

func careForAnimals(_ animals: [any Animal]) {
  petAnimals(animals)  // type check error.
}
```

没法把 `animals` 的每个元素同时 open，而且拿 `any Animal` 作 generic parameter `A` 的 replacement type，对 `petAnimals()` 的这次调用也通不过类型检查。

> 译注：原书上一段把那个 generic parameter `A` 说成是 `careForAnimal()` 的，但代码里 `A` 属于 `petAnimal()`，而 `careForAnimals()` 根本没有 generic parameter；疑为笔误，以代码为准。

现在我们把「一般来说，Swift 里的 protocol 并不 conform to 它自己」中的「一般来说」讲精确。确实有一些 protocol 是 conform to 自己的，这种情况下 global conformance lookup 返回一个特殊的 `SelfProtocolConformance` 类型。

头两类特殊的 self-conforming existential type，是那些没有 conformance requirement 的。

### Any

`Any` 类型是一个 constraint type 为空 protocol composition 的 existential。把一个 generic parameter 约束到 `Any` 上毫无作用，等同于让这个 generic parameter 不带约束。而一个无约束的 generic parameter 可以被任意类型代入，包括 `Any` 自己。从这个意义上说，`Any`「conform to 它自己」：

```swift
func doStuff<T: Any>(_: [T]) {...}  // `T: Any' is pointless

let value: Any = ...

doStuff([value])  // okay
```

### AnyObject

`AnyObject` 类型是一个 existential，其 constraint type 要求所存的值是单个引用计数指针。`AnyObject` existential 不携带任何 witness table，所以这个 existential 本身和它的 payload 有相同的表示。正因如此，`AnyObject` existential type 满足 `AnyObject` layout constraint。`doStuff()` 的调用约定接收 `T` 的 type metadata 和一个引用计数指针的数组。把 `AnyObject` 自己的 type metadata 当作 `T` 传进去，再传一个 `AnyObject` 值的数组，工作得好好的：

```swift
func doStuff<T: AnyObject>(_: [T]) {...}

let value: AnyObject = ...

doStuff([value])  // okay
```

接下来两类 self-conforming existential 带有 protocol conformance requirement，但同样不携带 witness table。

### Sendable protocol

`Sendable` protocol 既没有 witness table 也没有任何 requirement，所以 `Sendable` existential 平凡地 conform to 自己。

### Certain @objc protocols

Objective-C protocol 不用 witness table 来派发方法调用，所以一个所有 protocol 都是 `@objc` 的 existential type，其表示和 `AnyObject` 一样——单个引用计数指针。这使得「各项全是 `@objc` protocol」的 protocol composition 可以 conform to 自己，前提是每个 protocol 还满足下面几条额外条件：

1. 每个被继承的 protocol 都必须递归地 self-conform。
2. 该 protocol 必须是 `@objc` protocol。
3. 该 protocol 不得声明任何 static 方法。
4. 该 protocol 不得声明任何构造器。

TODO：这里放一个能正常工作的例子。

后两条是语义上的条件，而非表示上的。如果不强制最后一条，下面这段代码就会被接受——尽管它并没有良定义的含义：`init()` 这条 requirement 是在 protocol metatype 自身上调用的，而不是在该 protocol 的某个具体实现上：

```swift
@objc protocol Initable {
  init()
}

func makeNewInstance<I: Initable>(_ type: I.Type) -> I {
  return type.init()
}

makeNewInstance(Initable.self)
```

### Error protocol

`Error` existential 同样用一种特殊表示，让它看起来像单个引用计数指针。`Error` protocol 是通过 witness table 派发方法调用的，但具体 conformance 对应的那张 witness table 存在堆分配里面，和具体值放在一起。

当一个函数的 generic parameter 被约束到 `Error` 时，它期望在调用时收到 `Error` conformance 的 witness table 作为实参，和该 generic parameter 的 type metadata 一起传进来。可具体 conformance 的 witness table 是存在**值**里面的，而我们手上并没有值——要是有值，我们一开始就该把 `Error` existential open 掉了。解决办法是：编译器为 `Error` protocol emit 一张特殊的 **self-conformance** witness table。等到这张 witness table 里的 witness 方法被调用时，值就已经有了，于是 self-conformance witness table 里的 witness 方法实现会把 existential 拆开，再派发一次——这一次走的是具体 conformance 的 witness table。

- Error 作为 existential —— Error 作为 generic 实参 —— Error 作为 self-conforming 的 generic 实参

只要想想两个**不同**的具体 `Error` 类型被存进一个 `any Error` 数组里的情形，就能看出为什么非得双重派发不可：

```swift
func printErrorDomain<E: Error>(_ errors: [E]) {
  for error in errors {
    print(error._domain)
  }
}

printErrorDomain([MyError() as Error, YourError() as Error])
```

除了形式上的 `errors` 参数之外，`printErrorDomain()` 还会收到两个 lower 之后的参数：`E` 的 type metadata，以及 `E: Error` conformance 的 witness table。第 7 行的调用把 existential type metadata `any Error` 作为 generic parameter `E` 传入，并传入 `E: Error` conformance 的 self-conforming witness table。在 `printErrorDomain()` 的函数体里，每一次 `print(error._domain)` 遇到的 existential 装的都是不同的具体类型，但调用用的却是同一张 self-conformance witness table。这仍然能跑通，因为 self-conformance witness table 里的 witness 方法会从 existential 里取出具体 witness table，再派发到真正的具体 witness 方法上。

`Error` protocol 的 self-conformance witness table 是在构建标准库时于 `SILGenModule::emitSelfConformanceWitnessTable()` 里 emit 的。

### What about other protocols?

理论上，加在 self-conforming `@objc` protocol 上的那几条语义条件，可以和 `Error` 的 self-conformance witness table 这类技巧结合起来，让更多 protocol 能够 self-conform，也许再配一个 opt-in 机制，避免「总是 emit self-conformance witness table」带来的无条件代码体积开销。至于 class existential，还得额外做某种 boxing（和 `Error` 类似），否则一个带 witness table 的 class existential 并不满足 `AnyObject` layout constraint。而这反过来又会让 `===` 这个指针同一性运算符的实现复杂起来，还不止这一处。看起来不值得为此付出如此可观的复杂度上涨……这也就是 Swift 今天没有为 protocol 实现通用 self-conformance 的原因。

## Source Code Reference

> 译注：本节在原书中包在 `\iffalse` 条件块里（不是 `\ifWIP`，但效果一样：官方 PDF 不输出），块内只有作者留下的一份 TODO 提纲；照译以备参考。

TODO：

- **`TypeBase`** Swift 类型层级的基类。
  - `isAnyExistentialType()` 若这是一个 `ExistentialType` 或 `ExistentialMetatypeType` 则返回 true。
- **`ExistentialType`** 一个 existential 的 `any` 类型。
  - `getConstraintType()` 返回底层的 constraint type。
- **`ExistentialMetatypeType`** 一个 existential metatype。
  - `getConstraintType()` 返回底层的 constraint type。
- **`MetatypeType`** 一个具体 metatype。
  - `getInstanceType()` 返回底层的 instance type。
- **`ASTContext`** 全局状态的单例。
  - `getAnyExistentialType()` 返回 `Any` 对应的 existential type。
  - `getAnyObjectType()` 返回 `AnyObject` 对应的 existential type。
- **`GenericEnvironment`** 相对某个 generic signature，从 type parameter 到 archetype 的映射。
  - `forOpenedExistential()` 创建一个全新的 opened generic environment。
- **`ASTContext`** 全局状态的单例。
  - `getOpenedArchetypeSignature()` 构建一个 opened existential signature。

---

> 译自 `docs/Generics/chapters/existential-types.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
