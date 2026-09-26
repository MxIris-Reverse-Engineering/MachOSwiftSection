# Opaque Result Types（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/opaque-result-types.tex`（《Compiling Swift Generics》一书的「Opaque Result Types」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。
>
> **这份译文的用途**：本库把 `some P` 从二进制里还原成源码拼写，靠的就是这一章描述的三样东西——opaque result generic signature（约束长什么样）、带 substitution map 的 opaque archetype（跨模块引用怎么编码）、opaque type descriptor（underlying type 存在哪）。本库如何对应这些概念，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)；译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（opaque result type、opaque result declaration、owner declaration、underlying type、opaque archetype、substitution map、type witness……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex` 的 Type Parameter Order 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。原书的 `T` 对应 `τ_0_0`，`U` 对应 `τ_0_1`，代表 opaque result type 的那个参数多写成 `τ_1_0` |
> | `↻T` | type parameter `T` 的 **opaque archetype**（原书符号是「o」和「->」的合体，取「opaque」与「result」之意）。带下标的 `↻T_d` 指明它属于哪个 opaque result declaration `d` |
> | `⟦T⟧` | type parameter `T` 的 **primary archetype**（函数体内表达式类型里出现的那种） |
> | `[X: P]` | 类型 `X` 对 protocol `P` 的一个 conformance；`X` 是 type parameter 或 archetype 时它是 abstract conformance |
> | `Σ`、`Σ′` | substitution map。写成 `{τ_0_0 ↦ Int; [τ_0_0: Equatable] ↦ [Int: Equatable]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `T`；`Σ ⊗ Σ′` 是 substitution map composition |
> | `P ⊗ X` | global conformance lookup：查 `X` 对 `P` 的 conformance |
> | `Element ⊗ [X: Sequence]` | type witness projection：从 conformance `[X: Sequence]` 里取 associated type `Element` 的 type witness |
> | `Type(G)`、`Type^ctx(G)` | generic signature `G` 的 interface type 集合、contextual type 集合 |
> | `Sub(G → H)`、`Sub^ctx(G → H)` | input generic signature 为 `G`、output generic signature 为 `H` 的 substitution map 集合（replacement type 分别为 interface type / contextual type） |
> | `1_G`、`Fwd_G` | `G` 的 identity substitution map、forwarding substitution map（把每个参数映到自己的 primary archetype） |
> | `in`、`out` | 把类型映入 / 映出 primary generic environment（interface type ↔ contextual type） |

---

Opaque result type 引入了一种此前讲过的语言特性都表达不了的新抽象。尽管概念上是一次飞跃，我们会看到它其实是由既有的构件拼起来的：generic signature（`generic-signatures.tex`）、substitution map（`substitution-maps.tex`）和 abstract conformance（`conformances.tex` 的 Abstract Conformances 一节）。我们先给一个直观的概述，再看具体语法，最后讲清语义。

Opaque result type 的基本想法，是把 generic declaration 里调用方与被调用方的常规关系「反过来」。普通的「输入」generic parameter 抽象的是**调用方**提供的 generic argument；opaque result type 则像一个「输出」generic parameter，抽象的是一个只有**被调用方**知道的固定具体类型。我们把这个具体类型叫做 opaque result type 的 **underlying type**。

和普通 generic parameter 一样，opaque result type 也可以受 requirement 约束。对带 opaque result type 的声明做类型检查时，我们从函数体的语句推断它的 underlying type，并检查这个 underlying type 满足施加其上的 requirement。之后若遇到对这个声明的调用，我们说调用的结果类型是一个受这些 requirement 约束的 **opaque archetype**；调用方不知道 underlying type 是什么。

## Opaque result declarations

回忆一下，`some` 关键字出现在参数位置时表示一个 **opaque parameter declaration**，那只是「一个无名 generic parameter 外加一条 conformance requirement」的语法糖（`declarations.tex` 的 Generic Parameters 一节）。而当 `some` 出现在函数或 subscript 声明的**返回类型**里，或者作为变量声明的类型时，我们得到的是一个 **opaque result declaration**：

```swift
func foo() -> some Sequence {...}
var bar: some Sequence {...}
struct S {
  subscript(_: Int) -> some Sequence {...}
}
```

Opaque result declaration 在求值 **opaque result type request** 时产生。这个 request 以一个 value declaration 为输入。求值函数检查该声明的返回类型里有没有 `some`；没有就结束，有就构造一个 opaque result declaration。

## Opaque result generic signatures

Opaque result declaration 指回它的 **owner declaration**，即声明了这个 opaque result type 的那个 value declaration。Opaque result declaration 与 owner declaration 一一对应。由于 `some` 可以在 owner declaration 的返回类型里出现任意多次，一个 opaque result declaration 一般会声明一个或多个 **opaque result type**。

我们用 opaque result declaration 的 generic signature 来描述这些 opaque result type，它在 opaque result type request 里构造出来。我们把这个 generic signature 叫做 **opaque result generic signature**，而把 owner declaration 的 generic signature 叫做 **outer generic signature**。

第一步是收集所有 `some` 的出现位置。这里处理的是语法层面的 type representation（`type-resolution.tex`），所以我们遍历 owner declaration 返回类型的 type representation，对每个 `some` 后面的 constraint type 调用 type resolution。拿到 constraint type 列表后，我们用下面的参数发起 **abstract generic signature request**（`building-generic-signatures.tex`）：

1. 把 outer generic signature 作为 parent signature 传入。
2. 为 owner declaration 返回类型里的每一个 `some` 添加一个 generic parameter。

   如果 owner declaration 本身不是 generic 的，所有新参数的 depth 都是 0；否则 depth 是 outer generic signature 参数的最大 depth 加一。每个新参数的 index 由 `some` 出现的先后顺序决定。

   > 译注：函数符号里 `Qr` 表示 index 0 的 opaque result type，`QR<n>` 表示 index n + 1；本库按「depth + index」这个坐标去 descriptor 里找参数，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md) §1.3。

3. 对每个新 generic parameter，再添加一条 requirement：左边是这个 generic parameter，右边是它的 constraint type。

   Constraint type 是 protocol type、protocol composition type 或 parameterized protocol type 时，这是一条 conformance requirement。对 protocol composition 和 parameterized protocol type，request 会自动把 requirement 分解成更简单的 requirement（`building-generic-signatures.tex` 的 Decomposition and Desugaring 一节）。

   否则 constraint type 必须是 class type，此时我们添加的是一条 superclass requirement。

Opaque result generic signature 不依赖 opaque result type 的 underlying type，所以不用看函数体就能算出来。这一点很重要，因为 textual interface 里除了 `@inlinable` 函数之外都省略了函数体（`compilation-model.tex` 的 Module System 一节）。同理，parser 也不解析一个 frontend job 的 secondary file 里的声明体。只有当 owner declaration 出现在本 frontend job 的 primary file 里，我们才会去计算 underlying type。因此下面的例子都可以省略函数体。

**例.** 下面列出几个简单情形下得到的 opaque result generic signature，其中一些后面还会回头看。

1. 这里得到一个完全无约束的 opaque result type，因为 `Any` 是空的 protocol composition，对 `Any` 的 conformance requirement 是空操作：

   ```swift
   func fullyOpaque() -> some Any {...}
   ```

   **Opaque result generic signature：** `<τ_0_0>`

2. 下面这个 opaque result declaration 有两个无约束的 opaque result type：

   ```swift
   func fullyOpaquePair() -> (some Any, some Any) {...}
   ```

   **Opaque result generic signature：** `<τ_0_0, τ_0_1>`

3. Constraint type 是单个 protocol 时，opaque result generic signature 带一条对该 protocol 的 conformance requirement：

   ```swift
   func someEquatable(_ b: Bool) -> some Equatable {...}
   ```

   **Opaque result generic signature：** `<τ_0_0 where τ_0_0: Equatable>`

4. Owner declaration 是 generic 的时候，它的 generic signature 会并入 opaque result generic signature。原因见下一节：

   ```swift
   func someEquatable2<T>(_: T) -> some Equatable {...}
   ```

   **Opaque result generic signature：** `<τ_0_0, τ_1_0 where τ_1_0: Equatable>`

5. Parameterized protocol type 分解成一条 conformance requirement 加一条或多条 same-type requirement：

   ```swift
   func someSequenceOfInt() -> some Sequence<Int> {...}
   ```

   **Opaque result generic signature：** `<τ_0_0 where τ_0_0: Sequence, τ_0_0.Element == Int>`

6. 最后，parameterized protocol type 可以在 opaque result type 和 owner declaration 的 type parameter 之间引入一条 same-type requirement：

   ```swift
   func someSequenceOfT<T>(_: T) -> some Sequence<T> {...}
   ```

   **Opaque result generic signature：** `<τ_0_0, τ_1_0 where τ_0_0 == τ_1_0.Element, τ_1_0: Sequence>`

## Inferring the underlying type

对 primary file 里的函数体做类型检查时，我们在给表达式赋好类型之后推断它的 opaque result type 的 underlying type。我们收集函数体里出现的所有 `return` 语句，考察每个被返回表达式的类型。

**例.** `hungryHorses` 这个计算属性展示了 opaque result type 的典型用途：把一个不平凡的 generic 返回类型「藏起来」：

```swift
struct Horse {
  var isHungry: Bool
}

struct Farm {
  var horses: [Horse] = []
  var hungryHorses: some Collection<Horse> {
    return horses.lazy.filter(\.isHungry)
  }
}
```

