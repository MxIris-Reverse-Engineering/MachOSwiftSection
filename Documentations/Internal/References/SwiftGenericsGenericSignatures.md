# Generic Signatures（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/generic-signatures.tex`（《Compiling Swift Generics》一书的「Generic Signatures」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这是全书的理论核心，也是本库（MachOSwiftSection）逆向 generic signature 的直接依据。二进制里的 generic context descriptor 存的正是本章定义的那套东西——一串 generic parameter 加一串 requirement；requirement 的四种 kind（conformance / same-type / superclass / layout）、它们的排列顺序、以及 same-type requirement 哪一边写 reduced type，都由本章的 type parameter order 和 reduced type 定义决定。本章末尾的 generic signature query 是编译器回答「这个 type parameter conform 到什么」「它的 reduced type 是什么」的统一接口，本库在没有编译器的前提下重实现了其中一部分。译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（generic signature、requirement signature、explicit requirement、derived requirement、elementary statement、inference rule、derivation、valid type parameter、reduced type、reduced type equality、equivalence class、bound / unbound type parameter、type parameter order、generic signature query、canonical……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)） 的 Local Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本 + Unicode）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 canonical generic parameter type。原书的 `T` 记作 `τ_0_0`，`U` 记作 `τ_0_1`，`V` 记作 `τ_0_2` |
> | `[T: P]` | conformance requirement：`T` conform 到 protocol `P` |
> | `[T == U]` | same-type requirement。右边是 concrete type 时（`[T == X]`）称作 concrete same-type requirement |
> | `[T: C]` | superclass requirement，`C` 是 class type |
> | `[T: AnyObject]` | layout requirement |
> | `[Self.U: Q]_P` | protocol `P` 的 **associated** conformance requirement（下标标出它属于哪个 protocol 的 requirement signature） |
> | `[Self.U == Self.V]_P` | `P` 的 associated same-type requirement |
> | `G ⊢ D` | 「`D` 属于 `G` 的 theory」，即 `D` 可以从 generic signature `G` 推导出来。`D` 是一条 requirement 或一个 type parameter |
> | `G_P` | protocol `P` 的 protocol generic signature，即 `<Self where Self: P>` |
> | `T.A` | unbound dependent member type（只指向标识符 `A`） |
> | `T.[P]A` | bound dependent member type（指向 protocol `P` 的 associated type declaration `A`） |
> | `\|T\|` | type parameter `T` 的 length |
> | `T.SubSequence^n` | 把 `.SubSequence` 接在 `T` 后面 `n` 次；`n = 0` 时就是 `T` |
> | `X′`、`C′` | 把 `Self` 换成 `T` 之后得到的 concrete type / class type |
> | `⟦T⟧` | `T` 的 equivalence class；在 `archetypes.tex` 里同一个记号也用来表示 `T` 对应的 archetype |
> | `<`、`≤`、`≥` | type parameter order（以及一般的 partial order / linear order） |
> | `∈`、`∉`、`⊆`、`∪`、`∩`、`×`、`∅`、`≠` | 集合记号：属于、不属于、子集、并、交、Cartesian product、空集、不等 |
> | `ℕ`、`ℤ`、`ℚ` | 自然数、整数、有理数 |
> | `requiresProtocol(G, T, P)` | generic signature query，写成「函数名(参数)」的形式 |

---

**Generic signature** 是一类语义对象，描述 generic declaration 的类型检查行为。声明可以嵌套，而外层的 generic parameter 在内层声明里是可见的，所以 generic signature 是一种「拍平」的表示：它把在该声明作用域内生效的所有 **generic parameter type** 和 **requirement** 收集到一起。这样就把上一章讲的具体语法抽象掉了：

- Generic parameter type 列表从所有外层 generic parameter 开始，其后是显式 generic parameter 列表 `<...>` 里的参数，以及由 opaque parameter declaration 隐式引入的 generic parameter type——比如 `func f(_: some P)` 里的那个 `some P`。
- Generic signature 的 requirement 列表包含外层 generic declaration 写下的 requirement，也包含来自 generic parameter inheritance clause、trailing `where` clause 和 opaque parameter 的 requirement。还有第四种来源叫 requirement inference，见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Requirement Inference 一节。

全书以及编译器的调试输出都用下面这种记法来写 generic signature：

```
<A, B, C, ... where A: Sequence, B: Equatable, A.Element == Int, ...>
 └── generic parameter ──┘ └────────── requirement ──────────────┘
```

Generic signature 里的 requirement 与 trailing `where` clause 里的 requirement 用同一套语义表示，即 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 给出的 requirement 定义，只是多几条额外性质：generic signature 总是把列表里所有冗余的 requirement 去掉，剩下的那些也会被改写成「尽可能简单」的形式。这一点会在 `building-generic-signatures.tex` 里讲透——那一章说明一个声明的 generic signature 是怎么从上一章描述的语法形式构造出来的。眼下我们只假设手里已经有一个现成的 generic signature。

铺垫之后，本章的 Derived Requirements 一节会引入一套用来推理 requirement 和 type parameter 的形式系统。它把此前提到的**声明的 interface type** 这个概念讲精确：interface type 里含有 type parameter，而这些 type parameter 的合法性可以从声明的 generic signature 推导出来。本章的 Generic Signature Queries 一节描述 **generic signature query**——它们是实现里的基本原语，编译器其余部分靠它们回答关于 generic signature 的问题。这些问题会用我们的形式系统精确地叙述出来。

### Debugging

`-debug-generic-signatures` 这个 frontend flag 让我们得以一窥泛型实现的内部：它会打印每个正在被类型检查的声明的 generic signature。下面是一个有三层嵌套 generic declaration 的简单程序：

```swift
struct Outer<T: Sequence> {
  struct Inner<U> {
    func transform() where T.Element == U {
      ...
    }
  }
}
```

带上这个 flag 编译，可以看到每一层嵌套的 generic signature 都纳入了外层声明的 generic signature 的全部信息：

```
debug.(file).Outer@debug.swift:1:8
Generic signature: <T where T : Sequence>

debug.(file).Outer.Inner@debug.swift:2:10
Generic signature: <T, U where T : Sequence>

debug.(file).Outer.Inner.transform()@debug.swift:3:10
Generic signature: <T, U where T : Sequence, U == T.[Sequence]Element>
```

这个 flag 还让我们能观察到 **requirement minimization**。下面三个函数各自对一对 conform 到 `Sequence` 的类型做泛型：

```swift
func sameElt<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Element == S2.Element {...}

func sameIter<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Iterator == S2.Iterator {...}

func sameEltAndIter<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Element == S2.Element,
          S1.Iterator == S2.Iterator {...}
```

第一个函数要求两个 sequence 有相同的 `Element` associated type，例如可以这样调用：`sameElt(Array<Int>(), Set<Int>())`。第二个函数要求两者的 `Iterator` 类型相同。第三个函数同时要求这两个条件，但由于标准库里 `Sequence` 的声明方式，第二个条件其实强于第一个：如果两个 sequence 的 `Iterator` 类型相同，那它们的 `Element` 类型**也**相同。换句话说，same-type requirement `[S1.Element == S2.Element]` 在 `sameEltAndIter()` 里是**冗余的**。（本章后面 The SameName Rule 那个例子重新讨论这个 generic signature 时，我们会真正**证明**这个事实。）用 `-debug-generic-signatures` 编译这个程序，会看到 `sameElt()` 的 generic signature 与另外两个不同，而 `sameIter()` 与 `sameEltAndIter()` 的 generic signature 长这样：

```
<S1, S2 where S1: Sequence, S2: Sequence,
              S1.[Sequence]Iterator == S2.[Sequence]Iterator>
```

Requirement minimization 见 `building-generic-signatures.tex` 的 Requirement Minimization 一节。

### Canonical signatures

Generic signature 是不可变且唯一化（uniqued）的，所以结构相同、类型逐个指针相等的两个 generic signature 一定是同一个指针。虽然 generic signature 里的 requirement 已经最小化并按某种顺序排好，两个在其他方面完全相同的 generic signature 仍可能在 type sugar 上有差别。如果一个 generic signature 列出的所有 generic parameter type 都是 canonical 的，且 requirement 里出现的所有类型也都是 canonical 的，我们就说它是 **canonical** 的。要从任意一个 generic signature 算出它的 canonical signature，把签名里出现的 sugared type 全部换成 canonical type 即可。由此得到 generic signature 的 canonical equality：两个 generic signature 是 canonically equal 的，当且仅当它们的 canonical signature 指针相等。

上面 `sameIter()` 和 `sameEltAndIter()` 的 generic signature 是 canonically equal 的，但不是指针相等：它们的 generic parameter **名字**相同，但 sugared generic parameter type 指向的是实际的**声明**，而那是两个不同的声明。它们的 canonical signature 长这样：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
           τ_0_0.[Sequence]Iterator == τ_0_1.[Sequence]Iterator>
```

### Empty generic signature

一个既没有 generic parameter 列表也没有 trailing `where` clause 的 generic declaration，直接继承父上下文的 generic signature。如果没有任何外层父上下文是 generic 的，我们得到的就是 **empty generic signature**，它既无 generic parameter 也无 requirement。Empty generic signature 描述的 interface type 就是 fully-concrete type，即不含任何 type parameter 的类型。

### Protocol generic signature

`declarations.tex` 的 Protocols 一节讲过，每个 protocol declaration 都有一个名为 `Self` 的 generic parameter，它 conform 到这个 protocol 自身。Protocol 的 `Self` 类型在 canonical 意义下总是等于 `τ_0_0`。我们把 protocol `P` 的 **protocol generic signature** 记作 `G_P`：

```
G_P := <Self where Self: P>
```

## Requirement Signatures

每个 protocol 都有一个 **requirement signature**，它收集该 protocol 的 associated type declaration 以及施加在它们身上的 **associated requirement**。这同样把 `declarations.tex` 的 Protocols 一节讲的具体语法抽象掉了。Generic signature 与 requirement signature 之间存在一种对偶，下表把两类实体逐项对照，并各给一个具体样例以便回忆记法：

| **Generic signature** | **Requirement signature** |
|---|---|
| Generic parameter： | Associated type： |
| `τ_0_1` | `associatedtype Iterator` |
| Generic requirement： | Associated requirement： |
| `[τ_0_1: Sequence]` | `[Self.Iterator: IteratorProtocol]_Sequence` |

（Requirement signature 还描述 protocol 的 type alias 成员，这些叫做 **protocol type alias**。它们不属于下一节要讲的那套形式系统，会在 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Protocol Type Aliases 一节讨论。）

如果 generic signature `G` 写有一条 conformance requirement `[T: P]`，那么 `P` 的 requirement signature 会衍生出额外的结构。先非形式地说：

- 对 `P` 的每个 associated type `A`，我们都可以谈论 dependent member type `T.[P]A`，它抽象的是 conformance 里的那个 type witness。
- 由于 associated requirement 被每一个具体的 conforming type 满足，它们「相对于」抽象的 type parameter `T` 也成立。

因此，要解释一个 generic signature，我们可能需要查阅它所「依赖」的某一批 protocol 的 requirement signature。究竟是**哪些** protocol，由 `basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)） 的 Protocol Components 一节说清楚；眼下我们可以认为 generic signature 活在「name lookup 能看到的全体 protocol」这个宇宙里——也就是源程序和所有序列化模块里声明的 protocol。这个集合总是有限的。

回忆一下，protocol `P` 的 protocol generic signature 只有一条 conformance requirement `[Self: P]`；因此 `P` 的 protocol generic signature 是能让我们「往 `P` 的 requirement signature 里看」的最简单的 generic signature。

`-debug-generic-signatures` 这个 frontend flag 在类型检查每个 protocol 时也会打印它的 requirement signature。虽然打印时我们把 requirement signature 写成一个只有 `Self` 一个 generic parameter 的 generic signature，但在理论上和实现上，requirement signature 与 generic signature 是两种不同的东西。

**例（推导 requirement 的动机）.** 回忆 `Sequence` protocol 写有两条 associated requirement：

```
[Self.Iterator: IteratorProtocol]_Sequence
[Self.Element == Self.Iterator.Element]_Sequence
```

为了给下一节要引入的形式系统作铺垫，我们来看：在一个写了对某 protocol 的 conformance requirement 的 generic declaration 内部，这个 protocol 的 associated requirement 是怎样被观察到的。下面这个 generic function 写了对 `Sequence` 的 conformance requirement——实际上写了两条：

```swift
func firstTwoEqual<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Element == S2.Element, S1.Element: Equatable {
  var iter1 = s1.makeIterator()
  var iter2 = s2.makeIterator()
  return iter1.next()! == iter2.next()!
}
```

这里我们不用 sugared 的 generic parameter type `S1` 和 `S2`，而用 canonical type，以强调 type sugar 没有语义作用。`firstTwoEqual()` 的 generic signature 是：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Element: Equatable,
                    τ_0_0.Element == τ_0_1.Element>
