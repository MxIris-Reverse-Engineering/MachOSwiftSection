# Completion（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/completion.tex`（《Compiling Swift Generics》一书的「Completion」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是 Requirement Machine 的心脏——Knuth-Bendix completion procedure，也是全书交换图最密集的一章。本库（MachOSwiftSection）**不实现**重写系统：二进制里躺着的是这套算法跑完、再经 minimization 之后固化下来的结果。读这一章的价值在于理解那个结果为什么长成那样——为什么 `T.[P]A` 这种 bound type parameter 是 reduced 形式而 `T.A` 不是，为什么 associated type 在 mangling 里总是绑着声明它的 protocol，以及为什么某些看起来合法的 generic signature 编译器会直接拒绝（completion 不终止）。
>
> **术语**：书中定义的术语一律保留英文（Knuth-Bendix completion、critical pair、overlapping rules、overlap term、overlap position、orthogonal、local confluence、confluence、Church-Rosser property、convergent rewriting system、reduction order、reduction relation、rewrite step、rewrite path、rewrite loop、basepoint、whiskering、parallel rewrite paths、rule trie、left / right simplification、substitution simplification、left-reduced / right-reduced rewriting system、Tietze transformation、monoid presentation、finitely-presented monoid、free semigroup、imported rule / local rule、protocol component、protocol symbol、associated type symbol、name symbol、generic parameter symbol、conformance rule、associated type rule、identity conformance rule、permanent rule、recursive conformance requirement、bound / unbound type parameter、requirement minimization……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Correctness 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（本章属规约 §6 的 B 类，行文里的数学用 Markdown LaTeX `$...$` / `$$...$$`；交换图按规约 §6.5 (a) 降级成裸代码块里的 Unicode 箭头图，代码块里没法跑 LaTeX，所以另给一套纯文本写法，两栏一一对应）：
>
> | LaTeX（行文用） | 纯文本（图里用） | 含义 |
> |---|---|---|
> | `$[\texttt{P}]$` → $[\texttt{P}]$ | `[P]` | **protocol symbol** |
> | `$[\texttt{P}\vert\texttt{A}]$` → $[\texttt{P}\vert\texttt{A}]$ | `[P\|A]` | **associated type symbol**（protocol `P` 声明的 associated type `A`） |
> | `$\texttt{A}$` | `A` | **name symbol**（只有名字，还没绑到 protocol 上） |
> | `$\tau_{0,0}$` | `τ_0_0` | **generic parameter symbol**。原书的 `\rT` 即 $\tau_{0,0}$，`\rU` 即 $\tau_{0,1}$ |
> | `$\cdot$` | `·` | 符号相连，即自由 monoid $A^*$ 的乘法 |
> | `$\Rightarrow$` | `⇒` | 一步 rewrite step，也用来写 rewrite rule 本身 |
> | `$\rightarrow$` | `→` | **reduction relation**：零步或多步的正向重写 |
> | `$\sim$` | `∼` | term 的等价关系（双向可达） |
> | `$\circ$` | `∘` | rewrite path 的复合（先左后右） |
> | `$p^{-1}$` | `p⁻¹` | 逆向 rewrite path |
> | `$\triangleleft$` / `$\triangleright$` | `◁` / `▷` | **whiskering**：把一个 path 放进上下文，`x ◁ p ▷ z` 表示两侧各接上 `x` 与 `z` |
> | `$\operatorname{src}(p)$` / `$\operatorname{dst}(p)$` | `src(p)` / `dst(p)` | rewrite path 的起点 / 终点 |
> | `$\langle A\,\vert\,R\rangle$` | `⟨A \| R⟩` | **monoid presentation**（生成元集 \| 关系集） |
> | `$\varepsilon$` | `ε` | 空项 |
> | `$\vert u\vert$` | | term `u` 的长度 |
> | `$u[:i]$` / `$u[i:]$` | | `u` 长为 `i` 的前缀 / 去掉前 `i` 个符号后的后缀 |
> | `$\tilde{u}$` | | `u` 的 normal form（reduced term） |
> | `(*n)` | | 规则编号前的星号表示**这条规则是 completion 加出来的**，不在初始规则集里 |
> | `$\mathbb{N}$` | | 自然数 |
> | `$\mathcal{N}$`、`$\mathcal{S}$`、`$\mathcal{R}$`、`$\hat{\mathcal{R}}$` | | 本章最后一例里对规则集的分组 |
>
> 原书的 `\uptau`（直立 tau）在 Markdown 数学里渲染不出来，本文一律写 `\tau`。原书给 completion 新增的规则用了三种不一致的标记（菱形 `◇n`、前置星号 `*n`、后置星号 `n*`），本译文统一成正文自己声明的那一种：前置星号 `(*n)`。

---

**Knuth-Bendix completion** 是 Requirement Machine 里的核心算法。Completion 试图从一串 rewrite rule 出发，构造出一个 convergent rewriting system；而有了 convergent rewriting system，我们就能在有限步内判定两个 term 是否有相同的 normal form，也就解决了 word problem。正如上一章所见，我们的初始 rewrite rule 由一个 generic signature 的 explicit requirement 及其 protocol dependency 决定。这个映射有一条很好的性质，由 `symbols-terms-and-rules.tex` 的 Correctness 一节里的一对定理给出：一条 **derived** requirement 定义了一条建立在「代表 explicit requirement 的那些 rewrite rule」之上的 rewrite path。凡此种种合起来意味着：completion 给了我们 derived requirement 形式系统的一个**判定过程**——任给一条 derived requirement，问它是否成立（也就是问是否存在一条由 explicit requirement 搭出来的合法 derivation），只要在 convergent rewriting system 里做一次 term reduction 就能回答。generic signature query 与 minimization 都建立在这个基础之上。

### The algorithm

我们先给一个自足的描述，本章余下的大部分篇幅则留给例子。这个描述可以配合任何一本讲重写理论的书一起读，比如 Book 与 Otto 2012 年的《String-Rewriting Systems》，或者 Baader 与 Nipkow 1998 年的《Term Rewriting and All That》。这个算法有点巧妙，想真正「吃透」它可能得读上好几遍。Donald E. Knuth 与 Peter Bendix 在 1970 年的一篇论文里针对 term rewriting system 描述了这个算法（收录于 1983 年的《Automation of Reasoning》，题为「Simple Word Problems in Universal Algebras」）；正确性证明后来由 Gérard Huet 在 1981 年给出（《Journal of Computer and System Sciences》，「A complete proof of correctness of the Knuth-Bendix completion algorithm」）。在我们的应用里，term 是自由 monoid 的元素，所以我们面对的是 string rewriting system；这个特例由 Kapur 与 Narendran 在 1985 年研究过（《SIAM Journal on Computing》，「The Knuth-Bendix Completion Procedure and Thue Systems」）。相关技术的综述见 Buchberger 1987 年的「History and basic features of the critical-pair/completion procedure」（《Journal of Symbolic Computation》）。

进入 Knuth-Bendix completion procedure 的入口是本章的 **Knuth-Bendix completion procedure** 算法，但在抵达它之前我们先把四块小一点的东西拆出去，好让顶层只剩下主循环：

- **Overlap lookup in rule trie** 算法：找出在某条固定规则的某个固定位置上与之 overlap 的所有规则。
- **Find overlapping rules** 算法：找出在任意位置上 overlap 的所有规则对。
- **Construct critical pair** 算法：从一对 overlap 的规则造出一个 critical pair。
- **Resolve critical pair** 算法：resolve 一个 critical pair。

我们从最里层开始，先讲 **Construct critical pair** 与 **Resolve critical pair** 这两个算法。overlapping rule 与 critical pair 这一对孪生概念是整个算法的根本，其余部分的理论依据都由它们提供。

### Local confluence

我们希望自己的 reduction relation $\rightarrow$ 满足 **Church-Rosser property**：若 $x\sim y$ 是两个等价的 term，则存在某个 term $z$ 使得 $x\rightarrow z$ 且 $y\rightarrow z$。由 `monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 Church-Rosser Theorem，这等价于 $\rightarrow$ 是 **confluent** 的，即任意两条从同一起点岔开的 positive rewrite path 都能各自延长到彼此相遇。直接验证这一点很困难，但 Max Newman 1941 年的一篇论文（《Annals of Mathematics》，「On Theories with a Combinatorial Definition of Equivalence」）表明：当 reduction relation 是 terminating 的时候，存在一个更简单的等价条件。

**定义.** 一个 reduction relation $\rightarrow$ 称为 **locally confluent**，如果每当 $s_1$ 与 $s_2$ 是两个满足 $\operatorname{src}(s_1)=\operatorname{src}(s_2)$ 的 positive rewrite step 时，总存在一个 term $z$ 使得 $\operatorname{dst}(s_1)\rightarrow z$ 且 $\operatorname{dst}(s_2)\rightarrow z$。

要检验 local confluence，我们从一个 term 出发，只沿两个不同方向各「岔开」一步，然后看两边是否都能归约到某个共同的 term。我们将看到这件事是可以算法判定的，而且发现的任何 local confluence 违例都可以被「修好」。因此，Newman 的结论是根本性的：

**定理（Newman's Lemma）.** 若一个 reduction relation $\rightarrow$ 是 terminating 且 locally confluent 的，则 $\rightarrow$ 是 confluent 的。

### Overlapping rules

一对共起点的 positive rewrite step 定义了一个 **critical pair**。一个 critical pair 表明某个 term 可以被「以两种不同的方式」归约。只要逐个检查 critical pair，我们就能回答自己的 rewrite rule 是否定义了一个 locally confluent 的 reduction relation。对任何非平凡的规则表，这样的 critical pair 都有无穷多个；不过除去有限的一个子集之外，其余的都可以不管。假设我们在某个字母表 $A$ 上有这两条规则：

$$u_1\Rightarrow v_1$$
$$u_2\Rightarrow v_2$$

对任意 term $x\in A^*$，我们都能拼出一个「三明治」term $t := u_1xu_2$。每一个这样的 $x$ 都定义出一个新的 critical pair：$t$ 里 $u_1$ 与 $u_2$ 这两处可以用两种方式重写，即 $s_1 := (u_1\Rightarrow v_1)xu_2$ 与 $s_2 := u_1x(u_2\Rightarrow v_2)$。但由于 $s_1$ 与 $s_2$ 重写的是 $t$ 的两个**不相交**的 subterm，我们说这个 critical pair 是 **orthogonal** 的。orthogonal 的 critical pair 没有意思，因为它们不可能见证一次 local confluence 违例。原因是：无论先用 $s_1$ 还是先用 $s_2$，都存在一个互补的 rewrite step $s_1^\prime$ 或 $s_2^\prime$，把 $\operatorname{dst}(s_1)$ 或 $\operatorname{dst}(s_2)$ 重写成那个「归约过的三明治」$v_1xv_2$。事实上，任何 orthogonal critical pair 都给出这样一张交换图：

```
                          u₁xu₂
      s₁:=(u₁⇒v₁)xu₂  ↙           ↘  s₂:=u₁x(u₂⇒v₂)
              v₁xu₂                   u₁xv₂
      s₁′:=v₁x(u₂⇒v₂) ↘           ↙  s₂′:=v₁x(u₂⇒v₂)
                          v₁xv₂
```

这张图断言的是：从 $u_1xu_2$ 出发先走哪一边都无所谓，两条长度为 2 的路径最终都落在同一个 term $v_1xv_2$ 上——也就是说 orthogonal critical pair 总是 trivial 的。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

> 译注：原书把 $s_2^\prime$ 也标成了 $v_1x(u_2\Rightarrow v_2)$，与 $s_1^\prime$ 完全一样。但 $s_2^\prime$ 是从 $u_1xv_2$ 出发的那一步，它重写的必须是 $u_1$，因此应为 $(u_1\Rightarrow v_1)xv_2$，疑为笔误，以本译注的写法为准。

我们也可以用 `monoids.tex` 的 Equivalence of Terms 一节里给 rewrite step 设计的那套「图示」记法来看一个 orthogonal critical pair：

```
       先走 s₁：                        先走 s₂：
  ┌─────────────────────┐         ┌─────────────────────┐
  │        u₁xu₂        │         │        u₁xu₂        │
  ╞══════╤══════╤═══════╡         ╞══════╤══════╤═══════╡
  │  u₁  │      │       │         │      │      │   u₂  │
  │  ⇓   │  y   │   u₂  │         │  u₁  │  y   │   ⇓   │
  │  v₁  │      │       │         │      │      │   v₂  │
  ╞══════╧══════╧═══════╡         ╞══════╧══════╧═══════╡
  │        v₁xu₂        │         │        u₁xv₂        │
  ╞══════╤══════╤═══════╡         ╞══════╤══════╤═══════╡
  │      │      │   u₂  │         │  u₁  │      │       │
  │  v₁  │  y   │   ⇓   │         │  ⇓   │  y   │   v₂  │
  │      │      │   v₂  │         │  v₂  │      │       │
  ╞══════╧══════╧═══════╡         ╞══════╧══════╧═══════╡
  │        v₁xv₂        │         │        v₁xv₂        │
  └─────────────────────┘         └─────────────────────┘
```

这张图断言的是：两种走法各自经过一个不同的中间 term（$v_1xu_2$ 与 $u_1xv_2$），但终点同为 $v_1xv_2$；每个小格子从上到下读就是一次 rewrite step，中间那一列始终原封不动。

> 译注：原书此处是一张由两个表格并排组成的 `tikzpicture` 式图示，这里用 ASCII 表格转述；图的原貌见官方 PDF 对应章节。

> 译注：原书这两张表里，中间那一列写作 $y$，而正文里三明治的填充项是 $x$（$t:=u_1xu_2$）；右表左下格写的是 $v_2$，而那一步重写的是 $u_1$，应为 $v_1$。两处均疑为笔误，以正文的 $x$ 与 $v_1$ 为准。

显然，在我们搜寻 local confluence 违例的路上，只需要检查那些**不是** orthogonal 的 critical pair；也就是说，它们重写的必须是共同源 term 里**互相重叠**的 subterm。这样的 critical pair 只有有限多个，而且它们全都可以通过检查 rewrite rule 的左侧来枚举出来。下面这个定义把它们完整刻画了出来。

**定义.** 两条规则 $(u_1, v_1)$ 与 $(u_2, v_2)$ 称为 **overlap**，如果下列之一成立：

1. 第二条规则的左侧完全包含在第一条规则的左侧之内。也就是说，存在 $x$、$y$、$z\in A^*$ 使得 $u_1=xyz$ 且 $u_2=y$。若把 $u_1$ 与 $u_2$ 写下来，再把 $u_2$ 向右挪到对齐，得到的是这样：

$$\begin{aligned} x&yz\\ &y \end{aligned}$$

2. 第二条规则左侧的某个前缀等于第一条规则左侧的某个后缀。也就是说，存在 $x$、$y$、$z\in A^*$ 使得 $u_1=xy$ 且 $u_2=yz$，其中 $|x|>0$ 且 $|z|>0$。同样把 $u_2$ 挪到对齐，得到的是这样：

$$\begin{aligned} x&y\\ &yz \end{aligned}$$

以上两种就是一个非 orthogonal 的 critical pair 重写同一个 term 的全部方式。需要区分情形时，我们可以分别称之为**第一类** overlap 或**第二类** overlap。两种情形下，在适当地指定了 $x$、$y$、$z$ 之后，我们把 **overlap term** 定义为 $xyz$，把 **overlap position** 定义为 $|x|$。

**例.** 考虑这三条规则：

$$\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}] \tag{1}$$

$$\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\Rightarrow\tau_{0,1} \tag{2}$$

$$[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Collection}|\texttt{Element}]\Rightarrow[\texttt{Collection}|\texttt{Element}] \tag{3}$$

> 译注：原书的规则 (1) 只写了一个 term，没有 $\Rightarrow$ 和右侧，与「规则」的定义不符；按上下文它应当是一条 conformance rule，即 $\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}]\Rightarrow\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]$。疑为笔误；后文只用到它的左侧，所以不影响论述。

(1) 与 (2) 之间在位置 0 处有一个第一类 overlap；(2) 的左侧完全包含在 (1) 的左侧之内。这里的 overlap term 是 $\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}]$：

$$\begin{aligned} &\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}]\\ &\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}] \end{aligned}$$

(1) 与 (3) 之间在位置 1 处有一个第二类 overlap；(3) 的左侧以 $[\texttt{Collection}|\texttt{SubSequence}]$ 开头，而它同时也是 (1) 左侧的一个后缀。overlap term 是 $\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}]$：

$$\begin{aligned} \tau_{0,0}\cdot{}&[\texttt{Collection}|\texttt{SubSequence}]\\ &[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Collection}|\texttt{Element}] \end{aligned}$$

第二类 overlap 的定义要求 $x$ 与 $z$ 都非空。如果放宽这个条件，那么规则 (2) 与 (1) 之间在位置 0 处**也**会构成一个第二类 overlap：

$$\begin{aligned} &\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\\ &\tau_{0,0}\cdot[\texttt{Collection}|\texttt{SubSequence}]\cdot[\texttt{Equatable}] \end{aligned}$$

可它的 overlap term 与 overlap position 跟我们已经见过的第一种情形完全相同，所以去 resolve 这个 critical pair 不会带来任何新东西。我们调整定义正是为了避免在这种情况下做重复劳动。

两条规则也可能在**不同的**位置上 overlap 不止一次；这时每一个可能的 overlap 都必须考虑。例如下面这两条规则一共生成四个 overlap：

$$[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\Rightarrow [\texttt{P}|\texttt{C}] \tag{4}$$

$$[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\Rightarrow [\texttt{P}|\texttt{D}] \tag{5}$$

规则 (4) 与 (5) 在位置 1 处 overlap：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot{}&[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\\ &[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}] \end{aligned}$$

规则 (4) 与 (5) 在位置 3 处 overlap：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot{}&[\texttt{P}|\texttt{B}]\\ &[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}] \end{aligned}$$

规则 (5) 与 (4) 在位置 1 处 overlap：

$$\begin{aligned} [\texttt{P}|\texttt{B}]\cdot{}&[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\\ &[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}] \end{aligned}$$

最后同样重要的是，规则 (5) 与 (4) 在位置 3 处 overlap：

$$\begin{aligned} [\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot{}&[\texttt{P}|\texttt{A}]\\ &[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}] \end{aligned}$$

### Resolving critical pairs

一个 critical pair 展示了某个 term $t$ 被以两种不同方式重写。取这两个 rewrite step 各自的终点 term，就得到一对已知与 $t$ 等价、因而也彼此等价的 term。对第一类 overlap，这一对是 $(v_1,\,xv_2z)$；对第二类，是 $(v_1z,\,xv_2)$：

```
        第一类 overlap                          第二类 overlap

               xyz                                    xyz
  (u₁⇒v₁)  ↙        ↘  x(u₂⇒v₂)z        (u₁⇒v₁)z  ↙        ↘  x(u₂⇒v₂)
       v₁              xv₂z                   v₁z              xv₂
```

这两张图断言的是：同一个 overlap term $xyz$ 一步就能岔成两个不同的 term，而这两个 term 因此必然等价——这正是待 resolve 的那个 critical pair。

> 译注：原书此处是两张并排的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

我们 **resolve** 一个 critical pair $(t_1,t_2)$ 的办法是：用到目前为止构造出的 reduction relation 把两边都归约掉，再比较归约后的 term。有四种可能的结局：

1. 若 $t_1$ 与 $t_2$ 归约到同一个 term $t^\prime$，我们说这个 critical pair 是 **trivial** 的。（注意这个说法给了 local confluence 一个等价的定义：一个 reduction relation 是 locally confluent 的，当且仅当它所有的 critical pair 都是 trivial 的。）
2. 若 $t_1\rightarrow t_1^\prime$ 且 $t_2\rightarrow t_2^\prime$ 而 $t_1^\prime\neq t_2^\prime$，我们就在同一个等价类里找到了两个不同的 reduced term：一次 **confluence violation**。若 $t_2^\prime < t_1^\prime$，我们通过加入一条新的 rewrite rule $(t_1^\prime, t_2^\prime)$ 来修复这次违例。这么做之后，若令 $t^\prime:=t_2^\prime$，我们就又一次看到 $t_1$ 与 $t_2$ 归约到了同一个 term $t^\prime$。
3. 若反过来 $t_1^\prime<t_2^\prime$，情况一样，只是我们改为加入新规则 $(t_2^\prime, t_1^\prime)$，并令 $t^\prime:=t_1^\prime$。
4. 若 $t_1^\prime$ 与 $t_2^\prime$ 不同但**不可比**，我们就碰上了一个 non-orientable 的关系，必须报错。在 Requirement Machine 所用的 reduction order 下这种情况不会发生。

每种情形都能画一张图，展示的是 rewrite graph 的一个 subgraph；虚线箭头表示正在加入的新规则：

```
      trivial 的 overlap              加入一条新规则                   加入一条新规则

             t                             t                             t
          ↙     ↘                       ↙     ↘                       ↙     ↘
        t₁       t₂                   t₁       t₂                   t₁       t₂
        ↓         ↓                   ↓         ↓                   ↓         ↓
       ···       ···                 t₁′       ···                 ···       t₂′
          ↘     ↙                     ⇢ ↘     ↙                       ↘     ↙ ⇠
             t′                             t′                             t′