`return` 语句的类型是 `LazyFilterSequence<Array<Horse>>`，但调用方只看得到它是一个 `Element` 为 `Horse` 的 `Collection`。

我们必须维持的基本不变量是：opaque result type 的 underlying type 在程序运行期间不能改变。一般来说，带 opaque result type 的函数体里若有多条 `return` 语句，它们必须返回完全相同的类型。（这对普通函数也成立。）

**例.** 因此下面这样是不允许的；要表达这种动态性，函数可以改为返回一个 existential type `any Sequence`（`existential-types.tex`）：

```swift
func twoSequences(_ b: Bool) -> some Sequence {
  if b {
    return [1, 2, 3]  // Array<Int>
  } else {
    return ["a", "ab", "ba"]  // Array<String>
  }
}
```

这条规则有一个例外：我们允许 opaque result type 的 underlying type 依赖于 **availability**。本书不讨论 availability checking，只说一点：用特殊语法 `if #available(...)` 写的 availability check，其结果在程序执行期间不会变化。所以，只要带 opaque result type 的函数里那些类型不一致的 `return` 语句分别位于 availability check 的不同分支，就是允许的。

**例.** 在 macOS 宿主上，`bestWidget()` 会按操作系统版本返回两种 underlying type 之一：

```swift
protocol Widget {}
struct OldWidget: Widget {}

@available(macOS 11, *)
struct NewWidget: Widget {}

func bestWidget() -> some Widget {
  if #available(macOS 11, *) {
    return NewWidget()
  } else {
    return OldWidget()
  }
}
```

我们把一个 opaque result declaration 的 underlying type 记录成一组 **underlying type substitution map**，每张 substitution map 对应一个互不相交的 **availability range**。此后我们都假设每个 opaque result declaration 只有一个 availability range，因而只有一张 underlying type substitution map。

> 译注：多张 substitution map 在二进制里的落点，是 opaque type descriptor 的 underlying argument 指向一个 accessor thunk 而不是类型名，thunk 内部先做版本检查再二选一。本库离线读取这种 thunk 的办法见提案 0028 到 0032。

Underlying type substitution map 的 input generic signature 是 opaque result generic signature，output generic signature 按构造就是 outer generic signature。这张 substitution map 把 outer generic signature 的 generic parameter 映到它们自己，把代表 opaque result type 的 generic parameter 映到对应的 underlying type。我们用 `type-resolution.tex` 的 Check substitution map 算法检查这张 substitution map 满足 opaque result generic signature 的 requirement。

**例.** 我们拒绝下面的程序：

```swift
func invalidUnderlyingType() -> some Sequence<Int> {
  return ["ab", "ba", "aab"]  // error
}
```

Opaque result generic signature 是 `<τ_0_0 where τ_0_0: Sequence, τ_0_0.Element == Int>`。我们为它构造出这张 underlying type substitution map：

```
{τ_0_0 ↦ Array<String>;
 [τ_0_0: Sequence] ↦ [Array<String>: Sequence]}
```

把它应用到 same-type requirement `τ_0_0.Element == Int` 得到 `String == Int`，不满足，于是报错。

## History

Opaque result type 在 Swift 5.1 引入（SE-0244），所以它其实早于 opaque parameter declaration（SE-0341）。最初的实现只允许 `some` 在 type representation 的最外层出现一次。Swift 5.7 把它推广到允许 `some` 出现一次或多次、嵌套在任意类型里（SE-0328）。Swift 5.7 还引入了依赖 availability 的 opaque result type（SE-0360）。

## Opaque Archetypes

有了 opaque result generic signature，就可以进入 type resolution，构造 owner declaration 的 interface type。要得到返回位置上某个 `some` 的 interface type，我们取 opaque result generic signature 里对应的 generic parameter，构造代表这个 generic parameter 的 **opaque archetype**。这个 opaque archetype 随后出现在 owner declaration 的 interface type 里。

我们在 `archetypes.tex` 里见过 archetype 和产生它们的 generic environment。那里的重点是 primary archetype，先回忆几条关于它的事实。形式上，primary archetype 是一个二元组 `(G, T)`，`G` 是某个 generic signature，`T` 是（reduced）type parameter。我们把它记作 `⟦T⟧_G`，或在 `G` 显然时简记为 `⟦T⟧`。Primary archetype 只出现在函数体内的表达式类型里，继而出现在 SIL 指令里。

Opaque archetype 同样把一个 type parameter 和一个 generic signature 打包在一起：

**定义.** 若 `d` 是一个 opaque result declaration，`T` 是 `d` 的 opaque result generic signature 的一个 reduced type parameter，我们把 `T` 的 opaque archetype 记作 `↻T_d`，或在 `d` 由上下文可知时记作 `↻T`。

**例（someEquatable）.** 回忆一下，owner declaration 不是 generic 时，opaque result generic signature 的 generic parameter depth 为 0。考虑这个函数：

```swift
func someEquatable(_ b: Bool) -> some Equatable {
  return b ? 1 : 2
}
```

上面的 opaque result generic signature 是 `<τ_0_0 where τ_0_0: Equatable>`，我们把这个函数的返回类型 resolve 为 opaque archetype `↻τ_0_0`。这个函数声明的 interface type 是 function type `(Bool) -> ↻τ_0_0`。

注意，来自不同 opaque result declaration 的 opaque archetype 彼此不同，即使它们的 opaque result generic signature 相等；那种情况下它们只是恰好满足相同 requirement 的两个无关类型。

Opaque archetype 以两种方式参与 type substitution 代数。第一，opaque archetype 可以作为 replacement type 出现在 substitution map 里。第二，可以对 opaque archetype 应用 substitution map，得到一个新的 opaque archetype。下面逐一考察。

**例.** 上一个例子里，`someEquatable()` 的 opaque result type 的 underlying type 是 `Int`，但调用方观察不到这一事实。我们得到的是 opaque archetype `↻τ_0_0`，只有 `Equatable` protocol 提供的操作可用。我们还知道每次调用返回的都是同一个类型：

```swift
print(someEquatable(false) == someEquatable(true))   // 打印 false
print(someEquatable(false) == someEquatable(false))  // 打印 true
```

回忆一下，`==` 的两个实参必须是同一类型，且该类型必须 conform to `Equatable`。`==` 的 generic signature 是 `<τ_0_0 where τ_0_0: Equatable>`，所以我们构造出这张以 `↻τ_0_0` 为 replacement type 的 substitution map：

```
{τ_0_0 ↦ ↻τ_0_0;
 [τ_0_0: Equatable] ↦ [↻τ_0_0: Equatable]}
```

Input generic signature 声明了一条 conformance requirement，所以构造 substitution map 时要查找 `↻τ_0_0` 对 `Equatable` 的 conformance。我们在 `archetypes.tex` 的 Local Requirements 一节把 global conformance lookup 扩展到了 archetype，它对 primary 和 opaque archetype 的行为一致。给定一个 opaque archetype，若其 opaque result generic signature 声明了一条 conformance requirement，global conformance lookup 输出一个以该 opaque archetype 为 subject type 的 abstract conformance：

```
Equatable ⊗ ↻τ_0_0 = [↻τ_0_0: Equatable]
```

我们把这简称为 **opaque abstract conformance**。接下来演示从 opaque abstract conformance 做 type witness projection。为此把 opaque result type 约束到一个带 associated type 的 protocol 上。

**例（opaque type witness）.** 下面这段的最后一行，call expression `someSequence()` 的类型是 `↻τ_0_0`。我们来推导 `pick(someSequence())` 的类型：

```swift
func someSequence() -> some Sequence {
  return [1, 2, 3]
}

func pick<S: Sequence>(_ s: S) -> S.Element {...}

print(pick(someSequence()))
```

调用 `pick()` 的 substitution map 是：

```
Σ := {τ_0_0 ↦ ↻τ_0_0;
      [τ_0_0: Sequence] ↦ [↻τ_0_0: Sequence]}
```

把 `Σ` 应用到 `pick()` 的原始返回类型 `τ_0_0.Element` 就得到答案。把这个 dependent member type 分解，再把 `Σ` 应用到它的 abstract conformance，我们从 substitution map 里得到那个 opaque abstract conformance：

```
τ_0_0.Element ⊗ Σ
  = Element ⊗ [τ_0_0: Sequence] ⊗ Σ
  = Element ⊗ [↻τ_0_0: Sequence]
```

最后做 type witness projection。这输出同一个 opaque result declaration 的另一个 opaque archetype，代表我们的 dependent member type：

```
Element ⊗ [↻τ_0_0: Sequence] = ↻(τ_0_0.Element)
```

注意 `someSequence()` 有如下 underlying type substitution map：

```
{τ_0_0 ↦ Array<Int>;
 [τ_0_0: Sequence] ↦ [Array<Int>: Sequence]}
```

因此在运行时，类型为 `↻(τ_0_0.Element)` 的值实际上是一个 `Int`。

### Declared interface type

回忆 `declarations.tex` 对 type declaration 的讨论。当时没说的是，opaque result declaration 其实是一种特殊的 type declaration，所以我们也得给它一个 **declared interface type**。我们规定 opaque result declaration 的 declared interface type 就是 owner declaration 的返回类型。注意这个类型**包含**至少一个 opaque archetype，但它本身不一定**是**一个 opaque archetype。于是可以说一个 opaque result declaration「声明」了其 declared interface type 里出现的所有 opaque archetype，而这个类型可以带任意结构。在实现里，type declaration 的 declared interface type 必须设成**某个东西**，设成**这个**恰好对实现最方便。