```

类型检查函数体时，大致会发生下面这些事：

1. `s1` 的类型是 `τ_0_0`，它 conform 到 `Sequence`，所以有一个可以调用的 `makeIterator()` 方法。
2. 这个方法返回 `Self.Iterator`。把 `Self` 代换成 `τ_0_0`，得出 `iter1` 的类型是 `τ_0_0.Iterator`。
3. 同理，`iter2` 的类型是 `τ_0_1.Iterator`。

接着看子表达式 `iter1.next()!`：

1. `Sequence` 的 requirement signature 告诉我们 `τ_0_0.Iterator` conform 到 `IteratorProtocol`，所以它有一个 `next()` 方法。
2. 这个方法返回 `Optional<Self.Element>`，把 `Self` 代换成 `τ_0_0.Iterator`，得到 `Optional<τ_0_0.Iterator.Element>`。
3. 强制解包表达式的类型于是是 `τ_0_0.Iterator.Element`。

同样的分析表明 `iter2.next()!` 的类型是 `τ_0_1.Iterator.Element`。再看 `Equatable` protocol 里 `==` 运算符的 interface type：

```
<Self where Self: Equatable> (Self, Self) -> Bool
```

要类型检查表达式 `iter1.next()! == iter2.next()!`，编译器必须证明下面这两条 requirement 是我们这个 generic signature 的显式 requirement（连同 `Sequence` 的 requirement signature）的推论：

```
[τ_0_0.Iterator.Element == τ_0_1.Iterator.Element]
[τ_0_0.Iterator.Element: Equatable]
```

我们首先会把这句话的含义形式化，办法是定义一个 generic signature 的 **derived requirement** 集合。然后在 The Requirement Machine 那一部分（`basic-operation.tex` 起），我们会描述一个**判定过程**（decision procedure），它能告诉我们某条 requirement 是否可以推导出来。对上面两条 requirement 它会给出肯定回答，而对下面这条就会给出否定回答——它不是我们这个签名的推论：

```
[τ_0_0.Iterator: Equatable]
```

我们的判定过程还会告诉我们：`τ_0_0.Iterator.Element` 是一个 valid type parameter，而 `τ_0_0.Element.Iterator` 这样的东西不是。

## Derived Requirements

接下来三节定义一个 generic signature 的 **derived requirement** 与 **valid type parameter**。有了它们，我们就能把「编译器在类型检查 generic declaration 时必须能回答哪些关于 generic signature 的问题」这件事精确地叙述出来。

做法是在一套演绎推理系统——也就是数理逻辑里研究的那种**形式系统**（Curry 1977，《Foundations of Mathematical Logic》）——里工作。我们的形式系统是相对于一个固定的 generic signature `G` 定义的，所以每个 generic signature 都有自己对应的一套形式系统。一个形式系统由三部分组成，下面稍作非形式的描述：

1. 对系统中所有可能的**语句**（statement）的刻画：它们由一组固定的符号有限组合而成。

   我们的语句就是 requirement（例如 `[τ_0_0.Element: Equatable]`）和 type parameter（例如 `τ_0_1.Iterator`）；如前所见，它们的语法结构相当简单。

2. 一组有限的、被假定为真的 **elementary statement**。

   我们的 elementary statement 就是 generic signature `G` 的 generic parameter 和 explicit requirement：所有 generic parameter 都是 valid type parameter，所有 explicit requirement 都平凡地「已推导」。

3. 一套 **inference rule** 的说明，规定如何从已有语句推出新语句，而这种推导只依赖语句的形式语法结构。

   Requirement 与 type parameter 的 inference rule 马上就会给出。

一个形式系统的 **theory**，是我们能在该系统内证明的全部语句的集合。它总是包含 elementary statement，但不应该包含**所有**可能的语句。（一个「什么都为真」的 theory 什么也解释不了。）

一个 generic signature 的 theory，是它的 derived requirement 与 valid type parameter 的并集。要证明某个语句属于这个集合，我们写下一个 **derivation**——一列有限的步骤，构造性地证明目标语句是该形式系统的推论：

1. Derivation 必然以推出一条或多条 elementary statement 开始。
2. 其后是零步或多步，每步用 inference rule 从此前的语句推出新语句。
3. Derivation 以证明结论的最后一步结束。（换个角度，如果把每一中间步骤的结论**都**算上，也可以认为一个 derivation 同时证明了多个结论。）

证明同一件事可以有很多种写法，而且我们允许写「没用的」步骤——其结论根本没被用到，所以 derivation 一般并不唯一。写下 derivation 的意义在于我们可以**逐步检查**推理，从而确信结论确实是 theory 里的真语句。

给实践者的一点提醒：我们用这套形式系统来**规定**实现的各种行为，但编译器本身并不把 derivation 直接编码成数据结构。（`symbols-terms-and-rules.tex` 会讲到，我们是把 derived requirement 与 valid type parameter 的推理翻译成一个**字符串重写**问题来处理的。）

### Notation

一个 **derivation step** 总是写成一行，结论在前；然后在右侧写这一步的「种类」（用小型大写字母表示），后面跟着前提列表。结论和前提都是语句：

```
结论                                              （Kind 前提）
```

**Elementary derivation step** 没有前提，所以它证明的是一条 elementary statement。其他种类的 derivation step 则是把一条 inference rule 应用到一个或多个前提上，而这些前提本身是此前某些步骤的结论。在讨论某个具体 derivation step 时，我们把前提就地写出来。在列出一整个 derivation 时，为求简洁，我们给每一步**编号**，并用编号来指代此前某步的结论：

```
1. 某条「Pooh」类的 elementary statement            （Pooh）
2. 由上一步按「Piglet」原理得到的推论                 （Piglet 1）
```

我们用「turnstile 算子」`⊢` 作为谓词。若 `G` 是一个 generic signature，`D` 是一条 requirement 或一个 type parameter，则 `G ⊢ D` 表示 `D` 是 `G` 的 theory 的一个元素，用法形如「若 `G ⊢ D`，则……」。

我们的形式系统有 6 种 elementary statement 和 17 条 inference rule；本节与后两节会把它们全部讲一遍：

1. 我们从 conformance requirement 和 type parameter 之间的 same-type requirement 开始。这个 theory 完整描述了语言中这一子集的行为。我们也会把其余几种 requirement kind 勾勒一下。
2. 本章的 Valid Type Parameters 一节会定义更多 inference rule，使得一个 generic signature 的 derived same-type requirement 在它的 type parameter 上生成一个 equivalence relation。我们会研究这个关系生成的 equivalence class。
3. 一开始我们只考虑由 unbound dependent member type 构成的 type parameter。本章的 Bound Type Parameters 一节会把 theory 扩展到 bound dependent member type，不过这一步不会带来任何本质上的新东西。

### Elementary statements

设 `G` 是一个 generic signature。`G` 的每个 generic parameter `τ_d_i` 都可以推出（**Generic**）：

```
τ_d_i                                             （Generic）
```

设 `[T: P]` 是 `G` 的一条显式 conformance requirement，于是 `T` 是某个 type parameter，`P` 是一个 protocol。我们可以推出这条 requirement（**Conf**）：

```
[T: P]                                            （Conf）
```

设 `[T == U]` 是 `G` 的一条显式 same-type requirement，`T` 与 `U` 都是 type parameter。我们可以推出这条 requirement（**Same**）：

```
[T == U]                                          （Same）
```

### Requirement signatures

现在假设我们已经为某个 type parameter `T` 和 protocol `P` 推出了一条具体的 conformance requirement `[T: P]`。`P` 的 requirement signature 的每一个元素都定义一条 inference rule，用来生成新的语句：

```
[T: P] + P 的 requirement signature = 更多语句
```

这三类 inference rule 是 **AssocName**、**AssocConf** 和 **AssocSame**。它们对应 requirement signature 的元素，正如 **Generic**、**Conf**、**Same** 这三种 elementary statement 对应 generic signature 的元素。

从 `P` 的每个 associated type declaration `A`，**AssocName** 这条 inference rule 推出 unbound dependent member type `T.A`，其 base type 是 `T`、标识符是 `A`。注意这一步是其前提的推论，而前提就是那条原始的 conformance requirement：

```
T.A                                               （AssocName，前提 [T: P]）
```

从 `P` 的每条 associated conformance requirement，**AssocConf** 这条 inference rule 推出一条 conformance requirement——把 `Self` 代换成 `T` 之后得到的那条。一条任意的 associated conformance requirement 形如 `[Self.U: Q]_P`，其中 `Self.U` 是某个 type parameter、`Q` 是某个 protocol。上面说的代换后的 type parameter 就记作 `T.U`：

```
[T.U: Q]                                          （AssocConf，前提 [Self.U: Q]_P、[T: P]）
```

从 `P` 的每条 associated same-type requirement，**AssocSame** 这条 inference rule 通过把 `Self` 代换成 `T` 推出一条新的 same-type requirement。Associated same-type requirement 最一般的形式是 `[Self.U == Self.V]_P`，其中 `Self.U` 与 `Self.V` 都是 type parameter，所以我们从两个代换后的 type parameter `T.U` 和 `T.V` 构造出一条 same-type requirement：

```
[T.U == T.V]                                      （AssocSame，前提 [Self.U == Self.V]_P、[T: P]）
```

在一个固定的 generic signature 里列出 derivation 时，我们会把前提中的那条 associated requirement 省略掉，因为这样做不会产生歧义。

关于上面用到的那些元语法变量（`T`、`U` 等）再说几句。在 elementary derivation step 的结论里，它们给出的是 `G` 的一条显式 requirement 的最一般形式；也就是说，我们有一组固定的 elementary derivation step，每一个都可以通过把具体实体适当地代入 `T`、`U`、`P` 而从这个模式得到。而当元语法变量出现在 derivation step 的**前提**里（如上所示）时，含义不同——这时我们是在用模式匹配的方式定义 inference rule：只要元语法变量的某种适当代换能把每个前提匹配到此前某步的结论，我们就可以使用这条规则。

Associated requirement 内部的 type parameter 的一般形式之所以记作 `Self.U`，是因为它是 protocol generic signature `G_P` 的一个 type parameter，因而必然是 `Self` 被递归地包进 dependent member type **零**次或多次的结果。这意味着 `Self` 本身也是 `Self.U` 的一个合法代换。这一点在 protocol inheritance 时会用到：若 `Derived` 继承自 `Base`，我们就有 associated requirement `[Self: Base]_Derived`。给定一个 `[T: Derived]` 的 derivation，只要为 `[Self: Base]_Derived` 添一个 **AssocConf** derivation step，就得到 `[T: Base]` 的 derivation。

**例（推导 equivalence 的动机）.** 目前给出的 inference rule 已经能证明一些有意思的语句了，但还不足以解释前面那个非形式概述（「推导 requirement 的动机」那个例子）里的全部内容。回到那个例子的 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Element: Equatable,
                    τ_0_0.Element == τ_0_1.Element>
```

`Sequence` protocol 声明了 `Iterator` 和 `Element` 两个 associated type，而 `τ_0_0` conform 到 `Sequence`，所以我们可以推出 `τ_0_0.Element`：

```
1. [τ_0_0: Sequence]                              （Conf）
2. τ_0_0.Element                                  （AssocName，前提 1）
```

`τ_0_0.Iterator` 同理。现在考虑 `τ_0_0.Iterator.Element`。回忆 `Sequence` 声明了两条 associated requirement：

```
[Self.Iterator: IteratorProtocol]_Sequence
[Self.Element == Self.Iterator.Element]_Sequence
```

第一条 associated requirement 让我们推出 `τ_0_0.Iterator` conform 到 `IteratorProtocol`，由此再推出 `τ_0_0.Iterator.Element`：

```
1. [τ_0_0: Sequence]                              （Conf）
2. [τ_0_0.Iterator: IteratorProtocol]             （AssocConf，前提 1）
3. τ_0_0.Iterator.Element                         （AssocName，前提 2）
```

从 `[τ_0_1: Sequence]` 出发，同样可以推出 `τ_0_1.Iterator.Element`：

```
1. [τ_0_1: Sequence]                              （Conf）
2. [τ_0_1.Iterator: IteratorProtocol]             （AssocConf，前提 1）
3. τ_0_1.Iterator.Element                         （AssocName，前提 2）
```

回忆一下，我们在「推导 requirement 的动机」那个例子里的原始目标，是要在 `τ_0_0.Iterator.Element` 与 `τ_0_1.Iterator.Element` 之间建立一条 same-type requirement，而不只是证明这两个 type parameter 存在。我们来试着写出一个 derivation。`Sequence` 的 associated same-type requirement 给了我们一条介于 `τ_0_0.Element` 与 `τ_0_0.Iterator.Element` 之间的 same-type requirement：

```
1. [τ_0_0: Sequence]                              （Conf）
2. [τ_0_0.Element == τ_0_0.Iterator.Element]      （AssocSame，前提 1）
```

关于 `τ_0_1` 也能推出类似的语句：

