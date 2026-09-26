# The Property Map（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/property-map.tex`（《Compiling Swift Generics》一书的「The Property Map」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：**先说清楚一件事：本章在原书里尚未定稿。** 原书 README 把它列为「not yet written」，全章七个小节里有六个要么只剩一个空标题，要么整段包在 `\ifWIP` 条件块里——而 `generics.tex` 把 `\ifWIP` 定义成 `\iffalse`，所以这些内容在官方 PDF 里根本不输出，它们是作者的草稿。本译文按项目规约把草稿一并译出，并在每个草稿块开头标注出来；**读的时候不要把它当作与其它章节同等权威的文本**：正文里还留着作者自己的 TODO，以及若干处对不上的规则编号与表格编号（都在下文以译注标出）。
>
> 就内容而言，本章讲的是 requirement machine 怎样从重写系统里回答比 `requiresProtocol()` 更一般的 generic signature query（`getRequiredProtocols()`、`getLayoutConstraint()`、`getSuperclassBound()`、`getConcreteType()`）。办法是在 completion 跑完之后一次性构造一张 multi-map，把 term 映到它满足的属性集合上；查询时只需找最长的那个后缀。本库（MachOSwiftSection）**不实现**重写系统，也不实现 property map；它消费的是这套机制的**产物**——编译器已经写进二进制里的 reduced type 与 canonical 顺序。少数几处真有对应关系的地方以「译注」标出。
>
> **术语**：书中定义的术语一律保留英文（property map、property-like symbol、joinable、canonical form、reduced type、canonical anchor、type term、rewrite rule、critical pair、overlap、completion、Knuth-Bendix、protocol symbol、associated type symbol、layout symbol、superclass symbol、concrete type symbol、substitution term、type lowering map、type lifting map、generic signature query、layout constraint、join、conflicting requirements……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Generic Signature Queries 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（本章属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`）。**注意本章开头重定义了五个与全书同名的宏**（源文件里还挂着一句 "Remove these" 的注释），下表按本章的**局部**定义展开，不按全书定义：
>
> | 记法 | 含义 |
> |---|---|
> | $T$、$U$、$V$、$Z$ | term，多数时候是 type term |
> | $T\rightarrow Z$ | $T$ 经零步或多步重写归约到 $Z$ |
> | $x\Rightarrow y$ | 一条 rewrite rule，即一步重写 |
> | $T{\downarrow}$ | $T$ 的 canonical form（归约到底的结果） |
> | $T\downarrow U$ | $T$ 与 $U$ **joinable**：存在 $Z$ 使 $T\rightarrow Z$ 且 $U\rightarrow Z$ |
> | $\Pi$ | property-like symbol，即 protocol / layout / superclass / concrete type 这四类符号的统称 |
> | $[\texttt{P}]$ | protocol symbol（全书宏 `\protosym{P}`，简写 `\pP`、`\pQ`、`\pR`） |
> | $[\texttt{P}\vert\texttt{A}]$ | protocol $\texttt{P}$ 的 associated type $\mathrm{A}$ 所对应的 associated type symbol |
> | $[\texttt{P}_1\cap\ldots\cap\texttt{P}_n\colon\mathrm{A}]$ | merged associated type symbol（多个 protocol 合并而来的那种） |
> | $[\mathsf{layout}\colon\texttt{AnyObject}]$ | layout symbol |
> | $[\mathsf{superclass}\colon \mathrm{C}\langle\sigma_0\rangle;\,\sigma_0:=V]$ | superclass symbol；分号后面列的是它内部的 substitution term |
> | $[\mathsf{concrete}\colon \mathrm{C}\langle\sigma_0\rangle;\,\sigma_0:=V]$ | concrete type symbol |
> | $\sigma_i$ | symbol 内部第 $i$ 个 substitution term |
> | $\tau_{d,i}$ | depth $d$、index $i$ 的 generic parameter symbol（**本章局部宏** `\genericsym{d}{i}`；原书排的是直立的 `\uptau`，KaTeX 不认，本文一律写 `\tau`） |
> | $\mathrm{A}$、$\mathrm{Cache}$、$\mathrm{Array}$ | 源码里的名字：associated type 名、类型名（**本章局部宏** `\namesym{}` 展开为 `\mathrm{}`，全书定义不是这个） |
> | $\texttt{P}$、$\texttt{P4}$ | protocol 名（**本章局部宏** `\proto{}` 展开为 `\texttt{}`） |
> | $\mathsf{Self}$、$\mathsf{A}$ | 源码层面的 generic parameter 写法（**本章局部宏** `\genericparam{}` 展开为 `\mathsf{}`） |
> | $\langle \tau_{0,0}\;\textit{where}\;\tau_{0,0}\colon\texttt{P}\rangle$ | generic signature（**本章局部宏** `\gensig{}{}`，展开为 $\langle\,\cdot\;\textit{where}\;\cdot\,\rangle$） |
> | $\Lambda\colon\mathrm{Type}\rightarrow\mathrm{Term}$ | type lowering map；$\Lambda_{\texttt{P}}$ 是 protocol $\texttt{P}$ 用的那一份 |
> | $\Lambda^{-1}\colon\mathrm{Term}\rightarrow\mathrm{Type}$ | type lifting map，lowering map 的逆 |
> | $P[V]$ | property map $P$ 中 key $V$ 所对应的符号集合 |
> | $A\wedge B$ | 两个 layout constraint 的 **join**：同时满足二者的最一般者。$A\leq B$ 定义为 $A=A\wedge B$ |
> | $T\vert_{\pi_i}$ | 类型 $T$ 在位置 $\pi_i$ 处的子项 |
> | $\mathbb{N}$ | 自然数集 |

---

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。本块一直延续到 Substitution Simplification 一节之前。

到目前为止，你看到的是 `requiresProtocol()` 这个 generic signature query 怎么解：若 $T$ 是一个 type term，则 $T$ 所代表的那个 type parameter conform 到 protocol $\texttt{P}$，当且仅当 $T$ 与 $T.[\texttt{P}]$ 归约到同一个 canonical form $T{\downarrow}$。下一步是解更一般的 query，比如 `getRequiredProtocols()`。这里要找的是**所有**满足「$T.[\texttt{P}]$ 与 $T$ 都归约到某个 $T{\downarrow}$」的 protocol symbol $[\texttt{P}]$。

一种可能的实现是穷举枚举。一个 rewrite system 的规则里只会提到有限多个 protocol symbol，所以把 type term 依次接上每一个已知的 protocol symbol、再试着归约，就足够了。这至少说明这个 query 是可实现的，但方案并不令人满意。下面要讲的办法效率更高，而且对涉及 layout、superclass 和 concrete type requirement 的 generic signature query 一样管用，适用面更广。

**定义.** 若 $T$ 与 $U$ 是 term，且存在某个 term $Z$ 使得 $T\rightarrow Z$ 且 $U\rightarrow Z$，则称 $T$ 与 $U$ 是 **joinable** 的，记作 $T\downarrow U$。

**定义.** 若 $\Pi$ 是一个 property-like symbol、$T$ 是一个 term，且 $T.\Pi\downarrow T$，则称 $T$ **satisfies** $\Pi$。$T$ 所满足的属性集合，定义为所有使 $T.\Pi\downarrow T$ 成立的 symbol $\Pi$ 构成的集合。

**定理.** 设 $T$ 是一个 type term，canonical form 为 $T{\downarrow}$；设 $\Pi$ 是一个 property-like symbol，且 $T$ satisfies $\Pi$。那么 $T{\downarrow}.\Pi\rightarrow T{\downarrow}$。进一步，这个归约序列只由单独一条规则 $V.\Pi\Rightarrow V$ 构成，其中 $V$ 是 $T{\downarrow}$ 的某个非空后缀。

**证明.** 由于 $T$ 可以归约到 $T{\downarrow}$，把同一条归约序列作用到 $T.\Pi$ 上就会得到 $T{\downarrow}.\Pi$。这说明 $T.\Pi$ 既能归约到 $T{\downarrow}$（由假设），也能归约到 $T{\downarrow}.\Pi$。由 confluence，$T{\downarrow}.\Pi$ 必定能归约到 $T{\downarrow}$。

由于 $T{\downarrow}$ 是 canonical 的，$T{\downarrow}.\Pi$ 除非借助形如 $V.\Pi\Rightarrow V'$ 的 rewrite rule，否则无法再往下归约，其中 $T{\downarrow}=UV$，而 $U$、$V$、$V'$ 都是 term。剩下要证的是 $V=V'$。（TODO：这一步还需要一条关于 conformance-valid 规则的额外假设。）

由上面这条定理，一个 type term 满足哪些属性，可以这样发现：考察 $T{\downarrow}$ 的所有非空后缀，收集形如 $V.\Pi\rightarrow V$ 的 rewrite rule，其中 $\Pi$ 是某个 property-like symbol。

**代码清单：property map 的引例**

```swift
protocol P1 {}

