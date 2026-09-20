# Conformance Paths（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/conformance-paths.tex`（《Compiling Swift Generics》一书的「Conformance Paths」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章讲的是「已经拿到一张 witness table，怎么一步步取到所需的 associated conformance」——也就是 conformance path。这正是本库在二进制里做的事情的**正向版本**：本库从 conformance descriptor 和 protocol witness table 的槽位里把这些关系读回来。本章后半给出的不可判定性结论，则是本库「算不出来就诚实降级、绝不假装算得出」这条纪律的理论依据。译文本身不夹带本库的实现细节，只在个别地方以「译注」标出对应关系。
>
> **术语**：书中定义的术语一律保留英文（conformance path、abstract conformance、root abstract conformance、principal abstract conformance、reduced abstract conformance、associated conformance projection、local conformance lookup、conformance path graph、protocol dependency graph、conformance substitution graph、witness table、tag system、halting problem……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Valid Type Parameters 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本 + Unicode）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 generic parameter。原书的 `T` 对应 `τ_0_0`，`U` 对应 `τ_0_1`。本章后半（tag system 那部分）在 protocol generic signature 里把 `τ_0_0` 直接简写成 `τ` |
> | `[T: P]` | conformance requirement，等价地看就是一个 **abstract conformance**：`T` 对 protocol `P` 的一致性 |
> | `[T == U]` | same-type requirement |
> | `[Self.U: Q]_P` | protocol `P` 的一条 **associated conformance requirement**（带下标 `P` 表示它是 `P` 的 requirement signature 里的） |
> | `⟨Self.U: Q]` | **associated conformance projection**：从一个对 `P` 的 conformance 里，把 `Self.U` 对 `Q` 的那个 associated conformance 投影出来。左尖括号 + 右方括号是原书的记法 |
> | `⟨P\|A` | **type witness projection**：从一个对 protocol `P` 的 conformance 里，把 associated type `A` 的 type witness 投影出来 |
> | `⟨P]` | protocol `P` 的 protocol generic signature |
> | `X ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `X`；`Σ ⊗ Σ′` 是 substitution map composition。`⊗` 在本章是唯一的「运算符」，左右两侧可以是类型、conformance、substitution map |
> | `Σ`、`Σ_S`、`Σ_AA` | substitution map。写成 `{τ_0_0 ↦ String; [τ_0_0: Collection] ↦ [String: Collection]}`，分号前是 replacement type，分号后是 replacement conformance |
> | `1`、`1_G` | generic signature `G` 的 identity substitution map |
> | `1_v` | 顶点 `v` 处的 empty path |
> | `G ⊢ R` | requirement `R` 可以从 generic signature `G` 的 explicit requirement 导出（derived requirement） |
> | `\|T\|` | type parameter `T` 的 length（它套了几层 dependent member type） |
> | `src(p)`、`dst(p)` | 有向图里一条边 / 一条路径的起点与终点 |
> | `Proto` | name lookup 能看见的全体 protocol declaration 组成的集合 |
> | `Conf(G)`、`Type(G)`、`Sub(G, H)` | output signature 为 `G` 的 conformance 集合、`G` 的 interface type 集合、input 为 `G`、output 为 `H` 的 substitution map 集合 |
> | `ℕ` | 自然数集 |
> | `♣` | 原书用来标记一条 normal conformance 的表头记号，本文照搬 |

---

我们现在回头，把 type substitution 里留下的一条线头收起来。先回顾一下已知的部分。Substitution map 是一个有限的数据结构——它按自己 generic signature 的每个 generic parameter 和每条 conformance requirement，存了一串 replacement type 和 replacement conformance。但从语义上看，substitution map 是给它 generic signature 的**每一个** valid type parameter 都指定了一个 replacement type，而 valid type parameter 可能有无穷多个。当 signature 一条 conformance requirement 也没有时，valid type parameter **就是**那些 generic parameter，于是 type substitution 很容易描述。一般情形下，valid type parameter 的集合还包含由这些 conformance requirement 导出的 dependent member type。

在 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Abstract Conformances 一节里我们引入了 local conformance lookup 操作，于是「把 substitution map 应用到一个 dependent member type」这个问题，就变成了「从一个 conformance 里投影出一个 type witness」。但我们当时把「local conformance lookup 究竟怎么工作」这件事推掉了，只讲了 dependent member type 能从某条 explicit conformance requirement 一步导出的情形。那对应一条长度为 1 的 **conformance path**。本章我们研究更一般的 conformance path。

> 译注：本库读二进制时走的是反向的这条路——protocol conformance descriptor 里逐槽位记着这些 associated conformance，本库把它们按 conformance 归属拆开，见 [PerConformanceAttribution.md](../PerConformanceAttribution.md) 与 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

**代码清单（标准库里的几个 protocol 及其 conformance）.**

```swift
protocol IteratorProtocol {
  associatedtype Element
}

protocol Sequence {
  associatedtype Element
  associatedtype Iterator: IteratorProtocol
    where Element == Iterator.Element
}

protocol Collection: Sequence {
  associatedtype SubSequence: Collection
    where Element == SubSequence.Element,
          SubSequence == SubSequence.SubSequence
}
```

```
♣ [String: Collection]
  ⟨Collection|SubSequence         ↦  Substring
  ⟨Self: Sequence]                ↦  [String: Sequence]
  ⟨Self.SubSequence: Collection]  ↦  [Substring: Collection]

♣ [Substring: Collection]
  ⟨Collection|SubSequence         ↦  Substring
  ⟨Self: Sequence]                ↦  [Substring: Sequence]
  ⟨Self.SubSequence: Collection]  ↦  [Substring: Collection]

♣ [String: Sequence]
  ⟨Sequence|Element               ↦  Character
  ⟨Sequence|Iterator              ↦  IndexingIterator<String>
  ⟨Self.Iterator: IteratorProtocol]  ↦  [IndexingIterator<String>: IP]

♣ [Substring: Sequence]
  ⟨Sequence|Element               ↦  Character
  ⟨Sequence|Iterator              ↦  IndexingIterator<Substring>
  ⟨Self.Iterator: IteratorProtocol]  ↦  [IndexingIterator<Substring>: IP]
```

（上面的「`IP`」本该写成「`IteratorProtocol`」，当然是排不下。）

**例.** 为了引出这个概念，设 `G` 是下面这个 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Collection,
                    τ_0_1 == τ_0_0.[Collection]SubSequence>
```

我们还要用到标准库的 `String`、`Substring` 和 `Character` 类型，以及它们对 `Sequence` 和 `Collection` 的 conformance。这几个 protocol 在 `generic-signatures.tex` 与 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)） 里已经研究过（前者的 `Collection` 例子、后者的 type parameter graph 例子）。上面的代码清单重述了这几条 protocol 声明，并列出了下面这四条 normal conformance 的相关事实：

```
[String: Collection]
[Substring: Collection]
[String: Sequence]
[Substring: Sequence]
```

我们打算把下面这张 substitution map 应用到各种 dependent member type 上：

```
Σ := {τ_0_0 ↦ String,
      τ_0_1 ↦ Substring;
      [τ_0_0: Collection] ↦ [String: Collection]}
```

下面我们会在 derived requirement 这套形式体系和 type substitution 代数之间来回跳，所以先重述 `conformances.tex` 的 Abstract Conformances 一节里把两者连起来的那套术语：

- 一条 **conformance requirement** 就是一个 **abstract conformance**。
- 一条 **derived** conformance requirement 就是一个 **valid** abstract conformance。
- 一条 **explicit** conformance requirement 就是一个 **root** abstract conformance。

先热个身：用 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Check substitution map 算法验证 `Σ` 满足 `G` 的 explicit requirement。它满足那条 conformance requirement 是显然的。要看它满不满足那条 same-type requirement，我们把 `Σ` 应用到等式两边。右边是一个 dependent member type，所以我们把它写成某个 root abstract conformance 的 type witness：

```
τ_0_1 ⊗ Σ = Substring

τ_0_0.[Collection]SubSequence ⊗ Σ
  = ⟨Collection|SubSequence ⊗ [τ_0_0: Collection] ⊗ Σ
  = ⟨Collection|SubSequence ⊗ [String: Collection]
  = Substring
```

可见 `Σ` 把 same-type requirement 的两边都映到了 `Substring`。

到这里都还没出现新东西。现在我们来算 `τ_0_1.[Sequence]Iterator ⊗ Σ`。同样地，可以把这个 dependent member type 表达成某个 abstract conformance 的 type witness：

```
τ_0_1.[Sequence]Iterator ⊗ Σ
  = ⟨Sequence|Iterator ⊗ [τ_0_1: Sequence] ⊗ Σ
```

这一次，`[τ_0_1: Sequence]` **不是** `G` 的 explicit conformance requirement。不过，利用 `[τ_0_1: Sequence] = ⟨Sequence] ⊗ τ_0_1` 和 `τ_0_1 ⊗ Σ = Substring` 这两条事实，我们仍然算得出答案：

```
[τ_0_1: Sequence] ⊗ Σ
  = ⟨Sequence] ⊗ τ_0_1 ⊗ Σ
  = ⟨Sequence] ⊗ Substring
  = [Substring: Sequence]
```

可是，我们希望**只**靠 `Σ` 就把 `[Substring: Sequence]` 恢复出来，而不要像上面这样求助于一次 **global** conformance lookup。可选的手段并不多。事实上，local conformance lookup 能做的**几乎只有**一件事：拿起 substitution map 里存着的某个 root conformance，然后不断做 associated conformance projection。

我们的 generic signature `G` 只有一条 explicit conformance requirement，所以就从 `Σ` 里那个孤零零的 root conformance 出发：

```
[τ_0_0: Collection] ⊗ Σ = [String: Collection]
```

`⟨Self.SubSequence: Collection]` 这个 associated conformance 看着有戏，于是把它投影出来：

```
⟨Self.SubSequence: Collection] ⊗ [String: Collection]
  = [Substring: Collection]
```

我们要找的是 `[Substring: Sequence]`，不是 `[Substring: Collection]`，但再做一次 associated conformance projection 就到了：

```
⟨Self: Sequence] ⊗ [Substring: Collection]
  = [Substring: Sequence]
```

有了 `[Substring: Sequence]` 这个 conformance，再投影出 `Iterator` 的 type witness，就得到最终的代入结果：

```
⟨Sequence|Iterator ⊗ [Substring: Sequence]
  = IndexingIterator<Substring>
```

先把「这套做法**为什么**看上去行得通」这个问题搁下不谈——这是个很重要的问题，我们后面会详细研究——可以看到 `τ_0_1.[Sequence]Iterator ⊗ Σ` 是分四步从 `Σ` 里恢复出来的：先从 `Σ` 里投影出 root conformance，然后投影一次 associated conformance，再投影一次，最后投影一次 type witness：

```
τ_0_1.[Sequence]Iterator ⊗ Σ

  = ⟨Sequence|Iterator ⊗ ( [τ_0_1: Sequence] ⊗ Σ )
                         └──── local conformance lookup ────┘

  = ⟨Sequence|Iterator
      ⊗ ( ⟨Self: Sequence]                          ┐
            ⊗ ( ⟨Self.SubSequence: Collection]      │
                  ⊗ ( [τ_0_0: Collection]           ├ local conformance lookup
                        ⊗ Σ ) ) )                   ┘

  = ⟨Sequence|Iterator ⊗ [Substring: Sequence]

  = IndexingIterator<Substring>
```

把中间那个长表达式两端的 type witness projection 和 substitution map 剥掉，剩下的就是 `G` 的 abstract conformance `[τ_0_1: Sequence]` 的一条 conformance path：

```
⟨Self: Sequence] ⊗ ⟨Self.SubSequence: Collection] ⊗ [τ_0_0: Collection]
```

一条 conformance path 只依赖于 generic signature，不依赖于任何一张具体的 substitution map。上面这条 conformance path 可以用来在**任何**一张 input generic signature 同为 `G` 的 substitution map 里，对 `[τ_0_1: Sequence]` 做 local conformance lookup。

**定义.** 设 `G` 是一个 generic signature。形式上，一条 **conformance path** 是一个长度 `n ≥ 1` 的有序元组 `(s_1, …, s_n)`，其中第一步 `s_1` 是 `G` 的一个 root abstract conformance，而之后的每一步 `s_i` 都是「上一步右边那个 protocol 所声明的一条 associated conformance requirement」。不过我们不用元组记法，而是把 conformance path **从右往左**写：

```
s_n ⊗ ⋯ ⊗ s_1
```

也可以写成这样：

```
⟨Self.U_n: P_n] ⊗ ⋯ ⊗ ⟨Self.U_2: P_2] ⊗ [T_1: P_1]
```

长度为 1 的 conformance path 就是一个单独的 root abstract conformance `[T_1: P_1]`。