### Type substitution

按 `substitution-maps.tex` 的 Substitute type 算法，primary archetype `⟦T⟧` 的行为和它代表的 type parameter `T` 一样：给定 substitution map `Σ`，有 `⟦T⟧ ⊗ Σ = T ⊗ Σ`。Opaque archetype 则大不相同：对 opaque archetype 应用 substitution map，产生一个新的 opaque archetype。

在完全一般的情况下，opaque archetype 其实是一个**三元组** `(T, d, Σ)`：`T` 是 `d` 的 opaque result generic signature 里的 reduced type parameter，`Σ` 是 `d` 的 outer generic signature 的一张 substitution map。（若 `d` 的 owner declaration 不是 generic 的，`Σ` 永远是 empty substitution map，下面的一切都退化为平凡情形。）

**定义.** 我们继续用 `↻T_d` 表示 outer generic signature 取 identity substitution map 时的 opaque archetype。更一般地，`↻T_d ⊗ Σ` 表示 substitution map 为 `Σ` 的 **substituted opaque archetype**。

Type resolution 总是把每个 `some` resolve 成 outer generic signature 取 identity substitution map 的 opaque archetype。当然，正如记法所示，把 substitution map `Σ` 应用到 `↻T` 就得到 `↻T ⊗ Σ`。这个行为类似 generic nominal type 的 context substitution map。

**例（generic opaque）.** 这是一个带 opaque result type 的 generic function：

```swift
func someEquatable2<T: Equatable>(_ t: T) -> some Equatable {
  return [t]
}
```

Opaque result generic signature 包含 outer generic signature，并为 opaque result type 多加了一个 depth 1 的 generic parameter：

```
<τ_0_0, τ_1_0 where τ_0_0: Equatable, τ_1_0: Equatable>
```

`someEquatable2()` 的 interface type 是如下 generic function type：`<τ_0_0 where τ_0_0: Equatable> (τ_0_0) -> ↻τ_1_0`。

现在考虑对下面两条语句做类型检查：

```swift
print(someEquatable2(1) == someEquatable2(2))  // 打印 false
print(someEquatable2(1) == someEquatable2("hello"))  // 类型错误
```

第一条语句里，两次调用 `someEquatable2()` 用的是同一张 substitution map：

```
Σ₁ := {τ_0_0 ↦ Int; [τ_0_0: Equatable] ↦ [Int: Equatable]}
```

于是第一条语句类型正确，因为我们用两个类型为 `↻τ_1_0 ⊗ Σ₁` 的实参调用 `==`。执行它会打印 `false`，因为两个值确实不相等。不过我们走不到那一步。第二条语句里，右边那次调用 `someEquatable2()` 用的是另一张 substitution map：

```
Σ₂ := {τ_0_0 ↦ String; [τ_0_0: Equatable] ↦ [String: Equatable]}
```

因此 type checker 拒绝第二条语句：右边的类型是 `↻τ_1_0 ⊗ Σ₂`，与左边的 `↻τ_1_0 ⊗ Σ₁` 不同。

这个行为可以这样解释：opaque result type 的 underlying type 同样依赖于 outer generic signature。看 `someEquatable2()` 的 underlying type substitution map：

```
{τ_0_0 ↦ τ_0_0,
 τ_1_0 ↦ Array<τ_0_0>;
 [τ_0_0: Equatable] ↦ [τ_0_0: Equatable],
 [τ_1_0: Equatable] ↦ [Array<τ_0_0>: Equatable]}
```

这张 substitution map 的 output generic signature 是 owner declaration `someEquatable2()` 的 generic signature。我们会在本章 Runtime Representation 一节展开。

我们看到，取 identity substitution map 的 opaque archetype 应用一张 substitution map `Σ`，得到 substitution map 为 `Σ` 的新 opaque archetype。更一般地，若 opaque archetype 带着任意一张 substitution map，再对它应用另一张 substitution map 就是把两张表 compose。

**算法（Apply substitution map to opaque archetype）.** 输入 opaque archetype `↻T_d ⊗ Σ` 和 substitution map `Σ′`，输出 `(↻T_d ⊗ Σ) ⊗ Σ′`。

1. 把 `↻T_d ⊗ Σ` 分解成三元组 `(T, d, Σ)`。
2. 构造 `Σ ⊗ Σ′`（`substitution-maps.tex` 里 substitution map composition 的定义）。
3. 用三元组 `(T, d, Σ ⊗ Σ′)` 构造一个 opaque archetype 并返回。（按我们的记法它写作 `↻T_d ⊗ (Σ ⊗ Σ′)`，理由现在应该清楚了。）

注意，若从 `↻T_d = ↻T_d ⊗ 1_G` 出发应用 substitution map `Σ`，上述算法退化为直接用这张 substitution map 构造新的 opaque archetype，因为 `1_G ⊗ Σ = Σ`：

```
(↻T_d ⊗ 1_G) ⊗ Σ = ↻T_d ⊗ (1_G ⊗ Σ) = ↻T_d ⊗ Σ
```

### Interface types

Opaque archetype 可以出现在声明的 interface type 里，这一点很重要。当然，一个声明自己声明了 opaque result type 时，它的 interface type 里会有它自己的 opaque archetype。但声明的 interface type 也可能涉及别处声明的 opaque archetype。最明显的情形是变量声明的初值表达式调用了一个带 opaque result type 的函数，例如：

```swift
let result = someEquatable(false)
```

不过这并非总被允许，取决于变量的 declaration context。局部变量可以，模块 main source file（若有）里的全局变量也可以。库源文件里的全局变量和 nominal type declaration 的 stored property 则禁止引用其它 owner declaration 的 opaque archetype，我们会报错。

这两类变量之间的区分其实是人为的，我们在本章 Opaque Type Witnesses 一节会看到引用另一个声明的 opaque archetype 的更一般方式。因此我们把 interface type 的定义扩展到包含某些 opaque archetype 的类型，不限制 opaque archetype 的 owner declaration。

**定义.** 我们把 `substitution-maps.tex` 里 interface type 的定义修正如下。设 `↻T_d ⊗ Σ` 是一个 opaque archetype。若 `G` 是 `d` 的 outer generic signature，`H` 是另一个 generic signature 且 `Σ ∈ Sub(G → H)`，则我们说 `↻T_d ⊗ Σ ∈ Type(H)`。也就是说，opaque archetype 是其 substitution map 的 output generic signature 的 interface type。特别地，若 `Σ` 是 identity substitution map `1_G`，则 `↻T ⊗ 1_G = ↻T ∈ Type(G)`。即 type resolution 把一个 `some` resolve 成 opaque archetype 时，我们得到的是其 outer generic signature 的 interface type，正如所期望的。

### Conformance substitution

现在考虑把 substitution map 应用到 opaque abstract conformance 意味着什么。按原始定义，abstract conformance `[T: P]` 以 type parameter `T` 为 subject type，把 substitution map `Σ` 应用到 `[T: P]` 退化为在 `Σ` 里做一次 local conformance lookup。我们在 `conformances.tex` 的 Abstract Conformances 一节用下面的恒等式把它和对类型 `T ⊗ Σ` 的 global conformance lookup 联系起来：

```
[T: P] ⊗ Σ = (P ⊗ T) ⊗ Σ = P ⊗ (T ⊗ Σ)
```

在 `archetypes.tex` 的 Primary Archetypes 一节里我们遇到过 primary archetype 的 abstract conformance，并由上式推出它们在 conformance substitution 下的行为和 type parameter 一样：`[⟦T⟧: P] ⊗ Σ = [T: P] ⊗ Σ`。现在假设把 `Σ` 应用到一个 opaque abstract conformance，比如 `[↻T: P]`。同样有 `[↻T: P] = P ⊗ ↻T`，所以：

```
[↻T: P] ⊗ Σ = (P ⊗ ↻T) ⊗ Σ = P ⊗ (↻T ⊗ Σ)
```

但这一次 `↻T ⊗ Σ` 是另一个 opaque archetype，而 `P ⊗ (↻T ⊗ Σ)` 退化为对 `P` 的另一个 abstract conformance，只不过 subject type 换成了 substituted archetype。我们这样定义 opaque abstract conformance 的 conformance substitution：

```
[↻T: P] ⊗ Σ := [(↻T ⊗ Σ): P]
```

更一般地，opaque abstract conformance 的 subject type 可能带非 identity 的 substitution map，此时记法稍显别扭：

```
[(↻T ⊗ Σ): P] ⊗ Σ′ := [(↻T ⊗ (Σ ⊗ Σ′)): P]
```

关键事实是：对 opaque abstract conformance 应用 substitution map，输出的总是另一个 opaque abstract conformance。这与 subject type 是 type parameter 或 primary archetype 的 abstract conformance 不同。

### Interface types and contextual types

回忆一下，contextual type 是包含 primary archetype 的类型。在 `archetypes.tex` 的 Primary Archetypes 一节我们引入了 `in` 与 `out` 两个操作，在 generic signature `G` 的 interface type 与 contextual type 之间来回映射，这两个集合记作 `Type(G)` 与 `Type^ctx(G)`。

