# Basic Operation（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/basic-operation.tex`（《Compiling Swift Generics》一书的「Basic Operation」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `c9d2f522c02`，2025-12-02）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章是全书第四部分（The Requirement Machine）的入门章，从外部视角讲清楚「这台机器有几种实例、各自什么时候建、建完拿来干什么」，不涉及内部的重写系统本身。本库 MachOSwiftSection **不实现** Requirement Machine——二进制里的 requirement 已经是它 minimize 过的结果，type parameter 也已经是 reduced 形式，本库只是把这些成品读回来。读本章的价值在于知道「读到的东西是怎么被算出来的」：为什么 requirement 的顺序是那个顺序、为什么同一份 protocol 的 associated requirement 在不同二进制里长得一样、为什么相互递归的一组 protocol 会被当成一个整体处理。
>
> **术语**：书中定义的术语一律保留英文（requirement machine、query machine、minimization machine、protocol machine、protocol minimization machine、rewrite context、local rule、imported rule、property map、completion、convergent rewriting system、protocol component、protocol dependency graph、strongly connected component、spanning tree、tree edge、frond、cross-link、requirement signature、generic signature query、minimal requirement……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Generic Signature Queries 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的算法、定义、例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，本章按 Markdown LaTeX 数学书写，行内用 `$...$`、展示式用 `$$...$$`）：
>
> | 记法 | 含义 |
> |---|---|
> | $[\texttt{T: P}]$ | conformance requirement：类型 `T` 遵循 protocol `P` |
> | $[\texttt{T == X}]$ | same-type requirement |
> | $[\texttt{Self.U: Q}]_\texttt{P}$ | protocol `P` 的一条 **associated conformance requirement**（下标是声明它的 protocol） |
> | $G_\texttt{P}$ | protocol `P` 的 **protocol generic signature**，即 `<Self where Self: P>` |
> | $G \vdash [\texttt{T: P}]$ | 从 generic signature $G$ 可以**推导出**这条 requirement |
> | $\texttt{P} \prec \texttt{Q}$ | protocol `P` **依赖** protocol `Q` |
> | $G \prec \texttt{P}$ | generic signature $G$ 对 protocol `P` 有一条 **protocol dependency** |
> | $x \prec y$ | 有向图里存在一条从 $x$ 到 $y$ 的 path（**reachability relation**） |
> | $x \equiv y$ | 顶点 $x$ 与 $y$ **strongly connected**，即 $x \prec y$ 且 $y \prec x$ |
> | $(V, E)$ | 有向图，$V$ 是顶点集，$E$ 是边集 |
> | $\operatorname{src}(e)$、$\operatorname{dst}(e)$ | 边 $e$ 的起点与终点 |
> | $\texttt{NUMBER}(v)$ | Tarjan 算法给顶点 $v$ 的访问序号 |
> | $\texttt{LOWLINK}(v)$ | Tarjan 算法给顶点 $v$ 的 lowlink 值；$\texttt{LOWLINK}(v)=\texttt{NUMBER}(v)$ 表示 $v$ 是某个 strongly connected component 的 root |
> | $\texttt{ONSTACK}(v)$ | 一个 bit，表示 $v$ 当前是否在栈上 |
> | **Conf**、**AssocConf** | derived requirement 形式系统里的推导步骤名（见 `derived-requirements-summary.tex`（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)）） |

---

本书的最后一部分专讲两件事的实现：generic signature query（见 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）的 Generic Signature Queries 一节）与 requirement minimization（见 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）的 Requirement Minimization 一节）。我们的目标是搞懂 derived requirement 形式系统的一套**判定过程**（decision procedure）。我们会学着把每个 generic signature 与每个 protocol 的 requirement 翻译成 **rewrite rule**，然后分析这些规则生成的某个关系。

我们用专有名词「the Requirement Machine」指编译器里负责这套推理的那个组件；而**一台** requirement machine——普通名词——指的是一个数据结构**实例**，它装着描述某个具体 generic signature 或 protocol 的那些 rewrite rule。

本章只给出 requirement machine 运转方式的高层概览，完全不谈内部发生了什么。要理解内部机理还得再花两章：`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)） 介绍 finitely-presented monoid 与 string rewriting 的理论，`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)） 详述 requirement 到 rewrite rule 的翻译。

出发。进入 Requirement Machine 有两个主要入口：

- **回答一个 generic signature query** 时，我们先用给定 generic signature 的 requirement 构造一台 requirement machine，称之为 **query machine**。然后我们查这台 query machine 的 **property map**：那是一份描述，说明每个 type parameter 上都压着哪些 conformance、superclass、layout 与 concrete type requirement。

- **构建一个新的 generic signature** 时，我们用一份用户写下的 requirement 列表构造一台 requirement machine，称之为 **minimization machine**。新签名的 minimal requirement 是这个构造过程的副产品。

此外还有两个与 protocol 声明相关的入口：

- 要为一个声明了 conformance requirement 的 generic signature 构造 query machine 或 minimization machine，我们得先为该 protocol 的 requirement signature 建一台 requirement machine，称之为 **protocol machine**。
- 要为源码里写下的 protocol **构建一个新的 requirement signature**，我们用那份用户写下的 requirement 列表构造一台 requirement machine，称之为 **protocol minimization machine**。minimal associated requirement 是这个构造过程的副产品。

一台 requirement machine 的 rewrite rule 分成两类：**local rule** 对应这台机器最初据以建立的那些 requirement；**imported rule** 则（马上就会看到）描述 local rule 所引用的那些 protocol 的 associated requirement。下面逐一细看这四种 requirement machine。

> 译注：本库处在这条流水线的下游终点——二进制里存下来的 requirement 已经是 minimization machine 输出的 minimal requirement，type parameter 也已经是 property map 给出的 reduced 形式。本库读 opaque type descriptor 里那串逐字节的 requirement 时，看到的顺序与形态正是这里定下来的 canonical 结果，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

### Query machines.

我们在一个单例对象里维护一张 **query machine** 实例表，这个单例叫 **rewrite context**。表的 key 可以直接用 **canonical** 的 generic signature，因为把 requirement 翻译成 rewrite rule 的过程会忽略 type sugar。一台 query machine 一旦建好，就在整个编译会话期间一直活着。我们这样从一个 generic signature 建出 query machine：

1. 用 `symbols-terms-and-rules.tex` 的 Build rule from explicit requirement 算法把 generic signature 的 explicit requirement 翻译成 rewrite rule，得到这台 query machine 的 local rule 列表。

2. 对签名里每条 conformance requirement 右侧出现的 protocol，**惰性**地构造一台 protocol machine。

3. 用本章的 Import rules from protocol components 算法，从这些 protocol machine、以及它们递归引用到的所有 protocol machine 里收集 local rule，得到这台 query machine 的 imported rule 列表。

4. 跑 **completion procedure**（见 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)）），把那些属于既有规则之「推论」的新 local rule 加进来。这样我们就得到了一个 **convergent rewriting system**。

5. 建立 property map 数据结构（见 `property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)））。

6. 如果建立 property map 的过程又添了新的 local rule，回到第 4 步，重新跑一遍 completion 与 property map 构造。

流程图如下：

```
 Minimal requirements ───→ Collect protocols ───→ Imported rules
          │                                              │
          ↓                                              │
     Build rules ←─────────────────────────────────────── ┘
          │
          ↓
     Completion ←──────────────┐
          │                    │
          ↓                    │
  Build property map ──────────┘
          │
          ↓
  Requirement machine