现在我们可以把 `conformances.tex` 的 Substitute dependent member type 算法里缺的那个子过程补上了。我们还不知道怎么真正**找到**给定 abstract conformance 的 conformance path，但只要把这件事再委托给另一个子过程，就能看出 local conformance lookup 要做的事是：拿给定的 substitution map `Σ` 去**求值**这条 conformance path：

```
(s_n ⊗ (⋯ ⊗ (s_2 ⊗ (s_1 ⊗ Σ)) ⋯ ))
```

**算法（Local conformance lookup）.** 输入是一张 substitution map `Σ` 和一个 abstract conformance `[T: P]`，返回 `[T: P] ⊗ Σ`。

1. 用 Find conformance path 算法为 `[T: P]` 找一条 conformance path `s_n ⊗ ⋯ ⊗ s_1`。
2. （Root）设 `s_1 = [T_1: P_1]`。令 `C ← [T_1: P_1] ⊗ Σ`。（这不是递归调用；我们只是把 root conformance 从 `Σ` 里取出来。）令 `i ← 2`。
3. （Check）若 `i = n + 1`，返回 `C`。
4. （Project）由于 `i > 1`，我们知道 `s_i = ⟨Self.U_i: P_i]`，其中 `Self.U_i` 是 `P_i` 的 protocol generic signature 里的某个 type parameter。令 `C ← ⟨Self.U_i: P_i] ⊗ C`。
5. （Next）令 `i ← i + 1`，回到第 3 步。

第 4 步里那次 projection 只有在 `C` 是一个对 `P_{i-1}` 的 conformance 时才讲得通；这一点由 conformance path 定义里的条件保证。此外，最后一步 `s_n` 右边出现的那个 protocol `P_n` 必然与给定的 `P` 相同。

## Validity and Existence

除了「拿一张 substitution map 去求值」之外，我们也可以把一条 conformance path 看成 type substitution 代数里一个独立的表达式：

```
⟨Self: Sequence] ⊗ ⟨Self.SubSequence: Collection] ⊗ [τ_0_0: Collection]
  = ⟨Self: Sequence] ⊗ [τ_0_0.[Collection]SubSequence: Collection]
  = [τ_0_0.[Collection]SubSequence: Sequence]
```

（为了省地方，我们把 associated conformance projection 写成带 unbound type parameter 的形式，但实际上 requirement signature 里的 type parameter 全都是 bound 的。）

我们说这条 conformance path **表示**（represent）它这样算出来的那个 abstract conformance；一个 abstract conformance 如果能被某条 conformance path 表示，就称它是 **principal** 的。

**算法（Simplify conformance path）.** 输入一条 conformance path `s_n ⊗ ⋯ ⊗ s_1`，输出这条 path 所表示的 principal abstract conformance。

1. （Root）设 `s_1 = [T_1: P_1]`。令 `P ← P_1`、`T ← T_1`、`i ← 2`。
2. （Check）若 `i = n + 1`，返回 `[T: P]`。
3. （Step）设 `s_i = ⟨Self.U_i: P_i]`。令 `P ← P_i`、`T ← T.U_i`，其中 `T.U_i` 是把 `Self.U_i` 里的 `Self` 换成 `T` 得到的。
4. （Next）令 `i ← i + 1`，回到第 2 步。

上面这个算法其实只是 Local conformance lookup 算法在取 identity substitution map `1_G` 时的一个特例，但接下来的讨论里直接实现它会方便一些。

### Equivalence

在前面那个例子里，我们为 `[τ_0_1: Sequence]` 找到的 conformance path 实际表示的是 `[τ_0_0.[Collection]SubSequence: Sequence]`。两者虽不相同，但它们的 subject type `τ_0_1` 与 `τ_0_0.[Collection]SubSequence` 是等价的，这来自 `G` 的那条 same-type requirement。这提示我们定义下面这个等价关系。

**定义.** 设 `G` 是一个 generic signature。若能导出 `G ⊢ [T == T′]`——换句话说，若 `T` 与 `T′` 是 `G` 的等价 type parameter——我们就说两个 abstract conformance `[T: P]` 与 `[T′: P]` 关于 `G` **等价**。在这个关系下，每个等价类里恰好含有一个 **reduced abstract conformance**，即 subject type 是 `G` 的 reduced type parameter 的那一个。

于是在我们的例子里，`[τ_0_1: Sequence]` 和 `[τ_0_0.[Collection]SubSequence: Sequence]` 属于同一个等价类；前者是 reduced 的，后者是 principal 的。就 type substitution 而言，这两个 abstract conformance 可以互换。一般地，若 `Σ ∈ Sub(G, H)` 是 well-formed 的（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)） 的 well-formed substitution map 定义），那么把 `Σ` 应用到 `G` 中两个等价 abstract conformance 的 subject type 上，输出的总是 `H` 的两个等价 interface type。

### Validity

到目前为止，我们只确认了**某一条**具体 conformance path 的合法性。要把结论推广开，我们必须对下面三个问题给出肯定的回答：

1. 每个 principal abstract conformance 是不是也都是 valid abstract conformance？
2. 每个 valid abstract conformance 是不是都等价于某个 principal abstract conformance？
3. 给定一个 valid abstract conformance，我们能不能找出一条表示某个与之等价的 principal abstract conformance 的 conformance path？

我们先回答 (1) 和 (2)，(3) 留到下一节用 Find conformance path 算法解决。回忆一下，`[T: P]` 是 valid abstract conformance 当且仅当 `G ⊢ [T: P]`。要确立 (1)，我们可以说明一条 conformance path 可以翻译成一种特殊形式的 derivation。

**定义.** 设 `G` 是一个 generic signature。一个 **principal derivation** 是一条 conformance requirement 的 derivation，它由一条 **Conf** elementary statement 开头，随后是零步或多步对上一步的结论施加 **AssocConf**，中间既没有用不上的结论，也没有别的种类的步骤：

```
1.  [T_1: P_1]                        (Conf)
2.  [T_1.U_2: P_2]                    (AssocConf  [Self.U_2: P_2]_{P_1}  [T_1: P_1])
    ⋮
n.  [T_1.U_2...U_n: P_n]              (AssocConf  [Self.U_n: P_n]_{P_{n-1}}  [T_1.U_2...U_{n-1}: P_{n-1}])
```

我们总能为一条 conformance path 写下一个 principal derivation；反过来，给定一个 principal derivation，也总能从中「读出」一条 conformance path。一个 principal derivation 的最终结论，与把 Simplify conformance path 算法应用到对应 conformance path 得到的 principal abstract conformance 是同一个东西。

**例.** 又是我们最喜欢的那条 conformance path：

```
⟨Self: Sequence] ⊗ ⟨Self.SubSequence: Collection] ⊗ [τ_0_0: Collection]
```

下面是 `G ⊢ [T.[Collection]SubSequence: Sequence]` 的 principal derivation：

```
1.  [τ_0_0: Collection]                            (Conf)
2.  [τ_0_0.[Collection]SubSequence: Collection]    (AssocConf 1)
3.  [τ_0_0.[Collection]SubSequence: Sequence]      (AssocConf 2)
```

我们可以给上面这个 principal derivation 再接一步 **SameConf**，得到 `[τ_0_1: Sequence]` 的一个 derivation。这就不再是 principal derivation 了：

```
4.  [τ_0_1 == τ_0_0.[Collection]SubSequence]       (Same)
5.  [τ_0_1: Sequence]                              (SameConf 3 4)
```

### Existence

现在我们来确立：abstract conformance 的每个等价类里至少含有一个 principal abstract conformance。为此我们要说明，一条 conformance requirement 的 derivation 总能拆成「一个 principal derivation，后面跟一条 same-type requirement」。其中的 principal derivation 定义了一条 conformance path，而这条 conformance path 表示的 principal abstract conformance，通过那条 same-type requirement 与原来的 abstract conformance 等价。

首先我们需要一个预备结果，它在 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Correctness 一节里还会用到。回忆 `generic-signatures.tex` 的 Valid Type Parameters 与 Bound Type Parameters 两节：对每个 protocol `P` 的每个 associated type `A`，我们都定义了一对推理规则 **SameName** 和 **SameDecl**：

```
[T.A == U.A]                          (SameName  [U: P]  [T == U])
[T.[P]A == U.[P]A]                    (SameDecl  [U: P]  [T == U])
```

这两条规则把一条 same-type requirement 的两边各包进一层 dependent member type，使它们的长度各加一。下面这条引理表明，我们也可以反复迭代这两步，造出「更长的」same-type requirement。这需要用归纳法来证明，还要用到关于 well-formed generic signature 的一些事实（见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Well-Formed Requirements 一节）。

**引理.** 设 `G` 是一个 well-formed generic signature，且对某两个 type parameter `T` 与 `U` 有 `G ⊢ [T == U]`。设 `T.V` 与 `U.V` 是把 `T` 与 `U` 各自包进若干层 dependent member type 得到的 type parameter，且两边逐层用的 identifier 或 associated type declaration 一一相同，即对某个 `n ≥ 0`：

```
T.V := T.A_1...A_n    以及    U.V := U.A_1...A_n
```

再设 `T.V` 与 `U.V` 中至少有一个是 valid 的，即 `G ⊢ T.V` 或 `G ⊢ U.V`。那么：

```
G ⊢ [T.V == U.V]
```

**证明.** 先考虑 `G ⊢ U.V` 的情形。注意 `|T.V| = |T| + n`，`|U.V| = |U| + n`。我们对 `n` 作归纳。

**基础情形.** 若 `n = 0`，则 `T.V` 就是 `T`，`U.V` 也就是 `U`。由假设已有 `G ⊢ [T == U]`，这正是要证的结论 `G ⊢ [T.V == U.V]`。

**归纳步骤.** 设 `n > 0`，考察 `U.V` 最外层的那个 dependent member type，它要么是 bound 的 `U′.[P]A`，要么是 unbound 的 `U′.A`，其中 `U′` 是某个 type parameter，`A` 是某 protocol `P` 的一个 associated type。由假设，`T.V` 具有相同的形状 `T′.[P]A` 或 `T′.A`，其中 `T′` 是某个 type parameter。注意 `|T′| = |T| - 1`，`|U′| = |U| - 1`。

由 `G ⊢ U.V`，再据 `building-generic-signatures.tex` 里那条关于 valid type parameter 的等价刻画命题，得到 `G ⊢ [U′: P]`：

```
1.  [U′: P]                          (…)
```

另外 `G` 是 well-formed 的，所以 `G ⊢ U′`。应用归纳假设，得到：

```
2.  [T′ == U′]                       (…)
```

若 `T.V` 是 `T′.[P]A`、`U.V` 是 `U′.[P]A`，我们对 (1) 与 (2) 施加 **SameDecl**：

```
3.  [T′.[P]A == U′.[P]A]             (SameDecl 1 2)
```

若 `T.V` 是 `T′.A`、`U.V` 是 `U′.A`，则改为对 (1) 与 (2) 施加 **SameName**：

```
3.  [T′.A == U′.A]                   (SameName 1 2)
```

两种情形下我们都得到 `G ⊢ [T.V == U.V]`，归纳完成。

若改为从 `G ⊢ T.V` 出发证同一结论，我们先用 **Sym** 把 `[T == U]` 翻过来，对 `[U == T]` 重复上面的构造得到 `[U.V == T.V]`，再用一次 **Sym** 即得 `G ⊢ [T.V == U.V]`。

> 译注：原书此处把引理的假设写成「至少有一个 `T.U` 或 `U.V` 是 valid 的」，但上下文（包括证明本身）通篇用的都是 `T.V` 与 `U.V`，`T.U` 疑为笔误，以 `T.V` 为准。译文已按 `T.V` 译出。

**例.** 若 `G` 是前面那个例子里的 generic signature，我们可以用这条引理，从 `G ⊢ [τ_0_1 == τ_0_0.SubSequence]` 和 `G ⊢ τ_0_1.Iterator.Element`，导出 `G ⊢ [τ_0_1.Iterator.Element == τ_0_0.SubSequence.Iterator.Element]`。

**定理.** 设 `G` 是一个 well-formed generic signature。若对某个 type parameter `T` 与 protocol `P` 有 `G ⊢ [T: P]`，则存在一个 valid type parameter `T′`，使得 `G ⊢ [T′: P]` 可以经由一个 principal derivation 导出，且 `G ⊢ [T == T′]`。

在看证明之前，读者不妨先回顾一下 `derived-requirements-summary.tex`（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)），并记住 conformance requirement 总是由下面三种步骤之一导出的：

```
[T: P]                                (Conf)
[T: P]                                (SameConf  [U: P]  [T == U])
[U.V: P]                              (AssocConf  [Self.V: P]_Q  [U: Q])
```

