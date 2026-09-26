# Symbols, Terms, and Rules（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/symbols-terms-and-rules.tex`（《Compiling Swift Generics》一书的「Symbols, Terms, and Rules」一章，属第四部分 The Requirement Machine），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是 Requirement Machine 的「字母表」一章——把 generic signature 的每条 requirement 编码成一条 rewrite rule，把每个 type parameter 编码成一串 symbol（term），并证明「在 $G$ 里推导出一条 requirement」与「在重写系统里存在一条 rewrite path」是同一件事。本库（MachOSwiftSection）**不实现**这套重写系统，它整个活在编译器里；但本库天天在读它的产物：二进制里的 generic signature、requirement、mangled type name，全是这台机器跑完 completion 与 minimization 之后吐出来的 reduced 形态，而 `T.[Sequence]Element` 这种把 associated type 绑死到声明它的 protocol 上的写法，正是本章 Rules 一节讲的 associated type symbol 序列化后的样子。
>
> **术语**：书中定义的术语一律保留英文（symbol、term、rewrite rule、monoid presentation、alphabet、generic parameter symbol、name symbol、protocol symbol、associated type symbol、layout symbol、superclass symbol、concrete type symbol、concrete conformance symbol、standard term、admissible term、conformance chart、pattern type、substitution term、property rule、reduction order、weighted shortlex order、trie、normal form algorithm、rewrite path、whiskering、completion、minimization），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 Equivalence of Terms 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（本章属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`）：
>
> | 记法 | 含义 |
> |---|---|
> | $\langle A \vert R\rangle$ | monoid presentation：生成元集合 $A$（这里叫 alphabet）与关系集合 $R$（这里叫 rewrite rule） |
> | $\tau_{d,i}$ | generic parameter symbol（depth $d$、index $i$）。原书用直立的 `\uptau`，KaTeX 不认，本文一律写 $\tau$ |
> | $\texttt{A}$ | name symbol，即一个裸 identifier |
> | $[\texttt{P}]$ | protocol symbol |
> | $[\texttt{P}\vert\texttt{A}]$ | associated type symbol（protocol P 与名字 A 的「融合」） |
> | $[\mathsf{layout}\colon\texttt{AnyObject}]$ | layout symbol |
> | $[\mathsf{superclass}\colon \texttt{C};\,t_0,\ldots,t_n]$ | superclass symbol：pattern type 加一列 substitution term |
> | $[\mathsf{concrete}\colon \texttt{X};\,\ldots]$ | concrete type symbol |
> | $[\mathsf{concrete}\colon \texttt{X}\colon\texttt{P};\,\ldots]$ | concrete conformance symbol |
> | $\cdot$ | requirement machine 的 monoid 运算，把 symbol 串起来成 term |
> | $\varepsilon$ | 空 term |
> | $A^*$ | $A$ 上的 free monoid，即全体 term |
> | $\mathsf{term}$ / $\mathsf{rule}$ | 把 type parameter / explicit requirement 翻成 term / rewrite rule 的映射 |
> | $\mathsf{term}_\texttt{P}$ / $\mathsf{rule}_\texttt{P}$ | 同上，但针对 protocol P 的 associated requirement |
> | $\mathsf{type}$ / $\mathsf{chart}$ | 反方向：把 admissible term 翻回 type parameter / conformance chart |
> | $\mathsf{path}$ | 把一条 derivation 翻成一条 rewrite path |
> | $u \sim v$ | 两个 term 在 $R$ 生成的等价关系 $\sim_R$ 下等价 |
> | $u \Rightarrow v$ | 一步 rewrite |
> | $x \triangleleft s$ / $s \triangleright y$ | 左 / 右 whisker，把一段 term 接在 rewrite step 两侧 |
> | $p \circ q$、$p^{-1}$、$1_t$ | rewrite path 的复合、逆、以及 $t$ 上的空 path |
> | $\operatorname{src}(p)$ / $\operatorname{dst}(p)$ | 一条 rewrite path（或 rewrite step）的起点 / 终点 |
> | $G\vdash D$ | $D$ 属于 generic signature $G$ 的 theory，也就是 $D$ 可从 $G$ 推导出来 |
> | $G\prec\texttt{P}$ | $G$ 依赖 protocol P |
> | $\diamond\,n$ | 原书给「规则 $n$ 被 completion 化简之后的新形态」起的标号 |
> | $[\texttt{T: P}]$ / $[\texttt{T == U}]$ | conformance requirement / same-type requirement |
> | $[\ldots]_\texttt{P}$ | P 的 associated requirement |
> | $\bot$ | 两者不可比——partial order 下它们之间没有关系 |
> | $\texttt{KEY}(n)$ / $\texttt{CHILD}(n,s)$ / $\texttt{VALUE}(n)$ | trie 节点 $n$ 的 key、沿 symbol $s$ 的子节点、存的值 |

---

把 monoid presentation 翻译成 generic signature，我们的动机是说明「能接受什么」存在理论上的上限。反过来，把 generic signature 翻译成 monoid presentation，则是一件极其实用的事。`basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)） 的结尾我们说过，一台 requirement machine 由一组 rewrite rule 构成；现在把这句话讲精确。就像 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）的 Derived Requirements 一节处理 derived requirements 形式系统那样，我们分步揭开完整的编码方式。先从 Swift 泛型模型的核心开始：unbound type parameter、conformance requirement，以及 type parameter 之间的 same-type requirement。我们会证明一个正确性结果，然后把编码扩展到 bound type parameter 和其余几类 requirement。

### Core model.

设 $G$ 是一个 generic signature。回忆 `basic-operation.tex` 的 Protocol Components 一节：若 $\texttt{P}$ 是某个 protocol，则 $G\prec\texttt{P}$ 表示 $G$ 依赖 $\texttt{P}$。现在我们引入一个特定的 monoid presentation $\langle A \vert R\rangle$，称为 $G$ 的 **requirement machine**。

我们把那些「有嚼劲」的递归输入——type parameter、conformance requirement、same-type requirement——拿来炖，一直炖到「结缔组织」散开为止。炖出来的是一个有限的 alphabet $A$，其中每个 symbol 属于下面三类之一：

| symbol | 类别 | 条件 |
|---|---|---|
| $\tau_{d,i}$ | generic parameter symbol | 对某组 $d$、$i\in\mathbb{N}$ |
| $\texttt{A}$ | name symbol | 对某个 identifier $\texttt{A}$ |
| $[\texttt{P}]$ | protocol symbol | 对某个满足 $G\prec\texttt{P}$ 的 $\texttt{P}$ |

要得到 $R$，我们定义一个「$\mathsf{term}$」函数，把 $G$ 的 type parameter 翻译成 term；再定义一个「$\mathsf{rule}$」函数，把 $G$ 的每条 explicit requirement 翻译成一条 rewrite rule：

$$\begin{array}{lcl}
\mathsf{term}(\tau_{d,i}) & := & \tau_{d,i}\\
\mathsf{term}(\texttt{U.A}) & := & \mathsf{term}(\texttt{U})\cdot\texttt{A}
\end{array}
\qquad\qquad
\begin{array}{lcl}
\mathsf{rule}\ [\texttt{T: P}] & := & \mathsf{term}(\texttt{T})\cdot[\texttt{P}]\sim\mathsf{term}(\texttt{T})\\
\mathsf{rule}\ [\texttt{T == U}] & := & \mathsf{term}(\texttt{T})\sim\mathsf{term}(\texttt{U})
\end{array}$$

此外，对每个满足 $G\prec\texttt{P}$ 的 protocol $\texttt{P}$，我们定义一个「$\mathsf{term}_\texttt{P}$」函数，把 $G_\texttt{P}$ 的 type parameter 翻译成一个以 $[\texttt{P}]$ 打头的 term；再定义一个「$\mathsf{rule}_\texttt{P}$」函数，以与「$\mathsf{rule}$」完全类似的方式，把 $\texttt{P}$ 的每条 associated requirement 翻译成一条 rewrite rule：

$$\begin{array}{lcl}
\mathsf{term}_\texttt{P}(\texttt{Self}) & := & [\texttt{P}]\\
\mathsf{term}_\texttt{P}(\texttt{V.A}) & := & \mathsf{term}_\texttt{P}(\texttt{V})\cdot\texttt{A}
\end{array}
\qquad\qquad
\begin{array}{lcl}
\mathsf{rule}_\texttt{P}\ [\texttt{U: Q}]_\texttt{P} & := & \mathsf{term}_\texttt{P}(\texttt{U})\cdot[\texttt{Q}]\sim\mathsf{term}_\texttt{P}(\texttt{U})\\
\mathsf{rule}_\texttt{P}\ [\texttt{U == V}]_\texttt{P} & := & \mathsf{term}_\texttt{P}(\texttt{U})\sim\mathsf{term}_\texttt{P}(\texttt{V})
\end{array}$$

这就把一个非常了不起的对象完整地描述出来了：在这个对象里，$G$ 的 **derived requirement** 就是 $G$ 的 requirement machine 里的 **rewrite path**。

**例.** 设 $G$ 是下面这个 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.Element: Equatable,
                    τ_0_0.Element == τ_0_1.Element>
```

这个签名我们在 `generic-signatures.tex` 里见过（那一章用它引出 derived requirements，随后在 Derived Requirements 与 Valid Type Parameters 两节里研究过它）。现在我们来构造它的 requirement machine。

这个 generic signature 依赖 `Sequence`、`IteratorProtocol` 和 `Equatable`。前两者都声明了一个名为 `Element` 的 associated type，而 `Sequence` 还声明了一个名为 `Iterator` 的 associated type。于是我们的 alphabet 有七个 symbol：

$$\{ \underbrace{\tau_{0,0},\, \tau_{0,1}}_{\text{generic param}},\ \underbrace{\texttt{Element},\, \texttt{Iterator}}_{\text{name}},\ \underbrace{[\texttt{Sequence}],\, [\texttt{IteratorProtocol}],\,[\texttt{Equatable}]}_{\text{protocol}}\}$$

下面是 $G$ 与 `Sequence` 的 requirement，它们将定义我们的 rewrite rule：

$$\begin{gathered}
[\tau_{0,0}\texttt{: Sequence}]\\
[\tau_{0,1}\texttt{: Sequence}]\\
[\tau_{0,0}\texttt{.Element: Equatable}]\\
[\tau_{0,0}\texttt{.Element} == \tau_{0,1}\texttt{.Element}]\\[1ex]
[\texttt{Self.Iterator: IteratorProtocol}]_\texttt{Sequence}\\
[\texttt{Self.Element} == \texttt{Self.Iterator.Element}]_\texttt{Sequence}
\end{gathered}$$

我们对每条 requirement 施加「$\mathsf{rule}$」或「$\mathsf{rule}_\texttt{P}$」，得到 rewrite rule 的集合 $R$：

- **(1)** $\tau_{0,0} \cdot [\texttt{Sequence}] \sim \tau_{0,0}$
- **(2)** $\tau_{0,1} \cdot [\texttt{Sequence}] \sim \tau_{0,1}$
- **(3)** $\tau_{0,0}\cdot\texttt{Element} \cdot [\texttt{Equatable}] \sim \tau_{0,0}\cdot\texttt{Element}$
- **(4)** $\tau_{0,0}\cdot\texttt{Element} \sim \tau_{0,1}\cdot\texttt{Element}$
- **(5)** $[\texttt{Sequence}]\cdot\texttt{Iterator} \cdot [\texttt{IteratorProtocol}] \sim [\texttt{Sequence}]\cdot\texttt{Iterator}$
- **(6)** $[\texttt{Sequence}]\cdot\texttt{Element} \sim [\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element}$

注意「$\mathsf{term}$」不过是把 type parameter 的链表结构拍平成数组；拍出来的 term 是一个 generic parameter symbol 后面跟零个或多个 name symbol。为了把两种表示区分开，我们像以前一样用「`.`」分隔 type parameter 的各段，而 term 则用 requirement machine 的 monoid 运算「$\cdot$」把自己的 symbol 连起来。之所以需要「$\mathsf{term}_\texttt{P}$」和「$\mathsf{rule}_\texttt{P}$」这两个 protocol 版本，是为了把每条 associated requirement 的原始 protocol 编码进去。这也正是「$\mathsf{term}_\texttt{P}$」把 `Self` 换成 protocol symbol $[\texttt{P}]$、而不是换成 generic parameter symbol $\tau_{0,0}$ 的原因。

还有一点要说。name symbol 和 protocol symbol 活在不同的命名空间里，所以即便我们把 `IteratorProtocol` 改名叫 `Iterator`，name symbol $\texttt{Iterator}$ 仍然与 protocol symbol $[\texttt{Iterator}]$ 彼此不同。另一方面，不同 protocol 里同名的两个 associated type，永远定义**同一个** name symbol。

现在继续这个例子，想一想这些 rewrite rule 生成的等价关系。注意 protocol symbol 出现的方式带有某种对称性：conformance requirement (1)、(2)、(3)、(5) 重写的是**以** protocol symbol **结尾**的 term；associated requirement (5) 和 (6) 重写的则是**以** protocol symbol **开头**的 term。（associated conformance requirement (5) 两者兼备：它的左端既以 protocol symbol 开头，又以 protocol symbol 结尾。）

由 `generic-signatures.tex` 的那个 derived equivalence 例子我们知道 $G\vdash[\tau_{0,0}\texttt{.Iterator.Element} == \tau_{0,1}\texttt{.Iterator.Element}]$，尽管这条 requirement 并没有被显式写出来。把「$\mathsf{rule}$」作用在这条 requirement 上，输出这一对有序的 term：

$$(\tau_{0,0}\cdot\texttt{Iterator}\cdot\texttt{Element},\ \tau_{0,1}\cdot\texttt{Iterator}\cdot\texttt{Element})$$

再说一次，这不是一条 explicit requirement，所以它不是 $R$ 里的规则。但从第一个 term 到第二个 term 存在一条 rewrite path；它们在 $\sim_R$ 下等价：

$$\begin{gathered}
(\tau_{0,0}\Rightarrow\tau_{0,0}\cdot[\texttt{Sequence}])\triangleright\texttt{Iterator}\cdot\texttt{Element}\\
{}\circ\ \tau_{0,0}\triangleleft([\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element}\Rightarrow[\texttt{Sequence}]\cdot\texttt{Element})\\
{}\circ\ (\tau_{0,0}\cdot[\texttt{Sequence}]\Rightarrow\tau_{0,0})\triangleright\texttt{Element}\\
{}\circ\ (\tau_{0,0}\cdot\texttt{Element}\Rightarrow\tau_{0,1}\cdot\texttt{Element})\\
{}\circ\ (\tau_{0,1}\Rightarrow\tau_{0,1}\cdot[\texttt{Sequence}])\triangleright\texttt{Element}\\
{}\circ\ \tau_{0,1}\triangleleft([\texttt{Sequence}]\cdot\texttt{Element}\Rightarrow[\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element})\\
{}\circ\ (\tau_{0,1}\cdot[\texttt{Sequence}]\Rightarrow\tau_{0,1})\triangleright\texttt{Iterator}\cdot\texttt{Element}
\end{gathered}$$

换个方式也能看明白：把相邻两步 rewrite 之间的中间 term 一个个写出来。我们用 conformance requirement 在调用 associated same-type requirement 的前后插入和删除 protocol symbol：

$$\begin{gathered}
\tau_{0,0}\cdot\texttt{Iterator}\cdot\texttt{Element}\\
{}\sim\ \tau_{0,0}\cdot[\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element}\\
{}\sim\ \tau_{0,0}\cdot[\texttt{Sequence}]\cdot\texttt{Element}\\
{}\sim\ \tau_{0,0}\cdot\texttt{Element}\\
{}\sim\ \tau_{0,1}\cdot\texttt{Element}\\
{}\sim\ \tau_{0,1}\cdot[\texttt{Sequence}]\cdot\texttt{Element}\\
{}\sim\ \tau_{0,1}\cdot[\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element}\\
{}\sim\ \tau_{0,1}\cdot\texttt{Iterator}\cdot\texttt{Element}
\end{gathered}$$

现在换 $G\vdash[\tau_{0,0}\texttt{.Iterator: IteratorProtocol}]$ 试试。施加「$\mathsf{rule}$」得到一对有序的 term：

$$(\tau_{0,0}\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}],\ \tau_{0,0}\cdot\texttt{Iterator})$$

要证明这个等价，我们先用 conformance requirement (1)，再用 associated conformance requirement (5)：

$$\begin{gathered}
(\tau_{0,0}\Rightarrow\tau_{0,0}\cdot[\texttt{Sequence}])\triangleright\texttt{Iterator}\cdot[\texttt{IteratorProtocol}]\\
{}\circ\ \tau_{0,0}\triangleleft([\texttt{Sequence}]\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}]\Rightarrow[\texttt{Sequence}]\cdot\texttt{Iterator})\\
{}\circ\ (\tau_{0,0}\cdot[\texttt{Sequence}]\Rightarrow\tau_{0,0})\triangleright\texttt{Iterator}
\end{gathered}$$

同样，我们也可以把这条 path 上的中间 term 摊开：

$$\begin{gathered}
\tau_{0,0}\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}]\\
{}\sim\ \tau_{0,0}\cdot[\texttt{Sequence}]\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}]\\
{}\sim\ \tau_{0,0}\cdot[\texttt{Sequence}]\cdot\texttt{Iterator}\\
{}\sim\ \tau_{0,0}\cdot\texttt{Iterator}
\end{gathered}$$

## Correctness

我们看了几个把 derived requirement 编码成 word problem 的例子。现在把这件事讲精确。我们要证明两条定理，以确认 derivation 能翻译成 rewrite path，反之亦然。用到的工具是 `monoids.tex` 的 Equivalence of Terms 一节里那套重写的代数。

先来一个预备结果。在 `generic-signatures.tex` 的 Derived Requirements 一节里，我们是用形式代入来定义 **AssocConf** 和 **AssocSame** 这两条 inference rule 的：若 $\texttt{T}$ 是 $G$ 的某个已知遵循 protocol $\texttt{P}$ 的 type parameter，而 $\texttt{Self.U}$ 是 $G_\texttt{P}$ 的某个 type parameter，则 `T.U` 表示把 $\texttt{Self.U}$ 里的 `Self` 替换成 $\texttt{T}$ 的结果。我们可以把这件事和 requirement machine 的 monoid 运算联系起来。

**引理.** 设 $G$ 是一个 generic signature，$\langle A \vert R\rangle$ 是 $G$ 的 requirement machine。进一步假设：

1. $\texttt{T}$ 是 $G$ 的某个 type parameter，
2. $\texttt{P}$ 是某个 protocol，且 $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]\sim\mathsf{term}(\texttt{T})$，
3. $\texttt{Self.U}$ 是 $G_\texttt{P}$ 的某个 type parameter。

那么 $\mathsf{term}(\texttt{T})\cdot\mathsf{term}_\texttt{P}(\texttt{Self.U}) \sim \mathsf{term}(\texttt{T.U})$。

**证明.** 由「$\mathsf{term}_\texttt{P}$」的定义可知，对某个 $u\in A^*$ 有 $\mathsf{term}_\texttt{P}(\texttt{Self.U})=[\texttt{P}]\cdot u$。再令 $t := \mathsf{term}(\texttt{T})$，于是 $\mathsf{term}(\texttt{T.U})=t\cdot u$。现在，若 $p$ 是一条从 $t\cdot[\texttt{P}]$ 到 $t$ 的 rewrite path，则 $p\triangleright u$ 就是一条从 $t\cdot[\texttt{P}]\cdot u$ 到 $t\cdot u$ 的 rewrite path。

**例.** 在本章开头那个例子里，第二条 rewrite path 现在可以换个眼光来看：

$$\begin{gathered}
\mathsf{term}(\tau_{0,0}\texttt{.Iterator})\cdot[\texttt{IteratorProtocol}]\\
{}\sim\ \mathsf{term}(\tau_{0,0}) \cdot \mathsf{term}_\texttt{Sequence}(\texttt{Self.Iterator}) \cdot [\texttt{IteratorProtocol}]\\
{}\sim\ \mathsf{term}(\tau_{0,0}) \cdot \mathsf{term}_\texttt{Sequence}(\texttt{Self.Iterator})\\
{}\sim\ \mathsf{term}(\tau_{0,0}\texttt{.Iterator})
\end{gathered}$$

这种把一个 term「劈成两半」的想法，会是下面那个证明归纳步骤的关键——在处理 **AssocConf** 和 **AssocSame** 这两条 inference rule 的时候。

**定理.** 设 $G$ 是一个 generic signature，$\langle A \vert R\rangle$ 是 $G$ 的 requirement machine。

1. 若对某个 type parameter $\texttt{T}$ 和 protocol $\texttt{P}$ 有 $G\vdash[\texttt{T: P}]$，则 $\mathsf{term}(\texttt{T})\cdot[\texttt{P}] \sim \mathsf{term}(\texttt{T})$。
2. 若对某对 type parameter $\texttt{T}$、$\texttt{U}$ 有 $G\vdash[\texttt{T == U}]$，则 $\mathsf{term}(\texttt{T}) \sim \mathsf{term}(\texttt{U})$。

**证明.** 我们对 derived requirement 作结构归纳（见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）的 Well-Formed Requirements 一节），定义一个「$\mathsf{path}$」映射，给每条 derived requirement $G\vdash D$ 指派一条 rewrite path $p$，使得 $\mathsf{rule}(D)=(\operatorname{src}(p),\,\operatorname{dst}(p))$。结论随即成立。

**基础情形.** 对那些 elementary statement，以及假设里不含任何 requirement 的 inference rule，我们直接构造一条 rewrite path。

一个 **Conf** 步引用 $G$ 的一条 explicit conformance requirement：

$$[\texttt{T: P}]\qquad(\textsf{Conf})$$

注意 $\mathsf{rule}\,[\texttt{T: P}]=(\mathsf{term}(\texttt{T})\cdot[\texttt{P}],\,\mathsf{term}(\texttt{T}))\in R$。这条 path 就是单独一步 rewrite：

$$\mathsf{path}\,[\texttt{T: P}] := (\mathsf{term}(\texttt{T})\cdot[\texttt{P}] \Rightarrow \mathsf{term}(\texttt{T}))$$

一个 **Same** 步引用 $G$ 的一条 explicit same-type requirement：

$$[\texttt{T == U}]\qquad(\textsf{Same})$$

注意 $\mathsf{rule}\,[\texttt{T == U}]=(\mathsf{term}(\texttt{T}),\,\mathsf{term}(\texttt{U}))\in R$。这条 path 同样是单独一步 rewrite：

$$\mathsf{path}\,[\texttt{T == U}] := (\mathsf{term}(\texttt{T}) \Rightarrow \mathsf{term}(\texttt{U}))$$

一个 **Reflex** 步从一个 valid type parameter 推出一条平凡的 same-type requirement：

$$[\texttt{T == T}]\qquad(\textsf{Reflex}\ \ \texttt{T})$$

这里我们根本用不上 $G\vdash\texttt{T}$ 这个事实，因为在一个 finitely-presented monoid 里，任何 term 通过空 rewrite path 就已经与自身等价了。于是令 $t := \mathsf{term}(\texttt{T})$，并置：

$$\mathsf{path}\,[\texttt{T == T}] := 1_t$$

**归纳步骤.** 每种情形下，结论的「$\mathsf{path}$」都由该步各个假设的「$\mathsf{path}$」定义出来。对一个 **AssocConf** 步，归纳假设给了我们 $p_1 := \mathsf{path}\,[\texttt{T: P}]$，于是 $\operatorname{src}(p_1)=\mathsf{term}(\texttt{T})\cdot[\texttt{P}]$ 且 $\operatorname{dst}(p_1)=\mathsf{term}(\texttt{T})$：

$$[\texttt{T.U: Q}]\qquad(\textsf{AssocConf}\ \ [\texttt{Self.U: Q}]_\texttt{P}\ \ [\texttt{T: P}])$$

注意 $\mathsf{rule}_\texttt{P}\,[\texttt{Self.U: Q}]_\texttt{P}\in R$ 形如 $([\texttt{P}]\cdot u\cdot[\texttt{Q}],\,[\texttt{P}]\cdot u)$（对某个 $u\in A^*$）。借助上面那条引理，我们在恰当的位置插入一个 $[\texttt{P}]$，施加 associated requirement，再把 $[\texttt{P}]$ 删掉。令 $t := \mathsf{term}(\texttt{T})$，$s := ([\texttt{P}] \cdot u \cdot [\texttt{Q}] \Rightarrow [\texttt{P}] \cdot u)$，并置：

$$\mathsf{path}\,[\texttt{T.U: Q}] := (p_1^{-1} \triangleright u \triangleright [\texttt{Q}]) \circ (t \triangleleft s) \circ (p_1 \triangleright u)$$

对一个 **AssocSame** 步，归纳假设给了我们 $p_1 := \mathsf{path}\,[\texttt{T: P}]$：

$$[\texttt{T.U == T.V}]\qquad(\textsf{AssocSame}\ \ [\texttt{Self.U == Self.V}]_\texttt{P}\ \ [\texttt{T: P}])$$

注意 $\mathsf{rule}_\texttt{P}\,[\texttt{Self.U == Self.V}]_\texttt{P}\in R$ 形如 $([\texttt{P}]\cdot u,\,[\texttt{P}]\cdot v)$（对某些 $u$、$v\in A^*$）。再次用上那条引理。令 $t := \mathsf{term}(\texttt{T})$，$s := ([\texttt{P}] \cdot u \Rightarrow [\texttt{P}] \cdot v)$，并置：

$$\mathsf{path}\,[\texttt{T.U == T.V}] := (p_1^{-1} \triangleright u) \circ (t \triangleleft s) \circ (p_1 \triangleright v)$$

对一个 **Sym** 步或 **Trans** 步，我们用 rewrite path 的取逆与复合运算：

$$\begin{gathered}
[\texttt{U == T}]\qquad(\textsf{Sym}\ \ [\texttt{T == U}])\\
[\texttt{T == V}]\qquad(\textsf{Trans}\ \ [\texttt{T == U}]\ \ [\texttt{U == V}])\\[1ex]
\mathsf{path}\,[\texttt{U == T}] := \mathsf{path}\,[\texttt{T == U}]^{-1}\\
\mathsf{path}\,[\texttt{T == V}] := \mathsf{path}\,[\texttt{T == U}] \circ \mathsf{path}\,[\texttt{U == V}]
\end{gathered}$$

对一个 **SameConf** 步，归纳假设给了我们一对 rewrite path：$p_1 := \mathsf{path}\,[\texttt{U: P}]$ 与 $p_2 := \mathsf{path}\,[\texttt{T == U}]$：

$$[\texttt{T: P}]\qquad(\textsf{SameConf}\ \ [\texttt{U: P}]\ \ [\texttt{T == U}])$$

我们先用 $p_2$ 把 $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]$ 重写成 $\mathsf{term}(\texttt{U})\cdot[\texttt{P}]$，再用 $p_1$ 把词尾的 $[\texttt{P}]$ 删掉，最后再用一次 $p_2$ 把 $\mathsf{term}(\texttt{U})$ 重写回 $\mathsf{term}(\texttt{T})$：

$$\mathsf{path}\,[\texttt{T: P}] := (p_2 \triangleright [\texttt{P}]) \circ p_1 \circ p_2^{-1}$$

对一个 **SameName** 步，归纳假设给了我们 $p_1 := \mathsf{path}\,[\texttt{U: P}]$ 与 $p_2 := \mathsf{path}\,[\texttt{T == U}]$：

$$[\texttt{T.A == U.A}]\qquad(\textsf{SameName}\ \ [\texttt{U: P}]\ \ [\texttt{T == U}])$$

构造新的 rewrite path 只需要 $p_2$，做一次 whisker 即可：

$$\mathsf{path}\,[\texttt{T.A == U.A}] := p_2 \triangleright \texttt{A}$$

归纳至此完整地定义出了「$\mathsf{path}$」，把它作用到我们最初那条 requirement 上，就得到了想要的结果。下面这张图列出了我们构造的每一条 rewrite path。

```
Conf:        [T: P]

    term(T)·[P] ────────→ term(T)