```

> 译注：原书此处是一张 TikZ 流程图（方框为 data 与 stage 两类节点），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### Minimization machines.

要算出一个新 generic signature 的 minimal requirement 列表，我们建一台 **minimization machine**。这是 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)）里 inferred generic signature request 与 abstract generic signature request 两张总览图的最后一步。minimization machine 的生命期是临时的，归 **inferred generic signature request** 或 **abstract generic signature request** 所有。流程与建 query machine 相似，只是输入换成了 desugar 之后的用户手写 requirement（见 `building-generic-signatures.tex` 的 Decomposition and Desugaring 一节）。其它几处主要差别是：

1. 如果输入的 requirement 里含有 unbound dependent member type——它们来自 structural resolution 阶段时就是这样——completion 得多做一些工作。
2. completion 还会记录 **rewrite loop**，用来描述规则之间的关系；具体来说，这描述了哪些规则因为是既有规则的推论而变得冗余。
3. 构造 property map 时，我们会记下任何相互冲突的 requirement，以便在这个 generic signature 有源码位置时给出诊断。
4. completion 与 property map 构造之后，我们处理那些 rewrite loop，找出一个能蕴含其余规则的 local rule 极小子集。这是 `minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)） 的主题。
5. 最后，我们把这些 minimal rule 翻译回 requirement，得到要输出的 minimal requirement 列表。这在 `minimization.tex` 的 Building Requirements 一节讲解。

流程图如下：

```
 Desugared requirements ───→ Collect protocols ───→ Imported rules
            │                                              │
            ↓                                              │
       Build rules ←─────────────────────────────────────── ┘
            │
            ↓
       Completion ←──────────────┐
            │                    │
            ↓                    │
    Build property map ──────────┘
            │
            ↓
   Find minimal rules ─────→ Build requirements
            │                        │
            ↓                        ↓
   Requirement machine       Minimal requirements
```

> 译注：原书此处是一张 TikZ 流程图，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

### An optimization.

构建新 generic signature 时，minimal requirement 列表是构造 minimization machine 的**副产品**。做完之后我们当然可以直接把这台 minimization machine 扔掉，但我们会先去 rewrite context 里看看：同一个 generic signature 是否已经有一台 query machine 了。如果还没有，我们就把这台新的 minimization machine **install** 进去，把所有权转交给 rewrite context。这在下面这种情形下能省不少功夫：我们为 main module 里写的某个声明构建了一个新的 generic signature，紧接着在类型检查该声明的函数体时又要对这个新签名发起查询。

```
 Desugared      ───→   Minimization   ───→   Minimal
 requirements           machine              requirements
                           ║
                           ║  （同一个对象）
                           ║
 Minimal        ───→     Query
 requirements            machine
```

> 译注：原书此处是一张 TikZ 图（两行三列的矩阵，minimization machine 与 query machine 之间用一条双线相连，表示它们是同一个实例），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

这个优化要成立，用户写下的那些 requirement 必须与 minimization machine **输出**的 minimal requirement 生成同一套 **theory**——「同一套 theory」是 `building-generic-signatures.tex` 里 generic signature equivalence 那条命题的意义上的。这个等价性几乎总是成立，只有下面四种情形例外。前三种只在代码有错时出现，并且都伴有诊断；第四种不是错误，只是一种罕见的边界情形，此时这个优化做不了：

1. minimization 输出的一定是一份 **well-formed** 的 requirement 列表，也就是说它们只引用合法的 type parameter（见 `building-generic-signatures.tex` 的 Well-Formed Requirements 一节）。如果用户写下的 requirement 里有不 well-formed 的，我们会把它丢掉，于是输出的 minimal requirement 列表生成的是另一套 theory。

2. 当两条 requirement 相互冲突、无法同时被满足时（见 `building-generic-signatures.tex` 里 conflicting requirement 的定义），我们有时会丢掉其中一条。这时新建的 query machine 同样不会包含那些冲突的 requirement。

3. 正如 `monoids.tex` 的 The Word Problem 一节将要看到的，如果用户写下的 requirement 复杂到无法推理，completion 可能失败。这种情况下 minimization machine 输出一份空的 minimal requirement 列表。

4. 如果一条 conformance requirement 被一条把 type parameter 钉死到具体类型的 same-type requirement 弄成了冗余的（比如同时有 $[\texttt{T: P}]$ 和 $[\texttt{T == X}]$，而 `X` 是一个遵循 `P` 的 concrete type），我们会把那条 conformance requirement 丢掉，但这会改变 theory；这一点我们将在 `property-map.tex` 的 Concrete Conformances 一节讨论。

只要上述任一条件成立，我们就在建 minimization machine 的过程中把这个事实记下来。这会阻止这台 minimization machine 被 install 进 rewrite context，迫使我们把它丢弃。frontend flag `-disable-requirement-machine-reuse` 是给调试用的，它把这个优化整个关掉，强制我们立刻丢弃所有 minimization machine，连尝试 install 都不做。

### Protocol machines.

一台 **protocol machine** 收集的是一个 **protocol component**（即一组相互依赖的 protocol 声明）的 associated requirement。眼下我们先当作每个 component 都只含一个 protocol——这是典型情形；一般情形留给下一节。

protocol machine 的生命期是全局的，归 rewrite context 所有。建 protocol machine 的过程与建 query machine 相似：

1. 用 `symbols-terms-and-rules.tex` 的 Build rule from associated requirement 算法，把每个 protocol 的 associated requirement 翻译成 rewrite rule。这些就是该 protocol machine 的 local rule。
2. 对每条 associated conformance requirement 右侧出现的 protocol，惰性地构造一台 protocol machine。
3. 用本章的 Import rules from protocol components 算法，从这些 protocol machine、以及它们递归引用到的所有 protocol machine 里收集 local rule，得到我们的 imported rule。也就是说，protocol machine 会递归地从别的 protocol machine 导入规则。
4. completion 与 property map 构造与 query machine 的情形相同。

典型场景是这样的：用户的程序声明了一批 protocol，然后通过在各种 generic 类型与函数上写 conformance requirement，把这些 protocol 引用很多次。因此，两个不同 generic signature 的 requirement machine 若依赖同一批 protocol，就可能共享大量 rewrite rule。

protocol machine 就是这些共享规则的容器。这样一来，「把一个 protocol 的 associated requirement 翻译成 rewrite rule、再对这些规则跑一遍 completion」的开销就不必重复付出了。取而代之的是：当某台 query machine 或 minimization machine 依赖某个 protocol 时，我们为这个 protocol 惰性地创建一次 protocol machine，此后每当建 requirement machine 需要它的 rewrite rule，就**导入**过来。

### Protocol minimization machines.

要真正构建源码里写下的 protocol 的 requirement signature，我们构造一台 **protocol minimization machine**。protocol minimization machine 的生命期是临时的，作用域限于 **requirement signature request**。requirement signature 的 minimal requirement 是构造这台 protocol minimization machine 的副产品。

在没有错误条件的前提下，我们会把这台 protocol minimization machine install 进 rewrite context，于是它就变成了同一个 protocol component 的长期 protocol machine。事实上，只有在 protocol minimization machine **没能**被 install 时，我们才会为源码里写的 protocol 直接构造 protocol machine。除此之外，protocol machine 通常只在用户程序引用了来自 serialized module（比如标准库）的 protocol 时才会建起来。