若 `G ⊢ [T: P]` 的导出过程里根本没用到 **SameConf**，那它已经是 principal 的了；同样，若最后一步是对某个 principal derivation 施加 **SameConf**，我们也就成了。真正的难点在于 **AssocConf** 可能施加在 **SameConf** 的结论上，这就要求我们把两段 derivation「解开」。

**证明.** 我们对 `G ⊢ [T: P]` 的 derivation 作结构归纳，在每一步同时构造出想要的那两段 derivation。

**基础情形.** 一条 **Conf** elementary statement 是结构归纳的基础情形，因为它没有前提。按我们的定义，一条 explicit conformance requirement 的 derivation 本身就是 principal 的，于是取 `T′ := T`。第一段 derivation 就是：

```
[T: P]                               (Conf)
```

至于第二段 derivation：注意 `G` 是 well-formed 的，而 `T` 出现在 `[T: P]` 里，所以 `G ⊢ T`。于是用 **Reflex** 推理规则从 `G ⊢ T` 导出 `G ⊢ [T == T]`：

```
1.  T                                (…)
2.  [T == T]                         (Reflex 1)
```

**归纳步骤.** 否则，我们手上这段 derivation 的最后一步施加的是 **SameConf** 或 **AssocConf**。先看 **SameConf**：

```
[T: P]                               (SameConf  [U: P]  [T == U])
```

由归纳假设，`G ⊢ [U: P]` 可以拆成我们想要的 principal derivation `G ⊢ [T′: P]`（对某个 `T′`）以及一条 same-type requirement 的 derivation `G ⊢ [U == T′]`。于是对 `G ⊢ [T == U]` 与 `G ⊢ [U == T′]` 施加 **Trans**，导出 `G ⊢ [T == T′]`。

剩下的情形是 derivation 以 **AssocConf** 结尾，此时 `T` 具有 `U.V` 的形状——也就是说，它是把某个 protocol generic signature `G_Q` 里的某个 type parameter `Self.V` 中的 `Self` 换成 `U` 得到的：

```
[U.V: P]                             (AssocConf  [Self.V: P]_Q  [U: Q])
```

这里就是「解开」的部分。`G ⊢ [U: Q]` 未必是 principal 的，但由归纳假设，它可以拆成一个 principal derivation `G ⊢ [U′: Q]`（对某个 `U′`）和一条 same-type requirement `G ⊢ [U == U′]`。我们对第一段 derivation 施加 **AssocConf**，得到一个对 `P` 的 conformance，只是 subject type 换成了另一个 `U′.V`：

```
1.  [U′: Q]                          (…)
2.  [U′.V: P]                        (AssocConf 1)
```

这就是我们要的 principal derivation，于是取 `T′ := U′.V`。由于 `G` 是 well-formed 的，我们还有 `G ⊢ U′.V`。上面那条引理的条件得到满足，于是可以导出 same-type requirement `G ⊢ [U.V == U′.V]`，换句话说 `G ⊢ [T == T′]`。

## The Conformance Path Graph

我们在 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 开始了这趟 type substitution 之旅，沿途有三个算法作为路标：

1. `substitution-maps.tex` 的 Substitute type 算法实现 type parameter substitution，它直接处理 generic parameter type，而把 dependent member type 的情形委托出去。
2. `conformances.tex` 的 Substitute dependent member type 算法用 local conformance lookup 来实现 dependent member type substitution。
3. 本章的 Local conformance lookup 算法实现 local conformance lookup，而把「找 conformance path」这件事委托出去。

有了上一节那条定理，我们确立了：在等价的意义下，每个 dependent member type 都能写成**某条** conformance path 的 type witness。这为上面这一整套提供了理论依据，但它并没有直接给出一个找 conformance path 的有效程序。不过，只要把问题改用图论的语言重述一遍，实现方式就浮出水面了。

**定义.** 设 `G` 是一个 generic signature。`G` 的 **conformance path graph** 是如下定义的有向图：

- 顶点是 `G` 的 abstract conformance 的等价类。每个顶点用它那个等价类的 reduced abstract conformance 作标签。
- 对每一对 abstract conformance `[T: P]` 与 `[T′: Q]`，只要存在某个 associated conformance projection `⟨Self.U: Q]` 使得 `[T′: Q]` 与 `[T: P] ⊗ ⟨Self.U: Q]` 等价，我们就添一条起点为 `[T: P]`、终点为 `[T′: Q]` 的边，边的标签是 `⟨Self.U: Q]`。

一条 conformance path 就是 conformance path graph 里的一条路径。这条路径从某个 root abstract conformance 出发，止于它所表示的那个 principal abstract conformance；途中经过的顶点，正是 Simplify conformance path 算法里 `[T: P]` 的各个中间值。我们此前在 `archetypes.tex` 的 The Type Parameter Graph 一节讨论 generic signature 的 type parameter graph 时研究过有向图。Conformance path graph 的构造与之类似，两者对照着看很有启发：

| | **Type parameter graph** | **Conformance path graph** |
|---|---|---|
| **Roots** | Generic parameter type | Root abstract conformance |
| **Vertices** | Reduced type parameter | Reduced abstract conformance |
| **Edges** | Associated type declaration | Associated conformance requirement |
| **Paths** | Type parameter | Conformance path |

上一节那条定理其实是一个关于 conformance path graph 的论断，因为它告诉我们：每个顶点都至少能从某个 root 顶点到达。

**定义.** 设 `(V, E)` 是一个有向图。若 `u, v ∈ V`，且存在一条路径 `p` 使 `src(p) = u` 且 `dst(p) = v`，我们就说 `v` 从 `u` **可达**（reachable）。注意每个 `v ∈ V` 总是经由 empty path `1_v` 从自身可达。

**例.** 我们来把前面那个例子的 conformance path graph 构造出来。那个 root abstract conformance 给了我们一条长度为 1 的 conformance path：

```
p_11 := [τ_0_0: Collection]
```

把 `Collection` 的每一条 associated conformance requirement 投影出来，得到两条长度为 2 的 conformance path：

```
p_21 := ⟨Self: Sequence] ⊗ p_11
p_22 := ⟨Self.SubSequence: Collection] ⊗ p_11
```

从 `p_21` 又得到一条长度为 3 的 conformance path：

```
p_31 := ⟨Self.Iterator: IteratorProtocol] ⊗ p_21
```

路径 `p_22` 又是一个对 `Collection` 的 conformance，它的两个 projection 再给出两条长度为 3 的 conformance path。我们最喜欢的那条 conformance path 就是下面的 `p_32`：

```
p_32 := ⟨Self: Sequence] ⊗ p_22
p_33 := ⟨Self.SubSequence: Collection] ⊗ p_22
```

最后，路径 `p_32` 可以延长成一条长度为 4 的 conformance path：

```
p_41 := ⟨Self.Iterator: IteratorProtocol] ⊗ p_32
```

到这一步，只剩从 `p_33` 出发的那些路径还没探索，但我们注意到 `p_22` 与 `p_33` 描述的是等价的 abstract conformance：

```
[τ_0_0.[Collection]SubSequence: Collection]
[τ_0_0.[Collection]SubSequence.[Collection]SubSequence: Collection]
```

因此探索 `p_33` 不会带来任何新东西，于是就结束了。要得到图的顶点集，我们把每条 conformance path 化简成一个 principal abstract conformance，再算出其 subject type 的 reduced type，得到 reduced abstract conformance：

```
p_11  →  [τ_0_0: Collection]
p_21  →  [τ_0_0: Sequence]
p_22  →  [τ_0_1: Collection]
p_31  →  [τ_0_0.[Sequence]Iterator: IteratorProtocol]
p_32  →  [τ_0_1: Sequence]
p_41  →  [τ_0_1.[Sequence]Iterator: IteratorProtocol]
```

于是我们这个 generic signature 的 conformance path graph 如下；root abstract conformance 在原书里用更深的灰底标出，这里用 `★` 标出。注意 `[τ_0_1: Collection]` 上有一个 **loop**——一条起点与终点相同的边：

```
★ τ_0_0: Collection
├── ⟨Self: Sequence] ───────────────→ τ_0_0: Sequence
│                                     └── ⟨Self.Iterator: IteratorProtocol] ──→ τ_0_0.Iterator: IteratorProtocol
└── ⟨Self.SubSequence: Collection] ─→ τ_0_1: Collection   ⟲ ⟨Self.SubSequence: Collection]
                                      └── ⟨Self: Sequence] ──→ τ_0_1: Sequence
                                          └── ⟨Self.Iterator: IteratorProtocol] ──→ τ_0_1.Iterator: IteratorProtocol
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

上面这个 conformance path graph 是有限的，但一般情况下并非如此，下一节我们就会研究无限的 conformance path graph。一般地**确实**成立的是：每个顶点只有有限多个直接后继，换句话说，共享同一个起点的边只有有限多条。于是，和 type parameter graph 一样，conformance path graph 是 **locally finite** 的（见 `archetypes.tex` 里 locally finite 的定义）。Locally finite 图有一条重要性质（可对路径长度作归纳来证明）：若固定 `v ∈ V` 与 `n ∈ ℕ`，那么起点为 `v`、长度为 `n` 的全体互异路径构成的集合必然是有限的。

要为一个 abstract conformance 找一条 conformance path，我们对 conformance path graph 作**广度优先搜索**。从那个有限的 root 顶点集合出发，把长度为 `n` 的所有路径都访问完，再去看长度为 `n + 1` 的路径。一旦找到一条表示给定 abstract conformance 所在等价类的路径，就停下来。事实上，这样找到的总是一条长度最小的路径。不过，长度最小的路径可能不止一条。Conformance path 会出现在 ABI 里——它是 symbol mangling 方案的一部分——所以我们必须做一个确定性的选择。

> 译注：本库在解析 mangled symbol 时消费的正是这套编码结果；conformance 与 requirement 在二进制里的落点见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)，PWT 槽位的投影见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

若两条 conformance path 表示的 principal abstract conformance 等价——换句话说，若两条路径终止于图中同一个顶点——我们就说这两条 conformance path **等价**。接下来我们给 conformance path 规定一个线性序，与 `generic-signatures.tex` 的 Reduced Type Parameters 一节里的 type parameter order 类似：短的路径排在长的前面，长度相同的两条路径则逐元素比较。（和 type parameter order 一样，conformance path order 也是一种 **shortlex order**，我们在 `monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 The Normal Form Algorithm 一节给出它的一般定义。）

**算法（Conformance path order）.** 输入两条 conformance path，记为 `x := x_m ⊗ ⋯ ⊗ x_1` 与 `y := y_n ⊗ ⋯ ⊗ y_1`，返回「`<`」「`>`」「`=`」三者之一。

1. （Shorter）若 `n < m`，则 `x < y`，返回「`<`」。
2. （Longer）若 `n > m`，则 `x > y`，返回「`>`」。
3. （Initialize）否则 `n = m`，必须逐元素比较。令 `i ← 1`。
4. （Equal）若 `i = n + 1`，两条 conformance path 完全相同，返回「`=`」。
5. （Compare）把 `x_i` 与 `y_i` 看成 conformance requirement，用 `building-generic-signatures.tex` 的 Requirement order 算法比较它们的 subject type 与 protocol。结果若不是「`=`」就返回它。
6. （Next）否则 `x_i` 与 `y_i` 相同。令 `i ← i + 1`，回到第 4 步。

Requirement order 一般而言只是偏序，但它在 conformance requirement 上是线性的，所以第 5 步不会返回「`⊥`」，conformance path order 也就同样是线性的。`generic-signatures.tex` 里证明 type parameter order 良基所用的论证，同样可以说明 conformance path order 是 **well-founded** 的。因此，conformance path 的每个等价类里都含有唯一的最小元，称为 **reduced conformance path**。

Conformance path order 算法虽是形式模型的一部分，编译器却并不直接实现它。取而代之的做法是：保证广度优先搜索在每一步都按递增顺序访问 requirement，这就足以确保我们总是先找到每个等价类里的 reduced conformance path。这个广度优先搜索为每个 generic signature `G` 关联一份持久状态：

- 一张哈希表，把 reduced abstract conformance 映到 conformance path。
- 一个整数 `N`，初值为 0。
- 一个可增长数组 `B`，存放所有长度为 `N` 的 conformance path，初值为空。
- 一个可增长数组 `B_1`，临时存放所有长度为 `N + 1` 的 conformance path。

下面终于是真正的算法了。每次调用要么立刻从表里返回一条已有的 conformance path，要么继续按递增顺序枚举 conformance path，直到我们要找的那一条出现在表里为止。

**算法（Find conformance path）.** 输入一个 generic signature `G` 和一个 valid abstract conformance `[T: P]`，输出 `[T: P]` 的 reduced conformance path。