Same:        [T == U]

    term(T) ────────→ term(U)


Reflex:      [T == T]

    term(T)


AssocConf:   [T.U: Q]

    term(T.U)·[Q] ───⋯───→ term(T)·term_P(Self.U)·[Q]
                                        │
                                        ↓
    term(T.U)     ←───⋯─── term(T)·term_P(Self.U)


AssocSame:   [T.U == T.V]

    term(T.U) ───⋯───→ term(T)·term_P(Self.U)
                                    │
                                    ↓
    term(T.V) ←───⋯─── term(T)·term_P(Self.V)


Sym:         [U == T]

    term(T) ←───⋯─── term(U)


Trans:       [T == V]

    term(T) ───⋯───→ term(U) ───⋯───→ term(V)


SameConf:    [T: P]

    term(T)·[P] ───⋯───→ term(U)·[P]
                                │ ⋯
                                ↓
    term(T)     ←───⋯─── term(U)


SameName:    [T.A == U.A]

    term(T)·A ───⋯───→ term(U)·A
```

这张图断言的是：上面证明里给每条 inference rule 造出来的 rewrite path，在 rewrite graph 里各自长成什么形状。箭头一律是 rewrite（$\Rightarrow$），标着 `⋯` 的箭头表示「一段不止一步的 path」。**Conf**、**Same** 各是单独一步；**Reflex** 是孤立的一个顶点，也就是空 path；**AssocConf** 与 **AssocSame** 是一个方块——先把 $\mathsf{term}(\texttt{T.U})$ 换成「劈开」的形态 $\mathsf{term}(\texttt{T})\cdot\mathsf{term}_\texttt{P}(\texttt{Self.U})$，在那里施加 associated requirement（竖着那一步），再合回去；**Trans** 是两段首尾相接；**SameConf** 是先横着走到 $\mathsf{term}(\texttt{U})\cdot[\texttt{P}]$，竖着删掉 $[\texttt{P}]$，再横着走回来；**SameName** 则是把整条 path 右 whisker 一个 name symbol $\texttt{A}$。

> 译注：原书此处是一张由 9 张 tikzcd 交换图组成的图（每条 inference rule 一张），这里用 Unicode 箭头图转述，节点与箭头标签照抄原文；图的原貌见官方 PDF 对应章节。

现在我们走反方向，说明 requirement machine 里的 rewrite path 如何定义出 generic signature 里的 derived requirement。想一想我们该怎么把「$\mathsf{path}$」映射反过来。要克服的主要困难在于：每一步其实并没有真正用上所有假设。

1. **Reflex** 步 $[\texttt{T == T}]$ 的「$\mathsf{path}$」把 type parameter $\texttt{T}$ 有效性的那份证明整个丢掉了，因为在 monoid 里我们对**任何** term 都能立刻造出一条空 rewrite path。

   但这也意味着，如果我们从某个「不知所云」的 term——比如 $\texttt{A} \cdot \tau_{0,1} \cdot [\texttt{Sequence}] \cdot \tau_{0,0}$——上的空 rewrite path 出发，是没法「倒着走回去」、指望由此证明 $G$ 里任何 type parameter 有效的。

2. **SameName** 步 $[\texttt{T.A == U.A}]$ 的「$\mathsf{path}$」是由 $\mathsf{path}\,[\texttt{T == U}]$ 做 whisker 得到的，完全忽略了 $\mathsf{path}\,[\texttt{T: P}]$，因为**任何** rewrite path 我们都能 whisker。

   也就是说，只要有一对等价的 term $\mathsf{term}(\texttt{T}) \sim \mathsf{term}(\texttt{U})$，而 $\texttt{A}$ 是任意一个 name symbol，那么在 monoid 里**必然**有 $\mathsf{term}(\texttt{T})\cdot \texttt{A} \sim \mathsf{term}(\texttt{U})\cdot \texttt{A}$。

   然而我们未必推得出 $G\vdash[\texttt{T.A == U.A}]$，因为 $\texttt{T}$ 可能并不遵循任何声明了名为 `A` 的 associated type 的 protocol。按同样的道理，我们甚至可能连 $G\vdash[\texttt{T == U}]$ 都推不出来。

因此，$\sim_R$ 的等价类并不是每一个都对应到 generic signature $G$ 的一个 valid type parameter。在弄清楚怎样把一条具体的 rewrite path 翻译成 derivation 之前，我们得先搞明白哪些 rewrite path 对我们是有意义的。先从描述某个 type parameter $\texttt{T}$ 所对应的 $\mathsf{term}(\texttt{T})$ 的等价类开始。

**定义.** 设 $t\in A^*$ 是一个 term。

- 若 $t$ 的首个 symbol 是 generic parameter symbol，且其后所有 symbol 都是 name symbol，我们称 $t$ 是一个 **standard** term。
- 若 $t$ 的首个 symbol 是 generic parameter symbol，且其后所有 symbol 要么是 name symbol、要么是 protocol symbol，我们称 $t$ 是一个 **admissible** term。

**引理.** 上述定义的若干推论：

1. 每个 standard term 都是某个 unbound type parameter $\texttt{T}$ 的 $\mathsf{term}(\texttt{T})$。
2. 每个 standard term 都是 admissible term。
3. 若 $(u,v)$ 是「$\mathsf{rule}$」输出的一条 rewrite rule，则 $u$ 和 $v$ 都是 admissible term。
4. 若 $t\in A^*$ 是 admissible term，而 $u\in A^*$ 是若干 name symbol 与 protocol symbol 的组合（可以为空），则 $tu$ 是 admissible term。

下一条引理说的是：admissibility 在重写下保持不变。特别地，这意味着重写一个 standard term 得到的总是 admissible term。

**引理.** 设 $G$ 是一个 generic signature，$\langle A \vert R\rangle$ 是 $G$ 的 requirement machine。设 $t\in A^*$ 是 admissible term。若对另一个 term $z\in A^*$ 有 $t\sim z$，则 $z$ 也是 admissible term。

**证明.** 设 $p$ 是一条从 $t$ 到 $z$ 的 rewrite path。我们对 $p$ 的长度作归纳。

**基础情形.** 若是空 rewrite path，则 $t=z$，故 $z$ 是 admissible term。

**归纳步骤.** 否则 $p=p^\prime \circ s$，其中 $p^\prime$ 是一条 rewrite path、$s$ 是一步 rewrite。把 $s$ 写成 $s := x(u\Rightarrow v)y$，其中 $x$、$y\in A^*$，且 $(u,v)$ 或 $(v,u)$ 之一属于 $R$。

由归纳假设，$\operatorname{dst}(p^\prime)=\operatorname{src}(s)=xuy$ 是 admissible term。因为前缀 $xu$ 非空，所以右 whisker $y$ 只含 name symbol 与 protocol symbol。

若 $s$ 所施加的规则是某条 explicit requirement 的「$\mathsf{rule}$」，则左 whisker $x$ 为空——因为 $u$ 以一个 generic parameter symbol 开头。而且 $v$ 是 admissible term。于是 $\operatorname{dst}(s)=vy$ 是 admissible term。

若 $s$ 所施加的规则是某条 associated requirement 的「$\mathsf{rule}_\texttt{P}$」，则左 whisker $x$ 非空，而且它本身是 admissible term，同时 $u$ 与 $v$ 只能含 name symbol 与 protocol symbol。于是 $\operatorname{dst}(s)=xvy$ 是 admissible term。

正如 standard term 描述一个 unbound type parameter，admissible term 更一般地描述**一个 type parameter 外加一串 conformance requirement**。

**定义.** 「$\mathsf{type}$」函数把每个 admissible term 映射成一个 unbound type parameter：忽略 protocol symbol，并把 generic parameter symbol 与 name symbol 翻译成 generic parameter type 与 dependent member type：

$$\begin{array}{lcl}
\mathsf{type}(\tau_{d,i}) & := & \tau_{d,i} \\
\mathsf{type}(\texttt{U} \cdot \texttt{A}) & := & \mathsf{type}(\texttt{U})\texttt{.A} \\
\mathsf{type}(\texttt{U} \cdot [\texttt{P}]) & := & \mathsf{type}(\texttt{U})
\end{array}$$

**定义.** 设 $z\in A^*$ 是一个 admissible term。$z$ 的 **conformance chart** 是一个由 conformance requirement 组成的 **multiset**（也就是允许重复）：

1. 每条 requirement 对应 $z$ 里 protocol symbol 的一次出现。
2. 每条 requirement 的 subject type 是该 protocol symbol 之前的那段前缀。
3. 重复元素代表连续出现的相同 protocol symbol。

**定义.** 「$\mathsf{chart}$」函数把每个 admissible term 映射成它的 conformance chart：忽略 generic parameter symbol 与 name symbol，把 protocol symbol 转成 requirement：

$$\begin{array}{lcl}
\mathsf{chart}(\tau_{d,i}) & := & \{\}\\
\mathsf{chart}(\texttt{U} \cdot \texttt{A}) & := & \mathsf{chart}(\texttt{U})\\
\mathsf{chart}(\texttt{U} \cdot [\texttt{P}]) & := & \mathsf{chart}(\texttt{U}) \cup \{ [\mathsf{type}(\texttt{U})\texttt{: P}] \}
\end{array}$$

**例.** 若 $z=\mathsf{term}(\texttt{T})$ 是一个 standard term：

$$\begin{gathered}
\mathsf{type}(z)=\texttt{T}\\
\mathsf{chart}(z)=\{\}
\end{gathered}$$

若 $z=\mathsf{term}(\texttt{T})\cdot[\texttt{P}]$，其中 $\texttt{T}$ 是某个 unbound type parameter、$\texttt{P}$ 是某个 protocol：

$$\begin{gathered}
\mathsf{type}(z)=\texttt{T}\\
\mathsf{chart}(z)=\{[\texttt{T: P}]\}
\end{gathered}$$

若 $z=\tau_{0,1} \cdot [\texttt{Sequence}] \cdot [\texttt{Sequence}] \cdot \texttt{Iterator} \cdot [\texttt{IteratorProtocol}]$：

$$\begin{gathered}
\mathsf{type}(z) = \tau_{0,1}\texttt{.Iterator},\\
\mathsf{chart}(z) = \{\,[\tau_{0,1}\texttt{: Sequence}],\ [\tau_{0,1}\texttt{: Sequence}],\ [\tau_{0,1}\texttt{.Iterator: IteratorProtocol}]\,\}.
\end{gathered}$$

如果再加上两条假设——$\texttt{T}$ 是一个 **valid** type parameter，且我们的 generic signature $G$ 是 well-formed——那能说的就多得多了。（这么假设并不损失什么，因为否则我们会直接报错并拒绝这个程序，见 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节。）这么一来我们会看到：把一个 standard term 重写成一个 admissible term，等价于在推出一条 same-type requirement 的**同时，把目标 term 的 chart 里每一条 conformance requirement 也一并推出来**。

**定理.** 设 $G$ 是一个 well-formed generic signature，$\langle A \vert R\rangle$ 是 $G$ 的 requirement machine，$t$ 是一个 standard term 且 $\mathsf{type}(t)$ 是 $G$ 的一个 valid type parameter。又设给定 term $z\in A^*$ 满足 $t \sim z$。那么 $z$ 是 admissible term，而且：

1. $G \vdash [\mathsf{type}(t) == \mathsf{type}(z)]$。
2. 对每个 $[\mathsf{type}(u)\texttt{: P}]\in\mathsf{chart}(z)$，有 $G \vdash [\mathsf{type}(u)\texttt{: P}]$。

**证明.** 前一条引理已经说明 $z$ 是 admissible term。要立起主结论，我们这样推理：

1. 因为出发点是一个 standard term，所以 $z$ 里出现的每个 protocol symbol 都必然是我们这条 path 上某一步 rewrite 插进去的。

   当某一步 rewrite 引入一个 protocol symbol 时，我们必须有能力推出对应的那条 conformance requirement，并把它记到 chart 旁边。

2. 其余的 rewrite 步施加的是 same-type requirement，我们必须有能力构造出与这次变换对应的一条 derived same-type requirement。

   我们还得搞清楚 same-type requirement 规则对 conformance chart 产生了什么影响，以便在需要时更新我们收集到的那组 derived conformance requirement。

设 $p$ 是一条从 $t$ 到 $z$ 的 rewrite path。我们对 $p$ 的长度作归纳。

**基础情形.** 若 $p$ 为空，则 $t=z$，故 $\mathsf{type}(t)=\mathsf{type}(z)$，且 $\mathsf{chart}(z)=\{\}$。我们利用「$\mathsf{type}(t)$ 是 valid type parameter」这一假设，对 $G\vdash\mathsf{type}(t)$ 的一份 derivation 施加 **Reflex** inference rule，从而推出 same-type requirement $[\mathsf{type}(t) == \mathsf{type}(t)]$。不需要推出任何 conformance requirement。

**归纳步骤.** 否则 $p=p^\prime \circ s$，其中 $p^\prime$ 是 rewrite path、$s$ 是一步 rewrite。令 $z^\prime := \operatorname{dst}(p^\prime) = \operatorname{src}(s)$，并注意 $z=\operatorname{dst}(s)$。由归纳假设：

1. $G \vdash [\mathsf{type}(t) == \mathsf{type}(z^\prime)]$。
2. 对每个 $[\mathsf{type}(u^\prime)\texttt{: P}]\in\mathsf{chart}(z^\prime)$，有 $G \vdash [\mathsf{type}(u^\prime)\texttt{: P}]$。

这一步 rewrite $s$ 施加的是一条 conformance requirement 或 same-type requirement；该 requirement 要么是 explicit 的（「$\mathsf{rule}$」）、要么是 associated 的（「$\mathsf{rule}_\texttt{P}$」）；而这步 rewrite 可以是 positive 的、也可以是 negative 的。我们逐一考察这些情形，以推出关于 $z$ 的期望结论：

| | **种类** | **来源** | **符号** | **一般形式** |
|---|---|---|---|---|
| 1. | conformance | explicit | $+$ | $(u\cdot[\texttt{P}]\Rightarrow u)\triangleright y$ |
| 2. | | explicit | $-$ | $(u\Rightarrow u\cdot[\texttt{P}])\triangleright y$ |
| 3. | | associated | $+$ | $x\triangleleft([\texttt{P}]\cdot u\cdot[\texttt{Q}]\Rightarrow[\texttt{P}]\cdot u)\triangleright y$ |
| 4. | | associated | $-$ | $x\triangleleft([\texttt{P}]\cdot u\Rightarrow[\texttt{P}]\cdot u\cdot[\texttt{Q}])\triangleright y$ |
| 5. | same-type | explicit | $+$ | $(u\Rightarrow v)\triangleright y$ |
| 6. | | explicit | $-$ | $(v\Rightarrow u)\triangleright y$ |
| 7. | | associated | $+$ | $x\triangleleft([\texttt{P}]\cdot u\Rightarrow[\texttt{P}]\cdot v)\triangleright y$ |
| 8. | | associated | $-$ | $x\triangleleft([\texttt{P}]\cdot v\Rightarrow[\texttt{P}]\cdot u)\triangleright y$ |

**情形 1.** 一条 explicit conformance requirement 的 positive rewrite 步形如下式：左 whisker 为空，对某个 standard term $u$ 与 protocol symbol $[\texttt{P}]$ 有 $(u\cdot[\texttt{P}],u)\in R$，右 whisker $y$ 是 name symbol 与 protocol symbol 的组合：

$$(u\cdot[\texttt{P}]\Rightarrow u)\triangleright y$$

这步 rewrite 删掉 protocol symbol $[\texttt{P}]$ 的一次出现：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=u\cdot[\texttt{P}]\cdot y\\
z=\operatorname{dst}(s)=u\cdot y\\[1ex]
\mathsf{type}(z)=\mathsf{type}(z^\prime)\\
\mathsf{chart}(z)=\mathsf{chart}(z^\prime) \setminus \{[\mathsf{type}(u)\texttt{: P}]\}
\end{gathered}$$

因此我们的结论已经成立；只需把 $[\mathsf{type}(u)\texttt{: P}]$ 的那份 derivation「丢掉」即可。

**情形 2.** 一条 explicit conformance requirement 的 negative rewrite 步形如下式：左 whisker 同样为空，对某个 standard term $u$ 与 protocol symbol $[\texttt{P}]$ 有 $(u\cdot[\texttt{P}],u)\in R$，右 whisker $y$ 同前：

$$(u\Rightarrow u\cdot[\texttt{P}])\triangleright y$$

这步 rewrite 插入 protocol symbol $[\texttt{P}]$ 的一次出现：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=u\cdot y\\
z=\operatorname{dst}(s)=u\cdot[\texttt{P}]\cdot y\\[1ex]
\mathsf{type}(z)=\mathsf{type}(z^\prime)\\
\mathsf{chart}(z)=\mathsf{chart}(z^\prime) \cup \{[\mathsf{type}(u)\texttt{: P}]\}
\end{gathered}$$

要立起结论，我们必须推出 $[\mathsf{type}(u)\texttt{: P}]$。我们用一条 **Conf** elementary statement 来做，因为 $\mathsf{rule}\,[\mathsf{type}(u)\texttt{: P}]=(u\cdot[\texttt{P}],u)\in R$：

$$1.\ [\mathsf{type}(u)\texttt{: P}] \qquad (\textsf{Conf})$$

**情形 3.** 一条 associated conformance requirement 的 positive rewrite 步形如下式：$x$ 是 admissible term，对某个只含 name symbol 的 $u$ 有 $([\texttt{P}]\cdot u\cdot[\texttt{Q}],[\texttt{P}]\cdot u)\in R$，右 whisker $y$ 同前：

$$x\triangleleft([\texttt{P}]\cdot u\cdot[\texttt{Q}]\Rightarrow[\texttt{P}]\cdot u)\triangleright y$$

这步 rewrite 删掉一个 protocol symbol $[\texttt{Q}]$。注意 $\mathsf{type}(x\cdot [\texttt{P}] \cdot u)=\mathsf{type}(x\cdot u)$：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=x\cdot[\texttt{P}]\cdot u\cdot[\texttt{Q}]\cdot y\\
z=\operatorname{dst}(s)=x\cdot[\texttt{P}]\cdot u\cdot y\\[1ex]
\mathsf{type}(z)=\mathsf{type}(z^\prime)\\
\mathsf{chart}(z)=\mathsf{chart}(z^\prime) \setminus \{[\mathsf{type}(x\cdot u)\texttt{: Q}]\}
\end{gathered}$$

与情形 1 一样，我们把先前 $[\mathsf{type}(x\cdot u)\texttt{: Q}]$ 的那份 derivation「丢掉」。

**情形 4.** 一条 associated conformance requirement 的 negative rewrite 步形如下式：$x$ 是 admissible term，对某个只含 name symbol 的 $u$ 有 $([\texttt{P}]\cdot u\cdot [\texttt{Q}],[\texttt{P}]\cdot u)\in R$，右 whisker $y$ 同前：

$$x\triangleleft ([\texttt{P}]\cdot u\Rightarrow[\texttt{P}]\cdot u\cdot[\texttt{Q}])\triangleright y$$

这步 rewrite 插入一个 protocol symbol $[\texttt{Q}]$。同样有 $\mathsf{type}(x\cdot [\texttt{P}] \cdot u)=\mathsf{type}(x\cdot u)$：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=x\cdot[\texttt{P}]\cdot u\cdot y\\
z=\operatorname{dst}(s)=x\cdot[\texttt{P}]\cdot u\cdot[\texttt{Q}]\cdot y\\[1ex]
\mathsf{type}(z)=\mathsf{type}(z^\prime)\\
\mathsf{chart}(z)=\mathsf{chart}(z^\prime) \cup \{[\mathsf{type}(x\cdot u)\texttt{: Q}]\}
\end{gathered}$$

我们必须推出 $[\mathsf{type}(x\cdot u)\texttt{: Q}]$。由于 $[\mathsf{type}(x)\texttt{: P}]\in\mathsf{chart}(z^\prime)$，归纳假设告诉我们 $G\vdash[\mathsf{type}(x)\texttt{: P}]$，再施加 **AssocConf** inference rule 即得：

$$\begin{gathered}
1.\ [\mathsf{type}(x)\texttt{: P}] \qquad (\ldots)\\
2.\ [\mathsf{type}(x\cdot u)\texttt{: Q}] \qquad (\textsf{AssocConf}\ 1)
\end{gathered}$$

**情形 5.** 一条 explicit same-type requirement 的 positive rewrite 步形如下式：左 whisker 为空，对 standard term $u$、$v$ 有 $(u,v)\in R$，右 whisker $y$ 是 name symbol 与 protocol symbol 的组合：

$$(u\Rightarrow v)\triangleright y$$

这步 rewrite 把前缀 $u$ 换成 $v$：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=u\cdot y\\
z=\operatorname{dst}(s)=v\cdot y
\end{gathered}$$

这一情形下 $\mathsf{type}(z)$ 与 $\mathsf{type}(z^\prime)$ 并不恒同，所以我们得先推出 same-type requirement $G\vdash[\mathsf{type}(t) == \mathsf{type}(z)]$。下面我们把 $z^\prime$ 写成 $u\cdot y$，于是归纳假设给了我们这条 same-type requirement：

$$1.\ [\mathsf{type}(t) == \mathsf{type}(u\cdot y)] \qquad (\ldots)$$

现在用上「$G$ 是 well-formed」这一假设。因为 $\mathsf{type}(u\cdot y)$ 出现在上面那条 requirement 里，$G$ 的 well-formedness 允许我们推出 $G\vdash\mathsf{type}(u\cdot y)$：

$$2.\ \mathsf{type}(u\cdot y) \qquad (\ldots)$$

接着用一条 **Same** elementary statement 推出 $[\mathsf{type}(u) == \mathsf{type}(v)]$：

$$3.\ [\mathsf{type}(u) == \mathsf{type}(v)] \qquad (\textsf{Same})$$

此外，$\mathsf{type}(u)$ 是 $\mathsf{type}(u\cdot y)$ 的一个前缀。把 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）里那条关于一般 member type 的引理作用到 $G\vdash\mathsf{type}(v\cdot y)$ 与 $G\vdash[\mathsf{type}(u) == \mathsf{type}(v)]$ 上，即可推出 $G\vdash[\mathsf{type}(u\cdot y) == \mathsf{type}(v\cdot y)]$，换句话说就是 $[\mathsf{type}(z^\prime) == \mathsf{type}(z)]$：

$$4.\ [\mathsf{type}(z^\prime) == \mathsf{type}(z)] \qquad (\ldots)$$

最后施加 **Trans** inference rule，把上面这条 requirement 与归纳假设给我们的那条 same-type requirement 复合起来：

$$5.\ [\mathsf{type}(t) == \mathsf{type}(z)] \qquad (\textsf{Trans}\ 1\ 4)$$

现在我们拿到了想要的 same-type requirement，但还必须从 $\mathsf{chart}(z^\prime)$ 里的那些 conformance requirement 出发，推出 $\mathsf{chart}(z)$ 里的每一条。

注意 $z^\prime$ 与 $z$ 拥有数量相同、相对顺序也相同的 protocol symbol，而且它们全都落在右 whisker $y$ 里，所以 $\mathsf{chart}(z^\prime)$ 与 $\mathsf{chart}(z)$ 的元素之间存在一一对应。

在 $y$ 里 protocol symbol 的每一次出现处，我们把 $y$ 劈成两段，写成 $y=y_1\cdot[\texttt{P}]\cdot y_2$（对某些 $y_1$、$y_2\in A^*$ 与某个 protocol $\texttt{P}$）。于是：

$$\begin{gathered}
[\mathsf{type}(u\cdot y_1)\texttt{: P}]\in\mathsf{chart}(z^\prime)\\
[\mathsf{type}(v\cdot y_1)\texttt{: P}]\in\mathsf{chart}(z)
\end{gathered}$$

对每个 $[\mathsf{type}(u\cdot y_1)\texttt{: P}]\in\mathsf{chart}(z^\prime)$，我们知道 $\mathsf{type}(u\cdot y_1)$ 是 $\mathsf{type}(z^\prime)$ 的一个前缀。因为 $G$ 是 well-formed，`building-generic-signatures.tex` 里那条关于前缀的命题说 $G\vdash\mathsf{type}(u\cdot y_1)$。又因为 $\mathsf{type}(u)$ 也是 $\mathsf{type}(u\cdot y_1)$ 的前缀，那条一般 member type 引理给出 $G\vdash[\mathsf{type}(u\cdot y_1) == \mathsf{type}(v\cdot y_1)]$。最后用 **Sym** 把这条 requirement 翻个面，再施加 **SameConf**，即可推出 $\mathsf{chart}(z)$ 里我们想要的那条 conformance requirement：

$$\begin{gathered}
1.\ [\mathsf{type}(u\cdot y_1) == \mathsf{type}(v\cdot y_1)] \qquad (\ldots)\\
2.\ [\mathsf{type}(u\cdot y_1)\texttt{: P}] \qquad (\ldots)\\
3.\ [\mathsf{type}(v\cdot y_1) == \mathsf{type}(u\cdot y_1)] \qquad (\textsf{Sym}\ 1)\\
4.\ [\mathsf{type}(u\cdot y_1)\texttt{: P}] \qquad (\textsf{SameConf}\ 3\ 1)
\end{gathered}$$

**情形 6.** 一条 explicit same-type requirement 的 negative rewrite 步形如下式：对 standard term $u$、$v$ 有 $(u,v)\in R$，左 whisker 为空，右 whisker $y$ 是 name symbol 与 protocol symbol 的组合：

$$(v\Rightarrow u)\triangleright y$$

做法同情形 5，只不过当 **Same** elementary statement 给出 $[\mathsf{type}(u) == \mathsf{type}(v)]$ 时，我们必须先施加 **Sym** inference rule 把它翻成 $[\mathsf{type}(v) == \mathsf{type}(u)]$ 再往下走：

$$\begin{gathered}
1.\ [\mathsf{type}(u) == \mathsf{type}(v)] \qquad (\textsf{Same})\\
2.\ [\mathsf{type}(v) == \mathsf{type}(u)] \qquad (\textsf{Sym}\ 1)
\end{gathered}$$

随后就能像之前那样推出最终的 same-type requirement，以及 chart 里列出的全部 conformance requirement。

**情形 7.** 一条 associated same-type requirement 的 positive rewrite 步形如下式：左 whisker $x$ 是 admissible term，$([\texttt{P}]\cdot u,[\texttt{P}] \cdot v)\in R$，$u$ 与 $v$ 只含 name symbol，右 whisker $y$ 是 name symbol 与 protocol symbol 的组合：

$$x\triangleleft([\texttt{P}]\cdot u\Rightarrow[\texttt{P}]\cdot v)\triangleright y$$

这步 rewrite 把 term 中段的 $[\texttt{P}]\cdot u$ 换成 $[\texttt{P}]\cdot v$：

$$\begin{gathered}
z^\prime=\operatorname{src}(s)=x\cdot[\texttt{P}]\cdot u\cdot y\\
z=\operatorname{dst}(s)=x\cdot[\texttt{P}]\cdot v\cdot y
\end{gathered}$$

注意 $[\mathsf{type}(x)\texttt{: P}]\in\mathsf{chart}(z^\prime)$，它由归纳假设可推出。另外注意 $\mathsf{type}(x\cdot[\texttt{P}]\cdot u)=\mathsf{type}(x\cdot u)$。我们经由 **AssocSame** inference rule，从 $[\mathsf{type}(x)\texttt{: P}]$ 推出 $[\mathsf{type}(x\cdot u) == \mathsf{type}(x\cdot v)]$：

$$\begin{gathered}
1.\ [\mathsf{type}(x)\texttt{: P}] \qquad (\ldots)\\
2.\ [\mathsf{type}(x\cdot u) == \mathsf{type}(x\cdot v)] \qquad (\textsf{AssocSame}\ 1)
\end{gathered}$$

接着把那条一般 member type 引理作用到 $G\vdash\mathsf{type}(x\cdot u\cdot y)$ 与 $G\vdash[\mathsf{type}(x\cdot u) == \mathsf{type}(x\cdot v)]$ 上，推出 $G\vdash[\mathsf{type}(x\cdot u\cdot y) == \mathsf{type}(x\cdot v\cdot y)]$，换句话说就是 $[\mathsf{type}(z^\prime) == \mathsf{type}(z)]$：

$$4.\ [\mathsf{type}(z^\prime) == \mathsf{type}(z)] \qquad (\ldots)$$

最后施加 **Trans** inference rule，把上面这条 requirement 与归纳假设给我们的那条 same-type requirement 复合起来：

$$5.\ [\mathsf{type}(t) == \mathsf{type}(z)] \qquad (\textsf{Trans}\ 1\ 4)$$

我们还得更新 conformance chart。$x$ 和 $y$ 里都可能出现 protocol symbol，但由于 $\mathsf{chart}(x)\subseteq\mathsf{chart}(z^\prime)\cap\mathsf{chart}(z)$，$\mathsf{chart}(x)$ 里那些两边共有的 requirement 保持不变。至于 $y$ 里 protocol symbol 出现处对应的新 conformance requirement，按情形 5 的办法推出即可。

**情形 8.** 一条 associated same-type requirement 的 negative rewrite 步形如下式：左 whisker $x$ 是 admissible term，$([\texttt{P}]\cdot u,[\texttt{P}]\cdot v)\in R$，$u$ 与 $v$ 只含 name symbol，右 whisker $y\in A^*$ 是 name symbol 与 protocol symbol 的组合：

$$x\triangleleft([\texttt{P}]\cdot v\Rightarrow[\texttt{P}]\cdot u)\triangleright y$$

做法同情形 7，只不过要像情形 6 那样先用 **Sym** 把 same-type requirement 翻个面。

我们真正想要的那条陈述，从上面这条定理里自然掉出来：

**推论.** 设 $G$ 是一个 generic signature，$\langle A \vert R\rangle$ 是 $G$ 的 requirement machine。假设 $G$ 是 well-formed 的。

1. 若对某个 valid type parameter $\texttt{T}$ 有 $\mathsf{term}(\texttt{T})\cdot[\texttt{P}] \sim \mathsf{term}(\texttt{T})$，则 $G \vdash [\texttt{T: P}]$。
2. 若对 valid type parameter $\texttt{T}$、$\texttt{U}$ 有 $\mathsf{term}(\texttt{T}) \sim \mathsf{term}(\texttt{U})$，则 $G\vdash[\texttt{T == U}]$。

**证明.** 两种情形下我们手上都是「一个 standard term 与一个 admissible term 之间的等价」，所以可以施加前一条定理。

**情形 1.** 令 $t := \mathsf{term}(\texttt{T})$，$z := \mathsf{term}(\texttt{T})\cdot[\texttt{P}]$。我们有：

$$\begin{gathered}
\mathsf{type}(z)=\texttt{T}\\
\mathsf{chart}(z) = \{[\texttt{T: P}]\}
\end{gathered}$$

翻译这条 rewrite path，得到 $G\vdash[\texttt{T == T}]$（丢掉不要）以及 $G\vdash[\texttt{T: P}]$（正是要的）。

**情形 2.** 令 $t := \mathsf{term}(\texttt{T})$，$z := \mathsf{term}(\texttt{U})$。我们有：

$$\begin{gathered}
\mathsf{type}(z) = \texttt{U}\\
\mathsf{chart}(z)=\{\}
\end{gathered}$$

翻译这条 rewrite path，得到 $G\vdash[\texttt{T == U}]$（正是要的），外加一张空的 derived conformance requirement 清单（丢掉不要）。

### The decision procedure.

回忆 `generic-signatures.tex` 的 Generic Signature Queries 一节里那四个基本 generic signature query，它们刻画了一个 generic signature 的等价类结构。我们看到前两个从理论角度讲是最根本的。

把 `monoids.tex` 里那条「convergent 则可判定」的推论、上面那条把 derivation 翻成 path 的定理、以及刚才那条把 path 翻回 derivation 的推论合起来看：如果我们有一个 well-formed generic signature $G$，它由一个 convergent rewriting system $\langle A \vert R\rangle$ 给出，且给定的那些 type parameter 都是 valid 的，那么：

1. $G\vdash[\texttt{T: P}]$ **当且仅当** $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]$ 与 $\mathsf{term}(\texttt{T})$ 有相同的 normal form。
2. $G\vdash[\texttt{T == U}]$ **当且仅当** $\mathsf{term}(\texttt{T})$ 与 $\mathsf{term}(\texttt{U})$ 有相同的 normal form。

而且，关键在于，这里的前提条件全都是我们能够**检查**的，term 的 normal form 也能用 `monoids.tex` 的 normal form algorithm 算出来。到这一步，事情已经相当清楚了：

> 按下面的方式实现时，这两个基本 generic signature query 总能在有限步内给出正确答案。
>
> - **Query：** `requiresProtocol(G, T, P)`
>
>   对 $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]$ 和 $\mathsf{term}(\texttt{T})$ 施加 normal form algorithm，检查得到的是不是一对恒同的 term。
>
> - **Query：** `areReducedTypeParametersEqual(G, T, U)`
>
>   对 $\mathsf{term}(\texttt{T})$ 和 $\mathsf{term}(\texttt{U})$ 施加 normal form algorithm，检查得到的是不是一对恒同的 term。

> 译注：本库不跑重写系统，但它读到的每一个 type parameter 都已经是这套 normal form 的产物——二进制里的 requirement、mangled name 里的 dependent member type，全是编译器把 term 归约到 canonical form 之后写下的。本库需要判断「两个 type parameter 是不是同一个」时，靠的也是这份既成的 canonical 顺序，而不是自己重算；opaque type descriptor 里 requirement 的排列顺序就是一例，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

## Symbols

我们已经讲清楚了 Swift 泛型的核心模型如何把 requirement 翻译成 rewrite rule。这些规则定义在一个由 generic parameter symbol、name symbol、protocol symbol 组成的 alphabet 上。本章余下的部分描述实际实现中的完整 Swift 泛型模型。从这里开始，数学上的严格性会少一些，对工程问题的关注会多一些。

我们先给 alphabet 添几类 symbol，以便把 bound type parameter 和其余几类 requirement 也编码进去。虽然前面的正确性结果只依赖对称的 term 等价关系，但实现里我们要用 normal form algorithm 拿到可计算的东西，所以还要在 alphabet 上定义一个 reduction order。

symbol 由 **rewrite context** 构造——那是 `basic-operation.tex` 的 Protocol Components 一节里那个全局单例，管理着 requirement machine 实例的生命周期。symbol 共有八类，每类各有自己的一组 structural component。这和 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）里给 type 建模的方式很像。

对每类 symbol，都有一个构造函数接收其 structural component，返回一个指向「由这组 structural component 构成的那个唯一 symbol」的指针。一个 symbol 的指针恒等性由它的 kind 与 structural component 决定，所以比较两个 symbol 是否相等非常便宜。

**定义.** Requirement Machine alphabet 里的一个 **symbol** 是下列各项之一的实例：

- 一个 **generic parameter symbol** $\tau_{d,i}$，其中 depth $d$ 与 index $i\in\mathbb{N}$。
- 一个 **name symbol** $\texttt{A}$，其中 $\texttt{A}$ 是程序里出现的某个 identifier。
- 一个 **protocol symbol** $[\texttt{P}]$，其中 $\texttt{P}$ 是指向某个 protocol declaration 的引用。
- 一个 **associated type symbol** $[\texttt{P}\vert\texttt{A}]$，其中 $\texttt{P}$ 是某个 protocol，$\texttt{A}$ 是某个 associated type declaration 的名字。
- 一个 **layout symbol** $[\mathsf{layout}\colon\texttt{L}]$，其中 `L` 是一个 layout constraint，取值为 `AnyObject` 或 `_NativeClass`。
- 一个 **superclass symbol** $[\mathsf{superclass}\colon \texttt{C};\,t_0,\ldots,t_n]$，其中 $\texttt{C}$ 是一个 interface type，称为该 symbol 的 **pattern type**，而各 $t_i$ 是 term，称为 **substitution term**。在 superclass symbol 里，pattern type 是一个 class 或 generic class type。
- 一个 **concrete type symbol** $[\mathsf{concrete}\colon \texttt{X};\,t_0,\ldots,t_n]$，此时 pattern type $\texttt{X}$ 可以是任何不是 type parameter 的 interface type，各 $t_i$ 是 substitution term。
- 一个 **concrete conformance symbol** $[\mathsf{concrete}\colon \texttt{X}\colon\texttt{P};\,t_0,\ldots,t_n]$，其中 $\texttt{X}$ 是任何不是 type parameter 的 interface type，各 $t_i$ 是 substitution term，$\texttt{P}$ 是指向某个 protocol declaration 的引用。

### Name symbols.

name symbol 在本章开头已经引入过，没太多别的可说，但要补一句。在一个 well-formed generic signature $G$ 的 requirement machine 里，每个 name symbol 「$\texttt{A}$」都必须是某个满足 $G\prec\texttt{P}$ 的 $\texttt{P}$ 的某个 associated type 或 type alias 的名字——否则「$\texttt{A}$」不可能出现在任何 valid type parameter 里。不过我们允许为任意 identifier 构造 name symbol，这样才能把非法程序也建模出来。无论如何，被构造出来的 name symbol 总是有限的。

### Protocol symbols.

protocol symbol 上的 reduction order 有这样一条性质：若 protocol $\texttt{Q}$ 继承自 protocol $\texttt{P}$，则 $[\texttt{P}]<[\texttt{Q}]$。

考虑这样一张有向图：顶点是 protocol declaration；对每一对满足「$\texttt{Q}$ 继承自 $\texttt{P}$」的 protocol $\texttt{Q}$ 与 $\texttt{P}$，画一条以 $\texttt{Q}$ 为 source、$\texttt{P}$ 为 destination 的边。定义 $\mathsf{depth}(\texttt{P})\in\mathbb{N}$ 为从 $\texttt{P}$ 出发可达的 protocol 个数（不含 $\texttt{P}$ 自身）。要计算一个 protocol 的「$\mathsf{depth}$」，我们拿 $\texttt{P}$ 去求值 **all inherited protocols request**，它返回从 $\texttt{P}$ 可达的全部 protocol 构成的集合，再取这个集合的元素个数。

**算法（Protocol reduction order）.** 输入两个 protocol declaration $\texttt{P}$ 与 $\texttt{Q}$，输出「$<$」「$>$」「$=$」三者之一。

1. 若 $\mathsf{depth}(\texttt{P})>\mathsf{depth}(\texttt{Q})$，返回「$<$」。（越深的 protocol 越小。）
2. 若 $\mathsf{depth}(\texttt{P})<\mathsf{depth}(\texttt{Q})$，返回「$>$」。
3. 若 $\mathsf{depth}(\texttt{P})=\mathsf{depth}(\texttt{Q})$，用 `generic-signatures.tex` 的那个 Protocol order 算法比较这两个 protocol。

**例.** 标准库里不少 protocol 都继承自 `Sequence`：

```swift
public protocol Sequence {...}
public protocol Collection: Sequence {...}
public protocol BidirectionalCollection: Collection {...}
public protocol MutableCollection: Collection {...}
public protocol RandomAccessCollection: BidirectionalCollection {...}
```

上面这些 protocol 继承关系定义出下面这张图：

```
RandomAccessCollection ──→ BidirectionalCollection ──┐
                                                     ├──→ Collection ──→ Sequence
                           MutableCollection ────────┘