protocol P2 {}

protocol P3 {
  associatedtype T : P1
  associatedtype U : P2
}

protocol P4 {
  associatedtype A : P3 where A.T == A.U
  associatedtype B : P3
}
```

**例.** 考虑上面这段代码清单里的 protocol 定义。下面几个例子都会用到它们，所以先看看构造出来的 rewrite system 长什么样。Protocol $\texttt{P1}$ 和 $\texttt{P2}$ 既没有定义 associated type 也没有 requirement，因此不贡献任何 initial rewrite rule。Protocol $\texttt{P3}$ 有两个 associated type $\mathrm{T}$ 和 $\mathrm{U}$，分别 conform 到 $\texttt{P1}$ 和 $\texttt{P2}$，于是一对规则负责引入这两个 associated type，另一对规则负责施加 conformance requirement：

$$\begin{aligned}
[\texttt{P3}].\mathrm{T} &\Rightarrow [\texttt{P3}\vert\texttt{T}] && \qquad (1)\\
[\texttt{P3}].\mathrm{U} &\Rightarrow [\texttt{P3}\vert\texttt{U}] && \qquad (2)\\
[\texttt{P3}\vert\texttt{T}].[\texttt{P1}] &\Rightarrow [\texttt{P3}\vert\texttt{T}] && \qquad (3)\\
[\texttt{P3}\vert\texttt{U}].[\texttt{P2}] &\Rightarrow [\texttt{P3}\vert\texttt{U}] && \qquad (4)
\end{aligned}$$

Protocol $\texttt{P4}$ 再添五条规则。一对规则引入 associated type $\mathrm{A}$ 和 $\mathrm{B}$；接着，这两个 associated type 都 conform 到 $\texttt{P3}$，而且 $\mathrm{A}$ 在它的两个嵌套类型 $\mathrm{T}$ 与 $\mathrm{U}$ 之间有一条 same-type requirement：

$$\begin{aligned}
[\texttt{P4}].\mathrm{A} &\Rightarrow [\texttt{P4}\vert\texttt{A}] && \qquad (5)\\
[\texttt{P4}].\mathrm{B} &\Rightarrow [\texttt{P4}\vert\texttt{B}] && \qquad (6)\\
[\texttt{P4}\vert\texttt{A}].[\texttt{P3}] &\Rightarrow [\texttt{P4}\vert\texttt{A}] && \qquad (7)\\
[\texttt{P4}\vert\texttt{B}].[\texttt{P3}] &\Rightarrow [\texttt{P4}\vert\texttt{B}] && \qquad (8)\\
[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{U}] &\Rightarrow [\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}] && \qquad (9)
\end{aligned}$$

把上面这个 initial rewrite system 交给 Knuth-Bendix 算法，它会加进少量新规则来消解 critical pair。首先，$\texttt{P4}$ 的 conformance requirement 与 $\texttt{P3}$ 的 associated type introduction rule 之间有四处 overlap：

$$\begin{aligned}
[\texttt{P4}\vert\texttt{A}].\mathrm{T} &\Rightarrow [\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}] && \qquad (10)\\
[\texttt{P4}\vert\texttt{A}].\mathrm{U} &\Rightarrow [\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}] && \qquad (11)\\
[\texttt{P4}\vert\texttt{B}].\mathrm{T} &\Rightarrow [\texttt{P4}\vert\texttt{B}].[\texttt{P3}\vert\texttt{T}] && \qquad (12)\\
[\texttt{P4}\vert\texttt{B}].\mathrm{U} &\Rightarrow [\texttt{P4}\vert\texttt{B}].[\texttt{P3}\vert\texttt{U}] && \qquad (13)
\end{aligned}$$

最后，Rule 9 与 Rule 4 之间还有一处 overlap：

$$\begin{aligned}
[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}].[\texttt{P2}] &\Rightarrow [\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}] && \qquad (14)
\end{aligned}$$

现在考虑 $\texttt{P4}$ 的 generic signature 里的 type parameter $\mathsf{Self}.\mathrm{A}.\mathrm{U}$。经由 $\texttt{P4}$ 中那条 same-type requirement，它与 $\mathsf{Self}.\mathrm{A}.\mathrm{T}$ 等价。$\texttt{P3}$ 的 associated type $\mathrm{T}$ conform 到 $\texttt{P1}$，$\mathrm{U}$ conform 到 $\texttt{P2}$。这意味着 $\mathsf{Self}.\mathrm{A}.\mathrm{U}$ **同时** conform 到 $\texttt{P1}$ 和 $\texttt{P2}$。

来看这个事实怎么从 rewrite system 里推出来。把 $\Lambda_{\texttt{P4}}$ 作用到 $\mathsf{Self}.\mathrm{A}.\mathrm{U}$ 上，得到 type term $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{U}]$。这个 type term 用 Rule 9 一步就能归约到 canonical term $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}]$。按上面那条定理的结论，只需要看形如 $V.\Pi\Rightarrow V$ 的规则即可，其中 $V$ 是 $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}]$ 的某个后缀。这样的规则有两条：

1. Rule 3，它说 $[\texttt{P3}\vert\texttt{T}]$ conform 到 $\texttt{P1}$。
2. Rule 14，它说 $[\texttt{P4}\vert\texttt{A}].[\texttt{P4}\vert\texttt{T}]$ conform 到 $\texttt{P2}$。

> 译注：原书第 2 条写的是 $[\texttt{P4}\vert\texttt{A}].[\texttt{P4}\vert\texttt{T}]$，但 $\texttt{P4}$ 根本没有名为 $\mathrm{T}$ 的 associated type，而 Rule 14 的左端是 $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}].[\texttt{P2}]$，疑为笔误，应作 $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}]$。

这说明 type parameter $\mathsf{Self}.\mathrm{A}.\mathrm{U}$ 所满足的属性集合恰好是 $\{[\texttt{P1}],[\texttt{P2}]\}$。

上面这个例子也许会让人以为，查一个 type parameter 满足哪些属性非得遍历 rewrite rule 列表不可；但实际上，只要在 completion 过程结束之后，一次性把所有 $(V, \Pi)$ 对构造成一张 multi-map 就够了。

正如例子里看到的，同一个 type term 可以经由不同的后缀满足多个属性。正因如此，构造算法在为一个以 $V$ 为后缀的 term $UV$ 建条目时，会显式地把与 $V$ 关联的那些 symbol「继承」过来。这样一来，查找算法只要找出现在 multi-map 里的**最长**后缀，就能拿到该 term 满足的全部属性。

multi-map 的构造与查找可以形式化成一对算法。

**算法（Property map construction）.** 本算法在 completion 过程构造出一个右端已简化的 confluent rewrite system 之后运行。输出是一张把 term 映到符号集合的 multi-map。

1. 把 $S$ 初始化为所有形如 $V.\Pi\Rightarrow V$ 的 rewrite rule 的列表。
2. 把 $P$ 初始化为一张把 term 映到符号集合的 multi-map，初始为空。
3. 按 rewrite rule 左端的长度对 $S$ 升序排序。左端长度相同的规则之间，相对顺序无所谓。
4. 对每一条规则 $V.\Pi\Rightarrow V\in S$：
   1. 若 $V\notin P$，先按下面的办法初始化 $P[V]$。

      若 $P$ 里已经有某个 $V''$ 使得 $V=V'V''$，就把 $P[V'']$ 里的符号复制到 $P[V]$。复制 superclass 或 concrete type symbol 时，符号内部的 substitution term 必须做调整：给每个 term 前置 $V'$。

      正是在这一步，算法依赖了第 2 步里对规则所做的排序。因为 $\vert V''\vert<\vert V\vert$，所以等到算法遇到涉及 $V$ 的规则时，所有形如 $V''.\Pi\Rightarrow V''$ 的规则都已经处理过了。

      事实上，由于这张 map 是自底向上构造的，只检查 $V$ 的**最长**的那个满足 $V''\in P$ 的后缀 $V''$ 就够了。
   2. 把 $\Pi$ 插入 $P[V]$。

> 译注：原书这里说「第 2 步里对规则所做的排序」，但排序是第 3 步做的（第 2 步是初始化 $P$），疑为笔误，应读作第 3 步。

property map 一旦建好，查找就非常简单。

**算法（Property map lookup）.** 给定一个 type parameter $T$ 和一张 property map $P$，本算法输出 $T$ 所满足的属性集合。

1. 首先把 $T$ lower 成 type term $\Lambda(T)$，并把这个 term 归约到 canonical form $\Lambda(T){\downarrow}$。
2. 若 $\Lambda(T){\downarrow}$ 的任何后缀都没出现在 $P$ 里，返回空集。
3. 否则，令 $\Lambda(T){\downarrow}:=UV$，其中 $V$ 是 $\Lambda(T){\downarrow}$ 中出现在 $P$ 里的最长后缀。
4. 令 $S:=P[V]$，即 $P$ 中与 $V$ 关联的属性符号集合。
5. 对每一个 superclass 或 concrete type symbol $\Pi\in S$，给该符号内部的每个 substitution term 前置 $U$。

> 译注：原书第 4 步把这个集合写作 $V[P]$（后文 `getSuperclassBound()` 处又写作 $T[V]$），与构造算法里一贯使用的 $P[V]$ 记法不一致，疑为笔误；本译文统一按 $P[V]$ 理解。

注意在这两个算法里，superclass 和 concrete type symbol 都要靠给每个 substitution 前置一个前缀来做调整。

**例.** 回忆上一个例子，那里从「property map 的引例」这段代码清单构造出了一个 rewrite system。完整的 rewrite system 里有五条形如 $V.\Pi\Rightarrow V$ 的 rewrite rule：

1. Rule 3 与 Rule 4，它们说 $\texttt{P3}$ 的 associated type $\mathrm{T}$ 和 $\mathrm{U}$ 分别 conform 到 $\texttt{P1}$ 和 $\texttt{P2}$。
2. Rule 7 与 Rule 8，它们说 $\texttt{P4}$ 的 associated type $\mathrm{A}$ 和 $\mathrm{B}$ 都 conform 到 $\texttt{P3}$。
3. Rule 13，它说 $\texttt{P4}$ 的嵌套类型 $\mathsf{A}.\mathsf{T}$ 也 conform 到 $\texttt{P2}$。

> 译注：两处笔误。其一，原书这里指向的是「Protocol with concrete type requirements」那段代码清单（即下一个例子用的 `Cache` / $\texttt{P}$ / $\texttt{Q}$ / $\texttt{R}$ 那份），但上一个例子用的是「property map 的引例」那份，应以后者为准。其二，第 3 条说的 Rule 13 实为 Rule 14——Rule 13 是 $[\texttt{P4}\vert\texttt{B}].\mathrm{U}\Rightarrow[\texttt{P4}\vert\texttt{B}].[\texttt{P3}\vert\texttt{U}]$，并不是 $V.\Pi\Rightarrow V$ 的形状；下面那张表里的 $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}]$ 条目也只能由 Rule 14 产生。

由 Property map construction 算法从上述规则构造出的 property map 如下表所示。

**表：从上面这个例子构造出的 property map**

| Key | Values |
|---|---|
| $[\texttt{P3}\vert\texttt{T}]$ | $[\texttt{P1}]$ |
| $[\texttt{P3}\vert\texttt{U}]$ | $[\texttt{P2}]$ |
| $[\texttt{P4}\vert\texttt{A}]$ | $[\texttt{P3}]$ |
| $[\texttt{P4}\vert\texttt{B}]$ | $[\texttt{P3}]$ |
| $[\texttt{P4}\vert\texttt{A}].[\texttt{P3}\vert\texttt{T}]$ | $[\texttt{P1}]$、$[\texttt{P2}]$ |

**例.** 第二个例子探讨 layout、superclass 和 concrete type requirement。考虑下面这段代码清单里的 protocol 定义，再配上这个 generic signature：

$$\langle \tau_{0,0}\;\textit{where}\;\tau_{0,0}\colon\texttt{P},\ \tau_{0,0}.\mathrm{B}\colon\texttt{Q}\rangle$$

**代码清单：带 concrete type requirement 的 protocol**

```swift
class Cache<Key> {}

