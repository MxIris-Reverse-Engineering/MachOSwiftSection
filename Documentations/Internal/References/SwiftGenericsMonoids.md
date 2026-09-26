# Monoids（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/monoids.tex`（《Compiling Swift Generics》一书的「Monoids」一章，Part IV Requirement Machine 的第二章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这是全书数学最纯的一章，把 Requirement Machine 的理论地基一次性铺完——monoid、monoid presentation、free monoid、字符串重写系统、可归约 / 不可约、confluence、word problem 的不可判定性，以及「每个 finitely-presented monoid 都能写成一个 Swift protocol」这个核心对应。本库（MachOSwiftSection）**不实现**重写系统：它站在消费端，二进制里的 requirement 已经 minimize 过、type parameter 已经是 reduced form，本库照着读即可。把本章译出来的理由是，读懂「reduced / canonical 到底是什么意思、为什么编译器可以拿它当相等判据」，才知道本库为什么能直接按 mangled name 比对类型而不必自己求解约束。
>
> **术语**：书中定义的术语一律保留英文（monoid、monoid presentation、free monoid、generating set、term、rewrite rule、rewrite step、rewrite path、whiskering、monoid congruence、monoid homomorphism / isomorphism、Cayley graph、rewrite graph、word problem、reduction relation、normal form、reduction order、shortlex order、confluence、Church-Rosser property、convergent rewriting system、completion、finite derivation type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Derived Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的定义、例子、定理按原书的英文名或内容引用，不保留原书编号。
>
> **记法约定**（本章属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`；原书的自定义宏已就地展开）：
>
> | 记法 | 含义 |
> |---|---|
> | $(M,\,\cdot,\,\varepsilon)$ | monoid：集合、二元运算、identity element |
> | $\varepsilon$ | identity element；在 free monoid 里就是**空串** |
> | $A^*$ | 以 $A$ 为 generating set（alphabet）的 **free monoid**，元素叫 **term** |
> | $\lvert t\rvert$ | term $t$ 的**长度** |
> | $x^n$ | $x$ 的 $n$ 次幂（$x$ 连乘 $n$ 次，$x^0=\varepsilon$） |
> | $\langle A \mid R\rangle$ | **monoid presentation**：竖线左边是 generators，右边是 rewrite rules |
> | $u \sim v$ | 一条 rewrite rule；也写作 $(u,v)\in R$ |
> | $x \sim_R y$、$x \sim y$ | **term equivalence**（$R$ 生成的等价关系）。注意 $x = y$ 一律指两个 term **逐字相同**，不是等价 |
> | $x(u\Rightarrow v)y$ | 一个 **rewrite step**：把 term 中间的 $u$ 换成 $v$，$x$ / $y$ 是左右 **whisker** |
> | $\operatorname{src}(p)$、$\operatorname{dst}(p)$ | rewrite step / rewrite path 的起点与终点 |
> | $1_t$ | term $t$ 上的 **empty rewrite path** |
> | $p_1 \circ p_2$ | rewrite path 的**复合** |
> | $p^{-1}$ | rewrite path 的**逆** |
> | $z \triangleleft p$、$p \triangleright z$ | 左 / 右 **whiskering**：把 $z$ 接到 path 每一步的左 / 右侧 |
> | $[\![t]\!]$ | term $t$ 的**等价类**（同一记号在散文章节里也用于 archetype） |
> | $s \rightarrow t$ | **reduction relation**：存在一条从 $s$ 到 $t$ 的 positive rewrite path |
> | $\tilde{s}$ | $s$ 的 **normal form**（不可约的归约结果） |
> | $<$、$\bot$ | reduction order（shortlex order）；$\bot$ 表示两项**不可比** |
> | $\mathbb{N}$、$\mathbb{Z}_4$ | 自然数集；模 4 加法 monoid |
> | $\varphi$、$\varphi^{-1}$ | term $\leftrightarrow$ type parameter 的互逆映射 |
> | $G_\texttt{M}$、$G_N$ | protocol `M` / `N` 的 **protocol generic signature** |
> | $G \vdash D$ | $D$ 是 $G$ 的一条 **derived requirement**（turnstile，见 `generic-signatures.tex` 的 Derived Requirements 一节） |
> | $[\texttt{T: P}]$、$[\texttt{T == U}]$ | conformance requirement / same-type requirement |
> | $[\texttt{Self.U: Q}]_\texttt{P}$、$[\texttt{Self.U == Self.V}]_\texttt{P}$ | protocol `P` 的 **associated** conformance / same-type requirement |
> | $\mathsf{Conf}$、$\mathsf{AssocSame}$、$\mathsf{Trans}$… | derivation step 的规则名（原书用 small caps，KaTeX 不支持 `\textsc`，一律改 `\mathsf`） |
> | $\mathfrak{C}_1$、$\mathfrak{U}$、$S_1$、$D_{12}$ | Tseitin 的 monoid、Collins 的 monoid、Squier 的 monoid、12 阶二面体群 |

---

**Monoid** 是抽象代数里最基本的研究对象之一。它简单到足以容纳极大的一般性，所以我们很快就会把视野收窄到 **finitely-presented** 的那一类。我们将看到：每个 finitely-presented monoid 都能翻译成一个 Swift generic signature，这就在 `generic-signatures.tex` 的 Derived Requirements 一节那套 derived requirements 形式系统与 **word problem** 之间搭起了一座桥。跟 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 The Halting Problem 一节里的 halting problem 一样，我们会看到 word problem 在一般情形下是不可判定的。另一方面，对那些存在 **convergent** presentation 的 finitely-presented monoid，它是可解的。这为下一章做好了准备：在那里我们会把 generic signature 编码成一个 finitely-presented monoid，从而「解掉」derived requirements 形式系统。我们先从标准定义讲起，出处见 Howie 1995《Fundamentals of Semigroup Theory》与 Smith & Romanowska 2011《Post-Modern Algebra》。

**定义.** 一个 **monoid** $(M,\, \cdot,\, \varepsilon)$ 是由一个集合 $M$、一个二元运算 $\cdot$ 和一个 identity element $\varepsilon\in M$ 组成的结构，三者共同满足下面三条公理：

- 集合 $M$ 对该二元运算**封闭**：$\forall\, x,y \in M$，有 $x\cdot y\in M$。
- 该二元运算满足**结合律**（associative）：$\forall\, x, y, z \in M$，有 $x\cdot(y\cdot z)=(x\cdot y)\cdot z$。
- 元素 $\varepsilon$ 起 **identity** 的作用：$\forall\, x\in M$，有 $x\cdot \varepsilon=\varepsilon\cdot x=x$。

当二元运算和 identity element 从上下文已经清楚时，我们可以直接写 $M$ 而不写 $(M,\,\cdot,\,\varepsilon)$。有时也会省掉 $\cdot$ 这个符号，所以若 $x,y\in M$，可以写 $xy$ 代替 $x\cdot y$。最后，结合律让我们在 $x\cdot y\cdot z$ 或 $xyz$ 这样的表达式里省掉括号也不会有歧义。

具体的 monoid 实例可以相当复杂、相当抽象，不过我们的第一个例子很好描述。

**例.** 若取加法为运算、零为 identity element，则自然数集 $\mathbb{N}$ 满足 monoid 公理：

- 两个自然数之和仍是自然数。
- 加法满足结合律：$\forall\, x,y,z\in\mathbb{N}$，有 $(x+y)+z=x+(y+z)$。
- 零是 identity：$\forall\, x\in\mathbb{N}$，有 $x+0=0+x=x$。

我们很快会看到，$(\mathbb{N},+,0)$ 正是下面这个构造的一个实例。

**定义.** 设 $A$ 是一个集合。由 $A$ 生成的 **free monoid**（记作 $A^*$）是 $A$ 中元素组成的全部**有限串**的集合。（这跟 **regular expression** 里的 `*` 运算符是同一套记法。）集合 $A$ 称为 $A^*$ 的 **alphabet** 或 **generating set**。generating set 可以是有限的也可以是无限的，但除非特别说明，我们都假定它是有限的。$A^*$ 上的二元运算是**字符串拼接**，identity element $\varepsilon$ 是空串。$A^*$ 的元素也叫 **term**。若存在 $x,y\in A^*$ 使得 $t=xuy$，我们就说 $u$ 是 $t$ 的一个 **subterm**。term $t\in A^*$ 的**长度**记作 $\lvert t\rvert\in\mathbb{N}$。

读者不妨回头看看 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)） 的 The Type Parameter Graph 一节里关于 type parameter graph 的讨论。在抽象代数里，一个 monoid 的 **Cayley graph** 扮演着类似的角色，我们会发现两者之间有大量的平行对应。一般性的构造放到下一节讲，眼下先只看 free monoid $A^*$ 的 Cayley graph。这张图的顶点就是 $A^*$ 的各个 term，identity element 对应的顶点是特殊的 root 顶点。然后，对每个顶点 $t$ 和每个 generator $g\in A$，我们加一条以 $t$ 为 source、$tg$ 为 destination 的边，并把这条边标成 $g$。（这有时叫 **right** Cayley graph；对应地，left Cayley graph 可以反过来定义，把 $t$ 与 $gt$ 相连。）

**例.** 两个 generator 的 free monoid $\{a,b\}^*$ 由 $a$ 和 $b$ 组成的全部有限串构成。两个典型元素是 $abba$ 和 $bab$，它们的拼接是 $abba\cdot bab=abbabab$。与 $(\mathbb{N},+,0)$ 不同，这个 monoid 运算不满足**交换律**（commutative），例如 $abba\cdot bab\neq bab\cdot abba$。$\{a,b\}^*$ 的 Cayley graph 是一棵无限二叉树。每个顶点都有两个后继，分别对应右乘 $a$ 与右乘 $b$：

```
ε
├─a─→ a
│     ├─a─→ aa
│     │     ├─a─→ aaa ─a─→ …
│     │     │           └─b─→ …
│     │     └─b─→ aab ─a─→ …
│     │                 └─b─→ …
│     └─b─→ ab
│           ├─a─→ aba ─a─→ …
│           │           └─b─→ …
│           └─b─→ abb ─a─→ …
│                       └─b─→ …
└─b─→ b
      ├─a─→ ba
      │     ├─a─→ baa ─a─→ …
      │     │           └─b─→ …
      │     └─b─→ bab ─a─→ …
      │                 └─b─→ …
      └─b─→ bb
            ├─a─→ bba ─a─→ …
            │           └─b─→ …
            └─b─→ bbb ─a─→ …
                        └─b─→ …
```

> 译注：原书此处是一张 TikZ 图（以 $\varepsilon$ 为根、向四面展开的无限二叉树），这里用 ASCII 树转述；树枝上的 `a` / `b` 就是原图的边标签。图的原貌见官方 PDF 对应章节。

每个 term 都在 Cayley graph 里确定一条 path：从根 $\varepsilon$ 出发，沿着一串 $a$ 边或 $b$ 边走下去，直到抵达代表该 term 的顶点。一般地，Cayley graph 里每个顶点的后继个数都相同，等于 generating set $A$ 的元素个数。

在继续之前，我们需要一个把 $xxx$ 写成 $x^3$ 的简写：

**定义.** 设 $M$ 是一个 monoid。若 $x\in M$ 且 $n\in\mathbb{N}$，可以把 $x^n$ 定义为 $x$ 的「$n$ 次幂」：

$$
x^n = \begin{cases}
\varepsilon&n=0\\
x&n=1\\
x^{n-1}\cdot x&n>1
\end{cases}
$$

这套记法的正当性由下面这条「指数律」担保。

**命题.** 设 $M$ 是一个 monoid。若 $x\in M$ 是某个元素，则 $\forall\, m,n\in\mathbb{N}$，有 $x^m\cdot x^n=x^{m+n}$。

**证明.** 我们先固定一个任意的 $m\in\mathbb{N}$，然后对 $n\in\mathbb{N}$ 作**归纳**（见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Well-Formed Requirements 一节）。

**基础情形.** 需要证明 $x^m\cdot x^0=x^{m+0}$。用上 $x^0$ 的定义、$M$ 的 identity element 公理，以及 $\mathbb{N}$ 里 $m=m+0$ 这个事实：

$$x^m\cdot x^0=x^m\cdot\varepsilon=x^{m}=x^{m+0}$$

**归纳步骤.** 首先假定归纳假设成立：

$$x^m\cdot x^{n-1}=x^{m+n-1}$$

然后用 $M$ 的 monoid 运算给两边同时右乘 $x$：

$$(x^m\cdot x^{n-1})\cdot x =x^{m+n-1}\cdot x$$

用 $M$ 的结合律和 $x^n$ 的定义改写左边：

$$
(x^m\cdot x^{n-1})\cdot x = x^m\cdot (x^{n-1}\cdot x) = x^m\cdot x^{n-1+1}=x^m\cdot x^n
$$

再用 $x^n$ 的定义改写右边：

$$
x^{m+n-1}\cdot x = x^{m+n-1+1}=x^{m+n}
$$

合起来就得到 $x^m\cdot x^n=x^{m+n}$。由归纳法，这对所有 $n\in\mathbb{N}$ 都成立；又因为我们一开始取的 $m\in\mathbb{N}$ 也是任意的，证毕。

**例.** 单 generator 的 free monoid $\{a\}^*$ 与 $(\mathbb{N},+,0)$ **同构**（isomorphic）。isomorphism 稍后再谈，但本质上它意味着两者定义的是同一个对象，差别只在记法的选择。

确实，$\mathbb{N}$ 的每个非零元素都能唯一地表示成若干个 $1$ 之和，例如 $3=1+1+1$、$5=1+1+1+1+1$。这意味着我们可以用 $\varepsilon$ 代替 $0$、用 $a$ 代替 $1$、用 $\cdot$ 代替 $+$。于是等式 $3+5=8$ 就翻译成 $aaa\cdot aaaaa=aaaaaaaa$，用指数记法写就是 $a^3\cdot a^5 = a^8$。

接着看 $\{a\}^*$ 的 Cayley graph。这里每个顶点只有一个后继，因为 generating set 只有 $a$ 一个元素。这看起来正像 `archetypes.tex` 里 protocol `N` 的 type parameter graph，理由会在本章 A Swift Connection 一节揭晓：

```
 ε ──a──→ a ──a──→ a² ──a──→ a³ ──a──→ ⋯