```

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 图转述；箭头由「继承者」指向「被继承的 protocol」，与原书的 source / destination 方向一致。图的原貌见官方 PDF 对应章节。

对应的 protocol symbol 排序如下——注意越深的 protocol 排在越浅的 protocol 前面：

$$\begin{gathered}
[\texttt{RandomAccessCollection}]\\
{} < [\texttt{BidirectionalCollection}]<[\texttt{MutableCollection}]\\
{} < [\texttt{Collection}]\\
{} < [\texttt{Sequence}]
\end{gathered}$$

### Associated type symbols.

name symbol 代表一个 unbound dependent member type，而 **associated type symbol** 代表一个 **bound** dependent member type。我们用记号 $[\texttt{P}\vert\texttt{A}]$ 表示 associated type symbol，以唤起「protocol symbol $[\texttt{P}]$ 与 name symbol $\texttt{A}$ 融合在一起」的意象。事实上，对每个 associated type symbol $[\texttt{P}\vert\texttt{A}]$，我们都会引入一条形如 $[\texttt{P}]\cdot\texttt{A}\sim[\texttt{P}\vert\texttt{A}]$ 的 **associated type rule**。

由于 protocol 继承的缘故，associated type symbol 比 associated type declaration「更多」。若 $[\texttt{P}\vert\texttt{A}]$ 是一个 associated type symbol，则 $\texttt{A}$ 要么是 $\texttt{P}$ 自己的某个 associated type 的名字，要么是 $\texttt{P}$ 的某个 base protocol 的 associated type 的名字。正因如此，associated type symbol 并不指向某个 associated type **declaration**；它的存储里分开引用 protocol declaration 与 identifier。

下一节我们会看到 associated type symbol 是如何在把 type parameter 翻成 term 的过程中冒出来的。本章 Rules 一节会讨论 associated type rule。

为什么我们需要 associated type symbol？有两个理由，`completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 会详细研究它们：