> 译注：这里说的 requirement signature，正是本库从二进制里读回来的那份东西：protocol descriptor 里存的 requirement 就是这台机器 minimize 过的结果，本库把符号被 strip 掉的 protocol requirement 投影成按槽位编号的记录来做 ABI 比对，见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

**例.** 我们在 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)）开头谈过下面这几个声明，最近一次是在该章的 same name rule 那个例子里：

```swift
func sameElt<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Element == S2.Element {...}

func sameIter<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Iterator == S2.Iterator {...}

func sameEltAndIter<S1: Sequence, S2: Sequence>(_ s1: S1, _ s2: S2)
    where S1.Element == S2.Element,
          S1.Iterator == S2.Iterator {...}
```

我们当时指出，`sameElt()` 与 `sameEltAndIter()` 有相同的 generic signature，而 `sameIter()` 与它俩不同。假设我们按上面写的顺序依次类型检查这些声明：

1. 我们用 `sameElt()` 的 requirement 构造一台 minimization machine。这里有两条到 `Sequence` 的 conformance requirement，所以得先构造 `Sequence` 的 protocol machine。而 `Sequence` 又声明了一条到 `IteratorProtocol` 的 associated conformance requirement，所以我们还得构造 `IteratorProtocol` 的 protocol machine。
2. 一旦拿到 `sameElt()` 的 generic signature，我们就在 rewrite context 里把这个 generic signature 与这台 minimization machine 关联起来。类型检查 `sameElt()` 函数体时我们会对这个 generic signature 发起查询，这时复用的就是刚才建好的那台 minimization machine。
3. 接下来我们用 `sameIter()` 的 requirement 构造一台 minimization machine。这次我们从已经建好的 `Sequence` 与 `IteratorProtocol` 两台 protocol machine 导入规则，省掉了一些工作。我们拿到新的 generic signature，并把它 install 进 rewrite context。
4. 最后，我们构造一台 minimization machine 来建 `sameEltAndIter()` 的 generic signature。我们得到的 generic signature 与 `sameIter()` 的相同，而 rewrite context 里已经有它的 query machine 了。于是我们把这台新的 minimization machine 丢弃。

如果传入 frontend flag `-debug-requirement-machine=timers`，就能实时看到这一切发生：

```
$ swiftc three.swift -Xfrontend -debug-requirement-machine=timers
+ started InferredGenericSignatureRequest @ three.swift:1:6
| + started getRequirementMachine() [ Sequence ]
| | + started getRequirementMachine() [ IteratorProtocol ]
| | + finished getRequirementMachine() in 21us: [ IteratorProtocol ]
| + finished getRequirementMachine() in 61us: [ Sequence ]
+ finished InferredGenericSignatureRequest in 204us:
<S1, S2 where S1 : Sequence, S2 : Sequence, S1.Element == S2.Element>
+ started InferredGenericSignatureRequest @ three.swift:4:6
+ finished InferredGenericSignatureRequest in 88us:
<S1, S2 where S1 : Sequence, S2 : Sequence, S1.Iterator == S2.Iterator>
+ started InferredGenericSignatureRequest @ three.swift:7:6
+ finished InferredGenericSignatureRequest in 78us:
<S1, S2 where S1 : Sequence, S2 : Sequence, S1.Iterator == S2.Iterator>
```

更多 Requirement Machine 的调试 flag 见本章 Debugging Flags 一节。

**例.** 若 `P` 是任意 protocol，那么 protocol generic signature `<Self where Self: P>` 的 query machine 特别好建：我们取 `P` 的 protocol machine、以及 `P` 所依赖的全部 protocol 的 protocol machine，把它们的 local rule 全收集起来，然后为 $[\texttt{Self: P}]$ 添一条 local rule 就行了。

### Circularity.

如果我们遇到某个 type parameter 同时受一条 conformance requirement 和一条 concrete same-type requirement 约束——比如 $[\texttt{T: P}]$ 与 $[\texttt{T == X}]$，其中 `X` 是遵循 `P` 的 concrete type——我们可能要在这个 conformance 里查一个或多个 type witness。type witness 的投影会调用 type substitution，而后者又可能发起 generic signature query。如果这样递归回到我们此刻正在构造的那台 query machine，我们就答不上这个查询了，于是只好报一个 fatal error 然后放弃。

### Summary.

这四种机器对应「domain」（generic signature 还是 requirement signature）与「purpose」（查询一个已有实体，还是构建一个该类型的新实体）的四种组合：

| domain ＼ purpose | 查询已有实体 | 构建新实体 |
|---|---|---|
| generic signature | **Query machine** | **Minimization machine** |
| requirement signature | **Protocol machine** | **Protocol minimization machine** |

注意，protocol machine 是 query machine 的 protocol 版本，protocol minimization machine 是 minimization machine 的 protocol 版本。第一列的机器归 rewrite context 所有；第二列的机器生命期是临时的，但一旦被 install 进 rewrite context，就能转变成第一列里对应的那一种。

### History.

接着 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)）（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)）的 The Archetype Builder 一节那段历史速写往下讲：Requirement Machine 随 Swift 5.6 发布，当时只用于 generic signature query。requirement minimization 在 Swift 5.7 里被重新实现，旧逻辑保留在一个 flag 后面。`GenericSignatureBuilder` 随后在 Swift 5.8 中被彻底移除。

## Protocol Components

本节细看 generic signature 与 protocol 是怎么依赖别的 protocol 的，并把 protocol machine 的工作方式完整讲清楚。我们先回到 **protocol dependency graph**，它的定义在 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）里。回忆一下：顶点是 protocol 声明，边是 associated conformance requirement。也就是说，若 $[\texttt{Self.U: P}]_\texttt{Q}$ 是某条 associated conformance requirement，我们定义：

$$\operatorname{src}([\texttt{Self.U: Q}]_\texttt{P}) := \texttt{P},$$

$$\operatorname{dst}([\texttt{Self.U: Q}]_\texttt{P}) := \texttt{Q}.$$

> 译注：原书这段正文里写的是 $[\texttt{Self.U: P}]_\texttt{Q}$，而紧接着的两个公式写的却是 $[\texttt{Self.U: Q}]_\texttt{P}$，两者的下标与 protocol 恰好互换；`conformance-paths.tex` 里 protocol dependency graph 的定义用的是后一种写法（「$[\texttt{Self.U: Q}]_\texttt{P}$ 的 source vertex 是 `P`、destination vertex 是 `Q`」），可见正文那处是笔误。此处照译原文，语义以公式（即 `conformance-paths.tex` 的定义）为准。

这个概念还有另一种用 derived requirement 表述的定义。

**定义.** 如果我们能从 protocol generic signature $G_\texttt{P}$ 推导出一条到 `Q` 的 conformance——也就是说，对某个 type parameter `Self.U` 有 $G_\texttt{P} \vdash [\texttt{Self.U: Q}]$——我们就说 protocol `P` **依赖**（depends on）protocol `Q`。这个关系成立时记作 $\texttt{P} \prec \texttt{Q}$。`P` 的 **protocol dependency** 集合，就是所有满足 $\texttt{P} \prec \texttt{Q}$ 的 protocol `Q` 组成的集合。

**命题.** 关系 $\prec$ 是 reflexive 与 transitive 的。