我们还用 type substitution 刻画了 `in` 与 `out`：分别是对类型应用 forwarding substitution map `Fwd_G` 或 identity substitution map `1_G`。这给出了 `Sub(G → H)` 与 `Sub^ctx(G → H)` 之间的类似映射：把 substitution map 在右侧与 `Fwd_H` 或 `1_H` compose，就把它的 replacement type 变成 contextual type 或 interface type。

自然地，我们把 `in` 和 `out` 扩展到 opaque archetype：把 opaque archetype 的 substitution map 在右侧与相应 generic signature 的 forwarding 或 identity substitution map compose。细节如下。

首先，设 `↻T_d` 是 outer generic signature `G` 取 identity substitution map `1_G` 的 opaque archetype。把 `↻T_d` 映入 `G` 的 primary generic environment，得到如下 opaque archetype：

```
in(↻T_d) = ↻T_d ⊗ Fwd_G ∈ Type^ctx(G)
```

一般情形下我们有 opaque archetype `↻T_d ⊗ Σ`，其中 `Σ ∈ Sub(G → H)`。它是 `Type(H)` 的元素，可以映入 `H` 的 primary generic environment，得到一个新的 opaque archetype，其 substitution map 是 `Sub^ctx(G → H)` 里对应的那一张：

```
in_H(↻T_d ⊗ Σ) = ↻T_d ⊗ (Σ ⊗ Fwd_H) ∈ Type^ctx(H)
```

反方向，可以对 contextual type `↻T_d ⊗ Fwd_G` 应用 `out`。由于 `Fwd_G ⊗ 1_G = 1_G`，得到原来的 opaque archetype `↻T_d`：

```
out(↻T_d ⊗ Fwd_G) = ↻T_d ⊗ (Fwd_G ⊗ 1_G) = ↻T_d ∈ Type(G)
```

最后，一般情形 `Σ ∈ Sub^ctx(G → H)` 时：

```
out_H(↻T_d ⊗ Σ) = ↻T_d ⊗ (Σ ⊗ 1_H) ∈ Type(H)
```

总结：opaque archetype 既可以扮演 interface type，也可以扮演 contextual type，取决于它的 substitution map 存的是 interface type 还是 contextual type 的 replacement type。

**例.** 「generic opaque」那个例子里略去了一个细节：表达式里出现的 substitution map，其 replacement type 是 contextual type。下面我们把 opaque archetype 当作 contextual type 来用：

```swift
func someEquatable3<T: Equatable>(_ t: T) -> some Equatable {
  return [someEquatable2(t)]
}
```

设 `G` 是 `someEquatable3()` 的 generic signature。注意 `someEquatable3()` 调用 `someEquatable2()` 用的 substitution map，其 replacement type 是 `G` 的一个 primary archetype：

```
{τ_0_0 ↦ ⟦τ_0_0⟧; [τ_0_0: Equatable] ↦ [⟦τ_0_0⟧: Equatable]}
```

实际上这就是 `G` 的 forwarding substitution map。若 `d` 是 `someEquatable2()` 的 opaque result declaration，则 `someEquatable2()` 的原始返回类型是 opaque archetype `↻τ_1_0_d`，调用 `someEquatable2(t)` 的类型是 `↻τ_1_0_d ⊗ Fwd_G`。这个 call expression 嵌在 array literal 里，所以 return expression 的类型是 `Array<↻τ_1_0_d ⊗ Fwd_G>`。

要构造 underlying type substitution map，我们把 return expression 的类型映出 `G` 的 primary generic environment，得到 interface type `Array<↻τ_1_0_d>`。然后查找这个类型对 `Equatable` 的 conformance，得到一个 conditional 的 specialized conformance。我们得到这张 substitution map：

```
{τ_0_0 ↦ τ_0_0,
 τ_1_0 ↦ Array<↻τ_1_0_d>;
 [τ_0_0: Equatable] ↦ [τ_0_0: Equatable],
 [τ_1_0: Equatable] ↦ [Array<↻τ_1_0_d>: Equatable]}
```

我们看到 `someEquatable3()` 的 opaque result type 是用 `someEquatable2()` 的 opaque result type 定义的。在使用 opaque result type 的框架里这是家常便饭。

### Opaque generic environments

每个 opaque archetype 都从一个 **opaque generic environment** 实例化出来，每个 opaque generic environment 由二元组 `(d, Σ)` 唯一确定：`d` 是 opaque result declaration，`Σ` 是 `d` 的 outer generic signature 的一张 substitution map。回忆 `generic-signatures.tex` 的 Reduced Type Parameters 一节。在一个 opaque generic environment 内部，我们惰性地填一张查找表，键是 reduced type parameter `T`，值是 opaque archetype `↻T_d ⊗ Σ`。现在仔细看看这个映射。

虽然每个 opaque archetype 都代表一个 reduced type parameter，但并非 opaque result generic signature 里的每个 reduced type parameter 都由 opaque archetype 代表。回忆一下，opaque result generic signature 里的 generic parameter 要么属于 outer generic signature，要么代表一个 opaque result type。于是，如果看剥掉所有 dependent member type 之后剩下的 **root generic parameter**，opaque result generic signature 里有两种 reduced type parameter：

1. 根在 owner declaration 的 generic parameter 上的 type parameter，我们称为 **outer type parameter**。
2. 其余所有合法 type parameter 的根都是 opaque result declaration 新加的 generic parameter 之一，所以它们代表 opaque result type。

只有第二种 reduced type parameter 由 opaque archetype 代表；第一种的处理方式见下。

**算法（Map type parameter into opaque generic environment）.** 输入 opaque generic environment `(d, Σ)` 和 type parameter `T`。若 archetype 存在则输出 `↻T_d ⊗ Σ`，否则输出 `Σ` 的 output generic signature 的一个 interface type 或 contextual type。

1. 设 `O` 为 `d` 的 opaque result generic signature。
2. （Reduce）令 `X ← getReducedType(O, T)`。
3. （Concrete）若 `X` 是 concrete type，它仍可能包含 type parameter。对 `X` 里的每个 type parameter 递归应用本算法，返回结果。
4. （Abstract）否则 `X` 是 reduced type parameter。令 `T ← X`。
5. （Outer）若 `T` 是 outer type parameter，返回 `T ⊗ Σ`。
6. （Archetype）否则返回 opaque archetype `(T, d, Σ)`，记作 `↻T_d ⊗ Σ`。

要在第 3 步真正看到 concrete type、在第 5 步看到 outer type parameter，可以考虑约束到 parameterized protocol type 的 opaque result type。

**例.** 下面是「opaque type witness」例子的加强版：

```swift
func someSequenceOfInt() -> some Sequence<Int> {
  return [n]
}

func pick<S: Sequence>(_ s: S) -> S.Element {...}

print(pick(someSequenceOfInt()))
```

记下 `someSequenceOfInt()` 的 opaque result generic signature，它带一条来自 parameterized protocol type 的 same-type requirement：

```
<τ_0_0 where τ_0_0: Sequence, τ_0_0.Element == Int>
```

调用 `someSequenceOfInt()` 的返回类型是这个 signature 的 opaque archetype `↻τ_0_0`。要得到 `pick(someSequenceOfInt())` 的返回类型，我们像「opaque type witness」那个例子一样进行，但在最后一步从 opaque abstract conformance 做 type witness projection 时，得到的不再是另一个 opaque archetype。Type witness projection 把 `τ_0_0.Element` 映入 opaque generic environment 时，落在 Map type parameter into opaque generic environment 算法的第 3 步，得到 `Int`：

```
Element ⊗ [↻τ_0_0: Sequence] = Int
```

因此 call expression `pick(someSequenceOfInt())` 的类型是 `Int`。

**例（opaque result parameterized generic）.** Owner declaration 是 generic 时，parameterized protocol type 可以把它的 primary associated type 约束到 outer generic signature 的 type parameter 上。下面我们证明传给 `print()` 的实参类型是 `Bool`：

```swift
func someSequenceOfT<T>(_ t: T) -> some Sequence<T> {
  return [t]
}

func pick<S: Sequence>(_ s: S) -> S.Element {...}

print(pick(sequenceOfT(true)))
```

`sequenceOfT()` 的 generic signature 是 `<τ_0_0>`，最后一行我们用 substitution map `Σ := {τ_0_0 ↦ Bool}` 调用它。另设 `d` 是 `someSequenceOfT()` 的 opaque result declaration，`O` 是 opaque result generic signature：

```
<τ_0_0, τ_1_0 where τ_0_0 == τ_1_0.Element, τ_1_0: Sequence>
```

`sequenceOfT(true)` 的返回类型、也就是 `pick()` 的实参类型，是 opaque archetype `↻τ_1_0 ⊗ Σ`。于是我们可以从 conformance `[(↻τ_1_0 ⊗ Σ): Sequence]` 投影 `Element` 的 type witness 来得到 `pick()` 的返回类型。

要得到这个 type witness，我们把 `τ_1_0.Element` 映入 opaque generic environment `(d, Σ)`，为此先算 `getReducedType(O, τ_1_0.Element)`。结果是 `τ_0_0`，它是 `d` 的 outer type parameter，所以落在 Map type parameter into opaque generic environment 算法的第 5 步。对 `τ_0_0` 应用 `Σ` 得到答案：