protocol R {}
protocol Q : R {}

protocol P {
  associatedtype A : AnyObject
  associatedtype B : Cache<A>
  associatedtype C where C == Array<A>
}
```

$\texttt{R}$、$\texttt{Q}$、$\texttt{P}$ 这三个 protocol 连同上面的 generic signature，生成下列 initial rewrite rule：

$$\begin{aligned}
[\texttt{Q}].[\texttt{R}] &\Rightarrow [\texttt{Q}] && \qquad (1)\\
[\texttt{P}].\mathrm{A} &\Rightarrow [\texttt{P}\vert\texttt{A}] && \qquad (2)\\
[\texttt{P}].\mathrm{B} &\Rightarrow [\texttt{P}\vert\texttt{B}] && \qquad (3)\\
[\texttt{P}].\mathrm{C} &\Rightarrow [\texttt{P}\vert\texttt{C}] && \qquad (4)\\
[\texttt{P}\vert\texttt{A}].[\mathsf{layout}\colon\texttt{AnyObject}] &\Rightarrow [\texttt{P}\vert\texttt{A}] && \qquad (5)\\
[\texttt{P}\vert\texttt{B}].[\mathsf{superclass}\colon \mathrm{Cache}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]] &\Rightarrow [\texttt{P}\vert\texttt{B}] && \qquad (6)\\
[\texttt{P}\vert\texttt{B}].[\mathsf{layout}\colon\texttt{\_NativeClass}] &\Rightarrow [\texttt{P}\vert\texttt{B}] && \qquad (7)\\
[\texttt{P}\vert\texttt{C}].[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]] &\Rightarrow [\texttt{P}\vert\texttt{C}] && \qquad (8)\\
\tau_{0,0}.[\texttt{P}] &\Rightarrow \tau_{0,0} && \qquad (9)\\
\tau_{0,0}.[\texttt{P}\vert\texttt{B}].[\texttt{Q}] &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{B}] && \qquad (10)
\end{aligned}$$

Knuth-Bendix 算法再添下列规则，让 rewrite system 变得 confluent：

$$\begin{aligned}
\tau_{0,0}.\mathrm{A} &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{A}] && \qquad (11)\\
\tau_{0,0}.\mathrm{B} &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{B}] && \qquad (12)\\
\tau_{0,0}.\mathrm{C} &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{C}] && \qquad (13)\\
\tau_{0,0}.[\texttt{P}\vert\texttt{B}].[\texttt{R}] &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{B}] && \qquad (14)
\end{aligned}$$

下列 rewrite rule 具有 $V.\Pi\Rightarrow V$ 的形状，其中 $\Pi$ 是一个 property-like symbol：

1. Rule 1，它说 protocol $\texttt{Q}$ 继承自 $\texttt{R}$。
2. Rule 5，它说 protocol $\texttt{P}$ 里的 associated type $\mathrm{A}$ 在表示上是一个 $\mathrm{AnyObject}$。
3. Rule 6，它说 protocol $\texttt{P}$ 里的 associated type $\mathrm{B}$ 必须继承自 $\mathrm{Cache}\langle\mathrm{A}\rangle$。
4. Rule 7，它说 protocol $\texttt{P}$ 里的 associated type $\mathrm{B}$ 同时还表示为一个 $\mathrm{\_NativeClass}$。
5. Rule 8，它说 protocol $\texttt{P}$ 里的 associated type $\mathrm{C}$ 被钉死在 concrete type $\mathrm{Array}\langle\mathrm{A}\rangle$ 上。
6. Rule 9，它说 generic parameter $\tau_{0,0}$ conform 到 $\texttt{P}$。
7. Rule 10，它说 type parameter $\tau_{0,0}.\mathrm{B}$ conform 到 $\texttt{Q}$。
8. Rule 14，它说 type parameter $\tau_{0,0}.\mathrm{B}$ conform 到 $\texttt{R}$。

   最后这条规则是 completion 过程加进去的，用来消解 Rule 10 与 Rule 1 在 term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}].[\texttt{Q}].[\texttt{R}]$ 上的 overlap。

构造 property map 时，按左端长度给规则排序这一步，保证了 Rule 6 和 Rule 7 会先于 Rule 10 和 Rule 14 被处理。这很关键：Rule 6 和 Rule 7 的 subject type（$[\texttt{P}\vert\texttt{B}]$）是 Rule 10 和 Rule 14 的 subject type（$\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$）的后缀，这意味着 Rule 10 和 Rule 14 对应的 property map 条目会从 Rule 6 和 Rule 7 那里继承 superclass 与 layout requirement。而且，superclass requirement 里的 substitution $\sigma_0:=[\texttt{P}\vert\texttt{A}]$ 还要做调整：给它前置前缀 $\tau_{0,0}$。

由 Property map construction 算法从上述规则构造出的 property map 如下表所示。下一节你会看到这张 property map 怎么用来解 generic signature query。

**表：从上面这个例子构造出的 property map**

| Key | Values |
|---|---|
| $[\texttt{Q}]$ | $[\texttt{R}]$ |
| $[\texttt{P}\vert\texttt{A}]$ | $[\mathsf{layout}\colon\texttt{AnyObject}]$ |
| $[\texttt{P}\vert\texttt{B}]$ | $[\mathsf{superclass}\colon \mathrm{Cache}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]]$、$[\mathsf{layout}\colon\texttt{\_NativeClass}]$ |
| $[\texttt{P}\vert\texttt{C}]$ | $[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]]$ |
| $\tau_{0,0}$ | $[\texttt{P}]$ |
| $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ | $[\texttt{Q}]$、$[\texttt{R}]$、$[\mathsf{superclass}\colon \mathrm{Cache}\langle\sigma_0\rangle;\,\sigma_0:=\tau_{0,0}.[\texttt{P}\vert\texttt{A}]]$、$[\mathsf{layout}\colon\texttt{\_NativeClass}]$ |

> 译注：上面这张表正是「一个 type parameter 的 signature 到底钉死了它哪些事」的完整答案：conform 到哪些 protocol、layout 是什么、superclass 是谁、有没有被钉在某个 concrete type 上。本库不做重写系统，但在**没有任何泛型实参**的前提下要算字段偏移时，必须自己从二进制里把同一批事实挖出来——`ClassBoundGenericParameterAnalysis` 直接扫 generic context 的 requirement 列表，把 `layout(.class)`、`baseClass`、以及 RHS 为具体类型的 `sameType` 这三类 requirement 挑出来，得到「这个 generic parameter 不管代入什么都占一个指针宽」或者「它其实被钉死成 `Date` 了」这样的结论，再据此给字段定位。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

## Substitution Simplification

**算法（Simplify substitution terms）.**

> 译注：原书此处的 algorithm 环境是**空的**——只有标题，没有任何步骤；本节除此之外也没有别的内容。这是作者留的坑。

## Property Unification

> 译注：原书本节正文尚未撰写。源文件此处只留了两条索引条目，指向编译器调试标志 `-debug-requirement-machine=property-map` 与 `-debug-requirement-machine=conflicting-rules`。

## Concrete Type Unification

> 译注：同上，原书本节正文尚未撰写，源文件只留了一条指向 `-debug-requirement-machine=concrete-unification` 的索引条目。

## Concrete Conformances

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。本块是一份纯 TODO 清单，反映的是作者的写作计划。

TODO：

- Concrete conformance rule，property-like
- 引入它的那条 virtual rule
- 想法：它应该消掉 conformance rule，但不该消掉 concrete type rule
- 它实际上不出现在 signature 里，所以不应该影响 minimization
- Conditional requirement inference：只在 generic signature 里做，不在 protocol 里做，因为 completion 期间我们没法合并 connected component。对 generic signature 而言，一般情形下这真的需要引入新的 component

> 译注：原书此处另有一条索引条目，指向调试标志 `-debug-requirement-machine=concretize-nested-types`。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。本块同样是两份 TODO 清单。

TODO：

- Concrete type witness
- Abstract type witness
- Virtual rule
- 一个算法：通过代入另一个 symbol 的 pattern type，构造出「相对的」concrete type symbol

TODO：

- Free conformance
- 一个 protocol 能不能有 free conformance
- 能不能通过改动 protocol 把一个 conformance 变成 free 的
- Conformance evaluation graph
- 从一个 conformance 里找出 same-type requirement 的启发式办法；就是那个 parent type 的路子
- Opaque archetype 带来的麻烦
- 开放问题：能不能不求值就把一个 conformance 更直接地编码出来；`G<G<G<T>>>` 这个例子

> 译注：原书此处另有一条索引条目，指向编译器标志 `-enable-requirement-machine-opaque-archetypes`。

## Generic Signature Queries

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。本块一直延续到 Reduced Types 一节之前。

（`getReducedType()` 那个 hack）其它后果在 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 的 Concrete Contraction 一节里讨论。

回忆 `generic-signatures.tex` 的 Generic Signature Queries 一节，那里把 generic signature query 分成了 predicate、property 和 canonical type query 三类。其中的 predicate 可以用 property map 直截了当地实现。每个 predicate 都接受一个 subject type parameter $T$。

generic signature query 总是相对某个 generic signature 提出的，而不是相对某个 protocol 的 requirement signature，所以 type parameter $T$ 要用 generic signature 的那个 type lowering map $\Lambda\colon\mathrm{Type}\rightarrow\mathrm{Term}$（见 `symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 的 Build term for explicit requirement 算法）来 lower，而不是用某个 protocol $\texttt{P}$ 的 protocol type lowering map $\Lambda_{\texttt{P}}\colon\mathrm{Type}\rightarrow\mathrm{Term}$（见同一章的 Build term for associated requirement 算法）。