**证明.** 先看第一部分。设 `P` 是任意 protocol。我们总能借 $G_\texttt{P}$ 的 explicit requirement $[\texttt{Self: P}]$ 推出 $G_\texttt{P} \vdash [\texttt{Self: P}]$，因此 $\texttt{P} \prec \texttt{P}$，即 $\prec$ 是 reflexive 的。

再看第二部分。设 `P`、`Q`、`R` 是满足 $\texttt{P} \prec \texttt{Q}$ 与 $\texttt{Q} \prec \texttt{R}$ 的 protocol。按定义，对某两个 type parameter `Self.U` 与 `Self.V` 有 $G_\texttt{P} \vdash [\texttt{Self.U: Q}]$ 与 $G_\texttt{Q} \vdash [\texttt{Self.V: R}]$。由 `building-generic-signatures.tex` 的 Formal substitution 引理，$G_\texttt{P} \vdash [\texttt{Self.U.V: R}]$，其中 `Self.U.V` 是把 `Self.V` 里的 `Self` 换成 `Self.U` 得到的 type parameter。因此 $\texttt{P} \prec \texttt{R}$。

事实上，$\prec$ 恰好就是 protocol dependency graph 上的 reachability relation。

**命题.** 设 `P` 与 `Q` 是 protocol。那么 $\texttt{P} \prec \texttt{Q}$ 当且仅当在 protocol dependency graph 里 `Q` 可由 `P` 沿某条 path 到达。

**证明.** protocol dependency graph 里一条非空 path 由它走过的边决定，也就是由一串 associated conformance requirement 决定。这串 requirement 有一个性质：每一条 associated requirement 都必须声明在前一条 requirement 所点名的那个 protocol 里。同样地，当一个推导里出现一串连续的 **AssocConf** 步骤时，各步所引用的 requirement 序列也服从同一条相容性条件。

$(\Leftarrow)$ 假设 $\texttt{P} \prec \texttt{Q}$。按定义，存在 type parameter `Self.U` 使得 $G_\texttt{P} \vdash [\texttt{Self.U: Q}]$。由 `conformance-paths.tex` 的 conformance path 定理，我们能找到一个 type parameter $\texttt{Self.U}^\prime$，使得 $G_\texttt{P} \vdash [\texttt{Self.U} == \texttt{Self.U}^\prime]$，并且 $[\texttt{Self.U}^\prime\texttt{: Q}]$ 的推导有一种特别简单的形态：它以 explicit requirement $[\texttt{Self: P}]$ 的一个 **Conf** 步骤开头，随后是一连串 **AssocConf** 推导步骤。由前面那段说明，这串步骤给出了 protocol dependency graph 里一条从 `P` 到 `Q` 的 path。

$(\Rightarrow)$ 假设 protocol dependency graph 里存在一条从 `P` 到 `Q` 的 path。看它走过的边的序列。我们这样构造一个 $G_\texttt{P}$ 中某条 conformance requirement 的推导：先为 explicit requirement $[\texttt{Self: P}]$ 走一个 **Conf** 步骤，再为 path 里走过的每条边各加一个 **AssocConf** 步骤。由前面那段说明，这是一个合法的推导。于是我们看到对某个 type parameter `Self.U` 有 $G_\texttt{P} \vdash [\texttt{Self.U: Q}]$，即 $\texttt{P} \prec \texttt{Q}$。

> 译注：原书这两段的方向标记写反了。命题的形式是「$\texttt{P} \prec \texttt{Q}$ 当且仅当 `Q` 从 `P` 可达」，因此「假设 $\texttt{P} \prec \texttt{Q}$、证出一条 path」那一段该标 $(\Rightarrow)$，「假设有一条 path、证出 $\texttt{P} \prec \texttt{Q}$」那一段该标 $(\Leftarrow)$，原书恰好互换了。此处照译原文的标记，两段的实际内容不受影响。

### Recursive conformances.

在 `conformance-paths.tex` 的 Recursive Conformances 一节里我们说过，如果一条 conformance requirement 是 protocol dependency graph 里某个环的一部分，就称它是 **recursive** 的。下面的 Protocol component demonstration 这份代码清单给出了一些 protocol 声明。这个例子的 protocol dependency graph 含有一个环：

```
                 Top
              ↙       ↘
        ┌ ─ ─ ─ ─ ─ ─ ─ ─ ┐
        │   Foo  ⇄  Bar   │
        └ ─ ─ ─ ─ ─ ─ ─ ─ ┘
            ↓         ↓
           Baz       Fiz
              ↘     ↙
                 Bot
```

> 译注：原书此处是一张 TikZ 图（正文右侧的 wrapfigure），虚线框圈住 `Foo` 与 `Bar` 表示它们构成一个 strongly connected component，这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

`Foo` 与 `Bar` 各自通过一对相互递归的 associated conformance requirement 指向对方。按我们目前的描述，不先建出其中一台 protocol machine 就建不出另一台：这是一个循环依赖。

我们的解法是把 protocol 分组成 **protocol component**——在这个例子里，`Foo` 与 `Bar` 属于同一个 component。一台 protocol machine 描述的是整个 protocol component，它的 local rule 包含该 component 中所有 protocol 的 associated requirement。如果我们看的是 protocol **component** 之间而非 **protocol** 之间的依赖，得到的就是一个有向**无环**图。为了理解这些 component 是怎么形成的，我们先抽象地考察有向图。

**代码清单（Protocol component demonstration）.**

```swift
protocol Top {
  associatedtype A: Foo
  associatedtype B: Bar
}

protocol Foo {
  associatedtype A: Bar
  associatedtype B: Baz
}

protocol Bar {
  associatedtype A: Foo
  associatedtype B: Fiz
}

protocol Baz {
  associatedtype A: Bot
}

protocol Fiz {
  associatedtype A: Bot
}

protocol Bot {}
```

### Strongly connected components.

设 $(V, E)$ 是任意有向图，$\prec$ 是它的 reachability relation，即当存在一条以 $x$ 为起点、$y$ 为终点的 path 时 $x \prec y$。如果 $x \prec y$ 与 $y \prec x$ 同时成立，我们就说 $x$ 与 $y$ 是 **strongly connected** 的；下文把这个关系记作 $x \equiv y$。它是一个 equivalence relation：

- （Reflexivity）若 $x \in V$，则经由 $x$ 处的 empty path 有 $x \prec x$，于是 $x \equiv x$。
- （Symmetry）若 $x \equiv y$，则由 $\equiv$ 的定义即得 $y \equiv x$。
- （Transitivity）若 $x \equiv y$ 且 $y \equiv z$，则特别地有 $x \prec y$ 与 $y \prec z$，由 $\prec$ 的传递性得 $x \prec z$。同理也有 $y \prec x$ 与 $z \prec y$，故 $z \prec x$。因此 $x \equiv z$。

$\equiv$ 的等价类称为 $(V, E)$ 的 **strongly connected component**。于是我们可以构造一个新图，它的**顶点**就是原图的 strongly connected component；当且仅当第一个 component 里的某个顶点在原图中经一条 path 连到第二个 component 里的另一个顶点时，这两个 component 之间连一条边。（这是 well-defined 的，因为若 $x_1 \equiv x_2$ 且 $y_1 \equiv y_2$，则 $x_1 \prec y_1$ 当且仅当 $x_2 \prec y_2$。）strongly connected component 构成的图总是无环的。进一步地，如果原图本身就是无环的，那么 $x \equiv y$ 当且仅当 $x$ 与 $y$ 其实是同一个顶点；换句话说，一个有向无环图的 strongly connected component 图与原图同构。