1. （Assert）若 `requiresProtocol(G, T, P)` 为假，报错。
2. （Reduce）令 `T ← getReducedType(G, T)`。
3. （Check）若表里已有 `[T: P]` 的 conformance path，返回它。
4. （Initialize）若 `N > 0`，跳过这一步。否则，按 requirement order（见 `building-generic-signatures.tex` 的 Requirement order 算法）把 `G` 的每个 root abstract conformance 加进 `B`，并令 `N ← 1`。
5. （填充 `B_1`）对每条 conformance path `p ∈ B`：
   1. 对 `p` 应用 Simplify conformance path 算法，得到一个 principal abstract conformance `[T_p: P_p]`。
   2. 令 `T_p ← getReducedType(G, T_p)`，得到一个 reduced abstract conformance。
   3. 若表里已有 `[T_p: P_p]` 的 conformance path，跳过 d) 与 e)。
   4. 把键 `[T_p: P_p]`、值 `p` 加进表里。
   5. 按 requirement order 遍历 protocol `P_p` 的每条 associated conformance requirement `⟨Self.U: Q]`：把 `⟨Self.U: Q] ⊗ p` 加进 `B_1`。
6. （Repeat）交换 `B ↔ B_1`。清空 `B_1`。令 `N ← N + 1`。回到第 3 步。

第 1 步里，如果给定的 type parameter `T` 实际上并不 conform to `P`，我们就直接退出，因为那样永远也找不到 `[T: P]` 的 conformance path。前置条件一旦确立，由上一节那条定理加上我们对 conformance path order 的选择，就可以保证算法终止。特别地，这意味着第 5 步开始时 `B` 数组永远不会为空——否则我们就会陷入死循环，与那条定理矛盾。我们**不必**去说明它为什么不会为空！（不过还是说一下吧。若 `B` 为空而 `N > 0`，那说明我们这个 generic signature 的 conformance path 集合是有限的，而且在之前某次调用里已经把它们全部枚举完了。但这种情况下，第 3 步总会在我们走到第 5 步之前就返回一个值。）

**例.** 能终止固然好，可这个「有限」到底有多大？最坏情况下，Find conformance path 算法的运行时间关于 subject type parameter 的 length 是**指数**的。考虑下面这个 `M` 的 protocol generic signature `G_M`：

```swift
protocol M {
  associatedtype A: M
  associatedtype B: M
}
```

`G_M` 里的一条 conformance path 由 `[τ_0_0: M]` 打头，后面跟着 `⟨Self.A: M]` 与 `⟨Self.B: M]` 的任意组合。例如下面这条 conformance path 表示 `[τ_0_0.A.A.B.B: M]`：

```
⟨Self.B: M] ⊗ ⟨Self.B: M] ⊗ ⟨Self.A: M] ⊗ ⟨Self.A: M] ⊗ [τ_0_0: M]
```

`G_M` 的每一个 valid type parameter 都 conform to `M`；若 `T` 是某个长度为 `n` 的任意 valid type parameter，略一思索便知，我们很容易构造出一条同样长度为 `n` 的 conformance path 来表示 `[T: M]`。可惜 Find conformance path 算法没这么聪明，它只会把长度不超过某个上限的**所有** conformance path 都枚举一遍。我们这个 generic signature 有 1 条长度为 1 的 conformance path、2 条长度为 2 的、4 条长度为 3 的，一般地有 `2^(n-1)` 条长度为 `n` 的互异 conformance path。于是，若 `|T| = n`，我们要执行 `1 + 2 + ⋯ + 2^(n-1) = 2^n - 1` 次第 5 步的迭代：

```swift
func callee<T: M>(_: T.Type) {}

func caller<T: M>(_: T.Type) {
  callee(T.A.B.A.B.A.B.A.B.A.B.A.B.A.B.A.B.A.B.A.B.A.B.self)  // slow
}
```

至少到目前为止，我们还没在实践中观察到这种组合爆炸。在真实程序里，conformance path graph 往往相当简单，type parameter 也往往不会长得过分。

现在，我们歇一口气。Substitute type 算法的实现差不多已经补全了，只剩 `getReducedType()` 与 `requiresProtocol()` 这两个 generic signature query，它们的实现在原书第四部分（The Requirement Machine）里讲。值得一提的是，上面那个病态的 protocol `M` 出于别的原因也相当有意思，它会在 `monoids.tex` 的 A Swift Connection 一节里再次出现。

## Recursive Conformances

在 `archetypes.tex` 的 The Archetype Builder 一节里，我们把 generic signature 按复杂度递增分成了三族。回顾一下：一个 generic signature 的 type parameter 总共可能只有有限多个；也可能有无穷多个，但它们坍缩成有限多个等价类；最一般的情形是等价类本身就有无穷多个。

换成 type parameter graph 的语言可以这样重述。前两种情形下，type parameter graph 是有限的；而在第一种情形下，type parameter graph 还是一个 **directed acyclic graph**（有向无环图，见 `archetypes.tex` 里的定义）。的确，正如 `archetypes.tex` 里那个 `Collection` 的图所示，只要沿着一个 cycle 绕任意多圈，就能给出一串无穷多个互相等价的 type parameter。

下面我们会看到，如果改用 conformance path graph 来分类，也能得到类似的分族：我们的 conformance path graph 可能是有限且无环的，此时 conformance path 只有有限多条；也可能有限但含有 cycle，此时等价类有限多个，而其中至少一个含有无穷多条路径；再或者，conformance path 的等价类本身就有无穷多个。

事实是这两套分类互有重叠，但并不完全重合。要弄明白为什么，我们再引入一个有向图。

**定义.** **Protocol dependency graph** 是这样一个有向图：它的顶点是 protocol declaration，更确切地说，它的顶点集就是 name lookup 能看见的全体 protocol declaration，即 `conformances.tex` 的 Conformance Lookup 一节里记作 `Proto` 的那个集合。边集由所有 protocol 的所有 associated conformance requirement 组成：`[Self.U: Q]_P` 这条边的起点是 `P`，终点是 `Q`。

我们在 `basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)） 的 Protocol Components 一节讲 generic signature 的 requirement machine 怎么构造时还会再遇到 protocol dependency graph。

**例.** Protocol 的全集 `Proto` 是有限的，但可能相当大。不过它的边集相当稀疏，实践中这个图包含许多互不相连的**连通分支**（connected component）。如果我们假装前面代码清单里的 `Collection`、`Sequence` 和 `IteratorProtocol` 活在它们自己的小宇宙里，那么 protocol dependency graph 就可以画成下面这样。注意 `Collection` 上有一个 loop：

```
Collection  ⟲ ⟨Self.SubSequence: Collection]
    │
    │ ⟨Self: Sequence]
    ↓
Sequence
    │
    │ ⟨Self.Iterator: IteratorProtocol]
    ↓
IteratorProtocol
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

**例.** `generic-signatures.tex` 里那个 protocol `N` 的 protocol dependency graph 就是单独一个带 loop 的顶点：

```swift
protocol N {
  associatedtype A: N
}
```

```
N  ⟲ ⟨Self.A: N]
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

更一般地，一个 cycle 可以牵涉多条 associated conformance requirement：

```swift
protocol Fee {
  associatedtype Foo: Foe
}

protocol Foe {
  associatedtype Foo: Fee
}
```

```
Fee ──⟨Self.Foo: Foe]──→ Foe
 ↑                        │
 └──⟨Self.Foo: Fee]───────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

我们给这样的 associated conformance requirement 起个名字：

**定义.** 若一条 associated conformance requirement 对应的边处在 protocol dependency graph 的某个 cycle 上，就称它是 **recursive** 的。

在前面三个例子里，`[Self.SubSequence: Collection]_Collection`、`[Self.A: N]_N`、`[Self.Foo: Foe]_Fee` 和 `[Self.Foo: Fee]_Foe` 全都是 recursive 的。回忆 `archetypes.tex` 的 The Archetype Builder 一节：recursive conformance requirement 是在 Swift 4.1 才出现的（SE-0157）；在那之前，protocol dependency graph 总是无环的。

要把 conformance path graph 和 protocol dependency graph 联系起来，考虑函数 `π: Conf(G) → Proto`：

```
π([X: P]) := P
```

这个操作对 abstract conformance 和 concrete conformance 都有定义。若只看它在 abstract conformance 上的限制，就会发现它把 conformance path graph 的顶点映到 protocol dependency graph 的顶点。而且，若 conformance path graph 里两个顶点由一条边相连，则 protocol dependency graph 里对应的两个顶点也由一条带相同标签的边相连。

**定义.** 设 `X := (V_X, E_X)` 与 `Y := (V_Y, E_Y)` 是有向图。一个 **graph homomorphism** `f: X → Y` 是一对函数：把顶点映到顶点的 `f_v: V_X → V_Y`，和把边映到边的 `f_e: E_X → E_Y`，且对所有 `e ∈ E_X`：

```
f_v(src(e)) = src(f_e(e))
f_v(dst(e)) = dst(f_e(e))
```

注意只要 `Y` 在某个顶点处有一个 loop——即一条起点与终点相同的边——`f_e` 就允许把 `src(e)` 与 `dst(e)` 映到那同一个顶点。

我们也可以把 graph homomorphism 作用到 `G_1` 的一条路径上：先作用到起点，再依次作用到每条边。由归纳法可知，结果是 `G_2` 里的一条合法路径。特别地，若把 `π` 作用到 conformance path graph 的一条路径上，就得到 protocol dependency graph 里的一条路径。Protocol dependency graph 里的一条路径是一串 associated conformance projection，所以它就像一条去掉了第一步的 conformance path。从 `P_1` 到 `P_n` 的路径的一般形式可以记作：

```
⟨Self.U_n: P_n] ⊗ ⋯ ⊗ ⟨Self.U_1: P_1]
```

现在我们可以陈述下面这个有意思的事实了。

**命题.** 设 `G` 是一个 generic signature。以下两条等价：

1. `G` 的 conformance path 集合是无限的。
2. 存在一对 protocol `P` 与 `Q`（可以相同），使得 protocol dependency graph 里有一条从 `P` 到 `Q` 的路径，且 `Q` 处有一个由 recursive conformance requirement 组成的 cycle；同时 `G` 声明了一条 explicit conformance requirement `[T: P]`。

**证明.** `(1 ⇒ 2)` 设我们拿到了 `G` 的一个无限的 conformance path 集合。任何固定长度的路径都只有有限多条，所以这个集合里必然含有任意长的 conformance path。于是取一条 conformance path `s_n ⊗ ⋯ ⊗ s_1`，使 `n > |Proto|`，那么 protocol dependency graph 里对应的路径 `π(s_n ⊗ ⋯ ⊗ s_1)` 必然不止一次地访问某个顶点 `Q`。这就展示出 protocol `Q` 处的一个 cycle。再令 `P := π(s_1)`，可见 `s_n ⊗ ⋯ s_2` 就是我们要的、protocol dependency graph 里从 `P` 到 `Q` 的那条路径，而 `s_1` 就是我们要的 explicit conformance requirement `[T: P]`。

`(2 ⇒ 1)` 我们为每个 `n ∈ ℕ` 造出一条互异的 conformance path `p_n`，做法如下：取 root abstract conformance `[T: P]`，把 protocol dependency graph 里从 `P` 到 `Q` 那条路径上经过的 associated conformance projection 逐个接上去。这就给出一条表示某个对 `Q` 的 abstract conformance 的 conformance path。然后，再把 `Q` 处那个 cycle 上经过的边接上去，重复 `n` 次。

Swift 不允许 protocol 继承出现循环——这意味着 protocol dependency graph 里每个 cycle 上都至少有一条 associated conformance requirement 的 subject type 不是 `Self`。在上面的证明里，绕 `Q` 处那个 cycle 跑「一圈」因此至少会让 subject type parameter 的长度加一，所以我们那条 conformance path `p_n` 表示的是某个 `[T: Q]`，且 `|T| ≥ n`。若 `G` 是 well-formed 的，那么这个 `T` 必然是 `G` 的一个 valid type parameter。于是立即得到：

**命题.** 设 `G` 是一个 well-formed generic signature。若 `G` 的 conformance path 集合是无限的，则 `G` 的 valid type parameter 集合也是无限的。

因此，若 `G` 的 valid type parameter 集合是有限的——也就是说 `G` 的 type parameter graph 有限且无环——那么 `G` 的 conformance path graph 也必然有限且无环。不过我们不能把它加强成「当且仅当」，下面这个例子说明了这一点。

**例.** 设 `G` 是下面这个 protocol extension 的 generic signature：

```swift
protocol Tip { associatedtype Top }
extension Tip where Self == Self.Top {}
```