第一步是用 Property map lookup 算法查出 $T$ 满足的属性集合。之后，各个 predicate 可以这样判定：

- **`requiresProtocol()`**：若 $T$ 的某个后缀在 property map 里的条目存了 $[\texttt{P}]$，则 type parameter $T$ conform 到 protocol $\texttt{P}$。
- **`requiresClass()`**：若 $T$ 的某个后缀在 property map 里的条目存了某个满足 $L\leq[\mathsf{layout}\colon\texttt{AnyObject}]$ 的 layout symbol $L$，则 type parameter $T$ 在表示上是一个 retainable pointer。

  这里之所以要用到序关系，是因为存在比 $[\mathsf{layout}\colon\texttt{AnyObject}]$ 更细的 layout symbol，例如 $[\mathsf{layout}\colon\texttt{\_NativeClass}]$，所以只检查是否恰好等于 $[\mathsf{layout}\colon\texttt{AnyObject}]$ 是不够的。

  给定两个 layout symbol $A$ 和 $B$，$A\wedge B$ 是同时满足二者的最一般的那个 symbol。当 $A=A\wedge B$ 时，两个元素之间有序关系 $A\leq B$。
- **`isConcreteType()`**：若 $T$ 的某个后缀在 property map 里的条目存了一个 concrete type symbol，则 type parameter $T$ 被钉死在一个 concrete type 上。