我们把 **protocol component graph** 定义为 protocol dependency graph 的 strongly connected component 图。上面那份 Protocol component demonstration 的 protocol component graph 如下：

```
      {Top}
        ↓
   {Foo, Bar}
    ↙       ↘
 {Baz}     {Fiz}
    ↘       ↙
      {Bot}
```

> 译注：原书此处是一张 TikZ 图（正文左侧的 wrapfigure），这里用 ASCII 图转述；图的原貌见官方 PDF 对应章节。

它看起来几乎和原来的 protocol dependency graph 一样，只是我们把 `Foo` 与 `Bar` 收缩成了一个顶点。protocol component graph 虽然总是无环的，但一般情况下它既不是 tree 也不是 forest；正如例子所示，从 `Top` 到 `Bot` 有两条不同的 path，所以 component 之间可以共享「孩子」。为了不导入重复的规则，我们必须对每台下游 protocol machine 只访问一次，并且只从每台机器里取 **local** rule。

有一个调试 flag 会在每个 strongly connected component 形成时把它打印出来。拿我们的例子试试：

```
$ swiftc protocols.swift -Xfrontend -debug-requirement-machine=protocol-dependencies
Connected component: [Bot]
Connected component: [Fiz]
Connected component: [Baz]
Connected component: [Bar, Foo]
Connected component: [Top]
```

frontend flag `-debug-requirement-machine=timers` 也会记录 protocol component 的构造过程。缩进层次跟随 protocol machine 的递归构造：

```
+ started RequirementSignatureRequest [ Top ]
| + started RequirementSignatureRequest [ Bar Foo ]
| | + started RequirementSignatureRequest [ Fiz ]
| | | + started RequirementSignatureRequest [ Bot ]
| | | + finished RequirementSignatureRequest in 46us: [ Bot ]
| | + finished RequirementSignatureRequest in 81us: [ Fiz ]
| | + started RequirementSignatureRequest [ Baz ]
| | + finished RequirementSignatureRequest in 21us: [ Baz ]
| + finished RequirementSignatureRequest in 179us: [ Bar Foo ]
+ finished RequirementSignatureRequest in 211us: [ Top ]
```

### Tarjan's algorithm.

我们用 Robert Tarjan 发明的一个算法（Tarjan 1972，《Depth-First Search and Linear Graph Algorithms》，*SIAM Journal on Computing* 1(2): 146–160）来找出 protocol dependency graph 的 strongly connected component。具体来说，我们给这些 strongly connected component 编号、给每个顶点分配一个 component ID，并建一张从 component ID 到其所含顶点列表的表。

Tarjan 算法是增量式的。我们不需要事先把整张输入图建出来——那会逼我们先把每个 imported module 里的每个 protocol 都反序列化一遍。当被要求给出某个顶点的 component ID 时，我们先看这个顶点是否已经分配过 component ID，若已分配就立刻返回。若尚未分配，那么这个顶点必定属于一个与此前发现的所有 component 都不同的 component；我们于是访问从该顶点可达的所有顶点，并在这个过程中逐步形成各个 connected component。

回忆一下：若 $v \in V$ 是一个顶点，而存在一条边 $e \in E$ 满足 $\operatorname{src}(e)=v$ 且 $\operatorname{dst}(e)=w$，则称 $w \in V$ 是 $v$ 的一个 **successor**。为了找出 $v$ 的 strongly connected component，Tarjan 算法执行一次 **depth-first search**：给定 $v$，我们先递归访问 $v$ 的第一个尚未访问过的 successor，再访问它的 successor，如此深入下去，然后才回头处理 $v$ 的下一个 successor。（对比 `conformance-paths.tex` 的 The Conformance Path Graph 一节里用来寻找 conformance path 的 **breadth-first search**：那里我们先访问 $v$ 的全部 successor，再往它们的 successor 深入。）

Tarjan 算法要求我们以「把给定顶点映射到它的 successor 列表」的回调形式给出输入图。这使得图可以被增量地探索。在我们这里，一个 protocol 的 successor 由求值 **protocol dependencies request** 得到，其实现如下：

- 如果这个 protocol 声明在 main module 内，我们求值 **structural requirements request**，收集该 protocol 源码里写下的 associated conformance requirement 右侧出现的那些 protocol。

- 如果这个 protocol 来自 serialized module，我们求值 **requirement signature request**，收集该 protocol 的 associated requirement 右侧出现的那些 protocol。

我们按访问顺序给顶点编号：在访问顶点 $v$ 的 successor 之前，把一个计数器的当前值赋给 $v$。赋给顶点 $v$ 的这个值记作 $\texttt{NUMBER}(v)$。遍历时只要检查 $\texttt{NUMBER}(v)$ 是否已设置，就能判断某个顶点此前是否访问过。

我们回到 Protocol component demonstration 的 protocol dependency graph。一次从 `Top` 出发的 depth-first search 给出下面这个顶点编号，第一个顶点被赋为 1：

```
                  1                （Top）
              ↙       ↘
             2    ⇄    3           （Foo、Bar）
             ↓         ↓
             6         4           （Baz、Fiz）
              ↘     ↙
                  5                （Bot）
```

> 译注：原书此处是一张 TikZ 图（正文右侧的 wrapfigure，与上面那张 protocol dependency graph 同形，只是把 protocol 名换成了访问序号），这里用 ASCII 图转述，并在括号里补回各顶点对应的 protocol 名以便对照；图的原貌见官方 PDF 对应章节。

这里整张图最终都能从 1 到达；更一般地，我们得到的是从初始顶点可达的那个 subgraph 的编号。

访问顶点 $v$ 时，我们逐一查看每条满足 $\operatorname{src}(e)=v$ 的边 $e \in E$。设 $\operatorname{dst}(e)$ 是另一个顶点 $w$；我们看 $\texttt{NUMBER}(w)$ 的状态，把边 $e$ 归为 tree edge、ignored edge、frond 或 cross-link 之一。

若 $\texttt{NUMBER}(w)$ 尚未设置，我们说 $e$ 是一条 **tree edge**；这些 tree edge 定义了本次搜索所探索的那个 subgraph 的一棵 **spanning tree**。否则，$w$ 是我们在搜索中更早见过的，边 $e$ 属于其余三种之一。若 $\texttt{NUMBER}(w) \geq \texttt{NUMBER}(v)$（取等号对应一条从 $v$ 指向自身的边，这是允许的），那么任何从 $v$ 到 $w$ 的 path 都必须经过 $v$ 与 $w$ 在 spanning tree 中的某个公共祖先。此时我们说 $e$ 是一条 **ignored edge**，因为 $e$ 不可能产生任何新的 strongly connected component。最后两种出现在 $\texttt{NUMBER}(w) < \texttt{NUMBER}(v)$ 的时候：若 $w$ 同时还是 $v$ 在 spanning tree 中的祖先，我们说 $e$ 是一条 **frond**；否则 $e$ 是一条 **cross-link**。（后两种的区分在 Tarjan 的正确性证明里有作用，但我们马上会看到，算法本身对 frond 与 cross-link 一视同仁。）

如果输入图是一个 forest，那么每条边都是 tree edge；我们访问的 subgraph 就是它自身的 spanning tree。如果输入图是一个有向**无环**图，那么所有边要么是 tree edge 要么是 ignored edge，于是同样地，任何两个不同的顶点都不可能 strongly connected。Tarjan 的洞见在于：要理解图中那些非平凡的 strongly connected component，看 frond 与 cross-link 就够了。

