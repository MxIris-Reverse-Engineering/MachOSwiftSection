# Substitution Algebra（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/type-substitution-summary.tex`（《Compiling Swift Generics》一书的「Substitution Algebra」一章，全书三个附录之一），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这是 type、substitution map 与 conformance 上各种运算的代数记号总表——$\otimes$ 的全部重载、四个集合（$\mathsf{Type}$ / $\mathsf{Sub}$ / $\mathsf{Conf}$ / $\mathsf{Req}$）、以及 normal / specialized / abstract 三种 conformance 之间的换算律，一页看全。本库（MachOSwiftSection）从二进制里读回来的东西刚好对应表的左半边：`__swift5_types` 里的 nominal type declaration $d$、mangled name 里的 substitution map $\Sigma$、`__swift5_proto` 里的 conformance descriptor；而本库的静态布局引擎在无运行时的情况下，把 $\otimes$ 这条运算自己实现了一遍。
>
> **术语**：书中定义的术语一律保留英文（generic signature、substitution map、interface type、type parameter、generic parameter、nominal type declaration、declared interface type、normal / specialized / abstract conformance、type witness、associated conformance、global conformance lookup、type witness projection、conformance path、protocol substitution map、dependent member type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)） 的 Type Witnesses 一节」，文件都在源码树 `docs/Generics/chapters/` 下。
>
> **记法约定**（本附录属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`）。全书中译分两种风格，下表给出两套写法的对照——左边是本文用的 LaTeX，中间是散文章节（如 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）用的纯文本 Unicode：
>
> | LaTeX（本文） | 纯文本（散文章节） | 含义 |
> |---|---|---|
> | `$\otimes$` → $\otimes$ | `⊗` | 本书的通用运算符号，按两边的类型重载（见下文各表） |
> | `$\mapsto$` → $\mapsto$ | `↦` | substitution map 内部的「映到」 |
> | `$\Sigma$`、`$\Sigma_1$` | `Σ`、`Σ₁` | substitution map |
> | `$\tau_{d,i}$` → $\tau_{d,i}$ | `τ_d_i` | depth `d`、index `i` 的 generic parameter |
> | `$[\texttt{T: P}]$` | `[T: P]` | abstract conformance（左端是 type parameter） |
> | `$[\texttt{X: P}]$` | `[X: P]` | specialized conformance（左端是具体的 interface type） |
> | `$[\texttt{X}_d\texttt{: P}]$` | `[X_d: P]` | normal conformance（左端是 $d$ 的 declared interface type） |
> | `$\texttt{X}_d$` | `X_d` | nominal type declaration $d$ 的 declared interface type |
> | `$\mathsf{Type}(G)$`、`$\mathsf{Sub}(G,H)$`、`$\mathsf{Conf}(G)$`、`$\mathsf{Req}(G)$` | `Type(G)`、`Sub(G → H)`、`Conf(G)`、`Req(G)` | 四个集合。原书用 small caps，KaTeX 无 `\textsc`，本文一律改用 `\mathsf`；散文章节的 `Sub(G → H)` 与本文的 $\mathsf{Sub}(G,H)$ 是同一个东西 |
> | `$\langle\texttt{P}]$` | `⟨P]` | 名为 `P` 的 protocol declaration |
> | `$\langle\texttt{P}\vert\texttt{A}$` | `⟨P\|A` | protocol `P` 中名为 `A` 的 associated type declaration。**原书的宏只开不闭**（左边是尖括号、中间一竖、右边没有收口），本文照原样保留 |
> | `$\langle\texttt{Self.U: Q}]$` | `⟨Self.U: Q]` | associated conformance requirement |
> | `$1_G$` | `1_G` | $G$ 的 identity substitution map |
> | `$\texttt{T.[P]A}$` | `T.[P]A` | base type 为 `T`、associated type 为 `P` 的 `A` 的 dependent member type |
>
> 原书的 `\uptau`（直立 tau）在 Markdown 数学里渲染不出来，本文一律写 `\tau`。

---

这是我们为 type、substitution map 和 conformance 上各种运算所用代数记号的小结。细节见 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）、`conformances.tex` 与 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）。

| 记号 | 含义 | 记号 | 含义 |
|---|---|---|---|
| $G$、$H$、$I$、… | generic signature | $\Sigma$、$\Sigma_1$、… | substitution map |
| $\texttt{T}$ | type parameter | $\texttt{X}$ | interface type |
| $\tau_{d,i}$ | generic parameter | $[\texttt{X}_d\texttt{: P}]$ | normal conformance |
| $d$ | nominal type declaration | $[\texttt{X: P}]$ | specialized conformance |
| $\texttt{X}_d$ | $d$ 的 declared interface type | $[\texttt{T: P}]$ | abstract conformance |

| 集合 | 含义 |
|---|---|
| $\mathsf{Type}(G)$ | $G$ 的全部 valid interface type |
| $\mathsf{Sub}(G,H)$ | input signature 为 $G$、output signature 为 $H$ 的 substitution map |
| $\mathsf{Conf}(G)$ | output generic signature 为 $G$ 的 conformance |
| $\mathsf{Req}(G)$ | 由 $G$ 的 interface type 构成的 requirement |

| 运算 | 名称 | 出处 |
|---|---|---|
| $\mathsf{Type}(G)\otimes\mathsf{Sub}(G,H)\rightarrow\mathsf{Type}(H)$ | type substitution | `substitution-maps.tex` |
| $\mathsf{Sub}(G,H)\otimes\mathsf{Sub}(H,I)\rightarrow\mathsf{Sub}(G,I)$ | substitution map composition | `substitution-maps.tex` 的 Composition 一节 |
| $\mathsf{Conf}(G)\otimes\mathsf{Sub}(G,H)\rightarrow\mathsf{Conf}(H)$ | conformance substitution | `conformances.tex` 的 Conformance Substitution 一节 |
| $\mathsf{Req}(G)\otimes\mathsf{Sub}(G,H)\rightarrow\mathsf{Req}(H)$ | requirement substitution | `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Generic Arguments 一节 |