```

> 译注：原书此处是一张 TikZ 图（一条向右无限延伸的链），这里用 Unicode 箭头图转述；这张图断言的是：$\{a\}^*$ 的 Cayley graph 里每个顶点只有一个后继，整张图就是一条链。图的原貌见官方 PDF 对应章节。

**例.** 以**空集**为 generating set 的 free monoid $\varnothing^*$ 就是 $\{\varepsilon\}$——只含空串的单元素集合。这叫 **trivial monoid**，它的 Cayley graph 是单个顶点。

## Finitely-Presented Monoids

free monoid 的每个元素都有**唯一**一种写成 generator 乘积的方式。finitely-presented monoid 更一般，因为多个不同的组合可以指向同一个元素。为了给这个现象建模，我们加入一个有限的 **rewrite rule**（或称 **relation**）集合，它们随后会在 term 上生成一个等价关系。我们在 `generic-signatures.tex` 的 Valid Type Parameters 一节第一次用到等价关系，为的是理解 generic signature 的 same-type requirement；下面这个构造与之类似。

一个 **monoid presentation** 就是一张 generator 与 rewrite rule 的清单：

$$\langle \underbrace{a_1,\,\ldots,\, a_m}_{\text{generators}} \mid \underbrace{u_1 \sim v_1,\,\ldots,\, u_n \sim v_n}_{\text{rewrite rules}}\rangle$$

另外，若 $A := \{a_1,\ldots, a_m\}$ 与 $R := \{(u_1,v_1),\,\ldots,\,(u_n,v_n)\}\subseteq A^* \times A^*$ 都是有限集，我们就能构造 monoid presentation $\langle A \mid R\rangle$。$R$ 在 $A^*$ 的 term 上生成的等价关系记作 $x\sim_R y$；当 $R$ 从上下文已经清楚时就写 $x \sim y$。注意：当我们写 $x=y$ 时，**永远**是指 $x$ 与 $y$ 在 $A^*$ 里**逐字相同**，而不只是在 $\langle A \mid R\rangle$ 里等价。

我们先描述 term equivalence relation 背后那个直观模型，下一节再给严格定义。从语法上看，一条 rewrite rule $(u,v)\in R$ 就是一对 term。从语义上看，一条 rewrite rule 告诉我们：只要在某个 term 里的任何位置找到 $u$，就可以把这个 subterm 换成 $v$，得到另一个等价的 term。term equivalence 是对称的，所以反过来把 $v$ 换成 $u$ 同样可以。最后它还是传递的，所以这些 rewrite step 可以迭代任意多次来证明一个等价。

一个 monoid presentation $\langle A \mid R\rangle$ 定义出一个 **finitely-presented monoid**：元素是 $\sim_R$ 的**等价类**，identity element 是 $\varepsilon$ 所在的等价类，二元运算是 term 的拼接（我们稍后会证明它是 well-defined 的）。

**例.** finitely-presented monoid 推广了 free monoid——每个 free monoid（generating set 有限时）只要配上空的 rewrite rule 集合，也是 finitely presented 的。此时 $x\sim y$ 当且仅当 $x=y$。

**例.** 考虑有限集 $\{0,1,2,3\}$ 配上由下表给出的二元运算 $+$。这种定义有限 monoid 的办法叫 **Cayley table**：

| $+$ | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| **0** | 0 | 1 | 2 | 3 |
| **1** | 1 | 2 | 3 | 0 |
| **2** | 2 | 3 | 0 | 1 |
| **3** | 3 | 0 | 1 | 2 |

上面这个运算就是**模 4 加法**，这个 monoid 记作 $\mathbb{Z}_4$。若用 $a$ 代替 $1$、$\varepsilon$ 代替 $0$、$\cdot$ 代替 $+$，就能用一个 generator 和一条 rewrite rule 把 $\mathbb{Z}_4$ 呈现出来：

$$\mathbb{Z}_4 := \langle a \mid a^4\sim\varepsilon\rangle$$

规则 $a^4\sim\varepsilon$ 允许我们插入或删除 $aaaa$，由此得到这条一般原理：

$a^m\sim a^n$ 当且仅当 $m\equiv n\pmod 4$。

于是这条规则把 $\{a\}^*$ 的 term 划分成四个无限的等价类：

$$
\begin{gathered}
\{\varepsilon,\, a^4,\, a^8, \ldots,\, a^{4k},\, \ldots\}\\
\{a,\, a^5,\, a^9,\, \ldots,\, a^{4k+1},\, \ldots\}\\
\{a^2,\, a^6,\, a^{10},\, \ldots,\, a^{4k+2},\, \ldots\}\\
\{a^3,\, a^7,\, a^{11},\, \ldots,\, a^{4k+3},\, \ldots\}
\end{gathered}
$$

构造 finitely-presented monoid 的 Cayley graph 时，我们取 term 的**等价类**作为顶点。边的关系现在定义在这些等价类上：对每个等价类 $[\![t]\!]$ 和每个 generator $g\in A$，加一条以 $[\![t]\!]$ 为 source、$[\![tg]\!]$ 为 destination 的边。若我们用每个等价类中最短的 term 给顶点贴标签，就会看到 $\mathbb{Z}_4$ 的 Cayley graph 长得正像 `archetypes.tex` 里 `Z4` protocol 的 type parameter graph：

```
       ε  ──a──→  a
       ↑           │
       │a         a│
       │           ↓
       a³ ←──a──  a²
```

> 译注：原书此处是一张 TikZ 图（四个顶点首尾相接的有向圈），这里用 Unicode 箭头图转述；这张图断言的是：$\mathbb{Z}_4$ 的四个等价类排成一个长度为 4 的有向圈，每走一条 $a$ 边就前进一个等价类，走满四步回到 $\varepsilon$。图的原貌见官方 PDF 对应章节。

**例.** 我们看到 free monoid $\{a,b\}^*$ 不满足交换律。如果希望以「最一般」的方式让它变得可交换，可以考虑两个 generator 上的 **free commutative monoid**：

$$\langle a,b \mid ba\sim ab\rangle$$

这条规则说的是我们可以在一个 term 内部置换 $a$ 和 $b$，除此之外什么都不许做；特别地，同一个等价类里的 term 长度必然全都相同。因此每个等价类都是有限的；进一步，我们可以把任意 term 变形成一个 $a$ 全排在前面的「canonical form」。这让我们可以靠指数相加来计算（事实上这个 monoid 同构于 **Cartesian product** $\mathbb{N}\times\mathbb{N}$，其元素是按分量相加的有序对）。例如：

$$a^2 b^3 \cdot a^7 b = a^9 b^4$$

canonical form 的存在意味着每个等价类都恰好含有一个形如 $a^mb^n$（$m,n\in\mathbb{N}$）的 term，我们就拿它们当 Cayley graph 的顶点标签。现在，右乘 $a$ 使第一个指数加一，右乘 $b$ 使第二个指数加一。若把顶点排成网格，就会看到每个顶点都与它正下方和正右方的顶点相连：

```
  ε   ──a──→  a   ──a──→  a²   ──a──→  a³   ──a──→ ⋯
  │            │            │            │
  b            b            b            b
  ↓            ↓            ↓            ↓
  b   ──a──→  ab  ──a──→  a²b  ──a──→  a³b  ──a──→ ⋯
  │            │            │            │
  b            b            b            b
  ↓            ↓            ↓            ↓
  b²  ──a──→  ab² ──a──→  a²b² ──a──→  a³b² ──a──→ ⋯
  │            │            │            │
  b            b            b            b
  ↓            ↓            ↓            ↓
  b³  ──a──→  ab³ ──a──→  a²b³ ──a──→  a³b³ ──a──→ ⋯
  │            │            │            │
  ↓            ↓            ↓            ↓
  ⋯            ⋯            ⋯            ⋯
```

> 译注：原书此处是一张 TikZ 图（向右下无限延伸的网格，横边标 $a$、竖边标 $b$），这里用 Unicode 箭头图转述；这张图断言的是：$\langle a,b \mid ba\sim ab\rangle$ 的等价类与 $\mathbb{N}\times\mathbb{N}$ 的格点一一对应，横向走一步指数 $m$ 加一、纵向走一步指数 $n$ 加一。图的原貌见官方 PDF 对应章节。

这张 Cayley graph（以及 $\mathbb{Z}_4$ 那张）里有一样 free monoid 没有的东西：**起点和终点相同的多条 path**。例如，因为 $ababab\sim aaabbb$，我们可以从 $\varepsilon$ 出发，把这两个 term 中的任意一个从左往右读着走边，两种走法最后都停在 $a^3b^3$。$a^3b^3$ 的等价类刻画的，正是所有能把我们带到网格右下角的「步行路线」。

**例.** 下一个例子同样从两个 generator 和一条 rewrite rule 起步，但得到的 monoid 面貌相当不同。

给定一串 `(` 和 `)`，若想判断括号是否配平，可以反复删除出现的子串 `()`，直到再也删不动为止。如果最后得到空串，就知道原串里每个左括号都有右括号与之匹配。现在，用 $a$ 代替 `(`、用 $b$ 代替 `)`，这就是 **bicyclic monoid**——配平的括号串恰好就是那些等价于 $\varepsilon$ 的 term：

$$\langle a, b \mid ab\sim\varepsilon\rangle$$

考虑 term $baaba$，它含有 subterm $ab$。我们的规则允许把这个 subterm 换成 $\varepsilon$，于是 $baaba\sim baa$。接着还可以在别的位置插回一个 $ab$，例如 $baa\sim babaa$。等价关系是**传递的**，所以也有 $baaba\sim babaa$。注意这个 monoid 不满足交换律，例如 $ab\not\sim ba$。在这个 monoid 里，每个等价类都有唯一一个长度最小的 term，就是那个不含任何 $ab$ 的 term。这种 term 形如 $b^ma^n$（$m,n\in\mathbb{N}$），我们就拿它们给顶点贴标签。跟上一个例子一样，把 Cayley graph 的顶点排成网格：

```
  ε   ⇄  a   ⇄  a²   ⇄  a³   ⇄ ⋯
  │
  b
  ↓
  b   ⇄  ba  ⇄  ba²  ⇄  ba³  ⇄ ⋯
  │
  b
  ↓
  b²  ⇄  b²a ⇄  b²a² ⇄  b²a³ ⇄ ⋯
  │
  b
  ↓
  b³  ⇄  b³a ⇄  b³a² ⇄  b³a³ ⇄ ⋯
  │
  ↓
  ⋯
```

> 译注：原书此处是一张 TikZ 图（网格，横向是一对方向相反的弯边），这里用 Unicode 箭头图转述。`⇄` 表示横向的一对边：**向右**那条标 $a$（右乘 $a$），**向左**那条标 $b$（右乘 $b$ 把刚加上的 $a$ 抵消掉）；竖直的 $b$ 边只存在于最左一列——只有当右边没有 $a$ 可抵消时，乘 $b$ 才会把我们带进新的一行。这张图断言的是：从 $\varepsilon$ 到任何顶点都有唯一一条最短 path，即不含 $ab$ 的那条。图的原貌见官方 PDF 对应章节。

要更好地理解这个边关系，可以观察到：任何 term 右乘一个 $a$ 之后，再乘一个 $b$ 就能把这个 $a$「抵消」掉，回到原处。反过来，若右边已经没有 $a$ 可抵消了，新加一个 $b$ 会把我们带进一个再也回不来的新「状态」。从 $\varepsilon$ 到其余每个顶点都存在唯一一条最短 path，就是那条不含 $ab$ 的 path。

**例.** 并非每个「初等」的 monoid 都是 finitely presented 的，一个例子就是**乘法**下的自然数。这是自然数的下面四条性质导致的：

1. 每个非零自然数都有唯一一种写成**素数**乘积的表示（**算术基本定理**）。
2. 素数有无穷多个（**欧几里得定理**）。
3. 自然数乘法满足交换律。
4. 任何数乘以零都得零。

这几条给了我们 $(\mathbb{N},\cdot,1)$ 的一个**无限** presentation。这个 monoid 由零和所有素数生成：$\{0,\,2,\,3,\,5,\,7,\,11,\,\ldots\}$。然后，加上规则 $0\cdot 0\sim 0$（零乘零得零），再加上两个无限的 rewrite rule 集合：

- 对每一对不同的素数 $p$ 与 $q$，有 $p\cdot q\sim q\cdot p$，于是二元运算可交换。
- 对每个素数 $p$，有 $0\cdot p\sim 0$ 与 $p\cdot 0\sim 0$，于是零表现得像个 **zero element**。

一个自然数的唯一素因子分解，其实就是用这些 generator 写出来的一个 term，例如 $84=2^2\cdot 3\cdot 7$。这个 monoid 远比 $(\mathbb{N},+,0)$ 精巧——后者不过是单 generator 的 free monoid 而已。

### Mathematical aside.

抽象代数课程通常从 **group** 讲起。group 就是这样的 monoid：其中每个元素 $x$ 都有一个逆元 $x^{-1}$，满足 $x\cdot x^{-1}=x^{-1}\cdot x=\varepsilon$。就因为多了这一条公理，group 的结构就比 monoid 丰富得多。加法下的自然数不是 group，但若改取全体整数 $\mathbb{Z}$，则 $\mathbb{Z}$ 在加法下是 group，因为每个 $n\in\mathbb{Z}$ 都有逆元：$n+(-n)=(-n)+n=0$。加法可交换，而二元运算可交换的 group 又叫 **Abelian group**。

再上一层结构是 **ring**。一个 ring 是一个集合 $R$ 配上**两个**二元运算（记作 $+$ 与 $\cdot$）以及两个特殊元素 $0$ 和 $1$。ring 的公理要求 $(R,+,0)$ 是 Abelian group、$(R,\cdot,1)$ 是 monoid，且 $+$ 与 $\cdot$ 通过**分配律**关联：$a(b+c)=ab+ac$ 且 $(a+b)c=ac+bc$。配上通常的加法和乘法，$\mathbb{Z}$ 就成了一个 ring。若每个非零元素都有乘法逆元，就得到 **division ring**。若进一步要求乘法可交换，就得到 **field**。在 field 里，非零元素在乘法下构成一个 Abelian group。有理数集 $\mathbb{Q}$ 就是一个 field。

这一整座抽象阶梯同样刻画复数、四元数、矩阵、多项式、模算术，以及数学各种应用中常见的其他「类数」对象。

## Equivalence of Terms

monoid presentation 的 Cayley graph 帮我们看清了各个等价类**之间**的关系。为了看清**单个**等价类**内部**的结构，我们跟随 Squier、Otto 与 Kobayashi 1994（《A finiteness condition for rewriting systems》）引入另一张有向图，叫 monoid presentation $\langle A \mid R\rangle$ 的 **rewrite graph**。先从这张图的边讲起。

**定义.** 一个 monoid presentation $\langle A \mid R\rangle$ 生成一组 **rewrite step**：

1. 一个 **rewrite step** 是一个有序的 term 元组，写作 $x(u\Rightarrow v)y$，其中 $x,y\in A^*$，且 $(u,v)$ 与 $(v,u)$ 二者之一属于 $R$。
2. 若 $(u,v)\in R$，我们说 $x(u\Rightarrow v)y$ 是一个 **positive** rewrite step；若 $(v,u)\in R$，则 $x(u\Rightarrow v)y$ 是一个 **negative** rewrite step。
3. term $x$ 与 $y$ 分别叫作 **left whisker** 与 **right whisker**。若 $x$ 或 $y$ 恰好就是 $\varepsilon$，记法中就把它省略。
4. 为了让 rewrite step 能充当图里的边，我们把 rewrite step $s:= x(u\Rightarrow v)y$ 的 **source** 与 **destination** 定义为 $A^*$ 中的下面两个 term：

$$
\begin{gathered}
\operatorname{src}(s) := xuy\\
\operatorname{dst}(s) := xvy
\end{gathered}
$$

rewrite step $x(u\Rightarrow v)y$ 代表把 $xuy$ 变换成 $xvy$：用 $v$ 替换掉 $u$，而 whisker $x$ 与 $y$ 原封不动。（不失一般性地，可以假定 $u\neq v$，从而排除掉 $\operatorname{src}(s)=\operatorname{dst}(s)$ 这种冗余的 step。）可以画张图：

```
┌───────────────────────┐
│          xuy          │
╞═══════╤═══════╤═══════╡
│       │   u   │       │
│   x   │   ⇓   │   y   │
│       │   v   │       │
╞═══════╧═══════╧═══════╡
│          xvy          │
└───────────────────────┘
```

> 译注：原书此处是用 LaTeX `array` 画的一个三列方框示意图，这里用 ASCII 方框转述；这张图断言的是：$xuy$ 与 $xvy$ 只在中段不同（$u$ 换成了 $v$），左右两段 whisker $x$ 与 $y$ 完全没动。图的原貌见官方 PDF 对应章节。

**定义.** monoid presentation $\langle A \mid R\rangle$ 的 **rewrite graph** 以 $A^*$ 的各个 term 为**顶点**、以 rewrite step 为**边**。除了 $A=\varnothing$ 这种平凡情形以外，这张图是无限的，但我们每次只看它的一小块**子图**。例如，每个 rewrite step 都确定一个两顶点、一条边的子图：

```
            x(u⇒v)y
  xuy ══════════════════⇒ xvy
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；这张图断言的是：一个 rewrite step 就是 rewrite graph 里从 $xuy$ 指向 $xvy$ 的一条边，边上标的就是这个 step 本身。图的原貌见官方 PDF 对应章节。