`G` 的 type parameter graph 有限但不无环，因为它是单独一个带标签为「`.Top`」的 loop 的顶点；而 `G` 的 conformance path graph 却是有限且无环的，因为它是单独一个没有任何边的顶点。我们可以导出一串无穷多个互相等价的 type parameter：`τ_0_0`、`τ_0_0.Top`、`τ_0_0.Top.Top`，依此类推。`G` 的所有 valid type parameter 也都 conform to `Tip`，但 root abstract conformance 只有 `[τ_0_0: Tip]` 一个，又没有任何 associated conformance requirement，所以实际上我们只有**一条**平凡的 conformance path，就是 `[τ_0_0: Tip]`。

不过，若改成去数等价类，我们就能得到一个更强的结论。

**命题.** 设 `G` 是一个 generic signature。以下两条等价：

1. `G` 的 type parameter 等价类集合是无限的。
2. `G` 的 conformance path 等价类集合是无限的。

**证明.** `(1 ⇒ 2)` 我们从每个等价类里取出 reduced type parameter，再把 generic parameter type 那个有限子集丢掉，剩下的就是一个无限的 reduced dependent member type 集合。考虑函数 `f`，它把 dependent member type `T.[P]A` 映到 abstract conformance `[T: P]`。每个 conformance 都只有有限多个 type witness，所以把 `f` 作用到一个无限的 reduced bound dependent member type 集合上，输出必然是一个无限的 reduced abstract conformance 集合。接着我们为每个 reduced abstract conformance 找一条 conformance path，就得到一个无限的、两两不等价的 conformance path 集合。

`(2 ⇒ 1)` 我们从每个等价类里挑一条 conformance path，并求出各自的 reduced abstract conformance。这给出一个无限的 reduced abstract conformance 集合。考虑函数 `g`，它把一个 abstract conformance 映到它的 subject type。subject type 相同的互异 reduced abstract conformance 只可能有有限多个，因为 `Proto` 里的 protocol 只有有限多个。于是 `g` 把这个无限的 reduced abstract conformance 集合映成一个无限的 reduced type parameter 集合。

总结一下：把 type parameter graph 与 conformance path graph 放在一起考虑，可以把 generic signature 的分类细化成**四**族：

1. 两个图都有限且无环。
2. 两个图都有限，但只有 conformance path graph 无环。
3. 两个图都有限，且都不无环。
4. 两个图都无限。

下面是 Dénes Kőnig 的一个经典结果（见 Kőnig 1936《Theory of Finite and Infinite Graphs》，或 Knuth《The Art of Computer Programming》第 1 卷第 2.3.4.3 节）：

**定理（Kőnig's infinity lemma）.** 设 `(V, E)` 是一个有向图，并固定一个有限的 root 顶点子集 `R ⊆ V`。假设下列条件成立：

1. 顶点集 `V` 是无限的。
2. 该图是 locally finite 的，即对每个 `v ∈ V`，满足 `src(e) = v` 的 `e ∈ E` 只有有限多条。
3. 每个顶点都至少可从某个 root 到达，即对每个 `v ∈ V` 都存在一条路径 `p`，使 `src(p) ∈ R` 且 `dst(p) = v`。

在这些假设下，`V` 含有一个由互异顶点组成的无限序列 `v_1, v_2, …`，使得相邻的每一对顶点 `v_j` 与 `v_{j+1}` 都由 `E` 中的一条边相连。

**证明.** 先引入一些记号。一条 **simple** path 是不重复访问同一顶点的路径。若 `src(p) = src(q)` 且 `p` 所经过的边序列是 `q` 所经过的边序列的前缀，我们就说路径 `q` **延长**（extend）路径 `p`。然后定义 `S(p)` 为延长给定 simple path `p` 的全体 simple path 构成的集合。另外，回忆一下我们表示 empty path 的记号。

若 `r ∈ R`，则 `S(1_r)` 就是从 `r` 可达的全体顶点的集合。由假设，每个 `v ∈ V` 都可从某个 `r ∈ R` 到达，但 `R` 有限而 `V` 无限，所以至少存在一个 `r ∈ R` 使集合 `S(1_r)` 无限。令 `p_1 := 1_r`，`v_1 := r`。

现在，设我们有一条 simple path `p_i`，它访问了顶点 `v_1, …, v_i`，且 `S(p_i)` 无限。考虑满足 `src(e) = dst(p_i)` 的边 `e ∈ E` 构成的集合。由于图是 locally finite 的，这个集合是有限的，因此至少有一条这样的边 `e` 使 `S(p_i ∘ e)` 无限。令 `p_{i+1} := p_i ∘ e`，`v_{i+1} := dst(e)`。

反复这样做就能生成任意长度的路径，结论随之成立。

所以，如果我们手上是一个无限的 generic signature，那么在与之关联的这两个图里都能找到一条 **ray**，也就是一条无限路径。我们来看 protocol `N`，它的整个图就是一条 ray。`G_N` 的 type parameter graph 在 `archetypes.tex` 里已经见过了。`G_N` 的 conformance path graph 与之相同，只是标签不一样：

```
★ τ_0_0: N ──⟨Self.A: N]──→ τ_0_0.A: N ──⟨Self.A: N]──→ τ_0_0.A.A: N ──⟨Self.A: N]──→ ⋯
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

现在，设我们对某个 conformance `[X: N]` 有一张 protocol substitution map `Σ_{[X: N]}`。可以设想把这张 substitution map 应用到 `G_N` 的 conformance path graph 的每个顶点上，得到一个对 `N` 的 conformance 的无限序列：

```
[τ_0_0: N] ⊗ Σ_{[X: N]}     = [X: N]
[τ_0_0.A: N] ⊗ Σ_{[X: N]}   = ⟨Self.A: N] ⊗ [X: N]
[τ_0_0.A.A: N] ⊗ Σ_{[X: N]} = ⟨Self.A: N] ⊗ ⟨Self.A: N] ⊗ [X: N]
…
```

和 abstract conformance 一样，concrete conformance 之间也由 associated conformance projection 联系着。事实上，把一张 substitution map 应用到 conformance path graph 的每个顶点上所得到的那一堆 substituted conformance，也可以被赋予有向图的结构。

### Conformance substitution graph

照例，下文中 `G` 与 `H` 是 generic signature，`Σ ∈ Sub(G, H)` 是一张 substitution map。首先我们在 `Conf(H)` 上定义一个等价关系：两个 conformance 等价，当且仅当它们指的是同一个 protocol，且它们的 conforming type 在 `Type(H)` 的 reduced type equality 关系下等价。现在，若把 `Σ` 应用到 `G` 的 conformance path graph 的每个顶点上，就会看到每个顶点都映到 `Conf(H)` 里的一个 conformance 等价类。正如 `conformances.tex` 的 Associated Conformances 一节所见，这个映射与 associated conformance projection 是相容的。

**定义.** `Σ` 的 **conformance substitution graph** 是如下定义的有向图：

- 顶点是 `[T: P] ⊗ Σ` 在上述关系下的等价类，其中 `[T: P]` 取遍 `G` 的所有 abstract conformance。
- 边关系就是 associated conformance projection。

有了这个构造，local conformance lookup 就成了一个从 `G` 的 conformance path graph 到 `Σ` 的 conformance substitution graph 的 graph homomorphism。（Conformance substitution graph 也解释了 Swift runtime 里 witness table 的实例化过程。一个 generic function 一开始为自己 generic signature 的每条 explicit conformance requirement 各收到一张 witness table。Witness table 随后又指向它们各自 associated conformance 的 witness table；这一步是靠一个 runtime entry point 惰性填充的，所以我们只会探索 conformance substitution graph 的某个有限子图。）

> 译注：本库在离线读取二进制时看到的正是这张图被「冻结」下来的那一份：protocol witness table 的 associated conformance 槽位、以及它们指向的 conformance descriptor。相关的槽位投影见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)；associated type 的 witness 则记在 `__swift5_assocty` 里，本库靠它解出关联类型字段的布局，见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

现在我们要问：若 `[X: N]` 是一个对 `N` 的 conformance，`Σ_{[X: N]}` 的 conformance substitution graph 长什么样？图论里另一个经典结果告诉我们，一条 ray 在 graph homomorphism 下的像必然是下面三者之一：

1. 一个 cycle。
2. 另一条无限 ray。
3. 一条通向某个 cycle 的有限路径。

因此，若从 `[X: N]` 出发反复施加 `⟨Self.A: N]`，最终必然发生下面三件事之一：

1. 我们回到 `[X: N]`。
2. 我们产生出一个由互异的、对 `N` 的 conformance 构成的无限序列。
3. 我们停在一个此前已经见过、但不是 `[X: N]` 的 conformance 上。

下面我们为每种行为各造一个例子，最后再给一个意外。

### Recursive normal conformances

我们可以用 normal conformance 组出一个 cycle：

```swift
struct Toe: N { typealias A = Tie }
struct Tie: N { typealias A = Pie }
struct Pie: N { typealias A = Poe }
struct Poe: N { typealias A = Toe }
```

注意到：

```
⟨Self.A: N] ⊗ [Toe: N] = [Tie: N]      ⟨Self.A: N] ⊗ [Pie: N] = [Poe: N]
⟨Self.A: N] ⊗ [Tie: N] = [Pie: N]      ⟨Self.A: N] ⊗ [Poe: N] = [Toe: N]
```

特别地：

```
⟨Self.A: N] ⊗ ⟨Self.A: N] ⊗ ⟨Self.A: N] ⊗ ⟨Self.A: N] ⊗ [Toe: N] = [Toe: N]
```

下面是 `Σ_{[Toe: N]}` 的 conformance substitution graph：

```
★ Toe: N ──→ Tie: N ──→ Pie: N ──→ Poe: N ──┐
  ↑                                          │
  └──────────────────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Recursive specialized conformances

要得到一个无限的 conformance substitution graph，我们从一个 conform to `N` 的 generic nominal type 出发：

```swift
struct G<T>: N {
  typealias A = G<G<T>>
}
```

这里那条 associated conformance requirement 是由一个 specialized conformance 来 witness 的。我们把 `τ_0_0` 简记为 `τ`，于是令 `Σ := {τ ↦ G<τ>}`，可以看到：

```
⟨Self.A: N] ⊗ [G<τ>: N] = [G<G<τ>>: N] = [G<τ>: N] ⊗ Σ
```

更一般地，我们得到一个由互异 specialized conformance 组成的无限序列：

```
⟨Self.A: N] ⊗ ⋯ ⊗ ⟨Self.A: N] ⊗ [G<τ>: N] = [G<τ>: N] ⊗ Σ ⊗ ⋯ ⊗ Σ
└──────────  n 次  ──────────┘                          └──  n 次  ──┘
```

下面是 `Σ_{[G<τ>: N]}` 的 conformance substitution graph：

```
★ G<τ>: N ──→ G<G<τ>>: N ──→ G<G<G<τ>>>: N ──→ ⋯
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Recursive abstract conformances

这里我们有一个 generic nominal type，它的 associated conformance 是由一个 abstract conformance 来 witness 的：

```swift
struct H<T: N>: N {
  typealias A = T
}
```

同样地，把 `τ_0_0` 写成 `τ` 会方便些。注意：

```
⟨Self.A: N] ⊗ [H<τ>: N] = [τ: N]
```

现在，把前面那几个 nominal type `Toe`、`Tie`、`Pie`、`Poe` 拿过来，考虑 specialized conformance `[H<H<Toe>>: N]`。我们给两张 substitution map 起个名字，因为它们下面会反复出现：

```
Σ_H   := {τ ↦ H<τ>; [τ: N] ↦ [H<τ>: N]}
Σ_Toe := {τ ↦ Toe;  [τ: N] ↦ [Toe: N]}
```

用上面的记号，我们有：

```
[H<H<Toe>>: N] = [H<τ>: N] ⊗ Σ_H ⊗ Σ_Toe
```

于是可以算出 `⟨Self.A: N] ⊗ [H<H<Toe>>: N]`：

```
⟨Self.A: N] ⊗ [H<H<Toe>>: N]
  = ⟨Self.A: N] ⊗ [H<τ>: N] ⊗ Σ_H ⊗ Σ_Toe
  = [τ: N] ⊗ Σ_H ⊗ Σ_Toe
  = [H<τ>: N] ⊗ Σ_Toe
  = [H<Toe>: N]
```

若再投影一次 associated conformance，得到：

```
⟨Self.A: N] ⊗ [H<Toe>: N]
  = ⟨Self.A: N] ⊗ [H<τ>: N] ⊗ Σ_Toe
  = [τ: N] ⊗ Σ_Toe
  = [Toe: N]
```

下面是 `Σ_{[H<H<Toe>>: N]}` 的 conformance substitution graph：

```
★ H<H<Toe>>: N ──→ H<Toe>: N ──→ Toe: N ──→ Tie: N ──→ Pie: N ──→ Poe: N ──┐
                                   ↑                                        │
                                   └────────────────────────────────────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Non-terminating substitutions

这个例子展示了一种新行为：