1. `generic-signatures.tex` 的 Generic Signature Queries 一节里我们看到，`isValidTypeParameter()` 可以用 `areReducedTypeParametersEqual()` 和 `requiresProtocol()` 这两个 generic signature query 实现。一旦加上 associated type symbol，我们就能直接用 normal form algorithm 判定一个 type parameter 是否 valid。
2. 更重要的是，事实表明：当 generic signature 的等价类有无穷多个时，我们**必须**有 associated type symbol 才能得到一个 convergent 的 rewriting system。

associated type symbol 上的 reduction order 由 identifier 的 lexicographic order 与 protocol reduction order 共同定义：

**算法（Associated type reduction order）.** 输入两个 associated type symbol $[\texttt{P}\vert\texttt{A}]$ 与 $[\texttt{Q}\vert\texttt{B}]$，输出「$<$」「$>$」「$=$」三者之一。

1. 用 lexicographic order 比较 identifier $\texttt{A}$ 与 $\texttt{B}$。若结果是「$<$」或「$>$」就返回它。否则两个 associated type 同名。
2. 用上面的 Protocol reduction order 算法比较 protocol $\texttt{P}$ 与 $\texttt{Q}$，返回其结果。

**例.** 接着上面那个 protocol reduction order 的例子。`Sequence` 协议声明了一个 `Element` associated type，所以继承自 `Sequence` 的 protocol 也继承了这个 associated type。`RandomAccessCollection` 的 **protocol machine** 的 alphabet 里有若干 associated type symbol，排序如下：

$$\begin{gathered}
[\texttt{RandomAccessCollection}\vert\texttt{Element}]\\
{} < [\texttt{BidirectionalCollection}\vert\texttt{Element}]\\
{} < [\texttt{Collection}\vert\texttt{Element}]\\
{} < [\texttt{MutableCollection}\vert\texttt{Element}]\\
{} < [\texttt{Sequence}\vert\texttt{Element}]
\end{gathered}$$

至于这个顺序**为什么**必须尊重 protocol 继承，见 `completion.tex` 的 Recursive Conformances 一节。

> 译注：`[P|A]` 这种把 associated type 绑死在声明它的 protocol 上的形态，序列化到二进制里就是 mangled name 里的 `T.[P]A`。本库离线算布局时要把它解回具体类型：`DependentMemberTypeBridge` 拿着这个形状，去声明该 conformance 的那个镜像的 `__swift5_assocty` 里查 type witness，再把 base 自己的 generic argument 代进去。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

接下来三类 symbol 出现在我们为 layout requirement、superclass requirement 和 concrete type requirement 构造 rewrite rule 的时候。正如一条 conformance requirement $[\texttt{T: P}]$ 定义出一条 rewrite rule $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]\sim\mathsf{term}(\texttt{T})$，这几类 requirement 也定义出形如 $\mathsf{term}(\texttt{T})\cdot s\sim\mathsf{term}(\texttt{T})$ 的 rewrite rule，其中 $\texttt{T}$ 是该 requirement 的 subject type，$s$ 是一个 layout、superclass 或 concrete type symbol。

### Layout symbols.

$[\mathsf{layout}\colon\texttt{AnyObject}]$ 这个 layout symbol 代表 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）里 requirement 定义中引入的那个 `AnyObject` layout constraint。当我们把一条 layout requirement $[\texttt{T: AnyObject}]$ 翻译成规则 $\mathsf{term}(\texttt{T})\cdot[\mathsf{layout}\colon\texttt{AnyObject}] \sim \mathsf{term}(\texttt{T})$ 时，它就出现了。

我们在 `generic-signatures.tex` 的 Generic Signature Queries 一节里还提到过 `_NativeClass` 这个 layout constraint。用户没法直接写出它，但一条「指向 Swift 原生 class」的 superclass requirement 会蕴含它。这两个 layout symbol 的顺序如下：

$$[\mathsf{layout}\colon\texttt{AnyObject}] < [\mathsf{layout}\colon\texttt{\_NativeClass}]$$

### Superclass and concrete type symbols.

superclass symbol 与 concrete type symbol 编码的是一个「可能含有 type parameter」的具体类型。要构造这种 symbol，我们先把这个具体类型拆成一个 **pattern type** 加一列 **substitution term**：

$$\text{concrete type} = \text{pattern type} + \text{substitution terms}$$

我们之所以要构造这个 symbol，是因为正在把某条 explicit 或 associated requirement 翻译成 rewrite rule，所以会按情况用「$\mathsf{term}$」或「$\mathsf{term}_\texttt{P}$」映射去翻译具体类型里出现的每个 type parameter。（下一节会介绍为此所用的 Build term for explicit requirement 与 Build term for associated requirement 两个算法；眼下本章开头给的定义仍然有效。）接着我们把每个 type parameter 替换成一个「幽灵」generic parameter $\tau_{0,i}$，其 depth 恒为零，而 index $i\in\mathbb{N}$ 是对应 substitution term 在那张列表里的下标。

**算法（Build concrete type symbol）.** 输入一个 interface type $\texttt{X}$，以及可选的一个 protocol $\texttt{P}$。输出一个 pattern type 连同一列 substitution term。注意类型 $\texttt{X}$ 自身不能是 type parameter。

1. （Initialize）置 $S\leftarrow\{\}$，置 $i\leftarrow 0$。
2. （Recurse）对 $\texttt{X}$ 的树形结构做一次前序遍历，把 $\texttt{X}$ 里出现的每个 type parameter $\texttt{T}$ 按下面的方式变换，构成新类型 `Y`：
   1. （Record）若我们是在 lower 一条 generic signature requirement，令 $t := \mathsf{term}(\texttt{T})$；否则令 $t := \mathsf{term}_\texttt{P}(\texttt{T})$。置 $S\leftarrow S + \{t\}$。（于是 $S[i]=t$。）
   2. （Transform）把 $\texttt{T}$ 的这一次出现替换成 $\tau_{0,i}$。
   3. （Next）置 $i\leftarrow i + 1$。（此时 $|S|=i$。）
3. 返回 pattern type `Y` 与 substitution term 数组 $S$。

**例.** 给定 explicit requirement $[\tau_{0,0} == \texttt{Array<}\tau_{0,1}\texttt{.Element>}]$，我们把右端拆解如下：

$$\texttt{Array<}\tau_{0,1}\texttt{.Element>} = \texttt{Array<}\tau_{0,0}\texttt{>} + \{\tau_{0,1}\cdot\texttt{Element}\}$$

于是可以由 pattern type $\texttt{Array<}\tau_{0,0}\texttt{>}$ 与 substitution term 列表 $\{\tau_{0,1}\cdot\texttt{Element}\}$ 构造出 concrete type symbol $[\mathsf{concrete}\colon \texttt{Array<}\tau_{0,0}\texttt{>};\, \tau_{0,1}\cdot\texttt{Element}]$。

**例.** 如果我们手上是一个不含 type parameter 的 fully concrete type，那么 substitution term 列表就是空的。例如 superclass requirement $[\texttt{Self: NSObject}]$ 的右端定义出 symbol $[\mathsf{superclass}\colon \texttt{NSObject}]$。

**例.** Build concrete type symbol 算法输出的 pattern type 满足若干条件：

1. pattern type 自身不能是 type parameter。
2. pattern type 不含任何 dependent member type。
3. pattern type 里出现的每个 generic parameter type 的 depth 都是零。
4. 每个 generic parameter type 的 index 都唯一。
5. index 连续，且从零开始。

下面这些都不是合法的 pattern type：

$$\begin{gathered}
\tau_{0,0}\\
\texttt{Array<}\tau_{0,0}\texttt{.Element>}\\
\texttt{Array<}\tau_{1,0}\texttt{>}\\
\texttt{Dictionary<}\tau_{0,0}\texttt{,~}\tau_{0,0}\texttt{>}\\
\texttt{(}\tau_{0,1}\texttt{) -> }\tau_{0,0}
\end{gathered}$$

要比较一对 superclass symbol 或 concrete type symbol，我们先按 canonical type equality 比较它们的 pattern type，再用下一节将定义的 term reduction order 比较它们的 substitution term。注意这是一个 **partial order**：pattern type 不同的两个 symbol 不可比。

**算法（Concrete type reduction order）.** 输入两个 superclass symbol 或 concrete type symbol $s_1$ 与 $s_2$，输出「$<$」「$>$」「$=$」或「$\bot$」。

1. （Invariant）我们假定两个 symbol 已经是同一 kind；不同 kind 的比较交给下面定义的通用 symbol order 处理。
2. （Incomparable）按 canonical type equality 比较 $s_1$ 与 $s_2$ 的 pattern type。若两者不同，返回「$\bot$」。
3. （Initialize）两个 symbol 的 pattern type 相同，所以它们的 substitution term 个数也必然相同，记为 $n$。置 $i\leftarrow 0$。
4. （Equal）若 $i=n$，说明所有 substitution term 都恒同。返回「$=$」。
5. （Compare）用下一节的 Weighted shortlex order 算法比较 $s_1$ 与 $s_2$ 的第 $i$ 个 substitution term。若结果是「$<$」或「$>$」就返回它。
6. （Next）否则置 $i\leftarrow i+1$，回到第 4 步。

superclass symbol 与 concrete type symbol 里虽然可以含有 term，但那些 term 自身不能再含有 superclass symbol 与 concrete type symbol，因为对应 type parameter 的 term 只含 generic parameter symbol、name symbol、protocol symbol 和 associated type symbol。

### Concrete conformance symbols.