有了 rewrite graph，我们就把 $x\sim_R y$ 定义成「这张图里存在一条 source 为 $x$、destination 为 $y$ 的 **path**」。下面这个 rewrite path 的定义，与 `archetypes.tex` 的 The Type Parameter Graph 一节里有向图中 path 的一般定义完全一致。

**定义.** 一条 **rewrite path** 由一个初始 term $t\in A^*$ 连同一串零个或多个 rewrite step $(s_1,\ldots,s_n)$ 组成，且满足下列条件：

1. 若这条 rewrite path 至少含一个 rewrite step，则第一个 rewrite step 的 source 必须等于初始 term：$\operatorname{src}(s_1)=t$。
2. 若这条 rewrite path 至少含两个 step，则后一个 step 的 source 必须等于前一个 step 的 destination：$\operatorname{src}(s_{i+1})=\operatorname{dst}(s_i)$，其中 $0<i\leq n$。

跟 rewrite step 一样，每条 rewrite path 也有 source 与 destination。我们这样定义一条 rewrite path $p$ 的 source 与 destination，其中 $n$ 是 $p$ 的**长度**：

$$
\begin{gathered}
\operatorname{src}(p):=t\\
\operatorname{dst}(p):=\begin{cases}
\operatorname{dst}(s_n)&\text{if } n>0\\
t&\text{if } n=0
\end{cases}
\end{gathered}
$$

对每个 term $t\in A^*$，都可以关联一条 rewrite step 序列为空的 rewrite path，叫 **empty rewrite path**，记作 $1_t$。它满足 $\operatorname{src}(1_t)=\operatorname{dst}(1_t)=t$。（这正是 rewrite path 必须存下初始 term 的原因——在空的情形下得靠它来指明 source 与 destination。）一条非空的 rewrite path $p$ 可以写成若干 step 的复合：$p=s_1\circ\cdots\circ s_n$。也可以把 rewrite path 想象成 rewrite graph 里的一条 path：

```
           s₁            ⋯             sₙ
  src(p) ══════⇒ ⋯ ══════⇒ ⋯ ══════⇒ dst(p)
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；这张图断言的是：一条 rewrite path 就是首尾相接的一串 rewrite step，整条 path 的 source 是第一步的 source、destination 是最后一步的 destination。图的原貌见官方 PDF 对应章节。

**例.** 回忆前面那个 bicyclic monoid $\langle a, b \mid ab\sim\varepsilon\rangle$。我们看到过 $baaba\sim baa$，因为从 $baaba$ 里删掉 subterm $ab$ 就得到 $baa$。这可以用一个 rewrite step $ba(ab\Rightarrow\varepsilon)a$ 来编码：

```
            ba(ab⇒ε)a
  baaba ══════════════⇒ baa
```

我们也看到过 $baa\sim babaa$。把 $baa$ 变换成 $babaa$ 这件事，可以用 rewrite step $b(\varepsilon\Rightarrow ab)aa$ 来编码：

```
            b(ε⇒ab)aa
  baa ══════════════⇒ babaa
```

第一个 rewrite step 的 destination 恰好是第二个 rewrite step 的 source。把它们复合起来就得到 rewrite path $ba(ab\Rightarrow\varepsilon)a\circ b(\varepsilon\Rightarrow ab)aa$。这条 rewrite path 编码了 $baaba\sim babaa$ 这个事实：

```
            ba(ab⇒ε)a           b(ε⇒ab)aa
  baaba ══════════════⇒ baa ══════════════⇒ babaa
```

> 译注：原书此处是三张 tikzcd 交换图（两个单步，外加它们的复合），这里用 Unicode 箭头图转述；这三张图断言的是：两个 rewrite step 首尾相接，复合成一条从 $baaba$ 到 $babaa$ 的 rewrite path。图的原貌见官方 PDF 对应章节。

### The algebra of rewriting.

为了确保 term equivalence relation 最终满足所需的公理，我们在 rewrite step 与 rewrite path 上引入若干代数运算，分别叫 inversion、composition 与 whiskering。

**定义.** rewrite step $s:=x(u\Rightarrow v)y$ 的**逆**（记作 $s^{-1}$）定义为 $x(v\Rightarrow u)y$，也就是把 $u$ 和 $v$ 对调。positive rewrite step 的逆是 negative 的，反之亦然；这意味着 rewrite graph 里的边总是成对互补地出现：

```
              x(u⇒v)y
          ╭───────────────⇒╮
  xuy ────┤                ├──── xvy
          ╰⇐───────────────╯
              x(v⇒u)y
```

> 译注：原书此处是一张 tikzcd 交换图（两个顶点之间一上一下两条弯边，方向相反），这里用 Unicode 箭头图转述；这张图断言的是：$xuy$ 与 $xvy$ 之间的边成对出现，上边由 $x(u\Rightarrow v)y$ 从左指向右，下边由 $x(v\Rightarrow u)y$ 从右指回左。图的原貌见官方 PDF 对应章节。

我们同样可以对一条 rewrite **path** 取逆，得到一条撤销原 path 所作变换的新 path。empty rewrite path 的逆是它自己。对非空的 rewrite path，我们把每一个 rewrite step 取逆，再按相反的顺序执行：

$$p^{-1}:=\begin{cases}
1_t&\text{if } p=1_t\\
s_n^{-1}\circ\cdots\circ s_1^{-1}&\text{if } p=s_1\circ\cdots\circ s_n
\end{cases}
$$

画在 rewrite graph 里，逆 path $p^{-1}$ 就是把 $p$ 倒过来走：

```
           s₁            ⋯             sₙ
  src(p) ⇐══════ ⋯ ⇐══════ ⋯ ⇐══════ dst(p)
```

> 译注：原书此处是一张 tikzcd 交换图（与前面 rewrite path 那张同形，但所有箭头反向），这里用 Unicode 箭头图转述；这张图断言的是：$p^{-1}$ 逐步撤销 $p$，起点与终点互换。图的原貌见官方 PDF 对应章节。

我们可以把 rewrite step 看成长度为 1 的 rewrite path。于是，若 $p$ **既可以是** rewrite step **也可以是** rewrite path，那么取逆这件事就是把它的 source 与 destination 对调：

$$
\begin{gathered}
\operatorname{src}(p^{-1})=\operatorname{dst}(p)\\
\operatorname{dst}(p^{-1})=\operatorname{src}(p)
\end{gathered}
$$

**例.** 我们在上一个例子里给出过这条 rewrite path，source 是 $baaba$、destination 是 $babaa$：

```
            ba(ab⇒ε)a           b(ε⇒ab)aa
  baaba ══════════════⇒ baa ══════════════⇒ babaa
```

把两个 step 各自取逆、再把施加顺序对调，就构造出从 $babaa$ 回到 $baaba$ 的逆 rewrite path：

```
            b(ab⇒ε)aa           ba(ε⇒ab)a
  babaa ══════════════⇒ baa ══════════════⇒ baaba
```

> 译注：原书此处是两张 tikzcd 交换图（原 path 与它的逆），这里用 Unicode 箭头图转述；这两张图断言的是：逆 path 走的是同样两步，但每步取逆、顺序颠倒，因此起点与终点互换。图的原貌见官方 PDF 对应章节。

**定义.** 若 $p_1$ 与 $p_2$ 是两条满足 $\operatorname{dst}(p_1)=\operatorname{src}(p_2)$ 的 rewrite path，我们把它们的**复合** $p_1 \circ p_2$ 定义为这样一条 rewrite path：初始 term 取 $p_1$ 的，接着是 $p_1$ 的各个 rewrite step，最后是 $p_2$ 的各个 step。这给出一条新的 rewrite path，source 与 $p_1$ 相同、destination 与 $p_2$ 相同：

$$
\begin{gathered}
\operatorname{src}(p_1 \circ p_2) = \operatorname{src}(p_1)\\
\operatorname{dst}(p_1 \circ p_2) = \operatorname{dst}(p_2)
\end{gathered}
$$

画成图，复合就是把两条 path 接起来（中间那个 $=$ 不是图里的边，只是表示这两个 term 相同）：

```
  src(p₁) ══⇒ ⋯ ══⇒ (dst(p₁) = src(p₂)) ══⇒ ⋯ ══⇒ dst(p₂)
```

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；这张图断言的是：只要 $p_1$ 的终点与 $p_2$ 的起点是同一个 term，两条 path 就能在那一点接上，拼成一条更长的 path。图的原貌见官方 PDF 对应章节。

empty rewrite path 在复合下起 identity 的作用：

$$
\begin{gathered}
1_{\operatorname{src}(p)}\circ p = p\\
p\circ 1_{\operatorname{dst}(p)} = p
\end{gathered}
$$

复合的逆等于各自的逆按相反顺序复合：

$$(p_1 \circ p_2)^{-1} = p_2^{-1} \circ p_1^{-1}$$

最后，rewrite path 的复合满足结合律。若 $p_3$ 是另一条满足 $\operatorname{dst}(p_2)=\operatorname{src}(p_3)$ 的 rewrite path：

$$p_1 \circ (p_2 \circ p_3) = (p_1 \circ p_2) \circ p_3$$

**例.** 接着上一个例子。考虑 bicyclic monoid 里下面这两条 rewrite path，记作 $p_1$ 与 $p_2$：

```
            ba(ab⇒ε)b          b(ab⇒ε)
  baabb ══════════════⇒ bab ══════════⇒ b

            a(ab⇒ε)bb          (ab⇒ε)b
  aabbb ══════════════⇒ abb ══════════⇒ b
```

这两条 path 的 destination 同为 $b$，但 source 不同。若把第二条取逆再与第一条复合，就得到 rewrite path $p_1 \circ p_2^{-1}$，它把 $baabb$ 变换成 $aabbb$：

```
            ba(ab⇒ε)b          b(ab⇒ε)        (ε⇒ab)b         a(ε⇒ab)bb
  baabb ══════════════⇒ bab ══════════⇒ b ══════════⇒ abb ══════════════⇒ aabbb
```

> 译注：原书此处是两张 tikzcd 交换图（前一张含上下两行，即 $p_1$ 与 $p_2$；后一张是 $p_1 \circ p_2^{-1}$），这里用 Unicode 箭头图转述；这两张图断言的是：两条终点相同的 path，可以把其中一条反过来走，拼成一条连接两个起点的 path。图的原貌见官方 PDF 对应章节。

**定义.** 若 $s:=x(u\Rightarrow v)y$ 且 $z\in A^*$，我们定义 $z$ 对 $s$ 的左、右 **whiskering** 作用。whiskering 通过加长 whisker 来延展一个 rewrite step：

$$
\begin{gathered}
z\triangleleft s := zx(u\Rightarrow v)y\\
s\triangleright z := x(u\Rightarrow v)yz
\end{gathered}
$$

whiskering 运算按如下方式推广到 rewrite path：先把 monoid 运算施加到初始 term 上，再给每个 rewrite step 加 whisker。若 path 是空的，whiskering 就在一个新的 term 上产生另一条 empty rewrite path：

$$
\begin{gathered}
z\triangleleft 1_t = 1_{z\cdot t}\\
1_t\triangleright z = 1_{t\cdot z}
\end{gathered}
$$

若 path 非空，**分配律**把 path 的 whiskering 与 step 的 whiskering 联系起来：

$$
\begin{gathered}
z\triangleleft (s_1\circ\cdots\circ s_n) = (z\triangleleft s_1)\circ\cdots\circ (z\triangleleft s_n)\\
(s_1\circ\cdots\circ s_n)\triangleright z = (s_1\triangleright z)\circ\cdots\circ (s_n\triangleright z)
\end{gathered}
$$

下面是 $z\triangleleft p$ 与 $p\triangleright z$ 的图示：

```
                 z◁s₁                        z◁sₙ
  z·src(p) ══════════⇒ z⋯ ══════⇒ z⋯ ══════════⇒ z·dst(p)

                 s₁▷z                        sₙ▷z
  src(p)·z ══════════⇒ ⋯z ══════⇒ ⋯z ══════════⇒ dst(p)·z