```
Element ⊗ [(↻τ_1_0 ⊗ Σ): Sequence]
  = τ_0_0 ⊗ Σ
  = Bool
```

Map type parameter into opaque generic environment 算法假设：若 type parameter `T` 等价于某个 outer type parameter，则 `getReducedType(O, T)` 总是一个 outer type parameter。要让这一点成立，outer type parameter 在 type parameter order 里必须排在前面。然而 `generic-signatures.tex` 的 Type parameter order 算法没有这个性质，因为它先比长度；可能出现 `|T| > |U|` 而 `T` 是 outer、`U` 不是。这曾是一个 bug 报告的主题，现已修复（Swift issue #59391）。描述修法之前先看个例子。

**例.** 下面用 `generic-signatures.tex` 里「protocol N」例子的 protocol `N`，其实任何能让我们写出长度大于 2 的 reduced type parameter 的 protocol 都行。（`pick()` 沿用前两个例子。）

```swift
func someSequenceOfLong<T: N>() -> some Sequence<T.A.A> {
  return Array<T.A.A>
}

print(pick(someSequenceOfLong(...)))
```

我们用某张 substitution map `Σ` 调用 `someSequenceOfLong()`，得到 opaque archetype `↻τ_1_0 ⊗ Σ`。和「opaque type witness」例子一样，我们通过从某个 conformance 投影 `Element` 的 type witness，来确定 `pick()` 调用的 substituted type。注意 opaque result type 的 generic argument 是 `τ_0_0.A.A`，一个长度为 3 的 type parameter。Opaque result generic signature 如下：

```
<τ_0_0, τ_1_0 where τ_0_0: N, τ_1_0: Sequence,
                    τ_1_0.Element == τ_0_0.A.A>
```

在上面的 generic signature 里，`τ_1_0.Element` 等价于 outer type parameter `τ_0_0.A.A`。于是做 type witness projection 时，我们对 `τ_0_0.A.A` 应用 `Σ`：

```
Element ⊗ [↻τ_1_0 ⊗ Σ: Sequence] = τ_0_0.A.A ⊗ Σ
```

由于 `|τ_1_0.Element| = 2` 而 `|τ_0_0.A.A| = 3`，Type parameter order 算法会说 reduced type 必须是长度 2 的那个。但如果真是那样，type witness projection 会输出一个 opaque archetype `↻(τ_1_0.Element) ⊗ Σ`，这是错的。所以我们必须修改 opaque result generic signature 所用的 type parameter order。

**定义.** Generic parameter type 除了存 depth 和 index，还存一个 **weight**，取 0 或 1。普通 generic signature 的 generic parameter weight 为 0，特别地，opaque result generic signature 里的 outer generic parameter weight 为 0。Opaque result generic signature 里代表 opaque result type 的 generic parameter weight 为 1。

**Weighted type parameter order** 先比 weight 再比长度，于是 outer type parameter（weight 0）总是排在 opaque result type（weight 1）之前。

**算法（Weighted type parameter order）.** 输入两个 type parameter `T` 与 `U`，输出 `<`、`>` 或 `=` 之一。

1. 设 `T′` 与 `U′` 分别是 `T` 与 `U` 的 root generic parameter。
2. 若 `T′` weight 为 0 而 `U′` weight 为 1，返回 `<`。
3. 若 `T′` weight 为 1 而 `U′` weight 为 0，返回 `>`。
4. 否则两者 weight 相等，按 Type parameter order 算法比较 `T` 与 `U`。

我们在 `generic-signatures.tex` 里断言过 type parameter order 是 well-founded 的。换成上面的 weighted order 后依然成立。（给定一个非空的 type parameter 集合，可以这样找最小元：若集合里至少有一个 weight 0 的元素，就可以丢掉所有 weight 1 的元素，它们不可能比它小。剩下的元素 weight 相同，它们在原 type parameter order 下的最小元就是原集合在修改后的 order 下的最小元。）

> 译注：这就是本库所谓「反向 pin」的成因。Requirement Machine 把 same-type 连通分量里最 canonical 的代表元放在 requirement 左边（`lib/AST/RequirementMachine/RequirementBuilder.cpp`），而 weighted order 保证代表元永远是 outer 那一侧，所以 descriptor 里写的是 `τ_0_0 == τ_1_0.Element`、`τ_0_0.A.A == τ_1_0.Element`，outer type parameter 在左。见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md) §2.3。

本节最后是两个小的实现限制。

**例.** 一个 opaque result type 不能嵌套在另一个的 constraint type 里，所以今天写不了这个：

```swift
func unsupportedNesting() -> some Sequence<some Equatable> {...}
```

其实上面这个用下面的 opaque result generic signature 有明确的解释：

```
<τ_0_0, τ_1_0 where τ_0_0: Sequence, τ_0_1: Equatable,
                    τ_0_1 == τ_0_0.Element>
```

这一条不用太多功夫就能解决。

**例.** 与普通的「输入」type parameter 不同，opaque result type 不参与 requirement inference（`building-generic-signatures.tex` 的 Requirement Inference 一节）：

```swift
func goodInference(_: Set<some Any>) {}  // 实际上是 Hashable
func badInference() -> Set<some Any> {}  // error
```

构造第一个声明的 generic signature 时，我们推断出 requirement `[τ_0_0: Hashable]`。第二个声明没有对应的行为，所以我们不会在 opaque result generic signature 里推断出 `[τ_0_0: Hashable]`。`some Any` 的 opaque archetype `↻τ_0_0` 不 conform to `Hashable`，不能做 `Set` 的 generic argument，于是报错。把 requirement inference 扩展到 opaque result generic signature 当然是可能的，但从代码可读性角度看未必可取。

## Opaque Type Witnesses

回忆 `conformances.tex` 的 Type Witnesses 一节对 type witness 的讨论，以及同文件 Associated Type Inference 一节的 associated type inference。我们现在会看到：若 protocol 里某个 value requirement 返回一个 associated type，而候选 value witness 返回一个 opaque archetype，associated type inference 会推出 type witness 就是这个 opaque archetype。因此，opaque archetype 可以在一个 conformance 里 witness 一条 associated type requirement。

**例（opaque archetype witness）.** 下面的 normal conformance `[Horses: Sequence]` 用一对 opaque archetype witness 了 `Element` 与 `Iterator` 两个 associated type：

```swift
struct Horses: Sequence {
  func makeIterator() -> some IteratorProtocol {
    return ["Noby", "Neo"].makeIterator()
  }
}
```

我们的 `makeIterator()` 方法返回 opaque archetype `↻τ_0_0`。我们推出 `Iterator` 的 type witness 就是它返回的这个 opaque archetype：

```
Iterator ⊗ [Horses: Sequence] = ↻τ_0_0
```

这个 opaque archetype conform to `IteratorProtocol`，所以它用一个 opaque abstract conformance 满足 `Sequence` protocol 的 associated conformance requirement：

```
Self.Iterator ⊗ [Horses: Sequence]
  = [↻τ_0_0: IteratorProtocol]
```

要得到 `Element`，我们像 `conformances.tex` 里「abstract type witness」例子一样，考虑 `Sequence` protocol 的 associated same-type requirement。这产生另一个 opaque archetype：

```
Element ⊗ [Horses: Sequence]
  = Element ⊗ [↻τ_0_0: IteratorProtocol]
  = ↻(τ_0_0.Element)
```

Associated type inference 还会合成两个 type alias declaration，名为 `Iterator` 和 `Element`。它们让我们能按名字引用这些 opaque archetype。例如，`ride()` 把 opaque archetype `↻(τ_0_0.Element)` 当作**参数**接收：

```swift
func ride(_: Horses.Element) {...}  // 怎么做到的？

for horse in Horses() {
  ride(horse)
}
```

当候选 value witness 定义在 conforming type 的 superclass 里，或它所 conform 的某个 protocol 的 protocol extension 里，我们必须对候选 type witness 应用一张 substitution map，才能得到正确 generic signature 的 interface type。这类似 `type-resolution.tex` 的 Member Type Representations 一节里 member type 的 type resolution。接下来两个例子都声明对这个 protocol 的 conformance：

```swift
protocol P {
  associatedtype A
  func f() -> A
}
```

**例（opaque type witness in a protocol extension）.** 这里 protocol extension 提供了一个 default witness：

```swift
extension P {
  func f() -> some Any {...}  // underlying type 可以依赖 `Self`
}

struct S: P {}
```

Default witness `P.f()` 返回一个 opaque archetype `↻τ_1_0`，其 outer generic signature 是 protocol generic signature `G_P`。我们推出 `A` 的 type witness 是 `↻τ_1_0` 应用 protocol substitution map `Σ_[S: P]` 的结果：

```
A ⊗ [S: P] = ↻τ_1_0 ⊗ {τ_0_0 ↦ S; [τ_0_0: P] ↦ [S: P]}
```

注意 substitution map 指回了 normal conformance `[S: P]`。

**例（opaque type witness in a superclass）.** 最后一种可能是 witness 在 superclass 里：

```swift
class Base<T> {
  func f() -> some Any {...}  // underlying type 可以依赖 `T`
}

class Derived: Base<Int>, P {}
```

类方法 `Base.f()` 返回 opaque archetype `↻τ_1_0`，其 outer generic signature 是 `Base` 的 generic signature。我们应用 `Derived` 的 superclass substitution map，得到 `Derived` 对 `P` 的 conformance 里的 type witness：