Layout symbol 以 `LayoutConstraint` 类实例的形式存放一条 layout constraint。`requiresClass()` 的实现里用到的 join 运算，定义在 `LayoutConstraint` 的 `merge()` 方法里。

`requiresProtocol()` 这个 query 你在 `symbols-terms-and-rules.tex` 里已经见过了，那里说明了它可以通过检查 $\Lambda(T).[\texttt{P}]\downarrow\Lambda(T)$ 来实现。property map 的实现也许还稍微高效一点，因为它只需要化简一个 term 而不是两个。另一方面，`requiresClass()` 和 `isConcreteType()` 是新东西，它们展示了 property map 的威力：光靠 rewrite system，这两个 query 除了在所有已知的 layout symbol 和 concrete type symbol 上穷举枚举之外，根本没法实现。

后面所有的例子都引用上一个例子（即带 `Cache` 的那个）里的 protocol 定义，以及由它得出的那张 property map。

> 译注：原书这句（以及后文「再看四个 property query 的例子」那句）指向的是**前一个**例子的那张表（$\texttt{P1}$–$\texttt{P4}$ 那份），但后文所有例子用的符号都是 $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$、$[\mathsf{layout}\colon\texttt{AnyObject}]$ 之类，只可能出自带 `Cache` 的那个例子的表；同理，后文说「Rule 10 见前一个例子」时，指的也是带 `Cache` 的这个例子。均疑为笔误。

**例.** 考虑 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$。这个 type parameter 经由 generic signature 里声明的一条 requirement conform 到 $\texttt{Q}$，而且因为 $\texttt{Q}$ 继承自 $\texttt{R}$，它也 conform 到 $\texttt{R}$。`requiresProtocol()` 会确认这两个事实，因为 $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 的 property map 条目里含有 protocol symbol $[\texttt{Q}]$ 和 $[\texttt{R}]$：

1. 对 $\texttt{Q}$ 的 conformance 由 rewrite rule $\tau_{0,0}.[\texttt{P}\vert\texttt{B}].[\texttt{Q}]\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 见证，也就是上一个例子里的 Rule 10。这是由 conformance requirement 生成的 initial rule。
2. 对 $\texttt{R}$ 的 conformance 由 rewrite rule $\tau_{0,0}.[\texttt{P}\vert\texttt{B}].[\texttt{R}]\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 见证，也就是上一个例子里的 Rule 14。这条规则是 completion 过程加进去的，用来消解上面那条 Rule 10（它说 $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ conform 到 $\texttt{Q}$）与 Rule 1（它说凡 conform 到 $\texttt{Q}$ 者也 conform 到 $\texttt{R}$）之间的 overlap。

**例.** 这个例子在两个不同的 type term 上演示 `requiresClass()` query。

首先，考虑 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{A}]$。query 返回 true，因为在 property map 里有条目的最长后缀是 $[\texttt{P}\vert\texttt{A}]$，它存了单独一个 symbol $[\mathsf{layout}\colon\texttt{AnyObject}]$。对应的 rewrite rule 是 $[\texttt{P}\vert\texttt{A}].[\mathsf{layout}\colon\texttt{AnyObject}]\Rightarrow[\texttt{P}\vert\texttt{A}]$，即上一个例子里的 Rule 5。这是由 protocol $\texttt{P}$ 里 $\mathrm{A}\colon\mathrm{AnyObject}$ 这条 layout requirement 生成的 initial rule。

再考虑 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$。query 同样返回 true。这一次最长后缀就是整个 type term，因为 property map 里为 $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 存了条目，其中的 layout symbol 是 $[\mathsf{layout}\colon\texttt{\_NativeClass}]$。这个 symbol 满足

$$[\mathsf{layout}\colon\texttt{\_NativeClass}]\leq[\mathsf{layout}\colon\texttt{AnyObject}],$$

因为

$$[\mathsf{layout}\colon\texttt{\_NativeClass}]\wedge [\mathsf{layout}\colon\texttt{AnyObject}]=[\mathsf{layout}\colon\texttt{\_NativeClass}].$$

**例.** 最后一个 predicate 是 `isConcreteType()` query。考虑 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{C}]$。在 property map 里出现的最长后缀是 $[\texttt{P}\vert\texttt{C}]$。这个条目存了 concrete type symbol $[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]]$，因此 query 返回 true。

接下来我要讲那些返回 type parameter **属性**的 generic signature query，不过这需要先多铺一点机器。第一步是把 `getRequiredProtocols()` 返回的 protocol 列表所满足的不变式定义清楚。

**定义.** 若一个 protocol 列表 $\{\texttt{P}_i\}$ 中没有任何一个 protocol 继承自列表里的另一个 protocol——也就是说，不存在 $i,j\in\mathbb{N}$ 使得 $i\neq j$ 且 $\texttt{P}_i$ 继承自 $\texttt{P}_j$——则称该列表是 **minimal** 的。若该列表按 canonical protocol order 排好序，则称它是 **canonical** 的。

从任意一个 protocol 列表 $P=\{\texttt{P}_1,\ldots,\texttt{P}_n\}$ 出发，可以用下面的算法构造出一个 minimal canonical 的 protocol 列表：

1. 令 $G=(V,\, E)$ 是这样一张有向无环图：$V$ 是所有 protocol 的集合，而当 $\texttt{P}\in V$ 继承自 $\texttt{Q}\in V$ 时，$E$ 中有一条从 $\texttt{P}$ 指向 $\texttt{Q}$ 的边。（原注：type checker 看到的非法代码里可能出现循环的 protocol 继承。编译器里的 request evaluator 框架会以一套成体系的办法打断这类环，所以 requirement machine 不必显式处理它。）
2. 构造由 $P$ 生成的子图 $H\subseteq G$。
3. 计算 $H$ 的根节点集合（也就是没有入边、入度为零的那些节点），得到 $P$ 的 minimal protocol 集合。
4. 用 canonical protocol order（见 `generic-signatures.tex` 的 Protocol order 算法）给这个集合的元素排序，得到由 $P$ 得出的最终 minimal canonical protocol 列表。

> 译注：「minimal canonical 的 protocol 列表」这个形状，正是 protocol composition 在二进制里的形状——existential 与 opaque return type 的 requirement 列表都按这套规则收敛过一遍，所以读回来时既不会有冗余的父 protocol，顺序也是 canonical 的而非源码顺序。本库在还原 opaque return type 的 primary associated type 时必须按这个前提办事：约束只能按 descriptor 给出的 canonical 顺序归属到各个 protocol 上，源码顺序是恢复不出来的。见 [OpaquePrimaryAssociatedTypeAttribution.md](../OpaquePrimaryAssociatedTypeAttribution.md)。

第二步是定义一个从 type term 到 Swift type parameter 的映射，供 `getSuperclassBound()` 和 `getConcreteType()` 在把 substitution 映射回 Swift 类型时使用。

**算法.** type lifting map $\Lambda^{-1}\colon\mathrm{Term}\rightarrow\mathrm{Type}$ 以一个 type term $T$ 为输入，把它映射回一个 Swift type parameter。它是 `symbols-terms-and-rules.tex` 的 Build term for associated requirement 算法所给出的 type lowering map $\Lambda\colon\mathrm{Type}\rightarrow\mathrm{Term}$ 的逆。

1. 把 $S$ 初始化为一个空的 type parameter。
2. $T$ 的第一个 symbol 必定是某个 generic parameter symbol $\tau_{d,i}$，它映射到 depth 为 $d$、index 为 $i$ 的 `GenericTypeParamType`。把 $S$ 置为这个类型。
3. $T$ 后续的每个 symbol 都必定是某个 associated type symbol $[\texttt{P}_1\cap\ldots\cap\texttt{P}_n\colon\mathrm{A}]$。这个 symbol 映射到一个 `DependentMemberType`，其 base type 是 $S$ 的前一个取值，而 associated type declaration 按下面的办法找：
   1. 对每一个 $\texttt{P}_i$，要么 $\texttt{P}_i$ 自己就定义了一个名为 $\mathrm{A}$ 的 associated type，要么 $\mathrm{A}$ 声明在某个 $\texttt{P}_i$ 所继承的 protocol $\texttt{Q}$ 里。两种情况下都把找到的 associated type declaration 收进一个列表。
   2. 上面找到的 associated type 里，若有非 root 的 associated type declaration，就把它换成它的 anchor（见 `generic-signatures.tex` 的 root associated type 定义）。
   3. 从上面这个集合里，按 associated type order（见 `generic-signatures.tex` 的 Associated type order 算法）挑出最小的那个 associated type declaration。