```

> 译注：原书此处是一张含两行的 tikzcd 交换图，这里用 Unicode 箭头图转述；这张图断言的是：whiskering 不改变 path 的形状（步数与顺序原样保留），只是把 $z$ 统一贴在每个中间 term 的左侧或右侧。图的原貌见官方 PDF 对应章节。

再一次，若让 $p$ 既可指 rewrite path 也可指单个 rewrite step，就会看到 whiskering 与 $A^*$ 的 monoid 运算有两方面的关联：

$$
\begin{gathered}
\operatorname{src}(z\triangleleft p)=z\cdot \operatorname{src}(p)\\
\operatorname{dst}(z\triangleleft p)=z\cdot \operatorname{dst}(p)\\[6pt]
\operatorname{src}(p\triangleright z)=\operatorname{src}(p)\cdot z\\
\operatorname{dst}(p\triangleright z)=\operatorname{dst}(p)\cdot z
\end{gathered}
$$

另外，若 $z^\prime\in A^*$ 是另一个 term：

$$
\begin{gathered}
z\triangleleft (z^\prime \triangleleft p)=(z\cdot z^\prime) \triangleleft p\\
(p\triangleright z)\triangleright z^\prime=p\triangleright (z\cdot z^\prime)
\end{gathered}
$$

左、右 whiskering 作用彼此相容：

$$(z\triangleleft p)\triangleright z^\prime = z\triangleleft(p\triangleright z^\prime)$$

最后，分配律从 rewrite step 推广到 rewrite path：

$$
\begin{gathered}
z\triangleleft (p_1 \circ p_2) = (z\triangleleft p_1) \circ (z\triangleleft p_2)\\
(p_1 \circ p_2)\triangleright z = (p_1\triangleright z) \circ (p_2\triangleright z)
\end{gathered}
$$

**命题.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，$P$ 是 $\langle A \mid R\rangle$ 的 rewrite path 全体。下列公理刻画了 $P$：

1. （基础情形）对每个 $(u,v)\in R$，存在一条「初等」rewrite path $(u\Rightarrow v)\in P$。
2. （对取逆封闭）若 $p\in P$，则 $p^{-1}\in P$。
3. （对复合封闭）若 $p_1,p_2\in P$ 且 $\operatorname{dst}(p_1)=\operatorname{src}(p_2)$，则 $p_1\circ p_2\in P$。
4. （对 whiskering 封闭）若 $p\in P$ 且 $z\in A^*$，则 $z\triangleleft p,\ p\triangleright z\in P$。

**证明.** 由 rewrite step 的定义，对每个 $(u,v)\in R$ 都存在一个 positive rewrite step $(u\Rightarrow v)$。又因为每个 rewrite step 同时也是一条长度为 1 的 rewrite path，(1) 得证。另外，rewrite step 对取逆与 whiskering 封闭，这就为长度为 1 的 rewrite path 建立了 (2) 与 (4)。(2)、(3)、(4) 的一般情形可以对 rewrite path 的长度作归纳得到。

回忆一下，$x\sim_R y$ 意思是我们的 rewrite graph 里有一条从 $x$ 到 $y$ 的 path。

**命题.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，则 $\sim_R$ 是 $A^*$ 上的一个**等价关系**。

**证明.** 设 $P$ 是 $\langle A \mid R\rangle$ 的 rewrite path 全体。逐条检查公理。

1. （自反性）对每个 $x\in A^*$，存在 empty rewrite path $1_x\in P$。由于 $\operatorname{src}(1_x)=\operatorname{dst}(1_x)=x$，故 $x\sim x$。
2. （对称性）假设 $x\sim y$，则存在 $p\in P$ 使得 $x=\operatorname{src}(p)$、$y=\operatorname{dst}(p)$。由于 $P$ 对取逆封闭，$p^{-1}\in P$。而 $y=\operatorname{src}(p^{-1})$、$x=\operatorname{dst}(p^{-1})$，故 $y\sim x$。
3. （传递性）假设 $x\sim y$ 且 $y\sim z$。则存在 $p_1\in P$ 使 $x=\operatorname{src}(p_1)$、$y=\operatorname{dst}(p_1)$，以及 $p_2\in P$ 使 $y=\operatorname{src}(p_2)$、$z=\operatorname{dst}(p_2)$。于是 $\operatorname{dst}(p_1)=\operatorname{src}(p_2)$，而 $P$ 对复合封闭，故 $p_1\circ p_2 \in P$。又知：

$$
\begin{gathered}
\operatorname{src}(p_1\circ p_2)=\operatorname{src}(p_1)=x\\
\operatorname{dst}(p_1\circ p_2)=\operatorname{dst}(p_2)=z
\end{gathered}
$$

因此 $x\sim z$。

注意上面我们用到了取逆与复合，但没有用到 whiskering。

接下来我们就用 whiskering 来证明 $\sim$ 与 term 拼接是**相容**的：

**定义.** 设 $M$ 是一个 monoid。一个关系 $R\subseteq M\times M$ 称为 **translation-invariant** 的，若对所有 $(x,y)\in R$ 与 $z\in M$，都有 $(zx,zy)\in R$ 且 $(xz,yz)\in R$。

translation-invariant 的等价关系又叫 **monoid congruence**。

**例.** 考虑 monoid $(\mathbb{N},+,0)$。$\mathbb{N}$ 上标准的**线性序** $<$ 是 translation-invariant 的（但它不是等价关系）。例如 $5<7$ 也蕴涵 $5+2<7+2$。（可见这里的「translation」用的是几何意义上的「平移」。）

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，则 term equivalence relation $\sim_R$ 是一个 monoid congruence。

**证明.** 我们已经看到 $\sim$ 是等价关系，剩下的只需建立 translation invariance。设 $P$ 是 $\langle A \mid R\rangle$ 的 rewrite path 全体。假设 $x,y,z\in A^*$ 且 $x\sim y$，于是有 $p\in P$ 使 $x=\operatorname{src}(p)$、$y=\operatorname{dst}(p)$。我们必须证明 $zx\sim zy$ 与 $xz\sim yz$。对第一个断言，注意到 $z\triangleleft p\in P$，因此 $zx\sim zy$：

$$
\begin{gathered}
\operatorname{src}(z\triangleleft p)=z\cdot \operatorname{src}(p)=zx\\
\operatorname{dst}(z\triangleleft p)=z\cdot \operatorname{dst}(p)=zy
\end{gathered}
$$

要证明 $xz \sim yz$，改看 $p\triangleright z$ 即可。

于是，$\sim_R$ 的**等价类全体**就带上了 monoid 的结构：

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation。term 拼接在 $\sim_R$ 的等价类上是 **well-defined** 的；也就是说，若各取一个代表元 term 拼接起来，结果所在的等价类不依赖于代表元的选取。

**证明.** 假设给定 $x,x^\prime,y,y^\prime\in A^*$ 满足 $x\sim x^\prime$ 且 $y\sim y^\prime$。我们必须证明 $xy\sim x^\prime y^\prime$。由假设，存在一对 rewrite path $p_x$、$p_y$ 满足：

$$
\begin{gathered}
\operatorname{src}(p_x)=x\\
\operatorname{dst}(p_x)=x^\prime\\[6pt]
\operatorname{src}(p_y)=y\\
\operatorname{dst}(p_y)=y^\prime
\end{gathered}
$$

现在，对 $p_x$ 与 $p_y$ 作 whiskering 再复合，构造出 rewrite path $p := (p_x\triangleright y) \circ (x^\prime\triangleleft p_y)$。这个复合是合法的：

$$
\begin{gathered}
\operatorname{dst}(p_x\triangleright y)=\operatorname{dst}(p_x)\cdot y=x^\prime\cdot y\\
\operatorname{src}(x^\prime\triangleleft p_y)=x^\prime\cdot\operatorname{src}(p_y)=x^\prime\cdot y
\end{gathered}
$$

还有：

$$
\begin{gathered}
\operatorname{src}(p) = \operatorname{src}(p_x\triangleright y) = \operatorname{src}(p_x)\cdot y = x\cdot y\\
\operatorname{dst}(p) = \operatorname{dst}(x^\prime\triangleleft p_y) = x^\prime \cdot \operatorname{dst}(p_y) = x^\prime\cdot y^\prime
\end{gathered}
$$

这条 rewrite path 的存在就确立了 $xy\sim x^\prime y^\prime$。图示的证明见下图。

**图：term 拼接在 $\sim$ 的等价类上是 well-defined 的**

```
     x                         x·y
     ⇓                          ⇓
     ⋯                          ⋯                      x·y
     ⇓                          ⇓                       ⇓
     x′       ──whiskering──→   x′·y    ──composition──→ ⋯
                                                         ⇓
     y                         x′·y                     x′·y
     ⇓                          ⇓                        ⇓
     ⋯                          ⋯                        ⋯
     ⇓                          ⇓                        ⇓
     y′                        x′·y′                    x′·y′