### Substitution maps

一张 substitution map $\Sigma\in\mathsf{Sub}(G,H)$ 含有两个数组：一组取自 $\mathsf{Type}(H)$ 的 interface type（replacement type），以及一组取自 $\mathsf{Conf}(H)$ 的 conformance（root conformance）。

对 $G$ 的每个 generic parameter $\tau_{d,i}$ 和每个 root abstract conformance $[\texttt{T: P}]$：

$$\tau_{d,i} \otimes \Sigma = \tau_{d,i} \otimes \{\ldots,\,\tau_{d,i} \mapsto \texttt{X},\,\ldots\} = \texttt{X}$$

$$[\texttt{T: P}] \otimes \Sigma = [\texttt{T: P}] \otimes \{\ldots,\,[\texttt{T: P}] \mapsto [\texttt{X: P}],\,\ldots\} = [\texttt{X: P}]$$

（第二条见 `conformances.tex` 的 Conformance Substitution 一节。）

Substitution map composition：

$$\texttt{X} \otimes (\Sigma_1 \otimes \Sigma_2) = (\texttt{X} \otimes \Sigma_1) \otimes \Sigma_2$$

$$\Sigma_1 \otimes (\Sigma_2 \otimes \Sigma_3) = (\Sigma_1 \otimes \Sigma_2) \otimes \Sigma_3$$

Identity substitution map：

$$\texttt{X} \otimes 1_G = \texttt{X} \qquad (\forall\,\texttt{X}\in\mathsf{Type}(G))$$

$$[\texttt{X: P}] \otimes 1_G = [\texttt{X: P}] \qquad (\forall\,[\texttt{X: P}]\in\mathsf{Conf}(G))$$