在正式给出这些 query 之前的第三步、也是最后一步，是把 superclass 或 concrete type symbol 映射回 Swift 类型的算法。这个算法会在 substitution 里出现的 type parameter 上用到上面那个 type lifting map。

**算法（Constructing a concrete type from a symbol）.** 本算法的输入是一个 superclass symbol $[\mathsf{superclass}\colon \mathrm{T}\colon\sigma_0,\ldots,\sigma_n]$ 或一个 concrete type symbol $[\mathsf{concrete}\colon \mathrm{T}\colon\sigma_0,\ldots,\sigma_n]$。它是 `symbols-terms-and-rules.tex` 的 Build concrete type symbol 算法的逆。

1. 令 $\pi_0,\ldots,\pi_n$ 是这样一组位置：$\mathrm{T}\vert_{\pi_i}$ 是 index 为 $i$ 的 `GenericTypeParamType`。
2. 对每个 $i$，把 $\mathrm{T}\vert_{\pi_i}$ 替换成 $\Lambda^{-1}(\sigma_i)$，即把 lifting map 作用到 $\sigma_i$ 上得到的 type parameter。
3. 做完上述全部代入之后，返回类型 $\mathrm{T}$ 的最终取值。

现在，终于可以来讲这四个 property query 的实现了。

- **`getRequiredProtocols()`**：type parameter $T$ 满足的那些 protocol requirement，在 property map 里以 protocol symbol 的形式记录着。用上面那条 minimal canonical protocol 列表的定义，把这个列表转换成 minimal canonical 的形式。
- **`getLayoutConstraint()`**：一个 type parameter $T$ 可能同时受多条 layout constraint 约束，这时 property map 条目里会存一串 layout constraint $L_1,\ldots,L_n$。本 query 要计算它们的 join，也就是同时满足所有这些约束的最大的那条 layout constraint：

  $$L_1\wedge\cdots\wedge L_n.$$

  有些 layout constraint 在 concrete type 上是互斥的，这意味着它们的 join 是那条无居民的「bottom」layout constraint，它在偏序里排在所有其它 layout constraint 之前。这种情况下，就说原来的 generic signature 含有 conflicting requirement。这样的 signature 虽然不违反 requirement machine 的不变式，但没有任何一组合法的 concrete substitution 能满足它。conflicting requirement 的检测与诊断留到后面讨论。
- **`getSuperclassBound()`**：若 type parameter $T$ 不满足任何 superclass symbol，返回空类型。否则，$T$ 可以写成 $T=UV$，其中 $V$ 是 $T$ 在 property map 里出现的最长后缀。令 $[\mathsf{superclass}\colon \mathrm{C};\,\sigma_0,\ldots,\sigma_n]$ 是 $P[V]$ 里的一个 superclass symbol。

  第一步是调整这个 symbol：给每个 substitution $\sigma_i$ 前置 $U$，产生 superclass symbol

  $$[\mathsf{superclass}\colon \mathrm{C};\,\sigma_0,\ldots,U\sigma_n].$$

  然后就可以用 Constructing a concrete type from a symbol 算法把这个 symbol 转换成一个 Swift 类型。
- **`getConcreteType()`**：这个 query 与 `getSuperclassBound()` 几乎一模一样，把上面那段里的「superclass symbol」换成「concrete type symbol」即可。

> 译注：上面那个展示式里第一个 substitution 原书写作 $\sigma_0$ 而非 $U\sigma_0$，与紧接着的正文「给每个 substitution $\sigma_i$ 前置 $U$」相矛盾，疑为笔误；应为 $U\sigma_0,\ldots,U\sigma_n$。

注意 `getLayoutConstraint()` 处理多个 layout symbol 的办法是算它们的 join，而 `getSuperclassBound()` 和 `getConcreteType()` 却只是随便挑一个 superclass 或 concrete type symbol。的确，我们后面会看到只挑一个并不总是够用：一个完整的实现必须对 superclass 和 concrete type symbol 也做 join；而且，类似于「无居民的 layout constraint」的情形同样会出现——一个 type parameter 可能受一组互相冲突的 superclass 或 concrete type requirement 约束。不过就目前而言，现在这套表述已经够用了。

下面再看看这四个 property query 的例子。同样地，这些例子用的是上面那张（带 `Cache` 的那个例子的）property map。

**例.** 考虑在 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 上计算 `getRequiredProtocols()`。property map 里存的 protocol symbol 是 $\{[\texttt{Q}],[\texttt{R}]\}$，但 $\texttt{Q}$ 继承自 $\texttt{R}$，所以 minimal canonical 的 protocol 列表就只剩 $\{[\texttt{Q}]\}$。

**例.** 考虑在 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 上计算 `getSuperclassBound()`。superclass symbol $[\mathsf{superclass}\colon \mathrm{Cache}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]]$ 不需要靠给每个 substitution term 前置前缀来调整，因为这条 property map 条目关联的就是整个 term $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$。

把 Constructing a concrete type from a symbol 算法作用到这个 superclass symbol 上，得到 Swift 类型：

$$\mathrm{Cache}\langle\tau_{0,0}.\mathrm{A}\rangle.$$

**例.** 考虑在 canonical type term $\tau_{0,0}.[\texttt{P}\vert\texttt{C}]$ 上计算 `getConcreteType()`。这里 property map 条目关联的是后缀 $[\texttt{P}\vert\texttt{C}]$，这意味着必须对 concrete type symbol $[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{A}]]$ 做调整。调整后的 symbol 是

$$[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=\tau_{0,0}.[\texttt{P}\vert\texttt{A}]].$$

把 Constructing a concrete type from a symbol 算法作用到调整后的 concrete type symbol 上，得到 Swift 类型：

$$\mathrm{Array}\langle\tau_{0,0}.\mathrm{A}\rangle.$$

## Reduced Types

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。本块一直延续到 Source Code Reference 一节之前。

canonical type query 把前面所有东西串了起来。

- **`areSameTypeParametersInContext()`**：两个 type parameter $T$ 与 $U$ 等价，当且仅当 $\Lambda(T)\downarrow\Lambda(U)$；而这成立当且仅当 $\Lambda(T){\downarrow}=\Lambda(U){\downarrow}$。

  注意，如果 $T$ 或 $U$ 中任何一个被钉死在 concrete type 上，这个 query 就派不上什么用场了。

  这也是唯一一个只靠 rewrite system、不靠 property map 就能解的 generic signature query；放在这里只是为了完整。
- **`isCanonicalTypeInContext()`**：这个 query 对类型 $T$ 做一连串检查；其中任何一项不通过，$T$ 就不是 canonical 的，返回 false。

  有两种情形要考虑：$T$ 要么是一个 type parameter，要么是一个 concrete type（后者的嵌套位置上还可能含有 type parameter）：

  1. 若 $T$ 是 type parameter，则 $T$ 是 canonical type 当且仅当它既是 canonical anchor，又没有被钉死在某个 concrete type 上。
     1. inherited 与 merged associated type 的那些特殊性质，使得一个类型 $T$ 可以在**类型**层面是 canonical anchor，即便 $\Lambda(T)$ 并不是一个 canonical **term**。不过有一个较弱的条件把两种「canonical」联系了起来：$T$ 是 canonical anchor，当且仅当把 type lowering map 作用到 $T$ 上、归约结果、再作用 type lifting map，得到的还是 $T$：

        $$\Lambda^{-1}(\Lambda(T){\downarrow})=T.$$
     2. 一旦知道 type parameter $T$ 是 canonical anchor，只要再检查 `isConcreteType()` 返回 false，就足以断定它是一个 canonical type parameter。
  2. 否则，$T$ 是一个 concrete type。令 $\pi_0,\ldots,\pi_n$ 是 $T$ 中使 $T\vert_{\pi_i}$ 为 type parameter 的那组位置。那么 $T$ 是 canonical 的，当且仅当所有投影 $T\vert_{\pi_i}$ 都是 canonical type parameter。