```

> 译注：原书此处是一张跨页插图（`figure` 环境），由五张竖排的 tikzcd 交换图分三组组成，组间用带标签的横箭头 `whiskering` / `composition` 相连；这里用 Unicode 箭头图转述。这张图断言的是：先把 $x\Rightarrow x^\prime$ 整条 path 右接 whisker $y$、把 $y\Rightarrow y^\prime$ 整条 path 左接 whisker $x^\prime$，两条新 path 在 $x^\prime\cdot y$ 处接得上，复合后就是一条从 $x\cdot y$ 到 $x^\prime\cdot y^\prime$ 的 path。图的原貌见官方 PDF 对应章节。

**例.** 可以把这条定理应用到前面那个 bicyclic monoid $\langle a, b \mid ab\sim\varepsilon\rangle$ 上。考虑四个 term $x := baba$、$x^\prime := ba$、$y := a$、$y^\prime := aba$。通过下面两条 rewrite path，我们有 $x\sim x^\prime$ 与 $y\sim y^\prime$：

$$
\begin{gathered}
p_x := b(ab\Rightarrow\varepsilon) a\\
p_y := (\varepsilon\Rightarrow ab) a
\end{gathered}
$$

于是 $(p_x\triangleright a)\circ (ba\triangleleft p_y)$ 就是一条从 $babaa$ 到 $baaba$ 的 rewrite path，说明 $xy\sim x^\prime y^\prime$：

$$b(ab\Rightarrow\varepsilon)aa\circ ba(\varepsilon\Rightarrow ab)a$$

我们最初那个例子表明，bicyclic monoid 能通过「检查一个 term 是否等价于 $\varepsilon$」来编码括号匹配问题。那其实有点儿平凡，因为我们只在单个等价类内部打转，完全没用上 monoid 运算。更漂亮的一手，是用 bicyclic monoid 来给 **stack language** 程序的 **stack effect** 建模。这个编码就要靠 monoid 运算了。

一个 stack language 程序是一串 token，每个 token 要么是 **literal**，要么是 **word**。运行程序时，我们从左到右依次求值每个 token：

1. literal 立刻被压入栈。
2. word 类似于其他语言里的函数：它从栈上弹出若干输入值，处理这些值，然后把零个或多个结果压回栈上。

给每个 token 指派一个 **stack effect**，即一对自然数 $(m,n)$，编码了在栈上求值该 token 所需的输入个数 $m$ 与产出个数 $n$。事实证明，若把每个 stack effect 编码成 bicyclic monoid 里的元素 $b^m a^n$，那么 monoid 运算恰好给出 stack effect 的复合运算。

考虑这样一个 stack language：literal 是整数，word 如下表。

| **Token** | **说明** | **Stack effect** |
|---|---|---|
| 一个 literal | 任意整数值。 | $a$ |
| `neg` | 弹出栈顶，压入它的相反数。 | $ba$ |
| `+` | 从栈上弹出两个值，压入它们的和。 | $b^2a$ |
| `*` | 从栈上弹出两个值，压入它们的积。 | $b^2a$ |
| `dup` | 复制栈顶。 | $ba^2$ |
| `.` | 弹出栈顶并打印出来。 | $b$ |

可以用这个语言求值简单的后缀算术表达式：

```
5 dup * 3 neg + .
```

上面这个程序对栈整体没有影响：在空栈上运行能正确执行完；若栈上本来有值，这些值保持不变。另一方面，我们也可以写 `dup * .` 这样的程序，它要求至少已有一个输入值，否则求值 `dup` 时会试图弹出空栈的栈顶。最后，还可以写 `5 7 + 1` 这样的程序，它不需要输入，但会在栈上留下东西。

不必真的执行，我们就能确定上述每个程序的 stack effect：按上表把每个 token 映成它的 stack effect，然后把它们复合起来。下面这个 monoid 运算的闭式表达式在这里很有用：

$$
b^i a^j \cdot b^k a^l = \begin{cases}
b^{i-j+k} a^l &\text{if } j<k\\
b^i a^{j-k+l} &\text{if } j\geq k
\end{cases}
$$

例如，可以这样算出 `5 dup * 3 neg + .` 的 stack effect，从而确认这个程序对栈没有影响：

$$a\cdot ba^2 \cdot b^2a \cdot a \cdot ba \cdot b^2a \cdot b = \varepsilon$$

由于 monoid 运算满足结合律，可知两个程序**拼接**后的 stack effect 等于它们各自 stack effect 的复合。正因如此，基于栈的语言又叫 **concatenative language**。基于栈的语言的例子有 Forth（Brodie 2004，《Thinking Forth》）、Joy（von Thun）与 Factor（Pestov、Ehrenberg、Groff 2010）。Factor 编译器实现的静态 stack effect 检查器，正是基于我们刚描述的这个思路。

## A Swift Connection

本节要证明，finitely-presented monoid 能以一种非常自然的方式映射到 Swift protocol 上。我们会用到 `generic-signatures.tex` 的 Derived Requirements 一节定义的 derived requirements 形式系统，以及 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节里的一些进一步结果。到这里，两套理论之间的相似之处应该已经很明显了，即便概念并不完全重合：

| **Swift generics** | **F-P monoids** |
|---|---|
| Type parameter | Term |
| Explicit requirement | Rewrite rule |
| Derived requirement | Rewrite path |
| Reduced type equality | Term equivalence |
| Type parameter graph | Cayley graph |

> 译注：这张对照表正是本库站在哪一端的说明。表右边那一列（term、rewrite rule、rewrite path）是编译器**求解**阶段的东西，本库一概不做；本库消费的是左边那一列**已经算完之后**的产物——二进制里的 requirement 已经 minimize 过，type parameter 已经是 reduced form，`__swift5_types` / opaque descriptor 里逐字节读出来的就是最终答案。读 reduced type 与 canonical 顺序那一路见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

### Free monoids.

下面这个 protocol——更准确地说，是它的 **protocol generic signature** $G_\texttt{M}$——给两个 generator 的 free monoid $\{a,b\}^*$ 建了模：

```swift
protocol M {
  associatedtype A: M
  associatedtype B: M
}
```

我们定义一个函数 $\varphi$，把 $\{a,b\}^*$ 的每个元素送到 $G_\texttt{M}$ 的一个 type parameter：对每个 $a$ 和 $b$ 递归地构造一层 dependent member type，直到最后剩下空 term，它变成 protocol 的 `Self` 类型：

$$
\begin{gathered}
\varphi(\varepsilon):=\texttt{Self}\\
\varphi(ua):=\varphi(u)\texttt{.A}\\
\varphi(ub):=\varphi(u)\texttt{.B}
\end{gathered}
$$

例如，四个长度为 2 的不同 term 映到下面这些 type parameter：

$$
\begin{gathered}
\varphi(aa)=\texttt{Self.A.A}\\
\varphi(ab)=\texttt{Self.A.B}\\
\varphi(ba)=\texttt{Self.B.A}\\
\varphi(bb)=\texttt{Self.B.B}
\end{gathered}
$$

`M` 的 requirement signature 还声明了两条 **associated conformance requirement**：

$$
\begin{gathered}
[\texttt{Self.A: M}]_\texttt{M}\\
[\texttt{Self.B: M}]_\texttt{M}
\end{gathered}
$$

这两条 requirement 带来的结果是：$\varphi$ 输出的每个 type parameter 都是 $G_\texttt{M}$ 的合法 type parameter，而且每个这样的 type parameter 也都 conform 到 `M`：

**命题.** 若 $t\in \{a,b\}^*$ 且 $\texttt{T}:=\varphi(t)$，则 $G_\texttt{M}\vdash\texttt{T}$ 且 $G_\texttt{M}\vdash[\texttt{T: M}]$。

**证明.** 对 $t$ 的长度作**归纳**。

**基础情形.** 若 $\lvert t\rvert=0$，则 $t=\varepsilon$，而 $\varphi(\varepsilon)=\texttt{Self}$。我们可以用一条 $\mathsf{Generic}$ 初等语句导出 `Self`：

$$
\begin{aligned}
1.&\quad \texttt{Self} &&(\mathsf{Generic})
\end{aligned}
$$

同样地，用一条 $\mathsf{Conf}$ 初等语句得到 conformance：

$$
\begin{aligned}
2.&\quad [\texttt{Self: M}] &&(\mathsf{Conf})
\end{aligned}
$$

**归纳步骤.** 我们知道对某个 $u\in A^*$ 有 $t=ua$ 或 $t=ub$，令 $\texttt{U}:=\varphi(u)$。由归纳假设，$G_\texttt{M}\vdash\texttt{U}$ 且 $G_\texttt{M}\vdash[\texttt{U: M}]$（实际上只需要后者）。首先，对 $[\texttt{U: M}]$ 应用 $\mathsf{AssocName}$ 推理规则，导出 `U.A` 或 `U.B`：

$$
\begin{aligned}
1.&\quad [\texttt{U: M}] &&(\ldots)\\
2.&\quad \texttt{U.A} &&(\mathsf{AssocName}\ 1)\\
3.&\quad \texttt{U.B} &&(\mathsf{AssocName}\ 1)
\end{aligned}
$$

要从 $[\texttt{U: M}]$ 导出 $[\texttt{U.A: M}]$ 或 $[\texttt{U.B: M}]$，就对相应的 associated requirement 应用 $\mathsf{AssocConf}$ 推理规则：

$$
\begin{aligned}
1.&\quad [\texttt{U: M}] &&(\ldots)\\
2.&\quad [\texttt{U.A: M}] &&(\mathsf{AssocConf}\ 1)\\
3.&\quad [\texttt{U.B: M}] &&(\mathsf{AssocConf}\ 1)
\end{aligned}
$$

归纳完成。

我们希望给 $G_\texttt{M}$ 的 type parameter 配上 monoid 结构。identity element 取 `Self`，因为它就是 $\varphi(\varepsilon)$。

二元运算 $\cdot$ 由**形式代入**（formal substitution）定义：把右边那个 type parameter 里的 `Self` 换成左边那整个 type parameter。看看 `Self.A.A` 与 `Self.B.B` 这两个 type parameter：

$$(\texttt{Self.A.A})\cdot(\texttt{Self.B.B})=\texttt{Self.A.A.B.B}$$

为了确保这给出的是合法的 type parameter，我们求助于 `building-generic-signatures.tex` 的 Formal substitution 引理。假设给定两个合法 type parameter $G_\texttt{M}\vdash\texttt{U}$ 与 $G_\texttt{M}\vdash\texttt{V}$。由上面那条命题，$G_\texttt{M}\vdash[\texttt{U: M}]$。Formal substitution 引理的条件得到满足，因此 $G_\texttt{M}\vdash\texttt{U}\cdot\texttt{V}$。

现在我们有了一个元素集合、一个二元运算和一个 identity element。最后一个问题是：这个 monoid 在什么意义上「等同于」free monoid $\{a,b\}^*$？答案在于 $\varphi$ 是一个 monoid 的**同构**。

**定义.** 设 $M$ 与 $N$ 是 monoid。

1. 一个 **monoid homomorphism** 是把 identity 送到 identity、且与二元运算相容的函数 $f\colon M\rightarrow N$。也就是说，$f(\varepsilon_M)=\varepsilon_N$，且对所有 $x,y\in M$ 有 $f(x\cdot_M y)=f(x)\cdot_N f(y)$。
2. 一个 **monoid isomorphism** 是存在逆 $f^{-1}$ 的 monoid homomorphism $f$，即对所有 $x\in M$ 有 $f^{-1}(f(x))=x$，对所有 $x\in N$ 有 $f(f^{-1}(f(x))=x$。此时我们也说 $M$ 与 $N$ **同构**。

> 译注：原书第 2 条里的第二个等式写成 $f(f^{-1}(f(x))=x$，括号不配对且多了一层 $f$；按 isomorphism 的标准定义，这里应为 $f(f^{-1}(x))=x$（对所有 $x\in N$）。疑为笔误，以标准定义为准。

我们已经看到 $\varphi$ 把 $\{a,b\}^*$ 的 identity element $\varepsilon$ 送到 $G_\texttt{M}$ 的 identity element `Self`。它也保持 monoid 运算。例如：

$$
\begin{aligned}
&\varphi(aa)\cdot\varphi(bb)\\
&\quad =(\texttt{Self.A.A})\cdot(\texttt{Self.B.B})\\
&\quad =\texttt{Self.A.A.B.B}\\
&\quad =\varphi(aabb)
\end{aligned}
$$

最后，存在一个逆映射 $\varphi^{-1}$，把 $G_\texttt{M}$ 的 type parameter 送回 $\{a,b\}^*$ 的元素：

$$
\begin{gathered}
\varphi^{-1}(\texttt{Self}):=\varepsilon\\
\varphi^{-1}(\texttt{U.A}):=\varphi^{-1}(\texttt{U})\cdot a\\
\varphi^{-1}(\texttt{U.B}):=\varphi^{-1}(\texttt{U})\cdot b
\end{gathered}
$$

我们证明了 $G_\texttt{M}$ 的 type parameter 带有一个同构于 $\{a,b\}^*$ 的 monoid 结构。更进一步，整个构造并不依赖于恰好有两个 generator；我们可以按需在 `M` 里增删 associated type 声明。例如，把这个构造用在单 generator 的 free monoid 上，得到的就是 `archetypes.tex` 里的 protocol `N`。那个 monoid 同构于 $(\mathbb{N},+,0)$，这也解释了 `N` 这个名字的由来。

### Finitely-presented monoids.

我们把编码从 free monoid $A^*$ 推广到 finitely-presented monoid $\langle A \mid R\rangle$。先取一个编码 $A^*$ 的 protocol `M`，然后对每个 $(u,v)\in R$，把 $\varphi$ 分别作用到 $u$ 与 $v$ 上，得到一条 **associated same-type requirement** $[\varphi(u) == \varphi(v)]_\texttt{M}$。最后，给 `M` 挂一个 trailing `where` 子句，在其中写下这些 requirement。拿前面那个 bicyclic monoid $\langle a, b \mid ab\sim\varepsilon\rangle$ 试一下：

```swift
protocol M {
  associatedtype A: M
  associatedtype B: M where Self.A.B == Self
}
```

`M` 的 same-type requirement 使得 protocol generic signature $G_\texttt{M}$ 在 **reduced type equality** 关系下具有非平凡的等价类结构。

**例.** 回忆前面那个例子：在 bicyclic monoid 里 $baaba\sim babaa$，而 $ba(ab\Rightarrow\varepsilon)a \circ b(\varepsilon\Rightarrow ab)aa$ 是从 $baaba$ 到 $babaa$ 的一条可行 rewrite path。设 `M` 是编码这个 monoid 的 protocol。把每个 rewrite step 逐一翻译，就能构造出 $G_\texttt{M}\vdash[\texttt{Self.B.A.A.B.A == Self.B.A.B.A.A}]$ 的一个 derivation：

$$
\begin{aligned}
&ba(ab\Rightarrow\varepsilon)a && G_\texttt{M}\vdash[\texttt{Self.B.A.A.B.A == Self.B.A.A}]\\
&b(\varepsilon\Rightarrow ab)aa && G_\texttt{M}\vdash[\texttt{Self.B.A.A == Self.B.A.B.A.A}]
\end{aligned}
$$

第一个 rewrite step $ba(ab\Rightarrow\varepsilon)a$ 证明了 $baaba$ 与 $baa$ 之间的等价。我们一块一块地搭 derivation，先从左 whisker $ba$ 开始：

$$
\begin{aligned}
1.&\quad [\texttt{Self: M}] &&(\mathsf{Conf})\\
2.&\quad [\texttt{Self.B: M}] &&(\mathsf{AssocConf}\ 1)\\
3.&\quad [\texttt{Self.B.A: M}] &&(\mathsf{AssocConf}\ 2)
\end{aligned}
$$

接着应用 $\mathsf{AssocSame}$ 推理规则，得到 $ba(ab\Rightarrow\varepsilon)$：

$$
\begin{aligned}
4.&\quad [\texttt{Self.B.A.A.B == Self.B.A}] &&(\mathsf{AssocSame}\ 3)
\end{aligned}
$$

最后应用 $\mathsf{SameName}$ 推理规则，得到 $ba(ab\Rightarrow\varepsilon)a$：

$$
\begin{aligned}
5.&\quad [\texttt{Self.B.A.A.B.A == Self.B.A.A}] &&(\mathsf{SameName}\ 3\ 4)
\end{aligned}
$$

第二个 rewrite step $b(\varepsilon\Rightarrow ab)aa$ 证明了 $baa$ 与 $babaa$ 之间的等价。上面的一些 derivation step 可以复用，先得到 $b(\varepsilon\Rightarrow ab)$：

$$
\begin{aligned}
6.&\quad [\texttt{Self.B.A.B == Self.B}] &&(\mathsf{AssocSame}\ 2)\\
7.&\quad [\texttt{Self.B == Self.B.A.B}] &&(\mathsf{Sym}\ 6)
\end{aligned}
$$

接着搭出 $b(\varepsilon\Rightarrow ab)a$：

$$
\begin{aligned}
8.&\quad [\texttt{Self.B.A.B: M}] &&(\mathsf{AssocConf}\ 3)\\
9.&\quad [\texttt{Self.B.A == Self.B.A.B.A}] &&(\mathsf{SameName}\ 8\ 7)
\end{aligned}
$$

再加一个 $a$，就得到 $b(\varepsilon\Rightarrow ab)aa$：

$$
\begin{aligned}
10.&\quad [\texttt{Self.B.A.B.A: M}] &&(\mathsf{AssocConf}\ 8)\\
11.&\quad [\texttt{Self.B.A.A == Self.B.A.B.A.A}] &&(\mathsf{SameName}\ 10\ 9)
\end{aligned}
$$

最后用 $\mathsf{Trans}$ 把两个 rewrite step 复合起来，大功告成：

$$
\begin{aligned}
12.&\quad [\texttt{Self.B.A.A.B.A == Self.B.A.B.A.A}] &&(\mathsf{Trans}\ 9\ 11)
\end{aligned}
$$

> 译注：原书这一步的前提写作「$\mathsf{Trans}$ 9 11」，但第 9 步的结论是 $[\texttt{Self.B.A == Self.B.A.B.A}]$，与第 11 步接不上；能与第 11 步复合出第 12 步结论的是第 **5** 步 $[\texttt{Self.B.A.A.B.A == Self.B.A.A}]$。疑为笔误，应以「$\mathsf{Trans}$ 5 11」为准。

现在我们来证明：对任意 monoid presentation $\langle A \mid R\rangle$，对应的 generic signature $G_\texttt{M}$ 与 $\sim_R$ 具有相同的等价类结构：

1. 若 $x\sim y$，则 $\varphi(x)$ 与 $\varphi(y)$ 在 $G_\texttt{M}$ 中是等价的 type parameter。
2. 若 $\varphi(x)$ 与 $\varphi(y)$ 在 $G_\texttt{M}$ 中是等价的 type parameter，则 $x\sim y$。

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，`M` 是编码 $\langle A \mid R\rangle$ 的 protocol。则对所有 $x,y\in A^*$，$x\sim_R y$ 蕴涵 $G_\texttt{M}\vdash[\varphi(x) == \varphi(y)]$。

**证明.** 给定一条满足 $\operatorname{src}(p)=x$、$\operatorname{dst}(p)=y$ 的 rewrite path $p$，我们必须构造出 $G_\texttt{M}\vdash[\varphi(x) == \varphi(y)]$ 的一个 derivation。对 rewrite path $p$ 的长度作**归纳**。

**基础情形.** 我们有一条 empty rewrite path，即对某个 $t\in A^*$ 有 $p=1_t$。用上面那条命题构造出 $G_\texttt{M}\vdash\varphi(t)$ 的 derivation，然后应用 $\mathsf{Reflex}$ 推理规则导出 $[\varphi(t) == \varphi(t)]$：

$$
\begin{aligned}
1.&\quad \varphi(t) &&(\ldots)\\
2.&\quad [\varphi(t) == \varphi(t)] &&(\mathsf{Reflex}\ 1)
\end{aligned}
$$

**归纳步骤.** 假设 $p$ 的长度至少为 1，于是 $p=p^\prime \circ s$，其中 $p^\prime$ 是一条更短的 rewrite path、$s$ 是一个 rewrite step。设 $s = t(u\Rightarrow v)w$，其中 $t,w\in A^*$，且 $(u,v)$ 或 $(v,u)\in R$。看看 $p^\prime$ 与 $s$ 的 source 和 destination：

$$
\begin{aligned}
&\operatorname{src}(p^\prime)=x &&\operatorname{src}(s) = tuw\\
&\operatorname{dst}(p^\prime)=tuw &&\operatorname{dst}(s) = tvw=y
\end{aligned}
$$

由归纳假设，$G_\texttt{M}\vdash[\varphi(x) == \varphi(tuw)]$。剩下的是构造 $G_\texttt{M}\vdash[\varphi(tuw) == \varphi(tvw)]$ 的 derivation。为此先构造 $G_\texttt{M}\vdash[\varphi(tu) == \varphi(tv)]$。

由上面那条命题，$G_\texttt{M}\vdash[\varphi(t): \texttt{M}]$。现在看 $s$ 的方向：

1. 若 $s$ 是 positive 的，则 `M` 声明了一条 associated same-type requirement $[\varphi(u) == \varphi(v)]_\texttt{M}$。对 $[\varphi(t): \texttt{M}]$ 应用 $\mathsf{AssocSame}$，就得到 $G_\texttt{M}\vdash[\varphi(tu) == \varphi(tv)]$。
2. 若 $s$ 是 negative 的，$\mathsf{AssocSame}$ 给出的是 $G_\texttt{M}\vdash[\varphi(tv) == \varphi(tu)]$，于是再用 $\mathsf{Sym}$ 推理规则得到 $G_\texttt{M}\vdash[\varphi(tu) == \varphi(tv)]$。

接着，那条命题又给出 $G_\texttt{M}\vdash\varphi(w)$。既然有 $G_\texttt{M}\vdash[\varphi(tu) == \varphi(tv)]$ 与 $G_\texttt{M}\vdash\varphi(w)$，Formal substitution 引理就蕴涵 $G_\texttt{M}\vdash[\varphi(tuw) == \varphi(tvw)]$。

最后，用 $\mathsf{Trans}$ 导出 $G_\texttt{M}\vdash[\varphi(x) == \varphi(y)]$（回忆 $y=tvw$）：

$$
\begin{aligned}
1.&\quad [\varphi(x) == \varphi(tuw)] &&(\ldots)\\
2.&\quad [\varphi(tuw) == \varphi(y)] &&(\ldots)\\
3.&\quad [\varphi(x) == \varphi(y)] &&(\mathsf{Trans}\ 1\ 2)
\end{aligned}
$$

于是，每条 rewrite path 都映射到 $G_\texttt{M}$ 的一条 derived same-type requirement。

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，`M` 是编码 $\langle A \mid R\rangle$ 的 protocol。则对所有 $x,y\in A^*$，$G_\texttt{M}\vdash[\varphi(x) == \varphi(y)]$ 蕴涵 $x\sim_R y$。

**证明.** 给定 $[\varphi(x) == \varphi(y)]$ 的一个 derivation，我们必须构造一条 source 为 $x$、destination 为 $y$ 的 rewrite path $p$，从而证明 $x\sim y$。我们对 derived requirement 作结构**归纳**。

下面这些 derivation step 会产出 same-type requirement（不过 $\mathsf{Same}$ 在我们这里不会出现，因为 $G_\texttt{M}$ 没有 explicit same-type requirement；所有 same-type requirement 都派生自 `M` 的 requirement signature）：

| | | |
|---|---|---|
| $\mathsf{Same}$ | $\mathsf{AssocSame}$ | $\mathsf{SameName}$ |
| $\mathsf{Reflex}$ | $\mathsf{Sym}$ | $\mathsf{Trans}$ |

每种情形下，我们都必须从该 step 所用的各个假设对应的 rewrite path（若有的话）出发，构造出一条新的 rewrite path $p$，其 source 与 destination 要与该 step 结论里的 same-type requirement 对得上。

**基础情形.** 基础情形是 derivation step 不含任何 same-type requirement 假设、而结论却是某条 same-type requirement 的情况。这样的 step 有两类，两类里我们都直接构造出 rewrite path $p$。

写成下面这种形式的 $\mathsf{AssocSame}$ 推理规则的一次应用，蕴涵我们有一条 rewrite rule $(u,v)\in R$。取 $p:=t(u\Rightarrow v)$：

$$[\varphi(tu) == \varphi(tv)] \qquad (\mathsf{AssocSame}\ [\varphi(t): \texttt{M}])$$

另一个基础情形是 $\mathsf{Reflex}$ step，此时取 $p:=1_t$：

$$[\varphi(t) == \varphi(t)] \qquad (\mathsf{Reflex}\ \varphi(t))$$

**归纳步骤.** $\mathsf{Sym}$ 通过给 rewrite path 取逆来处理。归纳假设给出 $p^\prime$，满足 $\operatorname{src}(p^\prime)=t$、$\operatorname{dst}(p^\prime)=u$。取 $p:=(p^\prime)^{-1}$，因为 $\operatorname{src}(p)=u$、$\operatorname{dst}(p)=t$：

$$[\varphi(u) == \varphi(t)] \qquad (\mathsf{Sym}\ [\varphi(t) == \varphi(u)])$$

$\mathsf{Trans}$ 通过复合来处理。归纳假设给出 $p_1$、$p_2$，满足 $\operatorname{src}(p_1)=t$、$\operatorname{dst}(p_1)=\operatorname{src}(p_2)=u$、$\operatorname{dst}(p_2)=v$。取 $p:=p_1\circ p_2$，因为 $\operatorname{src}(p)=t$、$\operatorname{dst}(p)=v$：

$$[\varphi(t) == \varphi(v)] \qquad (\mathsf{Trans}\ [\varphi(t) == \varphi(u)]\ [\varphi(u) == \varphi(v)])$$

最后，$\mathsf{SameName}$ 通过 whiskering 来处理。这里 $g\in A$ 是一个 generator，对应 `M` 里的一个 associated type 声明。归纳假设给出 $p^\prime$，满足 $\operatorname{src}(p^\prime)=t$、$\operatorname{dst}(p^\prime)=u$。取 $p:=p^\prime\triangleright g$，因为 $\operatorname{src}(p)=tg$、$\operatorname{dst}(p)=ug$：

$$[\varphi(tg) == \varphi(ug)] \qquad (\mathsf{SameName}\ [\varphi(u): \texttt{M}]\ [\varphi(t) == \varphi(u)])$$

于是，$G_\texttt{M}$ 的每条 derived same-type requirement 都映射到一条 rewrite path $p$。

一般来说，Cayley graph 并不被 monoid isomorphism 保持，因为它依赖于 generating set 的选取。不过在我们这套 Swift 编码里，Cayley graph 直接显形了。现在我们知道 `N` 与 `Z4` 分别编码了 monoid $\{a\}^*$ 与 $\langle a \mid a^4\sim\varepsilon\rangle$。前面也已经指出过：

- $\{a\}^*$ 的 Cayley graph 长得像 $G_N$ 的 type parameter graph。
- $\langle a \mid a^4\sim\varepsilon\rangle$ 的 Cayley graph 长得像 $G_\texttt{Z4}$ 的 type parameter graph。

这件事总是成立的；进一步，`conformance-paths.tex` 的 The Conformance Path Graph 一节里的 conformance path graph 在这种情形下也与前两张图重合：

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation，`M` 是编码 $\langle A \mid R\rangle$ 的 protocol。下面三张图彼此同构：

1. $\langle A \mid R\rangle$ 的 Cayley graph。
2. $G_\texttt{M}$ 的 type parameter graph。
3. $G_\texttt{M}$ 的 conformance path graph。

**证明.** 先看每张图的顶点集。我们已经确立了 term 与 type parameter 具有相同的等价类结构。由此可知，三个顶点集之间的差别本质上只是标签的选择：

1. (1) 中的一个顶点是一个 term 等价类：$[\![t]\!]$，其中 $t\in A^*$。
2. (2) 中的一个顶点是一个 type parameter 等价类：$[\![\varphi(t)]\!]$，其中 $t\in A^*$。
3. (3) 中的一个顶点是一个 **abstract conformance** 等价类。由于 $G_\texttt{M}$ 的每个 type parameter 都恰好 conform 到唯一一个 protocol——`M`——故每个 abstract conformance 都形如 $[\varphi(t): \texttt{M}]$，其中 $t\in A^*$。

边集也可以同样地说：

1. (1) 中的一条边把每个 $[\![t]\!]$ 与 $[\![tg]\!]$ 相连，对所有 $g\in A$。
2. (2) 中的一条边把每个 $[\![\varphi(t)]\!]$ 与 $[\![\varphi(t)\texttt{.A}]\!]$ 相连，对 `M` 的所有 associated type `A`。
3. (3) 中的一条边把每个 $[[\![\varphi(t)]\!]: \texttt{M}]$ 与 $[[\![\varphi(t)\texttt{.A}]\!]: \texttt{M}]$ 相连，对 `M` 的所有 associated conformance requirement $[\texttt{Self.A: M}]_\texttt{M}$。

> 译注：原书 (1) 这一条写的是「for all $a\in A$」，但式中用的 generator 记号是 $g$；疑为笔误，此处按 $g\in A$ 译。

最后再说一点。回忆一下：在 monoid presentation $\langle A \mid R\rangle$ 的 Cayley graph 里，每个顶点的后继个数都相同；我们刚刚证明了 $G_\texttt{M}$ 的 type parameter graph 也是如此。反过来，在一个任意的 generic signature 里，顶点的后继个数会各不相同，因为不同等价类会 conform 到各式各样、associated type 也各不相同的 protocol 集合。一个「典型」generic signature 的 type parameter graph 几乎永远不会是某个 monoid 的 Cayley graph。

## The Word Problem

上一节那两条定理（rewrite path 给出 derivation、derivation 给出 rewrite path）告诉我们：我们可以写出一个程序，它能通过类型检查**当且仅当** finitely-presented monoid 里的两个 term 等价。编译器必须有能力验证这个等价，或者在不成立时拒绝该程序。

例如，可以从编码 bicyclic monoid 的那个 protocol 出发，再在 protocol extension 里声明一个方法：

```swift
protocol M {
  associatedtype A: M
  associatedtype B: M where Self.A.B == Self
}