```swift
struct S: N {
  typealias A = F<S>
}

struct F<T: N>: N {
  typealias A = T.A.A
}
```

我们定义这两张 substitution map：

```
Σ_S := {τ ↦ S;    [τ: N] ↦ [S: N]}
Σ_F := {τ ↦ F<τ>; [τ: N] ↦ [F<τ>: N]}
```

`[S: N]` 的 associated conformance 可以用 `Σ_S` 表达出来：

```
⟨Self.A: N] ⊗ [S: N] = [F<τ>: N] ⊗ Σ_S                        (1)
```

我们也用一条 conformance path 把 `[F<τ>: N]` 的 type witness 写出来：

```
⟨N|A ⊗ [F<τ>: N] = τ.A.A = ⟨N|A ⊗ ⟨Self.A: N] ⊗ [τ: N]        (2)
```

现在我们来算下面这个对 `f()` 的调用的代入后返回类型：

```swift
func f<T: N>(_: T) -> T.A {...}

let value = f(F<S>())  // What is the type of `value'?
```

这次调用的 substitution map 是 `Σ_F ⊗ Σ_S = {τ ↦ F<S>; [τ: N] ↦ [F<S>: N]}`，而要被代入的 dependent member type 是 `τ.A`。我们先把这个 dependent member type 展开，并应用恒等式 `[τ: N] ⊗ Σ_F = [F<τ>: N]`：

```
τ.A ⊗ Σ_F ⊗ Σ_S
  = ⟨N|A ⊗ [τ: N] ⊗ Σ_F ⊗ Σ_S
  = ⟨N|A ⊗ [F<τ>: N] ⊗ Σ_S                                    (3)
```

再应用 (2)，随后应用恒等式 `[τ: N] ⊗ Σ_S = [S: N]`，可以继续往下走：

```
  = ⟨N|A ⊗ ⟨Self.A: N] ⊗ [τ: N] ⊗ Σ_S
  = ⟨N|A ⊗ ⟨Self.A: N] ⊗ [S: N]
```

不幸的是，我们唯一剩下的动作是应用 (1)，可那又把我们带回了 (3)：

```
  = ⟨N|A ⊗ [F<τ>: N] ⊗ Σ_S
```

### Normal forms

我们一直默默假设：任何用 `⊗` 这个「唱机转盘」运算符写出来的合法表达式，都能经由有限次代数恒等式的应用化成一个 **normal form**——一个单独的类型、substitution map 或 conformance——直到表达式里再也不出现 `⊗` 为止。结果这个假设是错的。在上一个例子里，唱片一直转，派对停不下来：`⊗ ⊕ ⊗ ⊕ ⊗ ⋯`

我们证明了**寻找** conformance path 的 Find conformance path 算法总会终止，但显然不能对**求值** conformance path 的 Local conformance lookup 算法说同样的话！Local conformance lookup——更一般地说，`⊗` 运算符——实际上是一个**偏函数**（partial function），它并不总能给出结果。同样地，上面描述的那张 substitution map `Σ_S` 并**不拥有**一个 conformance substitution graph。

在目前这个时点上，如果尝试一次不终止的 type substitution，编译器会以 stack overflow 结束。Local conformance lookup 算法本身只是一个计数循环，递归是从第 4 步冒出来的：若 `C` 是一个 specialized conformance，从 `C` 投影一个 associated conformance 就要把某张 substitution map 应用到另一个 conformance 上；若那个 conformance 是 abstract 的，我们就又递归地调回 local conformance lookup。我们这个例子恰好把一切都安排得刚刚好，使得我们最终反复做的是**同一次** local conformance lookup。

## The Halting Problem

将来，编译器应该检测出不终止的 type substitution 并给出诊断，而不是直接崩溃。有两条路子马上会想到：

1. 给每一次 type substitution 都设一个操作次数上限，超过就报错终止。
2. 试着提前检测这种行为：仔细分析程序里所有的 substitution map 与 conformance，把那些编码了不终止计算的拒掉。

结果是，一般情况下我们没法指望做得比上面的 (1) 更好。要理解为什么，得先回顾一点可计算性理论。这方面的经典教材是 Cutland 1980《Computability: An Introduction to Recursive Function Theory》，而 MacCormick 2018《What Can Be Computed?: A Practical Guide to the Theory of Computation》的入门门槛更低一些。

### Computable numbers

1937 年，Alan Turing 着手把「**可计算数**」这个说法形式化，也就是要说清 `1/3`、`(1+√5)/2` 和 `π := 3.14159…` 在什么意义下是可计算的（Turing 1937,《On Computable Numbers, with an Application to the Entscheidungsproblem》）。如果从「每个整数都可以由一个有限的二进制数字序列表示，因而『本质上』是可计算的」这个观察出发，那么剩下要做的就是定义区间 `(0, 1)` 内的实数的可计算性。这样一个数的二进制表示由小数点后一个无限的「0」「1」数字序列构成；只要我们能写下一个**有效程序**（effective procedure），把这个数字序列生成到任意精度，这个数就是可计算的。

为了描述这样的有效程序，Turing 引入了我们今天称作 **Turing machine** 的形式体系。精确定义可以在文献里找到，就本文的目的而言，一台 Turing machine 是这样的东西：

1. 固定的**机器描述**由以下部分组成：一个有限的**符号**集（用「0」和「1」就够）、一个有限的**状态**集（其中之一是**初始状态**），以及一张把（状态, 符号）键映到（状态, 符号, 方向）值的表。
2. Turing machine 的**读写头**在一条由连续存储单元组成的**纸带**上读写符号，每个单元要么含有一个符号，要么是空白。机器有一个寄存器保存它的**当前状态**，执行开始时它就是初始状态。
3. 每一步，机器读出读写头所在位置的符号，用这个符号连同当前状态构成一个键，去转移表里查。查到的值决定了下一个状态、要在读写头处写入的新符号，以及读写头移动的方向——读写头只能向左或向右移动一格。

举例来说，要确立 `π` 是可计算的，我们可以给出一台 Turing machine，它从空白纸带开始执行，然后永远不停地把 `π` 的二进制数字一位位写到纸带上。只要我们愿意等得够久，就能用这台 Turing machine 生成任意精度的 `π` 的近似值。

有一点很重要：即便我们要表示的数有一个有尽的二进制展开（比如 `1/2`），我们仍然要求那台 Turing machine 永远输出数字下去，在这个例子里就是在末尾产生一个无限长的「0」序列。我们不能用一台最终停止产生数字的 Turing machine 来表示一个可计算数，因为那样我们就无法判断：究竟是二进制展开真的结束了，还是只需再让机器多跑一会儿、它就会再输出一位数字。Turing 把持续永远输出二进制数字的机器称为「circle-free」的。一台「circular」的机器就是不 circle-free 的机器，也就是在输出有限多位二进制数字之后「卡住」了。

一个自然的问题随之而来：有没有一个有效程序，能判定给定的一台 Turing machine 是不是 circle-free 的？我们把这个问题精确化如下。一台 Turing machine 不必从空白纸带开始，更一般地它可以接收一个输入串，我们设想执行开始时这个串已经在纸带上了。为了把一台 Turing machine 作为输入传给另一台 Turing machine，我们定义 Turing machine 的**标准描述**（standard description），它把机器的完整状态编码成一个有限的符号串。若一个串表示某台 circle-free 机器的标准描述，我们就说它是**satisfactory** 的；于是我们要找的是这样一台 circle-free 的 Turing machine：输入串 satisfactory 时它输出「1」「1」……，否则输出「0」「0」……。Turing 证明了这是不可能的。

**定理.** 不存在能判定给定输入串是否 satisfactory 的 circle-free Turing machine。

### The Church-Turing thesis

今天我们用一种不同但等价的方式来陈述 Turing 的结果。我们不再谈 circle-free 机器，而是谈**停机问题**（halting problem），它问的是一台 Turing machine 最终会不会到达某个固定的终止「停机状态」：

**定理.** 不存在有效程序能判定给定的一台 Turing machine 是否在有限步内停机。

Turing 的结果同样适用于任何能**模拟** Turing machine 的形式体系，而这样的体系有很多。与 Turing 的工作同时期，Alonzo Church 引入了 **lambda calculus**，并证明了一个类似的不可判定性结论（Church 1936,《An Unsolvable Problem of Elementary Number Theory》）。Lambda calculus 是 **Turing-complete** 的，意思是每个 lambda 可计算的函数都可以由 Turing machine 计算，反之亦然。事实上，迄今为止发现的每一种「有效程序」或「可计算函数」的形式化都是如此。**Church-Turing thesis** 就是这样一条观察：每一种足够一般的计算形式，其表达能力都与 Turing machine 相同。

Swift 编程语言是 Turing-complete 的，因为我们可以用一段 Swift 程序模拟一台 Turing machine 的执行，而且至少在理论上，我们也可以用一台 Turing machine 模拟任何一段 Swift 程序的执行。下面我们给出上面那条定理的一个非正式证明，不过用的是 Swift 而不是 Turing machine。

**证明.** 设想一种没有任何副作用、也没有任何不确定性的 Swift 方言，但它多了一种新的自省设施，能把任意一个函数值转换成它的完整源代码、语法树、或者随便什么形式。借助这个设施，我们也许可以试着实现一个 `halts()` 函数，它接收另一个函数作为输入，执行任意但有限多的计算，然后返回一个布尔值，告诉我们输入的那个函数若被调用会不会停机：

```swift
// Return true if f() would halt, or false if f() would run forever.
func halts(_ f: () -> ()) -> Bool {...}
```

现在，看看我们运行下面这个函数时会发生什么：

```swift
func naughty() {
  if halts(naughty) { while true {} }  // I won't do what you tell me!
}
```

如果 `halts(naughty)` 返回 true，那么 `naughty()` 会进入死循环而不停机，于是 `halts(naughty)` 不可能为 true。如果 `halts(naughty)` 返回 false，那么 `naughty()` 其实是会停机的，于是 `halts(naughty)` 看起来也不可能为 false。剩下唯一的可能性是 `halts(naughty)` 永远跑下去、什么也不返回，但这与我们假设的「`halts()` 自己能在有限步内作出判断」相矛盾。每种结果都导向矛盾，所以 `halts()` 的正确实现不可能存在——停机问题是**不可判定的**。

虽然这不是一个严格的证明，但关键直觉是：一旦我们的形式系统足够有表达力，我们总能「智取」任何号称能做终止性检查的算法，无论它多精巧——办法就是把这个终止性检查器本身编码进我们的形式体系里，然后专门做它所说的反面。

> 译注：这条结论对本库有直接后果——从二进制里把 associated type 或 conformance 一路解出来，本质上就是在求值一条 conformance path，因此不可能保证总能得出结果。本库的做法是：算不出来就把失败作为事件上报并诚实降级，而不是猜一个值填上去，见 [EventBasedDegradationReporting.md](../EventBasedDegradationReporting.md)。

### Tag systems

下面我们来证明 Swift 的 type substitution 代数同样是 Turing-complete 的，因此一段 Swift 程序可以要求编译器在**编译期**执行任意计算。我们不去直接编码一台 Turing machine，而是考虑 **tag system**——一种由 Emil L. Post 在 1943 年首次引入的计算形式体系（Post 1943,《Formal Reductions of the General Combinatorial Decision Problem》）。

**定义.** 一个 **tag system** 由以下部分组成：

- 一个有限的符号字母表。
- 一个固定的 `n ∈ ℕ`，称为**删除数**（deletion number）。（可以假设 `n > 1`，否则这个 tag system 相当平凡。）
- 一张把每个符号映到一个有限符号串的表。这个串称为该符号的**产生式**（production）。

与 Turing machine 一样，tag system 也在一条符号纸带上操作，但求值规则更简单。设想有**两个**读写头，都朝同一方向移动。第一个头每次读一个符号，并把这个符号传给第二个头，后者随即按对应的产生式规则往纸带上写零个或多个符号。删除数则告诉读头要跳过多少个位置。初始状态下，机器把读头放在输入串的开头，把写头放在末尾。如果读头追上了写头，求值就停止，否则这场追逐永远持续下去。

**算法（Evaluate tag system）.** 输入一张产生式规则表、一个删除数 `n` 和一个串。反复修改这个输入串。

1. 若串的长度小于删除数 `n`，停机。
2. 从串的开头读一个符号。
3. 把这个符号的产生式写到串的末尾。
4. 从串的开头删掉 `n` 个符号。
5. 回到第 1 步。

上面这套东西在任何 Turing-complete 的编程语言里都很容易实现。远没那么显然的是，我们也能反过来走，把任意一台 Turing machine 翻译成一个 tag system；这一点直到 1961 年才确立（见 Minsky 1961,《Recursive Unsolvability of Post's Problem of "Tag" and other Topics in Theory of Turing Machines》，或 Minsky 1967,《Computation: Finite and Infinite Machines》）。这意味着 tag system 是 Turing-complete 的，因而它们的停机问题同样不可判定。下面我们来看一个不平凡的 tag system。

### The Collatz conjecture

**Collatz 猜想**（以 Lothar Collatz 命名）是数论里一个著名的未解问题，讲的是下面这个函数 `f: ℕ → ℕ`：

```
        ⎧ n/2      若 n 是偶数