我们这个例子的边分类如下。原书用四种箭头样式区分四类边，这里改用四组 ASCII 记号：

```
 ═══▶   tree edge（原书画成粗箭头）
 ╌╌╌▶   ignored edge（原书画成虚线箭头）
 ───▶   frond（原书画成细箭头）
 ──▶▶   cross-link（原书画成双箭头头）
```

> 译注：原书此处随正文插了四张各只画一支箭头的行内 TikZ 图例，这里合并成一张 ASCII 对照表转述；图的原貌见官方 PDF 对应章节。

用这套记号画出的边分类如下，粗箭头构成的就是本次搜索的 spanning tree：

```
                  1
              ↙       ↘
             2    ⇄    3
             ↓         ↓
             6         4
              ↘     ↙
                  5

 1 ═══▶ 2    tree edge      （Top → Foo）
 1 ╌╌╌▶ 3    ignored edge   （Top → Bar）
 2 ═══▶ 3    tree edge      （Foo → Bar）
 3 ───▶ 2    frond          （Bar → Foo）
 2 ═══▶ 6    tree edge      （Foo → Baz）
 3 ═══▶ 4    tree edge      （Bar → Fiz）
 6 ──▶▶ 5    cross-link     （Baz → Bot）
 4 ═══▶ 5    tree edge      （Fiz → Bot）
```

> 译注：原书此处是一张 TikZ 图（正文左侧的 wrapfigure），四类边全靠线型区分。ASCII 无法稳定还原这四种线型，这里保留图形轮廓，另附一张逐边标注类型的邻接表；图的原貌见官方 PDF 对应章节。

算法的正确性依赖 depth-first search 的下述性质：任何两个 strongly connected 的顶点在 spanning tree 中都有一个公共祖先，因此每个 strongly connected component 都在 spanning tree 里诱导出一棵**子树**。我们把一个 strongly connected component 的 **root** 定义为这棵子树的根。为了找到一个 strongly connected component 的 root，我们再给每个顶点 $v$ 关联一个整数，记作 $\texttt{LOWLINK}(v)$。这个值的定义使得：若 $\texttt{LOWLINK}(v)=\texttt{NUMBER}(v)$，则 $v$ 是某个 strongly connected component 的 root。在我们的例子里，除「$3$」之外所有 $v$ 都有 $\texttt{LOWLINK}(v)=\texttt{NUMBER}(v)$；而 $\texttt{LOWLINK}(3)=\texttt{NUMBER}(2)$，因为「$2$」与「$3$」在同一个 strongly connected component 里，且该 component 以「$2$」为 root。

我们在访问 $v$ 的 successor 的过程中反复更新 $\texttt{LOWLINK}(v)$，访问完后再检查是否有 $\texttt{LOWLINK}(v)=\texttt{NUMBER}(v)$。若成立，我们就发现了一个新的 strongly connected component！我们维护一个下推**栈**，其维护方式保证在这一刻，该 strongly connected component 恰好由栈顶若干个顶点构成。

我们在访问一个顶点的 successor 之前把它压栈，但只在形成新的 strongly connected component 时才弹栈；一个顶点会一直留在栈上，直到我们访问到它所在 component 的 root 为止。因此，尽管压栈与弹栈看上去不配对，每个压入的顶点最终都会被弹出。

算法还需要一个廉价的办法来判断某个顶点当前是否在栈上。我们再给每个顶点 $v$ 关联一份状态：一个 bit，记作 $\texttt{ONSTACK}(v)$，在 $v$ 被压栈时置位、被弹出时清零。

**算法（Tarjan's algorithm）.** 输入是一个顶点 $v$，以及一个回调——它能输出从 $v$ 可达的任意顶点的 successor 顶点。返回时，$v$ 已被分配了一个 component ID。算法更新两张表：给每个顶点分配一个 component ID，给每个 component ID 分配一张成员顶点列表。此外还用到一个栈，以及两个全局递增计数器：下一个未使用的顶点 ID，和下一个 component ID。

1. （Memoize）若 $v$ 已经分配过 component ID，返回这个 component ID，用它就能查到该 component 的成员。
2. （Invariant）否则，确认 $\texttt{NUMBER}(v)$ 尚未设置。如果它已设置而 $v$ 却没有 component ID，说明我们做了一次非法的 re-entrant 调用（见下文）。
3. （Visit）把 $\texttt{NUMBER}(v)$ 设为下一个顶点 ID。置 $\texttt{LOWLINK}(v) \leftarrow \texttt{NUMBER}(v)$。置 $\texttt{ONSTACK}(v) \leftarrow \textrm{true}$。把 $\texttt{NUMBER}(v)$ 压栈。
4. （Successors）对 $v$ 的每个 successor $w$：
   1. 若 $\texttt{NUMBER}(w)$ 未设置，这是一条 tree edge。对 $w$ 递归调用本算法，然后置 $\texttt{LOWLINK}(v) \leftarrow \min(\texttt{LOWLINK}(v), \texttt{LOWLINK}(w))$。
   2. 若 $\texttt{NUMBER}(w) \geq \texttt{NUMBER}(v)$，这是一条 ignored edge；什么也不做。
   3. 否则 $\texttt{NUMBER}(w) < \texttt{NUMBER}(v)$，这是一条 frond 或 cross-link。若 $\texttt{ONSTACK}(w)$ 为真，置 $\texttt{LOWLINK}(v) \leftarrow \min(\texttt{LOWLINK}(v), \texttt{NUMBER}(w))$。
5. （Not root?）若 $\texttt{LOWLINK}(v) \neq \texttt{NUMBER}(v)$，返回。
6. （Root）把下一个未使用的 component ID 分配给 $v$，并把 $v$ 加进这个 component ID。
7. （Add vertex）从栈里弹出一个顶点 $v^\prime$（此刻栈必定非空），清零 $\texttt{ONSTACK}(v^\prime)$。把 $v^\prime$ 加进 $v$ 的 component，并把该 component ID 关联到 $v^\prime$。
8. （Repeat）若栈非空，回到第 7 步。否则返回。

> 译注：第 8 步的终止条件与算法本身矛盾：照字面执行会把整个栈掏空，于是在我们这个例子里，第一次发现 root（顶点「5」/`Bot`）时栈上的 1、2、3、4、5 会被一并塞进同一个 component，这与正文刚说过的「一个顶点会一直留在栈上，直到我们访问到它所在 component 的 root」以及调试输出里的五个 component 都对不上。编译器实现（`lib/AST/RequirementMachine/RewriteContext.cpp` 的 `getProtocolComponentRec()`）用的是 `do { ... } while (depProto != proto);`，即**弹到把 $v$ 自己弹出来为止**；按这个条件，第 6 步给 $v$ 的那次「加进 component」也会在第 7 步弹出 $v$ 时重复一遍。此处照译原文，语义以实现为准。

最外层的递归调用返回后，栈总是空的。注意，这个算法虽然是递归的，却不是可重入的；特别是，取一个顶点的 successor 这件事本身不得触发同一批 strongly connected component 的计算。这由第 2 步来保证。在我们这里之所以可能发生，是因为取一个 protocol 的 successor 要做 type resolution；实践中这应该极难碰到，所以为简单起见我们直接报 fatal error 退出编译器，而不试图恢复。