```
A ⊗ [Derived: P] = ↻τ_1_0 ⊗ {τ_0_0 ↦ Int}
```

适当修改 `Base` 与 `Derived` 的声明，可以让 type witness 是带任意 substitution map 的 opaque archetype。

**例.** 若 conforming type 是 generic 的，type witness 可以被 substitute。考虑 normal conformance `[Barn<τ_0_0>: Sequence]`：

```swift
struct Barn<T>: Sequence {
  func makeIterator() -> some IteratorProtocol<T> {...}
}
```

在这个 conformance 里，`Iterator` 的 type witness 是 `makeIterator()` 的 opaque archetype `↻τ_1_0`，而 `Element` 的 type witness 是 outer generic parameter `τ_0_0`，同「opaque result parameterized generic」例子：

```
Iterator ⊗ [Barn<τ_0_0>: Sequence] = ↻τ_1_0
Element ⊗ [Barn<τ_0_0>: Sequence] = τ_0_0
```

于是 specialized conformance `[Barn<Int>: Sequence]` 的 type witness 是：

```
Iterator ⊗ [Barn<Int>: Sequence] = ↻τ_1_0 ⊗ {τ_0_0 ↦ Int}
Element ⊗ [Barn<Int>: Sequence] = Int
```

**例.** 若 owner declaration 带有 generic parameter list，它的 opaque archetype 不能 witness associated type requirement：

```swift
protocol GenericP {
  associatedtype A
  func f<T>(_: T) -> A
}

struct Bad: GenericP {  // error
  func f<T>(_: T) -> some Any {...}
}
```

这不是实现限制，而是语言语义的必然结果。Type witness 必须是其 conformance 的 generic signature 的 interface type。然而 opaque result type 是由 owner declaration 的 generic signature 参数化的。Owner declaration 一旦引入自己的 generic parameter，两者就不再重合。嵌套 nominal type 有类似的情形：

```swift
protocol P {
  associatedtype A
}

struct S: P {  // error
  struct A<T> {}
}
```

### Textual interfaces

构建供分发的共享库时，我们用 AST printer 打印模块里的每个声明，生成一个 **textual interface** 文件（`compilation-model.tex` 的 Module System 一节）。Interface 文件包含所有 synthesized declaration，特别是 associated type inference 合成的 type alias。这时我们面临一个新难题：合成的 type alias declaration，其 underlying type 可能引用一个已经存在的 opaque archetype。然而 Swift 语言没有引用 opaque archetype 的语法；`some` 关键字**声明**一个 opaque archetype。

我们用一种只在 textual interface 文件里允许的特殊语法解决这个问题。它把对 opaque archetype `↻T_d ⊗ Σ` 的引用编码为 `d` 的 owner declaration 的 **mangling** 加上 `T` 的 root generic parameter 的 **index**。若 `Σ` 为空且 `T` 只是一个 generic parameter type，长这样：

```
@_opaqueReturnTypeOf("mangling", index) __
```

若 `T` 是 dependent member type，则用 member type representation 语法把它包起来：

```
(@_opaqueReturnTypeOf("mangling", index) __).Element
```

若 `d` 的 owner declaration 是 generic 的，则 `Σ` 非空。我们把 `Σ` 的 replacement type（比如 `X`、`Y`、`Z`）打印在 generic argument list 里：

```
@_opaqueReturnTypeOf("mangling", index) __<X, Y, Z>
(@_opaqueReturnTypeOf("mangling", index) __<X, Y, Z>).Element
```

这个语法不是给人看的，所以被埋进了 `@foo` type attribute 的语法里，这也简化了实现。通常 type attribute 修饰紧跟其后的 type representation，比如 function type 前面的 `@escaping`，但对 `@_opaqueReturnTypeOf` 来说，attribute 本身已经完全指定了类型，后面的 type representation 除了它的 generic argument 之外不被使用。事实上 `__` 可以是任何合法标识符，Swift 5.5 之前 AST printer 用的还是一个 emoji，后来这项「创新」被移除了。

> 译注：本库在 mangling 层面对应这两种拼法——`opaqueReturnTypeOf`（`QO`，只有 owner declaration 的名字）与 `opaqueType`（`Qo`，带 index 与 generic argument list）；本库在 interface 里默认把它们展开成 underlying type，展不开时改用这里的 `@_opaqueReturnTypeOf` 拼法兜底（提案 0045-opaque-reference-spelling-and-member-projection）。

**例.** 把「opaque archetype witness」例子里的声明改成 `public`，用 `-enable-library-evolution` 和 `-emit-module-interface` 调用 `swiftc`，就能生成 textual interface。下面是其中一部分，加了换行：

```swift
public struct Horses : Swift.Sequence {
  public func makeIterator() -> some Swift.IteratorProtocol

  public typealias Element =
    (@_opaqueReturnTypeOf("$s5horse6HorsesV12makeIteratorQryF", 0) __)
      .Element
  public typealias Iterator =
    @_opaqueReturnTypeOf("$s5horse6HorsesV12makeIteratorQryF", 0) __
}
```

打印 `Horse.makeIterator()` 的返回类型时我们用 `some` 语法，因为这里是在声明一个新的 opaque result type。而两个 type alias 的 underlying type 则用 `@_opaqueReturnTypeOf` 语法引用已有的 opaque archetype。注意 `$s5horse6HorsesV12makeIteratorQryF` 是 `makeIterator()` 方法的 mangled name。

**例.** 把「opaque type witness in a protocol extension」例子的声明改成 public、模块名设为 `p`，textual interface 是这样：

```swift
public protocol P {
  associatedtype A
  func f() -> Self.A
}
extension p.P {
  public func f() -> some Any

}
public struct S : p.P {
  public typealias A =
    @_opaqueReturnTypeOf("$s1p1PPAAE1fQryF", 0) __<p.S>
}
```

注意我们用一张 substitution map 引用 opaque archetype。用 `swift-demangle` 工具打印 owner declaration 的 mangled name：

```
$ swift-demangle s1p1PPAAE1fQryF
s1p1PPAAE1fQryF ---> (extension in p):p.P.f() -> some
```

`-expand` 选项会更详细地打印 mangled name 的结构，不妨一试。

**例.** 最后是「opaque type witness in a superclass」例子的 textual interface：

```swift
public class Base<T> {
  public init()
  public func f() -> some Any
}
@_inheritsConvenienceInitializers
public class Derived : p.Base<Swift.Int>, p.P {
  override public init()
  public typealias A =
    @_opaqueReturnTypeOf("$s1p4BaseC1fQryF", 0) __<Swift.Int>
}
```

为了在 type resolution 里支持 `@_opaqueReturnTypeOf` 语法，我们在 parser 解析 textual interface 文件时做一点簿记，把所有 opaque result declaration 收进一个按 source file 的列表。我们还维护一张查找表，初始为空，把 owner declaration 的 mangled name 映回声明本身。这张表在下面算法第一次调用时填充。

**算法（Resolve opaque archetype）.** 输入 mangled name `s`、整数 `i`，以及可选的 generic argument type 列表。返回对应的 opaque archetype。

1. 若已解析的 opaque result declaration 列表为空，跳到第 3 步。
2. 否则从列表取出下一个 opaque result declaration。调用 mangler 构造其 owner declaration 的 mangled name，这会触发若干 request，例如 interface type request。在查找表里加一项，把这个 mangled name 关联到 owner declaration。回到第 1 步。
3. 在表里查 `s`，得到 opaque result declaration `d`。
4. 构造 generic parameter type `τ_d_i`，其中 `d` 是 `d` 的 opaque result generic signature 的最大 depth，`i` 是输入的 index。
5. 设 `G` 为 `d` 的 outer generic signature。若 `G` 非空，我们必须有 generic argument 列表。用这些 generic argument 为 `G` 构造 substitution map `Σ`，用 global conformance lookup 填充 substitution map 的 conformance。否则若 `G` 为空，令 `Σ` 为 empty substitution map。
6. 调用 Map type parameter into opaque generic environment 算法，把 `τ_d_i` 映入 opaque generic environment `(d, Σ)`。
7. 返回这个 opaque archetype `↻(τ_d_i)_d ⊗ Σ`。

## Runtime Representation

回到 `introduction.tex`，我们学到 Swift 通过把函数的 generic signature 编码进 calling convention 来实现 generic function 的 separate compilation。调用方构造 substitution map 里每个 replacement type 和 conformance 的运行时表示，被调用方则用调用方提供的 metadata 和 witness table 抽象地操作 generic 值。Opaque result type 的实现与此类似，只是「反过来」。

调用带 opaque result type 的函数的一方，必须用 runtime type metadata 抽象地操作结果值。为此编译器在编译被调用方时发出一个 **opaque type descriptor**。Opaque type descriptor 引用了 opaque archetype 的 underlying type 的 runtime type metadata。

我们先精确定义 opaque archetype 的 underlying type。为简化讨论，只考虑 opaque result type 的 underlying type 不依赖 availability 的情形，此时只有一张 underlying type substitution map。设 opaque result declaration `d` 的 opaque result generic signature 为 `O`，underlying type substitution map 为 `Σ′`，outer generic signature 为 `G`。

**定义.** 设 `↻T_d ⊗ Σ` 是一个 opaque archetype。`↻T_d ⊗ Σ` 的 **underlying type** 是如下 substituted type：

```
T ⊗ Σ′ ⊗ Σ
```