extension M {
  static func testBicyclicMonoid() {
    sameType(Self.B.A.A.B.A.self, Self.B.A.B.A.A.self)  // ok
    sameType(Self.A.A.A.self, Self.B.B.B.self)          // error!
  }
}

func sameType<T>(_: T.Type, _: T.Type) {}
```

调用 `sameType()` 要求两个实参都是 instance type 相同的 metatype。为了让这个程序通过类型检查，编译器必须验证两条语句，分别对应 `sameType()` 的两次调用：

$$
\begin{gathered}
G_\texttt{M}\vdash[\texttt{Self.B.A.A.B.A == Self.B.A.B.A.A}]\\
G_\texttt{M}\vdash[\texttt{Self.B.A.A == Self.B.B.B}]
\end{gathered}
$$

第一条语句为真，因为我们已经见过 $baaba\sim babaa$。然而第二条语句其实是假的，事实上 $baa\not\sim bbb$。编译器接受第一次调用，并在第二次 `sameType()` 调用上诊断出一个错误——正如我们所预期。

事实上，若我们为到目前为止见过的每一个 finitely-presented monoid 例子都写一段类似的程序，Swift 编译器都能替我们正确判定任意两个 term 是否等价。一个自然的问题是：这总是行得通吗？还是说存在某些按这种方式构造出来的 protocol 声明是我们无法接受的？

我们其实是在要求 Swift 编译器解决那个著名的 **word problem**：

- **输入：** 一个 monoid presentation $\langle A \mid R\rangle$，以及两个 term $x,y\in A^*$。

  **结果：** 真或假：$x\sim_R y$？

word problem 大概最早是 20 世纪初由 Axel Thue 提出的。他研究了各种形式系统，其共同点都是「按一组固定规则在更长的串里替换子串」。Thue 在 1914 年的一篇论文里描述了后来被称为 **Thue system** 与 **semi-Thue system** 的东西（英译见 Power 2013，《Thue's 1914 paper: a translation》）。一个 Thue system 就是一个 finitely-presented monoid；而 semi-Thue system 则是把对称的 term equivalence relation 换成 **reduction relation** 之后得到的东西——下一节我们就会研究它。

看起来 Thue 的目标在很多方面与我们相似：把一个形式系统的各条语句编码成某个 finitely-presented monoid 里的 term，使得语句的证明变成一串 rewrite step，从而把关于这个形式系统的问题都转化成 word problem 的实例。剩下的任务就是补上最后那块拼图——然后，瞧，整个数学就被我们解决了。

Thue 在某些受限的实例里确实解出了 word problem。例如，若 rewrite rule 保持 term 长度，那么每个等价类必然是有限的，$x\sim y$ 就可以靠穷举 $[\![y]\!]$ 来判定。然而 Thue 始终没能找到一个在所有情形下都管用的一般方法。

这段故事的下一个转折出现在可计算性理论发展起来之后。我们在 `conformance-paths.tex` 的 The Halting Problem 一节已经勾勒过 Turing machine 与 halting problem，在那里我们看到：在 type substitution 代数里，**termination checking** 这个问题是不可判定的。现在，我们将看到另一个这样的不可判定问题。在 1947 年的一篇论文里，Emil Post 给出了一个证明：不存在任何**有效程序**（effective procedure）能解决 word problem。Post 的做法是定义一套把 Turing machine 编码成 Thue system 的方案。粗略地说，这套编码是这样工作的：

1. 在任一时刻，Turing machine 的完整状态（当前状态符号加上纸带内容）都可以用 finitely-presented monoid 里的一个 term 来描述。
2. 单步转移——机器替换当前读写头位置上的符号并向左或向右移动——定义了这个 monoid 的 rewrite rule。
3. 一次顺序执行定义了一条 rewrite path。若机器停机，我们就知道存在一条从初始状态到停机状态的 rewrite path。于是，Turing machine 停机当且仅当初始状态与停机状态是等价的 term。

如果我们能在**任意**的 finitely-presented monoid 里解决 word problem，那我们也就能解决任意 Turing machine 的 halting problem——矛盾，因此这样的算法不存在。而且结论还更强。不仅不存在那种把 monoid presentation 作为输入一部分的「通用」算法，我们甚至可以构造出一个 word problem 不可判定的**具体**的 finitely-presented monoid。

一条路子是从 Turing 的**通用机**（universal machine）构造出发。这是一台 Turing machine，它一步一步地模拟另一台 Turing machine 的执行，把后者的**标准描述**作为纸带输入接收进来。放到今天，我们大概会把这东西叫「模拟器」或「解释器」。

把 Post 的构造套到一台 universal Turing machine 上，就能得到一个 word problem 不可判定的具体 monoid presentation：因为现在可以把任意 Turing machine 编码成这个具体 monoid 里的一个 term，然后通过解 word problem 来判定这台 Turing machine 是否停机。不过，这个「universal Turing machine」monoid 的 generator 和 rewrite rule 数量相当庞大。

一个简单得多、word problem 同样不可判定的 monoid 出现在 G. S. Tseitin 1958 年的论文《An associative calculus with an insoluble problem of equivalence》里。带注释的英译本见 Nyberg-Brodda 2024。

**定理.** 下面这个 finitely-presented monoid 的 word problem 不可判定：

$$
\begin{aligned}
\mathfrak{C}_1 := \langle a,b,c,d,e \mid\ &ac\sim ca,\,ad\sim da,\,bc\sim cb,\,bd\sim db,\\
&eca\sim ce,\,edb\sim de,\\
&cca\sim ccae\rangle
\end{aligned}
$$

**推论.** 不存在任何有效程序，能判定 protocol generic signature $G_\texttt{C1}$ 里任意两个 type parameter 是否等价：

```swift
protocol C1 {
  associatedtype A: C1
  associatedtype B: C1
  associatedtype C: C1
  associatedtype D: C1
  associatedtype E: C1
    where A.C == C.A, A.D == D.A, B.C == C.B, B.D == D.B,
          E.C.A == C.E, E.D.B == D.E,
          C.C.A == C.C.A.E
}
```

Swift 编译器**拒绝**这个 protocol 并诊断出一个错误：

```
error: cannot build rewrite system for protocol;
rule length limit exceeded
```

错误里的「rule length」指的不是我们写下的那些规则，而是在为 $\mathfrak{C}_1$ 构造 **convergent** presentation 的过程中生成出来的那些规则——这件事我们会在本章 The Normal Form Algorithm 一节谈到。如果我们的 monoid 的 word problem 不可判定，这件事就做不成，而生成这种 presentation 的那套程序会用各种启发式规则来判断何时该放弃。在原书作者的机器上，Swift 编译器处理约 30 毫秒后拒绝了 protocol `C1`。

要理解 $\mathfrak{C}_1$，我们需要引入一个新概念。一个 **special monoid presentation** 是指每条 rewrite rule 的右端都是 $\varepsilon$ 的 presentation；而 **special monoid** 就是拥有这样一个 presentation 的 monoid：

$$\langle a_1, \ldots, a_m \mid u_1 \sim \varepsilon,\, \ldots,\, u_n \sim \varepsilon\rangle$$

前面那个 bicyclic monoid 就是 special 的。每个 group 也都是 special 的，因为有逆运算在——我们总可以把规则 $u\sim v$ 换成 $uv^{-1}\sim\varepsilon$。

Tseitin 的 monoid $\mathfrak{C}_1$ 是一台**求解 special monoid 中 word problem 的通用机**。给定一个 special monoid presentation $\langle A \mid R\rangle$ 和一对 term $x,y\in A^*$，我们可以把 $\langle A \mid R\rangle$、$x$、$y$ 编码成 $\mathfrak{C}_1$ 的 generator 上的三个 term $W$、$X$、$Y$。于是，Tseitin 的关键结果如下：

在 $\langle A \mid R\rangle$ 中 $x\sim y$，当且仅当在 $\mathfrak{C}_1$ 中 $W\!X\sim WY$。

我们来略述一下这套编码：把**12 阶二面体群**（描述正六边形的对称性）里的一个 word problem 编码成 $\mathfrak{C}_1$ 里的一个 word problem。把 $s$ 想成旋转 $60^\circ$，把 $t$ 想成沿某条对称轴的反射：

$$D_{12} := \langle s,t \mid s^6\sim\varepsilon,\, t^2\sim\varepsilon,\, (st)^2\sim \varepsilon\rangle$$

**（第一步。）** 先编码 $D_{12}$ 的 presentation。把 $D_{12}$ 的每条 rewrite rule 翻译成 $\mathfrak{C}_1$ 的一个元素，办法是把 $s$ 换成 $cd$、把 $t$ 换成 $cd^2$（若 $D_{12}$ 还有第三个 generator，它就映到 $cd^3$，依此类推）：

$$
\begin{aligned}
s^6 &\mapsto (cd)^6\\
t^2 &\mapsto (cd^2)^2\\
(st)^2 &\mapsto (cdcd^2)^2
\end{aligned}
$$

**（第二步。）** 在上面每个 term 末尾追加一个 $c$，把它们拼接起来，最后再加一个 $c$。至此我们把 $D_{12}$ 的**presentation** 编码成了 $\mathfrak{C}_1$ 的一个**元素**。这就是我们的 term $W$：

$$
W := \underbrace{(cd)^6}_{s^6}\cdot c\cdot \underbrace{(cd^2)^2}_{t^2}\cdot c\cdot \underbrace{(cdcd^2)^2}_{(st)^2}\cdot c\cdot c
$$

**（第三步。）** 现在从 $D_{12}$ 里挑一对 term。取 $x:=ts$ 与 $y:=s^5t$。先旋转再反射，跟先反射再朝反方向旋转是一回事，所以 $ts\sim s^5t$。我们再次把这两个 term 翻译进 $\mathfrak{C}_1$，只不过这次用 $a$ 和 $b$ 而不是 $c$ 和 $d$。这就给出了 $X$ 与 $Y$：

$$
\begin{gathered}
X := ab^2ab\\
Y := (ab)^5ab^2
\end{gathered}
$$

Tseitin 的 rewrite rule 定义了一条（相当长的）从 $W\!X$ 到 $WY$ 的 rewrite path。

我们这个例子并没有展示出不可判定性，因为 $D_{12}$ 里的 word problem 非常容易解——总共才 12 个元素，把 Cayley table 写出来就完事了。不过，跟 monoid 一样，group 的 word problem 在一般情形下也是不可判定的（Boone 1959，《The Word Problem》；更易读的入门见 Cravitz 2021《An introduction to the word problem for groups》，或 Rotman 1994《An Introduction to the Theory of Groups》第 12 章）。既然 $\mathfrak{C}_1$ 能编码**所有** group 里的 word problem，我们当然不能指望写得出一个解 $\mathfrak{C}_1$ 里 word problem 的算法。

### The big picture.

我们已经证明，每个 finitely-presented monoid 都能编码成一类特定的 Swift protocol，简直就像 Swift 的 protocol 是 finitely-presented monoid 的一种推广似的！不过这对实现 Swift 泛型还没有直接帮助。然而，`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 那一章会说明：只要取一套合适的 alphabet 和 rewrite rule 集合，我们就能反过来走，把任意 Swift generic signature 编码成一个 finitely-presented monoid。虽然 word problem 的不可判定性使我们无法接受**所有**的 generic signature，但下一节将描述一大类 word problem 很容易解的 finitely-presented monoid。一切合理的 generic signature 都落在我们这个模型里。

### Closing remarks.

在 `conformance-paths.tex` 的 The Halting Problem 一节，我们证明了 type substitution 代数能用 recursive conformance requirement（SE-0157）编码任意计算。现在我们看到，用 recursive conformance requirement 加上 protocol 的 `where` 子句（SE-0142），也能在 derived requirements 形式系统里编码一个不可判定问题。