### Protocol components.

我们在 rewrite context 里维护两张表：

1. 一张从 protocol 声明到 **protocol node** 的映射。

   `P` 的 protocol node 存着 Tarjan 算法关联到 `P` 上的那份状态：$\texttt{NUMBER}(\texttt{P})$、$\texttt{LOWLINK}(\texttt{P})$、$\texttt{ONSTACK}(\texttt{P})$，以及 `P` 的 component ID。

2. 一张从 component ID 到 **protocol component** 的映射。

   一个 protocol component 是一张 protocol 声明列表外加一台 requirement machine。后者要么是一台由用户手写 requirement 构造的 protocol minimization machine，要么是一台由这些 protocol 的 requirement signature 构造的 protocol machine。这台 requirement machine 是在首次需要时惰性构造的，而不是在 Tarjan's algorithm 形成 component 的那一刻构造的。

### Generic signatures.

「一个 protocol 对另一个 protocol 有依赖关系」这个想法可以推广到「一个 generic signature 依赖一个 protocol」。一个 generic signature 的 protocol dependency，就是那些出现在 derived conformance requirement 右侧的 protocol。

**定义.** 如果我们能从 generic signature $G$ 推导出一条到 protocol `P` 的 conformance——也就是说，对某个 type parameter `T` 有 $G \vdash [\texttt{T: P}]$——我们就说 $G$ 对 `P` 有一条 **protocol dependency**，记作 $G \prec \texttt{P}$。generic signature $G$ 的 **protocol dependency 集合**，就是所有满足 $G \prec \texttt{P}$ 的 protocol `P` 组成的集合。

$\prec$ 的这种新形式并不是 `generic-signatures.tex` 里定义的那种意义上的二元关系，因为两个操作数来自不同的集合。不过它仍然是传递的：$G \prec \texttt{P}$ 与 $\texttt{P} \prec \texttt{Q}$ 合起来蕴含 $G \prec \texttt{Q}$。注意 $\prec$ 的两种定义通过 protocol generic signature 联系起来：$G_\texttt{P} \prec \texttt{Q}$ 当且仅当 $\texttt{P} \prec \texttt{Q}$。

现在，考虑出现在我们的 generic signature $G$ 的那些 **explicit** conformance requirement 右侧的 protocol；类比 protocol dependency graph 里一个 protocol 的 successor，我们把它们称作 $G$ 的 **successor**。如果我们把从 $G$ 的 successor 出发经由各条 path 可达的所有 protocol 都算进来，得到的就是 $G$ 的完整 protocol dependency 集合。

本节最后给出为一台新 requirement machine 收集 imported rule 的算法。我们找出从某个初始集合可达的全部 protocol，算出它们的 strongly connected component，为每个 component 惰性地构造一台 protocol machine，最后从每台 requirement machine 里收集 local rule。

**算法（Import rules from protocol components）.** 输入是一张 protocol 列表，它们是某个 generic signature 或 protocol 的直接 successor。输出一张 imported rule 列表。

1. （Initialize）初始化一个 worklist，把所有输入 protocol 加进去。初始化一个空的已访问 protocol 集合 $S$。初始化一个空的 requirement machine 集合 $M$（按指针相等去重）。
2. （Check）若 worklist 为空，转到第 8 步。
3. （Next）否则，从 worklist 里取出下一个 protocol `P`。若 $\texttt{P} \in S$，回到第 2 步；否则置 $S \leftarrow S \cup \{\texttt{P}\}$。
4. （Component）用 Tarjan's algorithm 算出 `P` 的 component ID。
5. （Machine）设 $m$ 是这个 protocol component 的 requirement machine，必要时先把它创建出来。若 $m \notin M$，置 $M \leftarrow M \cup \{m\}$。
6. （Successors）把 `P` 的每条 protocol dependency 加进 worklist。
7. （Loop）回到第 1 步。
8. （Collect）从每个 $m \in M$ 收集 local rule，返回。

> 译注：第 7 步写的是「回到第 1 步」，但第 1 步是 Initialize——回到那里会把 worklist、$S$、$M$ 全部清空重来，算法永不终止。按第 2、3 两步的写法，这里应当是回到第 2 步（Check）。此处照译原文，语义以「回到第 2 步」为准。

等到 `completion.tex` 里讨论 Knuth-Bendix completion procedure 时，我们还会再遇到 protocol dependency graph。completion 要寻找规则两两之间的 **overlap**，而我们会用 protocol dependency graph 来削减它的工作量——办法是证明「两条规则都是 imported 的那些组合」根本不必考虑。

一个 protocol component 永远被当作不可分割的整体来处理；举个例子，`minimization.tex` 里我们会看到，requirement minimization 必须同时考虑一个 component 里的所有 protocol 才能得到正确结果。

## Debugging Flags

我们已经见过 `-debug-requirement-machine` flag 的两个例子：

```
-debug-requirement-machine=timers
-debug-requirement-machine=protocol-dependencies
```

更一般地，这个 flag 的参数是一张逗号分隔的选项列表，可选项如下：

- `timers`：本章。
- `protocol-dependencies`：本章 Protocol Components 一节。
- `simplify`：`symbols-terms-and-rules.tex` 的 The Normal Form Algorithm 一节。
- `add`、`completion`：`completion.tex`。
- `concrete-unification`、`conflicting-rules`、`property-map`：`property-map.tex`。
- `concretize-nested-types`、`conditional-requirements`：`property-map.tex` 的 Concrete Conformances 一节。
- `concrete-contraction`：`minimization.tex` 的 Concrete Contraction 一节。
- `homotopy-reduction`、`homotopy-reduction-detail`、`propagate-requirement-ids`：`minimization.tex` 的 Homotopy Reduction 一节。
- `minimal-conformances`、`minimal-conformances-detail`：`minimization.tex` 的 Conformance Minimization 一节。
- `minimization`、`redundant-rules`、`redundant-rules-detail`、`split-concrete-equiv-class`：`minimization.tex` 的 Building Requirements 一节。

还有最后两个调试 flag。我们在 rewrite context 里维护了一些**直方图**。`-analyze-requirement-machine` flag 会在编译会话结束时把它们打印出来。做性能优化时这些数据会很有用：

- 按种类统计分配过的唯一 symbol 数（见 `symbols-terms-and-rules.tex` 的 Symbols 一节）。
- 按长度统计分配过的 term 数（见 `symbols-terms-and-rules.tex` 的 Terms 一节）。
- 关于 rule trie（见 `symbols-terms-and-rules.tex` 的 The Normal Form Algorithm 一节）与 property map trie（见 `property-map.tex`）的统计。
- 关于 minimal conformance 算法（见 `minimization.tex` 的 Conformance Minimization 一节）的统计。

`-dump-requirement-machine` flag 会在 completion procedure 跑之前与跑之后各打印一次每台 requirement machine。打印出来的表示包含一张 rewrite rule 列表、property map 以及所有 rewrite loop。读完 `symbols-terms-and-rules.tex` 之后，这些输出才会开始变得可读。

## Source Code Reference

关键源文件：

- `lib/AST/RequirementMachine/`

Requirement Machine 的实现对 `lib/AST/` 之外是私有的。编译器其余部分只能间接与它打交道：通过 `GenericSignature` 上的 generic signature query 方法（见 `generic-signatures.tex` 的 Source Code Reference 一节），以及各种用于构建新 generic signature 的 request（见 `building-generic-signatures.tex` 的 Source Code Reference 一节）。