若 `Σ ∈ Sub(G → H)`，则按定义 `↻T_d ⊗ Σ ∈ Type(H)`。正如所期望的，`↻T_d ⊗ Σ` 的 underlying type 也是 `Type(H)` 的元素。事实上：

```
T ⊗ Σ′ ∈ Type(O)
T ⊗ Σ′ ⊗ Σ ∈ Type(H)
```

类似地，若 `Σ ∈ Sub^ctx(G → H)`，则 `↻T_d ⊗ Σ` 的 underlying type 是 `Type^ctx(H)` 的元素。

**定义.** 我们也定义 opaque abstract conformance `[(↻T_d ⊗ Σ): P]` 的 **underlying conformance** 如下：

```
[T: P] ⊗ Σ′ ⊗ Σ
```

即把 underlying type substitution map 应用到我们的 opaque archetype 的 type parameter `T` 的 abstract conformance 上。同样由 substitution map composition 的定义，若 `[(↻T_d ⊗ Σ): P] ∈ Conf(H)`，则它的 underlying conformance 也是 `Conf(H)` 的元素。（`Conf^ctx(H)` 同理。）

**例（opaque archetype underlying type）.** 考虑这个函数：

```swift
func someSequence2<T>(_ t: T) -> some Sequence {
  return [t]
}
```

Underlying type substitution map 是：

```
Σ′ := {τ_0_0 ↦ τ_0_0,
       τ_1_0 ↦ Array<τ_0_0>;
       [τ_1_0: Sequence] ↦ [Array<τ_0_0>: Sequence]}
```

现在设 `Σ := {τ_0_0 ↦ Int}` 是 outer generic signature `<τ_0_0>` 的一张 substitution map。`↻τ_1_0 ⊗ Σ` 的 underlying type 是：

```
τ_1_0 ⊗ Σ′ ⊗ Σ = Array<τ_0_0> ⊗ Σ = Array<Int>
```

`↻(τ_1_0.Element) ⊗ Σ` 的 underlying type 是：

```
τ_1_0.Element ⊗ Σ′ ⊗ Σ = τ_0_0 ⊗ Σ = Int
```

### Runtime entry points

Swift runtime 导出一对入口，它们接收一个 opaque type descriptor，并投影出其 underlying type substitution map 里 replacement type 与 conformance 的 type metadata 和 witness table：

- `swift_getOpaqueTypeMetadata2()` 接收一个 opaque type descriptor 和 opaque result generic signature 里某个 opaque result type 的 index，返回对应 underlying type 的 type metadata。
- `swift_getOpaqueTypeConformance2()` 接收一个 opaque type descriptor 和 opaque result generic signature 里某条 conformance requirement 的 index，返回对应 underlying conformance 的 witness table。

由于 underlying type substitution map 依赖 outer generic signature，每个 runtime 入口还接收完整的一组 type metadata 和 witness table，就是传给同 signature 的 generic function 的那一组。因此，调用带 opaque result type 的函数的一方，必须用与调用时相同的 substitution map 来调用这些入口。这会产生描述 opaque archetype 的 type metadata 与 witness table，从此这个 opaque archetype 的实例就可以像普通 type parameter 的实例一样被操作。

> 译注：descriptor 尾部的 underlying argument 先排每个 opaque 参数的 replacement type，再排 root generic parameter 落在 opaque depth 上的 conformance requirement 各一张 witness table（`lib/IRGen/GenMeta.cpp` 的 `OpaqueTypeDescriptorBuilder::addUnderlyingTypeAndConformances` 与 `opaqueTypeRequiresWitnessTable`）；outer generic signature 的 requirement 不占槽。本库按 index 取 replacement type 的依据就在这里。

**例.** 接着「opaque archetype underlying type」例子。这样调用我们的 `someSequence2()`：

```swift
func pick<S: Sequence>(_ s: S) -> S.Element {...}

print(pick(someSequence2(123)))
```

`someSequence2()` 的入口接收三个参数：一个用来存放类型为 `↻τ_1_0` 的返回值的缓冲区、`τ_0_0` 的 type metadata（这里是 `Int`）、一个指向 `τ_0_0` 类型的值的指针。

为了确定返回值缓冲区的大小，我们生成一次对相应 Swift runtime 入口的调用，把 `someSequence2()` 的 opaque type descriptor 和 `τ_0_0` 的 type metadata 交给它。运行时它输出 underlying type `Array<Int>` 的 type metadata。我们从 metadata 里取出类型大小，据此生成一次动态栈分配。

然后我们把 `someSequence2()` 的结果交给 `pick()`。`pick()` 的入口接收四个参数：一个用来存放类型为 `τ_0_0.Element` 的返回值的缓冲区、`τ_0_0` 的 type metadata，以及 `[τ_0_0: Sequence]` 的 witness table。对后者，我们必须传入 `[(↻τ_1_0 ⊗ Σ): Sequence]` 的 witness table。为了拿到它，我们生成一次对另一个 Swift runtime 入口的调用，同样交给它 opaque type descriptor 和 `Int` 的 type metadata。这个入口输出 underlying conformance `[Array<Int>: Sequence]` 的 witness table。

最后，为了抽象地操作 `pick()` 的返回值，特别是取得一个 `τ_0_0.Element` 的大小，我们生成一次对 `[(↻τ_1_0 ⊗ Σ): Sequence]` 的 witness table 里 `Element` associated type 的 metadata access function 的调用。

### Specialization

这种实现策略对 library evolution 是 resilient 的。若被调用方在共享库里而调用方链接这个库，我们可以自由改变被调用方的 underlying type。只要 opaque result generic signature 不变，生成的 opaque type descriptor 的布局就不变，与调用方的二进制兼容性得以维持。

另一方面，很多情况下调用方与被调用方总是一起编译，比如它们声明在同一个 source file 里。此时 type checker 必须继续维持「opaque archetype 的 underlying type 对调用方隐藏」这一假象。但在代码生成阶段，我们可以避免 runtime type metadata 带来的抽象开销，直接把 opaque archetype 的值当作 underlying type 来操作。

回忆一下，普通 generic function 也用类似的实现策略。默认是 separate compilation，但当函数体对调用方可见时，SIL optimizer 可以根据调用方的 substitution map 生成函数的一个 specialization。

事实上 opaque result type 的情形还更简单，因为一个 opaque archetype 只有一个 underlying type。我们不用单独的 optimizer pass，而是在 SILGen 把类型检查后的 AST 降低到 SIL 指令时做这个替换。准确地说，替换发生在 SIL type lowering（`substitution-maps.tex` 的 SIL Type Lowering 一节）过程中。

**定义.** 设 `f` 是当前正在 lower 的 function declaration，`↻T_d ⊗ Σ` 是 `f` 里引用的某个 opaque archetype。形式上，若下列任一条成立，我们说 `d` 的 underlying type substitution map 从 `f` **可见**（visible）：

1. `d` 的 owner declaration 在另一个 module 里，并且要么
   1. owner declaration 是 `@inlinable` 的，要么
   2. 那个 module 构建时没有开启 library evolution。
2. `d` 的 owner declaration 在 main module 的一个 primary file 里，并且要么
   1. `f` 本身**不是** `@inlinable` 的，要么
   2. `d` 的 owner declaration 也是 `@inlinable` 的。

在 whole module 模式下每个 source file 都是 primary file，所以这个优化在那种情况下最有效。`@inlinable` 的限制确保我们在把 `@inlinable` 函数的 SIL 表示序列化进 binary module（`compilation-model.tex` 的 Module System 一节）时不会泄漏实现细节。这个序列化表示不能依赖任何非 `@inlinable` 函数的 underlying type，即使在同一 module 内。

上述可见性条件成立时，我们可以取得 `d` 的 underlying type substitution map `Σ′`，并放心假设在 `f` 内部 `↻T` 的 underlying type 总是等于 `T ⊗ Σ′`。不过还有一件事要检查。

Access control 关键字（`fileprivate`、`internal`、`public`）决定的不仅是编译期 name lookup 对声明的可见性，还有生成的 object file 里符号的可见性。特别地，只有 underlying type 里出现的每个 nominal type 都可见时，我们才能把 opaque archetype 替换成它的 underlying type。比如，若我们的 opaque result type `d` 声明在另一个 source file 里，其 underlying type 涉及一个 `private struct`，那么即使我们被允许知道这个类型是什么，也不能直接引用它。

**Type expansion context** 收集可见性检查的输入数据。它由 `f` 的 parent declaration context 和一个表示 `f` 是否 `@inlinable` 的标志组成。

下面三个互相递归的算法被 SIL type lowering 用来把 type、conformance 和 substitution map 里出现的 opaque archetype 替换成 underlying type。

**算法（Specialize opaque archetypes within a type）.** 接收 type expansion context 和一个 type。

- 对 **opaque archetype** `↻T_d ⊗ Σ`：
  1. 若其 underlying type 可见，代入 underlying type；若 underlying type 还包含 opaque archetype，则递归。
  2. 否则递归变换 `Σ`，构造一个新的 opaque archetype。
- 对 **existential archetype** `Ǝ_T ⊗ Σ`：递归变换 `Σ`。（`existential-types.tex` 的 Existential Archetypes 一节会讲到它。）
- 对**其它任何 type** `X`：若有子类型则递归变换，并用变换后的子类型构造新 type。