```

这三张图断言的是：无论哪种情形，处理完之后从 $t$ 出发的两条 rewrite path 都终结于同一个 term $t^\prime$；中间那张的虚线是新规则 $(t_1^\prime, t_2^\prime)$，右边那张的虚线是新规则 $(t_2^\prime, t_1^\prime)$。

> 译注：原书此处是三张并排的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

在（必要时）加入一条新 rewrite rule 之后，我们手上就有了一对 rewrite path $p_1$ 与 $p_2$，以及一个 term $t^\prime$。注意 $\operatorname{src}(p_1)=\operatorname{src}(p_2)=t$ 且 $\operatorname{dst}(p_1)=\operatorname{dst}(p_2)=t^\prime$，两条 path 起点终点都相同。我们称 $p_1$ 与 $p_2$ 是 **parallel** 的 rewrite path。

### Rewrite loops

现在我们稍微换一个视角，引入一个新概念。给定两条 parallel 的 rewrite path $p_1$ 与 $p_2$，我们可以把第一条与第二条的逆复合起来，得到 rewrite path $\ell:=p_1\circ p_2^{-1}$：

```
        p₁：                p₂：                    p₁ ∘ p₂⁻¹：

         t                   t                          t
      ↙                       ↘                      ↙     ↖
    ···                        ···                 ···      ···
      ↘                       ↙                      ↘     ↗
         t′                  t′                         t′
```

这张图断言的是：把 $p_2$ 整条反向之后接在 $p_1$ 后面，就得到一条从 $t$ 出发又回到 $t$ 的闭合路径。

> 译注：原书此处是三张并排的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

这条新的 rewrite path $\ell$ 有一个性质：它的起点与终点是**同一个** term $t$：

$$\operatorname{src}(\ell)=\operatorname{src}(p_1)=t\qquad\qquad\operatorname{dst}(\ell)=\operatorname{dst}(p_2^{-1})=\operatorname{src}(p_2)=t$$

我们说 $\ell$ 是一个以 $t$ 为 **basepoint** 的 **rewrite loop**。一个 rewrite loop 对 basepoint term $t$ 施加一串 rewrite rule，然后再经由一组可能**不同**的 rewrite rule 把它重写「回」$t$。在 rewrite graph 里，一个 rewrite loop 就是一个 cycle（图论学家有时称之为「闭路径」）。注意对每个 $t\in A^*$，空 rewrite path $1_t$ 也可以看成一个以 $t$ 为 basepoint 的 trivial rewrite loop。

现在我们给出两个算法，它们合起来构成 completion procedure 的内层循环。把一个 critical pair 看成一条长度为 2 的 rewrite path（而不是两个共起点的 rewrite step）也很方便——我们把第一步与第二步的逆复合起来。在这个新表述里，resolve 一个 critical pair 就是把这个 critical pair「补完」成一个 rewrite loop。

**算法（Construct critical pair）.** 输入两条规则 $(u, v)$ 与 $(u^\prime, v^\prime)$，外加一个 overlap position $i$，其中 $0\leq i<|u|$。返回一个三元组 $(t_1, t_2, p)$，其中 $t_1$ 与 $t_2$ 是 term，$p$ 是满足 $\operatorname{src}(p)=t_1$、$\operatorname{dst}(p)=t_2$ 的 rewrite path。

1. 若 $i+|u^\prime|\leq|u|$，则这是一个第一类 overlap；$u=xu^\prime z$，$x$ 与 $z$ 为某两个 term。
   1. 令 $x:=u[:i]$（$u$ 长为 $i$ 的前缀），$z:=u[i+|u^\prime|:]$（$u$ 长为 $|u|-|u^\prime|-i$ 的后缀）。
   2. 令 $t_1:=v$，即用第一条规则重写 $u$ 的结果。
   3. 令 $t_2:=xv^\prime z$，即用第二条规则重写 $u$ 的结果。
   4. 令 $p:=(v\Rightarrow u)\circ x\triangleleft(u^\prime\Rightarrow v^\prime)\triangleright z$。这是一条从 $t_1$ 到 $t_2$ 的 rewrite path。
2. 否则，这是一个第二类 overlap；$u=xy$ 且 $u^\prime=yz$，$x$、$y$、$z$ 为某三个 term。
   1. 令 $x:=u[:i]$（$u$ 长为 $i$ 的前缀），$z:=u^\prime[|u|-i:]$（$u^\prime$ 长为 $|u^\prime|-|u|+i$ 的后缀）。（我们实际上不需要 $y:=u[i:]=u^\prime[:|u|-i]$。）
   2. 令 $t_1:=vz$，即用第一条规则重写 $xyz$ 的结果。
   3. 令 $t_2:=xv^\prime$，即用第二条规则重写 $xyz$ 的结果。
   4. 令 $p:=(v\Rightarrow u)\triangleright z\circ x\triangleleft(u^\prime\Rightarrow v^\prime)$。
3. 返回三元组 $(t_1, t_2, p)$。

**算法（Resolve critical pair）.** 输入 term $u$ 与 $v$，以及一条满足 $\operatorname{src}(p)=u$、$\operatorname{dst}(p)=v$ 的 rewrite path $p$。记录一个 rewrite loop，并可能加入一条新规则；若加了规则则返回 true。

1. 若 $u=v$，则 $p$ 本身已经是一个 loop；记录它并返回 false。
2. 用 `symbols-terms-and-rules.tex` 的 Normal form algorithm using rule trie 算法计算 $u$ 的 normal form，得到 $\tilde{u}$ 与 $p_1$。
3. 用同一个算法计算 $v$ 的 normal form，得到 $\tilde{v}$ 与 $p_2$。
4. 用 `symbols-terms-and-rules.tex` 的 Weighted shortlex order 算法比较 $\tilde{u}$ 与 $\tilde{v}$。
5. 若 $\tilde{u}=\tilde{v}$，记录一个以 $\tilde{u}=\tilde{v}$ 为 basepoint 的 loop $p_1^{-1}\circ p\circ p_2$，返回 false。
6. 若 $\tilde{v}<\tilde{u}$，记录规则 $(\tilde{u}, \tilde{v})$，记录一个以 $\tilde{u}$ 为 basepoint 的 loop $p_2^{-1}\circ p^{-1}\circ p_1\circ (\tilde{u}\Rightarrow \tilde{v})$，返回 true。
7. 若 $\tilde{u}<\tilde{v}$，记录规则 $(\tilde{v}, \tilde{u})$，记录一个以 $\tilde{v}$ 为 basepoint 的 loop $p_1^{-1}\circ p \circ p_2 \circ (\tilde{v}\Rightarrow \tilde{u})$，返回 true。
8. 若 $\tilde{u}$ 与 $\tilde{v}$ 不可比，报错。

Rewrite loop 不只是一个理论工具；我们对 Knuth-Bendix 算法的实现遵循 Heyworth 与 Johnson 2005 年的《Logged Rewriting for Monoids》以及 Guiraud、Malbos 与 Mimram 2013 年的《A Homotopical Completion Procedure with Applications to Coherence of Monoids》，会把描述已 resolve 的 critical pair 的那些 rewrite loop 编码并记录下来。这使得 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 的 Homotopy Reduction 一节里的 minimal requirement 计算成为可能。只有 local rule 会进入 minimization，所以我们只记录涉及 local rule 的 rewrite loop。如果一个 requirement machine 实例只打算用于 generic signature query 而不做 minimization，那么 rewrite loop 根本不会被记录。

### An optimization

现在我们已经知道怎么处理单个 overlap、怎么 resolve 一个 critical pair，下一块代码要解决的是枚举所有候选 overlap。如果我们的 rewrite rule 真是任意的，那就得考虑所有可能的组合：对每条 rewrite rule $u_1\Rightarrow v_1$、对每条 rewrite rule $u_2\Rightarrow v_2$、对每个位置 $i<|u_1|$，都要检查 $u_1$ 与 $u_2$ 的相应 subterm 是否相同。但我们能做得更好。Requirement machine 从 protocol component 自底向上构造的方式，以及把 rewrite rule 划分成 imported rule 与 local rule 的做法，使得某些规则对之间的 overlap 根本不必考虑：

- 不需要在 imported rule 之间找 overlap。imported rule 固然可能与另一条 imported rule overlap，但这类 critical pair 全都是 trivial 的，不必再 resolve 一遍。
- 不需要在 imported rule 与 local rule 之间找 overlap。imported rule 不可能与 local rule overlap。

于是只剩下两种有意思的配对：

- 一条 local rule 可以与另一条 local rule overlap。
- 一条 local rule 可以与一条 imported rule overlap。

我们接下来证明事实确实如此。首先，假设两条 imported rule overlap。我们依次考虑三种可能：

- 存在一个第一类 overlap。
- 存在一个第二类 overlap，且第二条规则的左侧以一个 associated type symbol 开头。
- 存在一个第二类 overlap，且第二条规则的左侧以一个 protocol symbol 开头。

三种情形下我们都将得出结论：两条规则要么来自同一个 protocol component，要么来自两个不同的 component 而其中一个 import 了另一个。这意味着那个 critical pair 现在已经是 trivial 的了——它在「包含另一个的那个 protocol component」做 completion 时就已经被 resolve 掉了。

第一种情形下，立刻可以看出两条规则都是从 `P` 的 protocol component 导入的：

$$\begin{aligned} &[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]\\ &[\texttt{P}|\texttt{A}] \end{aligned}$$

第二种情形下，`P` 与 `Q` 要么在同一个 protocol component 里，要么 `Q` 是 `P` 的一个 protocol dependency，因为我们有 $G_\texttt{P}\vdash[\texttt{Self.A: Q}]$：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot{}&[\texttt{Q}|\texttt{B}]\\ &[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}|\texttt{C}] \end{aligned}$$

最后一种情形同样推出 `Q` 是 `P` 的一个 protocol dependency：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot{}&[\texttt{Q}]\\ &[\texttt{Q}]\cdot[\texttt{R}] \end{aligned}$$

接下来我们断言 imported rule 不可能与 local rule overlap。在一个 generic signature 的 query machine 或 minimization machine 里，local rule 的两侧都以一个 generic parameter symbol 开头。而 imported rule 的左侧不可能以 generic parameter symbol 开头，也不可能含有 generic parameter symbol，断言得证。在一个 protocol 的 requirement machine 里，我们同样可以排除 imported rule 与 local rule 之间的第一类 overlap，因为两条规则必须以同一个 protocol symbol 或 associated type symbol 开头，因而来自同一个 protocol component。现在假设一个 protocol machine 出现了第二类 overlap。我们来证明：如果第二条规则——左侧为 $[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}|\texttt{C}]$ 的那条——是 local rule，那么第一条也是：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot{}&[\texttt{Q}|\texttt{B}]\\ &[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}|\texttt{C}] \end{aligned}$$

如前所述，`Q` 必然是 `P` 的一个 protocol dependency。但这一次我们多了一条假设：`Q` 属于**当前**的 protocol component，于是 `P` 的出现意味着 `P` **也**必须是 `Q` 的一个 protocol dependency。这样 `P` 与 `Q` 互相依赖，实际上属于同一个 component；因此两条规则都是 local 的。

### Another optimization

如果固定一条规则和一个位置，我们可以通过在 **rule trie** 里做一次查找来找出涉及这条规则与这个位置的所有 overlap；这个 trie 就是我们先前在 `symbols-terms-and-rules.tex` 的 The Normal Form Algorithm 一节里用来加速 term reduction 的那个。这进一步削减了枚举 overlap 的工作量。底层数据结构虽然相同，但这里的查找算法与 term reduction 用的那个不一样：我们必须枚举出所有匹配，而不是找到第一个就停。

考虑一组 rewrite rule，其左侧分别为 term $a$、$ab$、$bc$、$bd$ 与 $acd$。左侧为 $ab$ 的那条规则与除 $acd$ 之外的所有规则都有 overlap。下面是这个 rule trie，粗边框表示该节点关联着一条 rewrite rule：

```
root
├── (a)            ← 粗框：有规则
│   ├── (b)        ← 粗框：有规则
│   └── c
│       └── (d)    ← 粗框：有规则
└── b
    ├── (c)        ← 粗框：有规则
    └── (d)        ← 粗框：有规则
```

这张图表示的是：五条规则的左侧 $a$、$ab$、$acd$、$bc$、$bd$ 按符号逐个下降存进一棵 trie；只有 $a$、$ab$、$acd$、$bc$、$bd$ 对应的节点（带括号那些）挂着规则，中间节点 `c`（$a$ 之下）与 `b`（根之下）只是路径上的过渡。

> 译注：原书此处是一张 TikZ 树图，这里用 ASCII 树转述；图的原貌见官方 PDF 对应章节。

在检查左侧 $ab$ 是否有 overlap 时，我们做两次查找：

- 在位置 0，我们查 $ab$。从根出发，先碰到 $a$ 的规则，再碰到 $ab$（这就是我们自己这条规则的左侧，所以跳过）。后一个节点是叶子，于是搜索结束。
- 在位置 1，我们查 $b$。$b$ 节点本身没有存 rewrite rule，但它有子节点。输入序列已经走完了，所以我们递归访问它所有的子节点，找到最后两个 overlap 候选：$bc$ 与 $bd$。

这种新的 trie 查找可以看成一个 coroutine 或迭代器，随着搜索推进逐个 yield 出零个或多个结果。我们把它实现成一个接受 callback 的高阶函数。

**算法（Overlap lookup in rule trie）.** 输入一个 term $t$、一个满足 $0\leq i<|t|$ 的偏移 $i$，以及一个 callback。对每条满足「$t[i:]$ 是 $u$ 的前缀」或「$u$ 是 $t[i:]$ 的前缀」的规则 $(u, v)$，用该规则调用一次 callback。

1. （初始化）令 $N$ 为 trie 的根节点。
2. （末端）若 $i=|t|$，说明 term 已经走完。对 $N$ 的所有子节点做一次先序遍历，凡是关联了 rewrite rule 的子节点，就用那条规则调用 callback（这对应 $t[i:]$ 是每个 $u$ 的前缀这一情形）。
3. （下降）令 $s_i$ 为 $t$ 的第 $i$ 个符号。在 $N$ 里查找 $s_i$。若没有这样的子节点，返回。
4. （子节点）否则称这个子节点为 $M$。若 $M$ 关联了一条规则 $u\Rightarrow v$，就用这条规则调用 callback（这时 $u$ 是 $t[i:]$ 的前缀）。
5. （前进）令 $N \leftarrow M$，$i \leftarrow i+1$，回到第 2 步。

下一个算法把 Overlap lookup in rule trie 算法的结果喂给 Construct critical pair 算法，从而构造出我们所有 rewrite rule 之间的 critical pair 列表。在 resolve 完这些 critical pair 之后，我们还得再查一遍 overlap，以防新加进来的规则引入了新的 overlap。为了避免重复劳动，下面这个算法维护了一个已访问 overlap 的集合，这样就能跳过那些我们已知被 resolve 过的 critical pair，不必再构造与 resolve 一次。

**算法（Find overlapping rules）.** 输入一串 rewrite rule，输出一串 critical pair。同时查询并更新一个已访问 overlap 的集合 $V$。

1. （初始化）令 $i \leftarrow 0$。令 $n$ 为 local rule 的总数。初始化空的输出列表。
2. （外层检查）若 $i=n$，就做完了，返回输出列表。
3. （取规则）令 $(u,v)$ 为第 $i$ 条 local rule。若这条规则被标记为 **left-simplified**、**right-simplified** 或 **substitution-simplified**，就整条跳过，转到第 7 步。否则令 $j \leftarrow 0$。
4. （内层检查）若 $j=|u|$，就做完了，转到第 7 步。
5. （找 overlap）用 Overlap lookup in rule trie 算法，找出所有「左侧是符号区间 $u[j:]$ 的前缀」或「$u[j:]$ 是其左侧的前缀」的规则。对每条匹配的规则 $(u^\prime, v^\prime)$：
   1. 若 $(u^\prime, v^\prime)$ 被标记为 **left-simplified**、**right-simplified** 或 **substitution-simplified**，跳过这条规则。
   2. 若 $((u, v),\,(u^\prime, v^\prime),\,j)\in V$，跳过这条规则。
   3. 否则令 $V\leftarrow V \cup \{((u, v),\,(u^\prime, v^\prime),\,j)\}$，并用 Construct critical pair 算法为这个 overlap 构造一个 critical pair。它返回一个三元组 $(t_1, t_2, p)$；把它加入输出列表。
6. （内层循环）令 $j\leftarrow j+1$，回到第 3 步。
7. （外层循环）令 $i\leftarrow i+1$，回到第 2 步。

> 译注：原书第 3 步的赋值 $ \leftarrow 0$ 漏掉了左边的变量名，按第 4 步与第 6 步对 $j$ 的使用，应为 $j \leftarrow 0$；又第 6 步说「回到第 3 步」，而按结构应回到第 4 步（内层检查）——第 3 步会重新取规则并把 $j$ 清零，那样内层循环永不前进。两处均疑为笔误，本译文照译原文，以本译注的读法为准。

现在我们可以描述 Knuth-Bendix completion procedure 的主循环了：它反复寻找并 resolve critical pair，直到不再有非 trivial 的 critical pair 为止。这个过程可能不终止，我们可能会一直发现新的 critical pair、一直加新规则来 resolve 它们，没完没了。为了防止失败时陷入死循环，我们实现了一个终止检查；如果觉得已经干了太多活，就放弃构造 convergent rewriting system。前面已经好几次提到 **left-simplified**、**right-simplified** 与 **substitution-simplified** 这三个标记，它们由规则简化 pass 设置，前两个描述在本章 Rule Simplification 一节，第三个在 `property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)） 的 Substitution Simplification 一节。这些 pass 在下面的主循环里会在恰当的时机被调用。

**算法（Knuth-Bendix completion procedure）.** 输入一串 rewrite rule。记录新的 rewrite rule 以及 rewrite loop，返回成功或失败。成功时，这些 rewrite rule 定义了一个 convergent rewriting system。失败意味着我们得到了一条 non-orientable 的 rewrite rule，或者触发了终止检查。

1. 清除标志位。
2. 用 Find overlapping rules 算法构造一串 critical pair。
3. 用 Left-simplify rules 算法对所有规则做 left-simplify。
4. 用 Resolve critical pair 算法逐个 resolve critical pair；若加入了任何新 rewrite rule，置上标志位。
5. 用 Right-simplify rules 算法对所有 rewrite rule 做 right-simplify。
6. 用 `property-map.tex` 的 Simplify substitution terms 算法对所有 rewrite rule 做 substitution-simplify。
7. 检查规则数、term 长度或 concrete 嵌套深度是否超限；若超限，返回失败。
8. 若标志位被置上了，回到第 1 步。否则返回成功。

### Termination

终止检查由几个 frontend flag 控制：

- `-requirement-machine-max-rule-count=<value>` 把 local rule 的最大条数设为 `value`。imported rule 不计入这个总数，所以现实代码很难撞上它。默认上限是 4000 条 local rule。
- `-requirement-machine-max-rule-length=<value>` 把一条规则里 term 的最大长度设为 `value`。实际的量还要再加上**用户手写**的最长规则的长度；所以这个限制针对的是相对的「增长量」，而不是用户写下的 type parameter 本身的长度。默认值是 12。
- `-requirement-machine-max-concrete-nesting=<value>` 把 concrete type 的嵌套深度上限设为 `value`，用来防止 substitution simplification 构造出 `G<G<G<...>>>` 这样的无穷类型。与规则长度限制一样，实际上限还要加上用户手写规则的最大嵌套深度。默认值是 30。

三者之中第一个就足以检测出不终止，但 completion 要记满那么多条规则需要一两秒。另外两个限制则通过更早地拒绝明显非法的程序来改善用户体验。规则长度限制之所以设成相对的而不是一刀切地禁止长度 12 的 term，是为了让各种病态但合法的情形得以通过，否则它们会被毫无必要地拒绝。

举例来说，下面这个 protocol 呈现的是 monoid $\mathbb{Z}_{14}$，定义了一条长度为 14 的规则，所以绝对的规则长度上限其实是 $14+12=26$。completion 不会加入更长的规则，所以我们毫无问题地接受它：