```
3. [τ_0_1: Sequence]                              （Conf）
4. [τ_0_1.Element == τ_0_1.Iterator.Element]      （AssocSame，前提 1）
```

> 译注：原书这里第 4 步的前提写作 1，但 **AssocSame** 需要的是 `[τ_0_1: Sequence]`，即第 3 步；本章后面重复这同一段 derivation 时写的正是「前提 3」，故此处疑为笔误，以「前提 3」为准。

别忘了我们还有一条显式的 same-type requirement：

```
5. [τ_0_0.Element == τ_0_1.Element]               （Same）
```

到此为止，我们手上有 (2)、(4)、(5) 三条 same-type requirement，但还没有任何办法推出别的东西：

```
[τ_0_0.Element == τ_0_0.Iterator.Element]
[τ_0_1.Element == τ_0_1.Iterator.Element]
[τ_0_0.Element == τ_0_1.Element]
```

这个例子先放一放，下一节引入更多处理 type parameter 之间 same-type requirement 的 inference rule 之后再回来。

### Other requirements

现在我们把形式系统扩展到 concrete same-type requirement、superclass requirement 和 layout requirement，但要事先声明：扩展后的这套 theory 是**不完备的**。这些规则作出的推断都是正确的，但它们并没有描述这几种 requirement kind 已实现行为的全部。本章的 Generic Signature Queries 一节以及 `building-generic-signatures.tex` 的 Requirement Minimization 一节会给出不完备的例子。

我们再添几条 elementary statement。设 `G` 是一个 generic signature。若 `[T == X]` 是 `G` 的一条显式 same-type requirement，其中 `T` 是 type parameter、`X` 是 concrete type（即 `X` 本身不是 type parameter，但可以**含有** type parameter）（**Concrete**）：

```
[T == X]                                          （Concrete）
```

若 `[T: C]` 是 `G` 的一条显式 superclass requirement，其中 `C` 是一个 class type（**Super**）：

```
[T: C]                                            （Super）
```

若 `[T: AnyObject]` 是 `G` 的一条显式 layout requirement（**Layout**）：

```
[T: AnyObject]                                    （Layout）
```

> 译注：这四种 requirement kind——conformance、same-type、superclass、layout——正是二进制里 generic requirement descriptor 的四种 flag 取值；本库逐字节解读 opaque type descriptor 里 13 条 requirement 的过程见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

上面这几种 requirement 的 associated requirement 形式也各有对应的 inference rule，所以下文假设我们已经能为某个 `T` 和 `P` 推出 `[T: P]`。

假设 `P` 声明了一条 associated same-type requirement `[Self.U == X]_P`，其中 `Self.U` 是某 type parameter、`X` 是某 concrete type。把 `Self.U` 里的 `Self` 代换成 `T` 得到 type parameter `T.U`，把 `X` 里的 `Self` 代换成 `T` 得到 concrete type `X′`。于是可以推出（**AssocConcrete**）：

```
[T.U == X′]                                       （AssocConcrete，前提 [Self.U == X]_P、[T: P]）
```

对一条 associated superclass requirement `[Self.U: C]_P`，把 `C` 里的 `Self` 代换成 `T` 得到 `C′`（**AssocSuper**）：

```
[T.U: C′]                                         （AssocSuper，前提 [Self.U: C]_P、[T: P]）
```

最后，associated layout requirement 的右边没有任何东西可代换，所以我们推出的是关于 `T.U` 的同一条语句（**AssocLayout**）：

```
[T.U: AnyObject]                                  （AssocLayout，前提 [Self.U: AnyObject]_P、[T: P]）
```

至此，所有种类的 elementary statement 都已出现，但还有几条 inference rule 没定义。下面先把到目前为止见过的 elementary statement 和 inference rule 汇总一下：

| | | |
|---|---|---|
| **基本模型：** | | |
| **Generic** | **Conf** | **Same** |
| **AssocName** | **AssocConf** | **AssocSame** |
| **其他 requirement：** | | |
| **Concrete** | **Super** | **Layout** |
| **AssocConcrete** | **AssocSuper** | **AssocLayout** |

## Valid Type Parameters

本节细看能从一个 generic signature 推出的 valid type parameter。`types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 引入了 type parameter 的两种相等概念：canonical type equality 告诉我们两者的拼写是否相同；**reduced type equality** 则是相对于某个 generic signature 而言，它还把 same-type requirement 考虑在内。现在我们来定义 type parameter 上的 reduced type equality，并在本章的 Generic Signature Queries 一节把它推广到全体 interface type。

Reduced type equality 是一个 **equivalence relation**，所以先把这个概念复习一遍。给定一个固定的集合（称作 **domain**），一个 relation 刻画的是「一对元素之间可能具有的某种性质」。在编程语言里，relation 通常是一个接受一对值、返回真假的函数。而在数学里，我们把 relation 想成所有使该性质成立的**有序对** `(x, y)` 构成的集合。

**定义.** 设 `S` 是一个集合。以 `S` 为 domain 的 **relation** 是 Cartesian product `S × S` 的一个子集。

**定义.** **Equivalence relation** `R ⊆ S × S` 是自反、对称且传递的：

- 若对所有 `x ∈ S` 都有 `(x, x) ∈ R`，则称 `R` 是**自反的**（reflexive）。
- 若对所有 `x, y ∈ S`，`(x, y) ∈ R` 蕴含 `(y, x) ∈ R`，则称 `R` 是**对称的**（symmetric）。
- 若对所有 `x, y, z ∈ S`，`(x, y) ∈ R` 且 `(y, z) ∈ R` 蕴含 `(x, z) ∈ R`，则称 `R` 是**传递的**（transitive）。

把分数 `a/b` 想成一个纯形式的对象，即一对整数 `a`、`b`（`b ≠ 0`）。`1/2`、`2/4` 和 `(-3)/(-6)` 是三个不同的分数，但它们表示同一个比例——交叉相乘即可看出。于是我们有两个 equivalence relation：

- `a/b` 与 `c/d`「相同」，当且仅当 `a = b` 且 `c = d`。
- `a/b` 与 `c/d`「等价」，当且仅当 `ad = bc`。

**定义.** 设 `R` 是以 `S` 为 domain 的 equivalence relation，`x ∈ S`。`x` 的 **equivalence class**（记作 `⟦x⟧`）是所有满足 `(x, y) ∈ R` 的 `y ∈ S` 构成的集合。

在上面那个「比例等价」关系下，`1/2` 的 equivalence class 是所有形如 `n/2n` 的分数（`n` 取遍所有非零整数）。每个分数恰属于一个 equivalence class，所以这个 equivalence relation 把分数集合划分成一些互不相交的 equivalence class。现在提升一层抽象，考虑以这些 equivalence class 为**元素**的那个集合。它就是 `ℚ`，即**有理数**集合——两个等价的分数表示同一个有理数。这个构造对任何 equivalence relation 都能照做一遍。

**命题.** 设 `R` 是以 `S` 为 domain 的 equivalence relation。则 `R` 的 equivalence class 构成 `S` 的一个不相交划分。

**证明.** 需要确立两件事：

1. 每个 `x ∈ S` **至少**属于一个 equivalence class。
2. 每个 `x ∈ S` **至多**属于一个 equivalence class，也就是说，若对某 `y, z ∈ S` 有 `x ∈ ⟦y⟧` 且 `x ∈ ⟦z⟧`，则实际上 `⟦y⟧ = ⟦z⟧`（这是集合相等，意即两者元素相同）。

先看第一件。`R` 自反意味着对所有 `x ∈ S` 有 `(x, x) ∈ R`。按 `⟦x⟧` 的定义这就是 `x ∈ ⟦x⟧`，所以每个 `x` 至少是它**自己**那个 equivalence class `⟦x⟧` 的元素。

再看第二件。假设对某 `y, z ∈ S` 存在 `x ∈ ⟦y⟧ ∩ ⟦z⟧`。要证 `⟦y⟧ = ⟦z⟧`，我们证 `⟦y⟧ ⊆ ⟦z⟧` 且 `⟦z⟧ ⊆ ⟦y⟧`。为看出 `⟦y⟧ ⊆ ⟦z⟧`，任取一个元素 `t ∈ ⟦y⟧`，然后顺着一串等价关系推出 `t ∈ ⟦z⟧`：

1. `t ∈ ⟦y⟧` 且 `x ∈ ⟦y⟧`，所以 `(t, y) ∈ R`、`(x, y) ∈ R`。
2. `(x, y) ∈ R`，而 `R` 对称，所以 `(y, x) ∈ R`。
3. `(t, y) ∈ R`、`(y, x) ∈ R`，而 `R` 传递，所以 `(t, x) ∈ R`。
4. `(t, x) ∈ R`、`(x, z) ∈ R`，而 `R` 传递，所以 `(t, z) ∈ R`，即 `t ∈ ⟦z⟧`。

这给出 `⟦y⟧ ⊆ ⟦z⟧`。要证 `⟦z⟧ ⊆ ⟦y⟧`，只需把上面这段原样复制一遍，把出现的 `y` 和 `z` 互换即可。（遇到这种完全机械的情形，我们一般不把反方向的证明写出来。）

我们已经证明：若 `S` 的两个 equivalence class 至少有一个公共元素，它们就必定重合。剩下的唯一可能性就是这两个 equivalence class 不相交，即它们的交集是空集。注意这里三条定义性质我们全都用上了；一旦去掉自反性、对称性或传递性中的任何一条，结论就不再成立。

### Reduced type equality

现在我们在 type parameter 上定义一个 equivalence relation。我们希望这样说：如果能推出两个 type parameter 之间的一条 same-type requirement，它们就是等价的。

**定义.** 设 `G` 是一个 generic signature。`G` 的 valid type parameter 上的 **reduced type equality** 关系，是所有满足 `G ⊢ [T == U]` 的 type parameter 对 `T`、`U` 构成的集合。

要让这件事成立，我们必须为形式系统添三条新的 inference rule，对应 equivalence relation 的三条定义性公理。第一条规则说：若能推出 valid type parameter `T`，就能推出平凡的 same-type requirement `[T == T]`（**Reflex**）。注意这里是从一个 **type parameter** 推出一条 **requirement**；这是唯一一处可以这么做的地方：

```
[T == T]                                          （Reflex，前提 T）
```

其次，若能为 type parameter `T` 与 `U` 推出 same-type requirement `[T == U]`，就能推出反向的那条（**Sym**）：

```
[U == T]                                          （Sym，前提 [T == U]）
```

最后，若能推出两条 same-type requirement `[T == U]` 与 `[U == V]`，其中前者的右边与后者的左边相同，那么我们就能一步跨过去，推出一条从头连到尾的 same-type requirement（**Trans**）：

```
[T == V]                                          （Trans，前提 [T == U]、[U == V]）
```

有了这些新规则，立刻可以看出：

**命题.** Reduced type equality 是一个 equivalence relation。

**证明.** 每条公理都由对应的 inference rule 得到：

- （自反性）设 `T` 是 `G` 的一个 valid type parameter。给定 derivation `G ⊢ T`，经 **Reflex** 推出 `G ⊢ [T == T]`。于是 `T` 与自身等价。
- （对称性）设 `T` 与 `U` 等价。给定 derivation `G ⊢ [T == U]`，经 **Sym** 推出 `G ⊢ [U == T]`。于是 `U` 与 `T` 等价。
- （传递性）设 `T` 与 `U` 等价、`U` 与 `V` 等价。给定两个 derivation `G ⊢ [T == U]` 与 `G ⊢ [U == V]`，把它们首尾相接，经 **Trans** 推出 `G ⊢ [T == V]`。于是 `T` 与 `V` 等价。

我们刻意把这个关系的 domain 限制在 `G` 的 valid type parameter 上，而不是所有语法上能拼出来的 type parameter。若 `T` 是某个无法从 `G` 推出的非法 type parameter，我们就不能用 **Reflex** 推出 `[T == T]`，那样一来它就不再是 equivalence relation 了。

到目前为止，还没有什么能阻止我们推出一条 `[T == U]`，其中 `T` 或 `U` 本身并不可推导。真发生这种情况时，我们就把这个有序对排除在关系之外。眼下不必为此担心，因为 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节会说明：这类情形可以通过诊断用户写下的非法 requirement 来排除掉。

**例（推出 equivalence）.** 用这些 inference rule 可以推出更多 requirement。回到前面「推导 equivalence 的动机」那个例子，我们当时推到了 (2)、(4)、(5) 就卡住了：

```
1. [τ_0_0: Sequence]                              （Conf）
2. [τ_0_0.Element == τ_0_0.Iterator.Element]      （AssocSame，前提 1）
3. [τ_0_1: Sequence]                              （Conf）
4. [τ_0_1.Element == τ_0_1.Iterator.Element]      （AssocSame，前提 3）
5. [τ_0_0.Element == τ_0_1.Element]               （Same）
```

接下来这样做。对 (2) 应用 **Sym**，然后可以观察到 (6)、(5)、(4) 构成一条链——每一条的右边与下一条的左边相同。两次应用 **Trans** 就得到了我们想要的东西：

```
6. [τ_0_0.Iterator.Element == τ_0_0.Element]          （Sym，前提 2）
7. [τ_0_0.Iterator.Element == τ_0_1.Element]          （Trans，前提 6、5）
8. [τ_0_0.Iterator.Element == τ_0_1.Iterator.Element] （Trans，前提 7、4）
```

我们看到 `τ_0_0.Iterator.Element` 与 `τ_0_1.Iterator.Element` 等价。顺带还发现，我们这个 generic signature 有下面这四个单元素 equivalence class：

```
{τ_0_0}, {τ_0_1}, {τ_0_0.Iterator}, {τ_0_1.Iterator}
```

以及由其余四个 type parameter 组成的最后一个 equivalence class：

```
{τ_0_0.Element, τ_0_1.Element,
 τ_0_0.Iterator.Element, τ_0_1.Iterator.Element}