- **`getCanonicalTypeInContext()`**：同样地，$T$ 要么是 type parameter，要么是 concrete type。下面先讲 type parameter 的情形；concrete type 的情形是递归实现的，办法是考察所有含有 type parameter 的嵌套位置。

  1. 若 $T$ 是 type parameter，`isConcreteType()` 会判定 $T$ 是否被钉死在某个 concrete type 上。
     1. 若 $T$ 被钉死在某个 concrete type $T'$ 上，则 $T$ 的 canonical type 等于 $T'$ 的 canonical type。这可以通过对 `getConcreteType()` 的结果递归调用 `getCanonicalTypeInContext()` 来算出。
     2. 否则 $T$ 没被钉死在 concrete type 上，这意味着 $T$ 的 canonical type 就是 $T$ 的 canonical anchor。令 $\Lambda(T)$ 是 $T$ 对应的 type term，$\Lambda(T){\downarrow}$ 是 term $\Lambda(T)$ 的 canonical form，那么 $T$ 的 canonical anchor 就是 $\Lambda^{-1}(\Lambda(T){\downarrow})$。
  2. 否则，$T$ 是一个 concrete type。令 $\pi_0,\ldots,\pi_n$ 是 $T$ 中使 $T\vert_{\pi_i}$ 为 type parameter 的那组位置。$T$ 的 canonical type，就是把每个位置 $\pi_i$ 上的 type parameter 换成对 $T\vert_{\pi_i}$ 递归调用 `getCanonicalTypeInContext()` 的结果之后得到的那个类型。

**例.** 这个例子展示 protocol 继承怎样导致这样一种局面：一个 canonical anchor $T$ lower 之后得到的 term $\Lambda(T)$ 却不是 canonical 的。考虑 generic signature $\langle \tau_{0,0}\;\textit{where}\;\tau_{0,0}\colon\texttt{P}\rangle$，protocol 定义如下：

```swift
protocol Q {
  associatedtype A
}

protocol P : Q {}
```

rewrite system 有两条 associated type introduction rule，一条来自 $\mathrm{A}$ 在 $\texttt{Q}$ 里的声明，另一条来自 $\texttt{P}$ 中继承而来的类型 $\mathrm{A}$：

$$\begin{aligned}
[\texttt{Q}].\mathrm{A} &\Rightarrow [\texttt{Q}\vert\texttt{A}] && \qquad (1)\\
[\texttt{P}].[\texttt{Q}\vert\texttt{A}] &\Rightarrow [\texttt{P}\vert\texttt{A}] && \qquad (2)
\end{aligned}$$

protocol 之间的继承关系也引入一条 rewrite rule：

$$\begin{aligned}
[\texttt{P}].[\texttt{Q}] &\Rightarrow [\texttt{P}] && \qquad (3)
\end{aligned}$$

最后，generic signature 里的 conformance requirement 添上这条 rewrite rule：

$$\begin{aligned}
\tau_{0,0}.[\texttt{P}] &\Rightarrow \tau_{0,0} && \qquad (4)
\end{aligned}$$

消解 critical pair 又加进几条规则：

$$\begin{aligned}
[\texttt{P}].\mathrm{A} &\Rightarrow [\texttt{P}\vert\texttt{A}] && \qquad (5)\\
\tau_{0,0}.[\texttt{Q}] &\Rightarrow \tau_{0,0} && \qquad (6)\\
\tau_{0,0}.[\texttt{Q}\vert\texttt{A}] &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{A}] && \qquad (7)\\
\tau_{0,0}.\mathrm{A} &\Rightarrow \tau_{0,0}.[\texttt{P}\vert\texttt{A}] && \qquad (8)
\end{aligned}$$

现在考虑 type parameter $T:=\tau_{0,0}.\mathrm{A}$。这个 type parameter 是 reduced 的。由于 Swift 的 type parameter 总是指向一个真实存在的 associated type declaration，type term $\Lambda(T)$ 是 $\tau_{0,0}.[\texttt{Q}\vert\texttt{A}]$，而不是 $\tau_{0,0}.[\texttt{P}\vert\texttt{A}]$。然而 $\tau_{0,0}.[\texttt{Q}\vert\texttt{A}]$ 作为 term 并不 canonical，它经 Rule 7 归约到 $\tau_{0,0}.[\texttt{P}\vert\texttt{A}]$；于是 $T$ 是 canonical anchor，$\Lambda(T)$ 却不是 canonical term。

本质上说，term $\tau_{0,0}.[\texttt{P}\vert\texttt{A}]$ 比 $\Lambda\colon\mathrm{Type}\rightarrow\mathrm{Term}$ 所能输出的任何 type parameter 都「更 canonical」。Protocol $\texttt{P}$ 实际上并没有定义名为 $\mathrm{A}$ 的 associated type，因此 $\Lambda$ 只能构造出含有 symbol $[\texttt{Q}\vert\texttt{A}]$ 的 term，可偏偏 $[\texttt{P}\vert\texttt{A}]<[\texttt{Q}\vert\texttt{A}]$。

不过这里的关键不变式是 $\Lambda^{-1}(\tau_{0,0}.[\texttt{Q}\vert\texttt{A}])=\Lambda^{-1}(\tau_{0,0}.[\texttt{P}\vert\texttt{A}])=T$，换句话说：

$$\Lambda^{-1}(\Lambda(T){\downarrow})=T.$$

merged associated type symbol 也会造成类似局面，它同样比 $\Lambda$ 输出的任何「真」associated type symbol 都小。同样地，你会碰到一个 canonical type parameter $T$，它 lower 出来的 type term $\Lambda(T)$ 却不 canonical；但和刚才一样，$\Lambda^{-1}$ 会把 $\Lambda(T)$ 和它的 canonical form $\Lambda(T){\downarrow}$ 都映回 $T$，因为从 $\Lambda(T)$ 到 $\Lambda(T){\downarrow}$ 唯一可能的归约路径只会引入 merged associated type symbol，而这在 type lifting map 下是不变的。

**例.** 下一个例子演示存在 concrete type 时的 canonical type 计算。下面这张表给出了从这个 generic signature

$$\langle \tau_{0,0}\;\textit{where}\;\tau_{0,0}\colon\texttt{P},\,\tau_{0,0}.\mathrm{B}==\mathrm{Int}\rangle,$$

连同下面这份 protocol 定义构造出来的 property map：

```swift
protocol P {
  associatedtype A where A == Array<B>
  associatedtype B
}
```

**表：从这个例子构造出的 property map**

| Keys | Values |
|---|---|
| $[\texttt{P}\vert\texttt{A}]$ | $[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{B}]]$ |
| $\tau_{0,0}$ | $[\texttt{P}]$ |
| $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ | $[\mathsf{concrete}\colon \mathrm{Int}]$ |

考虑 type parameter $T:=\tau_{0,0}.\mathrm{A}$。它是一个 canonical anchor，因为 $\Lambda(T)=\tau_{0,0}.[\texttt{P}\vert\texttt{A}]$ 是 canonical term；但 $T$ 仍然不是 canonical type，因为它被钉死在一个 concrete type 上。所以 `isCanonicalTypeInContext()` 在 $T$ 上返回 false。

在 $T$ 上做 `getConcreteType()` query，会发现 $\Lambda(T)$ 中带有 property map 条目的最长后缀是 $[\texttt{P}\vert\texttt{A}]$，对应的前缀是 $\tau_{0,0}$。这条 property map 条目存的 concrete type symbol 是

$$[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=[\texttt{P}\vert\texttt{B}]].$$

给 substitution term $\sigma_0$ 前置 $\tau_{0,0}$，得到调整后的 concrete type symbol：