```swift
protocol Z14 {
  associatedtype A: Z14
    where Self == Self.A.A.A.A.A.A.A.A.A.A.A.A.A.A
}
```

如果 completion 是在为 minimization 构造 rewrite system 时失败的，我们手上有某个 protocol 或 generic 声明对应的 source location。错误会在这个 source location 上报出来，然后我们继续做 minimization，产出一张空的 requirement 列表。如果 completion 是在一个从既有 generic signature 或 protocol component 构造出的 rewrite system 上失败的，就没有可用于诊断的 source location；编译器会 dump 出整个 rewrite system 并以 fatal error 中止。后一种情形很少见；既然我们已经成功地从用户手写的 requirement 构造出了 generic signature，那就应该能够为它再构造一次 rewrite system。

### Debugging flags

有一对调试选项可以帮助我们理解 completion procedure 的运作；两者可以同时打开（原注：用一个 `-debug-requirement-machine=` flag，子 flag 之间用逗号分隔），但要当心它们会产生海量输出：

- `-debug-requirement-machine=completion` 会 dump 出所有 overlap 的规则与 critical pair。
- `-debug-requirement-machine=add` 会 dump 出 resolve critical pair 过程中得到的所有 rewrite rule 与 rewrite loop。

## Rule Simplification

我们给自己的 convergent rewriting system 再加两个条件：

1. 没有哪条规则的左侧能被别的规则归约。
2. 没有哪条规则的右侧能被别的规则归约。

满足这两条的 rewrite system 分别叫作 **left-reduced** 与 **right-reduced**；两条都满足就直接叫 **reduced**。任何 convergent rewriting system 都能通过一对（可能会删规则也可能会加规则的）简化 pass 变成 reduced 的。

在我们的实现里，我们并**不真的**删规则，因为别处要靠规则的下标做稳定引用；取而代之的是置上一对规则标记 **left-simplified** 与 **right-simplified**，并把这条规则从 rule trie 里删掉。这两个标记前面已经提过好几次，现在我们揭晓它们的用途。这也会引出后续的理论，为本章余下两节铺路。

### Left simplification

如果一条 rewrite rule $u_1\Rightarrow v_1$ 的左侧能被另一条 rewrite rule $u_2\Rightarrow v_2$ 归约，那么 $u_1=xu_2z$（$x$、$z\in A^*$），按本章 Overlapping rules 的定义，这就是一个第一类 overlap。一旦我们 resolve 了所有 critical pair，第一条规则就完全不需要了；我们知道在一个 convergent rewriting system 里，归约 overlap term $u_1:=xu_2z$ 的两种方式会产出相同的结果：

```
                         u₁
        (u₁⇒v₁)  ↙                ↘  x(u₂⇒v₂)z
              v₁                      xv₂z
              ↓                        ↓
             ···                      ···
                 ↘                ↙
                         t′
```

这张图断言的是：$u_1$ 既可以被它自己那条规则一步打到 $v_1$，也可以被 $u_2\Rightarrow v_2$ 就地打到 $xv_2z$，而两边最终都归约到同一个 $t^\prime$——所以第一条规则是多余的。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

**left simplification** 算法逐条检查规则的左侧，一旦发现某个 subterm 与另一条规则的左侧相同，就给这条规则打上标记。

**算法（Left-simplify rules）.** 输入 local rule 列表。有副作用。

1. （初始化）令 $n$ 为 local rule 总数，置 $i:=0$。
2. （外层检查）若 $i=n$，返回。否则设 $(u, v)$ 为第 $i$ 条 local rule，置 $j:=0$。
3. （内层检查）若 $j=|u|$，转到第 8 步。
4. （搜索）在 rule trie 里查找 $u[:j]$，这里 $u[:j]$ 指 $u$ 长为 $|u|-j$ 的后缀。
5. （判定）若 trie 查找没有结果，或者返回的就是 $(u, v)$ 自己（这只在 $j=0$、也就是 $u[:j]=u$ 时可能发生），转到第 7 步。
6. （标记）否则，$u$ 有一个 subterm 等于某条别的规则的左侧。把 $u\Rightarrow v$ 标记为 **left-simplified**，转到第 7 步。
7. （内层循环）令 $j\leftarrow j+1$，回到第 3 步。
8. （外层循环）令 $i\leftarrow i+1$，回到第 2 步。

> 译注：原书第 4 步把 $u[:j]$ 描述成「$u$ 长为 $|u|-j$ 的后缀」，而按本章前文一贯的记法，$u[:j]$ 是长为 $j$ 的**前缀**，长为 $|u|-j$ 的后缀应写作 $u[j:]$。从算法语义看（要在 trie 里查以位置 $j$ 开头的那一段），这里要的确实是后缀，疑为记号笔误，以文字描述为准。

### Right simplification

另一种情形是：某条规则 $(u, v)$ 的右侧 $v$ 不是 reduced 的，于是 $v\rightarrow v^\prime$，经由某条 positive rewrite path $p_v$。现在假设我们有一条 positive rewrite path $x(u\Rightarrow v)z\circ p$，其中 $\operatorname{dst}(p)$ 是某个 reduced term $t^\prime$。当我们用 $x(u\Rightarrow v)z$ 把 $xuz$ 归约成 $xvz$ 之后，接下来有两种选择：可以沿着 $p$ 走，也可以用 $x\triangleleft p_v \triangleright z$ 把 $xvz$ 归约成 $xv^\prime z$。由 confluence，第二种选择必然经由某条满足 $\operatorname{src}(p^\prime)=xv^\prime z$、$\operatorname{dst}(p^\prime)=t^\prime$ 的 positive rewrite path $p^\prime$ 把我们带到 $t^\prime$。于是我们记录一条新规则 $u\Rightarrow v^\prime$，它让 $u\Rightarrow v$ 作废：

```
              xuz
               │ x(u⇒v)z              ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇢ ⇘   x(u⇒v′)z（虚线）
               ↓                                                  ↓
              xvz ───── x ◁ p_v ▷ z ────────────────────────→   xv′z
               │ p                                                │ p′
               ↓                                                  │
              t′  ←─────────────────────────────────────────────── ┘
```

这张图断言的是：从 $xuz$ 出发无论走「旧规则再沿 $p$」还是走「新规则 $u\Rightarrow v^\prime$ 再沿 $p^\prime$」，都到达同一个 reduced term $t^\prime$；虚线那条就是新加的规则。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

**right simplification** 算法通过尝试归约每条 rewrite rule 的右侧，输出一个 right-reduced 的 rewrite system。left simplification 不需要记录新的 rewrite rule，因为 completion 已经 resolve 了所有第一类 overlap；right simplification 则既要给已有规则打上「已简化」的标记，也确实要记录新规则。新规则与旧规则之间由一个 rewrite loop 关联起来：

```
                 v
      (v⇒u)  ↙        ↖  p_v⁻¹
        u ── (u⇒v′) ──⇢ v′
```

这张图断言的是：以 $v$ 为 basepoint 绕一圈——先反用旧规则回到 $u$，再用新规则（虚线）到 $v^\prime$，最后沿 $p_v$ 的逆回到 $v$——从而把新旧两条规则记录在同一个 rewrite loop 里。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

**算法（Right-simplify rules）.** 输入 local rule 列表。有副作用。

1. （初始化）令 $n$ 为 local rule 总数，置 $i:=0$。
2. （检查）若 $i=n$，返回。否则令 $(u, v)$ 为第 $i$ 条 local rule。
3. （归约）对 $v$ 施用 `symbols-terms-and-rules.tex` 的 Normal form algorithm using rule trie 算法，得到 term $\tilde{v}$ 与 rewrite path $p_v$。若 $v=\tilde{v}$，说明右侧 $v$ 本来就是 reduced 的，转到第 7 步。
4. （记录）调用 `symbols-terms-and-rules.tex` 的 Record rule 算法，加入一条新的 rewrite rule $(u, \tilde{v})$。
5. （关联）加入以 $u$ 为 basepoint 的 rewrite loop $(u\Rightarrow v)\circ p\circ(v^\prime\Rightarrow u)$，把旧规则 $u\Rightarrow v$ 与新规则 $u\Rightarrow v^\prime$ 关联起来。
6. （标记）把旧规则标记为 **right-simplified**。
7. （循环）$i$ 加一，回到第 2 步。

> 译注：算法第 3 步与第 4 步把归约结果记作 $\tilde{v}$ 与 $p_v$，第 5 步却改用 $v^\prime$ 与 $p$，两套记号指的是同一样东西（正文散文部分用的是 $v^\prime$ 与 $p_v$）。原书此处记号不统一，照译。

我们对这两个 pass 之有效性的论证，是从「我们已经有一个 convergent rewriting system」这个假设出发的，也就是说 completion 已经做完了。而实际上，Knuth-Bendix completion procedure 算法在 completion 期间反复运行这两个 pass，每轮 critical pair resolution 各跑一次。这么做有好处：之后就可以不再考虑涉及已简化规则的 overlap。只要我们在**计算完** critical pair 之后、**resolve 它们之前**做 left simplification（resolve 可能会加新规则），这个策略就仍然是 sound 的。这把 left simplification 的候选范围收窄到那些 overlap 已经被考虑过的规则。至于 right simplification pass，它其实在任何时刻跑都没问题；我们选择在 resolve critical pair 之后跑。

### Related concepts

我们先前在 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Requirement Minimization 一节见过，generic signature 里的 same-type requirement 也受制于类似的 left-reduced 与 right-reduced 条件。这里确实有联系，因为正如 `minimization.tex` 的 Building Requirements 一节将会说明的，一个 generic signature 的 minimal requirement 归根结底是从一个 reduced rewrite system 的规则构造出来的。不过记号上有几处差别：

- 「左」与「右」的角色是反的，因为 requirement 用的是另一套约定：在一条 reduced 的 same-type requirement $[\texttt{U == V}]$ 里我们有 $\texttt{U} < \texttt{V}$，而在一条 rewrite rule $(u, v)$ 里我们有 $v<u$。
- reduced 的 same-type requirement 要求左右两侧之间的「距离」最短，所以若 `T`、`U`、`V` 全都等价且 $\texttt{T}<\texttt{U}<\texttt{V}$，对应的 requirement 是 $[\texttt{T == U}]$ 与 $[\texttt{U == V}]$。而如果我们有三个 term $t$、$u$、$v$ 满足 $t<u<v$，那么对应的两条 rewrite rule 会是 $(u, t)$ 与 $(v, t)$。

这些差别源自最初的 `GenericSignatureBuilder` minimization 算法，那个算法被描述成在一张连通分量图上求最小生成树。该算法输出的 reduced requirement 这一概念后来成了 Swift 稳定 ABI 的一部分。在 `minimization.tex` 的 Building Requirements 一节里我们会说明：一个 reduced rewrite system 里的一串 rewrite rule，经由某个变换定义出一串 reduced requirement。

我们所说的 reduced rewrite system，在文献里有时叫作「normalized」、「canonical」或「inter-reduced」。我们的 rewrite system 还实现了第三个简化 pass，叫 **substitution simplification**。它归约的是出现在 superclass、concrete type 与 concrete conformance symbol 里的 substitution term。我们将在 `property-map.tex` 里讨论它。

## Associated Types

一条 conformance rule $t\cdot[\texttt{P}]\Rightarrow t$ 总是与一条 associated type rule $[\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}]$ overlap，而 resolve 这个 critical pair 会定义出一条规则 $t\cdot\texttt{A}\Rightarrow t\cdot[\texttt{P}|\texttt{A}]$（除非右侧还能继续归约）。这些 rewrite rule 把代表 unbound type parameter 的 term 归约成 bound type parameter。于是我们将看到 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Bound Type Parameters 一节里那对 bound / unbound type parameter 在我们的重写系统里是怎样体现的。

> 译注：这正是本库在二进制里看到的那一侧结果。mangled name 与 `__swift5_assocty` 记录里写下的永远是 bound 形式（`T.[P]A`），因为它才是 reduced term；本库解析 associated type witness、以及离线布局引擎把 `C.Index` 这类 dependent member type 解开时，处理的就是这种已经绑好 protocol 的形状。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md) 与 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

**例.** 我们来看这一对 protocol 声明，以及 protocol generic signature $G_\texttt{P}$：

```swift
protocol Q {
  associatedtype B
}

protocol P {
  associatedtype A: Q
}
```

Protocol `P` 有一条 associated conformance requirement $[\texttt{Self.[P]A: Q}]_\texttt{P}$，而 $G_\texttt{P}$ 有一条 conformance requirement $[\texttt{τ}_{0,0}\texttt{: P}]$，所以 protocol dependency graph 有两条边 $G_\texttt{P}\prec\texttt{P}$ 与 $\texttt{P}\prec\texttt{Q}$。我们先为 `Q` 构造 rewrite system。$G_\texttt{P}$ 的 rewrite system 从 `P` 与 `Q` 导入规则：

$$[\texttt{Q}]\cdot\texttt{B}\Rightarrow[\texttt{Q}|\texttt{B}] \tag{1}$$

$$[\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}] \tag{2}$$

$$[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{P}|\texttt{A}] \tag{3}$$

$$[\texttt{P}|\texttt{A}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}] \tag{*4}$$

$$\tau_{0,0}\cdot[\texttt{P}]\Rightarrow\tau_{0,0} \tag{5}$$

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P}|\texttt{A}] \tag{*6}$$

这些 rewrite rule 可以这样归类：

- associated type rule：(1) 与 (2)。
- conformance requirement：(3) 与 (5)。
- 由 completion 加入的规则用星号标出：(*4) 与 (*6)。

我们略去了 identity conformance rule $[\texttt{Q}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]$ 与 $[\texttt{P}]\cdot[\texttt{P}]\Rightarrow[\texttt{P}]$；在这个例子里它们只会让排版更乱。它们稍后会在本章 More Critical Pairs 一节那个关于 protocol `S` 的例子里派上用场。

现在我们一步一步走一遍这个构造。Protocol `Q` 不依赖任何别的 protocol。`Q` 的 rewrite system 就只有规则 (1)：

$$[\texttt{Q}]\cdot\texttt{B}\Rightarrow[\texttt{Q}|\texttt{B}] \tag{1}$$

Protocol `P` 导入 `Q` 的这一条规则，再加上规则 (2) 与 (3)：

$$[\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}] \tag{2}$$

$$[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{P}|\texttt{A}] \tag{3}$$

我们要检查规则 (2) 与 (3) 的左侧与别的规则有没有 overlap。规则 (2) 与任何规则都不 overlap。规则 (3) 与规则 (1) 在 term $[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}]\cdot\texttt{B}$ 上 overlap：

$$\begin{aligned} [\texttt{P}|\texttt{A}]\cdot{}&[\texttt{Q}]\\ &[\texttt{Q}]\cdot\texttt{B} \end{aligned}$$

规则 (3) 是 `P` 的 local rule，而 (1) 是从 `Q` 导入的。这个 critical pair 的两侧分别归约到 $[\texttt{P}|\texttt{A}]\cdot\texttt{B}$ 与 $[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$。Resolve 它就引入了规则 (*4)：

$$[\texttt{P}|\texttt{A}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}] \tag{*4}$$

我们同时记录一个 rewrite loop，它用规则 (3) 与 (1) 定义出规则 (*4)：

```
                              [P|A]·[Q]·B
     ([P|A]·[Q] ⇒ [P|A])·B  ↙              ↖  [P|A]·([Q|B] ⇒ [Q]·B)
   [P|A]·B ──────────────────────────────────⇢ [P|A]·[Q|B]
              ([P|A]·B ⇒ [P|A]·[Q|B])   （虚线 = 新规则 *4）
```

这张图断言的是：以 $[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}]\cdot\texttt{B}$ 为 basepoint 绕一圈——先用规则 (3) 去掉 $[\texttt{Q}]$，再用新规则 (*4)，最后反用规则 (1) 回到起点——因此新规则完全由 (3) 与 (1) 导出，不是凭空加的。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

我们再检查一遍 local rule 左侧的 overlap——现在是 (2)、(3) 与 (4)。可以看到不再有 critical pair 剩下，`P` 的 convergent rewriting system 就构造好了。

最后我们构造 $G_\texttt{P}$ 的 rewrite system。我们从 `Q` 与 `P` 导入全部规则，再加一条对应 conformance requirement $[\texttt{τ}_{0,0}\texttt{: P}]$ 的新 local rule：

$$\tau_{0,0}\cdot[\texttt{P}]\Rightarrow\tau_{0,0} \tag{5}$$

我们要检查规则 (5) 的左侧有没有 overlap。确实，规则 (5) 与规则 (2) 在 term $\tau_{0,0}\cdot[\texttt{P}]\cdot\texttt{A}$ 上 overlap：

$$\begin{aligned} \tau_{0,0}\cdot{}&[\texttt{P}]\\ &[\texttt{P}]\cdot\texttt{A} \end{aligned}$$

Resolve 这个 critical pair 引入规则 (*6)：

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P}|\texttt{A}] \tag{*6}$$

我们同时记录一个 rewrite loop，它用规则 (5) 与 (2) 定义出规则 (*6)：

```
                            τ_0_0·[P]·A
     (τ_0_0·[P] ⇒ τ_0_0)·A  ↙            ↖  τ_0_0·([P|A] ⇒ [P]·A)
   τ_0_0·A ──────────────────────────────── ⇢ τ_0_0·[P|A]
              (τ_0_0·A ⇒ τ_0_0·[P|A])   （虚线 = 新规则 *6）
```

这张图断言的是：新规则 (*6) 同样是一个 rewrite loop 的一条边，另外两条边分别是 conformance rule (5) 与反向的 associated type rule (2)。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

此时可能还有涉及规则 (5) 或 (*6) 的 overlap；快速查一遍会发现没有剩下的，于是 $G_\texttt{P}$ 的 convergent rewriting system 就有了。

现在到了有意思的部分。考虑 $G_\texttt{P}$ 的这两个 type parameter 及其对应的 term：

1. unbound type parameter `τ_0_0.A.B`，term 为 $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$。
2. bound type parameter `τ_0_0.[P]A.[Q]B`，term 为 $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$。

第二个 term 是 reduced 的，所以第一个必然归约到第二个。Term reduction 输出一条 positive rewrite path $p$，满足 $\operatorname{src}(p)=\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ 且 $\operatorname{dst}(p)=\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$。这条 path 用到了 completion 加入的规则 (4) 与 (6)：

$$p := (\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P}|\texttt{A}])\cdot\texttt{B}\circ \tau_{0,0}\cdot([\texttt{P}|\texttt{A}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{B}|\texttt{Q}])$$

> 译注：原书这条公式末尾写的是 $[\texttt{B}|\texttt{Q}]$，而按规则 (*4) 与前后文应为 $[\texttt{Q}|\texttt{B}]$（associated type symbol 的写法是「protocol \| associated type 名」），疑为笔误，以 $[\texttt{Q}|\texttt{B}]$ 为准。

下面是 $p$ 的图示：

```
τ_0_0·A·B ────→ τ_0_0·[P|A]·B ────→ τ_0_0·[P|A]·[Q|B]
```

这张图断言的是：$p$ 是一条长度为 2 的 positive rewrite path，两步分别由规则 (6) 与 (4) 完成。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

这里有一种「拉伸望远镜」式的效果：term reduction 从左到右逐个处理 name symbol，把它们替换成 associated type symbol。顺带一提，如果我们拿到的是一个**非法**的 type parameter，比如 `τ_0_0.A.A`，那么 term 会归约到 $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot\texttt{A}$ 就再也归约不动了；最后那个 name symbol `A` 无法被「解析」，因为 type parameter `τ_0_0.A` 根本**没有**叫 `A` 的成员类型。

标准 term $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ 之所以归约到 $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$，是因为 unbound type parameter `τ_0_0.A.B` 与 bound type parameter `τ_0_0.[P]A.[Q]B` 等价，而后者是前者的 reduced type。这个等价成立是因为我们能推出一条 same-type requirement，且这条 same-type requirement 的左侧就是 reduced type——没有更小的 type parameter 能被证明与之等价：

$$G_\texttt{P}\vdash[\texttt{τ}_{0,0}\texttt{.[P]A.[Q]B == τ}_{0,0}\texttt{.A.B}]$$

这条 same-type requirement 的一种可能 derivation 如下：