```

而要证明 `τ_0_0.Iterator.Element` conform 到 `Equatable`，还需要另一条规则。

### Compatibility

我们那个分数上的 equivalence relation 有一条有意思的性质：从一对 equivalence class 里各挑一个分数相加（或相乘等等），结果所在的 equivalence class 与代表元的选取无关。在 Swift 泛型里我们有一个类似的目标：一个 type parameter 的任何可观察行为——conform 到某个 protocol、有某个 superclass bound、被固定到某个 concrete type、有某个名字的 dependent member type——都应该只取决于它的 equivalence class，而不取决于它的「拼写」。

于是我们再一次挥动魔杖，通过添加新的 inference rule 来钦定 reduced type equality 具有这条性质。这些规则把 same-type requirement 与其他种类的 requirement 联系起来，办法是替换掉后者的 subject type。也就是说，若能推出 same-type requirement `[T == U]` 与 conformance requirement `[U: P]`，就能推出 `[T: P]`（**SameConf**）：

```
[T: P]                                            （SameConf，前提 [U: P]、[T == U]）
```

Same-type requirement `[T == U]` 与其他几种 requirement kind 也可以这样复合（**SameConcrete**、**SameSuper**、**SameLayout**）：

```
[T == X]                                          （SameConcrete，前提 [U == X]、[T == U]）
[T: C]                                            （SameSuper，前提 [U: C]、[T == U]）
[T: AnyObject]                                    （SameLayout，前提 [U: AnyObject]、[T == U]）
```

还有第二条 compatibility 条件。我们希望等价的 type parameter 有等价的 member type，具体如下。假设能推出 conformance requirement `[U: P]` 与 same-type requirement `[T == U]`。那么对 `P` 的每个 associated type `A`，都能推出 same-type requirement `[T.A == U.A]`（**SameName**）：

```
[T.A == U.A]                                      （SameName，前提 [U: P]、[T == U]）
```

针对 bound dependent member type 的 inference rule 还没讲，那是紧接着下一节的内容。除此之外，我们的形式系统已经完整了，所以再看几个例子，以说明刚添的这几条规则的合理性。

**例.** 接着「推出 equivalence」那个例子。既然已经看到 `τ_0_0.Element` 与 `τ_0_0.Iterator.Element` 等价，我们就可以用 **SameConf** 从 `[τ_0_0.Element: Equatable]` 推出 `[τ_0_0.Iterator.Element: Equatable]`：

```
1. [τ_0_0.Element: Equatable]                          （Conf）
2. [τ_0_0.Element == τ_0_0.Iterator.Element]           （AssocSame，前提 1）
3. [τ_0_0.Iterator.Element == τ_0_0.Element]           （Sym，前提 2）
3. [τ_0_0.Iterator.Element: Equatable]                 （SameConf，前提 1、3）
```

> 译注：原书这段 derivation 有两处笔误：第 2 步的前提写作 1，但 **AssocSame** 需要的是 `[τ_0_0: Sequence]`（该 derivation 未列出这一步）；最后一步的编号重复写成 3，应为 4。照译原文，以此注为准。

在我们这个 generic signature 里，**整个** equivalence class 都 conform 到 `Equatable`：

```
{τ_0_0.Element, τ_0_1.Element,
 τ_0_0.Iterator.Element, τ_0_1.Iterator.Element}
```

**例（SameName 规则）.** 要看 **SameName** 这条 inference rule 的实际作用，回忆本章开头 `sameIter()` 的 generic signature：

```
<S1, S2 where S1: Sequence, S2: Sequence,
              S1.Iterator == S2.Iterator>
```

我们还见过另一个声明 `sameIterAndElt()`，它同时写了这两条 requirement：

```
[τ_0_0.Iterator == τ_0_1.Iterator]
[τ_0_0.Element == τ_0_1.Element]
```

我们当时说，requirement minimization 会把第二条丢掉，因为它是冗余的，于是 `sameIterAndElt()` 得到与 `sameIter()` 相同的 generic signature。这意味着我们应该能在不把第二条 requirement 本身当作 elementary statement 的前提下把它推出来。做法是从 `[τ_0_0.Iterator == τ_0_1.Iterator]` 出发，应用 **SameName** 推出 same-type requirement (4)：

```
1. [τ_0_0.Iterator == τ_0_1.Iterator]                  （Same）
2. [τ_0_1: Sequence]                                   （Conf）
3. [τ_0_1.Iterator: Sequence]                          （AssocConf，前提 1）
4. [τ_0_0.Iterator.Element == τ_0_1.Iterator.Element]  （SameName，前提 3、1）
```

> 译注：原书这段 derivation 的第 3 步有两处笔误：结论应为 `[τ_0_1.Iterator: IteratorProtocol]`（**SameName** 要求的 protocol 必须声明 `Element`），前提应为 2 而非 1。另外这个例子里的函数名 `sameIterAndElt()` 在本章开头写作 `sameEltAndIter()`，指的是同一个声明。

然后借助 `Sequence` 的 associated same-type requirement，把 (4) 的两边都改写成短形式：

```
5. [τ_0_0: Sequence]                                   （Conf）
6. [τ_0_0.Element == τ_0_0.Iterator.Element]           （AssocSame，前提 5）
7. [τ_0_1.Element == τ_0_1.Iterator.Element]           （AssocSame，前提 2）
8. [τ_0_1.Iterator.Element == τ_0_1.Element]           （Sym，前提 7）
9. [τ_0_0.Element == τ_0_1.Iterator.Element]           （Trans，前提 6、4）
10. [τ_0_0.Element == τ_0_1.Element]                   （Trans，前提 9、8）
```

没有 **SameName**，这条 requirement 是推不出来的。

**例（protocol N）.** 我们可以造出一个有无穷多个 equivalence class 的 generic signature。先给出这个 protocol：

```swift
protocol N {
  associatedtype A: N
}
```

现在考虑 protocol generic signature `G_N`。反复用 **AssocConf** 这条 inference rule 配合 associated conformance requirement `[Self.A: N]_N`，就能从 `[τ_0_0: N]` 推出一个无穷的 conformance requirement 序列：

```
1. [τ_0_0: N]                                     （Conf）
2. [τ_0_0.A: N]                                   （AssocConf，前提 1）
3. [τ_0_0.A.A: N]                                 （AssocConf，前提 2）
4. ...
```

也能推出无穷多个 valid type parameter：

```
5. τ_0_0                                          （Generic）
6. τ_0_0.A                                        （AssocName，前提 2）
7. τ_0_0.A.A                                      （AssocName，前提 3）
8. ...
```

这些 type parameter 每一个都自成一个 equivalence class，因为我们推不出任何非平凡的 same-type requirement。于是我们证明了 `G_N` 定义了一个无穷的 equivalence class 集合。

**例（protocol Collection）.** 下面是标准库 `Collection` protocol 的一个简化形式：

```swift
protocol Collection: Sequence {
  associatedtype SubSequence: Collection
      where Element == SubSequence.Element
            SubSequence == SubSequence.SubSequence
}
```

这个 protocol 从 `Sequence` 继承了 `Element` 和 `Iterator` 两个 associated type，然后声明了一个新的 associated type，并写下这四条 associated requirement：

```
[Self: Sequence]_Collection
[Self.SubSequence: Collection]_Collection
[Self.Element == Self.SubSequence.Element]_Collection
[Self.SubSequence == Self.SubSequence.SubSequence]_Collection
```

这些 associated requirement 可以这样读：

1. 第一条 conformance requirement 说：所有 collection 都是 sequence。
2. 第二条 conformance requirement 说：一个 collection 的 subsequence 仍是一个 collection，具体类型可以不同。
3. 第一条 same-type requirement 说：任意 collection 的 subsequence 的 element 类型总与原 collection 相同。
4. 第二条 same-type requirement 说：subsequence 的 subsequence 必须与原 collection 的 subsequence 类型相同。

举例来说，`Array<Int>` 的 `SubSequence` 是 `ArraySlice<Int>`，而 `ArraySlice<Int>` 的 `SubSequence` 还是 `ArraySlice<Int>`。（具体 conformance 的 type witness 见 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Type Witnesses 一节。）

我们来看 protocol generic signature `G_Collection`，试着理解它的 equivalence class。利用 protocol inheritance 关系可以推出 `τ_0_0.Iterator`：

```
1. [τ_0_0: Collection]                            （Conf）
2. [τ_0_0: Sequence]                              （AssocConf，前提 1）
3. τ_0_0.Iterator                                 （AssocName，前提 2）
```

首先注意到，`τ_0_0` 和 `τ_0_0.Iterator` 既不互相等价，也不与任何其他 type parameter 等价。它们各自独占一个 equivalence class，这就是头两个 equivalence class。

要理解其余的 equivalence class 是怎么形成的，注意 `[Self.SubSequence: Collection]_Collection` 会生成一个无穷的 conformance requirement 族，就像上一个例子里的 `[Self.A: N]_N` 那样：

```
1. [τ_0_0: Collection]                                （Conf）
2. [τ_0_0.SubSequence: Collection]                    （AssocConf，前提 1）
3. [τ_0_0.SubSequence.SubSequence: Collection]        （AssocConf，前提 2）
4. ...
```

为了讨论这个现象，我们引入下面的记法：

```
τ_0_0.SubSequence^n := τ_0_0                            （n = 0）
                       τ_0_0.SubSequence                （n = 1）
                       τ_0_0.SubSequence^(n-1).SubSequence  （n > 1）
```

于是对所有 `n ≥ 0`，`G_Collection` 的 theory 都含有 `[τ_0_0.SubSequence^n: Collection]`。进一步，对每个 `n ≥ 0`，都可以从下面的 (1) 推出：

```
1. [τ_0_0.SubSequence^n: Collection]                                        （...）
2. [τ_0_0.SubSequence^n: Sequence]                                          （AssocConf，前提 1）
3. [τ_0_0.SubSequence^n.Element == τ_0_0.SubSequence^(n+1).Element]         （AssocSame，前提 1）
4. [τ_0_0.SubSequence^n.Element == τ_0_0.SubSequence^n.Iterator.Element]    （AssocSame，前提 2）
```

无穷族 (3) 与 (4) 定义出**一个** equivalence class。这个 equivalence class 对所有 `n ≥ 0` 含有 `τ_0_0.SubSequence^n.Element` 与 `τ_0_0.SubSequence^n.Iterator.Element`。（特别地，它含有 `τ_0_0.Element`。）

我们还能生成另一个无穷的 same-type requirement 族：

```
5. [τ_0_0.SubSequence^(n+1) == τ_0_0.SubSequence^(n+2)]   （AssocSame，前提 1）
```

由此得到一个含有 `τ_0_0.SubSequence^n`（`n ≥ 1`）的 equivalence class。最后，应用 **SameName** 再给我们一个无穷族：

```
6. [τ_0_0.SubSequence^(n+1).Iterator == τ_0_0.SubSequence^(n+2).Iterator]   （SameName，前提 5、2）
```

它们构成最后一个 equivalence class；`SubSequence` 的 `Iterator` 可以与原 sequence 的不同。

可见 `G_Collection` 定义了五个 equivalence class，其中三个各含无穷多个代表 type parameter：

```
(1) {τ_0_0}

(2) {τ_0_0.Element, τ_0_0.SubSequence.Element, ...}
    ∪ {τ_0_0.Iterator.Element, τ_0_0.SubSequence.Iterator.Element, ...}

(3) {τ_0_0.Iterator}

(4) {τ_0_0.SubSequence, τ_0_0.SubSequence.SubSequence, ...}

(5) {τ_0_0.SubSequence.Iterator,
     τ_0_0.SubSequence.SubSequence.Iterator,
     ...}
