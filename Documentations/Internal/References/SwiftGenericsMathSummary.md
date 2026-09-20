# Mathematical Conventions（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/math-summary.tex`（《Compiling Swift Generics》一书的「Mathematical Conventions」一章，全书三个附录之一），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这是全书的数学写作约定与基础集合论记号总表，后面每一章的形式化小节都按它来读。对本库（MachOSwiftSection）而言，本附录不对应任何实现——它是**读法**，不是机制；真正跟本库有对应的是它服务的那些章节（generic signature、substitution map、conformance）。把它单独译出来的理由是：全书三个附录合起来就是一部记号索引，先把记号钉死，其余各章的公式才读得动。
>
> **术语**：书中定义的术语一律保留英文（set、subset、union、intersection、Cartesian product、function、homomorphism、binary operation、cardinality、formal system、equivalence relation、partial order、monoid、string rewriting……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Derived Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下。
>
> **记法约定**（本附录属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`）。全书的中译分两种风格：散文章节用**纯文本 Unicode** 记法，Part IV 与三个附录用 **LaTeX** 记法。下表给出两套写法的对照，便于在两种风格的译文之间对上号——左边是本文用的 LaTeX，中间是散文章节（如 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）用的纯文本：
>
> | LaTeX（本文） | 纯文本（散文章节） | 含义 |
> |---|---|---|
> | `$\varnothing$` → $\varnothing$ | `∅` | empty set |
> | `$\mathbb{N}$` → $\mathbb{N}$ | `ℕ` | 自然数集 |
> | `$\mathbb{Z}$` → $\mathbb{Z}$ | `ℤ` | 整数集 |
> | `$\in$` / `$\notin$` → $\in$ / $\notin$ | `∈` / `∉` | 属于 / 不属于 |
> | `$\subseteq$` / `$\subsetneq$` → $\subseteq$ / $\subsetneq$ | `⊆` / `⊊` | subset / proper subset |
> | `$\cup$` / `$\cap$` / `$\setminus$` → $\cup$ / $\cap$ / $\setminus$ | `∪` / `∩` / `\` | union / intersection / difference |
> | `$\times$` → $\times$ | `×` | Cartesian product |
> | `$\rightarrow$` → $\rightarrow$ | `→` | 函数箭头 |
> | `$\mapsto$` → $\mapsto$ | `↦` | 「映到」（substitution map 里用） |
> | `$\otimes$` → $\otimes$ | `⊗` | 二元运算；全书几乎专指 type substitution |
> | `$\triangleleft$` → $\triangleleft$ | `◁` | 另一个二元运算符号（见 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)）） |
> | `$\neq$` / `$\leq$` → $\neq$ / $\leq$ | `≠` / `≤` | 不等 / 小于等于 |
> | `$\vdash$` → $\vdash$ | `⊢` | turnstile，`G ⊢ D` 读作「$D$ 属于 $G$ 的 theory」 |
> | `$\Sigma$`、`$\sigma$`、`$\tau$` → $\Sigma$、$\sigma$、$\tau$ | `Σ`、`σ`、`τ` | 希腊字母 |
> | `$\tau_{d,i}$` → $\tau_{d,i}$ | `τ_d_i` | depth `d`、index `i` 的 generic parameter |
> | `$[\texttt{T: P}]$` | `[T: P]` | conformance requirement / conformance |
> | `$[\![\texttt{T}]\!]$` | `⟦T⟧` | primary archetype |
> | `$\circlearrowright\texttt{T}$` | `↻T` | opaque archetype |
> | `$\mathsf{Type}(G)$` | `Type(G)` | 原书用 small caps；KaTeX 无 `\textsc`，本文一律改用 `\mathsf` |
>
> 原书的 `\uptau`（直立 tau）在 Markdown 数学里渲染不出来，本文一律写 `\tau`。

---

本书里偏形式化的那些小节按「欧几里得式」写就：正文被进一步切分成下列几类元素。所有元素在同一章内连续编号，只有 algorithm 例外，它用字母编号。

- **Definition** 引入术语或记法。
- **Example** 展示这套术语和记法在实践中是怎么冒出来的。
- **Proposition** 陈述一条或多条 definition 的逻辑推论。
- **Lemma** 是为证明另一条 theorem 服务的中间 proposition。
- **Theorem** 是某种意义上更「深」、更本质的 proposition。
- **Corollary** 是前面某条 theorem 的直接结果。
- **Algorithm** 以输入和输出为准，一步一步地描述一个可计算函数。

> 译注：本套中译按规约把这七类元素分别写成 `**定义.**`、`**例.**`、`**命题.**`、`**引理.**`、`**定理.**`、`**推论.**`、`**算法.**`（原书给了名字的写成 `**定义（name）.**` 这样）。原书的编号（Example 3.12 之类）不保留，交叉引用一律改用名字。

有少数几个希腊字母被用作变量名和其他记法：小写的 $\alpha$（alpha）、$\beta$（beta）、$\gamma$（gamma）、$\varepsilon$（epsilon）、$\eta$（eta）、$\pi$（pi）、$\sigma$（sigma）、$\tau$（tau）、$\varphi$（phi），以及大写的 $\Sigma$（sigma）。「$=$」运算符说的是两个**已经存在**的东西恒同或等价，「$\neq$」说的是它们不恒同。「$:=$」运算符把左边的新东西**定义**成右边若干已有东西的组合。「$\leftarrow$」运算符表示算法里的一条命令式赋值语句。

### Sets

一个 **set** 是元素的一个汇集，不计顺序，也不计重复。Set 可以是有限的，也可以是无限的。有限 set 可以通过按任意顺序列出其元素来指定，例如 $\{a,\,b,\,c\}$。**empty set** $\varnothing$ 是唯一一个不含任何元素的 set。**natural numbers** 的 set

$$\mathbb{N}:=\{0,\,1,\,2,\,\ldots\}$$

是包含零及其全部 successor 的无限 set。**integers** 的 set

$$\mathbb{Z}:=\{\ldots,\,-2,\,-1,\,0,\,1,\,2,\,\ldots\}$$

则还包含负整数。

记法 $x\in S$ 的意思是「$x$ 是 set $S$ 的一个元素」，$x\notin S$ 是它的否定。Set 的性质可以用**存在**量化（「存在（至少一个）$x\in S$，使得 $x$ 具有这个性质……」）或**全称**量化（「对所有 $x\in S$，下面这条性质对 $x$ 成立……」）来定义。

如果对所有 $x\in X$ 都有 $x\in Y$，就说 set $X$ 是另一个 set $Y$ 的 **subset**，记作 $X\subseteq Y$。若 $X\subseteq Y$ 且 $Y\subseteq X$，则两个 set 拥有相同的元素，因而相等，即 $X=Y$。若 $X\subseteq Y$ 且 $X\neq Y$，则 $X$ 是 $Y$ 的 **proper** subset，记作 $X\subsetneq Y$。**union** $X\cup Y$ 是所有属于 $X$ 或属于 $Y$ 的元素构成的 set。**intersection** $X\cap Y$ 是所有既属于 $X$ 又属于 $Y$ 的元素构成的 set。**difference** $X\setminus Y$ 是 $X$ 中所有不同时属于 $Y$ 的元素构成的 set。

两个 set $X$ 与 $Y$ 的 **Cartesian product** 记作 $X\times Y$，它是所有 **ordered pair** $(x,y)$ 构成的 set，其中 $x\in X$、$y\in Y$。注意 ordered pair $(x,y)$ 与 set $\{x,y\}$ 不是一回事，因为 $(x,y)\neq(y,x)$。Cartesian product 这套构造可以推广到任意有限多个 set，从而给出 **ordered tuple**（也叫 **sequence**）。

### Functions

一个 **function**（也叫 **mapping**）$f\colon X\rightarrow Y$ 为每个 $x\in X$ 指定唯一一个元素 $f(x)\in Y$。如果 set $X$ 和 $Y$ 带有某种额外结构（这种结构会被显式定义），那么当 $f$ 保持这种结构时，就说 $f$ 是一个 **homomorphism**。

定义在 Cartesian product 上的 function $f\colon X\times Y\rightarrow Z$ 可以理解成：把一对值 $x\in X$、$y\in Y$ 送到一个元素 $f(x,y)\in Z$。**binary operation** 是定义在两个 set 的 Cartesian product 上、并以某个符号命名的 function，符号如「$\otimes$」「$\triangleleft$」「$\cdot$」。Binary operation 的应用写成把符号夹在两个元素中间的形式，例如 $x\otimes y$。

> 译注：全书最重要的那个 binary operation 就是 $\otimes$——把一张 substitution map 作用到类型、conformance 或 requirement 上（完整代数见 `type-substitution-summary.tex`（中译 [SwiftGenericsSubstitutionAlgebra.md](SwiftGenericsSubstitutionAlgebra.md)），中译 [SwiftGenericsSubstitutionAlgebra.md](SwiftGenericsSubstitutionAlgebra.md)）。本库在没有运行时、也不调用 metadata accessor 的情况下把这一步离线做了一遍：按 mangled name 里的实参重写 generic parameter，见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)。

有限 set $S$ 的 **cardinality** 记作 $|S|$，即 $S$ 中元素的个数。记法 $|x|$ 有时也用来表示另外一些取值在 $\mathbb{N}$ 里的 function，例如一个 sequence 的长度；需要时都会显式定义。

## More

- Formal system（`generic-signatures.tex` 的 Derived Requirements 一节）。
- Equivalence relation（`generic-signatures.tex` 的 Valid Type Parameters 一节、`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 的 Equivalence of Terms 一节）。
- Partial order 与 linear order（`generic-signatures.tex` 的 Reduced Type Parameters 一节、`monoids.tex` 的 The Normal Form Algorithm 一节、`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Terms 一节）。
- Category theory（`substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 Composition 一节）。
- Boolean satisfiability（`conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Associated Type Inference 一节）。
- Directed graph（`archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)） 的 The Type Parameter Graph 一节、`conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)） 的 The Conformance Path Graph 一节与 Recursive Conformances 一节、`basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)） 的 Protocol Components 一节）。
- 归纳法证明（`building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 的 Well-Formed Requirements 一节）。
- Computability theory（`conformance-paths.tex` 的 The Halting Problem 一节、`monoids.tex` 的 The Word Problem 一节）。
- Finitely-presented monoid 与 string rewriting（`monoids.tex`、`completion.tex`）。

> 译注：这份清单的后半截（directed graph、computability theory、finitely-presented monoid 与 string rewriting）全指向 Requirement Machine，也就是编译器求解 generic signature 的那套重写系统。本库**不实现**重写系统：它只消费重写系统已经算完的结果——二进制里的 requirement 已经是 minimize 过的，type parameter 已经是 reduced form，本库照着读就行。读 reduced type 与 canonical 顺序的那一路，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

---

> 译自 `docs/Generics/chapters/math-summary.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