1. $[\tau_{0,0}\texttt{: P}]$ （**Conf**）
2. $[\tau_{0,0}\texttt{.[P]A == }\tau_{0,0}\texttt{.A}]$ （**AssocBind** 1）
3. $[\tau_{0,0}\texttt{.A == }\tau_{0,0}\texttt{.[P]A}]$ （**Sym** 2）
4. $[\tau_{0,0}\texttt{.[P]A: Q}]$ （**AssocConf** 1）
5. $[\tau_{0,0}\texttt{.A.B == }\tau_{0,0}\texttt{.[P]A.B}]$ （**SameName** 3 4）
6. $[\tau_{0,0}\texttt{.[P]A.B == }\tau_{0,0}\texttt{.A.B}]$ （**Sym** 5）
7. $[\tau_{0,0}\texttt{.[P]A.[Q]B == }\tau_{0,0}\texttt{.[P]A.B}]$ （**AssocBind** 4）
8. $[\tau_{0,0}\texttt{.[P]A.[Q]B == }\tau_{0,0}\texttt{.A.B}]$ （**Trans** 7 6）

由 `symbols-terms-and-rules.tex` 里那条「derivation 可转成 path」的定理，我们可以把这个 derivation 变换成一条从 $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ 到 $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$ 的 rewrite path，且只涉及初始 rewrite rule。我们把这条 path 叫作 $p^\prime$：

$$\begin{aligned} p^\prime := {}&(\tau_{0,0}\Rightarrow\tau_{0,0}\cdot[\texttt{P}])\cdot\texttt{A}\cdot\texttt{B} \circ \tau_{0,0}\cdot([\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}])\cdot\texttt{B}\\ &\circ\ \tau_{0,0}\cdot([\texttt{P}|\texttt{A}]\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}])\cdot\texttt{B} \circ \tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot([\texttt{Q}]\cdot\texttt{B}\Rightarrow[\texttt{Q}|\texttt{B}]) \end{aligned}$$

与 $p$ 不同，$p^\prime$ **不是** positive rewrite path，因为第一步与第三步是 negative 的：它们各自反着用了一条 conformance rule。我们可以把 $p^\prime$ 画成 rewrite graph 里的一条路径，negative rewrite step 向上走：

```
              τ_0_0·[P]·A·B                        τ_0_0·[P|A]·[Q]·B
            ↗                ↘                   ↗                 ↘
  τ_0_0·A·B                    τ_0_0·[P|A]·B                          τ_0_0·[P|A]·[Q|B]
```

这张图断言的是：$p^\prime$ 是一条「上—下—上—下」的锯齿形路径，两个向上的尖端正是反用 conformance rule 的那两步。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

现在我们手上有两条 parallel 的 rewrite path：$p$（由 normal form 算法输出）与 $p^\prime$（由我们的 derivation 构造）。它们的复合 $p^\prime\circ p^{-1}$ 是一个 rewrite loop；我们可以把它画成一张图，规则 (*4) 与 (*6) 用虚线箭头表示：

```
              τ_0_0·[P]·A·B                        τ_0_0·[P|A]·[Q]·B
            ↙                ↖                   ↙                 ↖
  τ_0_0·A·B ──────⇢ τ_0_0·[P|A]·B ──────⇢ τ_0_0·[P|A]·[Q|B]
```

这张图断言的是：底下那两条虚线（规则 (*6) 与 (*4)）与上方那条锯齿路径合起来围成一个闭合的 rewrite loop，也就是 $p^\prime\circ p^{-1}$。

> 译注：原书此处是一张 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

回想一下 completion 时记录的那两个 rewrite loop。我们把第一个 rewrite loop 在右侧 whisker 上 `B`；再把第二个 rewrite loop 在左侧 whisker 上 $\tau_{0,0}$。现在这两个 rewrite loop 都经过公共 term $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot\texttt{B}$。不严格地说，我们可以在这一点上把它们「粘」起来，粘出来的就是 $p^\prime\circ p^{-1}$。

事实上，在一个 convergent rewriting system 里，任给两条 parallel 的 rewrite path，只要取 resolve critical pair 所生成的那个有限 rewrite loop 集合，把每个 loop 经由 whisker 放进上下文，再沿公共边或公共顶点粘起来，我们总能把两条 path 之间的二维空间「铺满」。这个想法将在 `minimization.tex` 里进一步展开，眼下先留一段话供咀嚼：

> Term 由有限个符号生成，是 rewrite graph 里的零维对象。Rewrite path 由有限条 rewrite rule 生成，它们在 term 上定义了一个等价关系；它们是一维对象。Rewrite loop 由有限个 critical pair 生成，它们在 path 上定义了一个等价关系；它们是二维对象。

Path 上的等价关系叫作 **homotopy relation**。

**例.** 我们接着上一个例子，看看 unbound type parameter 出现在 requirement 里时是怎么归约的。我们新增一个 protocol `R`，并声明一个 `P` 的 constrained protocol extension，条件是 `Self.A.B` conform to `R`：

```swift
protocol R {}

protocol Q {
  associatedtype B
}

protocol P {
  associatedtype A: Q
}

extension P where Self.A.B: R {}
```

在类型检查这些声明时，我们需要为这个 protocol extension 构造一个 generic signature。我们从 extended type 带来的 requirement $[\texttt{τ}_{0,0}\texttt{: P}]$ 起步，再加上用户手写的 requirement $[\texttt{τ}_{0,0}\texttt{.A.B: R}]$。rewrite system 与上个例子一样，只是多了两条规则：

$$\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]\Rightarrow\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B} \tag{7}$$

$$\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}]\Rightarrow\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}] \tag{*8}$$

规则 (7) 对应用户手写的 requirement。规则 (*8) 由 completion 加入，它 resolve 的是规则 (7) 与 (6) 在 term $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]$ 上的 overlap：

$$\begin{aligned} &\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]\\ &\tau_{0,0}\cdot\texttt{A} \end{aligned}$$

我们记录一个 rewrite loop，它用规则 (4)、(6) 与 (7) 定义出规则 (*8)：

```
起点（basepoint）  τ_0_0·A·B·[R]
  ──(τ_0_0·A ⇒ τ_0_0·[P|A])·B·[R]────────────→  τ_0_0·[P|A]·B·[R]
  ──τ_0_0·([P|A]·B ⇒ [P|A]·[Q|B])·[R]────────→  τ_0_0·[P|A]·[Q|B]·[R]
  ──(τ_0_0·[P|A]·[Q|B]·[R] ⇒ τ_0_0·[P|A]·[Q|B])⇢ τ_0_0·[P|A]·[Q|B]   （虚线 = 新规则 *8）
  ──τ_0_0·([P|A]·[Q|B] ⇒ [P|A]·B)────────────→  τ_0_0·[P|A]·B
  ──(τ_0_0·[P|A] ⇒ τ_0_0·A)·B───────────────→  τ_0_0·A·B
  ──(τ_0_0·A·B ⇒ τ_0_0·A·B·[R])─────────────→  τ_0_0·A·B·[R]（回到起点）
```

这张图断言的是：新规则 (*8) 闭合了一个六节点的 rewrite loop——沿着它先把 unbound 的 `τ_0_0.A.B` 归约成 bound 的 `τ_0_0.[P|A].[Q|B]`，用新规则去掉 `[R]`，再一路反推回去——所以 (*8) 完全由 (4)、(6)、(7) 导出。

> 译注：原书此处是一张六节点的 tikzcd 交换图（有交叉边），按规约 §6.5 (a) 改用邻接表式的 Unicode 箭头列表转述，整体形状是一个绕一圈回到起点的闭合环；图的原貌见官方 PDF 对应章节。

注意这是一个第一类 overlap，所以规则 (7) 现在被标记为 **left-simplified**。于是规则 (*8) 完全取代了规则 (7)。规则 (*8) 在 minimization 中存活下来，映射成 requirement $[\texttt{τ}_{0,0}\texttt{.[P]A.[Q]B: R}]$，它出现在我们为这个 protocol extension 输出的 generic signature 里：

```
<τ_0_0 where τ_0_0: P, τ_0_0.[P]A.[Q]B: R>
```

如果这次编译器调用要生成一个 serialized module，我们会把这个 protocol extension 的 generic signature 序列化下来，将来这个 module 被 import 时就不必重算。不过我们可能仍然需要一个 rewrite system 来做 generic signature query，这种场景下我们会构造一个「第二代」rewrite system：

1. 我们最初是从 protocol extension 里用户手写的 requirement 构造出一个 convergent rewriting system。
2. 找到最小规则集之后，把 minimal rule 转成 requirement，并把得到的 generic signature 序列化。
3. 在后续某次编译器调用里，我们把这个 generic signature 反序列化回来。
4. 然后从这个 generic signature 的 requirement 构造一个 convergent rewriting system；规则 (8) 现在成了我们的初始规则之一。

第 (1) 步之后的 rewrite system 与第 (4) 步之后的是等价的。也就是说，若忽略 **left-simplified** 与 **right-simplified** 的规则，两者的规则集相同，至多差一个排列。（我们没法完整证明这件事，因为 minimization 很微妙。但这就是这里打算维持的不变式。）

**例.** 现在我们改动 `Q`，给它加一条 associated requirement，要求 `B` conform to `R`。这么一来，我们 protocol extension 的 `where` 从句里那条 conformance requirement $[\texttt{τ}_{0,0}\texttt{.A.B: R}]$ 就变成冗余的了，因为（conform to `Q` 的类型的）每个 `B` 现在都 conform to `R`：

```swift
protocol R {}

protocol Q {
  associatedtype B: R
}

protocol P {
  associatedtype A: Q
}

extension P where Self.A.B: R {}
```

用来构造这个 protocol extension 的 generic signature 的 rewrite system 起步时与上例相同，只是从 protocol `Q` 多来了一条 imported rule：

$$[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}]\Rightarrow[\texttt{Q}|\texttt{B}]$$

conformance rule $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]\Rightarrow\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ 仍像先前那样与 $\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]$ 在 term $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]$ 上 overlap。这是一个第一类 overlap，所以原规则 $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}\cdot[\texttt{R}]\Rightarrow\tau_{0,0}\cdot\texttt{A}\cdot\texttt{B}$ 被标记为 **left-simplified**。但这一次，critical pair 是 trivial 的；两侧都已经归约到 $\tau_{0,0}\cdot[\texttt{P}|\texttt{A}]\cdot[\texttt{Q}|\texttt{B}]$：

```
起点（basepoint）  τ_0_0·A·B·[R]
  ──(τ_0_0·A ⇒ τ_0_0·[P|A])·B·[R]────────────→  τ_0_0·[P|A]·B·[R]
  ──τ_0_0·([P|A]·B ⇒ [P|A]·[Q|B])·[R]────────→  τ_0_0·[P|A]·[Q|B]·[R]
  ──τ_0_0·[P|A]·([Q|B]·[R] ⇒ [Q|B])─────────→  τ_0_0·[P|A]·[Q|B]
  ──τ_0_0·([P|A]·[Q|B] ⇒ [P|A]·B)────────────→  τ_0_0·[P|A]·B
  ──(τ_0_0·[P|A] ⇒ τ_0_0·A)·B───────────────→  τ_0_0·A·B
  ──(τ_0_0·A·B ⇒ τ_0_0·A·B·[R])─────────────→  τ_0_0·A·B·[R]（回到起点）
```

这张图断言的是：与上一例形状完全相同的六节点环，但这次闭合环的那条边不是新规则，而是从 `Q` 导入的既有规则 $[\texttt{Q}|\texttt{B}]\cdot[\texttt{R}]\Rightarrow[\texttt{Q}|\texttt{B}]$——所以没有新规则产生，critical pair 是 trivial 的。

> 译注：原书此处是一张六节点的 tikzcd 交换图，按规约 §6.5 (a) 改用邻接表式的 Unicode 箭头列表转述；图的原貌见官方 PDF 对应章节。

**例.** 我们接下来的目标是搞清楚：当一个 type parameter 同时 conform 到两个互不相关、却都声明了同名 associated type 的 protocol 时，会发生什么：

```swift
protocol P1 {
  associatedtype A
}

protocol P2 {
  associatedtype A
}
```

我们要看的是这个 generic signature：

```
<τ_0_0 where τ_0_0: P1, τ_0_0: P2>
```

每个 type parameter 的等价类都能由某个 unbound type parameter 唯一标识。在上面这个签名里，type parameter `τ_0_0.[P1]A` 与 `τ_0_0.[P2]A` 因此必须都等价于 `τ_0_0.A`。我们来看看这在 rewrite system 里是怎么落实的。下面是上述 generic signature 的 convergent rewriting system：

$$[\texttt{P1}]\cdot\texttt{A}\Rightarrow[\texttt{P1}|\texttt{A}] \tag{1}$$

$$[\texttt{P2}]\cdot\texttt{A}\Rightarrow[\texttt{P2}|\texttt{A}] \tag{2}$$

$$\tau_{0,0}\cdot[\texttt{P1}]\Rightarrow\tau_{0,0} \tag{3}$$

$$\tau_{0,0}\cdot[\texttt{P2}]\Rightarrow\tau_{0,0} \tag{4}$$

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}] \tag{*5}$$

$$\tau_{0,0}\cdot[\texttt{P2}|\texttt{A}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}] \tag{*6}$$

规则 (1) 与 (2) 从 `P1` 与 `P2` 导入，规则 (3) 与 (4) 对应 conformance requirement $[\texttt{τ}_{0,0}\texttt{: P1}]$ 与 $[\texttt{τ}_{0,0}\texttt{: P2}]$。Completion 另外加了两条规则。规则 (*5) 是在 resolve 规则 (3) 与规则 (1) 的 overlap 时加入的，跟本节第一个例子里一模一样。

规则 (4) 与规则 (2) 在 term $\tau_{0,0}\cdot[\texttt{P2}]\cdot\texttt{A}$ 上 overlap：

$$\begin{aligned} \tau_{0,0}\cdot{}&[\texttt{P2}]\\ &[\texttt{P2}]\cdot\texttt{A} \end{aligned}$$

这给了我们规则 (*6)，它的形式是我们先前没见过的。critical pair 的一侧归约到 $\tau_{0,0}\cdot[\texttt{P2}|\texttt{A}]$，另一侧则经由规则 (5) 归约到 $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]$。

我们记录一个 rewrite loop，它用 (2)、(4) 与 (5) 定义出规则 (*6)：

```
起点（basepoint）  τ_0_0·[P2]·A
  ──τ_0_0·([P2]·A ⇒ [P2|A])──────────────────→  τ_0_0·[P2|A]
  ──(τ_0_0·[P2|A] ⇒ τ_0_0·[P1|A])────────────⇢  τ_0_0·[P1|A]   （虚线 = 新规则 *6）
  ──(τ_0_0·[P1|A] ⇒ τ_0_0·A)─────────────────→  τ_0_0·A
  ──(τ_0_0·[P2] ⇒ τ_0_0)─────────────────────→  τ_0_0·[P2]·A（回到起点）
```

这张图断言的是：四个节点构成一个菱形环（顶 → 左 → 底 → 右 → 回到顶），虚线那条边就是新规则 (*6)，它由另外三条既有规则围合而成。

> 译注：原书此处是一张用 `\FourLoopDerived` 宏画的四节点 tikzcd 菱形交换图（顶部、左、底、右四个节点，沿顶→左→底→右→顶绕一圈；第二条边为虚线，表示新加入的规则），按规约 §6.5 (a) 用 Unicode 箭头的环路列表转述；本章共 16 张同形状的图，往下都用这一种写法。图的原貌见官方 PDF 对应章节。

我们可以把定义规则 (*5) 与 (*6) 的两个 rewrite loop「粘」成一张图：

```
                        τ_0_0·[P2]·A
                     ↙                ↖
        τ_0_0·[P2|A]                     τ_0_0·A
                     ⇢                ↗
                        τ_0_0·[P1|A]
                     ↘
                        τ_0_0·[P1]·A  ──────↑（回到 τ_0_0·A）
```

这张图断言的是：两条虚线箭头是规则 (*5) 与 (*6)；那些实线箭头给出一条只用初始规则、把 $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]$ 与 $\tau_{0,0}\cdot[\texttt{P2}|\texttt{A}]$ 连起来的 rewrite path。

> 译注：原书此处是一张五节点的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

这条 rewrite path 对应下面这个 derivation：

1. $[\tau_{0,0}\texttt{: P1}]$ （**Conf**）
2. $[\tau_{0,0}\texttt{.[P1]A == }\tau_{0,0}\texttt{.A}]$ （**AssocBind** 1）
3. $[\tau_{0,0}\texttt{: P2}]$ （**Conf**）
4. $[\tau_{0,0}\texttt{.[P2]A == }\tau_{0,0}\texttt{.A}]$ （**AssocBind** 3）
5. $[\tau_{0,0}\texttt{.A == }\tau_{0,0}\texttt{.[P2]A}]$ （**Sym** 4）
6. $[\tau_{0,0}\texttt{.[P1]A == }\tau_{0,0}\texttt{.[P2]A}]$ （**Trans** 2 5）

确实，我们看到 reduced type 为 `τ_0_0.[P1]A` 的那个等价类含有三个 type parameter。下面按 type parameter order 列出它们与对应的 term。这个例子里 reduced type 与 reduced term 恰好重合：

| **Type** | **Term** |
|---|---|
| `τ_0_0.[P1]A` | $\tau_{0,0}\cdot[\texttt{P1}\vert\texttt{A}]$ |
| `τ_0_0.[P2]A` | $\tau_{0,0}\cdot[\texttt{P2}\vert\texttt{A}]$ |
| `τ_0_0.A` | $\tau_{0,0}\cdot\texttt{A}$ |

## More Critical Pairs

**例.** 考虑这个 protocol 继承层级，`Bot` 继承自 `Mid`，`Mid` 又继承自 `Top`，而 `Mid` 声明了一个 associated type：

```swift
protocol Top {}

protocol Mid: Top {
  associatedtype A
}

protocol Bot: Mid {}
```

我们来考察 generic signature $G_\texttt{Bot}$ 的 rewrite system，它由从 `Mid` 与 `Bot` 导入的规则加上 local rule 组成（和前面一样，我们略去 identity conformance rule）：

$$[\texttt{Mid}]\cdot\texttt{A}\Rightarrow[\texttt{Mid}|\texttt{A}] \tag{1}$$

$$[\texttt{Mid}]\cdot[\texttt{Top}]\Rightarrow[\texttt{Mid}] \tag{2}$$

$$[\texttt{Bot}]\cdot\texttt{A}\Rightarrow[\texttt{Bot}|\texttt{A}] \tag{3}$$

$$[\texttt{Bot}]\cdot[\texttt{Mid}]\Rightarrow[\texttt{Bot}] \tag{4}$$

$$[\texttt{Bot}]\cdot[\texttt{Mid}|\texttt{A}]\Rightarrow[\texttt{Bot}|\texttt{A}] \tag{*5}$$

$$[\texttt{Bot}]\cdot[\texttt{Top}]\Rightarrow[\texttt{Bot}] \tag{*6}$$

$$\tau_{0,0}\cdot[\texttt{Bot}]\Rightarrow\tau_{0,0} \tag{7}$$

$$\tau_{0,0}\cdot[\texttt{Mid}]\Rightarrow\tau_{0,0} \tag{*8}$$

$$\tau_{0,0}\cdot[\texttt{Top}]\Rightarrow\tau_{0,0} \tag{*9}$$

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}] \tag{*10}$$

$$\tau_{0,0}\cdot[\texttt{Mid}|\texttt{A}]\Rightarrow\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}] \tag{*11}$$

我们只聚焦其中几条有意思的规则：

- `Bot` 虽然没有声明任何 associated type，但它从 `Mid` 继承了 `A`；规则 (3) 就是 `A` 的 associated type rule。
- 规则 (*5) 与 (*11) 由 completion 加入，是 associated type rule 的后果。
- 规则 (*6)、(*8) 与 (*9) 同样来自 completion。它们表达的是「传递性」的 conformance requirement $[\texttt{Self: Top}]_\texttt{Bottom}$、$[\texttt{τ}_{0,0}\texttt{: Top}]$ 与 $[\texttt{τ}_{0,0}\texttt{: Mid}]$。

规则 (4) 与规则 (1) 在 term $[\texttt{Bot}]\cdot[\texttt{Mid}]\cdot\texttt{A}$ 上 overlap：

$$\begin{aligned} [\texttt{Bot}]\cdot{}&[\texttt{Mid}]\\ &[\texttt{Mid}]\cdot\texttt{A} \end{aligned}$$

Resolve 这个 critical pair 会记录一个 rewrite loop，它用 (1)、(3) 与 (4) 定义出规则 (*5)：

```
起点（basepoint）  [Bot]·[Mid]·A
  ──[Bot]·([Mid]·A ⇒ [Mid|A])────────────────→  [Bot]·[Mid|A]
  ──([Bot]·[Mid|A] ⇒ [Bot|A])────────────────⇢  [Bot|A]      （虚线 = 新规则 *5）
  ──([Bot|A] ⇒ [Bot]·A)──────────────────────→  [Bot]·A
  ──([Bot] ⇒ [Bot]·[Mid])·A──────────────────→  [Bot]·[Mid]·A（回到起点）
```