```

要描述施加在每个 equivalence class 上的 conformance requirement，只需为每一对（type parameter, protocol）组合挑一条代表性的 conformance requirement 就够了，因为 **SameConf** 这条 inference rule 能把其余的推出来。下表总结我们这次「纸笔调查」的结果：

| **代表元** | **conform 到** |
|---|---|
| `τ_0_0` | `Collection` 与 `Sequence` |
| `τ_0_0.Element` | 无 |
| `τ_0_0.Iterator` | `IteratorProtocol` |
| `τ_0_0.SubSequence` | `Collection` 与 `Sequence` |
| `τ_0_0.SubSequence.Iterator` | `IteratorProtocol` |

关于 generic signature `G_Collection`，基本上也就这些可说了。不过上面这套描述有个不足：它没能把 member type 之间的关系显示出来。`archetypes.tex` 的 The Type Parameter Graph 一节引入 **type parameter graph** 时会重新讨论这里出现过的所有 generic signature。那里会在 equivalence class 上定义一个边关系，让 equivalence class 成为图的顶点，从而给我们一个理解 member type 关系的可视化工具。

注意我们这套形式系统可以生成**无穷的** theory！我们看到 `G_N` 有一个无穷的有限 equivalence class 集合，而在 `G_Collection` 里 equivalence class 本身就是无穷的。当然两者可以同时发生：`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 A Swift Connection 一节会出现一个有无穷多个无穷 equivalence class 的 generic signature。

## Bound Type Parameters

`types.tex` 的 Fundamental Types 一节讲过，dependent member type 有两种：

- **Unbound** dependent member type 指向一个标识符，记作 `T.A`，其中 `T` 是某 base type、`A` 是标识符。
- **Bound** dependent member type 指向一个 associated type declaration，记作 `T.[P]A`，其中 `T` 是某 base type、`A` 是某 protocol `P` 的 associated type declaration。

**定义.** 为方便起见定义如下：

- **Unbound type parameter** 指 generic parameter type，或者 base type 是另一个 unbound type parameter 的 unbound dependent member type。
- **Bound type parameter** 指 generic parameter type，或者 base type 是另一个 bound type parameter 的 bound dependent member type。

Bound 与 unbound type parameter 并没有把全体 type parameter 穷尽地划分开。按上面的定义，generic parameter type **既是** bound 也是 unbound 的；而像 `τ_0_0.[Sequence]Iterator.Element` 这样的 type parameter 则既不是 bound 也不是 unbound 的，因为它混用了 bound 和 unbound 的 dependent member type。

这里的根本矛盾在于：

- Unbound type parameter 出现在 type resolution 解析 `where` clause 里的 requirement 的时候，它们直接代表用户写下的东西。
- Type substitution 只能作用于 bound dependent member type，因为正如 `conformances.tex` 的 Abstract Conformances 一节会讲到的那样，我们需要描述一个合法 type parameter 的全部三块信息：base type、protocol、以及 associated type declaration。

我们经常要把 substitution map 应用到 generic signature 和 requirement signature 的 requirement 上，以及声明的 interface type 上。确实，这些语义对象都只能含有 bound type parameter。我们这样化解矛盾：

- Requirement minimization（`building-generic-signatures.tex` 的 Requirement Minimization 一节）在构造 generic signature 时，把 `where` clause 里的 unbound type parameter 转成 bound type parameter。
- Generic signature query（本章 Generic Signature Queries 一节）接受 unbound type parameter。要从一个 unbound type parameter 拿到对应的 bound type parameter，向 generic signature 询问该 unbound type parameter 的 **reduced type** 即可。
- Type resolution 在解析一个声明的 interface type 时用 generic signature query 来构造 bound type parameter（`type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)））。

现在我们扩展形式系统来描述这些行为。照旧设 `G` 是一个 generic signature，并假设对某个 `T` 和 `P` 有 `G ⊢ [T: P]`。

先添一条类似 **AssocName** 的 inference rule，区别是它推出的是 bound dependent member type。从 `P` 的每个 associated type declaration `A`，**AssocDecl** 这条 inference rule 推出 bound dependent member type `T.[P]A`，其 base type 是 `T`，并指向 associated type declaration `A`：

```
T.[P]A                                            （AssocDecl，前提 [T: P]）
```

为了把 bound 与 unbound dependent member type 的等价性编码进来，我们再添一条 inference rule，在两者之间推出一条 same-type requirement。也就是说，从 `P` 的每个 associated type declaration `A`，**AssocBind** 这条 inference rule 在「同样前提下 **AssocDecl** 与 **AssocName** 各自会推出的那两个 dependent member type」之间推出一条 same-type requirement：

```
[T.[P]A == T.A]                                   （AssocBind，前提 [T: P]）
```

**SameName** 这条 inference rule——从 `[U: P]` 与 `[T == U]` 得到 `[T.A == U.A]`——也有一个 bound type parameter 版本。在同样的前提下，**SameDecl** 推出 `[T.[P]A == U.[P]A]`：

```
[T.[P]A == U.[P]A]                                （SameDecl，前提 [U: P]、[T == U]）
```

**SameDecl** 这条 inference rule 与其余所有规则有本质区别：引入它并不给 theory 贡献任何新语句。

**命题.** 任何含有 **SameDecl** 步骤的 derivation，都可以改写成不含该步骤的 derivation。

**证明.** 给定 `G ⊢ [U: P]` 与 `G ⊢ [T == U]`，对任意合适的 `T`、`U`、`P` 与 `A`，添上下面这些步骤即可在不用 **SameDecl** 的情况下推出 `[T.[P]A == U.[P]A]`：

```
1. [U: P]                                         （...）
2. [T == U]                                       （...）
3. [T.A == U.A]                                   （SameName，前提 1、2）
4. [U.[P]A == U.A]                                （AssocBind，前提 1）
5. [U.A == U.[P]A]                                （Sym，前提 4）
6. [T: P]                                         （SameConf，前提 1、2）
7. [T.[P]A == T.A]                                （AssocBind，前提 6）
8. [T.[P]A == U.A]                                （Trans，前提 7、3）
9. [T.[P]A == U.[P]A]                             （Trans，前提 8、5）
```

不过，每次需要这条等价关系时写 1 步显然比写 7 步方便。因此 **SameDecl** 是我们这套形式系统的语法糖。

**例.** 考虑 protocol generic signature `G_Sequence`，回忆 `Sequence` 写有两条 associated requirement：

```
[Self.Iterator: IteratorProtocol]_Sequence
[Self.Element == Self.Iterator.Element]_Sequence
```

我们先继续假装这些 associated requirement 是用 unbound type parameter 写的，但允许使用新的 inference rule。这样可以推出 bound type parameter `τ_0_0.[Sequence]Iterator.[IteratorProtocol]Element`：

```
1. [τ_0_0: Sequence]                                              （Conf）
2. [τ_0_0.Iterator: IteratorProtocol]                             （AssocConf，前提 1）
3. [τ_0_0.[Sequence]Iterator == τ_0_0.Iterator]                   （AssocBind，前提 1）
4. [τ_0_0.[Sequence]Iterator: IteratorProtocol]                   （SameConf，前提 2、3）
5. τ_0_0.[Sequence]Iterator.[IteratorProtocol]Element             （AssocDecl，前提 4）
```

(3) 和 (5) 用到了新的 inference rule。注意 (4) 很像我们那条 associated conformance requirement，只不过用的是 bound type parameter。

另一方面，我们也可以把形式系统定义成这样：generic signature 的 explicit requirement 和 protocol 的 associated requirement 都用 bound type parameter 写——实现里本来就是这么做的：

```
[Self.[Sequence]Iterator: IteratorProtocol]_Sequence
[Self.[Sequence]Element ==
     Self.[Sequence]Iterator.[IteratorProtocol]Element]_Sequence
```

这样 `τ_0_0.[Sequence]Iterator.[IteratorProtocol]Element` 的推导步骤就变少了：

```
1. [τ_0_0: Sequence]                                              （Conf）
2. [τ_0_0.[Sequence]Iterator: IteratorProtocol]                   （AssocConf，前提 1）
3. τ_0_0.[Sequence]Iterator.[IteratorProtocol]Element             （AssocDecl，前提 2）
```

这里还有一种对称性——从含 bound type parameter 的 associated requirement 出发，同样可以轻松推出 unbound type parameter `τ_0_0.Iterator.Element`：

```
1. [τ_0_0: Sequence]                                              （Conf）
2. [τ_0_0.[Sequence]Iterator: IteratorProtocol]                   （AssocConf，前提 1）
3. [τ_0_0.[Sequence]Iterator == τ_0_0.Iterator]                   （AssocBind，前提 1）
4. [τ_0_0.Iterator == τ_0_0.[Sequence]Iterator]                   （Sym，前提 3）
5. [τ_0_0.Iterator: IteratorProtocol]                             （SameConf，前提 2、4）
6. τ_0_0.Iterator.Element                                         （AssocName，前提 5）
```

事实上，`building-generic-signatures.tex` 里会证明下面两件事：

- 该章的一条定理会证明：valid type parameter 的每个 equivalence class 总是至少含有一个 bound type parameter 和至少一个 unbound type parameter。
- 该章的一条命题会告诉我们：一开始给出的 explicit requirement 列表，无论是用 bound 还是 unbound type parameter 写的，theory 都不变。

**例（AssocBind）.** 假设 generic parameter `τ_0_0` conform 到两个 protocol `P1` 和 `P2`，而两者都声明了一个名为 `A` 的 associated type。同一个 unbound dependent type `τ_0_0.A` 从任一条 conformance requirement 都能推出来，这在语言语义上实际等于把施加在 `A` 上的 associated requirement 合并了。加进 bound dependent member type 之后这一点依然成立，因为我们可以推出：

```
1. [τ_0_0: P1]                                    （Conf）
2. [τ_0_0.[P1]A == τ_0_0.A]                       （AssocBind，前提 1）
3. [τ_0_0: P2]                                    （Conf）
4. [τ_0_0.[P2]A == τ_0_0.A]                       （AssocBind，前提 3）
5. [τ_0_0.A == τ_0_0.[P2]A]                       （Sym，前提 4）
6. [τ_0_0.[P1]A == τ_0_0.[P2]A]                   （Trans，前提 2、5）
```

一个特例是第一个 protocol 继承自第二个。也就是说，把一个 inherited protocol 的 associated type declaration 重新声明一遍，不会改变 generic signature 的 equivalence class 结构。

Bound type parameter 看起来没带来任何新东西，那为什么要费这个事？因为一般情形下 type substitution 本来就必须发起 generic signature query，我们本可以每次分解 dependent member type 时都去查一次 generic signature。而现在这种表示等于是把某些信息预先算好，编码进 dependent member type 自身的结构里。这样在简单情形下就免去了 generic signature query，而我们的形式系统证明了两种做法是等价的。

### Summary

Derived requirement 形式系统里全部 elementary statement 与 inference rule 的完整汇总见 `derived-requirements-summary.tex`（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)）。Bound type parameter 从理论角度看是平凡的，而我们关于 concrete type requirement 的 theory 又是不完备的，所以今后我们主要使用下面这个子集：

| | | | |
|---|---|---|---|
| **Elementary statement：** | **Generic** | **Conf** | **Same** |
| **Inference rule：** | **AssocName** | **AssocConf** | **AssocSame** |
| | **Reflex** | **Sym** | **Trans** |
| | | **SameConf** | **SameName** |

到目前为止，我们只是用形式系统在一个固定的 generic signature **内部**推导具体语句。后面几章则会证明一些**关于** generic signature 本身的结果：

- `building-generic-signatures.tex` 描述我们如何诊断非法的 requirement，并证明：只要没有发出诊断，我们这套形式系统就有一个性质很好的 theory。
- `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 细看 derived conformance requirement，以此描述 dependent member type 的代换；特别地，我们会证明某个算法必定终止。
- `monoids.tex` 用 derived requirement 证明一个 Swift protocol 可以编码任意有限表现的 monoid，这说明 generic signature 的 theory 可以是不可判定的。
- `symbols-terms-and-rules.tex` 把 generic signature 的 explicit requirement 翻译成 rewrite rule，然后证明在这个映射下 derived requirement 对应于 **rewrite path**。这给出了实现的正确性证明。

## Reduced Type Parameters

一个 type parameter 的 equivalence class 可能是无穷的，也可能虽有限但很大。因此在实现里我们不能把 equivalence class 建模成一个集合。取而代之的做法是：定义一种从每个 equivalence class 中一致地挑出唯一代表元的办法，这个代表元称作该 equivalence class 的 **reduced type parameter**。Reduced type parameter 可以「代表」整个 equivalence class，而全体 reduced type parameter 则给出了 generic signature 的 equivalence class 结构的另一种描述。

继续上一节分数的类比：我们平时并不把一个有理数想成一个无穷的分数集合，而是在做完一串算术运算之后，通过消去分子分母的公因子把结果**约分**到最简。例如 `2/4` 和 `(-3)/(-6)` 都约分为 `1/2`，而 `1/2` 本身已是最简。这给了我们一个判断两个分数是否等价的新办法：把两者都约分，再看约分后的分数是否相同。一个关键事实是：我们可以通过给 equivalence class 的元素**排序**来找到那个最简分数——最简分数就是正分母最小的那个。

**定义.** **Partial order** `R ⊆ S × S` 是反自反且传递的：