concrete conformance symbol 的记号看上去和 concrete type symbol 一样，但它还额外存了一个 protocol declaration。我们会在 `property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)） 的 Concrete Conformances 一节看到：当一个 type parameter $\texttt{T}$ 同时受到一条 conformance requirement $[\texttt{T: P}]$ 和一条 concrete same-type requirement $[\texttt{T == X}]$ 的约束时，我们会引入一条含有 concrete conformance symbol 的 rewrite rule：

$$\mathsf{term}(\texttt{T})\cdot[\mathsf{concrete}\colon \texttt{X}\colon\texttt{P};\,\ldots] \sim \mathsf{term}(\texttt{T})$$

要比较两个 concrete conformance symbol，我们先比较它们的 protocol，再比较 pattern type 与 substitution term。

**算法（Concrete conformance reduction order）.** 输入两个 concrete conformance symbol $s_1$ 与 $s_2$，输出「$<$」「$>$」「$=$」或「$\bot$」。

1. 用 Protocol reduction order 算法比较 $s_1$ 与 $s_2$ 的 protocol。若结果是「$<$」或「$>$」就返回它。
2. 否则按 Concrete type reduction order 算法比较 pattern type 与 substitution term。

### Symbol order.

要比较任意一对 symbol，我们先定义一个从 symbol kind 到自然数的映射：

| symbol kind | 数值 |
|---|---|
| Concrete conformance | 0 |
| Protocol | 1 |
| Associated type | 2 |
| Generic parameter | 3 |
| Name | 4 |
| Layout | 5 |
| Superclass | 6 |
| Concrete type | 7 |

**算法（Symbol reduction order）.** 输入两个 symbol，输出「$<$」「$>$」「$=$」或「$\bot$」。

若两个 symbol 的 kind 不同，就按上表把它们的 kind 映射成自然数，再用 $\mathbb{N}$ 上通常的线性序比较这两个数。否则两个 symbol 是同一 kind，而每种情形我们前面都已经交代过了：

- generic parameter symbol 用 `generic-signatures.tex` 的 Generic parameter order 算法。
- name symbol 用字符串上的 lexicographic order。
- protocol symbol 用 Protocol reduction order 算法。
- associated type symbol 用 Associated type reduction order 算法。
- layout symbol 用前面描述的那个顺序。
- superclass symbol 用 Concrete type reduction order 算法。
- concrete type symbol 用 Concrete type reduction order 算法。
- concrete conformance symbol 用 Concrete conformance reduction order 算法。

## Terms

在理论里，一个 term 是 free monoid 的一个元素。在实现里，一个 **term** 是一串 symbol。它有两种口味。**mutable term** 是一个 value type，自己持有一块堆分配的缓冲区；mutable term 改起来便宜，但复制和存储都贵。**immutable term** 分配起来贵，因为它要由 rewrite context 做 unique 化，但比较相等很便宜——长度与 symbol 都相同的两个 immutable term，作为指针就相等。normal form algorithm 与 Knuth-Bendix completion 用 mutable term 存中间结果；存一条 rewrite rule 的左端与右端 term 时则用 immutable term。

下一节我们会看到，requirement machine 里的 rewrite rule 两端永远都是非空 term。正因如此，空 term $\varepsilon$ 没有 immutable term 的表示。mutable term 倒是可以为空——这正是一个 mutable term 刚创建、还没添加任何 symbol 时的初始状态。

下面我们描述一对把 type parameter 翻译成 mutable term 的算法，它们实现本章开头的「$\mathsf{term}$」与「$\mathsf{term}_\texttt{P}$」映射。先从「$\mathsf{term}$」开始，它用于在 **query machine** 或 **minimization machine** 里构造 term。（四类 machine 见 `basic-operation.tex`。）我们把这个映射扩展到能处理 bound dependent member type，它们会翻译成 associated type symbol；当我们基于一个既有 generic signature 的 minimal requirement 构造 query machine 时，它们就会出现。大致意思如下：

| $\texttt{T}$ | $\mathsf{term}(\texttt{T})$ |
|---|---|
| $\tau_{0,0}\texttt{.A.B}$ | $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ |
| $\tau_{0,0}\texttt{.[P]A.[Q]B}$ | $\tau_{0,0}\cdot[\texttt{P}\vert\texttt{A}]\cdot[\texttt{Q}\vert\texttt{B}]$ |

一个 type parameter 是一条单向链表，每个内部节点是一个 dependent member type，链表的尾部是一个 generic parameter type。链表的头是**最外层**的 member type——在 $\tau_{0,0}\texttt{.A.B}$ 里就是 `B`——而每个 dependent member type 的 base type 就是那根「next」指针。

下面这个算法是「把链表转成数组」这一经典算法的一个实例。我们从头到尾遍历链表，每一步在 term 末尾添一个 symbol；这样得到的 term 里，**最后**一个元素才是 generic parameter symbol。于是我们再把 symbol 的顺序反转，得到最终结果。

**算法（Build term for explicit requirement）.** 输入一个 type parameter $\texttt{T}$，输出一个（非空的）mutable term。

1. （Initialize）令 $t$ 为一个新的空 mutable term。
2. （Base case）若 $\texttt{T}$ 是一个 generic parameter type $\tau_{d,i}$：
   1. 先把 generic parameter symbol $\tau_{d,i}$ 添到 $t$ 上。
   2. 然后反转 $t$ 里的 symbol 顺序，返回 $t$。
3. （Recursive case）否则 $\texttt{T}$ 是一个 dependent member type：
   1. 若 $\texttt{T}$ 是一个 unbound dependent member type `U.A`（对某个 type parameter $\texttt{U}$），把 name symbol $\texttt{A}$ 添到 $t$ 上。
   2. 否则 $\texttt{T}$ 是一个 bound dependent member type `U.[P]A`（同样对某个 type parameter $\texttt{U}$）。把 associated type symbol $[\texttt{P}\vert\texttt{A}]$ 添到 $t$ 上。

   置 $\texttt{T} \leftarrow \texttt{U}$，回到第 2 步。

`building-generic-signatures.tex` 里那条关于 bound 与 unbound 等价的定理说：每个 valid type parameter 都有一个等价的、长度相同的 bound 形式和 unbound 形式。在 requirement machine 里，若对这样一对等价的 type parameter 施加「$\mathsf{term}$」，我们得到的是一对在「由 rewrite rule 生成的 term 等价关系」下等价的 term。unbound type parameter 映射到一个含 name symbol 的 term，bound type parameter 映射到一个含 associated type symbol 的 term。这种等价是 associated type rule 的推论，下一节会介绍。

Build term for explicit requirement 算法的另一种同样合法的实现，是把 bound 与 unbound 的 dependent member type 都映射到 name symbol。那样会给 normal form algorithm 和 completion 添更多活儿，我们的实现避开了这一点。

接下来看「$\mathsf{term}_\texttt{P}$」映射，它用于在 **protocol machine** 或 **protocol minimization machine** 里构造 term。在核心模型里，「$\mathsf{term}_\texttt{P}$」把 $G_\texttt{P}$ 的一个 unbound type parameter 映射成一个以 protocol symbol 打头、后跟一串 name symbol 的 term。我们把它扩展到 bound type parameter 的做法是：去掉那个 protocol symbol，并把每个 dependent member type 翻译成 associated type symbol：

| $\texttt{T}$ | $\mathsf{term}_\texttt{P}(\texttt{T})$ |
|---|---|
| $\texttt{Self}$ | $[\texttt{P}]$ |
| $\texttt{Self.A.B}$ | $[\texttt{P}]\cdot\texttt{A}\cdot\texttt{B}$ |
| $\texttt{Self.[P]A.[Q]B}$ | $[\texttt{P}\vert\texttt{A}]\cdot[\texttt{Q}\vert\texttt{B}]$ |

**算法（Build term for associated requirement）.** 输入一个 type parameter $\texttt{T}$ 与一个 protocol declaration $\texttt{P}$，输出一个（非空的）mutable term。

1. （Initialize）令 $t$ 为一个新的空 mutable term。
2. （Base case）若 $\texttt{T}$ 是 protocol 的 `Self` 类型（即 $\tau_{0,0}$），考察目前为止构造出的 term $t$：
   1. 若 $t$ 以一个 associated type symbol $[\texttt{Q}\vert\texttt{A}]$ 结尾，那么要么 $\texttt{Q}$ 与 $\texttt{P}$ 恒同，要么 $\texttt{P}$ 继承自 $\texttt{Q}$。两种情形下都**替换** $t$ 的最后一个 symbol 为 $[\texttt{P}\vert\texttt{A}]$。
   2. 否则，要么 $t$ 为空，要么它以一个 name symbol 结尾。把 protocol symbol $[\texttt{P}]$ 添到 $t$ 上。

   最后反转 $t$ 里的 symbol 顺序，返回 $t$。
3. （Recursive case）否则 $\texttt{T}$ 是一个 dependent member type。
   1. 若 $\texttt{T}$ 是一个 unbound dependent member type `U.A`，把 name symbol $\texttt{A}$ 添到 $t$ 上。
   2. 否则 $\texttt{T}$ 是一个 bound dependent member type `U.[Q]A`。把 associated type symbol $[\texttt{Q}\vert\texttt{A}]$ 添到 $t$ 上。

   置 $\texttt{T} \leftarrow \texttt{U}$，回到第 2 步。

**例.** 回忆 `generic-signatures.tex` 里那个 **AssocBind** 的例子，注意 Build term for associated requirement 算法在 protocol 继承与「重新声明的 associated type」面前是怎么表现的：

```swift
protocol Root {
  associatedtype Element
}

protocol Left: Root {}

protocol Right: Root {
  associatedtype Element
}
```

经由 **AssocBind** inference rule，type parameter `Self.Element` 与 `Self.[Root]Element` 在 $G_\texttt{Root}$、$G_\texttt{Left}$、$G_\texttt{Right}$ 三者中都等价。在 $G_\texttt{Right}$ 里，这个等价类还包含 `Self.[Right]Element`，因为 `Right` 重新声明了这个 associated type。

这些 type parameter 在三台 protocol machine 里分别映射成这些 term：

$$\begin{gathered}
\mathsf{term}_\texttt{Root}(\texttt{Self.Element}) = [\texttt{Root}]\cdot\texttt{Element}\\
\mathsf{term}_\texttt{Root}(\texttt{Self.[Root]Element}) = [\texttt{Root}\vert\texttt{Element}]\\[1ex]
\mathsf{term}_\texttt{Left}(\texttt{Self.Element}) = [\texttt{Left}]\cdot\texttt{Element}\\
\mathsf{term}_\texttt{Left}(\texttt{Self.[Root]Element}) = [\texttt{Left}\vert\texttt{Element}]\\[1ex]
\mathsf{term}_\texttt{Right}(\texttt{Self.Element}) = [\texttt{Right}]\cdot\texttt{Element}\\
\mathsf{term}_\texttt{Right}(\texttt{Self.[Root]Element}) = [\texttt{Right}\vert\texttt{Element}]\\
\mathsf{term}_\texttt{Right}(\texttt{Self.[Right]Element}) = [\texttt{Right}\vert\texttt{Element}]
\end{gathered}$$

### Reduction order.

上一节我们在 symbol 上定义了一个 partial order。现在把它扩展成 term 上的 partial order。回忆 `monoids.tex` 的 The Normal Form Algorithm 一节里关于 reduction order 的讨论。

我们从 `monoids.tex` 的标准 shortlex order 算法出发，但额外加一道检查，保证含 name symbol 的 term 永远排在不含 name symbol 的 term 之后——即便含 name symbol 的那个更短。这是 **weighted shortlex order** 的一个实例，我们选取的权重函数数的是一个 term 里出现的 name symbol 个数。本章 Protocol Type Aliases 一节会说明：要在 protocol type alias 上得到正确行为，weighted shortlex order 是必需的。

**定义.** 设 $A$ 是任意集合。若 $w\colon A^*\rightarrow\mathbb{N}$ 对一切 $x$、$y\in A^*$ 满足 $w(xy)=w(x)+w(y)$，我们就称 $w$ 是一个 **weight function**。也就是说，$w$ 是从 $A^*$ 到 $\mathbb{N}$ 的一个 monoid homomorphism，其中后者被看作加法下的 monoid。

**算法（Weighted shortlex order）.** 输入两个 term $t$ 与 $u$，输出「$<$」「$>$」「$=$」或「$\bot$」。

1. （Weight）计算 $w(t)$ 与 $w(u)$。
2. （Less）若 $w(t)<w(u)$，返回「$<$」。
3. （More）若 $w(t)>w(u)$，返回「$>$」。
4. （Shortlex）否则 $w(t)=w(u)$，于是用 `monoids.tex` 的 shortlex order 算法比较这两个 term，返回其结果。

weighted shortlex order 是 `monoids.tex` 里 reduction order 定义意义下的一个合格 reduction order。

**命题.** 设 $w\colon A^*\rightarrow\mathbb{N}$ 是一个 weight function。那么由 $w$ 诱导的 weighted shortlex order 是 translation-invariant 且 well-founded 的。

**证明.** 设 $<$ 是 $A^*$ 上的标准 shortlex order，$<_w$ 是由 $w$ 诱导的 weighted shortlex order。

先证 translation invariance。给定 $x$、$y$、$z\in A^*$ 且 $x<_w y$。我们要证 $zx<_w zy$；$xz<_w yz$ 的证法类似。由 $x<_w y$ 及定义，要么 $w(x)<w(y)$，要么 $w(x)=w(y)$ 且 $x<y$。逐一考察：

1. 若 $w(x)<w(y)$，则由 $\mathbb{N}$ 上的线性序是 translation-invariant 可得 $w(z)+w(x)<w(z)+w(y)$；又因 $w(zx)=w(z)+w(x)$、$w(zy)=w(z)+w(y)$，故 $w(zx)<w(zy)$，因此 $zx <_w zy$。
2. 若 $w(x)=w(y)$ 且 $x<y$，则 $w(zx)=w(zy)$，而 $A^*$ 上 $<$ 的 translation invariance 蕴含 $zx<zy$。同样得出 $zx <_w zy$。

接着用反证法证明 $<_w$ 是 well-founded 的。假设存在一条无穷下降链：

$$t_1 >_w t_2 >_w t_3 >_w \cdots$$

把权重函数 $w$ 作用到链中每个 term $t_i$ 上，得到：

$$w(t_1) \geq w(t_2) \geq w(t_3) \geq \cdots$$

由于 $w(t_i)\in\mathbb{N}$，我们只能「往下掉」有限多次。于是存在某个下标 $i$，使得对一切 $j>i$ 有 $w(t_j)=w(t_i)$。结合 $t_j <_w t_i$，可知实际上 $t_j < t_i$。于是我们得到了**标准** shortlex order $<$ 的一条无穷下降链：

$$t_i > t_{i+1} > t_{i+2} > \cdots$$

但这矛盾，因为标准 shortlex order $<$ 是 well-founded 的。所以 $<_w$ 也必定是 well-founded 的。

此后我们不再用 $<_w$ 这个记号。term 上的 reduction order 一律记作 $<$，并约定它指的就是 Weighted shortlex order 算法给出的那个序。

## Rules

现在我们描述一对实现「$\mathsf{rule}$」与「$\mathsf{rule}_\texttt{P}$」映射的算法。先从「$\mathsf{rule}$」开始，它定义 **query machine** 或 **minimization machine** 的 local rule。我们可以假定输入的 requirement 已经 desugar 过了（见 `building-generic-signatures.tex` 的 Decomposition and Desugaring 一节），所以左端总是一个 type parameter。我们用 Build term for explicit requirement 算法（记作「$\mathsf{term}$」）把 type parameter 翻译成 term。

我们的核心模型只支持 conformance requirement 以及 type parameter 之间的 same-type requirement。我们看到，一条 conformance requirement $[\texttt{T: P}]$ 被翻译成一条 rewrite rule $\mathsf{term}(\texttt{T})\cdot[\texttt{P}]\sim\mathsf{term}(\texttt{T})$。现在我们把它看作 **property rule** 的一个特例——所谓 property rule，就是形如 $\mathsf{term}(\texttt{T})\cdot s\sim\mathsf{term}(\texttt{T})$ 的 rewrite rule，其中 $s$ 是一个 symbol。在完整模型里，其余几类 requirement 也翻译成 property rule，而 type parameter 之间的 same-type requirement 本质上仍自成一类：

| | **Property rule：** $\mathsf{term}(\texttt{T})\cdot s\sim\mathsf{term}(\texttt{T})$ | |
|---|---|---|
| $\mathsf{rule}\ [\texttt{T: P}]$ | $s=[\texttt{P}]$ | protocol symbol |
| $\mathsf{rule}\ [\texttt{T: AnyObject}]$ | $s=[\mathsf{layout}\colon\texttt{AnyObject}]$ | layout symbol |
| $\mathsf{rule}\ [\texttt{T: C}]$ | $s=[\mathsf{superclass}\colon \texttt{C};\, \ldots]$ | superclass symbol |
| $\mathsf{rule}\ [\texttt{T == X}]$ | $s=[\mathsf{concrete}\colon \texttt{X};\, \ldots]$ | concrete type symbol |
| | **Same-type rule：** | |
| $\mathsf{rule}\ [\texttt{T == U}]$ | $\mathsf{term}(\texttt{T})\sim\mathsf{term}(\texttt{U})$ | |

**算法（Build rule from explicit requirement）.** 输入一条 desugar 过的 requirement，输出一对 term。

1. 对一条 **conformance requirement** $[\texttt{T: P}]$，返回 $(\mathsf{term}(\texttt{T})\cdot s,\,\mathsf{term}(\texttt{T}))$，其中 $s$ 是 protocol symbol $[\texttt{P}]$。
2. 对一条 **layout requirement** $[\texttt{T: AnyObject}]$，返回 $(\mathsf{term}(\texttt{T})\cdot s,\,\mathsf{term}(\texttt{T}))$，其中 $s$ 是 layout symbol $[\mathsf{layout}\colon\texttt{AnyObject}]$。
3. 对一条 **superclass requirement** $[\texttt{T: C}]$，返回 $(\mathsf{term}(\texttt{T})\cdot s,\,\mathsf{term}(\texttt{T}))$，其中 $s$ 是把 Build concrete type symbol 算法作用到 $\texttt{C}$ 上得到的 superclass symbol。
4. 对一条 $\texttt{X}$ 为 **concrete type** 的 **same-type requirement** $[\texttt{T == X}]$，返回 $(\mathsf{term}(\texttt{T})\cdot s,\,\mathsf{term}(\texttt{T}))$，其中 $s$ 是把 Build concrete type symbol 算法作用到 $\texttt{X}$ 上得到的 concrete type symbol。
5. 对一条 $\texttt{U}$ 为 **type parameter** 的 **same-type requirement** $[\texttt{T == U}]$，返回 $(\mathsf{term}(\texttt{T}),\,\mathsf{term}(\texttt{U}))$。

### Associated requirements.

在 **protocol machine** 或 **protocol minimization machine** 里，我们以类似的方式从 associated requirement 得到 local rule，只不过这次把 type parameter 翻成 term 用的是 Build term for associated requirement 算法（记作「$\mathsf{term}_\texttt{P}$」）。

| | **Property rule：** $\mathsf{term}_\texttt{P}(\texttt{Self.U})\cdot s\sim\mathsf{term}_\texttt{P}(\texttt{Self.U})$ | |
|---|---|---|
| $\mathsf{rule}_\texttt{P}\ [\texttt{Self.U: Q}]_\texttt{P}$ | $s = [\texttt{Q}]$ | protocol symbol |
| $\mathsf{rule}_\texttt{P}\ [\texttt{Self.U: AnyObject}]_\texttt{P}$ | $s = [\mathsf{layout}\colon\texttt{AnyObject}]$ | layout symbol |
| $\mathsf{rule}_\texttt{P}\ [\texttt{Self.U: C}]_\texttt{P}$ | $s = [\mathsf{superclass}\colon \texttt{C};\,\ldots]$ | superclass symbol |
| $\mathsf{rule}_\texttt{P}\ [\texttt{Self.U == X}]_\texttt{P}$ | $s = [\mathsf{concrete}\colon \texttt{X};\,\ldots]$ | concrete type symbol |
| | **Same-type rule：** | |
| $\mathsf{rule}_\texttt{P}\ [\texttt{Self.U == Self.V}]_\texttt{P}$ | $\mathsf{term}_\texttt{P}(\texttt{Self.U})\sim\mathsf{term}_\texttt{P}(\texttt{Self.V})$ | |

**算法（Build rule from associated requirement）.** 输入一条 desugar 过的 requirement 与一个 protocol declaration $\texttt{P}$，输出一对 term。

1. 对一条 **associated conformance requirement** $[\texttt{Self.U: Q}]_\texttt{P}$，返回 $(\mathsf{term}_\texttt{P}(\texttt{Self.U})\cdot s,\,\mathsf{term}_\texttt{P}(\texttt{Self.U}))$，其中 $s$ 是 protocol symbol $[\texttt{P}]$。
2. 对一条 **associated layout requirement** $[\texttt{Self.U: AnyObject}]_\texttt{P}$，返回 $(\mathsf{term}_\texttt{P}(\texttt{Self.U})\cdot s,\,\mathsf{term}_\texttt{P}(\texttt{Self.U}))$，其中 $s$ 是 symbol $[\mathsf{layout}\colon\texttt{AnyObject}]$。
3. 对一条 **associated superclass requirement** $[\texttt{Self.U: C}]_\texttt{P}$，返回 $(\mathsf{term}_\texttt{P}(\texttt{Self.U})\cdot s,\,\mathsf{term}_\texttt{P}(\texttt{Self.U}))$，其中 $s$ 是把 Build concrete type symbol 算法作用到 $\texttt{C}$ 上得到的 superclass symbol。
4. 对一条 $\texttt{X}$ 为 **concrete type** 的 **associated same-type requirement** $[\texttt{Self.U == X}]_\texttt{P}$，返回 $(\mathsf{term}_\texttt{P}(\texttt{Self.U})\cdot s,\,\mathsf{term}_\texttt{P}(\texttt{Self.U}))$，其中 $s$ 是把 Build concrete type symbol 算法作用到 $\texttt{X}$ 上得到的 concrete type symbol。
5. 对一条 `Self.V` 为 **type parameter** 的 **associated same-type requirement** $[\texttt{Self.U == Self.V}]_\texttt{P}$，返回 $(\mathsf{term}_\texttt{P}(\texttt{Self.U}),\, \mathsf{term}_\texttt{P}(\texttt{Self.V}))$。

> 译注：原书此算法第 1 步说「其中 $s$ 是 protocol symbol $[\texttt{P}]$」，与紧邻其上那张表格里写的 $s = [\texttt{Q}]$ 矛盾（requirement 是 $[\texttt{Self.U: Q}]_\texttt{P}$，说的是 `Self.U` 遵循 $\texttt{Q}$，所以追加的应当是 $[\texttt{Q}]$），疑为笔误，以表格为准。

### Additional rules.

protocol 还有几条不来自 requirement 的规则：

| | | |
|---|---|---|
| **Identity conformance rule** | | |
| `protocol P {...}` | | $[\texttt{P}]\cdot[\texttt{P}] \sim [\texttt{P}]$ |
| **Associated type rule** | | |
| `associatedtype A` | | $[\texttt{P}]\cdot\texttt{A} \sim [\texttt{P}\vert\texttt{A}]$ |
| **Protocol type alias rule** | | |
| `typealias A = Self.U` | | $[\texttt{P}]\cdot\texttt{A} \sim \mathsf{term}_\texttt{P}(\texttt{Self.U})$ |
| `typealias A = X` | | $[\texttt{P}]\cdot\texttt{A}\cdot[\mathsf{concrete}\colon \texttt{X};\, \ldots] \sim [\texttt{P}]\cdot\texttt{A}$ |

回忆一下：在核心模型里，一个没有任何 associated requirement 的 protocol 不给 monoid presentation 贡献任何 rewrite rule。在完整模型里我们看到，每个 protocol 至少要添一条 rewrite rule。

首先，**identity conformance rule** $[\texttt{P}]\cdot[\texttt{P}] \sim [\texttt{P}]$ 在概念上陈述的是：$\texttt{P}$ 的 protocol `Self` 类型遵循 $\texttt{P}$。它扮演的角色不大，大部分时候我们可以忽略它，但 `completion.tex` 里会有一个例子为它的存在正名。

其次，我们收集该 protocol 自己以及全部 inherited protocol 的 associated type declaration 的名字，对每个互不相同的名字 $\texttt{A}$，添一条 **associated type rule** $[\texttt{P}]\cdot\texttt{A} \sim [\texttt{P}\vert\texttt{A}]$。它陈述的是 $\mathsf{term}_\texttt{P}(\texttt{Self.A})$ 与 $\mathsf{term}_\texttt{P}(\texttt{Self.[P]A})$ 等价，所以这些规则把 derived requirements 形式系统里的 **AssocBind** inference rule 编码了进来。反复施加这些规则，我们就能把 bound type parameter 的 term 重写成 unbound type parameter 的 term，反之亦然。这一点在 `completion.tex` 的 Associated Types 与 Tietze Transformations 两节里还会多讲。

最后，对 protocol 里出现的每个 type alias declaration，我们添一条 **protocol type alias rule**。这让 protocol type alias 也能受 requirement 约束，是对核心模型的一项扩展。protocol type alias 留到下一节讨论。本节最后，我们演示一下 associated type rule 在实践中是怎么工作的。

**例.** 在核心模型里，`Sequence` 协议被它那两条 associated requirement 对应的 rewrite rule 完整描述了。在完整模型里，当我们从 unbound type parameter 过渡到 bound type parameter 时，这两条规则会改变形态，而且我们还会添几条额外的规则。

先看编译标准库自身时会发生什么。我们从源码类型检查这些 protocol declaration，所以必须依次构造 `IteratorProtocol` 与 `Sequence` 的 requirement signature——顺序是固定的，因为存在 protocol 依赖。

先看 `IteratorProtocol` 的 **protocol minimization machine**。这台机器有一条 identity conformance rule 和一条 associated type rule，它们在核心模型里都不存在：

- **(1)** $[\texttt{IteratorProtocol}]\cdot[\texttt{IteratorProtocol}] \sim [\texttt{IteratorProtocol}]$
- **(2)** $[\texttt{IteratorProtocol}]\cdot\texttt{Element} \sim [\texttt{IteratorProtocol}\vert\texttt{Element}]$

接着构造 `Sequence` 的 protocol minimization machine。我们从 `IteratorProtocol` 那里导入这两条规则，再为 `Sequence` 添一条 identity conformance rule，以及为它的两个 associated type 各添一条 associated type rule：

- **(3)** $[\texttt{Sequence}]\cdot[\texttt{Sequence}] \sim [\texttt{Sequence}]$
- **(4)** $[\texttt{Sequence}]\cdot\texttt{Element} \sim [\texttt{Sequence}\vert\texttt{Element}]$
- **(5)** $[\texttt{Sequence}]\cdot\texttt{Iterator} \sim [\texttt{Sequence}\vert\texttt{Iterator}]$

最后我们解析写在 `Sequence` 协议内部的那些 associated requirement。得到两条用 unbound type parameter 写成的 requirement：

$$\begin{gathered}
[\texttt{Self.Iterator: IteratorProtocol}]_\texttt{Sequence}\\
[\texttt{Self.Element} == \texttt{Self.Iterator.Element}]_\texttt{Sequence}
\end{gathered}$$

施加「$\mathsf{rule}_\texttt{P}$」，得到的正是核心模型里那两条 rewrite rule：

- **(6)** $[\texttt{Sequence}]\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}] \sim [\texttt{Sequence}]\cdot\texttt{Iterator}$
- **(7)** $[\texttt{Sequence}]\cdot\texttt{Element} \sim [\texttt{Sequence}]\cdot\texttt{Iterator}\cdot\texttt{Element}$

总共七条 local rule。下一步是 completion，`completion.tex` 会描述它；眼下重要的事实是：我们会把规则 (6) 和 (7) 变换成另一种形态。新规则里含的是 associated type symbol，而不是 protocol symbol 加 name symbol：

- **(◇6)** $[\texttt{Sequence}\vert\texttt{Iterator}]\cdot[\texttt{IteratorProtocol}] \sim [\texttt{Sequence}\vert\texttt{Iterator}]$
- **(◇7)** $[\texttt{Sequence}\vert\texttt{Element}] \sim [\texttt{Sequence}\vert\texttt{Iterator}]\cdot[\texttt{IteratorProtocol}\vert\texttt{Element}]$

考察规则 (1) 到 (7) 可以看出，把 (6) 和 (7) 换成 (◇6) 和 (◇7) 并不改变 term 等价关系。事实上，一旦有了 (5) 和 (6)，(◇6) 的两端就已经经由这条 rewrite path 等价了：

$$\begin{gathered}
([\texttt{Sequence}\vert\texttt{Iterator}] \Rightarrow [\texttt{Sequence}]\cdot\texttt{Iterator}) \triangleright [\texttt{IteratorProtocol}]\\
{}\circ\ ([\texttt{Sequence}]\cdot\texttt{Iterator}\cdot[\texttt{IteratorProtocol}] \Rightarrow [\texttt{Sequence}]\cdot\texttt{Iterator})\\
{}\circ\ ([\texttt{Sequence}\vert\texttt{Iterator}] \Rightarrow [\texttt{Sequence}]\cdot\texttt{Iterator})
\end{gathered}$$

反过来，这是一条用 (5) 和 (◇6) 得到 (6) 的 rewrite path：

$$\begin{gathered}
([\texttt{Sequence}]\cdot\texttt{Iterator} \Rightarrow [\texttt{Sequence}\vert\texttt{Iterator}]) \triangleright [\texttt{IteratorProtocol}]\\
{}\circ\ ([\texttt{Sequence}\vert\texttt{Iterator}]\cdot[\texttt{IteratorProtocol}] \Rightarrow [\texttt{Sequence}\vert\texttt{Iterator}])\\
{}\circ\ ([\texttt{Sequence}\vert\texttt{Iterator}] \Rightarrow [\texttt{Sequence}]\cdot\texttt{Iterator})
\end{gathered}$$

类似地，可以证明规则 (7) 与 (◇7) 之间也能经由一对 rewrite path 互换。现在请注意：若我们把「$\mathsf{rule}_\texttt{P}$」施加到下面这对用 bound dependent member type 写成的 requirement 上，得到的正是规则 (◇6) 与 (◇7)：

$$\begin{gathered}
[\texttt{Self.[Sequence]Iterator: IteratorProtocol}]_\texttt{Sequence}\\
[\texttt{Self.[Sequence]Element ==}\\
\qquad\texttt{Self.[Sequence]Iterator.[IteratorProtocol]Element}]_\texttt{Sequence}
\end{gathered}$$

在 rule minimization 过程的末尾，我们把规则 (◇6) 与 (◇7) 翻译回 requirement，得到的恰好就是上面这两条（这个反向翻译见 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 的 Building Requirements 一节）。这就给出了 `Sequence` 的 requirement signature。我们把这份表示序列化进标准库的 binary module 里。

**例.** 现在假设用户的程序写了一条指向 `Sequence` 的 conformance requirement。我们为 `IteratorProtocol` 与 `Sequence` 各构造一台 **protocol machine**，从先前为标准库构造的 binary module 里反序列化出它们的 requirement signature。`IteratorProtocol` 的 protocol machine 和前面一样，由规则 (1) 与 (2) 构成。

`Sequence` 的 protocol machine 则由规则 (1) 到 (5) 连同 (◇6) 与 (◇7) 构成——因为一个 requirement signature 里序列化的 associated requirement 总是用 bound type parameter 写的。

**例.** 最后，我们在完整模型下重访本章开头那个 generic signature。假设用户的程序写了这个声明：

```swift
func allEqual<T: Sequence, U: Sequence>(_ t: T, _ u: U)
    where T.Element: Equatable,
          T.Element == U.Element {...}