这张图断言的是：新规则 (*5) 是这个四节点菱形环上唯一的新边，其余三条边分别是既有的 (1)、(3)、(4)。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

规则 (*5) 说的是：如果一个 conform to `Bot` 的 term 后面跟着 $[\texttt{Mid}|\texttt{A}]$，我们可以把它归约成 $[\texttt{Bot}|\texttt{A}]$。

规则 (4) 与规则 (3) 在 term $[\texttt{Bot}]\cdot[\texttt{Mid}]\cdot[\texttt{Top}]$ 上 overlap：

$$\begin{aligned} [\texttt{Bot}]\cdot{}&[\texttt{Mid}]\\ &[\texttt{Mid}]\cdot[\texttt{Top}] \end{aligned}$$

Resolve 这个 critical pair 会记录一个 rewrite loop，它用规则 (2) 与 (4) 定义出规则 (*6)：

```
起点（basepoint）  [Bot]·[Mid]·[Top]
  ──([Bot]·[Mid] ⇒ [Bot])·[Top]──────────────→  [Bot]·[Top]
  ──([Bot]·[Top] ⇒ [Bot])────────────────────⇢  [Bot]        （虚线 = 新规则 *6）
  ──([Bot] ⇒ [Bot]·[Mid])────────────────────→  [Bot]·[Mid]
  ──[Bot]·([Mid] ⇒ [Mid]·[Top])──────────────→  [Bot]·[Mid]·[Top]（回到起点）
```

这张图断言的是：$[\texttt{Bot}]$ conform to `Top` 这一事实，完全由「`Bot` 继承 `Mid`」与「`Mid` 继承 `Top`」这两条既有规则围出来。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

> 译注：原书正文说这个 overlap 是「规则 (4) 与规则 (3)」之间的，但 term $[\texttt{Bot}]\cdot[\texttt{Mid}]\cdot[\texttt{Top}]$ 与图里用到的都是规则 (2)（$[\texttt{Mid}]\cdot[\texttt{Top}]\Rightarrow[\texttt{Mid}]$），规则 (3) 是 associated type rule，与 $[\texttt{Top}]$ 无关。疑为笔误，应为「规则 (4) 与规则 (2)」。

规则 (*6) 说的是：如果一个 term conform to `Bot`，它也 conform to `Top`。一般来说，completion 之后形如 $[\texttt{P}]\cdot[\texttt{Q}]\Rightarrow[\texttt{P}]$ 的 rewrite rule 会编码 protocol 继承关系的传递闭包。

至此 `Bot` 的 rewrite system 就完成了。转到 $G_\texttt{Bot}$，我们看到规则 (7) 与规则 (4) 在 term $\tau_{0,0}\cdot[\texttt{Bot}]\cdot[\texttt{Mid}]$ 上 overlap：

$$\begin{aligned} \tau_{0,0}\cdot{}&[\texttt{Bot}]\\ &[\texttt{Bot}]\cdot[\texttt{Mid}] \end{aligned}$$

Resolve 这个 critical pair 用规则 (4)、(7) 与 (*8) 定义出规则 (*8)：

```
起点（basepoint）  τ_0_0·[Bot]·[Mid]
  ──(τ_0_0·[Bot] ⇒ τ_0_0)·[Mid]──────────────→  τ_0_0·[Mid]
  ──(τ_0_0·[Mid] ⇒ τ_0_0)────────────────────⇢  τ_0_0        （虚线 = 新规则 *8）
  ──(τ_0_0 ⇒ τ_0_0·[Bot])────────────────────→  τ_0_0·[Bot]
  ──τ_0_0·([Bot] ⇒ [Bot]·[Mid])──────────────→  τ_0_0·[Bot]·[Mid]（回到起点）
```

这张图断言的是：derived requirement $[\texttt{τ}_{0,0}\texttt{: Mid}]$ 由 $[\texttt{τ}_{0,0}\texttt{: Bot}]$ 与「`Bot` 继承 `Mid`」围出来。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

> 译注：原书正文说这个 critical pair「用规则 (4)、(7) 与 (*8) 定义出规则 (*8)」，一条规则不可能参与定义自己；按图中实际用到的边，应为「用规则 (4) 与 (7) 定义出规则 (*8)」。疑为笔误。

规则 (*8) 就是 derived requirement $[\texttt{τ}_{0,0}\texttt{: Mid}]$。规则 (7) 与规则 (5) 以同样的方式 overlap，定义出规则 (*9)，也就是 derived requirement $[\texttt{τ}_{0,0}\texttt{: Top}]$。我们再一次看到 protocol 继承关系的传递闭包被算了出来。

规则 (7) 与规则 (3) 在 term $\tau_{0,0}\cdot[\texttt{Bot}]\cdot\texttt{A}$ 上 overlap，定义出规则 (*10)，其一般原理与本章 Associated Types 一节第一个例子相同。

最后，规则 (*8) 与规则 (1) 在 term $\tau_{0,0}\cdot[\texttt{Mid}]\cdot\texttt{A}$ 上 overlap：

$$\begin{aligned} \tau_{0,0}\cdot{}&[\texttt{Mid}]\\ &[\texttt{Mid}]\cdot\texttt{A} \end{aligned}$$

Resolve 这个 critical pair 用规则 (1)、(3) 与 (*8) 定义出规则 (*11)：

```
起点（basepoint）  τ_0_0·[Mid]·A
  ──τ_0_0·([Mid]·A ⇒ [Mid|A])────────────────→  τ_0_0·[Mid|A]
  ──(τ_0_0·[Mid|A] ⇒ τ_0_0·[Bot|A])──────────⇢  τ_0_0·[Bot|A]（虚线 = 新规则 *11）
  ──τ_0_0·([Bot|A] ⇒ [Bot]·A)────────────────→  τ_0_0·A
  ──(τ_0_0 ⇒ τ_0_0·[Mid])·A──────────────────→  τ_0_0·[Mid]·A（回到起点）
```

这张图断言的是：同一个 associated type `A` 在 `Mid` 与 `Bot` 两边各有一个 symbol，而这条新规则把前者归约到后者。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

> 译注：原书把第三条边标成 $\tau_{0,0}\cdot([\texttt{Bot}|\texttt{A}] \Rightarrow [\texttt{Bot}]\cdot\texttt{A})$，但那一步的终点是 $\tau_{0,0}\cdot\texttt{A}$，所以标签应是规则 (*10) 的逆，即 $(\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}] \Rightarrow \tau_{0,0}\cdot\texttt{A})$。疑为笔误。

在这个例子里，type parameter 与 term 之间的关系比先前见过的更微妙，因为两个不同的 associated type symbol $[\texttt{Mid}|\texttt{A}]$ 与 $[\texttt{Bot}|\texttt{A}]$ 对应的其实是同一个 associated type **声明**。一方面，`τ_0_0.[Mid]A` 的等价类里只多含一个 type parameter，即 `τ_0_0.A`。可另一方面，我们有**三个**等价的 term：$\tau_{0,0}\cdot[\texttt{Mid}|\texttt{A}]$、$\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}]$ 与 $\tau_{0,0}\cdot\texttt{A}$。不仅如此，把 `symbols-terms-and-rules.tex` 的 Build term for explicit requirement 算法作用在 reduced type parameter `τ_0_0.[Mid]A` 上，输出的是 $\tau_{0,0}\cdot[\texttt{Mid}|\texttt{A}]$，而它**不是** reduced 的；这里的 reduced term 是 $\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}]$，因为在 reduction order（`symbols-terms-and-rules.tex` 的 Protocol reduction order 算法）下 $[\texttt{Bot}|\texttt{A}]<[\texttt{Mid}|\texttt{A}]$：

| **Type** | **Term** |
|---|---|
| `τ_0_0.[Mid]A` | $\tau_{0,0}\cdot[\texttt{Bot}\vert\texttt{A}]$ |
| | $\tau_{0,0}\cdot[\texttt{Mid}\vert\texttt{A}]$ |
| `τ_0_0.A` | $\tau_{0,0}\cdot\texttt{A}$ |

现在，假设我们把 `Bot` 的声明改成**重新声明**一次这个 associated type：

```swift
protocol Bot: Mid {
  associatedtype A
}
```

rewrite system 完全一样；我们现在把规则 (3) 叫作 associated type rule 而不是**继承而来的** associated type rule，但规则本身不变。我们的等价类现在有三个 type parameter 和三个 term，因为现在每个 associated type symbol 都对应一个声明：

| **Type** | **Term** |
|---|---|
| `τ_0_0.[Bot]A` | $\tau_{0,0}\cdot[\texttt{Bot}\vert\texttt{A}]$ |
| `τ_0_0.[Mid]A` | $\tau_{0,0}\cdot[\texttt{Mid}\vert\texttt{A}]$ |
| `τ_0_0.A` | $\tau_{0,0}\cdot\texttt{A}$ |

我们当初定义 `generic-signatures.tex` 的 Associated type order 算法（type parameter order 的一部分）时，就规定了 root associated type 声明总是排在这种重新声明的 associated type 声明之前；因此我们这个等价类的 reduced type parameter 仍然是 `τ_0_0.[Mid]A`。reduced term 也没变，还是 $\tau_{0,0}\cdot[\texttt{Bot}|\texttt{A}]$。这意味着重新声明一个 associated type（或删掉一个重新声明的 associated type）既不改变 rewrite system，也不改变 reduced type 关系，尤其是不会影响 calling convention、witness table layout 或 ABI 的任何其它方面。

注意由于这种对应关系并不是直截了当的，term 到 type parameter 的映射必须这样定义：给定一个 reduced term，要输出一个 reduced type parameter，办法是在每一步谨慎地挑选 associated type 声明。这会在 `property-map.tex` 的 Generic Signature Queries 一节解释。要不是因为有「继承而来的 associated type symbol」这种东西，再加上 associated type symbol 上的 reduction order 与 associated type 声明上的 type parameter order 并不一致，这点小麻烦本来是可以避免的。不过这两种行为各有其重要的可取之处，我们会在本章 Recursive Conformances 一节看到。

**例.** 我们现在来问 `f()` 能不能通过类型检查；`T.C.B` 与 `T.A` 等价吗？

```swift
protocol S {
  associatedtype A
  associatedtype B
  associatedtype C: S where Self == Self.C.C, Self.B == Self.C.A
}

func f<T: S>(val: T.C.B) {
  let val2: T.A = val
}
```

我们的 protocol 声明了三条 associated requirement：

$$[\texttt{Self.C: S}]_\texttt{S}$$
$$[\texttt{Self == Self.C.C}]_\texttt{S}$$
$$[\texttt{Self.B == Self.C.A}]_\texttt{S}$$

这两条 same-type requirement 的一个后果是：`τ_0_0.A` 与 `τ_0_0.C.C.A` 等价，而后者又与 `τ_0_0.C.B` 等价。完整的 derivation 如下：

1. $[\tau_{0,0}\texttt{: S}]$ （**Conf**）
2. $[\tau_{0,0}\texttt{.C: S}]$ （**AssocConf** 1）
3. $[\tau_{0,0}\texttt{.C.B == }\tau_{0,0}\texttt{.C.C.A}]$ （**AssocSame** 2）
4. $[\tau_{0,0}\texttt{ == }\tau_{0,0}\texttt{.C.C}]$ （**AssocSame** 1）
5. $[\tau_{0,0}\texttt{.C.C == }\tau_{0,0}]$ （**Sym** 4）
6. $[\tau_{0,0}\texttt{.C.C.A == }\tau_{0,0}\texttt{.A}]$ （**SameName** 1 5）
7. $[\tau_{0,0}\texttt{.C.B == }\tau_{0,0}\texttt{.A}]$ （**Trans** 3 6）

我们的 generic signature 定义了四个无穷的等价类：

| | | | |
|---|---|---|---|
| `τ_0_0` | `τ_0_0.A` | `τ_0_0.C` | `τ_0_0.B` |
| `τ_0_0.C.C` | `τ_0_0.C.B` | `τ_0_0.C.C.C` | `τ_0_0.C.A` |
| `τ_0_0.C.C.C.C` | `τ_0_0.C.C.A` | `τ_0_0.C.C.C.C.C` | `τ_0_0.C.C.B` |
| … | … | … | … |

为了有个直观的视角，我们来看 $G_\texttt{S}$ 的 type parameter graph：

```
                      τ_0_0
       .A ↙            ↕ .C            ↘ .B
  τ_0_0.A                                τ_0_0.B
       ↖ .B                            ↗ .A
                      τ_0_0.C

邻接表：
  τ_0_0    --.A-->  τ_0_0.A
  τ_0_0    --.B-->  τ_0_0.B
  τ_0_0    --.C-->  τ_0_0.C
  τ_0_0.C  --.A-->  τ_0_0.B
  τ_0_0.C  --.B-->  τ_0_0.A
  τ_0_0.C  --.C-->  τ_0_0
```

这张图断言的是：整张图只有四个节点、六条带名字的边，而 `τ_0_0` 与 `τ_0_0.C` 之间的 `.C` 边是双向的（$\texttt{Self} == \texttt{Self.C.C}$ 的直接后果），正是这条来回的边让每个等价类都变成无穷的。

> 译注：原书此处是一张 TikZ type parameter graph，这里用 ASCII 图加邻接表转述；图的原貌见官方 PDF 对应章节。

下面是两个具体的 conforming type：

```swift
struct X: S {
  typealias A = Int
  typealias B = String
  typealias C = Y
}

struct Y: S {
  typealias A = String
  typealias B = Int
  typealias C = X
}
```

现在来看我们真正的事实来源——rewrite system。我们从一条 identity conformance rule、三条 associated type rule，最后再加三条对应用户手写 requirement 的规则开始：

$$[\texttt{S}]\cdot[\texttt{S}]\Rightarrow[\texttt{S}] \tag{1}$$

$$[\texttt{S}]\cdot\texttt{A}\Rightarrow[\texttt{S}|\texttt{A}] \tag{2}$$

$$[\texttt{S}]\cdot\texttt{B}\Rightarrow[\texttt{S}|\texttt{B}] \tag{3}$$

$$[\texttt{S}]\cdot\texttt{C}\Rightarrow[\texttt{S}|\texttt{C}] \tag{4}$$

$$[\texttt{S}]\cdot\texttt{C}\cdot[\texttt{S}]\Rightarrow[\texttt{S}]\cdot\texttt{C} \tag{5}$$

$$[\texttt{S}]\cdot\texttt{C}\cdot\texttt{A}\Rightarrow[\texttt{S}]\cdot\texttt{B} \tag{6}$$

$$[\texttt{S}]\cdot\texttt{C}\cdot\texttt{C}\Rightarrow[\texttt{S}] \tag{7}$$

Completion 另外加了**十**条新规则；我们一次看几条。先看第一条规则 $[\texttt{S}]\cdot[\texttt{S}]\Rightarrow[\texttt{S}]$。每个 protocol 都有一条 identity conformance rule，但在先前的例子里它没起什么重要作用，所以我们忽略了它。identity conformance rule 总是与它自己 overlap：

$$\begin{aligned} [\texttt{S}]\cdot{}&[\texttt{S}]\\ &[\texttt{S}]\cdot[\texttt{S}] \end{aligned}$$

这个 critical pair 永远是 trivial 的：

```
  [S]·[S]·[S]
      │  ↑
      │  └── [S]·([S] ⇒ [S]·[S])
      └─────→ ([S]·[S] ⇒ [S])·[S]
      ↓
  [S]·[S]
```

这张图断言的是：两个节点之间一去一回，构成一个平凡的 rewrite loop，没有新规则产生。

> 译注：原书此处是一张两节点的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

identity conformance rule 也会与 associated type rule overlap。例如规则 (1) 与 (2) 在 term $[\texttt{S}]\cdot[\texttt{S}]\cdot\texttt{A}$ 上 overlap：

$$\begin{aligned} [\texttt{S}]\cdot{}&[\texttt{S}]\\ &[\texttt{S}]\cdot\texttt{A} \end{aligned}$$

这个 critical pair 的一侧归约到 $[\texttt{S}]\cdot[\texttt{S}|\texttt{A}]$，另一侧归约到 $[\texttt{S}|\texttt{A}]$。我们定义一条新规则 $[\texttt{S}]\cdot[\texttt{S}|\texttt{A}]\Rightarrow[\texttt{S}|\texttt{A}]$ 并记录一个 rewrite loop：

```
起点（basepoint）  [S]·[S]·A
  ──[S]·([S]·A ⇒ [S|A])──────────────────────→  [S]·[S|A]
  ──([S]·[S|A] ⇒ [S|A])──────────────────────⇢  [S|A]       （虚线 = 新规则）
  ──([S|A] ⇒ [S]·A)──────────────────────────→  [S]·A
  ──([S] ⇒ [S]·[S])·A────────────────────────→  [S]·[S]·A（回到起点）
```

这张图断言的是：这条「前缀去掉一个 $[\texttt{S}]$」的新规则，由 identity conformance rule 与 associated type rule 共同围出。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

同理我们给每个 associated type 都得到一条这样的规则：

$$[\texttt{S}]\cdot[\texttt{S}|\texttt{A}]\Rightarrow[\texttt{S}|\texttt{A}] \tag{*8}$$

$$[\texttt{S}]\cdot[\texttt{S}|\texttt{B}]\Rightarrow[\texttt{S}|\texttt{B}] \tag{*9}$$

$$[\texttt{S}]\cdot[\texttt{S}|\texttt{C}]\Rightarrow[\texttt{S}|\texttt{C}] \tag{*10}$$

在先前的例子里我们本来也可以写下类似的规则，只是它们说明不了什么。它们马上就要起作用了；不过在那之前，我们先处理几个 conformance rule 与 associated type rule 之间的 overlap。和先前的例子一样，我们得到用于归约 unbound type parameter 的那批常规规则 (*11)、(*12) 与 (*13)；同时 (5)、(6) 与 (7) 被 left-simplify，由规则 (*14)、(*15) 与 (*16) 取代：

$$[\texttt{S}|\texttt{C}]\cdot\texttt{A}\Rightarrow[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{A}] \tag{*11}$$

$$[\texttt{S}|\texttt{C}]\cdot\texttt{B}\Rightarrow[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{B}] \tag{*12}$$

$$[\texttt{S}|\texttt{C}]\cdot\texttt{C}\Rightarrow[\texttt{S}] \tag{*13}$$

$$[\texttt{S}|\texttt{C}]\cdot[\texttt{S}]\Rightarrow[\texttt{S}|\texttt{C}] \tag{*14}$$

$$[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{C}]\Rightarrow[\texttt{S}] \tag{*15}$$

$$[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{A}]\Rightarrow[\texttt{S}|\texttt{B}] \tag{*16}$$

重头戏来了：规则 (*15) 与 (*16) 在 term $[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{A}]$ 上 overlap：

$$\begin{aligned} [\texttt{S}|\texttt{C}]\cdot{}&[\texttt{S}|\texttt{C}]\\ &[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{A}] \end{aligned}$$

这个 critical pair 的右侧用规则 (*15) 归约 overlap term $[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{A}]$，得到 $[\texttt{S}]\cdot[\texttt{S}|\texttt{A}]$。先前，bound type parameter 的 term 要么以 protocol symbol 开头、要么以 associated type symbol 开头，**不会两个都有**；associated type symbol 本身已经编码了 protocol。而这个长相古怪的 term 确实经由规则 (*8) 归约成了单纯的 $[\texttt{S}|\texttt{A}]$——而规则 (*8) 正是那条神秘的 identity conformance rule (1) 的产物。

```
起点（basepoint）  [S|C]·[S|C]·[S|A]
  ──[S|C]·([S|C]·[S|A] ⇒ [S|B])──────────────→  [S|C]·[S|B]
  ──([S|C]·[S|B] ⇒ [S|A])────────────────────⇢  [S|A]        （虚线 = 新规则 *17）
  ──([S|A] ⇒ [S]·[S|A])──────────────────────→  [S]·[S|A]
  ──([S] ⇒ [S|C]·[S|C])·[S|A]────────────────→  [S|C]·[S|C]·[S|A]（回到起点）
```

这张图断言的是：正是 identity conformance rule 衍生出的规则 (*8) 让 $[\texttt{S}]\cdot[\texttt{S}|\texttt{A}]$ 塌回 $[\texttt{S}|\texttt{A}]$，这个环才闭合得上，新规则 (*17) 才得以成立。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

终于，如先前预告的那样，我们得到了那条证明 $G_\texttt{S}\vdash[\texttt{τ}_{0,0}\texttt{.A == τ}_{0,0}\texttt{.C.B}]$ 的规则：