- 若对所有 `x ∈ S` 都有 `(x, x) ∉ R`，则称 `R` 是**反自反的**（anti-reflexive）。
- 若 `(x, y) ∈ R` 且 `(y, z) ∈ R` 蕴含 `(x, z) ∈ R`，则称 `R` 是**传递的**。

当 `R` 由上下文可知时，我们用 `x < y` 代替 `(x, y) ∈ R`，用 `x ≮ y` 代替 `(x, y) ∉ R`。`>`、`≤`、`≥` 也按通常方式用 `<` 定义。

注意 `x < y` 与 `y < x` 不可能同时成立，否则由传递性可得 `x < x`，与「对所有 `x ∈ S` 有 `x ≮ x`」矛盾。因此在一个 partial order 里，对一对元素 `x, y ∈ S`，下面三者**至多**有一个成立：

1. `x = y`
2. `x < y`
3. `x > y`

若三者都不成立，我们就说 `x` 与 `y` 是**不可比的**（incomparable）。一般的 partial order 留到后面再说，眼下我们把注意力限制在「对任意一对元素，上述三条**恰好**有一条成立」的那种序上：

**定义.** **Linear order** 是没有不可比元素的 partial order。在 linear order 里，`x ≮ y` 就等于说 `x ≥ y`。

我们将在 type parameter 上定义一个 linear order，记作 `<`。它要表达这样一个想法：若 `G ⊢ [T == U]` 且 `T < U`，那么在这个同时包含两者的 equivalence class 里，`T` 比 `U`「更 reduced」。所有代表元中的最小者就是 reduced type parameter 本身。我们先来度量一个 type parameter 的「复杂度」，办法是数它的构造里用了多少个 dependent member type：

**定义.** Type parameter `T` 的 **length**（记作 `|T|`）是一个自然数。Generic parameter type 的 length 是 1，而 dependent member type `U.A` 或 `U.[P]A` 的 length 递归地定义为 `|U| + 1`。

我们希望 reduced type parameter 是 length 尽可能小的那一个，同时还希望能对它应用 substitution map，所以它应当是一个 bound type parameter。由此得出我们的 type parameter order 必须满足两个条件：

1. 若 `|T| < |U|`，则 `T < U`。
2. Bound dependent member type 排在 unbound dependent member type 之前。

**例.** 在前面「protocol Collection」那个例子里，我们研究了一个简化的 `Collection` protocol。我们看到 `G_Collection` 中 `τ_0_0.SubSequence` 的 equivalence class 含有一个 length 递增的无穷 type parameter 序列：

```
{τ_0_0.SubSequence^n}，n ≥ 1
```

加进 bound dependent member type 的 inference rule 之后，这个 equivalence class 还会含有下面这些：

```
{τ_0_0.[Collection]SubSequence^n}，n ≥ 1
```

（它也含有 bound 与 unbound「混合」的 type parameter。）这个 equivalence class 的 reduced type parameter 必定是 `τ_0_0.[Collection]SubSequence`。

`G_Collection` 的每个 equivalence class 都有唯一一个 length 最小的代表元，这一点对一般的 generic signature 并不总成立。这意味着：若两个等价的 type parameter length 相同，它们就只可能在 bound / unbound 上有区别，于是我们那两个条件就完全定下了每个 equivalence class 的 reduced type parameter：

```
τ_0_0
τ_0_0.[Sequence]Element
τ_0_0.[Sequence]Iterator
τ_0_0.[Collection]SubSequence
τ_0_0.[Collection]SubSequence.[Sequence]Iterator
```

（真正的 `Collection` protocol 除了这些 reduced type 之外，还定义了与 `Index` 和 `Indices` 这两个 associated type 相关的另外几个 equivalence class。）

一般来说我们还必须给 length 相同的 type parameter 排序，下面就来说这件事。下列算法都接受一对值 `x` 与 `y`，同时算出 `x < y`、`x > y` 还是 `x = y`。先从 generic parameter 开始——它们是 length 为 1 的 type parameter。

**算法（Generic parameter order）.** 输入两个 generic parameter type `τ_d_i` 与 `τ_D_I`。输出 `<`、`>`、`=` 三者之一。

1. 若 `d < D`，返回 `<`。
2. 若 `d > D`，返回 `>`。
3. 若 `d = D` 且 `i < I`，返回 `<`。
4. 若 `d = D` 且 `i > I`，返回 `>`。
5. 若 `d = D` 且 `i = I`，返回 `=`。

要给 dependent member type 排序，就必须先给 associated type declaration 排序；而要做到那一点，又必须先给 protocol declaration 排序。

**算法（Protocol order）.** 输入 protocol `P` 与 `Q`，输出 `<`、`>`、`=` 三者之一。

1. 用标识符上通常的字典序比较 `P` 与 `Q` 的父 module 名。若结果是 `<` 或 `>` 就返回。否则 `P` 与 `Q` 声明在同一个 module 里，继续下一步。
2. 比较 `P` 与 `Q` 的名字，若结果是 `<` 或 `>` 就返回。若 `P` 与 `Q` 其实是同一个 protocol，返回 `=`。否则这个程序是非法的，因为它声明了两个同名 protocol。此时可以用任意 tie-breaker，比如源码位置。

假设 `Barn` 模块声明了一个 `Horse` protocol，而 `Swift` 模块声明了 `Collection`。那么 `Horse` 排在 `Collection` 之前，因为两者声明在不同模块里，且 `Barn < Swift`。若 `Barn` 模块还声明了一个 `Saddle` protocol，则 `Horse < Saddle`，因为两者来自同一模块，于是比较它们的 protocol 名。

上一节我们证明了：把一个 inherited associated type 重新声明一遍，在形式系统里没有任何作用。我们也希望它对 reduced type 没有作用，因此 type parameter order 必须偏好某些 associated type declaration：

**定义.** **Root associated type** 指这样一个 associated type：它的父 protocol 没有从任何声明了同名 associated type 的 protocol 继承而来。

在下面的例子里，`Derived.Foo` 不是 root，因为 `Derived` 继承 `Base`，而 `Base` 也声明了一个名为 `Foo` 的 associated type。而 `Derived.Bar` 是 root：

```swift
protocol Base {
  associatedtype Foo  // root
}

protocol Derived: Base {
  associatedtype Foo  // not a root
  associatedtype Bar  // root
}
```

我们用 protocol order 来定义 associated type order。

**算法（Associated type order）.** 输入 associated type declaration `A₁` 与 `A₂`，输出 `<`、`>`、`=` 三者之一。

1. 先按字典序比较两者的名字。若结果是 `<` 或 `>` 就返回。否则两个 associated type 同名，继续下一步。
2. 若 `A₁` 是 root associated type 而 `A₂` 不是，返回 `<`。
3. 若 `A₂` 是 root associated type 而 `A₁` 不是，返回 `>`。
4. 否则 `A₁` 与 `A₂` 的「root 性」相同。用 Protocol order 算法比较 `A₁` 与 `A₂` 的父 protocol，若结果是 `<` 或 `>` 就返回。
5. 否则我们手上是同一个 protocol 里两个同名的 associated type。若 `A₁` 与 `A₂` 是同一个 associated type declaration，返回 `=`。
6. 否则这个程序是非法的。与 protocol order 一样，此时可以用任意 tie-breaker，比如源码位置。

至此我们已经有足够的材料给所有 type parameter 排序了。Type parameter order 不区分 type sugar，所以它输出 `=` 当且仅当 `T` 与 `U` 是 canonically equal 的。

**算法（Type parameter order）.** 输入 type parameter `T` 与 `U`，输出 `<`、`>`、`=` 三者之一。

1. 若 `T` 是 generic parameter type 而 `U` 是 dependent member type，则 `|T| < |U|`，返回 `<`。
2. 若 `T` 是 dependent member type 而 `U` 是 generic parameter type，则 `|T| > |U|`，返回 `>`。
3. 若 `T` 与 `U` 都是 generic parameter type，用 Generic parameter order 算法比较并返回结果。
4. 否则两者都是 dependent member type。递归比较 `T` 的 base type 与 `U` 的 base type，若结果是 `<` 或 `>` 就返回。
5. 否则 `T` 与 `U` 的 base type 是 canonically equal 的。
6. 若 `T` 是 bound 而 `U` 是 unbound，返回 `<`。
7. 若 `T` 是 unbound 而 `U` 是 bound，返回 `>`。
8. 若 `T` 与 `U` 都是 unbound dependent member type，按字典序比较两者的名字并返回结果。
9. 若 `T` 与 `U` 都是 bound dependent member type，用 Associated type order 算法比较两者的 associated type declaration 并返回结果。

**定义.** 设 `G` 是一个 generic signature。`G` 的一个 valid type parameter `T` 是 **reduced type parameter**，当且仅当对所有 `U`，`G ⊢ [T == U]` 蕴含 `T ≤ U`。

Type parameter order 是一个 linear order，所以只要我们能在某个 equivalence class 里找出一个 reduced type parameter，它就必定是唯一的。但我们还没看到怎么**算出** reduced type parameter。事实上，我们甚至还没确立一个 type parameter 的 equivalence class **有**最小元。例如整数集 `ℤ` 在通常的 linear order 下就没有最小元：

```
... < -2 < -1 < 0 < 1 < 2 < ...
```

我们要把这种可能性排除掉：

**定义.** 一个以 `S` 为 domain 的 linear order 是 **well-founded** 的，当且仅当 `S` 的每个非空子集都含有一个最小元。

对更一般的 partial order 而言这个定义并不合适，因为由两个不可比元素组成的集合没有最小元。对 partial order，正确的条件是 domain `S` 不含**无穷下降链**，即不存在无穷序列 `xᵢ ∈ S` 使得：

```
x₁ > x₂ > x₃ > ...
```

对 linear order 而言，这两个条件是等价的。

有限集上的任何 partial order 总是 well-founded 的。自然数 `ℕ` 上通常的 linear order 也是 well-founded 的（本质上这是由 `ℕ` 的**定义**给出的）。

**命题.** Type parameter order 算法给出的 type parameter order 是 well-founded 的。

**证明.** 设 `S` 是任意一个非空的 type parameter 集合（可以是无穷的）。我们要证明 `S` 含有最小元。

首先，取 `S` 中每个 type parameter 的 length，定义集合 `L(S) ⊆ ℕ`。尽管 `L(S)` 可能是无穷集，但在 `ℕ` 的 linear order 下它必有最小元，记作 `n ∈ L(S)`。令 `Sₙ ⊆ S` 是 `S` 中只含 length 为 `n` 的 type parameter 的子集。若 `Sₙ` 有最小元，那它也就是 `S` 的最小元。

另一方面，length 固定的 type parameter 集合必定是有限的。若我们整个程序连同所有 imported module 一共声明了 `g` 个不同的 generic parameter 和 `a` 个 associated type，那么所有 generic signature 生成的、length 为 `n` 的 type parameter 数目不会超过 `g(2a)ⁿ`。（我们把每个 associated type 数了两遍，以兼顾 bound 与 unbound type parameter；不过这个确切数字无关紧要，重要的是它有限。）

于是有限集 `Sₙ` 含有最小元，`S` 也就含有最小元；而 `S` 是任取的，所以我们得出结论：type parameter order 是 well-founded 的。

Type parameter order 在 Swift 的 ABI 里扮演重要角色。例如，一个 generic function 的 mangled symbol name 里含有该函数的参数类型和返回类型，而 mangler 取的是 reduced type，以确保对声明所做的表面改动不影响二进制兼容性。

> 译注：这正是本库能把二进制里的 same-type requirement 正确摆回「哪一边是被约束的参数」的依据——reduced type 与 canonical 顺序是编译器写入 descriptor 时的排列规则，本库逐字节解读 requirement 时反过来用同一套顺序判断，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

为了定义 reduced type parameter，我们比较的是**同一个** equivalence class 里的元素。我们也用 type parameter order 来建立 equivalence class **之间**的序关系——比较它们的 reduced type 即可。`building-generic-signatures.tex` 的 Requirement order 算法会把这一点推广成 **requirement** 上的一个 partial order。这个 requirement order 会在 Swift ABI 里浮出水面：

1. Generic function 的 calling convention 为其 generic signature 里的每条显式 conformance requirement 传一张 witness table，顺序就按这个序排。
2. Witness table 的内存布局里，为 protocol 的 requirement signature 中每条 associated conformance requirement 存一张 associated witness table，顺序同样按这个序排。

> 译注：本库正是靠这个顺序把一张被 strip 掉符号的 protocol witness table 投影成逐槽位的 requirement 记录，见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

`archetypes.tex` 会引入 **archetype**——把一个 reduced type parameter 与一个 generic signature 打包在一起的自描述表示，它在编译器内部的行为更像一个 concrete type。因此一个 archetype 代表 type parameter 的一整个 equivalence class，也正因如此，我们同样用 equivalence class 记法 `⟦T⟧` 来表示 type parameter `T` 对应的 archetype。