**算法（Specialize opaque archetypes within a conformance）.** 接收 type expansion context 和一个 conformance。

- 对 **specialized conformance** `[X: P] ⊗ Σ`：递归变换 `Σ`，返回一个新的 specialized conformance。
- 对 **opaque abstract conformance** `[(↻T ⊗ Σ): P]`：
  1. 若其 underlying conformance 可见，代入 underlying conformance；若 conforming type 又包含 opaque archetype，则递归。
  2. 否则递归变换 `Σ`。
- 对 **existential abstract conformance** `[(Ǝ_T ⊗ Σ): P]`：递归变换 `Σ`，构造一个新的 existential abstract conformance。

**算法（Specialize opaque archetypes within a substitution map）.** 接收 type expansion context 和 substitution map。

- 用前两个算法递归变换每个 replacement type 和 conformance，构造一张新 substitution map。

### Circularity

我们在之前讨论 conditional conformance 与 recursive conformance 时（`extensions.tex` 的 Conditional Conformances 一节、`conformance-paths.tex` 的 Recursive Conformances 一节）遇到过不终止的编译期计算。Opaque result type 也会出这个问题，因为目前的讨论并未排除一个 opaque result type 的 underlying type 用它自己来定义的可能。若真发生这种事，按前面的描述实现的「把 opaque archetype 替换成 underlying type」算法会永远跑下去。不过现实中我们会尝试检测并报错，如下所示。

**例.** 最简单的例子是带 opaque result type 的函数在所有控制流路径上都调用自己。这里 `f1a()` 与 `f1b()` 的 opaque result type 互相用对方定义：

```swift
func f1a() -> some Any {
  return f1b()
  // error: function opaque return type was inferred as `some Any',
  // which defines the opaque type in terms of itself
}

func f1b() -> some Any {
  return f1a()
  // error: function opaque return type was inferred as `some Any',
  // which defines the opaque type in terms of itself
}
```

**例.** 更复杂的递归也是可能的，underlying type 在结构位置上包含 opaque result type。这里我们的 opaque result type `↻T` 的 underlying type 是 `Array<↻T>`：

```swift
func f2() -> some Any {
  return [f2()]
  // error: function opaque return type was inferred as `[some Any]',
  // which defines the opaque type in terms of itself
}
```

在这些简单例子之外，`conformance-paths.tex` 的 The Halting Problem 一节里用 type substitution 编码 tag system 的技巧稍作修改就能改用 opaque result type，所以 opaque archetype specialization 其实是图灵完备的，这个过程是否终止在一般情况下不可判定。因此防止不终止计算的唯一办法，是对总工作量设一个上界，超出就报错：

1. 为了抓住大多数情形，我们在 type-check primary file request 里急切地尝试完全 specialize 每一个声明的 opaque result type。若出问题就发出 diagnostic，如上面两个例子所示。
2. 在更复杂的场景里，circular 的 opaque result type 只有在 SIL optimizer 跑过若干轮 inlining 与 specialization 之后才显现。此时我们打印一条 fatal error 并停止编译。

将来若能在第二种场景里也给出带有用 source location 的错误就好了。不过即便如此也抓不住一切。在 separate compilation 下，总能定义出互相递归的 opaque result type，直到运行时才暴露。那时程序会在 runtime type metadata 实例化逻辑里因无限递归而崩溃。

最后，默认限制对所有合理的程序应该都够用，但可以用一对 frontend 选项改它们：

- `-max-substitution-depth` 是递归调用的最大次数，即 opaque archetype 的 underlying type 涉及另一个 opaque archetype、它又涉及另一个，如此往复的层数。默认值 500。
- `-max-substitution-count` 是单个 type 内可以访问的 opaque archetype 总数，超过就放弃。默认值 120,000。

> 译注：本库展开 opaque type 时同样设了嵌套上限（`Node+OpaqueType.swift` 里 `OpaqueTypeRewriter.maximumNestedExpansionDepth`，目前是 8），到顶就把最内层引用原样保留，与这里「设上界」的思路一致。

## Source Code Reference

关键源文件：

- `lib/Sema/MiscDiagnostics.cpp`
- `lib/Sema/TypeCheckGeneric.cpp`

**`OpaqueTypeDecl`**：opaque result declaration。

- `getNamingDecl()` 返回该声明的 owner declaration。
- `getOpaqueInterfaceGenericSignature()` 返回该声明的 opaque result generic signature。
- `getUniqueUnderlyingTypeSubstitutions()` 在不依赖 availability 时返回该声明的 underlying type substitution map。Substitution map 尚未计算、或因 owner declaration 没有函数体而无法计算时返回 `nullopt`。
- `getConditionallyAvailableSubstitutions()` 是有多个 availability range 和多张 underlying type substitution map 时的一般形式。

**`ValueDecl::getOpaqueTypeDecl()`**：返回该声明的 opaque result declaration，没有则返回 `nullptr`。另见 `declarations.tex` 的 Source Code Reference 一节。

**`OpaqueResultTypeRequest`**：构造 opaque result type declaration 的 request，通过调用上面的 `ValueDecl::getOpaqueTypeDecl()` 求值。

**`OpaqueUnderlyingTypeChecker`**：一个 AST walker，收集函数体里的 `return` 语句并填写其 opaque result declaration 的 underlying type substitution map。也负责诊断错误，比如多条 `return` 语句的返回类型不一致。Type checker 在给表达式赋类型之后执行这次遍历。

### Opaque Archetypes

关键源文件：

- `include/swift/AST/GenericEnvironment.h`
- `lib/AST/GenericEnvironment.cpp`

**`TypeBase::hasOpaqueArchetype()`**：该 type 是否包含 opaque archetype。另见 `types.tex` 的 Source Code Reference 一节。

**`OpaqueTypeArchetypeType`**：`ArchetypeType` 的子类，表示 opaque archetype。回忆 `archetypes.tex` 的 Source Code Reference 一节：每个 archetype 都有 `getInterfaceType()` 方法返回其 type parameter，`getGenericEnvironment()` 方法返回其 parent generic environment。Opaque archetype 还有两个访问器：

- `getOpaqueDecl()` 返回该 opaque archetype 的 opaque result declaration。
- `getSubstitutions()` 返回该 opaque archetype 的 substitution map。

**`GenericEnvironment`**：另见 `archetypes.tex` 的 Source Code Reference 一节。

- `forOpaqueType()` 是静态工厂方法，返回给定 opaque result declaration 和 substitution map 的唯一 opaque generic environment。
- `getKind()` 对 opaque generic environment 返回 `GenericEnvironment::Kind::Opaque`。Opaque archetype 的 generic environment 一定是这种。
- `getOpaqueTypeDecl()` 返回该 environment 的 opaque result declaration。
- `getOuterSubstitutions()` 返回该 generic environment 的 substitution map。

### Opaque Type Witnesses

关键源文件：

- `lib/AST/SourceFile.cpp`
- `lib/Sema/TypeCheckType.cpp`

**`TypeResolver::resolveOpaqueReturnType()`**：即 Resolve opaque archetype 算法，解析特殊的 `@_opaqueReturnTypeOf` 语法。

**`SourceFile`**：另见 `compilation-model.tex` 的 Source Code Reference 一节。

- `addUnvalidatedDeclWithOpaqueResultType()` 把一个声明记录为带 opaque result type，加入按 source file 的列表。由 parser 调用。
- `getOpaqueReturnTypeDecls()` 遍历上述列表，构造每个 opaque result declaration，并用每个 owner declaration 的 mangled name 填充按 source file 的查找表。这是 Resolve opaque archetype 算法的第 1、2 步。
- `lookupOpaqueResultType()` 按给定 mangled name 返回 opaque result declaration。这是 Resolve opaque archetype 算法的第 3 步。

#### AST Demangler

关键源文件：

- `include/swift/AST/ASTDemangler.h`
- `lib/AST/ASTDemangler.cpp`

Opaque Type Witnesses 一节没说的是，`@_opaqueReturnTypeOf` 里的 mangled name 可以引用另一个 module 的 opaque archetype。这种情况下我们不查按 source file 的列表，而是去问「AST demangler」。

**`ASTBuilder::resolveOpaqueType()`**：若 mangled name 引用 main module，就在相应的 `SourceFile` 上调用 `lookupOpaqueResultType()`；否则走另一条路径。

### Runtime Representation

关键源文件：

- `lib/IRGen/GenMeta.cpp`
- `stdlib/public/runtime/MetadataLookup.cpp`

**`IRGenModule::emitOpaqueTypeDecl()`**：发出一个 opaque type descriptor。

**`swift_getOpaqueTypeMetadata2()`**：runtime 入口，为 opaque type descriptor 的 underlying type substitution map 里的某个 replacement type 构造 runtime type metadata。

**`swift_getOpaqueTypeConformance2()`**：runtime 入口，为 opaque type descriptor 的 underlying type substitution map 里的某个 conformance 构造 witness table。

#### Specialization

关键源文件：

- `include/swift/AST/Type.h`
- `lib/AST/TypeSubstitution.cpp`

**`TypeExpansionContext`**：把 declaration context 与 `@inlinable` 标志编码在一起的数据类型。

**`swift::substOpaqueTypesWithUnderlyingTypes()`**：这个函数针对 type、conformance 和 substitution map 的三个重载，实现了上面三个 specialization 算法。每个重载也接收一个 `TypeExpansionContext`。