$$[\mathsf{concrete}\colon \mathrm{Array}\langle\sigma_0\rangle;\,\sigma_0:=\tau_{0,0}.[\texttt{P}\vert\texttt{B}]].$$

把这个 symbol 转换成 Swift 类型，得到 $\mathrm{Array}\langle\tau_{0,0}.\mathrm{B}\rangle$。然而这还不是 canonical type，因为出现在嵌套位置上的 type parameter $\tau_{0,0}.[\texttt{P}\vert\texttt{B}]$ 不 canonical。对 type parameter $\tau_{0,0}.\mathrm{B}$ 递归调用 `getCanonicalTypeInContext()` 返回 $\mathrm{Int}$。因此，最初那次对 $T$ 的 `getCanonicalTypeInContext()` 调用返回

$$\mathrm{Array}\langle\mathrm{Int}\rangle.$$

接下来的问题比较微妙。为了正确处理涉及 concrete type symbol 与 superclass symbol 的规则之间的 overlap，Knuth-Bendix completion 过程需要做一点调整。下面我只谈 concrete type symbol，但照例，superclass symbol 的情况完全一样，把 $[\mathsf{concrete}\colon\cdots]$ 换成 $[\mathsf{superclass}\colon\cdots]$ 即可。

设两条相互 overlap 的规则是 $x\Rightarrow y$ 与 $x'\Rightarrow y'$，且 overlap 属于第二种，也就是 $x$ 有一个后缀等于 $x'$ 的某个前缀。再假设 $x'$ 以一个 concrete type symbol 结尾。沿用那条定义里的记法，这意味着

$$\begin{aligned}
x&=uv\\
x'&=vw.[\mathsf{concrete}\colon \mathrm{T};\;\sigma_0,\ldots,\sigma_n]
\end{aligned}$$

若完全照搬先前那条定义，overlap 出来的 term $t$ 是

$$t=uvw.[\mathsf{concrete}\colon \mathrm{T};\;\sigma_0,\ldots,\sigma_n].$$

用 $x\Rightarrow y$ 和 $x'\Rightarrow y'$ 归约 $t$，得到 critical pair：

$$\begin{aligned}
t_0&=yw.[\mathsf{concrete}\colon \mathrm{T};\;\sigma_0,\ldots,\sigma_n]\\
t_1&=uy'
\end{aligned}$$

下一个例子会说明，这并不是我们想要的。实际上，completion 会给每个 substitution term $\sigma_i$ 前置 $u$。于是调整后的 overlap term $t$ 是

$$t=uvw.[\mathsf{concrete}\colon \mathrm{T};\;u\sigma_0,\ldots,u\sigma_n].$$

用 $x\Rightarrow y$ 和 $x'\Rightarrow y'$ 归约调整后的 $t$，得到正确的 critical pair：

$$\begin{aligned}
t_0&=yw.[\mathsf{concrete}\colon \mathrm{T};\;u\sigma_0,\ldots,u\sigma_n]\\
t_1&=uy'
\end{aligned}$$

注意 $t_0$ 里的 substitution 现在每个 $\sigma_i$ 前面都带上了 $u$。

（顺带一问：关于 $t_1$ 还能不能多说点什么？是不是有 $t_0>t_1$？由于 $x'\Rightarrow y'$ 是一条 property-like 规则，$x'$ 就等于 $y'$ 后面接上一个 concrete type symbol，换句话说 $y'=vw$，于是 $t_1=uvw$。但 $x=uv$，所以 $t_1=uvw$ 可以归约到 $yw$。所以确实：上面这个 critical pair 要么因为 $t_0$ 能被别的规则归约而变得平凡，要么就引入 rewrite rule $t_0\Rightarrow yw$。）

**例.** 考虑下面这段代码清单里 class $\mathrm{C}$ 的 generic signature：

**代码清单：涉及 concrete type term 的 overlap 例子**

```swift
struct G<A> {}

protocol S {
  associatedtype E
}

protocol P {
  associatedtype T
  associatedtype U where U == G<V>
  associatedtype V
}

class C<X>
  where X : S,
        X.E : P,
        X.E.U == X.E.T {}
```

$$\begin{aligned}
\langle \tau_{0,0}\;\textit{where}\;&\tau_{0,0}\colon\texttt{S},\\
&\tau_{0,0}.\mathrm{E}\colon\texttt{P},\\
&\tau_{0,0}.\mathrm{E}.\mathrm{U}==\tau_{0,0}.\mathrm{E}.\mathrm{T}\rangle
\end{aligned}$$

这个 generic signature 的 rewrite rule 中相关的那一部分：

$$\begin{aligned}
[\texttt{P}\vert\texttt{U}].[\mathsf{concrete}\colon \mathrm{G}\langle\sigma_0\rangle;\;\sigma_0:=[\texttt{P}\vert\texttt{V}]] &\Rightarrow [\texttt{P}\vert\texttt{U}] && \qquad (\text{Rule } 1)\\
\tau_{0,0}.[\texttt{S}] &\Rightarrow \tau_{0,0} && \qquad (\text{Rule } 2)\\
\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}] &\Rightarrow \tau_{0,0}.[\texttt{S}\vert\texttt{E}] && \qquad (\text{Rule } 3)\\
\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{U}] &\Rightarrow \tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}] && \qquad (\text{Rule } 4)
\end{aligned}$$

可以看到 Rule 4 与 Rule 1 有 overlap。计算 critical pair 时，前缀 $\tau_{0,0}.[\texttt{S}\vert\texttt{E}]$ 必须前置到 concrete type symbol 内部的 substitution $\sigma_0$ 上：

$$\begin{aligned}
t_0&=\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}].[\mathsf{concrete}\colon \mathrm{G}\langle\sigma_0\rangle;\;\sigma_0:=\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{V}]]\\
t_1&=\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{U}]
\end{aligned}$$

此时 $t_0$ 已经无法再归约，而 Rule 7 把 $t_1$ 归约成 $\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}]$。这意味着消解这个 critical pair 会引入新的 rewrite rule：

$$\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}].[\mathsf{concrete}\colon \mathrm{G}\langle\sigma_0\rangle;\;\sigma_0:=\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{V}]]\Rightarrow\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}].$$

completion 过程一开始拿到的事实是

$$[\texttt{P}\vert\texttt{U}]==\mathrm{G}\langle[\texttt{P}\vert\texttt{V}]\rangle,$$

推出来的则是

$$\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}]==\mathrm{G}\langle\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}]\rangle.$$

把 concrete type symbol 做调整——给出现在 Rule 7 左端的 substitution $\sigma_0$ 前置前缀 $\tau_{0,0}.[\texttt{S}\vert\texttt{E}]$——相当于给 concrete type 换了个根，这才得出上面那个正确结果。不做这步调整的话，我们推出来的会是

$$\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}]==\mathrm{G}\langle[\texttt{P}\vert\texttt{T}]\rangle,$$

这是讲不通的。

> 译注：这个例子里有三处对不上的地方。其一，文中两次提到的「Rule 7」并不存在——源文件里前三条 associated type introduction rule 被注释掉之后编号重排了，但这两处没跟着改：归约 $t_1$ 的是 Rule 4，左端带 substitution $\sigma_0$ 的是 Rule 1。其二，推出的那条事实右端写作 $\mathrm{G}\langle\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{T}]\rangle$，但按上面那条新 rewrite rule 应为 $\mathrm{G}\langle\tau_{0,0}.[\texttt{S}\vert\texttt{E}].[\texttt{P}\vert\texttt{V}]\rangle$（$\texttt{V}$ 而非 $\texttt{T}$）。均疑为笔误。

concrete type 的这项调整，在下一章讲 property map 构造（Property map construction 算法）与查找（Property map lookup 算法）时还会再遇到。

> 译注：原书这句说「下一章」，但 property map 的构造与查找算法就在**本章**开头。这一整段（从 completion 的调整讲起、到上面这个例子为止）显然是从 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 挪过来的草稿，「下一章」的说法没跟着改。

## Source Code Reference

> 译注：原书本节只有一个标题，没有任何条目——与本章其余部分一样尚未撰写。

---

> 译自 `docs/Generics/chapters/property-map.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