关于 equivalence relation 和 partial order 更完整的论述，可以参考离散数学教材，例如 Grimaldi 1998 的《Discrete and Combinatorial Mathematics: An Applied Introduction》。要留意的是，有些作者把 partial order 定义成自反的而不是反自反的，于是 `≤` 成了基本运算。这样一来就需要附加一条：若 `x ≤ y` 与 `y ≥ x` 同时成立，则 `x = y`；没有这条假设的话，得到的是 **preorder**。有时 linear order 也叫做 **total order**，而带 well-founded order 的集合则称作 **well-ordered**。Type parameter order 其实是 **shortlex order** 的一个特例。在合理的假设下，shortlex order 总是 well-founded 的。`conformance-paths.tex` 的 The Conformance Path Graph 一节会出现 shortlex order 的另一个实例，而 `monoids.tex` 的 The Normal Form Algorithm 一节引入字符串重写理论时会把这个概念一般化。

## Generic Signature Queries

在实现里，我们通过发起 **generic signature query** 来回答关于一个 generic signature 的 derived requirement 与 valid type parameter 的问题。这些 query 是 `GenericSignature` 类上的方法，贯穿整个编译器。我们可以用本章前面建立的记法把它们的行为形式化：每个 query 定义一个数学**函数**，它接受一个 generic signature 以及至少一项其他数据，求值为该签名的某个性质。

> 译注：本库在没有编译器、只有一份二进制的前提下重实现了其中一部分——「这个 type parameter 被钉到哪个 concrete type」「它有没有 superclass bound」这类问题，由静态布局引擎直接从 descriptor 里的 requirement 算出，见 [SwiftLayout.md](../Modules/SwiftLayout.md)。

### Basic queries

前面看到，一个 generic signature 的 equivalence class 结构是由 conformance requirement 和 type parameter 之间的 same-type requirement 生成的。头四个 query 让我们能回答关于这个结构的问题，它们的行为完全由 derived requirement 形式系统所定义。

**Query：`requiresProtocol(G, T, P)`**

- **输入**：type parameter `T`，protocol `P`。
- **输出**：真或假——`G ⊢ [T: P]`？
- **说明**：判定一个 type parameter 是否 conform 到给定的 protocol。

**Query：`areReducedTypeParametersEqual(G, T, U)`**

- **输入**：type parameter `T`，type parameter `U`。
- **输出**：真或假——`G ⊢ [T == U]`？
- **说明**：判定两个 type parameter 是否属于同一个 equivalence class。

**Query：`isValidTypeParameter(G, T)`**

- **输入**：type parameter `T`。
- **输出**：真或假——`G ⊢ T`？
- **说明**：判定一个 type parameter 是否合法。

**Query：`getRequiredProtocols(G, T)`**

- **输入**：type parameter `T`。
- **输出**：所有满足 `G ⊢ [T: P]` 的 protocol `P`。
- **说明**：给出这个 type parameter 已知 conform 到的全部 protocol 的列表。

从理论角度看，两个最基本的 query 是 `requiresProtocol()` 与 `areReducedTypeParametersEqual()`。另外两个——`isValidTypeParameter()` 与 `getRequiredProtocols()`——虽然在实现里是原语，却可以用前两个形式化。`isValidTypeParameter(G, T)` 是这样：

- Generic parameter type 合法，当且仅当它出现在 `G` 里。
- Unbound dependent member type `U.A` 合法，当且仅当 `getRequiredProtocols(G, U)` 里存在某个 protocol `P` 声明了一个名为 `A` 的 associated type。
- Bound dependent member type `U.[P]A` 合法，当且仅当 `requiresProtocol(G, U, P)`。

至于 `getRequiredProtocols()`，由于那个「对所有」量词是在一个有限的 protocol 宇宙里挑选，一个正确但低效的实现可以逐个 protocol `P` 反复检查 `requiresProtocol(G, T, P)`。真正的实现则是构造一个能更高效完成这种查找的数据结构（`property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)））。

`getRequiredProtocols()` 这个 query 用在类型检查形如 `foo.bar` 的 member reference expression 上，此时 `foo` 的类型是一个 type parameter——我们通过对这个 protocol 列表做 qualified name lookup 来解析 `bar`。这个列表是最小的，意思是其中没有任何 protocol 继承自另一个，因为 qualified lookup 本来就会递归访问所有 inherited protocol。这些 protocol 还按 Protocol order 算法排过序。

**例.** 设 `G` 是「推导 requirement 的动机」那个例子里的 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Element: Equatable,
                    τ_0_0.Element == τ_0_1.Element>
```

1. `requiresProtocol(G, τ_0_0.Element, Equatable)` 为真。
2. `requiresProtocol(G, τ_0_0.Iterator.Element, Equatable)` 为真。
3. `requiresProtocol(G, τ_0_0.Iterator, Equatable)` 为假。
4. `areReducedTypeParametersEqual(G, τ_0_0.Element, τ_0_1.Element)` 为真。
5. `areReducedTypeParametersEqual(G, τ_0_0.Iterator, τ_0_1.Iterator)` 为假。
6. `isValidTypeParameter(G, τ_0_0.Element)` 为真。
7. `isValidTypeParameter(G, τ_0_0.Iterator.Element)` 为真。
8. `isValidTypeParameter(G, τ_0_0.Element.Iterator)` 为假。
9. `getRequiredProtocols(G, τ_0_0.Iterator)` 是 `{IteratorProtocol}`。

### Concrete types

接下来两个 query 关乎 concrete same-type requirement。我们可以问一个 type parameter 是否被固定到某个 concrete type，然后再问这个 concrete type 是什么。（下面仍用 `⊢`，但请回忆本章 Derived Requirements 一节说过：我们并没有一套完备的 inference rule 来描述 concrete same-type requirement 的已实现行为。）

**Query：`isConcreteType(G, T)`**

- **输入**：type parameter `T`。
- **输出**：真或假——是否存在某个 concrete type `X` 使得 `G ⊢ [T == X]`？
- **说明**：判定一个 type parameter 是否被固定到某个 concrete type。

**Query：`getConcreteType(G, T)`**

- **输入**：type parameter `T`。
- **输出**：某个满足 `G ⊢ [T == X]` 的 concrete type `X`。
- **说明**：输出一个 type parameter 被固定到的那个 concrete type。

**例（concrete type query）.** 设 `G` 是这个 generic signature：

```
<τ_0_0 where τ_0_0: Foo, τ_0_0.[Foo]B == Int>
```

其中 protocol `Foo` 如下：

```swift
protocol Foo {
  associatedtype A where A == Array<B>
  associatedtype B
}
```

1. `isConcreteType(G, τ_0_0.[Foo]A)` 为真。
2. `getConcreteType(G, τ_0_0.[Foo]A)` 是 `Array<τ_0_0.[Foo]B>`。
3. `getConcreteType(G, τ_0_0.[Foo]B)` 是 `Int`。

### Reduced types

现在我们可以把 type parameter 上的 reduced type equality 推广成 interface type（即**含有** type parameter 的那些类型）上的一个 equivalence relation。这个关系叫做 **reduced type equality of interface types**，它可以由两条定义性性质刻画。

第一条性质是：若一个 generic signature 把某 type parameter 固定到一个 concrete type，那么含有该 type parameter 的 interface type，与把该 type parameter 换成它的 concrete type 之后得到的那个 interface type 等价。在上一个例子里，`τ_0_0.[Foo]A` 被固定到 `Array<τ_0_0.[Foo]B>`，`τ_0_0.[Foo]B` 被固定到 `Int`，所以在那个签名里下面三个 interface type 是等价的：

```
τ_0_0.[Foo]A
Array<τ_0_0.[Foo]B>
Array<Int>
```

第二条性质是：在一个 interface type 里，把某个 type parameter 在它出现的任何位置换成一个与之等价的 type parameter，总会得到一个等价的 interface type。考虑下面这个签名，protocol `Foo` 与前面相同，但这次不是把 `τ_0_0.[Foo]B` 固定到 `Int`，而是说 `τ_0_0.[Foo]B` 与 `τ_0_1` 等价：

```
<τ_0_0, τ_0_1 where τ_0_0: Foo, τ_0_1 == τ_0_0.[Foo]B>
```

在这个 generic signature 里，下面三个 interface type 是等价的：

```
τ_0_0.[Foo]A
Array<τ_0_0.[Foo]B>
Array<τ_0_1>
```

假设我们取一个 interface type，反复施加下面这对变换直到不动点：第一，把每个被固定到 concrete type 的 type parameter 替换掉；第二，把其余每个 type parameter 换成它所在 equivalence class 的 reduced type parameter。一个关键事实是：得到的 interface type 与原来那个等价。

**算法（Compute reduced type）.** 输入一个 generic signature `G` 和一个 interface type `X`。输出 `X` 的 reduced type。

1. 若 `X` 其实是一个 type parameter `T`：
   1. 若 `isConcreteType(G, T)`：对 `getConcreteType(G, T)` 递归求 reduced type。
   2. 否则，返回 `T` 所在 equivalence class 的 reduced type parameter。
2. 否则 `X` 是一个 concrete type。若 `X` 没有任何子类型，返回 `X`。
3. 否则，递归地对 `X` 的每个子类型求 reduced type，再用这些 reduced 子类型连同 `X` 的所有非类型属性构造一个新类型。

这个算法输出的是一类特殊的 interface type：

**定义.** 设 `G` 是一个 generic signature。一个 interface type 是 `G` 的 **reduced type**，当且仅当它含有的每个 type parameter 都满足下面两个条件：

1. 每个这样的 type parameter 都是 `G` 的 reduced type parameter。
2. 没有哪个这样的 type parameter 被 `G` 固定到某个 concrete type。

特别地，fully-concrete type（不含 type parameter 的类型）是 reduced 的。

要保证 Compute reduced type 算法终止，我们必须禁止带自指 same-type requirement 的 generic signature。例如，若 `G ⊢ [τ_0_0 == Array<τ_0_0>]`，第 1a 步就会在 `τ_0_0`、`Array<τ_0_0>`、`Array<Array<τ_0_0>>`…… 之间无限约下去。具体做法见 `property-map.tex` 的 Substitution Simplification 一节。既然这种情况不会发生，那么每个 interface type 的 equivalence class 都含有唯一一个 reduced type。因此：

**命题.** 设 `G` 是一个 generic signature。两个 interface type 在 reduced type equality 关系下等价，当且仅当它们有相同的 reduced type。（更精确地说，当且仅当它们的 reduced type 是 canonically equal 的。）

于是下面这对 generic signature query 就判定了 reduced type equality：

**Query：`isReducedType(G, T)`**

- **输入**：interface type `T`。
- **输出**：真或假——`T` 与它自己的 reduced type 是否 canonically equal？
- **说明**：判定一个 interface type 是否已经是 reduced type。

**Query：`getReducedType(G, T)`**

- **输入**：interface type `T`。
- **输出**：`T` 的 reduced type。
- **说明**：用 Compute reduced type 算法计算 reduced type。它总是输出 canonical type，所以原类型里的 type sugar 会丢失。

**例.** Interface type 上的 reduced type equality 比 type parameter 上的 reduced type equality **更粗**（coarser）：两个等价的 type parameter 作为 interface type 也等价，但反过来**不**成立。设 `G` 是下面这个 generic signature，注意 `[τ_0_0 == τ_0_1]` 是**不能**从 `G` 推出的：

```
<τ_0_0, τ_0_1 where τ_0_0 == Int, τ_0_1 == Int>
```

1. `areReducedTypeParametersEqual(G, τ_0_0, τ_0_1)` 为假。
2. `getReducedType(G, τ_0_0)` 是 `Int`。
3. `getReducedType(G, τ_0_1)` 是 `Int`。

因此 `τ_0_0` 与 `τ_0_1` 作为 interface type 等价，但作为 type parameter 不等价。

### Other requirements

最后一组 query 关乎 superclass requirement 与 layout requirement。仍要提醒一句，`⊢` 在这里是一种「愿景」，因为这几种 requirement kind 的已实现行为并没有全部被我们的形式系统描述。

**Query：`getSuperclassBound(G, T)`**

- **输入**：type parameter `T`。
- **输出**：某个满足 `G ⊢ [T: C]` 的 concrete class type `C`。
- **说明**：输出该 type parameter 的 superclass bound（如果它有的话）。

**Query：`requiresClass(G, T)`**

- **输入**：type parameter `T`。
- **输出**：真或假——`G ⊢ [T: AnyObject]`？
- **说明**：判定 `T` 是否具有单个引用计数指针的表示。

**Query：`getLayoutConstraint(G, T)`**

- **输入**：type parameter `T`。
- **输出**：某个满足 `T ⊢ [T: L]` 的 layout constraint `L`。
- **说明**：输出该 type parameter 的 layout constraint（如果它有的话）。