Tseitin 的 monoid 不是 special monoid，所以它无法编码它自己的 word problem。D. J. Collins（1970，《A universal semigroup》）后来发现了一个「更加」通用的 word problem 解释器，只多出几条规则；它能编码 $\mathfrak{C}_1$ 乃至它自身里的 word problem：

$$
\begin{aligned}
\mathfrak{U} := \langle a,b,c,d,e_1,e_2,f,g \mid\ &ac\sim ca,\,ad\sim da,\,af\sim fa,\,ag\sim ga,\\
&bc\sim cb,\, bd\sim db,\, bf\sim fb,\, bg\sim gb,\\
&ce_1\sim ec_1a,\, de_1\sim e_1db,\\
&e_2c\sim cae_2,\, e_2d\sim dbe_2,\\
&e_1g\sim ge_2,\\
&f\sim fe_1,\, e_2f\sim f\rangle
\end{aligned}
$$

> 译注：原书第三行左式写作 $ce_1\sim ec_1a$，右端的下标位置与同组其余规则（$de_1\sim e_1db$、$e_2c\sim cae_2$）不一致，疑为 $ce_1 \sim e_1ca$ 的笔误；此处照译原文，读者若要核对请参 Collins 1970 原文。

## The Normal Form Algorithm

word problem 有一个「朴素」解法：从第一个 term $s$ 出发，尝试各种 rewrite step 的组合，直到走到 $t$。事实上，我们可以把搜索安排得使得：只要这样一条 path 存在，搜索就总能终止并给出相应的 rewrite path。

然而，若这样的 path 并不存在，我们就永远不知道该在何时停手。回忆一下，rewrite rule $(u, v)\in R$ 是一个**对称**的等价。从 $s$ 到 $t$ 的 rewrite path（若存在的话）可能多次用到同一条 rewrite rule，而且在整条 path 上可以往任一方向、甚至两个方向都用。rewrite graph 是无限的，途中经过的那些中间 term 也可能要多长有多长。

```
  s ══╗           ⋯ ══╗
      ╚══⇒ ⋯ ══╗       ╚══⇒ ⋯ ══╗
                ╚══⇒ ⋯          ╚══⇒ t
```

> 译注：原书此处是一张 tikzcd 交换图（上下两排顶点交替、箭头呈锯齿状来回），这里用 Unicode 箭头图转述；这张图断言的是：一条 rewrite path 可以上上下下地绕行，中间 term 时长时短，因此穷举搜索没有可靠的停止判据。图的原貌见官方 PDF 对应章节。

现在我们换个视角，把一条 rewrite rule $(u,v)$ 看成从 $u$ 到 $v$ 的一个**有向归约**（reduction）。也就是说，我们只被允许在 term 中任何出现 $u$ 的地方把它替换成 $v$，反过来不行。回忆一下：rewrite step $x(u\Rightarrow v)y$ 在 $(u,v)\in R$ 时是 positive 的，在 $(v,u)\in R$ 时是 negative 的。

**定义.** 一条 **positive rewrite path** 是指其中每一步都是 positive 的 rewrite path。

empty rewrite path 是 positive 的，因为它一步都没有。positive rewrite path 对**复合**与 **whiskering** 也封闭，即：a) 若 $p_1$ 与 $p_2$ 都是 positive 的，则 $p_1\circ p_2$ 也是；b) 若 $p$ 是 positive 的且 $z\in A^*$，则 $z\triangleleft p$ 与 $p\triangleright z$ 也都是。（另一方面，若 $p$ 是 positive 的，则 $p^{-1}$ 是 positive 的当且仅当 $p$ 是空的。）

**定义.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation。

1. 由 $R$ 在 $A^*$ 上生成的 **reduction relation**（记作 $s\rightarrow_R t$，当 $R$ 从上下文已清楚时记作 $s\rightarrow t$）把每一对满足「存在一条 source 为 $s$、destination 为 $t$ 的 positive rewrite path」的 term $s$ 与 $t$ 关联起来。
2. 若 $s\rightarrow t$ 蕴涵 $s=t$，则称 term $s$ 是**不可约的**（irreducible）或 **reduced** 的。
3. 若 $s\rightarrow t$ 且 $t$ 不可约，则称 $t$ 是 $s$ 的一个 **normal form**，记作 $\tilde{s} = t$。

我们可以给出一个尝试寻找 normal form 的**算法**。

**算法（Normal form algorithm）.** 输入是一个 term $t\in A^*$ 与一张 rewrite rule 清单 $R:=\{(u_1,v_1),\ldots,(u_n,v_n)\}$。输出是 $t$ 的某个 normal form（记作 $\tilde{t}$），以及一条满足 $\operatorname{src}(p)=t$、$\operatorname{dst}(p)=\tilde{t}$ 的 positive rewrite path $p$。

1. 把返回值 $p$ 初始化为 empty rewrite path $1_t$。
2. 若对某些 $x,y\in A^*$ 与某条 $(u,v)\in R$ 有 $t=xuy$：置 $t\leftarrow xvy$，置 $p\leftarrow p \circ x(u\Rightarrow v)y$，然后回到第 1 步。
3. 否则，返回 $t$ 与 $p$。

> 译注：原书第 2 步说「回到第 1 步」，但第 1 步是把 $p$ 初始化为空 path，跳回那里会把已经累积的 rewrite path 清空；按算法意图应是回到第 2 步继续找下一个可归约的 subterm。疑为笔误，以「回到第 2 步」为准（后文讨论终止性时也说的是「第 2 步的每次迭代」）。

假设给定一对 term $s,t\in A^*$，我们想判定是否 $s\sim t$。若算法告诉我们两者有相同的 normal form，那就意味着：$s\rightarrow \tilde{s}$（经由 $p_s$）、$t\rightarrow \tilde{t}$（经由 $p_t$），且 $\tilde{s}=\tilde{t}$。于是可以断定 $s\sim t$，因为 $p_s \circ p_t^{-1}$ 就是一条 source 为 $s$、destination 为 $t$ 的 rewrite path（它不再是 positive 的了，除非 $p_t$ 是空的）：

```
  s ══╗                             ╔══ t
      ╚══⇒ ⋯ ══╗             ╔══ ⋯ ══╝
                ╚══⇒ (s̃ = t̃) ⇐══╝
```

> 译注：原书此处是一张 tikzcd 交换图（左右两条斜向下的路径在底部同一点汇合，右侧箭头反向），这里用 Unicode 箭头图转述；这张图断言的是：$s$ 与 $t$ 各自沿 positive 方向归约到同一个 normal form，把右半边反过来走就得到一条连接 $s$ 与 $t$ 的 rewrite path，因此 $s\sim t$。图的原貌见官方 PDF 对应章节。

靠比较 normal form 来解 word problem 非常诱人，但在一般情形下行不通，因为我们已经知道 word problem 是不可判定的。粗略地说，有两件事可能出岔子：

1. **存在性：** 我们对 normal form algorithm 的描述看起来总会在第 3 步返回一个值，那么「某个 term $t$ 的 normal form 不存在」是什么意思？麻烦在于这个算法可能**不终止**。这种情况下，我们就说 $t$ 没有 normal form。
2. **唯一性：** 我们证明过，若对某些 $s,t\in A^*$ 有 $\tilde{s}=\tilde{t}$，则 $s\sim t$。然而反过来并不总成立：$\sim$ 的单个等价类里可能含有多个 $\rightarrow$ 意义下不可约的 term。换句话说，可能存在 $s$ 与 $t$ 使得 $s\sim t$，却有 $\tilde{s}\neq \tilde{t}$。

要理解何时、以及如何克服这些困难，我们转向**字符串重写**（string rewriting）理论。Book 与 Otto 的教材（2012，《String-Rewriting Systems》）是这方面的经典。此外，也可以不像我们这样经由 finitely-presented monoid 来引入字符串重写，而是从作用在「树状」表达式上的**抽象**归约关系出发，字符串只是其中的特例——那就是**项重写**（term rewriting）理论，我们也建议读者读一读 Baader & Nipkow 1998《Term Rewriting and All That》与 Dershowitz & Jouannaud 1990《Rewrite Systems》，以对这条路径作全面的了解。

### Existence.

考虑含两个元素 $\{0,1\}$、二元运算为 $x\cdot y:=\max(x,y)$ 的那个 monoid（identity 是 0）。下面是呈现这个 monoid 的一种方式：

$$\langle a \mid a\sim aa\rangle$$

每个非空 term 都**等价于** $a$，但**没有**任何非空 term 有 normal form：

$$a \rightarrow aa \rightarrow aaa \rightarrow aaaa \rightarrow \ldots$$

normal form algorithm 在这里毫无用处。然而，若把 rewrite rule $(a, aa)$ 换成 $(aa, a)$，normal form algorithm 就**总是**终止，而 term equivalence relation 丝毫不变。例如：

$$aaaa \rightarrow aaa \rightarrow aa \rightarrow a$$

现在每个非空 term 的 normal form 都是 $a$。事实上，若 $\langle A \mid R\rangle$ 具有「对每条 $(u,v)\in R$，要么 $\lvert u\rvert<\lvert v\rvert$、要么 $\lvert v\rvert<\lvert u\rvert$」这条性质，我们总能把 rewrite rule **定向**（orient）成 $\lvert v\rvert<\lvert u\rvert$。这样的 rewrite rule 称为 **length-reducing** 的。这保证了：在 normal form algorithm 第 2 步的每次迭代里，把 $u$ 换成 $v$ 之后中间 term $t$ 都会变短。这只能持续有限多步，所以我们必然总能得到一个 normal form。

只允许 length-reducing 的 rewrite rule 限制太严了；例如回忆一下，free commutative monoid 有一条 **length-preserving** 的 rewrite rule $(ba, ab)$。因此，为了建立终止性，我们必须把「比较 term 长度」这个想法一般化。

**定义.** 设 $A$ 是一个有限的符号 alphabet。一个 **reduction order** $<$ 是 $A^*$ 上的**偏序**，且同时是**良基的**（well-founded，见 `generic-signatures.tex` 的相应定义）与 **translation-invariant** 的。

**定义.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation。若 rewrite rule $(u,v)\in R$ 的右端在某个 reduction order $<$ 下更小（即 $u>v$），则称它相对于该 reduction order 是**定向的**（oriented）。（当然，若 $<$ 不是线性序，就可能出现 $u\not< v$ 且 $v\not< u$ 的**不可定向**（non-orientable）rewrite rule $(u,v)\in R$。）

如果我们能用某个 reduction order 把 monoid presentation 的 rewrite rule 全部定向，那么 normal form algorithm 就总能在有限步内找到**某个** normal form。这就解决了两个问题中的第一个：

**定理.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation。若 $R$ 的 rewrite rule 相对于某个 reduction order $<$ 都是定向的，则 $\sim$ 的每个等价类都含有**至少**一个 reduced term。这种情况下我们也说 reduction relation $\rightarrow$ 是 **terminating** 的或 **Noetherian** 的。

**证明.** 假设 normal form algorithm 从某个 term $t$ 出发有一次不终止的执行。这意味着我们有一个无限的 term 序列，每一个都经由一个 positive rewrite step 归约到下一个：

$$t\rightarrow t_1\rightarrow t_2 \rightarrow \cdots \rightarrow t_n \rightarrow \cdots$$

现在设 $s=x(u\Rightarrow v)y$ 是一个 positive rewrite step。由于 $(u,v)\in R$ 是定向的，我们有 $u>v$。又因为 $<$ 是 translation-invariant 的，所以 $xuy>xvy$。于是 $\operatorname{src}(s)>\operatorname{dst}(s)$。这意味着我们那个无限归约序列，在 reduction order 下给出了一条**无限下降链**：

$$t > t_1 > t_2 > \cdots > t_n > \cdots$$

然而这与 $<$ 良基的假设矛盾。因此这样的无限 term 序列不存在，normal form algorithm 必然终止。

若给符号 alphabet $A$ 配上一个良基的偏序，我们总能在 $A^*$ 上得到一个 reduction order，叫 **shortlex order**：

1. 较短的 term 排在较长的 term 前面。
2. 否则，若两个 term 长度相同，就用 $A$ 上的序逐位比较符号。

例如，若 $A:=\{a,b,c\}$，我们可以规定 $a<b<c$ 来定义 $A$ 上的一个线性序；于是就能用 shortlex order 给 $A^*$ 的各种 term 排序：

$$a<b<ab<ac<aab$$

**算法（Shortlex order）.** 输入是两个 term $x,y\in A^*$，输出是 $<$、$>$、$=$、$\bot$ 之一。

1. （更短）若 $\lvert x\rvert<\lvert y\rvert$，返回 $<$。
2. （更长）若 $\lvert x\rvert>\lvert y\rvert$，返回 $>$。
3. （初始化）若 $\lvert x\rvert=\lvert y\rvert$，就逐个元素比较。令 $i:=0$。
4. （相等）若 $i=\lvert x\rvert$，说明没找到任何差异，故 $x=y$。返回 $=$。
5. （取下标）令 $x_i,y_i\in A$ 分别为 $x$ 与 $y$ 的第 $i$ 个符号。
6. （比较）用 $A$ 上的序比较 $x_i$ 与 $y_i$。若结果是 $<$、$>$ 或 $\bot$ 就返回它。否则必有 $x_i=y_i$，继续往下走。
7. （下一个）把 $i$ 加一，回到第 4 步。

shortlex order 返回 $\bot$ 当且仅当两个等长 term $x$ 与 $y$ 在同一位置上有一对在 $A$ 的偏序下不可比的符号。特别地，若 $A$ 上的序是线性的，则诱导出的 shortlex order 在 $A^*$ 上也总是线性序。这里我们略去两个简单的证明：可以用与 `generic-signatures.tex` 中「type parameter order 是良基的」那条命题同样的论证证明 shortlex order 是良基的；也可以对 term 长度作归纳证明 shortlex order 是 translation-invariant 的。

**例.** shortlex order 与字符串上的**字典序**（lexicographic order）**不同**。例如在 shortlex order 下 $b<ab$，但在字典序下 $ab<b$。字典序**不是**良基的，因此不适合用作 reduction order：

$$b>ab>aab>aaab>aaaab>\cdots$$

在这里我们停下来观察一下：在目前见过的所有例子里，除了不可判定的 $\mathfrak{C}_1$ 之外，只要建立了终止性，normal form algorithm 就解决了 word problem：

1. 前面那个 monoid $\langle a \mid a^4\sim\varepsilon\rangle$ 只有一条 length-reducing 的 rewrite rule。normal form algorithm 会输出 $\{\varepsilon,a,a^2,a^3\}$ 之一。
2. 前面那个 bicyclic monoid $\langle a, b \mid ab\sim\varepsilon\rangle$ 只有一条 length-reducing 的 rewrite rule。normal form algorithm 会在每个等价类里找到唯一那个形如 $b^m a^n$ 的 term。
3. 前面那个 free commutative monoid $\langle a,b \mid ba\sim ab\rangle$ 可以配上 $a<b$ 的 shortlex order 来建立终止性。normal form algorithm 会在每个等价类里找到唯一那个形如 $a^m b^n$ 的 term。

上面三个例子都享有唯一的 normal form，而这对一个任意的 monoid presentation 并不成立。

### Uniqueness.

现在我们来刻画那些具有唯一 normal form 的 monoid presentation：

**定理（Church-Rosser Theorem）.** 设 $\langle A \mid R\rangle$ 是一个 monoid presentation。下面两个条件等价：

1. **（Confluence）** 对所有 $t\in A^*$，若对某些 $u,v\in A^*$ 有 $t\rightarrow u$ 且 $t\rightarrow v$，则存在 term $z\in A^*$ 使得 $u\rightarrow z$ 且 $v\rightarrow z$。
2. **（Church-Rosser property）** 对所有满足 $x\sim y$ 的 $x,y\in A^*$，存在 $z\in A^*$ 使得 $x\rightarrow z$ 且 $y\rightarrow z$。