```

我们构造一台 **minimization machine** 来构建这个声明的 generic signature。先从 `IteratorProtocol`、`Sequence` 和 `Equatable` 三台 protocol machine 那里导入规则（`Equatable` 没有 associated type，所以它只贡献一条规则）：

- **(1)** $[\texttt{IteratorProtocol}]\cdot[\texttt{IteratorProtocol}] \sim [\texttt{IteratorProtocol}]$
- **(2)** $[\texttt{IteratorProtocol}]\cdot\texttt{Element} \sim [\texttt{IteratorProtocol}\vert\texttt{Element}]$
- **(3)** $[\texttt{Sequence}]\cdot[\texttt{Sequence}] \sim [\texttt{Sequence}]$
- **(4)** $[\texttt{Sequence}]\cdot\texttt{Element} \sim [\texttt{Sequence}\vert\texttt{Element}]$
- **(5)** $[\texttt{Sequence}]\cdot\texttt{Iterator} \sim [\texttt{Sequence}\vert\texttt{Iterator}]$
- **(◇6)** $[\texttt{Sequence}\vert\texttt{Iterator}]\cdot[\texttt{IteratorProtocol}] \sim [\texttt{Sequence}\vert\texttt{Iterator}]$
- **(◇7)** $[\texttt{Sequence}\vert\texttt{Element}] \sim [\texttt{Sequence}\vert\texttt{Iterator}]\cdot[\texttt{IteratorProtocol}\vert\texttt{Element}]$
- **(8)** $[\texttt{Equatable}]\cdot[\texttt{Equatable}] \sim [\texttt{Equatable}]$

我们解析 `allEqual()` 里用户写下的 requirement，对每条施加 Build rule from explicit requirement 算法，再得到四条规则：

- **(9)** $\tau_{0,0}\cdot[\texttt{Sequence}] \sim \tau_{0,0}$
- **(10)** $\tau_{0,1}\cdot[\texttt{Sequence}] \sim \tau_{0,1}$
- **(11)** $\tau_{0,0}\cdot\texttt{Element}\cdot[\texttt{Equatable}] \sim \tau_{0,0}\cdot\texttt{Element}$
- **(12)** $\tau_{0,0}\cdot\texttt{Element} \sim \tau_{0,1}\cdot\texttt{Element}$

同样，associated type rule 让我们能把 (11) 与 (12) 转成含 associated type symbol 的新形态。首先注意，经由下面这条用了规则 (4) 与 (9) 的 rewrite path，$\tau_{0,0}\cdot[\texttt{Sequence}\vert\texttt{Element}]$ 与 $\tau_{0,0}\cdot\texttt{Element}$ 等价：

$$\begin{gathered}
\tau_{0,0} \triangleleft ([\texttt{Sequence}\vert\texttt{Element}] \Rightarrow [\texttt{Sequence}]\cdot\texttt{Element})\\
{}\circ\ (\tau_{0,0}\cdot[\texttt{Sequence}] \Rightarrow \tau_{0,0}) \triangleright \texttt{Element}
\end{gathered}$$

这条 rewrite path 的起点与终点，也可以写成把「$\mathsf{term}$」作用到两个 type parameter $\tau_{0,0}\texttt{.[Sequence]Element}$ 与 $\tau_{0,0}\texttt{.Element}$ 上的结果，所以从某种意义上说，这条 rewrite path 与下面这份 derived requirement 是对应的：

$$\begin{gathered}
1.\ [\tau_{0,0}\texttt{: Sequence}] \qquad (\textsf{Conf})\\
2.\ [\tau_{0,0}\texttt{.[Sequence]Element} == \tau_{0,0}\texttt{.Element}] \qquad (\textsf{AssocBind}\ 1)
\end{gathered}$$

类似地，经由一条用了规则 (4) 与 (10) 的 rewrite path，我们有 term 等价 $\tau_{0,1}\cdot[\texttt{Sequence}\vert\texttt{Element}] \sim \tau_{0,1}\cdot\texttt{Element}$。正因如此，completion 与 rule minimization 会把规则 (11) 与 (12) 换成下面的 (◇11) 与 (◇12)：

- **(◇11)** $\tau_{0,0}\cdot[\texttt{Sequence}\vert\texttt{Element}]\cdot[\texttt{Equatable}] \sim \tau_{0,0}\cdot[\texttt{Sequence}\vert\texttt{Element}]$
- **(◇12)** $\tau_{0,0}\cdot[\texttt{Sequence}\vert\texttt{Element}] \sim \tau_{0,1}\cdot[\texttt{Sequence}\vert\texttt{Element}]$

规则 (1) 到 (10) 连同 (11) 与 (12)，与规则 (1) 到 (10) 连同 (◇11) 与 (◇12)，生成同一个 term 等价关系。

下面是作为输入的、与 (11) 和 (12) 对应的那两条 requirement：

$$\begin{gathered}
[\tau_{0,0}\texttt{.Element: Equatable}]\\
[\tau_{0,0}\texttt{.Element} == \tau_{0,1}\texttt{.Element}]
\end{gathered}$$

下面是 minimization 结束时我们拿到的、与 (◇11) 和 (◇12) 对应的那两条 requirement：

$$\begin{gathered}
[\tau_{0,0}\texttt{.[Sequence]Element: Equatable}]\\
[\tau_{0,0}\texttt{.[Sequence]Element} == \tau_{0,1}\texttt{.[Sequence]Element}]
\end{gathered}$$

按 `building-generic-signatures.tex` 里那条关于等价 generic signature 的命题，用户写下的 requirement 与 minimization 输出的 reduced requirement 生成同一套 theory。我们输出最终的 generic signature：

```
<τ_0_0, τ_0_1 where τ_0_0: Sequence, τ_0_1: Sequence,
                    τ_0_0.[Sequence]Element: Equatable,
                    τ_0_0.[Sequence]Element ==
                        τ_0_1.[Sequence]Element>
```

如果之后我们要为这个 generic signature 构造一台 **query machine**——可能是在另一次编译会话里，为某个 import 了本模块的模块——我们只需对该 generic signature 里的每条 requirement 施加「$\mathsf{rule}$」，立刻就能得到规则 (1) 到 (10) 连同 (◇11) 与 (◇12)。

> 译注：上面这份「序列化进 binary module 的 requirement signature」，正是本库在二进制里读到的东西。protocol descriptor 后面挂着的那串 requirement，形状与顺序都已经是这里 minimization 的产物；本库把它们按槽位投影成 protocol witness table 的形状时，消费的就是这份既成结果，而不会自己再跑一遍 completion。见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

## Protocol Type Aliases

回忆一下：protocol type alias 与 associated type declaration 并列，作为 type parameter 的 member type 出现（见 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)）（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)）的 Member Type Representations 一节）。若一个 type parameter $\texttt{T}$ 遵循某个声明了 type alias $\texttt{A}$ 的 protocol $\texttt{P}$，用户就可以写出 member type representation `T.A`。

在 interface resolution 阶段，我们手上已经有了 generic signature，可以对 type parameter $\texttt{T}$ 发起 generic signature query 来找到 `A` 的声明，然后把 $\texttt{A}$ 的 underlying type 里的 `Self` 替换成 $\texttt{T}$。但 protocol type alias 也可能出现在 `where` 子句的 requirement 里，而这些是在 structural resolution 阶段解析的——那时我们**正在**构建当前上下文的 generic signature。

这种情况下，type resolution 对 $\texttt{T}$ 还一无所知，所以解析出来的类型总是一个 unbound dependent member type `T.A`。因此，在一个用了 protocol type alias 的源程序里，一个 unbound dependent member type 可能指向一个 **type alias** declaration，而不只是 associated type declaration。这给出了一种 derived requirements 形式系统覆盖不到的新行为。因此，我们在这里只描述它在 rewrite rule 层面是怎么实现的。

protocol $\texttt{P}$ 里的每个 protocol type alias $\texttt{A}$，在 $\texttt{P}$ 的 protocol machine 里定义出一条 **protocol type alias rule**，方式如下。我们设想出一条 associated same-type requirement，把左端的 unbound dependent member type `Self.A` 与右端 $\texttt{A}$ 的 underlying type 等同起来。那么 $\texttt{A}$ 的 protocol type alias rule，恰好就是我们把「$\mathsf{rule}_\texttt{P}$」施加到这条想象出来的 requirement 上会得到的那条规则。

**算法（Build rule for protocol type alias）.** 输入一个 protocol $\texttt{P}$ 和一个 type alias declaration $\texttt{A}$（约定 $\texttt{A}$ 是 $\texttt{P}$ 的成员），输出一对 term $(u,\,v)$。

1. 取得 $\texttt{A}$ 的 underlying type。怎么取取决于 requirement machine 的种类：
   - 若这是一台 **protocol minimization machine**，那么该 protocol 声明在主模块里。在 structural resolution 阶段解析这个 underlying type 的 type representation。
   - 若这是一台 **protocol machine**，我们已经有了该 protocol 的 requirement signature。直接在 requirement signature 里查 $\texttt{A}$ 的 underlying type。
2. 若 $\texttt{A}$ 的 underlying type 是某个 concrete type $\texttt{X}$，用 Build concrete type symbol 算法构造一个 concrete type symbol，并返回下面这对代表一条 property rule 的 term：

   $$([\texttt{P}] \cdot \texttt{A} \cdot [\mathsf{concrete}\colon \texttt{X};\,\ldots],\, [\texttt{P}] \cdot \texttt{A})$$
3. 若 $\texttt{A}$ 的 underlying type 是另外某个 type parameter $\texttt{Self.U}$，用 Build term for associated requirement 算法把它翻译成 term，并返回下面这对代表一条 same-type rule 的 term：

   $$([\texttt{P}] \cdot \texttt{A},\, \mathsf{term}_\texttt{P}(\texttt{Self.U}))$$

**例.** 下面这个 `Graph` 协议声明了两个 type alias：

```swift
protocol Pair {
  associatedtype Elt
}

protocol Graph {
  associatedtype Edge: Pair, Hashable

  typealias Vertex  = Self.Edge.Elt   // Type parameter
  typealias EdgeSet = Set<Self.Edge>  // Concrete type
}
```

我们会用到这个事实：`Graph` 的 **protocol minimization machine** 里含有 `Elt` 与 `Edge` 的 associated type rule，以及 associated conformance requirement $[\texttt{Self.Edge: Pair}]_\texttt{Graph}$ 对应的规则：

- **(1)** $[\texttt{Pair}]\cdot\texttt{Elt} \sim [\texttt{Pair}\vert\texttt{Elt}]$
- **(2)** $[\texttt{Graph}]\cdot\texttt{Edge} \sim [\texttt{Graph}\vert\texttt{Edge}]$
- **(3)** $[\texttt{Graph}]\cdot\texttt{Edge}\cdot[\texttt{Pair}] \sim [\texttt{Graph}]\cdot\texttt{Edge}$

要得到 `Vertex` 与 `EdgeSet` 的 protocol type alias rule，我们先解析它们的 underlying type，并为各自写下那条想象出来的 associated same-type requirement：

$$\begin{gathered}
[\texttt{Self.Vertex} == \texttt{Self.Edge.Elt}]_\texttt{Graph}\\
[\texttt{Self.EdgeSet} == \texttt{Array<Self.Edge>}]_\texttt{Graph}
\end{gathered}$$

> 译注：原书此处写作 `Array<Self.Edge>`，与上面代码里的 `typealias EdgeSet = Set<Self.Edge>` 以及紧接着的规则 (5) 里的 $[\mathsf{concrete}\colon\texttt{Set<}\tau_{0,0}\texttt{>};\ldots]$ 都矛盾，疑为笔误，以 `Set` 为准。

把这两条 requirement 翻译成 rewrite rule，可以看到 `Vertex` 得到一条 same-type rule，而 `EdgeSet` 得到一条 property rule：

- **(4)** $[\texttt{Graph}] \cdot \texttt{Vertex} \sim [\texttt{Graph}] \cdot \texttt{Edge} \cdot \texttt{Elt}$
- **(5)** $[\texttt{Graph}] \cdot \texttt{EdgeSet} \cdot [\mathsf{concrete}\colon \texttt{Set<}\tau_{0,0}\texttt{>};\, [\texttt{Graph}]\cdot\texttt{Edge}] \sim [\texttt{Graph}] \cdot \texttt{EdgeSet}$

接下来看看规则 (4) 会经历什么。completion 用 (2) 化简规则 (3)，把它换成 (◇3)：

- **(◇3)** $[\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}] \sim [\texttt{Graph}\vert\texttt{Edge}]$

规则 (4) 的左端是 term $[\texttt{Graph}] \cdot \texttt{Edge} \cdot \texttt{Elt}$。经由下面这条用了规则 (1)、(2) 和 (◇3) 的 rewrite path，这个 term 与 $[\texttt{Graph}\vert\texttt{Edge}] \cdot [\texttt{Pair}\vert\texttt{Elt}]$ 等价：

$$\begin{gathered}
([\texttt{Graph}] \cdot \texttt{Edge} \Rightarrow [\texttt{Graph}\vert\texttt{Edge}]) \triangleright \texttt{Elt}\\
{}\circ\ ([\texttt{Graph}\vert\texttt{Edge}] \Rightarrow [\texttt{Graph}\vert\texttt{Edge}] \cdot [\texttt{Pair}]) \triangleright \texttt{Elt}\\
{}\circ\ [\texttt{Graph}\vert\texttt{Edge}] \triangleleft ([\texttt{Pair}] \cdot \texttt{Elt} \Rightarrow [\texttt{Pair}\vert\texttt{Elt}])
\end{gathered}$$

completion 发现这个事实，并据此化简规则 (4)，把它换成 (◇4)：

- **(◇4)** $[\texttt{Graph}] \cdot \texttt{Vertex} \sim [\texttt{Graph}\vert\texttt{Edge}] \cdot [\texttt{Pair}\vert\texttt{Elt}]$

name symbol `Vertex` 留在了左端，消不掉。右端翻译回去，是 bound type parameter `Self.[Graph]Edge.[Pair]Elt`。这就成了我们作为该 protocol 的 requirement signature 的一部分序列化下来的 underlying type。若之后要为 `Graph` 构造一台 protocol machine，我们会直接拿到 rewrite rule (◇4)，而不是 (4)。

**例.** 现在我们可以写一个 `where` 子句里引用了 type alias `Vertex` 的声明：

```swift
func walk<E, G: Graph>(_: G, _: (G.Vertex) -> E)
    where G.Vertex: Equatable {}