$$[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{B}]\Rightarrow[\texttt{S}|\texttt{A}] \tag{*17}$$

接下来是**返场**：规则 (*15) 与规则 (*14) 在 term $[\texttt{S}|\texttt{C}]\cdot[\texttt{S}|\texttt{C}]\cdot[\texttt{S}]$ 上 overlap：

$$\begin{aligned} [\texttt{S}|\texttt{C}]\cdot{}&[\texttt{S}|\texttt{C}]\\ &[\texttt{S}|\texttt{C}]\cdot[\texttt{S}] \end{aligned}$$

这个 critical pair 借助 identity conformance rule 平凡地 resolve 掉了：

```
起点（basepoint）  [S|C]·[S|C]·[S]
  ──([S|C]·[S|C] ⇒ [S])·[S]──────────────────→  [S]·[S]
  ──([S]·[S] ⇒ [S])──────────────────────────→  [S]          （注意：没有虚线，无新规则）
  ──([S] ⇒ [S|C]·[S|C])──────────────────────→  [S|C]·[S|C]
  ──[S|C]·([S|C] ⇒ [S|C]·[S])────────────────→  [S|C]·[S|C]·[S]（回到起点）
```

这张图断言的是：四条边全是既有规则，环自动闭合，所以这是一个 trivial critical pair。

> 译注：原书此处是一张 `\FourLoopTrivial` 四节点菱形 tikzcd 交换图（与 `\FourLoopDerived` 形状完全相同，只是没有虚线边），这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

如果 identity conformance rule 当初不在初始规则集里，最后这个 critical pair 就会**定义**出 identity conformance rule，我们最终得到的仍是同一个 rewrite system。所以说到底，我们并不需要显式地加入 identity conformance rule。不过这里有个实践上的考虑。把这条规则放进初始集合，并且——关键在于——把它标记为 **permanent**，我们就把它从 rewrite system 的 minimization 算法里排除了出去。这省掉了大量不必要的工作。

Protocol `S` 是一个有意思的测试用例，展示了 rewrite system 发现非平凡恒等式的能力。它源自 2020 年一份开发者的 bug 报告（SR-12120，「Compiler forgets some constraints of P within extension to P, known bug?」，即 swiftlang/swift 的 issue 54555）；当时它让 `GenericSignatureBuilder` 的 minimization 算法崩了。有趣的是，Rust 编译器的泛型实现也证不出这条 derived requirement：

```rust
trait S {
  type A;
  type B;
  type C: S<A = Self::B, C = Self>;
}

fn f<T: S>(val: <T::C as S>::B) {
  let val2: T::A = val;
  // note: expected associated type `<T as S>::A'
  // found associated type `<<T as S>::C as S>::B'
}
```

## Tietze Transformations

Knuth-Bendix completion 与规则简化算法都保持 term 上的等价关系不变。当 completion 加入一条新的 rewrite rule 时，那是因为对应的一对 term 本来就已经被某条 rewrite path 连起来了。规则简化删掉一条 rewrite rule 时也有类似的保证：那两个 term 已知能被至少一条不涉及这条规则的 rewrite path 连起来。这些变换把 reduction relation 揉捏成更好的形状，而 term 上的等价关系则始终完全由我们最初那个 monoid presentation 的 rewrite rule 决定。

从数学上讲，这两个算法都被定义成 monoid presentation 上的一个变换。这个变换可以分解成一串顺序执行的步骤，每一步都以保持 monoid isomorphism 的方式改动 monoid presentation。下面四种保同构的变换以 Heinrich Tietze 命名（他在 1908 年引入了它们），我们目前已经见过其中两种：

**定义.** 设 $\langle A\,|\,R\rangle$ 是一个 finitely-presented monoid。一次**基本 Tietze transformation**（简称 Tietze transformation）是下列之一：

1. （加入一条 rewrite rule）若一对 term $u$、$v\in A^*$ 本来就被一条从 $u$ 到 $v$ 的 rewrite path 连着——也就是说，作为 $\langle A\,|\,R\rangle$ 的元素有 $u\sim v$——我们就可以加入 $(u,v)$：

$$\langle A\,|\,R\cup\{(u,v)\}\rangle$$

2. （删去一条 rewrite rule）若 $(u,v)\in R$ 且存在一条从 $u$ 到 $v$ 的 rewrite path，它对任何 $x$、$y\in A^*$ 都不含 rewrite step $x(u\Rightarrow v)y$ 或 $x(v\Rightarrow u)y$，我们就可以删去 $(u,v)$：

$$\langle A\,|\,R\setminus\{(u,v)\}\rangle$$

3. （加入一个生成元）若 $a$ 是某个与 $A$ 中所有符号都不同的符号，而 $t\in A^*$ 是任意 term，我们可以同时加入 $a$ 并令它等价于 $t$：

$$\langle A\cup\{a\}\,|\,R\cup\{(t,a)\}\rangle$$

4. （删去一个生成元）若 $a\in A$，且对某个不含 $a$ 的 term $t$ 有 $(t,a)\in R$，而且 $R$ 中没有别的 $(u,v)$ 的 term $u$ 或 $v$ 含有 $a$，我们可以同时删去 $a$ 与 $(t,a)$：

$$\langle A\setminus\{a\}\,|\,R\setminus\{(t,a)\}\rangle$$

这里的关键结论是：两个 finitely-presented monoid 同构，当且仅当它们是 **Tietze-equivalent** 的，即其中一个可以经由有限串基本 Tietze transformation 得到另一个。

几点细节：

- 每种 Tietze transformation 都有一个撤销该改动的互补变换；这样 (1) 与 (2) 互逆，(3) 与 (4) 也互逆。
- 我们已经知道，把一条 rewrite rule 里两个 term 的顺序调换——把 $R$ 中的 $(u,v)$ 换成 $(v,u)$——不改变所生成的 rewrite step 集合，因而呈现的是同一个 monoid。现在我们看到这个操作其实是两次基本 Tietze transformation 的复合：先加入 $(v,u)$，再删去 $(u,v)$。
- (4) 的某些定义里不要求被删符号 $a$ 不出现在别的 rewrite rule $(u,v)\in R$ 里。我们这个限制不损失任何一般性，因为若 $a$ 出现在别的 rewrite rule 里，我们总可以先做一串 Tietze transformation 把这些出现消掉：对每条这样的 $(u,v)$，把 $u$ 与 $v$ 里的 $a$ 替换成 $t$，加入这条新的 rewrite rule，最后删掉旧规则 $(u,v)$。不过我们仍然必须要求 $a$ 不出现在 $t$ 里；否则把 $a$ 换成 $t$ 并不能消掉 $a$ 的全部出现。

### Associated type symbols

Tietze transformation 给了我们理解 associated type symbol 的一个新角度。本章 Associated Types 一节所展示的那个「从用户手写 requirement 构造的 rewrite system」与「minimal requirement」之间的最终等价，意味着我们本可以把 `symbols-terms-and-rules.tex` 的 Build term for explicit requirement 与 Build term for associated requirement 这两个算法定义成只用 protocol symbol 与 name symbol 来构造 term。completion 跑完之后，我们得到的还是同一个 rewrite system，只不过路上要多费点劲。在这种设定下，初始 rewrite rule 里 associated type symbol 唯一的出现之处，就是 associated type rule 的右侧：

$$[\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}]$$

于是我们可以把 associated type rule 理解成对某个 monoid presentation 施加一串第三类 Tietze transformation 的结果。这个「原初的」monoid presentation 只涉及 protocol symbol 与 name symbol，而它编码的 monoid 与我们的那个同构。那我们究竟为什么还要费心引入 associated type symbol？下一节会看到，答案与 recursive conformance requirement 和 completion 之间的相互作用有关。

### Further discussion

基本 Tietze transformation 是「更高维」的 rewrite step，因为它们在一张以 **monoid presentation** 为顶点的图上定义了边关系。这张图里的一条路径见证了起点与终点定义的是一对同构的 monoid。判定两个 presentation 是否被一条路径连起来，这个问题就是 **monoid isomorphism problem**。与 word problem 一样，它在一般情形下当然是不可判定的。

Tietze transformation 是 **combinatorial group theory** 研究的基础，任何讲这门学问的书里都有描述，例如 Magnus、Karrass 与 Solitar 1976 年的《Combinatorial Group Theory: Presentations of Groups in Terms of Generators and Relations》。回忆一下，在 group presentation 里，一条 rewrite rule $(u, v)$ 总可以写成 $(uv^{-1},\varepsilon)$，即把单位元放在右侧。term $uv^{-1}$ 叫作 **relator**；在 group presentation 里，一组 relator 取代了 rewrite rule 的位置。monoid presentation 的 Tietze transformation 在 Book 与 Otto 2012 年的《String-Rewriting Systems》以及 Henry 与 Mimram 2021 年的《Tietze Equivalences as Weak Equivalences》里有描述。

## Recursive Conformances

从前面那些例子看，好像 completion 本质上是在枚举**所有**的 derived requirement，但一般情况下这不可能成立。我们从 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 Recursive Conformances 一节知道，recursive conformance requirement 能让我们定义出 derived requirement 的理论为无穷的 generic signature。如果编译器要允许这样的 generic signature，那么这个无穷的 derived requirement 集合就必须由有限条 rewrite rule 来编码。

我们将看到，在有 recursive conformance requirement 的情况下，Knuth-Bendix 算法能否成功终止，既取决于 associated type symbol（以及相应的规则）是否存在，也取决于我们选的 reduction order。这为 `monoids.tex` 的 The Word Problem 一节提到的某个场景给出了具体的例子。

**例.** 第一个例子是 protocol `N`，我们已经碰到它好几次，最近一次是在 `monoids.tex` 的 A Swift Connection 一节：

```swift
protocol N {
  associatedtype A: N
}
```

我们来看 $G_\texttt{N}$ 的 convergent rewriting system：

$$[\texttt{N}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}] \tag{1}$$

$$[\texttt{N}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}] \tag{2}$$

$$[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A} \tag{3}$$

$$[\texttt{N}|\texttt{A}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}] \tag{*4}$$

$$[\texttt{N}]\cdot[\texttt{N}|\texttt{A}]\Rightarrow[\texttt{N}|\texttt{A}] \tag{*5}$$

$$[\texttt{N}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}] \tag{*6}$$

$$\tau_{0,0}\cdot[\texttt{N}]\Rightarrow\tau_{0,0} \tag{7}$$

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{N}|\texttt{A}] \tag{*8}$$

规则 (*4)、(*5)、(*6) 与 (*8) 由下面「$G_\texttt{N}$ 中的 critical pair」那组图里的 rewrite loop 定义。规则 (3) 被标记为 **left-simplified**，因为它的左侧 $[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]$ 总能被 rewrite path $([\texttt{N}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}])\cdot[\texttt{N}]\circ([\texttt{N}|\texttt{A}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}])$ 归约掉。

**图（$G_\texttt{N}$ 中的 critical pair）.** 四个 rewrite loop，依次定义规则 (*4)、(*5)、(*6) 与 (*8)：

```
定义规则 (*4) ——
起点（basepoint）  [N]·A·[N]
  ──([N]·A ⇒ [N|A])·[N]──────────────────────→  [N|A]·[N]
  ──([N|A]·[N] ⇒ [N|A])──────────────────────⇢  [N|A]        （虚线 = 新规则 *4）
  ──([N|A] ⇒ [N]·A)──────────────────────────→  [N]·A
  ──([N]·A ⇒ [N]·A·[N])──────────────────────→  [N]·A·[N]（回到起点）

定义规则 (*5) ——
起点（basepoint）  [N]·[N]·A
  ──[N]·([N]·A ⇒ [N|A])──────────────────────→  [N]·[N|A]
  ──([N]·[N|A] ⇒ [N|A])──────────────────────⇢  [N|A]        （虚线 = 新规则 *5）
  ──([N|A] ⇒ [N]·A)──────────────────────────→  [N]·A
  ──([N] ⇒ [N]·[N])·A────────────────────────→  [N]·[N]·A（回到起点）

定义规则 (*6) ——（三节点三角形）
起点（basepoint）  [N|A]·[N]·A
  ──([N|A]·[N] ⇒ [N|A])·A────────────────────→  [N|A]·A
  ──([N|A]·A ⇒ [N|A]·[N|A])──────────────────⇢  [N|A]·[N|A]  （虚线 = 新规则 *6）
  ──[N|A]·([N|A] ⇒ [N]·A)────────────────────→  [N|A]·[N]·A（回到起点）

定义规则 (*8) ——（三节点三角形）
起点（basepoint）  τ_0_0·[N]·A
  ──(τ_0_0·[N] ⇒ τ_0_0)·A────────────────────→  τ_0_0·A
  ──(τ_0_0·A ⇒ τ_0_0·[N|A])──────────────────⇢  τ_0_0·[N|A]  （虚线 = 新规则 *8）
  ──τ_0_0·([N|A] ⇒ [N]·A)────────────────────→  τ_0_0·[N]·A（回到起点）
```

这四张图断言的是：四条由 completion 加入的规则，每一条都是某个闭合 rewrite loop 上唯一的新边，其余各边全是初始规则；前两个是四节点菱形，后两个是三节点三角形。

> 译注：原书此处是一整张 figure，内含四张 tikzcd 交换图（前两张用 `\FourLoopDerived` 宏），这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

在我们的 rewrite system 里，type parameter 的 term 以 $\tau_{0,0}$ 为首符号，其后每个符号要么是 `A`、要么是 $[\texttt{N}|\texttt{A}]$。任何这样的 term 都归约到一个长度相同的 term：

$$\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot\texttt{A}\rightarrow \tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]$$

reduced term 就是那些不含 `A` 的；也就是说，一个 reduced term 形如 $\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]^n$。另外，$G_\texttt{N}$ 的每个 type parameter 都 conform to `N`。我们有两个无穷的 derived conformance requirement 族，subject type 分别取自每个等价类里的 bound 与 unbound type parameter：

| |
|---|
| $[\texttt{τ}_{0,0}\texttt{.[N]A: N}]$ |
| $[\texttt{τ}_{0,0}\texttt{.[N]A.[N]A: N}]$ |
| $[\texttt{τ}_{0,0}\texttt{.[N]A.[N]A.[N]A: N}]$ |
| … |

| |
|---|
| $[\texttt{τ}_{0,0}\texttt{.A: N}]$ |
| $[\texttt{τ}_{0,0}\texttt{.A.A: N}]$ |
| $[\texttt{τ}_{0,0}\texttt{.A.A.A: N}]$ |
| … |

每条 derived requirement 都对应一个 term 等价式 $t\cdot[\texttt{N}]\sim t$，其中 $t$ 是一个 type parameter term。我们可以显式地构造出见证这些等价的 rewrite path。暂时把规则 (*4)、(*6) 与 (*8) 的 positive rewrite step 分别记作 $\alpha$、$\beta$ 与 $\gamma$：

$$\alpha := ([\texttt{N}|\texttt{A}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}])$$
$$\beta := ([\texttt{N}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}])$$
$$\gamma := (\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{N}|\texttt{A}])$$

对于 subject type 为 bound 的那些 derived requirement，$t=\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]^n$。我们只用一步 rewrite step 就能把 $t\cdot[\texttt{N}]$ 重写成 $t$：用规则 $\alpha$ 消掉后缀 $[\texttt{N}]$，term 的其余部分原封不动：

$$\tau_{0,0}\triangleleft\alpha$$
$$\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\triangleleft\alpha$$
$$\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\triangleleft\alpha$$
$$\ldots$$

对于 subject type 为 unbound 的那些 derived requirement，$t=\tau_{0,0}\cdot\texttt{A}$。要把 $t\cdot[\texttt{N}]$ 重写成 $t$，我们先把 $t\rightarrow t^\prime$ 归约掉，用规则 $\alpha$ 消去 $[\texttt{N}]$，再把归约反过来走回 $t$。归约由 path $p_n$ 给出，其中每个 $p_n$ 把 $\tau_{0,0}\cdot\texttt{A}^n$ 重写成 $\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]^n$：

$$p_1:=\gamma$$
$$p_2:=(\gamma\triangleright\texttt{A}\cdot[\texttt{N}])\circ(\tau_{0,0}\triangleleft\beta\triangleright[\texttt{N}])$$
$$p_3:=(\gamma\triangleright\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}])\circ(\tau_{0,0}\triangleleft\beta\triangleright\texttt{A}\cdot[\texttt{N}])\circ(\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\triangleleft\beta\triangleright[\texttt{N}])$$
$$\ldots$$

于是，subject type 为 unbound 的那些 derived requirement 对应下面这些 rewrite path：

$$(p_1\triangleright[\texttt{N}])\circ(\tau_{0,0}\triangleleft\alpha)\circ p_1^{-1}$$
$$(p_2\triangleright[\texttt{N}])\circ(\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\triangleleft\alpha)\circ p_2^{-1}$$
$$(p_3\triangleright[\texttt{N}])\circ(\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\triangleleft\alpha)\circ p_3^{-1}$$
$$\ldots$$

举例来说，$\tau_{0,0}\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]$ 与 $\tau_{0,0}\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}$ 都归约到 $\tau_{0,0}\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]$；我们可以用这条 rewrite path 把它们连起来：

```
  τ_0_0·A·A·A·[N]                          τ_0_0·A·A·A
        │ γ                                      ↑ γ⁻¹
        ↓                                        │
  τ_0_0·[N|A]·A·A·[N]                      τ_0_0·[N|A]·A·A
        │ β                                      ↑ β⁻¹
        ↓                                        │
  τ_0_0·[N|A]·[N|A]·A·[N]                  τ_0_0·[N|A]·[N|A]·A
        │ β                                      ↑ β⁻¹
        ↓                                        │
  τ_0_0·[N|A]·[N|A]·[N|A]·[N] ──── α ────→ τ_0_0·[N|A]·[N|A]·[N|A]
```

这张图断言的是：左列一路正向归约到底（三步，用 $\gamma$、$\beta$、$\beta$），在底部用 $\alpha$ 一步抹掉 $[\texttt{N}]$，然后沿右列反向爬回去——整条路径连接的正是那条 derived requirement 的两端。

> 译注：原书此处是一张双列梯形的 tikzcd 交换图，这里用 Unicode 箭头图转述；图的原貌见官方 PDF 对应章节。

于是，我们这八条规则编码了两个无穷的 derived requirement 族。

现在我们来说明 associated type rule $[\texttt{N}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}]$ 是必不可少的。让我们从初始规则重新开始，但在尝试 completion 之前先把符号 $[\texttt{N}|\texttt{A}]$ 与规则 (2) 删掉。只剩两条规则：

$$[\texttt{N}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}] \tag{1}$$

$$[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A} \tag{3}$$

可以看到规则 (3) 与它自己在 term $[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]$ 上 overlap：

$$\begin{aligned} [\texttt{N}]\cdot\texttt{A}\cdot{}&[\texttt{N}]\\ &[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}] \end{aligned}$$

Resolve 这个 critical pair 引入一条新规则 $[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}$：

```
起点（basepoint）  [N]·A·[N]·A·[N]
  ──([N]·A·[N] ⇒ [N]·A)·A·[N]───────────────→  [N]·A·A·[N]
  ──([N]·A·A·[N] ⇒ [N]·A·A)─────────────────⇢  [N]·A·A      （虚线 = 新规则）
  ──([N]·A ⇒ [N]·A·[N])·A───────────────────→  [N]·A·[N]·A
  ──[N]·A·([N]·A ⇒ [N]·A·[N])───────────────→  [N]·A·[N]·A·[N]（回到起点）
```

这张图断言的是：缺了 associated type symbol 之后，同一条 conformance rule 自我 overlap 就会生出一条**更长**的新规则——这正是不终止的起点。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

加入这条规则后，我们再查一遍 overlap。新规则与规则 (3) 在 $[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]$ 上 overlap，也与它自己在 $[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]$ 上 overlap。规则 (3) 也与新规则在 $[\texttt{N}]\cdot\texttt{A}\cdot[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]$ 上 overlap。显然，resolve 这些 critical pair 会引入新规则，而这个过程永远不会结束。我们得到一个由 $m$、$n\in\mathbb{N}$ 标号的无穷 critical pair 族：

```
起点（basepoint）  [N]·Aᵐ·[N]·Aⁿ·[N]
  ──([N]·Aᵐ·[N] ⇒ [N]·Aᵐ)·Aⁿ·[N]───────────→  [N]·A^(m+n)·[N]
  ──([N]·A^(m+n)·[N] ⇒ [N]·A^(m+n))─────────⇢  [N]·A^(m+n)  （虚线 = 新规则）
  ──([N]·Aᵐ ⇒ [N]·Aᵐ·[N])·Aⁿ───────────────→  [N]·Aᵐ·[N]·Aⁿ
  ──[N]·Aᵐ·([N]·Aⁿ ⇒ [N]·Aⁿ·[N])───────────→  [N]·Aᵐ·[N]·Aⁿ·[N]（回到起点）