Church-Rosser 定理由 Alonzo Church 与 John Rosser 发现（1936，《Some Properties of Conversion》）。原始结果是关于 **lambda calculus** 的——那是一个重写系统，其 term 由变量、函数应用和匿名函数组合而成。lambda calculus 是图灵完备的，所以对给定的 lambda term，归约可能不终止；但它总是 confluent 的，因此 Church-Rosser 性质成立。Haskell Curry（Haskell 语言即以他命名）随后在《Combinatory Logic》（Curry & Feys 1958）中把这条定理从 lambda calculus 里剥离出来推广了。我们采用的是 term 为 free monoid 中元素的那个版本的陈述，其证明见 Book & Otto 2012。

**例.** 考虑下面这个 monoid presentation：

$$\langle a,b,c \mid ab\sim a,\,bc\sim b\rangle$$

其 reduction relation 是 Noetherian 的，因为规则都是 length-reducing 的。然而我们会看到，这个 reduction relation **不是** confluent 的，因此 Church-Rosser 性质不成立：我们能在同一个等价类里找到两个不可约的 term。

首先观察到 $ac$ 与 $a$ 都是不可约的：两个 term 里都没有哪个 subterm 等于任一条规则的左端。现在来摆弄 term $abc$。我们可以先用两条 rewrite rule 中的任一条：

1. 对 $abc$ 用第一条规则，得到 $ac$，它不可约。
2. 对 $abc$ 用第二条规则，得到 $ab$，它再经第一条规则归约到 $a$，而 $a$ 不可约。

看起来 normal form algorithm 并不是确定性的：在第 2 步，我们面对若干条 rewrite rule 可选，于是会输出两条 rewrite path 之一，而它们终止于不同的不可约 term：

$$
\begin{gathered}
p_1 := (ab\Rightarrow a)c\\
p_2 := a(bc\Rightarrow b)\circ(ab\Rightarrow a)
\end{gathered}
$$

我们找到了一个 **confluence violation**。注意 $\operatorname{src}(p_1)=\operatorname{src}(p_2)=abc$，所以 $p_1^{-1}\circ p_2$ 是一条从 $ac$ 到 $a$ 的 rewrite path。因此 $ac\sim a$，可它们彼此不同、又都不可约。若把 rewrite path $p_1^{-1}\circ p_2$ 画成图，就会看到没有任何 positive rewrite path 能把我们从 $ac$ 带到 $a$——我们必须翻过「那座山包」：

```
                    abc
        (a⇒ab)c   ↙     ↘   a(bc⇒b)
      ⇐                        ⇒
    ac                           ab
                                 ↙  (ab⇒a)
                               ⇒
                    a
```

> 译注：原书此处是一张 tikzcd 交换图（$abc$ 居顶，向左下的边反向指回 $ac$、向右下的边指向 $ab$，$ab$ 再向左下指向 $a$），这里用 Unicode 箭头图转述；这张图断言的是：$ac$ 与 $a$ 虽在同一个等价类里，但连接它们的那条 path 必须先**反向**走回 $abc$（即 $ac \Leftarrow abc$ 这一段是 negative step），沿 positive 方向是下不去的。图的原貌见官方 PDF 对应章节。

现在，我们往 monoid presentation 里**加**一条 rewrite rule $(ac,a)$：

$$\langle a,b,c \mid ab\sim a,\,bc\sim b,\,ac\sim a\rangle$$

我们**本来就已经**有一条从 $ac$ 到 $a$ 的 rewrite path，所以加上 $(ac, a)$ 并不改变等价关系 $\sim$（我们会在 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 的 Tietze Transformations 一节看到，这叫一次 **Tietze transformation**）。但它**确实**改变了 $\rightarrow$：特别地，reduction relation 变得 confluent 了。

在新的 presentation 里，非确定性消失了：无论先选哪条 rewrite rule，normal form algorithm 都总把 $abc$ 归约到 $a$。事实上，现在每个等价类都有唯一的 normal form $c^i b^{\,j} a^k$，其中 $i,j,k\in\mathbb{N}$。

我们给这种「normal form algorithm 总能终止、且从每个等价类输出唯一 reduced term」的 monoid presentation 起个名字。

**定义.** 一个 **convergent rewriting system** 是指其 reduction relation $\rightarrow_R$ 既 Noetherian 又 confluent 的 monoid presentation $\langle A \mid R\rangle$。

由 convergent rewriting system 呈现的 monoid，其 word problem 是可判定的：

**推论.** 设 $\langle A \mid R\rangle$ 是一个 convergent rewriting system。则对所有 $x,y\in A^*$，有 $x\sim y$ 当且仅当 $\tilde{x}=\tilde{y}$。

我们给本章 A Swift Connection 一节开头那块「罗塞塔石碑」再添两行：

| **Swift generics** | **F-P monoids** |
|---|---|
| Type parameter order | Shortlex order |
| Reduced type parameter | Reduced term |

事实上，`generic-signatures.tex` 里那个 type parameter order 算法基本上就是 shortlex order 的一个具体实例，区别只在于它是用递归算法描述的，而上面那个 shortlex order 算法是迭代式的。

### Completion.

靠加规则来修补 confluence violation 的过程叫 **completion**。若 completion 成功，我们就得到一个 convergent rewriting system。`completion.tex` 那一章会讲解为此所用的 Knuth-Bendix 算法。例如，Swift 编译器接受编码上面那个非 confluent 例子的 monoid presentation 的 protocol `M`；completion 让我们得以确立 $G_\texttt{M}\vdash[\texttt{Self.A.C == Self.A}]$。

completion 只是一个可能不终止的**半判定程序**（semi-decision procedure）；实践中我们会给它加一个迭代次数上限。这一点无法改进，因为归根结底，「一个 monoid 能否由某个 convergent rewriting system 呈现」本身就是**不可判定的**（Ó'Dúnlaing 1983）。word problem 不可判定的 monoid 不可能有这样的 presentation，所以那种情况下 completion 必然失败。反过来成立吗？也就是说，若已知一个 finitely-presented monoid 的 word problem 可判定，completion 是否总能在有限步内终止并输出一个 convergent rewriting system？答案同样是否定的：

1. 对固定的 presentation $\langle A \mid R\rangle$，completion 成功与否可能取决于 reduction order $<$ 的选取。
2. 两个建立在不同 generating set（alphabet）上的 presentation $\langle A \mid R\rangle$ 与 $\langle A^\prime \mid R^\prime\rangle$ 可能在同构意义下呈现同一个 monoid，但 completion 对其中一个成功、对另一个失败。
3. 有些 finitely-presented monoid 已知 word problem 可判定，却在**任何** generating set 上都没有 convergent presentation。

我们会在 `completion.tex` 的 Recursive Conformances 一节看到，规避前两个问题正是把 generic signature 下降（lowering）为 monoid presentation 时若干设计决策的动机。第二个问题最早由 Kapur 与 Narendran（1985）探讨，从中我们了解到：monoid presentation $\langle a,b \mid aba\sim bab\rangle$ 无法在同一个 alphabet 上扩展成一个 convergent presentation，但只要加一个新符号 $c$ 连同 rewrite rule $ab\sim c$，completion 很快就能得到一个 convergent presentation。

第三种情况更难。下面这个例子出自 Craig C. Squier 的论文（Squier、Otto、Kobayashi 1994）；另见 Lafont & Prouté 1991 与 Lafont 1995。

**定理.** 下面这个 finitely-presented monoid 的 word problem 可以用一个「量身定做」的算法判定，但它在任何 generating set 上都没有 convergent presentation：

$$S_1:=\langle a,b,t,x,y \mid ab\sim \varepsilon,\,xa\sim atx,\,xt\sim tx,\,xb\sim bx,\,xy\sim \varepsilon\rangle$$

为证明这条定理，Squier 引入了一个关于前面 rewrite graph 定义的新的组合性质（论文里用的术语是 **derivation graph**），叫 **finite derivation type**。可以证明「具有 finite derivation type」这条性质不依赖于 presentation 的选取，因此它是 monoid 自身的一个不变量。进一步，convergent presentation 必然具有 finite derivation type。（具有 finite derivation type 是存在 convergent presentation 的**必要**条件，但不是充分条件。）例如，上面那个 $\langle a,b \mid aba\sim bab\rangle$ 可以在另一个 alphabet 上呈现为 convergent rewriting system，所以这个 monoid 必然具有 finite derivation type。

反过来，若能证明某个 monoid **不**具有 finite derivation type，我们就能断定它在任何 generating set 上都不存在 convergent presentation——哪怕它的 word problem 用别的办法是可判定的。Squier 证明了 $S_1$ 不具有 finite derivation type，而它的 word problem 却是可判定的。

于是，下面每一类都是下一类的**真子集**，而我们从这里开始就只打算在泳池的浅水区玩：

```
        convergent rewriting system
                    ⊊
          decidable word problem
                    ⊊
      all finitely-presented monoids
```

> 译注：原书此处是一张单列的 `tabular` 表（三行类名，中间用 $\subsetneq$ 相连），这里用等宽代码块转述其层级关系。

关于由 convergent rewriting system 呈现的 monoid 还满足哪些条件，Squier 1987、Cremanns & Otto 1994、Kobayashi 1995 作了探讨。convergent rewriting system 相关结果的综述见 Otto & Kobayashi 1997。许多问题至今悬而未决。注意我们见过的例子里有多少个只有一条 rewrite rule——即便是这种「单关系」（one-relation）monoid，情况也远非平凡。例如，至今不知道是否每个 one-relation monoid 都能由某个 convergent rewriting system 呈现，更一般地，也不知道这类 monoid 的 word problem 是否可判定。不过，one-relation monoid 已知具有 finite derivation type（Kobayashi 2000）。关于 one-relation monoid 的结果综述以及 word problem 的整体概览，见 Nyberg-Brodda 2021。除了字符串重写之外，解 word problem 的另一条路是用有限状态自动机来刻画 monoid 或 group 的结构（Epstein 1992，《Word Processing in Groups》）。抽象代数里其他有趣的不可判定问题见 Tarski、Mostowski & Robinson 1953，《Undecidable Theories》。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。原文在该块开头留有一行注释「这将替换掉上面的部分内容」。

word problem 可判定的头一批例子归功于 Craig C. Squier（1987），他证明了：由有限完备 presentation 给出的 monoid 必然满足 $\mathrm{FP}_3$ 这个不变量；而下面这个 $S_k$ 对所有 $k \geq 0$ 都有可判定的 word problem，但当 $k \geq 2$ 时不满足 $\mathrm{FP}_3$：

$$
\begin{alignedat}{2}
S_k := \langle a,b,t,x_1,\ldots,x_k,y_1,\ldots,y_k \mid\
&ab = 1, \\
&x_1 a = a t x_1, && \quad \ldots,\quad x_k a = a t x_k, \\
&x_1 t = t x_1, && \quad \ldots,\quad x_k t = t x_k, \\
&x_1 b = b x_1, && \quad \ldots,\quad x_k b = b x_k, \\
&x_1 y_1 = 1, && \quad \ldots,\quad x_k y_k = 1\rangle
\end{alignedat}
$$

为了解决 $k=1$ 的情形，Squier 随后在另一篇论文（Squier、Otto、Kobayashi 1994）中引入了 **finite derivation type**（FDT）这个不变量。关键结果是：由有限完备 presentation 给出的 monoid 具有 FDT，而带 5 个 generator、5 条关系的 $S_1$ 不具有 FDT，因此没有有限完备 presentation：

$$S_1:=\langle a,b,t,x,y \mid ab= 1,\,xa= atx,\,xt= tx,\,xb= bx,\,xy= 1\rangle$$

我们会在讲 FDT 的那一节回顾它的定义。我们不定义 $\mathrm{FP}_3$；只需知道 FDT 蕴涵 $\mathrm{FP}_3$，于是事实上对所有 $k \geq 1$，$S_k$ 都不具有 FDT（Cremanns & Otto 1994）。

> 译注：原书这里引用了一个标签为 `sec:fdt` 的小节，但该标签在全书源码里并不存在——这正是 `\ifWIP` 草稿尚未完工的痕迹之一。

finite derivation type 并不是 monoid 存在有限完备 presentation 的**充分**条件。Katsura 与 Kobayashi 发现了下面这个 word problem 可判定、具有 FDT、却没有有限完备 presentation 的 monoid（Katsura & Kobayashi 1997）：

$$
\begin{aligned}
\langle a,b_1,c_1,d_1,b_2,c_2,d_2,b_3,c_3,d_3 \mid\ &b_1 a = ab_1,\ b_2 a = ab_2,\ b_3 a = ab_3,\\
&c_1 b_1 = c_1 b_1,\ c_2 b_2 = c_1 b_1,\\
&b_1 d_1 = b_1 d_1,\ b_2 d_2 = b_1 d_1\rangle
\end{aligned}
$$

> 译注：上式中 $c_1 b_1 = c_1 b_1$ 与 $b_1 d_1 = b_1 d_1$ 两条「关系」两端完全相同，是平凡的恒等式，不可能是作者本意（疑为 $c_3 b_3$、$b_3 d_3$ 之类的笔误）；这也是 `\ifWIP` 草稿未定稿的表现。此处照译原文。

能不能把定义关系的条数压到比 Squier 的 $S_1$ 更少？看来此前的纪录是**三条**关系。Lafont 与 Prouté 给出了这个不满足 $\mathrm{FP}_3$ 的 monoid（Lafont & Prouté 1991）：

$$\langle a,b,c,d,d' \mid ab = a,\, da = ac,\, d'a = ac\rangle$$

Cain 等人证明了下面这个 monoid 不具有 FDT（Cain、Gray、Malheiro 2017）：

$$\langle a,b,c \mid ac = ca,\, bc = cb,\, cab = cbb\rangle$$

每个 one-relation monoid $\langle A \mid u=v\rangle$ 都具有 FDT（Kobayashi 2000）。「是否每个 one-relation monoid 都有有限完备 presentation 或可判定的 word problem」仍是悬而未决的问题（Nyberg-Brodda 2021）。

### Type substitution.

事实上，我们本可以把 type substitution 代数形式化成一个**项重写系统**（term rewriting system）。那将是一个建立在树状 term 上的重写系统，因为这套代数里的 type、substitution map 与 conformance 都彼此递归嵌套。

$\otimes$ 运算符的那些「求值规则」将改为定义一个 reduction relation，而 $\otimes$ 的结合律则等价于证明这个 reduction relation 是 confluent 的。（有胆量的读者可以快速翻一翻 `type-substitution-summary.tex`（中译 [SwiftGenericsSubstitutionAlgebra.md](SwiftGenericsSubstitutionAlgebra.md)） 那个附录，看看为什么会是这样。）不过这个 reduction relation 并不终止，因为正如 `conformance-paths.tex` 的 The Halting Problem 一节所示，它能编码任意计算。

若把 type substitution 看成一个项重写系统，它非常像 lambda calculus——confluent，但不终止。这个观察虽然有趣，但我们不会再沿这个方向深入下去。

> 译注：这一段描述的「$\otimes$ 的求值规则」正是本库在离线方向上真正实现过的那一件事。本库不做重写、不做 completion，但它确实要把 bound generic 的实参代入到字段类型上——那套代入是纯语法的自顶向下重写（不调 metadata accessor、不查 protocol witness table），见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。书里说这个 reduction relation 不终止，本库的对策是把它限制在「实参已经在 mangled name 里写死」的那一小块上，因此每次代入都必然停机。

$$\ast \ast \ast$$

本章没有 **Source Code Reference** 小节，因为我们通篇只谈了数学。

---

> 译自 `docs/Generics/chapters/monoids.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