```

derived requirements 形式系统解释不了 protocol type alias，而 conformance requirement $[\tau_{0,1}\texttt{.Vertex: Equatable}]$ 的 subject type 并不是那套理论的推论——根本没有叫 `Vertex` 的 associated type。但在实现里我们会看到，得到的 generic signature 与把这条 requirement 写成 $[\tau_{0,1}\texttt{.Edge.Elt: Equatable}]$ 时完全一样：

```swift
func walk<E, G: Graph>(_: G, _: (G.Vertex) -> E)
    where G.Edge.Elt: Equatable {}
```

`walk()` 的 minimization machine 从 `Graph` 的 protocol machine 导入规则，其中包括 (◇4)。我们再解析 `walk()` 的 requirement，添两条 local rule：

- **(6)** $\tau_{0,1}\cdot[\texttt{Graph}] \sim \tau_{0,1}$
- **(7)** $\tau_{0,1}\cdot\texttt{Vertex}\cdot[\texttt{Equatable}] \sim \tau_{0,1}\cdot\texttt{Vertex}$

注意 $\tau_{0,1}\cdot\texttt{Vertex}$ 与 $\tau_{0,1}\cdot[\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}\vert\texttt{Elt}]$ 等价：

$$\begin{gathered}
(\tau_{0,1} \Rightarrow \tau_{0,1}\cdot[\texttt{Graph}]) \triangleright \texttt{Vertex} \\
{}\circ\ \tau_{0,1} \triangleleft ([\texttt{Graph}] \cdot \texttt{Vertex} \Rightarrow [\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}\vert\texttt{Elt}])
\end{gathered}$$

这时 Weighted shortlex order 算法里那个 reduction order 就变得重要了。本质上，我们希望 normal form algorithm 在归约一个 term 时「尽可能多地」消掉 name symbol。这正是我们采用 weighted shortlex order 的理由——在比较长度**之前**先比较两个 term 里 name symbol 的个数；也就是：

$$\tau_{0,1}\cdot[\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}\vert\texttt{Elt}] < \tau_{0,1}\cdot\texttt{Vertex}$$

在我们这个例子里必须如此，因为 unbound type parameter $\tau_{0,1}\texttt{.Vertex}$ 比它等价类里任何 bound type parameter 都短。事实上，这里的 reduced type parameter 是 $\tau_{0,1}\texttt{.[Graph]Edge.[Pair]Elt}$。（在不描述 protocol type alias 的 derived requirements 形式系统里，这种事不可能发生——`building-generic-signatures.tex` 里那条关于 bound 与 unbound 等价的定理已经说明了这一点。）

说这么多是想讲清楚：completion 会化简规则 (7)，把它换成 (◇7)：

- **(◇7)** $\tau_{0,1}\cdot[\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}\vert\texttt{Elt}]\cdot[\texttt{Equatable}] \sim \tau_{0,1}\cdot[\texttt{Graph}\vert\texttt{Edge}]\cdot[\texttt{Pair}\vert\texttt{Elt}]$

我们把这条规则翻译成下面这条 conformance requirement，它会成为最终 generic signature 的一部分：

$$[\tau_{0,1}\texttt{.[Graph]Edge.[Pair]Elt: Equatable}]$$

**例.** `GenericSignatureBuilder` 会把 requirement 的处理与 name lookup 惰性地交织在一起，因此一个 `where` 子句可以毫无限制地引用声明在 protocol extension 里的 type alias。而 Requirement Machine 则是一次性地把一个 protocol 的全部 rewrite rule 收集齐。为了避免在收集 rewrite rule 时对所有 protocol extension 的所有成员做一次昂贵的遍历，今天只有**直接**声明在 protocol 内部的 type alias 才参与重写。

这意味着，protocol extension 里的 type alias 只有在 interface resolution 阶段解析某个 type representation 时才找得到。在 structural resolution 阶段，我们拿到的则是一个与任何东西都不等价的 unbound type parameter，因为没有任何 rewrite rule 能把它进一步归约。特别地，从一个 `where` 子句里引用这样的 type alias 是不合法的。

如果我们把前一个例子改成引用 protocol extension 里的 type alias，就会看到编译器报错：

```swift
extension Graph {
  typealias Bad = Self.Edge.Elt
}

func walk<G: Graph>(_: G) where G.Bad: Equatable {}
// error: `Bad' was defined in extension of protocol `Graph'
// and cannot be referenced from a `where' clause
```

我们诊断这个错误所用的机制，与拒绝那些不是 well-formed 的 requirement 时相同（见 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节）。回忆一下：一旦有了 generic signature，我们会回头重访 `where` 子句里的每个 type representation，在 interface resolution 阶段把它再解析一遍，以便诊断出非法的 type parameter。现在我们看到这里还要多检查一个条件——如果 type representation 确实解析成功了，但解析到的 type declaration 是一个 protocol extension 里的 type alias，我们就必须拒绝这个程序。

**例.** `GenericSignatureBuilder` 的另一处怪癖是：protocol type alias 可以出现在一条 conformance requirement 的**右端**。出于向后兼容，Requirement Machine 实现了这一行为的一个狭窄版本。

具体来说，若一个 protocol 声明了一个 underlying type 为 constraint type 的 protocol type alias `A`，我们允许 dependent member type `Self.A` 出现在 conformance requirement 的右端——无论写在该 protocol 自身还是它的 extension 里。更一般的 type parameter 则不可以。例如：

```swift
class Box {}

protocol Holder {
  typealias Wrapper = Box & Equatable
  associatedtype Contents: Self.Wrapper
}
```

我们在 requirement decomposition（见 `building-generic-signatures.tex` 的 Decomposition and Desugaring 一节）里处理这种情况。上面这段里，用户写下的 requirement 是 $[\texttt{Self.Contents: Self.Wrapper}]_\texttt{Holder}$。我们查出右端的 protocol type alias `Wrapper`，随后就当作用户写的是 `Box & Equatable` 来继续处理。它分解后给出 $[\texttt{Self.Contents: Box}]_\texttt{Holder}$ 与 $[\texttt{Self.Contents: Equatable}]_\texttt{Holder}$。

下面这个构造 protocol local rule 的算法把一切串了起来。

**算法（Build protocol rules）.** 输入一个 protocol declaration $\texttt{P}$，输出一列规则，每条表示成一对有序的 term。

1. 令 $R$ 为一列有序 term 对，初始为空。
2. 添加 identity conformance rule $[\texttt{P}]\cdot[\texttt{P}] \sim [\texttt{P}]$。
3. 对 $\texttt{P}$ 的每个 associated type $\texttt{A}$，添加 associated type rule $[\texttt{P}] \cdot \texttt{A} \sim [\texttt{P}\vert\texttt{A}]$。
4. 对 $\texttt{P}$ 所继承的每个 protocol $\texttt{Q}$（换句话说，满足 $G_\texttt{P}\vdash[\texttt{Self: Q}]$ 的那些 $\texttt{Q}$）的每个 associated type $\texttt{A}$，添加 associated type rule $[\texttt{P}] \cdot \texttt{A} \sim [\texttt{P}\vert\texttt{A}]$。
5. 对 $\texttt{P}$ 的每条 associated requirement，施加 Build rule from associated requirement 算法并把结果添进去。
6. 对声明在 $\texttt{P}$ 里的每个 type alias，施加 Build rule for protocol type alias 算法并把结果添进去。
7. 返回 $R$。

至此，四类 requirement machine 各自最初那份 rewrite rule 清单是怎么来的，我们已经完整交代过了。我们总是先用 `basic-operation.tex` 的 Import rules from protocol components 算法收集导入的规则。然后，要拿到 query machine 或 minimization machine 的 local rule，就对我们 generic signature 的每条 explicit requirement 施加 Build rule from explicit requirement 算法；要拿到 protocol machine 或 protocol minimization machine 的 local rule，就对该 component 里的每个 protocol 施加 Build protocol rules 算法。

### The rule array.

一台 requirement machine 把它的 rewrite rule 存在一个**数组**里。每条规则是一对 immutable term $(u,v)$。规则都是**定向**的，即在 reduction order 下 $u>v$，以保证 normal form algorithm 会停机。我们总是把新规则插在数组末尾，这样别的数据结构就能按下标引用规则。每条规则附带的标志位供 completion 与 minimization 使用：

- 若规则是一条 identity conformance rule 或 associated type rule，就置上 **permanent** 标志。permanent 规则不参与 rule minimization。
- 当一条规则被一条更简单的规则取代时，置上 **left-simplified**、**right-simplified** 或 **substitution-simplified** 标志（见 `completion.tex` 的 Rule Simplification 一节）。
- 若某条规则代表一条 conflicting 或 recursive 的 requirement，就在 property map 构造期间置上 **conflicting** 与 **recursive** 标志（见 `property-map.tex`）。
- **explicit** 标志置在由用户写下的 requirement 创建出来的那些初始规则上。rule minimization 还会以一种特定的方式把这个标志传播到其他规则上。explicit 规则在 minimal conformances 算法里有特殊行为（见 `minimization.tex` 的 Conformance Minimization 一节）。
- 若某条 rewrite rule 是其他非冗余规则的推论，rule minimization 就给它置上 **redundant** 标志。在 minimization 过程末尾由规则构建 requirement 时，我们只考虑那些没被标成 redundant 的规则（见 `minimization.tex`）。
- **frozen** 标志阻止其他任何标志被置上。导入的规则一律标成 frozen；local 规则则在 requirement machine 构造完成之后被标成 frozen。

一个标志一旦被置上就不能清除，而 frozen 标志会阻止任何新标志被置上。

## The Normal Form Algorithm

本节我们重访 `monoids.tex` 的 The Normal Form Algorithm 一节里那个 normal form algorithm。除别的用途外，我们可以用这个算法判定两个 type parameter 是否等价，这也就描述了 `areReducedTypeParametersEqual()` 这个 generic signature query 的实现。我们的目标是弥补那份规范里的两处不足：

1. 若原 term 里含有不止一个等于某条 rewrite rule 左端的 subterm，我们并没有规定该走哪一步 rewrite。
2. 若 rewrite rule 数量很大，把它们表示成一张对儿的列表是低效的，因为我们会不得不拿原 term 的每个 subterm 去和每条 rewrite rule 的左端比一遍。

关于第一点，我们知道 completion 给了我们一个 confluent 的归约关系，一个 term 的 normal form 与 rewrite step 怎么选无关。但从工程角度讲，我们仍然需要某种确定性的做法。我们的做法是：永远选左 whisker 最短的那一步 rewrite；换句话说，从左往右扫描原 term，重写**最左边**那个匹配上的 subterm（如果有的话），然后重复。至于第二点，我们必须高效地**找到**这些匹配的 subterm。我们借助一个辅助数据结构来做这件事。

### The rule trie.

一个 **trie** 表示一个从 key 到 value 的映射，其中 key 是字符串（也就是 free monoid 的元素）。lookup 操作会找出输入字符串中等于某个 key 的**最短前缀**，耗时与 key 的长度成线性关系。每台 requirement machine 都有自己的 **rule trie**，其 key 是各条 rewrite rule 的左端，value 是那些规则在数组里的下标。

具体地说，一个 trie 是一批**节点**的集合，组织成一棵树。每个节点代表一个唯一的字符串，它是 trie 里存的一个或多个 key 的前缀。对节点 $n$，我们把这个字符串记作 $\texttt{KEY}(n)$。若 $\texttt{KEY}(n)$ 是**完整的** key，则 $n$ 存着与该 key 关联的 value，记作 $\texttt{VALUE}(n)$。否则 $\texttt{VALUE}(n)$ 为 null。

空字符串 $\varepsilon$ 是每个字符串的前缀，所以一个非空的 trie 总有唯一一个节点 $r$ 满足 $\texttt{KEY}(r)=\varepsilon$。这就是 trie 的**根**。在我们的应用里，$\texttt{VALUE}(r)$ 恒为 null，因为一条 rewrite rule 的左端不可能为空。

最后，若节点 $m$ 与 $n$ 满足 $\texttt{KEY}(m)=\texttt{KEY}(n)\cdot s$（对某个 symbol $s$），我们就说 $m$ 是 $n$ 的**子节点**，即 $\texttt{CHILD}(n,s)=m$。每个节点存一张从 symbol 到子节点的哈希表，我们把它画成：父节点与每个子节点之间连一条边，边上标着对应的 symbol。事实上我们根本不需要在 $n$ 里存 $\texttt{KEY}(n)$；key 的集合已经隐含地编码在各个 $\texttt{CHILD}(n,s)$ 里了。

下面给出四条抽象的 rewrite rule（alphabet 为 $\{a,b,c,d\}$），以及按上面的描述得到的 trie：

$$\begin{array}{lr}
aa\sim a & (1)\\
acd\sim b & (2)\\
bc\sim b & (3)\\
bd\sim b & (4)
\end{array}$$

```
root
├── a ──→ ♡
│         ├── a ──→ (1)
│         └── c ──→ ♡
│                   └── d ──→ (2)
└── b ──→ ♡
          ├── c ──→ (3)
          └── d ──→ (4)