```

这张图断言的是：上一张图不是孤例，而是 $m=n=1$ 的特例；对每一对 $m$、$n$ 都有一个同构的菱形环，各自生出一条新规则。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

这些 critical pair 定义出一个无穷的 rewrite rule 序列：

$$[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}$$
$$[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}$$
$$[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}$$
$$\ldots$$

加入符号 $[\texttt{N}|\texttt{A}]$ 连同规则 $[\texttt{N}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}]$ 是一次 Tietze transformation，所以我们知道它不改变 term 上的等价关系。但它保证了收敛。收敛还取决于 associated type symbol 排在 name symbol 之前，即 $[\texttt{N}|\texttt{A}]<\texttt{A}$。否则我们又会得到一个无穷的 rewrite rule 序列：

$$[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}]\cdot\texttt{A}$$
$$[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot\texttt{A}$$
$$[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}]\cdot\texttt{A}\cdot\texttt{A}\cdot\texttt{A}$$
$$\ldots$$

让我们用 monoid presentation 与 Tietze transformation 来总结这个例子。我们把 $[\texttt{N}]$、`A`、$[\texttt{N}|\texttt{A}]$ 分别写成 $n$、$a$、$b$。连同 identity conformance rule 一起，用户手写的 requirement $[\texttt{Self.A: N}]_\texttt{N}$（subject type 是一个 unbound type parameter）在字母表 $a$、$n$ 上定义了这个 presentation：

$$M_1 := \langle a,n\,|\,nn\sim n,\,nan\sim na\rangle$$

我们看到 completion 在 $M_1$ 上不终止；抽象地看，可以把它理解成产出了一个**无穷**的 convergent presentation $M_1^\prime$，含有一族由 $i\in\mathbb{N}$ 参数化的 rewrite rule：

$$M_1^\prime := \langle a,n\,|\,na^in\sim na^i\rangle$$

为保证收敛，我们给 $M_1$ 加上符号 $b$ 及其定义规则 $na\sim b$；这是一次 Tietze transformation，给出了 $a$、$b$、$n$ 上的 presentation $M_2$：

$$M_2 := \langle a,b,n\,|\,nn\sim n,\,nan\sim na,\,na\sim b\rangle$$

在 reduction order $n<b<a$ 下对 $M_2$ 做 completion 会成功，加入两条 rewrite rule $bn\sim b$ 与 $ba\sim bb$，得到有限的 convergent presentation $M_2^\prime$：

$$M_2^\prime := \langle a,b,n\,|\,nn\sim n,\,nan\sim na,\,na\sim b,\,bn\sim b,\,ba\sim bb\rangle$$

规则简化删掉 rewrite rule $nan\sim na$，给出一个 reduced 的 presentation：

$$M_2^{\prime\prime} := \langle a,b,n\,|\,nn\sim n,\,na\sim b,\,bn\sim b,\,ba\sim bb\rangle$$

我们还没讲 rewrite system minimization，不过要 minimize $M_2^{\prime\prime}$，我们会把 completion 加入的规则全部消掉，只留下 $bn\sim b$——它是必须留的，因为原来那条 rewrite rule $nan\sim na$ 已经被删了。这样剩下 $M_3$：

$$M_3:=\langle a,b,n\,|\,nn\sim n,\,na\sim b,\,bn\sim b\rangle$$

规则 $bn\sim b$ 就是那条 minimal conformance requirement $[\texttt{Self.[N]A: N}]_\texttt{N}$，其 subject type 是一个 bound type parameter。上述所有 presentation 都定义出**同一个** monoid（至多相差一个同构）。而且，若对 $M_3$ 做 completion，我们又会得到 $M_2^{\prime\prime}$。

**例.** 假设我们继承 `N`，并对 `A` 施加我们自己的 recursive conformance requirement：

```swift
protocol Q: N where A: Q {}
```

尽管 protocol `Q` 并没有声明名为 `A` 的 associated type，我们仍然定义一个 associated type symbol $[\texttt{Q}|\texttt{A}]$ 以及对应的规则 $[\texttt{Q}]\cdot\texttt{A}\Rightarrow[\texttt{Q}|\texttt{A}]$。我们将看到收敛正取决于这条规则。

generic signature $G_\texttt{Q}$ 拥有 $G_\texttt{N}$ 的全部 derived requirement，另外再加两个无穷的、对 `Q` 的 conformance 族：

| |
|---|
| $[\texttt{τ}_{0,0}\texttt{.[N]A: Q}]$ |
| $[\texttt{τ}_{0,0}\texttt{.[N]A.[N]A: Q}]$ |
| $[\texttt{τ}_{0,0}\texttt{.[N]A.[N]A.[N]A: Q}]$ |
| … |

| |
|---|
| $[\texttt{τ}_{0,0}\texttt{.A: Q}]$ |
| $[\texttt{τ}_{0,0}\texttt{.A.A: Q}]$ |
| $[\texttt{τ}_{0,0}\texttt{.A.A.A: Q}]$ |
| … |

下面「protocol `Q` 的 rewrite system」那张清单给出了 `Q` 的 convergent rewrite system，它从 protocol `N` 导入规则。Completion 发现了下列 critical pair；因为与先前的例子类似，我们满足于只做个摘要：

- 规则 (6) 与 (7) 在 $[\texttt{Q}]\cdot[\texttt{Q}]\cdot\texttt{A}$ 上 overlap。我们定义出规则 (*10)（这条一般原理在本章 More Critical Pairs 一节关于 protocol `S` 的例子里已经确立）。
- 规则 (8) 与 (2) 在 $[\texttt{Q}]\cdot[\texttt{N}]\cdot\texttt{A}$ 上 overlap。我们定义出规则 (*11)（见本章 More Critical Pairs 一节关于 protocol 继承的例子）。
- 规则 (9) 与 (7) 在 $[\texttt{Q}]\cdot\texttt{A}\cdot[\texttt{Q}]$ 上 overlap。我们定义出规则 (*12)，并把规则 (9) 标记为 **left-simplified**（见本章 Associated Types 一节关于第一类 overlap 的例子）。
- 规则 (*12) 与 (8) 在 $[\texttt{Q}|\texttt{A}]\cdot[\texttt{Q}]\cdot[\texttt{N}]$ 上 overlap。我们定义出规则 (*13)。
- 规则 (*12) 与 (7) 在 $[\texttt{Q}|\texttt{A}]\cdot[\texttt{Q}]\cdot\texttt{A}$ 上 overlap。我们定义出规则 (*14)（见本章 Associated Types 一节第一个例子）。
- 规则 (*13) 与 (2) 在 $[\texttt{Q}|\texttt{A}]\cdot[\texttt{N}]\cdot\texttt{A}$ 上 overlap。我们定义出规则 (*15)。

**清单（protocol `Q` 的 rewrite system）.**

$$[\texttt{N}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}] \tag{1}$$

$$[\texttt{N}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}] \tag{2}$$

$$[\texttt{N}|\texttt{A}]\cdot[\texttt{N}]\Rightarrow[\texttt{N}|\texttt{A}] \tag{3}$$

$$[\texttt{N}]\cdot[\texttt{N}|\texttt{A}]\Rightarrow[\texttt{N}|\texttt{A}] \tag{*4}$$

$$[\texttt{N}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}] \tag{*5}$$

$$[\texttt{Q}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}] \tag{6}$$

$$[\texttt{Q}]\cdot\texttt{A}\Rightarrow[\texttt{Q}|\texttt{A}] \tag{7}$$

$$[\texttt{Q}]\cdot[\texttt{N}]\Rightarrow[\texttt{Q}] \tag{8}$$

$$[\texttt{Q}]\cdot\texttt{A}\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot\texttt{A} \tag{9}$$

$$[\texttt{Q}]\cdot[\texttt{Q}|\texttt{A}]\Rightarrow[\texttt{Q}|\texttt{A}] \tag{*10}$$

$$[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\Rightarrow[\texttt{Q}|\texttt{A}] \tag{*11}$$

$$[\texttt{Q}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}|\texttt{A}] \tag{*12}$$

$$[\texttt{Q}|\texttt{A}]\cdot[\texttt{N}]\Rightarrow[\texttt{Q}|\texttt{A}] \tag{*13}$$

$$[\texttt{Q}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{Q}|\texttt{A}]\cdot[\texttt{Q}|\texttt{A}] \tag{*14}$$

$$[\texttt{Q}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\Rightarrow[\texttt{Q}|\texttt{A}]\cdot[\texttt{Q}|\texttt{A}] \tag{*15}$$

这里有个问题。如果我们只保留那些与 associated type 声明直接对应的 associated type symbol，会怎么样？也就是说，如果我们去掉符号 $[\texttt{Q}|\texttt{A}]$ 连同规则 (7)——那条继承而来的 associated type rule $[\texttt{Q}]\cdot\texttt{A}\Rightarrow[\texttt{Q}|\texttt{A}]$——会怎样？得到的 monoid 仍然是等价的，因为这是一次 Tietze transformation。但我们将看到，completion 会失败。

规则 (8) 仍然与规则 (2) overlap，但 resolve 这个 critical pair 得到的不再是规则 (*11)，而是一条规则 $[\texttt{Q}]\cdot\texttt{A}\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$：

```
起点（basepoint）  [Q]·[N]·A
  ──([Q]·[N] ⇒ [Q])·A────────────────────────→  [Q]·A
  ──([Q]·A ⇒ [Q]·[N|A])──────────────────────⇢  [Q]·[N|A]    （虚线 = 新规则）
  ──[Q]·([N|A] ⇒ [N]·A)──────────────────────→  [Q]·[N]·A（回到起点）
```

这张图断言的是：没有了 $[\texttt{Q}|\texttt{A}]$，新规则的右侧只能退而求其次写成 $[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$——一个带前缀的长 term，而不是单个符号。

> 译注：原书此处是一张三节点的 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

规则 (9) 现在与 $[\texttt{Q}]\cdot\texttt{A}\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$ overlap。我们得到一条新规则 $[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$：

```
起点（basepoint）  [Q]·A·[Q]
  ──([Q]·A ⇒ [Q]·[N|A])·[Q]──────────────────→  [Q]·[N|A]·[Q]
  ──([Q]·[N|A]·[Q] ⇒ [Q]·[N|A])──────────────⇢  [Q]·[N|A]    （虚线 = 新规则）
  ──[Q]·([N|A] ⇒ A)──────────────────────────→  [Q]·A
  ──([Q]·A ⇒ [Q]·A·[Q])──────────────────────→  [Q]·A·[Q]（回到起点）
```

这张图断言的是：上一条新规则立刻又生出一条更长的新规则，而后者会自我 overlap。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，这里用 Unicode 箭头的环路列表转述；图的原貌见官方 PDF 对应章节。

现在，规则 $[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$ 与它自己在 term $[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]$ 上 overlap：

$$\begin{aligned} [\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot{}&[\texttt{Q}]\\ &[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}] \end{aligned}$$

这条规则与自身的 overlap 生成一个由 $m$、$n\in\mathbb{N}$ 标号的无穷 critical pair 族：

```
起点（basepoint）  [Q]·[N|A]ᵐ·[Q]·[N|A]ⁿ·[Q]
  ──（原书此边无标签）─────────────────────→  [Q]·[N|A]^(m+n)·[Q]
  ──([Q]·[N|A]^(m+n)·[Q] ⇒ [Q]·[N|A]^(m+n))⇢  [Q]·[N|A]^(m+n)
  ──（原书此边无标签）─────────────────────→  [Q]·[N|A]ᵐ·[Q]·[N|A]ⁿ
  ──（原书此边无标签）─────────────────────→  [Q]·[N|A]ᵐ·[Q]·[N|A]ⁿ·[Q]（回到起点）
```

这张图断言的是：与前面 protocol `N` 去掉 associated type symbol 后的情形同构——每对 $(m,n)$ 都围出一个菱形环并生出一条更长的新规则，于是 completion 不终止。

> 译注：原书此处是一张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，作者只填了四个节点与其中一条边的标签，其余三条边的标签留空；这里照实转述，用 Unicode 箭头的环路列表；图的原貌见官方 PDF 对应章节。

这些 critical pair 定义出一个无穷的 rewrite rule 族：

$$[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]$$
$$[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]$$
$$[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{Q}]\Rightarrow[\texttt{Q}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]\cdot[\texttt{N}|\texttt{A}]$$
$$\ldots$$

回想一下，protocol 上的 reduction order 被定义成先比较 protocol inheritance closure 里的元素个数，再比较名字。所以如果 `N` 与 `Q` 都不继承任何别的 protocol，我们会有 $[\texttt{N}]<[\texttt{Q}]$。但由于 `Q` 继承自 `N`，我们有 $[\texttt{Q}]<[\texttt{N}]$，从而 $[\texttt{Q}|\texttt{A}]<[\texttt{N}|\texttt{A}]$。我们不展开细节，但上述 rewrite system 的收敛**同样**依赖于 reduction order 是这个样子。若反过来有 $[\texttt{N}|\texttt{A}]<[\texttt{Q}|\texttt{A}]$，我们的 rewrite system 就不会有（有限的）convergent presentation（下面会看到我们仍能描述出一个**无穷的** convergent presentation，但我们没法拿它来计算）。

为总结这套理论，让我们把 `A`、$[\texttt{N}|\texttt{A}]$、$[\texttt{Q}|\texttt{A}]$、$[\texttt{P}]$、$[\texttt{Q}]$ 分别写成 $a$、$b$、$c$、$p$、$q$。

> 译注：这句里的符号对照有两处对不上——本例的两个 protocol 是 `N` 与 `Q`，并没有 `P`，所以 $[\texttt{P}]$ 应为 $[\texttt{N}]$；而后文所有 presentation 用的字母是 $n$ 而不是 $p$。疑为笔误，按 $[\texttt{N}]\mapsto n$ 读即可。
`N` 与 `Q` 的 identity conformance rule 与用户手写 requirement 定义出下面这个 presentation：

$$M_1 := \langle a,n,q\,|\,nn\sim n,\, nq\sim n,\, qq\sim q,\,nan\sim na,\,qaq\sim qa\rangle$$

Completion 在它上面不终止；抽象地看，我们在同一组生成元上得到一个无穷的 convergent presentation：

$$M_1^\prime := \langle a,n,q\,|\,na^in\sim na^i,\, qa^in\sim qa^i,\,qa^iq\sim qa^i\rangle$$

第一次 Tietze transformation 加入 $b$ 及其定义规则 $na\sim b$，和上一个例子一样：

$$M_2 := \langle a,b,n,q\,|\,nn\sim n,\, qq\sim q,\, qn\sim q,\, nan\sim na,\,qaq\sim qa,\,na\sim b\rangle$$

我们看到 completion 仍然失败；得到的是下面这个无穷的 convergent presentation：

$$M_2^{\prime} := \langle a,b,n,q\,|\,nn\sim n,\,na\sim b,\,bn\sim b,\,ba\sim bb,\,qb^iq\sim qb^i,\, qb^ia\sim qb^{i+1}\rangle$$

不过接下来我们加入 $c$ 及其定义规则 $qa\sim c$：

$$M_3 := \langle a,b,c,n,q\,|\,nn\sim n,\, qq\sim q,\, qn\sim q,\, nan\sim na,\,qaq\sim qa,\,na\sim b,\,qa\sim c\rangle$$

在 $c<b<a$ 且 $p<n$ 的 reduction order 下，completion 在 $M_3$ 上成功，我们得到一个有限的 convergent rewriting system。那一堆规则前面已经列过一次，这里不再重复。把这个有限的 convergent presentation 称作 $M_2^\prime$：

$$M_3^\prime := \langle a,b,c,n,q\,|\,\ldots 15\text{ 条 rewrite rule}\ldots\rangle$$

minimize 之后的 rewrite system 对应这个 presentation：

$$M_4 :=\langle a,b,c,n,q\,|\,nn\sim n,\, na\sim b,\, bn\sim b,\, qq\sim q,\, qa\sim c,\, qn\sim q,\, cq\sim c\rangle$$

若我们从 $M_3$ 出发做 completion，又会得到 $M_2^\prime$。

> 译注：原书此处记号自相矛盾：紧接着的公式定义的是 $M_3^\prime$，正文却说「把这个有限的 convergent presentation 称作 $M_2^\prime$」，而 $M_2^\prime$ 在上文已被用来指那个**无穷**的 presentation；末句「从 $M_3$ 出发做 completion，又会得到 $M_2^\prime$」按上下文应为 $M_3^\prime$。疑为笔误，以公式里的 $M_3^\prime$ 为准。

**例.** 我们最后一个例子把 Requirement Machine 的一个限制暴露无遗：一个 rewrite system 不收敛的 generic signature。它多半是这类情形里最简单的一个，所以我们要仔细研究。我们要把 protocol `N` 的递归性，与本章 Associated Types 一节末尾那个例子里「两个无关 protocol 的同名 associated type 相等价」的情形结合起来。设定与那个例子相同，只是现在两个 associated type 都带上了 recursive conformance requirement：

```swift
protocol P1 {
  associatedtype A: P1
}

protocol P2 {
  associatedtype A: P2
}
```

我们定义一个同时 conform to `P1` 与 `P2` 的 type parameter：

```
<τ_0_0 where τ_0_0: P1, τ_0_0: P2>
```

初始的 rewrite rule 如下：

$$[\texttt{P1}]\cdot[\texttt{P1}]\Rightarrow[\texttt{P1}] \tag{1}$$

$$[\texttt{P1}]\cdot\texttt{A}\Rightarrow[\texttt{P1}|\texttt{A}] \tag{2}$$

$$[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}]\Rightarrow[\texttt{P1}|\texttt{A}] \tag{3}$$

$$[\texttt{P1}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}] \tag{4}$$

$$[\texttt{P2}]\cdot[\texttt{P2}]\Rightarrow[\texttt{P2}] \tag{5}$$

$$[\texttt{P2}]\cdot\texttt{A}\Rightarrow[\texttt{P2}|\texttt{A}] \tag{6}$$

$$[\texttt{P2}|\texttt{A}]\cdot[\texttt{P2}]\Rightarrow[\texttt{P2}|\texttt{A}] \tag{7}$$

$$[\texttt{P2}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{P2}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}] \tag{8}$$

$$\tau_{0,0}\cdot[\texttt{P1}]\Rightarrow\tau_{0,0} \tag{9}$$

$$\tau_{0,0}\cdot[\texttt{P2}]\Rightarrow\tau_{0,0} \tag{10}$$

在我们这个 generic signature 里，type parameter 有无穷多个，形式都是 $\tau_{0,0}$ 后面跟一串由 `A`、`[P1]A` 与 `[P2]A` 组合而成的成员：

$$\texttt{τ}_{0,0}\texttt{.A}$$
$$\texttt{τ}_{0,0}\texttt{.[P2]A.[P1]A}$$
$$\texttt{τ}_{0,0}\texttt{.[P1]A.A.[P2]A}$$
$$\ldots$$

等价类的归属由 type parameter 里出现的 `A` 的个数决定，所以 `τ_0_0.[P1]A.[P1]A`、`τ_0_0.A.A` 与 `τ_0_0.[P2]A.[P2]A` 全都等价，我们因此能为这些等价推出 same-type requirement。

规则 (9) 与 (10) 分别与 (2) 和 (6) overlap。resolve 这些 overlap 的过程与本章 Associated Types 一节末尾那个例子一样：

$$\tau_{0,0}\cdot\texttt{A}\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}] \tag{11}$$

$$\tau_{0,0}\cdot[\texttt{P2}|\texttt{A}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}] \tag{12}$$

我们加了新规则，所以必须再查一遍 overlap 的规则。现在 (12) 与 (7) 在 term $\tau_{0,0}\cdot[\texttt{P2}|\texttt{A}]\cdot[\texttt{P2}]$ 上 overlap，而规则 (12) 也与 (8) 在 term $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}]\cdot\texttt{A}$ 上 overlap。Resolve 这两个 critical pair 又加进两条新规则：

$$\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}] \tag{13}$$

$$\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}] \tag{14}$$

我们现在开始第三轮，又有两个 critical pair：规则 (14) 与 (7) 在 term $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}]\cdot[\texttt{P2}]$ 上 overlap，与 (8) 在 term $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}]\cdot\texttt{A}$ 上 overlap。一个模式开始浮现了。我们加了两条新规则，但又冒出两个新的 critical pair：

$$\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}] \tag{15}$$

$$\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P2}|\texttt{A}]\Rightarrow \tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}]\cdot[\texttt{P1}|\texttt{A}] \tag{16}$$

Completion 最终撞上限制并失败。我们这个 rewrite system 实际上有两个无穷的 critical pair 族；第一族对每个 $n\in\mathbb{N}$ 定义出一条规则 $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]^n\cdot[\texttt{P2}]\Rightarrow\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]^n$：

```
起点（basepoint）  τ_0_0·[P1|A]^(n-1)·[P2|A]·[P2]
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]ⁿ·[P2]
  ──（原书此边无标签）────────────────────⇢  τ_0_0·[P1|A]ⁿ
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]^(n-1)·[P2|A]
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]^(n-1)·[P2|A]·[P2]（回到起点）
```

第二族定义出 $\tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]^n\cdot[\texttt{P2}|\texttt{A}]\Rightarrow \tau_{0,0}\cdot[\texttt{P1}|\texttt{A}]^{n+1}$：

```
起点（basepoint）  τ_0_0·[P1|A]^(n-1)·[P2|A]·A
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]ⁿ·[P2|A]
  ──（原书此边无标签）────────────────────⇢  τ_0_0·[P1|A]^(n+1)
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]ⁿ·A
  ──（原书此边无标签）─────────────────────→  τ_0_0·[P1|A]^(n-1)·[P2|A]·A（回到起点）