$$1_G \otimes \Sigma = \Sigma \otimes 1_H = \Sigma \qquad (\forall\,\Sigma\in\mathsf{Sub}(G,H))$$

每个 generic nominal type $\texttt{X}$ 都可以写成 $\texttt{X}=\texttt{X}_d\otimes\Sigma$ 的形式，其中 $d$ 是某个 nominal type declaration、$\Sigma$ 是某张 substitution map（见 `substitution-maps.tex` 的 Nominal Types 一节）。

> 译注：$\texttt{X}=\texttt{X}_d\otimes\Sigma$ 这条分解正是本库从二进制里读到的形态：$d$ 是 `__swift5_types` 里的 type context descriptor，$\Sigma$ 是 mangled name 里跟在后面的那串 generic argument。本库在不加载进程、不调用 metadata accessor 的前提下，把 $\otimes$ 这一步自己做了一遍——按 `(depth, index)` 把 field record 里的 generic parameter 重写成实参，见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)；由此算出的字段偏移见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

### Conformances

一个 normal conformance $[\texttt{X}_d\texttt{: P}]$ 声明了一系列 type witness 和 associated conformance。若 $\texttt{X}=\texttt{X}_d\otimes\Sigma$，则 $[\texttt{X: P}]=[\texttt{X}_d\texttt{: P}] \otimes \Sigma$ 是由 normal conformance $[\texttt{X}_d\texttt{: P}]$ 与 substitution map $\Sigma$ 构成的 specialized conformance。

| 集合 | 含义 |
|---|---|
| $\mathsf{Proto}$ | 全部 protocol declaration |
| $\mathsf{AssocType}_{\texttt{P}}$ | $\texttt{P}\in\mathsf{Proto}$ 的全部 associated type declaration |
| $\mathsf{AssocConf}_{\texttt{P}}$ | $\texttt{P}\in\mathsf{Proto}$ 所声明的全部 associated conformance requirement |
| $\mathsf{Conf}_{\texttt{P}}(G)$ | 对固定的 $\texttt{P}\in\mathsf{Proto}$，$\mathsf{Conf}(G)$ 中所有 $[\texttt{X: P}]$ 构成的集合 |

| 记号 | 含义 |
|---|---|
| $\langle\texttt{P}]$ | 名为 $\texttt{P}$ 的 protocol declaration |
| $\langle\texttt{P}\vert\texttt{A}$ | protocol $\texttt{P}$ 中名为 $\texttt{A}$ 的 associated type declaration |
| $\langle\texttt{Self.U: Q}]$ | associated conformance requirement |
| $\texttt{T.[P]A}$ | base type 为 $\texttt{T}$、associated type 为 $\texttt{P}$ 的 $\texttt{A}$ 的 dependent member type |
| $\Sigma_{[\texttt{X: P}]}$ | protocol substitution map $\{\tau_{0,0} \mapsto \texttt{X};\,[\tau_{0,0}\texttt{: P}] \mapsto [\texttt{X: P}]\}$ |

| 运算 | 名称 | 出处 |
|---|---|---|
| $\mathsf{Proto}\otimes\mathsf{Type}(G)\rightarrow\mathsf{Conf}(G)$ | global conformance lookup | `conformances.tex` 的 Conformance Lookup 一节 |
| $\mathsf{AssocType}_{\texttt{P}}\otimes\mathsf{Conf}_{\texttt{P}}(G)\rightarrow\mathsf{Type}(G)$ | type witness projection | `conformances.tex` 的 Type Witnesses 一节 |
| $\mathsf{AssocConf}_{\texttt{P}}\otimes\mathsf{Conf}_{\texttt{P}}(G)\rightarrow\mathsf{Conf}(G)$ | associated conformance projection | `conformances.tex` 的 Associated Conformances 一节 |

Global conformance lookup：

$$\langle\texttt{P}] \otimes \texttt{X}_d := [\texttt{X}_d\texttt{: P}] \qquad (\text{normal})$$