f(n) =  ⎨
        ⎩ 3n+1     若 n 是奇数
```

从任意 `n ∈ ℕ` 出发，反复把 `f` 作用到 `n` 上，就能构造出一个自然数的无限序列。这称为 `n` 的 **Collatz 序列**：

```
n, f(n), f(f(n)), f(f(f(n))), …
```

例如取 `n = 3`，得到下面这个 Collatz 序列：

```
3, 10, 5, 16, 8, 4, 2, 1, 4, 2, 1, …
```

序列一旦到达 1，之后就永远在 1、4、2、1 之间循环。除了 `n = 0` 这个平凡情形，已知的每个 Collatz 序列最终都会到达 1，但这一点是否普遍成立，仍是一个悬而未决的问题。一个了不起的事实是，Collatz 序列可以由下面这个 tag system 计算出来（De Mol 2008,《Tag systems and Collatz-like functions》）：

**定理.** 考虑字母表为 `{a, b, c}`、删除数为 2、产生式规则如下的 tag system：

```
a ↦ bc
b ↦ a
c ↦ aaa
```

若 `n ≥ 1`，那么用由 `n` 个「`a`」组成的输入串去求值上面这个 tag system，就会算出 `n` 的 Collatz 序列，序列的各项对应于那些所有符号都是「`a`」的中间状态。若序列到达 1，求值停机。

**例.** 我们用「`aaaa`」求值这个 tag system，来算出 4 的（非常短的）Collatz 序列。每行是「读一个符号 `⇒` 写产生式 `⇒` 删 2 个符号」；被读的符号和被写的产生式用下划线标出，这里改用方括号标出：

```
[a]aaa  ⇒  aaaa[bc]  ⇒  aabc          (4)
[a]abc  ⇒  aabc[bc]  ⇒  bcbc
[b]cbc  ⇒  bcbc[a]   ⇒  bca
[b]ca   ⇒  bca[a]    ⇒  aa
[a]a    ⇒  aa[bc]    ⇒  bc            (2)
[b]c    ⇒  bc[a]     ⇒  a
a                                     (1)
```

标着 (4)、(2)、(1) 的那几步里，串全由 `a` 组成；它们就是 4 的 Collatz 序列的各项。一旦到达 1，求值就停止，因为「`a`」的长度小于删除数 2。如果改从「`aaa`」开始，要多走很多步才会停机，而其中一个中间步骤是「`aaaaaaaaaaaaaaaa`」。

### Swift type substitution

下面我们要把 Collatz tag system 编码成一串 protocol conformance，再写出一张 substitution map；把它应用到某个特定的 dependent member type 上时，就会对给定的 `n ≥ 1` 求出 Collatz 序列。同一套编码很容易推广到任何 tag system。

我们从一个叫 `Tag` 的 protocol 开始。字母表里每个符号各加一个 associated type，并对每个都声明一条指向 `Tag` 的 recursive conformance requirement：

```swift
protocol Tag {
  associatedtype A: Tag
  associatedtype B: Tag
  associatedtype C: Tag
```

我们还要再加两个 associated type，稍后会说明它们的用途；其中第一个同样声明了一条 recursive conformance requirement：

```swift
  associatedtype Del: Tag
  associatedtype Next
}
```

最后，我们有 nominal type `AA`、`BB`、`CC`、`End` 和 `Halt`，见下面的代码清单，它们都 conform to `Tag`。`Tag` protocol 本身平淡无奇，所有的戏都在这些 concrete conformance 里。下文中我们操作的是 protocol generic signature `G_Tag`，并把它的 generic parameter `τ_0_0` 记作 `τ`。

**代码清单（Collatz tag system 用到的 concrete type）.**

```swift
struct AA<T: Tag>: Tag {
  typealias A = AA<T.A>
  typealias B = AA<T.B>
  typealias C = AA<T.C>
  typealias Del = T
  typealias Next = Del.Del.B.C.Next
}

struct BB<T: Tag>: Tag {
  typealias A = BB<T.A>
  typealias B = BB<T.B>
  typealias C = BB<T.C>
  typealias Del = T
  typealias Next = Del.Del.A.Next
}

struct CC<T: Tag>: Tag {
  typealias A = CC<T.A>
  typealias B = CC<T.B>
  typealias C = CC<T.C>
  typealias Del = T
  typealias Next = Del.Del.A.A.A.Next
}

struct End: Tag {
  typealias A = AA<End>
  typealias B = BB<End>
  typealias C = CC<End>
  typealias Del = Halt
  typealias Next = Halt
}

struct Halt: Tag {
  typealias A = Halt
  typealias B = Halt
  typealias C = Halt
  typealias Del = Halt
  typealias Next = Halt
}
```

**定义.** 我们把字母表 `{a, b, c}` 上的串编码成下面这些 substitution map 的复合：

```
Σ_AA  := {τ ↦ AA<τ>; [τ: Tag] ↦ [AA<τ>: Tag]}
Σ_BB  := {τ ↦ BB<τ>; [τ: Tag] ↦ [BB<τ>: Tag]}
Σ_CC  := {τ ↦ CC<τ>; [τ: Tag] ↦ [CC<τ>: Tag]}
Σ_End := {τ ↦ End;   [τ: Tag] ↦ [End: Tag]}
```

我们把「`a`」映到 `Σ_AA`、「`b`」映到 `Σ_BB`、「`c`」映到 `Σ_CC`，然后在末尾接上 `Σ_End`；最后在每一对相邻的 substitution map 之间插入「`⊗`」。

**例.** 空串「」变成 `Σ_End`，串「`b`」变成 `Σ_BB ⊗ Σ_End`，而「`abac`」变成 `Σ_AA ⊗ Σ_BB ⊗ Σ_AA ⊗ Σ_CC ⊗ Σ_End`。若把每个复合应用到 generic parameter type `τ` 上，就得到一个编码了该串的 concrete type，它由 `End`、`AA<>`、`BB<>` 和 `CC<>` 搭起来：

```
τ ⊗ Σ_End = End
τ ⊗ Σ_BB ⊗ Σ_End = BB<End>
τ ⊗ Σ_AA ⊗ Σ_BB ⊗ Σ_AA ⊗ Σ_CC ⊗ Σ_End = AA<BB<AA<CC<End>>>>
```

下面我们要证一串引理，分别说明：怎么从串的开头删符号、怎么检测停机状态、怎么在串的末尾追加符号，以及最后，怎么把产生式规则编码进去。每条引理都是一个关于 substitution map composition 的恒等式。

先从「从串的开头删符号」开始。我们把 `G_Tag` 的 identity substitution map 记作 `1`，并按如下方式定义 `Σ_Del`：

```
1     := {τ ↦ τ;     [τ: Tag] ↦ [τ: Tag]}
Σ_Del := {τ ↦ τ.Del; [τ: Tag] ↦ [τ.Del: Tag]}
```

**引理.** 若 `Σ` 表示一个非空串，则 `Σ_Del ⊗ Σ` 表示把 `Σ` 的第一个符号删掉之后得到的串。

**证明.** 由于 substitution map composition 满足结合律，只需说明：

```
Σ_Del ⊗ Σ_AA = 1
Σ_Del ⊗ Σ_BB = 1
Σ_Del ⊗ Σ_CC = 1
```

从上面的代码清单可以看到，把 `⟨Tag|Del` 与 `⟨Self.Del: Tag]` 应用到 `[AA<τ>: Tag]` 上得到：

```
⟨Tag|Del ⊗ [AA<τ>: Tag] = τ
⟨Self.Del: Tag] ⊗ [AA<τ>: Tag] = [τ: Tag]
```

利用这两条，把 `Σ_AA` 应用到 `Σ_Del` 的各个组成部分上：

```
τ.Del ⊗ Σ_AA = ⟨Tag|Del ⊗ [AA<τ>: Tag] = τ
[τ.Del: Tag] ⊗ Σ_AA = ⟨Self.Del: Tag] ⊗ [AA<τ>: Tag] = [τ: Tag]
```

注意我们得到的是 `τ` 与 `[τ: Tag]`，它们正是 `G_Tag` 的 identity substitution map 的组成部分，所以 `Σ_Del ⊗ Σ_AA = 1`。另外两条恒等式同理。

**例.** 从「`abac`」删掉第一个符号，得到「`bac`」：

```
Σ_Del ⊗ Σ_AA ⊗ Σ_BB ⊗ Σ_AA ⊗ Σ_CC ⊗ Σ_End
  = 1 ⊗ Σ_BB ⊗ Σ_AA ⊗ Σ_CC ⊗ Σ_End
  = Σ_BB ⊗ Σ_AA ⊗ Σ_CC ⊗ Σ_End
```

试图从空串里删一个符号，会把我们带到停机状态。

**引理.** 令 `Σ_Halt := {τ ↦ Halt; [τ: Tag] ↦ [Halt: Tag]}`。那么：

```
Σ_Del ⊗ Σ_End  = Σ_Halt
Σ_Del ⊗ Σ_Halt = Σ_Halt
```

**证明.** 看代码清单里 `End` 的声明，可以得到：

```
⟨Tag|Del ⊗ [End: Tag] = Halt
⟨Self.Del: Tag] ⊗ [End: Tag] = [Halt: Tag]
```

利用这两条，把 `Σ_Del` 应用到 `Σ_End` 的各个组成部分上：

```
τ.Del ⊗ Σ_End = ⟨Tag|Del ⊗ [End: Tag] = Halt
[τ.Del: Tag] ⊗ Σ_End = ⟨Self.Del: Tag] ⊗ [End: Tag] = [Halt: Tag]
```

这正是 `Σ_Halt` 的组成部分，所以 `Σ_Del ⊗ Σ_End = Σ_Halt`。至于第二条恒等式，注意：

```
⟨Tag|Del ⊗ [Halt: Tag] = Halt
⟨Self.Del: Tag] ⊗ [Halt: Tag] = [Halt: Tag]
```

由此可得 `Σ_Del ⊗ Σ_Halt = Σ_Halt`。

我们还需要在串的末尾追加符号。

**引理.** 给定下面这些 substitution map：

```
Σ_A := {τ ↦ τ.A; [τ: Tag] ↦ [τ.A: Tag]}
Σ_B := {τ ↦ τ.B; [τ: Tag] ↦ [τ.B: Tag]}
Σ_C := {τ ↦ τ.C; [τ: Tag] ↦ [τ.C: Tag]}
```

我们有：

```
Σ_A ⊗ Σ_End = Σ_AA ⊗ Σ_End
Σ_B ⊗ Σ_End = Σ_BB ⊗ Σ_End
Σ_C ⊗ Σ_End = Σ_CC ⊗ Σ_End
```

**证明.** 先考虑 `Σ_A ⊗ Σ_End`；我们是在往空串「」上加符号「`a`」。看代码清单里 `End` 的声明，可以把「`⟨Tag|A` 与 `⟨Self.A: Tag]` 应用到 `[End: Tag]` 上」的结果用 `Σ_End` 表达出来：

```
⟨Tag|A ⊗ [End: Tag] = AA<τ> ⊗ Σ_End
⟨Self.A: Tag] ⊗ [End: Tag] = [AA<τ>: Tag] ⊗ Σ_End
```

现在把 `Σ_End` 应用到 `Σ_A` 的各个组成部分上：

```
τ.A ⊗ Σ_End = ⟨Tag|A ⊗ [End: Tag] = AA<τ> ⊗ Σ_End
[τ.A: Tag] ⊗ Σ_End = ⟨Self.A: Tag] ⊗ [End: Tag] = [AA<τ>: Tag] ⊗ Σ_End
```

可见 `Σ_A ⊗ Σ_End = Σ_AA ⊗ Σ_End`，其余情形同理。

往非空串末尾追加符号则更有意思。把我们的串在**左边**复合上 `Σ_A`、`Σ_B` 或 `Σ_C`，效果是在**右边**插入一个 `Σ_AA`、`Σ_BB` 或 `Σ_CC`。这是因为我们的「单字母」substitution map 与「双字母」的那些是**可交换**的。

**引理.** 设 `Σ_A`、`Σ_B`、`Σ_C` 如上一条引理所定义。我们有：

```
Σ_A ⊗ Σ_AA = Σ_AA ⊗ Σ_A      Σ_B ⊗ Σ_AA = Σ_AA ⊗ Σ_B      Σ_C ⊗ Σ_AA = Σ_AA ⊗ Σ_C
Σ_A ⊗ Σ_BB = Σ_BB ⊗ Σ_A      Σ_B ⊗ Σ_BB = Σ_BB ⊗ Σ_B      Σ_C ⊗ Σ_BB = Σ_BB ⊗ Σ_C
Σ_A ⊗ Σ_CC = Σ_CC ⊗ Σ_A      Σ_B ⊗ Σ_CC = Σ_CC ⊗ Σ_B      Σ_C ⊗ Σ_CC = Σ_CC ⊗ Σ_C
```

**证明.** 看代码清单里 `AA` 的声明，我们可以把 `⟨Tag|B` 的 type witness 和 `⟨Self.B: Tag]` 的 associated conformance 用 `Σ_B` 表达出来：

```
⟨Tag|B ⊗ [AA<τ>: Tag] = AA<τ.B> = AA<τ> ⊗ Σ_B
⟨Self.B: Tag] ⊗ [AA<τ>: Tag] = [AA<τ.B>: Tag] = [AA<τ>: Tag] ⊗ Σ_B
```

现在，把 `Σ_AA` 应用到 `Σ_B` 的各个组成部分上，就能证明 `Σ_B ⊗ Σ_AA = Σ_AA ⊗ Σ_B`：

```
τ.B ⊗ Σ_AA = ⟨Tag|B ⊗ [AA<τ>: Tag] = AA<τ> ⊗ Σ_B
[τ.B: Tag] ⊗ Σ_AA = ⟨Self.B: Tag] ⊗ [AA<τ>: Tag] = [AA<τ>: Tag] ⊗ Σ_B
```

其余恒等式同理。

**例.** 要在「`ab`」末尾追加「`c`」，我们在**左边**复合上 `Σ_C`；注意它是怎样一路与每个邻居换位，直到碰上 `Σ_End`，随即化身为 `Σ_CC` 的：

```
Σ_C ⊗ Σ_AA ⊗ Σ_BB ⊗ Σ_End
  = Σ_AA ⊗ Σ_C ⊗ Σ_BB ⊗ Σ_End
  = Σ_AA ⊗ Σ_BB ⊗ Σ_C ⊗ Σ_End
  = Σ_AA ⊗ Σ_BB ⊗ Σ_CC ⊗ Σ_End