`AnyObject` 是唯一一个可以在源码里显式写出的 layout constraint。还有第二种 layout constraint `_NativeClass`，它由「superclass bound 是一个 native Swift class」蕴含——native 指不继承自 `NSObject` 的类。而 `_NativeClass` 这个 layout constraint 又蕴含 `AnyObject` layout constraint。

两者的区别在于 IRGen 如何 lower 引用计数操作。祖先未知的类走 Objective-C runtime 的入口点，而 native class 的实例走 Swift runtime 里另一批入口点。

> 译注：「一个 type parameter 即便没有任何 generic argument 也能被 superclass / layout requirement 钉死」正是本库静态布局引擎的立足点——class-bound 的参数必定是一个对象引用，concrete same-type pin 则直接给出替换类型，两者都能在不特化的情况下把字段布局算出来，见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

**例.** 设 `G` 是这个 generic signature：

```
<τ_0_0, τ_0_1, τ_0_2 where τ_0_0: Form, τ_0_1: Shape, τ_0_2: Entity>
```

连同这三个声明：

```swift
class Shape {}
protocol Form: AnyObject {}
protocol Entity: Shape, Form {}
```

1. `getSuperclassBound(G, τ_0_0)` 是 null。
2. `getSuperclassBound(G, τ_0_1)` 是 `Shape`。
3. `getSuperclassBound(G, τ_0_2)` 是 `Shape`。
4. `requiresClass(G, τ_0_0)` 为真。
5. `requiresClass(G, τ_0_1)` 为真。
6. `requiresClass(G, τ_0_2)` 为真。

我们可以为 `requiresClass(G, τ_0_0)` 写出一个 derivation：

```
1. [τ_0_0: Form]                                  （Conf）
2. [τ_0_0: AnyObject]                             （AssocLayout，前提 1）
```

然而我们写不出 `requiresClass(G, τ_0_1)` 的 derivation——尽管我们**本该**写得出来。实现认为这条 derived requirement 成立，理由是：任何满足那条 superclass requirement 的具体替换类型，也必然满足那条 layout requirement。我们在形式系统内部做不出这个推断，所以它是**不完备的**。这里缺的那条规则，是允许我们从 superclass requirement `[T: C]` 推出 `[T: AnyObject]` 的那一条。对这些缺失规则的形式化描述仍在进行中。

### Sugared types

为了避免在诊断信息里打印 `τ_d_i` 这样的 canonical generic parameter type，有一个专门的 query 可以用给定 generic signature 的 generic parameter 名把一个 canonical type 变成 sugared type。它其实根本不是语义 query，只是对类型做一次语法变换。

**Query：`getSugaredType(G, T)`**

- **输入**：interface type `T`。
- **输出**：一个与之 canonically equal 的 interface type，但用 `G` 的 sugared type 书写。

### Combined queries

为了简化 generic environment 内部 archetype 的构造（`archetypes.tex` 的 Local Requirements 一节），我们用一个特殊入口一次完成多项查找。除此之外，它的行为完全由其他 query 决定。

**Query：`getLocalRequirements(G, T)`**

- **输入**：type parameter `T`。
- **输出**：一个结构体，里面装着若干个 query 的结果。
- **说明**：输出关于 `T` 所在 equivalence class 的全部已知数据：

  ```
  getRequiredProtocols(G, T)
  getSuperclassBound(G, T)
  getLayoutConstraint(G, T)
  ```

## Source Code Reference

关键源文件：

- `include/swift/AST/GenericSignature.h`
- `include/swift/AST/Requirement.h`
- `include/swift/AST/RequirementSignature.h`
- `lib/AST/GenericSignature.cpp`

其他源文件：

- `include/swift/AST/Decl.h`
- `include/swift/AST/DeclContext.h`
- `lib/AST/Decl.cpp`
- `lib/AST/DeclContext.cpp`

**`DeclContext`**（class）：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getGenericSignatureOfContext()` 返回最内层 generic context 的 generic signature；没有则返回 empty generic signature。

**`GenericContext`**（class）：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getGenericSignature()` 返回该声明的 generic signature，必要时先把它算出来。若该声明既没有 generic parameter 列表也没有 trailing `where` clause，返回父上下文的 generic signature。

**`GenericSignature`**（class）：表示一个不可变、唯一化的 generic signature。它设计为按值传递，只存一个实例变量——一个 `GenericSignatureImpl *` 指针。

`getPointer()` 方法返回这个指针。该指针不是 `const` 的，不过 `GenericSignatureImpl` 并没有定义任何会修改自身的方法。

这个指针可能是 `nullptr`，表示 empty generic signature；默认构造函数 `GenericSignature()` 构造的就是这个值。它有一个隐式的 `bool` 转换，用来测试是否为 empty generic signature。

`getPointer()` 方法只是偶尔用到，因为 `GenericSignature` 类重载了 `operator->`，把方法调用转发给 `GenericSignatureImpl *` 指针。Generic signature 上的一部分操作是 `GenericSignature` 的方法（用 `.` 调用），另一部分是 `GenericSignatureImpl` 的方法（用 `->` 调用）。

`GenericSignature` 的方法对 empty generic signature 调用是安全的——此时它表现为没有任何 generic parameter 和 requirement。而转发给 `GenericSignatureImpl` 的方法只有在签名非空时才能调用。

`GenericSignature` 类显式 delete 了 `operator==` 和 `operator!=`，以强制调用者明确选择用指针相等还是 canonical 相等。要检查 generic signature 的指针相等，先用 `getPointer()` 把两边解包：

```cpp
if (lhsSig.getPointer() == rhsSig.getPointer())
  ...;
```

更常用的 canonical signature 相等检查由 `GenericSignatureImpl` 上的 `isEqual()` 方法实现：

```cpp
if (lhsSig->isEqual(rhsSig))
  ...;
```

各种访问器方法：

- `getGenericParams()` 返回一个 `GenericTypeParamType` 数组。若 generic signature 为空则是空数组，否则至少含一个 generic parameter。
- `getInnermostGenericParams()` 返回一个 `GenericTypeParamType` 数组，只含最内层的 generic parameter，即 depth 最大的那些。若 generic signature 为空则是空数组，否则至少含一个 generic parameter。
- `getRequirements()` 返回一个 `Requirement` 数组。若 generic signature 为空则是空数组。
- `getCanonicalSignature()` 返回 canonical signature。若 generic signature 为空，返回 canonical 的 empty generic signature。
- `getPointer()` 返回底层的 `GenericSignatureImpl *`。

计算 reduced type：

- `getReducedType()` 返回某 interface type 相对于这个 generic signature 的 reduced type。若 generic signature 为空，则该类型必须是 fully concrete 的，原样返回。

其他：

- `print()` 打印该 generic signature，有若干选项控制输出。
- `dump()` 打印该 generic signature，供调试器或临时的打印调试语句使用。

另见 `building-generic-signatures.tex` 的 Source Code Reference 一节。

**`GenericSignatureImpl`**（class）：generic signature 的后备存储。这个类的实例分配在 AST context 里，并且总是按指针传递。

- `isEqual()` 检查两个 generic signature 是否 canonically equal。
- `getSugaredType()` 接受一个含 canonical type parameter、且被理解为相对于这个 generic signature 书写的类型，把其中的 generic parameter type 换成「sugared」形式，使得该类型被打印成字符串时名字得以保留。
- `forEachParam()` 对该签名的每个 generic parameter 调用一次回调；回调还会收到一个布尔值，指示该 generic parameter type 是否 reduced——位于某条 same-type requirement 左边的 generic parameter 不是 reduced 的。
- `areAllParamsConcrete()` 检查是否所有 generic parameter 都被 same-type requirement 固定到 concrete type，这会让该 generic signature 有点像 empty generic signature。完全具体化的 generic signature 在 SIL 层会被 lower 掉。

本章 Generic Signature Queries 一节讲的那些 generic signature query 都是 `GenericSignatureImpl` 上的方法：

- 谓词类 query：
  - `isValidTypeParameter()`
  - `requiresProtocol()`
  - `requiresClass()`
  - `isConcreteType()`
- 属性类 query：
  - `getRequiredProtocols()`
  - `getSuperclassBound()`
  - `getConcreteType()`
  - `getLayoutConstraint()`
- Reduced type 类 query：
  - `areReducedTypeParametersEqual()`
  - `isReducedType()`
  - `getReducedType()`

**`CanGenericSignature`**（class）：`CanGenericSignature` 类包装一个已知为 canonical 的 `GenericSignatureImpl *` 指针。该指针可用 `getPointer()` 方法取回。存在一个从 `CanGenericSignature` 到 `GenericSignature` 的隐式转换。`operator->` 把方法调用转发给底层的 `GenericSignatureImpl`。

`operator==` 与 `operator!=` 用来测试 `CanGenericSignature` 的指针相等。`GenericSignatureImpl` 的 `isEqual()` 方法在任意 generic signature 上实现 canonical 相等的办法，是先把两边 canonical 化，再检查所得 canonical signature 的指针相等。因此下面两种写法等价：

```cpp
if (lhsSig->isEqual(rhsSig))
  ...;

if (lhsSig.getCanonicalSignature() == rhsSig.getCanonicalSignature())
  ...;
```

`CanGenericSignature` 类继承自 `GenericSignature`，因而继承了全部同样的方法。此外它还覆写了 `getGenericParams()`，改为返回一个 `CanGenericTypeParamType` 数组。

**`Requirement`**（class）：一条 generic requirement。由一个 kind、一个左边（总是 `Type`）和一个右边（类型取决于 kind）构成。另见 `type-resolution.tex` 与 `building-generic-signatures.tex` 的 Source Code Reference 一节。

- `Requirement(RequirementKind, Type, Type)` 构造除 `RequirementKind::Layout` 之外的任何 requirement kind。
- `Requirement(RequirementKind, Type, LayoutConstraint)` 构造 `RequirementKind::Layout`。
- `getKind()` 返回 `RequirementKind`。
- `getFirstType()` 返回左边的类型。
- `getSecondType()` 在这条 requirement 不是 `RequirementKind::Layout` 时返回右边的类型；否则断言失败。
- `getProtocolDecl()` 在这是一条 `RequirementKind::Conformance` 时返回右边的 protocol declaration；否则断言失败。
- `getLayoutConstraint()` 在这是一条 `RequirementKind::Layout` 时返回右边的 layout constraint；否则断言失败。

**`RequirementKind`**（enum class）：`Requirement::getKind()` 的返回类型。

- `RequirementKind::Conformance`
- `RequirementKind::Superclass`
- `RequirementKind::Layout`
- `RequirementKind::SameType`

**`ProtocolDecl`**（class）：另见 `declarations.tex` 与 `building-generic-signatures.tex` 的 Source Code Reference 一节。

- `getRequirementSignature()` 返回该 protocol 的 requirement signature，必要时先把它算出来。
- `requiresClass()` 检查该 protocol 是否是 class-constrained protocol。

**`RequirementSignature`**（class）：一个 protocol 的 requirement signature。

- `getRequirements()` 返回一个 `Requirement` 数组。
- `getTypeAliases()` 返回一个 `ProtocolTypeAlias` 数组。

另见 `building-generic-signatures.tex` 的 Source Code Reference 一节。

**`ProtocolTypeAlias`**（class）：一个 protocol type alias descriptor。

- `getName()` 返回该 alias 的名字。
- `getUnderlyingType()` 返回该 type alias 的 underlying type。这个类型是用 requirement signature 的 type parameter 书写的。

**`TypeBase`**（class）：另见 `types.tex` 的 Source Code Reference 一节。

- `isTypeParameter()` 检查这个类型是否是一个 type parameter，即一个 generic parameter type，或者 base 是另一个 type parameter 的 `DependentMemberType`。
- `hasTypeParameter()` 检查这个类型本身是否是 type parameter，或者是否在结构位置上含有 type parameter。例如 `Array<τ_0_0>` 对 `isTypeParameter()` 答 `false`，但对 `hasTypeParameter()` 答 `true`。

**`DependentMemberType`**（class）：一个抽象了某 conformance 中 type witness 的类型。

- `getBase()` 返回 base type；例如给定 `τ_0_0.Foo.Bar`，它答 `τ_0_0.Foo`。
- `getName()` 返回命名该 associated type 的标识符。
- `getAssocType()` 在这是一个 bound `DependentMemberType` 时返回 associated type declaration，若是 unbound 的则返回 `nullptr`。

**`TypeDecl`**（class）：另见 `declarations.tex` 的 Source Code Reference 一节。

- `compare()` 按 protocol order（见本章 Protocol order 算法）比较两个 protocol，返回下列之一：
  - `-1`，若本 protocol 排在给定 protocol 之前；
  - `0`，若两个 protocol declaration 相等；
  - `1`，若本 protocol 排在给定 protocol 之后。

**`compareDependentTypes()`**（function）：实现 type parameter order（见本章 Type parameter order 算法），返回下列之一：

- `-1`，若左边排在右边之前；
- `0`，若两个 type parameter 作为 canonical type 相等；
- `1`，若左边排在右边之后。

---

> 译自 `docs/Generics/chapters/generic-signatures.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