$$\langle\texttt{P}] \otimes (\texttt{X}_d \otimes \Sigma) := [\texttt{X}_d\texttt{: P}] \otimes \Sigma \qquad (\text{specialized})$$

$$\langle\texttt{P}] \otimes \texttt{T} := [\texttt{T: P}] \qquad (\text{abstract})$$

$$(\langle\texttt{P}] \otimes \texttt{T}) \otimes \Sigma = \langle\texttt{P}] \otimes (\texttt{T} \otimes \Sigma)$$

（最后一条见 `conformances.tex` 的 Abstract Conformances 一节。）

Specialized conformance substitution：

$$([\texttt{X}_d\texttt{: P}] \otimes \Sigma_1) \otimes \Sigma_2 := [\texttt{X}_d\texttt{: P}] \otimes (\Sigma_1 \otimes \Sigma_2)$$

> 译注：normal / specialized / abstract 这三分正是本库判定一个 witness 归属时要还原的三分：`__swift5_proto` 里的 conformance descriptor 对应 normal conformance，带 generic argument 的引用对应 specialized conformance，而 type parameter 上的那种只在 witness table 里留下一个槽位、没有具体实现，对应 abstract conformance。本库把 extension 容器按 (target, protocol, where 指纹, retroactive) 逐个 conformance 归属的做法见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)，protocol 侧槽位的投影见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

对每个 $\langle\texttt{P}\vert\texttt{A} \in \mathsf{AssocType}_{\texttt{P}}$：

$$\langle\texttt{P}\vert\texttt{A}\otimes [\texttt{X}_d\texttt{: P}] := \textit{declared in source} \qquad (\text{normal})$$

$$\langle\texttt{P}\vert\texttt{A}\otimes ([\texttt{X}_d\texttt{: P}]\otimes \Sigma) := (\langle\texttt{P}\vert\texttt{A}\otimes [\texttt{X}_d\texttt{: P}]) \otimes \Sigma \qquad (\text{specialized})$$

$$\langle\texttt{P}\vert\texttt{A} \otimes [\texttt{T: P}] := \texttt{T.[P]A} \qquad (\text{abstract})$$

（最后一条见 `conformances.tex` 的 Abstract Conformances 一节。）

对每个 $\langle\texttt{Self.U: Q}] \in \mathsf{AssocConf}_{\texttt{P}}$：

$$\langle\texttt{Self.U: Q}]\otimes [\texttt{X}_d\texttt{: P}] := \langle\texttt{Q}] \otimes \texttt{Self.U} \otimes \Sigma_{[\texttt{X}_d\texttt{: P}]} \qquad (\text{normal})$$

$$\langle\texttt{Self.U: Q}]\otimes ([\texttt{X}_d\texttt{: P}] \otimes \Sigma) := (\langle\texttt{Self.U: Q}] \otimes [\texttt{X}_d\texttt{: P}]) \otimes \Sigma \qquad (\text{specialized})$$

$$\langle\texttt{Self.U: Q}] \otimes [\texttt{T: P}] := [\texttt{T.U: Q}] \qquad (\text{abstract})$$

Dependent member type substitution：

$$\texttt{T.[P]A} \otimes \Sigma := \langle\texttt{P}\vert\texttt{A} \otimes ([\texttt{T: P}] \otimes \Sigma)$$

（见 `conformances.tex` 的 Abstract Conformances 一节。）

用一条 conformance path 做 local conformance lookup：

$$[\texttt{T: P}] \otimes \Sigma := \langle\texttt{Self.U}_n\texttt{: P}_n] \otimes \cdots \otimes \langle\texttt{Self.U}_1\texttt{: P}_1] \otimes [\texttt{T}_0\texttt{: P}_0] \otimes \Sigma$$

（见 `conformance-paths.tex`。）

---

> 译自 `docs/Generics/chapters/type-substitution-summary.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