```

不过，一旦到了停机状态，我们就再也追加不了任何符号。

**引理.** 设 `Σ_Halt` 如前所定义。我们有：

```
Σ_A ⊗ Σ_Halt = Σ_Halt
Σ_B ⊗ Σ_Halt = Σ_Halt
Σ_C ⊗ Σ_Halt = Σ_Halt
```

**证明.** 在代码清单里，`Halt` 的声明中 `A`、`B`、`C` 的 type witness 全都还是 `Halt`，而各个 associated conformance 都是 `[Halt: Tag]`，结论随之成立。

最后，我们把删除数和产生式规则编码进每个对 `Tag` 的 conformance 里 `Next` 这个 associated type 的 type witness：

```
⟨Tag|Next ⊗ [AA<τ>: Tag] = τ.Del.B.C.Next
⟨Tag|Next ⊗ [BB<τ>: Tag] = τ.Del.A.Next
⟨Tag|Next ⊗ [CC<τ>: Tag] = τ.Del.A.A.A.Next
```

注意，若串为空，我们立刻进入停机状态；而若已经在停机状态里，就一直留在那儿：

```
⟨Tag|Next ⊗ [End: Tag] = Halt
⟨Tag|Next ⊗ [Halt: Tag] = Halt
```

下面这个结果把一切串了起来。

**引理.** 我们可以把上面这些用 substitution map composition 表达出来：

```
τ.Next ⊗ Σ_AA = τ.Next ⊗ Σ_C ⊗ Σ_B ⊗ Σ_Del
τ.Next ⊗ Σ_BB = τ.Next ⊗ Σ_A ⊗ Σ_Del
τ.Next ⊗ Σ_CC = τ.Next ⊗ Σ_A ⊗ Σ_A ⊗ Σ_A ⊗ Σ_Del

τ.Next ⊗ Σ_End  = Halt
τ.Next ⊗ Σ_Halt = Halt
```

**证明.** 考虑第一条恒等式。左边我们有：

```
τ.Next ⊗ Σ_AA = ⟨Tag|Next ⊗ [τ: Tag] ⊗ Σ_AA = ⟨Tag|Next ⊗ [AA<τ>: Tag]
```

要得到右边，注意到：

```
⟨Self.A: Tag]   ⊗ [τ: Tag] = [τ: Tag] ⊗ Σ_A
⟨Self.B: Tag]   ⊗ [τ: Tag] = [τ: Tag] ⊗ Σ_B
⟨Self.C: Tag]   ⊗ [τ: Tag] = [τ: Tag] ⊗ Σ_C
⟨Self.Del: Tag] ⊗ [τ: Tag] = [τ: Tag] ⊗ Σ_Del
```

因此，若用一条 conformance path 把 `τ.Del.B.C.Next` 展开，就会看到：

```
τ.Del.B.C.Next
  = ⟨Tag|Next ⊗ ⟨Self.C: Tag] ⊗ ⟨Self.B: Tag] ⊗ ⟨Self.Del: Tag] ⊗ [τ: Tag]
  = ⟨Tag|Next ⊗ ⟨Self.C: Tag] ⊗ ⟨Self.B: Tag] ⊗ [τ: Tag] ⊗ Σ_Del
  = ⟨Tag|Next ⊗ ⟨Self.C: Tag] ⊗ [τ: Tag] ⊗ Σ_B ⊗ Σ_Del
  = ⟨Tag|Next ⊗ [τ: Tag] ⊗ Σ_C ⊗ Σ_B ⊗ Σ_Del
  = τ.Next ⊗ Σ_C ⊗ Σ_B ⊗ Σ_Del
```

类似的计算确立其余各条。

**例.** 下面这段程序在编译期算出 3 的 Collatz 序列。（`fatalError()` 调用在运行期会 trap，但这里无关紧要。）

```swift
func collatz<T: Tag>(_: T) -> T.Next {
  fatalError()
}

let x = collatz(AA<AA<AA<End>>>())  // what is the type of `x'?
```

要得到这个 call expression 的代入后返回类型，我们把 substitution map `Σ_AA ⊗ Σ_AA ⊗ Σ_AA ⊗ Σ_End` 应用到原始返回类型 `τ.Next` 上。代入结果恰好会是 `Halt`，因为 3 的 Collatz 序列会到达 1。

为了走一个完整的例子，我们改看 substitution map 为 `Σ_AA ⊗ Σ_AA ⊗ Σ_End` 时会发生什么，它求的就是 2 的 Collatz 序列。我们要用到前面那几条引理。每一对括号标出的是下一个归约步骤，右边标注用的是哪条引理：

```
(τ.Next ⊗ Σ_AA) ⊗ Σ_AA ⊗ Σ_End                          (τ.Next 恒等式引理)
  = τ.Next ⊗ Σ_C ⊗ Σ_B ⊗ (Σ_Del ⊗ Σ_AA) ⊗ Σ_End         (删除引理)
  = τ.Next ⊗ Σ_C ⊗ (Σ_B ⊗ Σ_End)                        (末尾追加引理)
  = τ.Next ⊗ (Σ_C ⊗ Σ_BB) ⊗ Σ_End                       (交换引理)
  = τ.Next ⊗ Σ_BB ⊗ (Σ_C ⊗ Σ_End)                       (末尾追加引理)
  = (τ.Next ⊗ Σ_BB) ⊗ Σ_CC ⊗ Σ_End                      (τ.Next 恒等式引理)
  = τ.Next ⊗ Σ_A ⊗ (Σ_Del ⊗ Σ_CC) ⊗ Σ_End               (删除引理)
  = τ.Next ⊗ (Σ_A ⊗ Σ_End)                              (末尾追加引理)
  = (τ.Next ⊗ Σ_AA) ⊗ Σ_End                             (τ.Next 恒等式引理)
  = τ.Next ⊗ Σ_C ⊗ Σ_B ⊗ (Σ_Del ⊗ Σ_End)                (停机引理)
  = τ.Next ⊗ Σ_C ⊗ (Σ_B ⊗ Σ_Halt)                       (停机后不可追加引理)
  = τ.Next ⊗ (Σ_C ⊗ Σ_Halt)                             (停机后不可追加引理)
  = (τ.Next ⊗ Σ_Halt)                                   (τ.Next 恒等式引理)
  = Halt
```

2 的 Collatz 序列不过是 2 接着 1，所以显然，我们这套编码效率相当低；光是算 `2 ÷ 2 = 1` 就要费这么大劲！在作者的机器上，用 `n = 19` 求值 Collatz tag system 大约要十分之一秒，而试 `n = 27` 会因为中间串太长而 trap 于 stack overflow。撇开实用性不谈，我们这个方案显然能编码任何 tag system。我们可以按需添加新符号、更改删除数与产生式规则，并用任意输入串把它启动起来。毫无疑问：

**定理.** Swift 的 type substitution 是 Turing-complete 的。

### Further discussion

在 `extensions.tex` 的 Conditional Conformances 一节里，我们看过 Swift 中一个不终止的 conditional conformance 检查的例子，并援引了 Rust 里一个类似的例子。事实上，本节的构造稍加改动就能改用 conditional conformance 来编码 tag system，所以 Swift 的 conditional conformance 检查同样是 Turing-complete 的，而不只是能编码出死循环而已。往后看，`monoids.tex` 的 The Word Problem 一节会说明 Swift 的 reduced type equality 在一般情形下同样是不可判定的，不过我们会通过限制问题来换取一个终止性保证。

Swift 论坛上的一位贡献者在 Swift 类型系统里发现了另一台 Turing machine（Keith Bauer 2023,《BrainF\*\*\* in the Swift type system》），办法是用 **key path member lookup** 特性（SE-0252）构造了一个「Brainfuck」编程语言的解释器。文献里还描述了数不清的其他不可判定类型检查问题。例如，Java 的泛型已知是 Turing-complete 的（Tate、Leung、Lerner 2011,《Taming wildcards in Java's type system》；Grigore 2017,《Java Generics Are Turing Complete》）。

最后，Robbie Ostrow 2019 的《Taking Types Too Far》描述了在 TypeScript 语言里对 Collatz 序列的一种编码。关于 Collatz 猜想的进一步讨论，见 Lagarias 2010《The Ultimate Challenge: The 3x+1 Problem》与 Stephen Wolfram 的《After 100 Years, Can We Finally Crack Post's Problem of "Tag?" A Story of Computational Irreducibility, and More》。

## Source Code Reference

关键源文件：

- `include/swift/AST/GenericSignature.h`
- `include/swift/AST/SubstitutionMap.h`
- `lib/AST/GenericSignature.cpp`
- `lib/AST/SubstitutionMap.cpp`
- `lib/AST/TypeSubstitution.cpp`

**`ConformancePath::Entry`（type alias）**：一个 conformance path 元素，表示成一个 `std::pair<CanType, ProtocolDecl *>`。这个 pair 要么编码一个 root abstract conformance，要么编码一条 associated conformance requirement。

**`ConformancePath`（class）**：`ArrayRef<ConformancePath::Entry>` 的一层包装，表示一条 conformance path。

**`SubstitutionMap`（class）**：`lookupConformance()` 方法实现了 Local conformance lookup 算法，用来做 local conformance lookup。该类的其他方法见 `substitution-maps.tex` 的 Source Code Reference 一节。

### Finding Conformance Paths

关键源文件：

- `lib/AST/RequirementMachine/GenericSignatureQueries.cpp`

**`GenericSignatureImpl`（class）**：`getConformancePath()` 方法返回给定 type parameter 与 protocol declaration 的 reduced conformance path。该类的其他方法见 `generic-signatures.tex` 的 Source Code Reference 一节。

**`rewriting::RequirementMachine`（class）**：`GenericSignature` 上的 `getConformancePath()` 方法会去调用 `RequirementMachine` 类上同名的方法，后者实现了 Find conformance path 算法。`RequirementMachine` 类有一对实例变量用来保存该算法的持久状态：

- `ConformancePaths` 是已知 conformance path 的那张表。
- `CurrentConformancePaths` 是当前枚举长度上的 conformance path 缓冲区，也就是我们记作 `B` 的那个数组。

Find conformance path 算法里流转的是 reduced type parameter，而实际实现处理的是 `Term` 的实例。Term 是 type parameter 在 Requirement Machine 内部的表示形式，我们会在 `symbols-terms-and-rules.tex` 里学到它。这样做避免了在计算 reduced type 时在 `Term` 与 `Type` 之间来回转换，但并没有从根本上改变算法。

---

> 译自 `docs/Generics/chapters/conformance-paths.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