### The Rewrite Context

关键源文件：

- `lib/AST/RequirementMachine/RewriteContext.h`
- `lib/AST/RequirementMachine/RewriteContext.cpp`

**`ASTContext`（class）**：单个 frontend 实例的全局单例。另见 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)）的 Source Code Reference 一节。

- `getRewriteContext()` 返回这个 frontend 实例的全局单例 `RewriteContext`。

**`rewriting::RewriteContext`（class）**：一个单例对象，负责管理 requirement machine 的构造、protocol component graph 的建立，以及 symbol 与 term 的唯一化分配。另见 `symbols-terms-and-rules.tex` 的 Source Code Reference 一节。

- `getRequirementMachine(CanGenericSignature)` 返回给定 generic signature 的 query machine，必要时先创建一台。
- `getRequirementMachine(ProtocolDecl *)` 返回包含给定 protocol 的那个 protocol component 的 protocol machine，必要时先创建一台。
- `getProtocolComponentImpl()` 是一个私有辅助函数，返回包含给定 protocol 的 protocol component。
- `getProtocolComponentRec()` 实现用于计算 strongly connected component 的 Tarjan's algorithm。
- `isRecursivelyConstructingRequirementMachine(CanGenericSignature)` 在我们当前正在为这个 generic signature 构造 query machine 时返回 true。
- `isRecursivelyConstructingRequirementMachine(ProtocolDecl *)` 在我们当前正在为给定 protocol 所在的 component 构造 protocol machine 时返回 true。这两个方法用于打破 associated type inference 里的 request cycle——否则可重入的构造会触发编译器里的一个断言。
- `installRequirementMachine(CanGenericSignature, std::unique_ptr<RequirementMachine>)` 接过一台 minimization machine，把它与给定签名关联起来。
- `installRequirementMachine(ProtocolDecl *, std::unique_ptr<RequirementMachine>)` 接过一台 protocol minimization machine，把它与给定 protocol 所在的 component 关联起来。

**`GenericSignatureImpl`（class）**：另见 `generic-signatures.tex` 的 Source Code Reference 一节。

- `getRequirementMachine()` 返回这个 generic signature 的 query machine，做法是请 rewrite context 产出一台，然后把结果缓存在 `GenericSignatureImpl` 实例自己的一个成员变量里。

  这个方法供 generic signature query 的实现使用；除此之外，编译器的其它地方不应该有理由伸手进 requirement machine 实例内部。

**`ProtocolDependenciesRequest`（class）**：一个 request evaluator request，计算从给定 protocol 的 associated conformance requirement 所引用到的全部 protocol。这些就是该 protocol 在 protocol dependency graph 里的 successor。

**`ProtocolDecl`（class）**：另见 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)）的 Source Code Reference 一节。

- `getProtocolDependencies()` 求值 `ProtocolDependenciesRequest`。

**`ProtocolInversesRequest`（class）**：一个 request evaluator request，枚举写在给定 protocol 及其 associated type 上的 inverse requirement。

**`ProtocolDecl`（class）**：另见 `declarations.tex` 的 Source Code Reference 一节。

- `getInverseRequirements()` 求值 `ProtocolInversesRequest`。

**`rewriting::RequirementMachine`（class）**：一张 rewrite rule 列表加一张 property map。另见 `symbols-terms-and-rules.tex` 与 `property-map.tex` 的 Source Code Reference 两节。初始化一台 requirement machine 的入口，由 rewrite context 与各种 request 调用：

- `initWithGenericSignature()` 从一个已有 generic signature 的 requirement 初始化一台新的 query machine。
- `initWithWrittenRequirements()` 在构建新 generic signature 时，从用户手写的 requirement 初始化一台新的 minimization machine。
- `initWithProtocolSignatureRequirements()` 从一个 protocol component 中每个 protocol 的 requirement signature 初始化一台新的 protocol machine。
- `initWithProtocolWrittenRequirements()` 从一个 protocol component 中每个 protocol 里用户手写的 requirement 初始化一台新的 protocol minimization machine。

把一台 requirement machine 拆开看：

- `getRewriteSystem()` 返回 `RewriteSystem`（见 `symbols-terms-and-rules.tex` 的 Source Code Reference 一节）。
- `getPropertyMap()` 返回 `PropertyMap`（见 `property-map.tex` 的 Source Code Reference 一节）。

杂项：

- `verify()` 检查各种不变量。我们在构造完这台 requirement machine 之后调用它。
- `dump()` 转储 `RewriteSystem` 与 `PropertyMap`。

### Requests

关键源文件：

- `lib/AST/RequirementMachine/RequirementMachineRequests.cpp`

下列 request 的求值函数实现在 Requirement Machine 里。

**`InferredGenericSignatureRequest::evaluate`（method）**：从源码里写下的 requirement 构建新 generic signature 的求值函数。构造一台 minimization machine。

这最终实现了 `GenericContext::getGenericSignature()` 方法；见 `generic-signatures.tex` 的 Source Code Reference 一节。

**`AbstractGenericSignatureRequest::evaluate`（method）**：从一张 generic parameter 列表与一张 requirement 列表构建新 generic signature 的求值函数。构造一台 minimization machine。这最终实现了 `buildGenericSignature()` 函数；见 `building-generic-signatures.tex` 的 Source Code Reference 一节。

**`RequirementSignatureRequest::evaluate`（method）**：取得一个 protocol 的 requirement signature 的求值函数。它要么把 requirement signature 反序列化出来，要么从用户手写的 requirement 构造一台 protocol minimization machine，用它建出一个新的 requirement signature。这最终实现了 `ProtocolDecl::getRequirementSignature()` 方法；见 `generic-signatures.tex` 的 Source Code Reference 一节。

### Debugging

关键源文件：

- `lib/AST/RequirementMachine/Debug.h`
- `lib/AST/RequirementMachine/Histogram.h`

**`rewriting::RewriteContext`（class）**

- `RewriteContext()`：rewrite context 的构造函数把 `-debug-requirement-machine` flag 的字符串值按逗号切成若干 token，再把每个 token 映射到 `DebugFlags` 枚举的一个元素。
- `getDebugFlags()` 返回 `DebugFlags` 枚举。
- `beginTimer()` 启动一个由给定字符串标识的计时器，并记一条日志。
- `endTimer()` 结束一个由给定字符串标识的计时器，并记一条日志。必须与对 `beginTimer()` 的调用配对。

**`rewriting::DebugFlags`（enum class）**：一个调试 flag 的 `OptionSet`，用来控制 Requirement Machine 打印的各类调试输出。

**`rewriting::Histogram`（class）**：一个把采样点汇总成直方图的工具类。每张直方图有固定数量的桶、一个初始值，以及一个「溢出」桶。采样点到桶的映射办法是减去初始值再与总桶数比较；若结果超过总桶数，就记进「溢出」桶。

如果编译器带 `-analyze-requirement-machine` frontend flag 调用，`RequirementMachine` 实例里的各张直方图会在编译器退出时打印出来。

- `Histogram(unsigned size, unsigned start)` 创建一张新的直方图。
- `add(unsigned)` 往直方图里记一个采样点。
- `dump()` 把直方图打印成 ASCII 图。

---

> 译自 `docs/Generics/chapters/basic-operation.tex`（swift-6.4.0-RELEASE，`c9d2f522c02`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