```

边上的标签是 symbol；`♡` 表示 `VALUE` 为 null 的节点（它的 `KEY` 只是某个 key 的真前缀），带括号数字的节点则存着对应规则在 rule array 里的下标。

> 译注：原书此处是一张 TikZ 图，这里用 ASCII 树转述；节点与边的标签照抄原文（原书用 $\heartsuit$ 标记无 value 的节点）。图的原貌见官方 PDF 对应章节。

要实现 trie 的 lookup 操作，我们从根出发，按照从左往右读 term 时看到的 symbol，沿着一连串边往下走。若走到某个带 value 的节点，就完成了。反过来，若走到了 term 的末尾，或者发现某个节点没有对应下一个 symbol 的子节点，那么 lookup 失败，不返回任何结果。另外，我们需要在**每个**位置上找匹配的 subterm，而不只是在 term 的开头，所以 lookup 还要接收一个「从第几个 symbol 开始查」的下标。

**算法（Lookup in rule trie）.** 输入一个 term $t$ 与一个偏移 $i$，满足 $0\leq i<|t|$。若存在满足 $|x|=i$ 的 term $x$ 与一条 rewrite rule $(u,v)$ 使得 $t=xuy$，则返回这条 $(u,v)$ 在 rule array 里的下标。否则返回 null。

1. （Initialize）令 $n$ 为根节点。
2. （End）若 $i=|t|$，说明已到 term 末尾。返回 null。
3. （Child）令 $m := \texttt{CHILD}(n,s_i)$，其中 $s_i$ 是 $t$ 的第 $i$ 个 symbol。若 $m$ 为 null，说明没有更多 key 可查。返回 null。
4. （Value）否则，若 $\texttt{VALUE}(m)$ 不为 null，返回 $\texttt{VALUE}(m)$。
5. （Advance）否则置 $n \leftarrow m$、$i \leftarrow i+1$，回到第 2 步。

举个例子，考虑 term $bacdc$ 与上面那张 trie。在位置 0 做 lookup 会失败：我们从根沿边 $b$ 走下去，然后发现这个子节点既不存 value，也没有对应 $a$ 的出边。反过来，在位置 1 做 lookup 会成功：我们依次沿标着 $a$、$c$、$d$ 的边走，抵达 value 为规则 (2) 的那个节点。于是，要实现 normal form algorithm，我们就在每个位置尝试这个 lookup，一旦匹配就施加那一步 rewrite，如此迭代直到不动点。

**算法（Normal form algorithm using rule trie）.** 输入一个 mutable term $t$。就地修改 $t$，并输出一条 positive rewrite path $p$，其中 $\operatorname{src}(p)$ 是原 term，$\operatorname{dst}(p)$ 是它的 normal form。

1. （Initialize）令 $p := 1_t$，令 $i := 0$。
2. （Check）若 $i=|t|$，则 term $t$ 现在是 irreducible 的。返回 $p$。
3. （Lookup）用 $t$ 与 $i$ 调用 Lookup in rule trie 算法。
4. （Rewrite）若找到了一条 rewrite rule $(u, v)$，使得 $t=xuy$ 且 $|x|=i$，那么置 $t\leftarrow xvy$、$p\leftarrow p\circ x(u\Rightarrow v)y$、$i\leftarrow 0$，回到第 2 步。
5. （Next）否则置 $i\leftarrow i+1$，回到第 2 步。

往 rule array 里添一条新 rewrite rule 之后，我们必须更新 rule trie。设新规则是 $(u,v)$，我们看它的左端 $u$。同样从根出发，按各个 symbol 沿边依次往下走，但这一次，必要时创建新节点。一旦抵达对应 $u$ 的那个节点，就把新规则的下标存进这个节点。

**算法（Insert rule in rule trie）.** 输入一条 rewrite rule $(u,v)$ 的下标。有副作用。

1. （Initialize）令 $n$ 为 trie 的根节点，令 $i:=0$。
2. （End）若 $i=|u|$，把 $\texttt{VALUE}(n)$ 更新为 $(u,v)$ 的下标，返回。
3. （Child）令 $s_i$ 为 $u$ 的第 $i$ 个 symbol，令 $m:=\texttt{CHILD}(n,s_i)$。若 $m$ 为 null，分配一个新节点 $m$，并置 $\texttt{CHILD}(n,s_i)\leftarrow m$。
4. （Next）置 $n \leftarrow m$、$i \leftarrow i+1$，回到第 2 步。

一旦收集齐一台 requirement machine 的 rewrite rule，我们就用下面这个算法把它们记录下来。我们先施加 normal form algorithm，用目前已添加的全部规则归约两端。若两端已经有相同的 normal form，就丢弃这条规则。否则在把它添进数组、更新 trie 之前，先按 reduction order 给这一对定向。注意 completion 也会添新的 rewrite rule，但用的是一个稍作扩展的流程，见 `completion.tex` 的 Resolve critical pair 算法。

**算法（Record rule）.** 输入一对 term $(u,v)$。返回一个标志，指示是否真的记录了一条新规则。有副作用。

1. （Reduce）对 $u$ 与 $v$ 施加 Normal form algorithm using rule trie 算法，得到 $\tilde{u}$ 与 $\tilde{v}$。
2. （Trivial）若 $\tilde{u}=\tilde{v}$，说明我们已经有 $u\sim v$ 了。返回 false。
3. （Compare）否则用 Weighted shortlex order 算法比较 $\tilde{u}$ 与 $\tilde{v}$。
4. （Error）若 $\tilde{u}$ 与 $\tilde{v}$ 不可比，报错。
5. （Orient）若 $\tilde{v}>\tilde{u}$，交换 $\tilde{u}$ 与 $\tilde{v}$。
6. （Record）现在有 $\tilde{u}>\tilde{v}$。把 $(\tilde{u},\tilde{v})$ 添进 rule array。
7. （Trie）调用 Insert rule in rule trie 算法更新 rule trie。返回 true。

注意第 4 步的错误在我们的实现里不可能发生，这是由「$\mathsf{rule}$」与「$\mathsf{rule}_\texttt{P}$」的定义方式决定的。的确，若两个 term 不可比，它们必定长度相同，且在相同位置上出现了 superclass、concrete type 或 concrete conformance symbol。然而这些 symbol 只出现在形如 $(t\cdot s,t)$ 的规则里，所以总有 $|t\cdot s|>|t|$，因而 $t\cdot s>t$。

### Rewrite paths.

Normal form algorithm using rule trie 算法输出一条 rewrite path，描述它执行的那次归约。现在我们讨论 rewrite path 及其 rewrite step 在实现里的表示。按 `monoids.tex` 的 rewrite step 定义，一步 rewrite $x(u\Rightarrow v)y$ 可以存成一个四元组 $(x,u,v,y)$，但我们用一种更紧凑的编码。

首先，$(u,v)$ 与 $(v,u)$ 之中必有一个是既有的 rewrite rule，取决于这一步是 positive 还是 negative。我们把全部 rewrite rule 放在一个数组里，所以一步 rewrite 只需存它那条 rewrite rule 的下标，外加一个「$+$」或「$-$」标志来指定方向。

其次，我们只需要知道 whisker $x$ 与 $y$ 的**长度**，而不需要 term 本身。理由是这样：设 $s:=x(u\Rightarrow v)y$，并且给定了 $\operatorname{src}(s)=xuy$。只要知道 $|x|$ 与 $|y|$，我们就能从 $\operatorname{src}(s)$ 里还原出 $x$ 与 $y$，进而用 $x$ 和 $y$ 构造出 term $\operatorname{dst}(s)=xvy$。

由归纳可知，若给定一条按这种方式表示的 rewrite path $p$ 连同 term $\operatorname{src}(p)$，我们就能还原出 $p$ 中每一步 rewrite 的左右 whisker，从而还原出每一步的起点与终点。最后也就得到了 $\operatorname{dst}(p)$。

于是，我们把一步 rewrite 编码成三个整数加一个布尔标志，而一条 rewrite path 则由初始 term 加一列按这种方式编码的 rewrite step 构成。**rewrite path evaluator** 按上面的办法还原出每一步的中间 term。这被用来在调试输出里打印 rewrite path。

### More about tries.

Lookup in rule trie 算法找的是输入字符串里匹配 trie 中某个 key 的最短前缀。特别地，若我们的 trie 里有两个 key、其中一个是另一个的前缀，那么 lookup 只会找到较短的那个。但较长的那个不能简单丢掉——我们会看到 completion 执行的是另一种 trie lookup，用来找出**所有**匹配的前缀（见 `completion.tex` 的 Overlap lookup in rule trie 算法）。最后，在 `property-map.tex` 里我们会看到，为了实现 property map 这个数据结构，我们用的是另一种 trie，它找的是输入字符串里匹配某个 key 的**最长后缀**。想了解更多关于 trie 的内容，见 Knuth《The Art of Computer Programming: Volume 3: Sorting and Searching》（1998）第 6.3 节。

### A possible optimization.

在一个输入字符串里查找一组固定子串的出现位置，是编程中的常见问题，而我们用 trie 的做法是典型解法。我们的测量表明，normal form algorithm 在总编译时间里占比微不足道，所以进一步优化似无必要。不过，在输入字符串非常长的那类应用里，Alfred V. Aho 与 Margaret J. Corasick 的论文（1975，《Efficient string matching: an aid to bibliographic search》）给出了进一步的改进。

在我们的 normal form algorithm 里，我们在输入 term 的每个位置上检查是否有匹配的 subterm。若当前在某个位置 $i$，一次 lookup 可能会在 trie 里遍历若干个节点（记为 $j$ 个），然后在位置 $i+j$ 处失败。此时我们从根节点重新开始一次新的 lookup，回到原 term 的位置 $i+1$。我们把这个整数 $j$ 称为一个 trie 节点的**层级**。当 lookup 在层级 $j>1$ 的节点处失败时，我们就被迫重看那些已经看过的 symbol。

Aho-Corasick 算法的关键想法，是给 trie（他们称之为 **goto graph**）补上一个描述 **failure function** 的额外数据结构。当节点 $n$ 没有对应下一个 symbol $s$ 的子节点时，failure function 把我们送到上一层级的某个别的节点——未必是根节点。于是我们可以在这个新节点上重新查**同一个** symbol $s$。若走到了根节点，那就不可能有匹配，于是前进到下一个 symbol，而且永不回头。

这个做法的代价是计算 failure function 所花的时间，而每当 rule trie 发生变化，这份工作就得重做一遍。不过必要的更新可以增量地完成，见 Meyer（1985，《Incremental string matching》，*Information Processing Letters* 21(5):219–227）。

## Source Code Reference

### Symbols

关键源文件：

- `lib/AST/RequirementMachine/Symbol.h`
- `lib/AST/RequirementMachine/Symbol.cpp`

**`rewriting::Symbol::Kind`**（enum class）：symbol 的 kind。各 case 的顺序是有意义的，它来自 symbol 上的 reduction order（见 Symbol reduction order 算法）。

- `ConcreteConformance`
- `Protocol`
- `AssociatedType`
- `GenericParam`
- `Layout`
- `Superclass`
- `ConcreteType`

> 译注：原书这份枚举清单漏了 `Name`，与前文 Symbol order 一节那张「symbol kind → 自然数」的表矛盾（那张表在 `GenericParam` 与 `Layout` 之间列出了 Name = 4），也与编译器源码 `lib/AST/RequirementMachine/Symbol.h` 里的实际定义不符，疑为笔误，以正文那张表为准。（顺带一提，实际源码里在 `Name` 之后还有本书未涉及的 `Shape` 与 `PackElement` 两个 case。）

**`rewriting::Symbol`**（class）：表示一个 immutable 且做过 unique 化的 symbol。实例按值传递。这个值包装了单个指针，指向由 `RewriteContext` 拥有的内部存储。symbol 在逻辑上是 variant 类型，但 C++ 并不直接支持这个概念，所以它的定义里有一些样板代码。

### Building symbols.

symbol 实例通过一组静态工厂方法获得，这些方法接收 structural component 与 `RewriteContext`：

- `forName()` 接收一个 `Identifier`。
- `forProtocol()` 接收一个 `ProtocolDecl *`。
- `forAssociatedType()` 接收一个 `ProtocolDecl *` 与一个 `Identifier`。
- `forGenericParam()` 接收一个 canonical 的 `GenericTypeParamType *`。
- `forLayout()` 接收一个 `LayoutConstraint`。
- `forSuperclass()` 接收一个 pattern type 与一列 substitution term。
- `forConcreteType()` 接收一个 pattern type 与一列 substitution term。
- `forConcreteConformance()` 接收一个 pattern type、一列 substitution term 以及一个 `ProtocolDecl *`。

后三个方法接收的 pattern type 类型是 `CanType`，substitution term 类型是 `ArrayRef<CanType>`。`RewriteContext::getSubstitutionSchemaFromType()` 方法接收任意一个具体的 `Type`，构造出 pattern type 与 substitution term。注意 pattern type 总是 canonical type，所以 Requirement Machine 在构造 generic signature 时并不保留 requirement 里的 type sugar。

### Structural components.

若干实例方法把 symbol 拆开：

- `getKind()` 返回 `Symbol::Kind`。它决定了余下哪些访问器可以调用。
- `getName()` 返回存在 name symbol 或 associated type symbol 里的 `Identifier`。
- `getProtocol()` 返回存在 protocol symbol、associated type symbol 或 concrete conformance symbol 里的 `ProtocolDecl *`。
- `getGenericParam()` 返回存在 generic parameter symbol 里的 `GenericTypeParamDecl *`。
- `getLayoutConstraint()` 返回存在 layout symbol 里的 `LayoutConstraint`。
- `getConcreteType()` 返回存在 superclass symbol、concrete type symbol 或 concrete conformance symbol 里的 pattern type。
- `getSubstitutions()` 返回存在 superclass symbol、concrete type symbol 或 concrete conformance symbol 里的 substitution term。
- `getRootProtocol()`：若这是 generic parameter symbol 则返回 `nullptr`；若这是 protocol symbol 或 associated type symbol 则返回一个 protocol declaration。对其他任何 symbol kind，触发断言。

比较 symbol：

- `operator==` 比较两个 symbol 是否相等。
- `compare()` 是 symbol 的 reduction order（见 Symbol reduction order 算法）。返回类型 `std::optional<int>` 与我们的记号对应如下：

  | 我们的记号 | C++ 返回值 |
  |---|---|
  | $\bot$ | `std::nullopt` |
  | $=$ | `std::optional(0)` |
  | $<$ | `std::optional(-1)` |
  | $>$ | `std::optional(1)` |

调试：

- `dump()` 以接近我们排版记号的方式打印这个 symbol。

**`rewriting::RewriteContext`**（class）：另见 `basic-operation.tex` 的 Source Code Reference 一节。

- `compareProtocols()` 实现 Protocol reduction order 算法。
- `getGenericParamIndex()` 接收一个必须是 depth 为 0 的 `GenericTypeParamType` 的 `Type`，返回它的 index。这是个很特定的操作，但在处理 superclass symbol、concrete type symbol 或 concrete conformance symbol 的 pattern type 时会频繁用到。
- `getSubstitutionSchemaFromType()` 接收任意一个具体的 `Type`，构造出 pattern type 与 substitution term；构造 concrete type symbol、superclass symbol 或 concrete conformance symbol 时会用到。它实现的是 Build concrete type symbol 算法。

### Terms

关键源文件：

- `lib/AST/RequirementMachine/Term.h`
- `lib/AST/RequirementMachine/Term.cpp`
- `lib/AST/RequirementMachine/RewriteContext.h`
- `lib/AST/RequirementMachine/InterfaceType.cpp`

### Common operations.

mutable term 与 immutable term 都实现了下列这组 STL 容器操作：

- `size()` 返回 term 的长度。
- `operator[]` 返回某个特定元素。
- `begin()` 与 `end()` 返回一对遍历 term 中 `Symbol` 元素的迭代器。
- `rbegin()` 与 `rend()` 返回一对逆序遍历的迭代器。
- `front()` 返回 term 里第一个 `Symbol`。
- `back()` 返回 term 里最后一个 `Symbol`。

两者还都提供了一个在处理「表示 type parameter 的 term」时很有用的工具方法：

- `getRootProtocol()`：若第一个 symbol 是 generic parameter symbol 则返回 `nullptr`，否则返回第一个 protocol symbol 或 associated type symbol 的 protocol。若第一个 symbol 是其他任何 kind，则触发断言。

**`rewriting::MutableTerm`**（class）：一个 mutable term。实例按需要以值或引用传递。每个值拥有一块堆分配的缓冲区来存放它所含的 symbol，所以复制 mutable term 有一定代价。默认构造函数创建一个空的 `MutableTerm`。其余构造函数从一列初始 symbol 初始化 `MutableTerm`，这列 symbol 可以指定为一对迭代器、一个 `ArrayRef`，或一个 immutable 的 `Term`。

这个类实现了上面列出的全部用于查看 term 中 symbol 的通用方法，此外还有几个：

- `empty()` 检查这个 mutable term 是否为空。
- `add()` 在这个 term 末尾添加单个 `Symbol`。
- `append()` 在这个 term 末尾追加另一个 `Term` 或 `MutableTerm`。这就是 free monoid 运算。
- `rewriteSubTerm()` 把这个 term 的某个 subterm 替换成另一个 term。要替换的 subterm 由一对迭代器指定，它们必须是指向本 term 的合法迭代器。替换用的 term 可以比原 subterm 更短或更长，本 term 的底层存储会相应地调整大小。这个操作是 Normal form algorithm using rule trie 算法里的关键一步。

**`rewriting::Term`**（class）：一个 immutable term。实例按值传递。每个值包装单个指针，指向由 `RewriteContext` 拥有的内部存储。immutable term 由 `Term` 上的一个静态工厂方法创建：

- `get()` 从一个 `MutableTerm` 创建一个 `Term`，该 `MutableTerm` 必须非空。

这个类实现了上面列出的全部用于查看 term 中 symbol 的通用方法，此外还有一个：

- `containsNameSymbols()`：若该 term 含有 name symbol 则返回 true。

比较 term：

- `operator==` 比较两个 immutable term 是否相等。它的实现是比较两者的指针是否恒同。
- `compare()` 实现 term 的 reduction order（见 Weighted shortlex order 算法）。返回类型 `std::optional<int>` 对结果的编码方式与 `Symbol::compare()` 相同。

调试：

- `dump()` 把 term 里的 symbol 用「`.`」连起来打印。

**`rewriting::RewriteContext`**（class）：另见 `basic-operation.tex` 的 Source Code Reference 一节。

- `getMutableTermForType()` 把一个含 type parameter 的 `Type` 翻译成一个 `MutableTerm`。这个方法同时实现了 Build term for explicit requirement 与 Build term for associated requirement 两个算法；第二个参数是一个 `ProtocolDecl *`，可以为 null。

### Rules

关键源文件：

- `lib/AST/RequirementMachine/RuleBuilder.h`
- `lib/AST/RequirementMachine/RuleBuilder.cpp`
- `lib/AST/RequirementMachine/Rule.h`
- `lib/AST/RequirementMachine/Rule.cpp`
- `lib/AST/RequirementMachine/RewriteSystem.h`
- `lib/AST/RequirementMachine/RewriteSystem.cpp`
- `lib/AST/RequirementMachine/Trie.h`

**`rewriting::Rule`**（class）：一条 rewrite rule，由一对 immutable term 加一些标志位表示。规则总是定向的，即在 term 的 reduction order 下右端小于左端。一对访问器方法把规则拆成两个 immutable term：

- `getLHS()` 返回左端。
- `getRHS()` 返回右端。

若干用于识别常见规则种类的工具方法：

- `isPropertyRule()` 检查这是否是一条 property rule，也就是 $(t\cdot s,\,t)$ 且 $s$ 是一个 property symbol。若是则返回 $s$，否则返回 `std::nullopt`。
- `isIdentityConformanceRule()` 检查这是否是一条 identity conformance rule，也就是 $([\texttt{P}]\cdot[\texttt{P}],\,[\texttt{P}])$。
- `isProtocolConformanceRule()` 检查这是否是一条 protocol conformance rule，也就是 $(t\cdot[\texttt{P}],\,t)$——换句话说，一条 property symbol 为 protocol symbol 的 property rule。
- `isAnyConformanceRule()` 检查这是否是一条 protocol conformance rule，或者一条 property symbol 为 concrete conformance symbol 的 property rule。
- `isProtocolTypeAliasRule()` 检查这条规则看起来是否像一条 protocol type alias rule，也就是：要么是一条左端为 $[\texttt{P}]\cdot\texttt{A}$（对某个 protocol symbol $[\texttt{P}]$ 与 name symbol $\texttt{A}$）的 same-type rule，要么是一条右端为 $[\texttt{P}]\cdot\texttt{A}$ 且 property symbol 为 concrete type symbol 的 property rule。
- `containsNameSymbols()`：若这条 rewrite rule 任一端含有 name symbol 则返回 true。

这些标志位我们在本章 Protocol Type Aliases 一节定义过：

- `isPermanent()` 与 `markPermanent()` 测试与设置 **permanent** 标志。
- `isExplicit()` 与 `markExplicit()` 测试与设置 **explicit** 标志。
- `isLHSSimplified()` 与 `markLHSSimplified()` 测试与设置 **left-simplified** 标志。
- `isRHSSimplified()` 与 `markRHSSimplified()` 测试与设置 **right-simplified** 标志。
- `isSubstitutionSimplified()` 与 `markSubstitutionSimplified()` 测试与设置 **substitution-simplified** 标志。
- `isConfliciting()` 与 `markConflicting()` 测试与设置 **conflicting** 标志。
- `isRecursive()` 与 `markRecursive()` 测试与设置 **recursive** 标志。
- `isFrozen()` 与 `freeze()` 测试与设置 **frozen** 标志。
- `isRedundant()` 与 `markRedundant()` 测试与设置 **redundant** 标志。

调试：

- `dump()` 以接近我们排版记号的方式打印这条规则。

> 译注：原书说这些标志位「在 Protocol Type Aliases 一节定义过」，但它们实际定义在本章 Rules 一节末尾的 The rule array 小标题下，疑为笔误。

**`rewriting::RewriteSystem`**（class）：一个 monoid presentation 里的 rewrite rule 清单，外加一些附加状态。每个 `RequirementMachine` 都有一个 `RewriteSystem`。另见 `completion.tex` 的 Source Code Reference 一节。

- `initialize()` 添加最初那份 imported rule 与 local rule 清单。
- `simplify()` 用 Normal form algorithm using rule trie 算法计算一个 term 的 normal form。就地修改给定的 `MutableTerm`，并可选地输出一条从原 term 到归约后 term 的 `RewritePath`。
- `addRule()` 归约并定向两端，记录一条新的 local rule。若两端有相同的 normal form 则返回 `false`，此时不添加任何规则。它同时实现了 Record rule 算法与下一章的 Resolve critical pair 算法。
- `addPermanentRule()` 尝试记录一条新的 rewrite rule，若确实添加了规则就立刻把它标成 **permanent**。
- `addExplicitRule()` 尝试记录一条新的 rewrite rule，若确实添加了规则就立刻把它标成 **explicit**。
- `getRules()` 返回这台 requirement machine 里全部规则构成的数组。
- `getLocalRules()` 返回这台 requirement machine 里全部 local rule 构成的数组。
- `getRule()` 返回给定下标处的规则。
- `dump()` 打印这个 `RewriteSystem` 里存着的全部 rewrite rule、rewrite loop 以及其他一些东西。

**`rewriting::RuleBuilder`**（class）：一个工具类，用来收集正在构造的 requirement machine 的 imported rule 与 local rule。下列方法由 `RequirementMachine` 里同名的方法调用：

- `initWithGenericSignature()` 为一台 query machine 构造 rewrite rule。
- `initWithWrittenRequirements()` 为一台 minimization machine 构造 rewrite rule。
- `initWithProtocolSignatureRequirements()` 为一台 protocol machine 构造 rewrite rule。
- `initWithProtocolWrittenRequirements()` 为一台 protocol minimization machine 构造 rewrite rule。

上面这些共享一些公共逻辑：

- `collectRulesFromReferencedProtocols()` 实现上一章（`basic-operation.tex`）的 Import rules from protocol components 算法。
- `addRequirement()` 实现 Build rule from explicit requirement 与 Build rule from associated requirement 两个算法。
- `addTypeAlias()` 实现 Build rule for protocol type alias 算法。
- `addPermanentProtocolRules()` 实现 Build protocol rules 算法。

**`rewriting::Trie`**（template class）：一个实现 trie 数据结构的模板类。被 `RewriteSystem` 与 `PropertyMap` 使用。key 是 term，value 类型是一个模板参数。另一个模板参数用来在「最短匹配」与「最长匹配」两种 lookup 策略之间选择。normal form algorithm 用的是最短匹配。另见 `completion.tex` 与 `property-map.tex` 各自的 Source Code Reference 一节。

- `find()` 用 Lookup in rule trie 算法查找一个既有条目。
- `insert()` 用 Insert rule in rule trie 算法插入一个新条目。

### Rewrite Steps

关键源文件：

- `lib/AST/RequirementMachine/RewriteLoop.h`
- `lib/AST/RequirementMachine/RewriteLoop.cpp`

另见 `completion.tex` 的 Source Code Reference 一节。

**`rewriting::RewriteStep::Kind`**（enum）：`RewriteStep::Kind::Rule` 这个 kind 表示把一条 rewrite rule 施加到一个 term 上。其他的 rewrite step kind 出现在 `property-map.tex` 的 Source Code Reference 一节。

**`rewriting::RewriteStep`**（struct）：一步 rewrite 的紧凑编码。

- `Kind` 是一个 `RewriteStep::Kind`。
- `Inverse` 是一个标志，编码这是一步 positive rewrite 还是 negative rewrite。对 `Rule` 而言，它指明的是 $(u,v)\in R$ 还是 $(v,u)\in R$。
- `StartOffset` 是左 whisker 的长度 $|x|$。
- `EndOffset` 是左 whisker 的长度 $|y|$。
- `Arg` 的含义取决于 kind；对 `Rule` 而言，它是这一步所施加的那条 rewrite rule 在 `RewriteSystem` 的 rule array 里的下标。
- `getRuleID()` 是一个 getter 方法，先断言 kind 是 `Rule`，再返回上面那个下标。

> 译注：原书 `EndOffset` 一条写作「左 whisker 的长度 $|y|$」，与其上一条 `StartOffset` 重复，且 $y$ 在全书中一律是**右** whisker（该条目原文的索引项标的也是 right whisker），疑为笔误，应为「右 whisker 的长度 $|y|$」。

**`rewriting::RewritePath`**（class）：一条 rewrite path，存成一个由 `RewriteStep` 元素构成的 `std::vector`。

- `empty()` 检查这是否是某个 term $t$ 上的空 rewrite path $1_t$。
- `size()` 返回这条 path 里 rewrite step 的个数。
- `begin()` 与 `end()` 返回一对用于遍历 path 中 rewrite step 的迭代器。
- `dump()` 用一种接近本书所用记号的方式打印这条 rewrite path；必须提供正确的源 `Term` 与 `RewriteSystem`。

**`rewriting::RewritePathEvaluator`**（class）：一个工具类，用来从一个源 term 出发求值一条 rewrite path。它按上面描述的紧凑编码，覆盖出 path 中的每一个中间 term。除别的用途外，这被用来实现 `RewritePath::dump()`。

---

> 译自 `docs/Generics/chapters/symbols-terms-and-rules.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