```

这两张图断言的是：每个 $n$ 都围出一个同构的四节点菱形环，各自生出一条比上一条更长的新规则；两族叠在一起，规则集永远长不完。

> 译注：原书此处是两张 `\FourLoopDerived` 四节点菱形 tikzcd 交换图，作者只填了节点、四条边的标签全部留空；这里照实转述，用 Unicode 箭头的环路列表；图的原貌见官方 PDF 对应章节。

在 protocol `N` 里，associated type rule 让我们能用有限条 rewrite rule 表达无穷个 derived requirement。在接下来那个 protocol `Q` 继承 `N` 的例子里，继承而来的 associated type rule 救了场。可这一回，我们手上再没有别的花招了。

让我们把 `A`、$[\texttt{P}|\texttt{A}]$、$[\texttt{Q}|\texttt{A}]$、$[\texttt{P}]$、$[\texttt{Q}]$、$\tau_{0,0}$ 分别写成 $a$、$b$、$c$、$p$、$q$、$t$。

> 译注：本例的两个 protocol 名叫 `P1` 与 `P2`，原书这里却沿用了 `P` / `Q` 的写法；按后文 presentation 的用法，$p$ 对应 $[\texttt{P1}]$、$q$ 对应 $[\texttt{P2}]$，$b$、$c$ 分别对应 $[\texttt{P1}|\texttt{A}]$ 与 $[\texttt{P2}|\texttt{A}]$。疑为笔误。
我们这个 generic signature 在字母表 $a$、$p$、$q$、$t$ 上定义出下面这个 monoid presentation：

$$M_1 := \langle a,p,q,t\,|\,pp\sim p,\,pap\sim pa,\,qq\sim q,\, qaq\sim qa,\, tp\sim t,\, tq\sim t\rangle$$

Requirement Machine 加入了符号 $b$ 与 $c$，其定义规则分别是 $pa\sim b$ 与 $qa\sim c$：

$$M_2 := \langle a,b,c,p,q,t\,|\,pp\sim p,\,pap\sim pa,\,qq\sim q,\, qaq\sim qa,\,tp\sim t,\, tq\sim t,\,pa\sim b,\,qa\sim c\rangle$$

我们看到 completion 失败了；得到的是同一字母表上一个无穷的 convergent presentation：

$$M_2^\prime := \langle a,b,c,p,q,t\,|\,pp\sim p,\,pa\sim b,\,bp\sim b,\,ba\sim bb,\,qq\sim q,\,qa\sim c,\,cq\sim c,\,ca\sim cc,\,ta\sim tb,\, tb^iq\sim tb^i,\,tb^ic\sim tb^{i+1}\rangle$$

事实上，associated type rule 对我们理解这个 monoid 毫无帮助。我们同样可以为 $M_1$ 的 completion 写下一个无穷的 convergent presentation：

$$M_1^\prime := \langle a,p,q,t\,|\,pa^ip\sim pa^i,\, qa^iq\sim qa^i,\, ta^ip\sim ta^i,\, ta^iq\sim ta^i\rangle$$

这个无穷 presentation 简单到可以为 $M_1^\prime$ 里的 word problem 专门实现一个一次性算法。我们还能进一步简化原来的 monoid presentation，把 $pp\sim p$ 与 $qq\sim q$ 去掉；结果**不是** Tietze-equivalent 的，但它在 completion 上遇到的问题一模一样。

### Future directions

现在我们要就这个只有四个符号与四条 rewrite rule、却出奇简单的 monoid presentation，提出一个开放问题：

> monoid $\langle a,p,q,t\,|\,pap\sim pa,\, qaq\sim qa,\, tp\sim t,\, tq\sim t\rangle$ 能否由一个有限的 convergent rewriting system 呈现？

两种可能的结局都有意义：

- 如果答案是肯定的，那么 Requirement Machine 或许能通过调整构造 rewrite system 的符号与规则的方式，来支持我们这个 generic signature。
- 如果我们反而证明了不存在这样的 convergent rewriting system，那我们就又得到一个例子：一个 word problem 可判定、却无法由有限 convergent rewriting system 呈现的 finitely-presented monoid，正如 `monoids.tex` 里那条关于 Squier 的 $S_1$ 的定理所给出的那个。

研究无穷 convergent rewriting system 的一条路子是走形式语言理论；Otto 1998 年的「Infinite Convergent String-rewriting Systems and Cross-sections for Finitely Presented Monoids」（《Journal of Symbolic Computation》）探索了这条路。我们回顾一下标准定义，它们可以在 Perrin 1990 年的《Handbook of Theoretical Computer Science (Vol. B)》第 1 章「Finite Automata」里找到。字母表 $A$ 上的一个**语言**是自由 monoid $A^*$ 的一个子集；一个语言称为 **recursive**，如果存在一个全可计算函数来判定这个集合的成员资格；而一个 **regular language** 是被某个有限状态自动机识别的字符串集合（等价地说，匹配某个正则表达式——经典意义上的那种，不含反向引用）。一个（有限或无穷的）convergent rewriting system 里各条规则的左侧，在这个意义下定义了一个语言，而有限 convergent rewriting system 就是这个语言为有限集的特例。

每个 finitely-presented monoid 都能由某个无穷 convergent rewriting system 呈现；但若这个 monoid 的 word problem 不可判定，那么这个 rewrite system 的语言就不是 recursive 的，所以这个视角当然不会从根本上改变问题的难度。不过，如果我们把无穷 convergent presentation 限制到一类足够受限的语言上（例如 regular language），我们就能为这一类 rewrite system 找到一个有效的 term reduction 过程。这时 completion 就变成一个非常不平凡的问题。Needham 1996 年的「Infinite complete group presentations」（《Journal of Pure and Applied Algebra》）提出了针对某一类无穷 convergent rewriting system 的 completion procedure；在那里，规则左侧带指数，很像我们例子里用的 $ta^ip\sim ta^i$ 与 $ta^iq\sim ta^i$ 这种记法。原则上，这样一个扩展有朝一日可以为 Requirement Machine 所考虑。

**例.** 本章以最后一件趣事收尾。我们在 `monoids.tex` 的 A Swift Connection 一节里，通过把任意 finitely-presented monoid $\langle A\,|\,R\rangle$ 编码成一份 protocol 声明，证明了 derived requirement 形式系统是不可判定的。而在 `symbols-terms-and-rules.tex` 里，我们定义了把一个 generic signature 及其 protocol dependency 下降成一个 finitely-presented monoid 的过程。如果把这两个变换串起来，我们就能把一个 finitely-presented monoid 映成一份 protocol 声明，再映回一个 finitely-presented monoid。那么后一个 monoid 是在什么意义上编码了原来那个 monoid 的呢？

设 $A^*:=\{a,b,c\}$，$R:=\{(ab,c),\,(bc,\varepsilon)\}$，考虑 monoid $M:=\langle A\,|\,R\rangle$。写成 Swift protocol，$M := \langle a,b,c\,|\,ab\sim c,\,bc\sim\varepsilon\rangle$ 长这样：

```swift
protocol P {
  associatedtype A: P
  associatedtype B: P
  associatedtype C: P
    where A.B == C, B.C == Self
}
```

现在我们假装把 `where` 从句注释掉，于是 protocol `P` 呈现的就只是自由 monoid $A^*$。我们来列出 `P` 的 convergent rewriting system，但这次换一种方式把规则分成两组。第一组规则涉及 name symbol，我们称这一组为 $\mathcal{N}$：

$$[\texttt{P}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}]\cdot\texttt{C}\Rightarrow[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{A}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{A}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}|\texttt{A}]\cdot\texttt{C}\Rightarrow[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{B}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{B}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}|\texttt{B}]\cdot\texttt{C}\Rightarrow[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{C}]\cdot\texttt{A}\Rightarrow[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{C}]\cdot\texttt{B}\Rightarrow[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}|\texttt{C}]\cdot\texttt{C}\Rightarrow[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{C}]$$

第二组只涉及 protocol symbol 与 associated type symbol。我们称这一组为 $\mathcal{S}$：

$$[\texttt{P}]\cdot[\texttt{P}]\Rightarrow[\texttt{P}]$$
$$[\texttt{P}]\cdot[\texttt{P}|\texttt{A}]\Rightarrow[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}]\cdot[\texttt{P}|\texttt{B}]\Rightarrow[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}]\cdot[\texttt{P}|\texttt{C}]\Rightarrow[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{A}]\cdot[\texttt{P}]\Rightarrow[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{B}]\cdot[\texttt{P}]\Rightarrow[\texttt{P}|\texttt{B}]$$
$$[\texttt{P}|\texttt{C}]\cdot[\texttt{P}]\Rightarrow[\texttt{P}|\texttt{C}]$$

并集 $\mathcal{N}\cup\mathcal{S}$ 是一个编码自由 monoid $\{a,b,c\}^*$ 的 protocol 的 rewrite system。这里 $\mathcal{N}$ 有 12 个元素，$\mathcal{S}$ 有 7 个。更一般地，若 $|A|=n$，我们有 $|\mathcal{N}|=n(n+1)$ 与 $|\mathcal{S}|=2n+1$。现在，如果我们把 $a$、$b$、$c$ 与 $[\texttt{P}|\texttt{A}]$、$[\texttt{P}|\texttt{B}]$、$[\texttt{P}|\texttt{C}]$ 认同起来，并定义一个新符号 $e:=[\texttt{P}]$，就会看到 $\langle A\cup\{e\}\,|\,\mathcal{S}\rangle$ 是一个 convergent presentation。但要理解它呈现的是什么对象，我们还需要几个相关的定义。

**semigroup** 是一个集合连同其上的一个结合二元运算，但不要求有一个特定的单位元。集合 $A$ 上的**自由 semigroup**（记作 $A^+$）是由 $A$ 的符号组成的所有**非空**字符串的集合。我们可以仿照 finitely-presented monoid 来定义 **finitely-presented semigroup**；这里 rewrite rule 的形式是 $(u,v)$，其中 $u$、$v\in A^+$。

每个 monoid 都平凡地满足 semigroup 公理，因此自由 monoid $A^*$ 也是一个 semigroup。但自由 monoid $A^*$ **不是**一个**自由** semigroup。例如取 $A:=\{a,b,c\}$，在 $A^*$ **作为 semigroup 来看**的元素里，我们有一些涉及 $\varepsilon$ 的非平凡恒等式，比如 $a=\varepsilon a$、$b\varepsilon=b$，等等。因此它不可能是自由 semigroup——在自由 semigroup 里，对所有 $x$、$y\in A^+$ 都有 $xy\neq x$ 且 $xy\neq y$。不过自由 monoid $A^*$ **确实**是一个 finitely-presented semigroup；我们必须给字母表加上符号 $e$，并为每个 $x\in A$ 加上一对 rewrite rule $ex\sim e$、$xe\sim e$。例如作为 semigroup，$\{a,b,c\}^*$ 有四个生成元和七条 rewrite rule：

$$\langle a,b,c,e\,|\,e\sim e,\,ea\sim a,\,eb\sim b,\,ec\sim c,\,ae\sim a,\,be\sim b,\,ce\sim c\rangle$$

> 译注：原书正文说要为每个 $x\in A$ 加上 $ex\sim e$ 与 $xe\sim e$，但紧接着的公式里写的是 $ea\sim a$、$ae\sim a$ 这一类（即 $ex\sim x$、$xe\sim x$），后者才与「$e$ 充当单位元」以及与 $\mathcal{S}$ 的对应关系吻合；另外公式首项 $e\sim e$ 是平凡恒等式，按 $\mathcal{S}$ 的第一条应为 $ee\sim e$。两处均疑为笔误，以公式其余部分与 $\mathcal{S}$ 为准。

确实，我们看到这组 rewrite rule 正是 $\mathcal{S}$；于是我们把自由 monoid 嵌入成一个 Swift protocol，最终就是把自由 monoid 编码成了 finitely-presented semigroup $\langle A\cup\{e\}\,|\,\mathcal{S}\rangle$，只不过它又被嵌在一个更大的、同时含有 name symbol 与规则集 $\mathcal{N}$ 的 semigroup 里。

现在，我们设想把 protocol `P` 的 `where` 从句取消注释，它带来两条 requirement $[\texttt{Self.A.B == C}]$ 与 $[\texttt{Self.B.C == Self}]$。这两条 requirement 给我们的 convergent rewriting system 贡献两条新的 rewrite rule；我们把这一组称作 $\mathcal{R}$：

$$[\texttt{P}|\texttt{A}]\cdot[\texttt{P}|\texttt{B}]\Rightarrow[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{C}]\Rightarrow[\texttt{P}]$$

我们可以从 $R$ 构造出 $\mathcal{R}$：把 rewrite rule 里任何出现 $\varepsilon$ 的地方都换成 $e$。这给出一组 semigroup rewrite rule，而我们看到 $\langle A\cup\{e\}\,|\, \mathcal{S}\cup\mathcal{R}\rangle$ 是 $\langle A\,|\,R\rangle$ 的一个 semigroup presentation：

$$\langle a,b,c,e\,|\,ee\sim e,\,ea\sim a,\,eb\sim b,\,ec\sim c,\,ae\sim a,\,be\sim b,\,ce\sim c,\,ab\sim c,\,bc\sim e\rangle$$

monoid presentation $M$ 与 semigroup presentation $\langle A\cup\{e\}\,|\,\mathcal{S}\cup\mathcal{R}\rangle$ 都不是 convergent 的。现在考虑下面这组 rewrite rule $\hat{R}$：

$$\hat{R} := \{(cc,a),\,(ba,c),\,(ca,a),\,(cb,\varepsilon)\}$$

一个平凡但繁琐的计算表明，$\langle A\,|\,R\cup\hat{R}\rangle$ 是 $\langle A\,|\,R\rangle$ 的一个 convergent monoid presentation。接下来我们把 $\hat{R}$ 变换成一组 semigroup rewrite rule，同样把 $\varepsilon$ 换成 $e$。我们把这一组称作 $\hat{\mathcal{R}}$：

$$[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{C}]\Rightarrow[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{B}]\cdot[\texttt{P}|\texttt{A}]\Rightarrow[\texttt{P}|\texttt{C}]$$
$$[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{A}]\Rightarrow[\texttt{P}|\texttt{A}]$$
$$[\texttt{P}|\texttt{C}]\cdot[\texttt{P}|\texttt{B}]\Rightarrow[\texttt{P}]$$

我们现在断言 $\langle A\cup\{e\}\,|\,\mathcal{S}\cup\mathcal{R}\cup\hat{\mathcal{R}}\rangle$ 是一个 convergent semigroup presentation，因为我们可以机械地把 $\langle A\,|\,R\cup\hat{R}\rangle$ 上的任意 positive rewrite path 变换成这个 semigroup presentation 上的 positive rewrite path。唯一不能平凡映射过去的 rewrite step 是 $x(cb\Rightarrow\varepsilon)y$（$x$、$y\in A^*$）。semigroup presentation 上对应的 rewrite step $x(cb\Rightarrow e)y$ 的终点 term 是 $xey$ 而不是 $xy$。若 $x$ 与 $y$ 中至少一个非空，我们可以从 $\mathcal{S}$ 里补一个 positive rewrite step 把这个 $e$ 消掉。否则，若 $xey=e$，那就什么都不用做。在任何给定的 positive rewrite path 里，这个变换只会补进有限多个用到 $\mathcal{S}$ 中 rewrite rule 的新 rewrite step。因此，confluence 与 termination 都被保持了下来。

一般来说，两个 convergent rewriting system 的并集当然未必 convergent，但在我们这个构造里它恰好成立。$\mathcal{N}$、$\mathcal{S}$ 与 $\mathcal{R}$ 的元素之间没有非平凡的 overlap。我们于是证明了下面这条定理：

**定理.** 设 $\langle A\,|\,R\rangle$ 是一个 finitely-presented monoid，$\hat{R}$ 是一个有限 rewrite rule 集合，使得 $\langle A\,|\,R\cup\hat{R}\rangle$ 是一个 convergent monoid presentation，且 $R$ 与 $\hat{R}$ 都相对于 $A^*$ 上的 shortlex order 定向。我们定义一个编码 $\langle A\,|\,R\rangle$ 的 protocol `P`，其 associated type 的命名与生成元集 $A$ 上那个固定的全序相对应（例如若 $a<b<c<\cdots$，则有 $[\texttt{P}|\texttt{A}]<[\texttt{P}|\texttt{B}]<[\texttt{P}|\texttt{C}]$）。那么我们这个 protocol `P` 有如下的 **convergent** presentation：

$$\langle A\cup\{e\}\cup B\,|\,\mathcal{N}\cup\mathcal{S}\cup\mathcal{R}\cup\hat{\mathcal{R}}\rangle$$

其中 $e:=[\texttt{P}]$，$B$ 是一组 name symbol，$\mathcal{N}$ 与 $\mathcal{S}$ 只依赖于 $A$，而 $\mathcal{R}$ 与 $\hat{\mathcal{R}}$ 按上述方式由 $R$ 与 $\hat{R}$ 构造。上面呈现的这个 semigroup 还含有一个具有下列 convergent presentation 的 sub-semigroup：

$$\langle A\cup\{e\}\,|\,\mathcal{S}\cup\mathcal{R}\cup\hat{\mathcal{R}}\rangle$$

这个 sub-semigroup 与 monoid $\langle A\,|\,R\cup\hat{R}\rangle$ 同构，因而也与 $\langle A\,|\,R\rangle$ 同构。

于是我们看到：若把一个 finitely-presented monoid $\langle A\,|\,R\rangle$ 编码成 protocol `P`，那么 Requirement Machine 会接受 `P` 并解出 $\langle A\,|\,R\rangle$ 里的 word problem，当且仅当 $\langle A\,|\,R\rangle$ 有一个与 $A^*$ 上 shortlex order 相容的 convergent presentation。对于「Swift 的类型检查是不可判定的」这句话，这是一个令人满意的收尾。

我们这套「monoid 编码成 protocol、protocol 再编码成 rewrite system」的双重编码引入了大量原 presentation 里没有的新符号与新 rewrite rule。因此，我们这个构造有一个了不起的性质：一个 convergent 的 monoid presentation 总能映成一个 convergent 的 rewriting system，而那些多出来的杂质总是可以被「约掉」。

## Source Code Reference

关键源文件：

- `lib/AST/RequirementMachine/KnuthBendix.cpp`
- `lib/AST/RequirementMachine/RewriteSystem.cpp`
- `lib/AST/RequirementMachine/Trie.h`

**`rewriting::RewriteSystem`（class）**

另见 `symbols-terms-and-rules.tex` 的 Source Code Reference 一节。

- **`addRule()`**：实现 Resolve critical pair 算法。
- **`recordRewriteLoop()`**：若这个 rewriting system 用于 minimization，则记录一个 rewrite loop。
- **`computeCriticalPair()`**：实现 Construct critical pair 算法。
- **`performKnuthBendix()`**：实现 Knuth-Bendix completion procedure 算法。
- **`simplifyLeftHandSides()`**：实现 Left-simplify rules 算法。
- **`simplifyRightHandSides()`**：实现 Right-simplify rules 算法。

**`rewriting::Trie`（template class）**

另见 `symbols-terms-and-rules.tex` 的 Source Code Reference 一节。

- **`findAll()`**：用 Find overlapping rules 算法找出所有 overlap 的规则。

---

> 译自 `docs/Generics/chapters/completion.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
