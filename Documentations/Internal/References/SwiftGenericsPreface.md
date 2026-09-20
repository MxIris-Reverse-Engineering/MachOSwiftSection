# Preface（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/preface.tex`（《Compiling Swift Generics》一书的「Preface」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本篇是全书前言，给出五个部分、二十来章的导览，因而也是本项目逐章中译的天然索引——下面每提到一章，都顺带写出它在源码树里的文件名（`docs/Generics/chapters/` 下的 `<name>.tex`），照着就能找到原文。对本库而言，这本书讲的是编译器怎么把 generic 代码编成二进制，而本库做的是反方向的事：从 Mach-O 二进制里把 Swift 的类型、protocol 和 conformance 读回来。书里的每一个语义对象在二进制里都有落点，前言正好说明了它们各自在哪一章。
>
> **术语**：书中定义的术语一律保留英文（generic signature、requirement、substitution map、conformance、archetype、generic environment、type parameter、associated type、conformance path、opaque result type、existential type、Requirement Machine、string rewriting、Knuth-Bendix completion……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Type Parameter Order 一节」，文件都在源码树 `docs/Generics/chapters/` 下。本章不含特殊数学记法，故不附记法表。

---

这是一本讲 generic programming——也叫 parametric polymorphism——在 Swift 编译器里如何实现的书。你不会在这里学到怎么**写** Swift 的 generic 代码；那件事最好的参考当然是官方语言指南（2014，《The Swift Programming Language》）。本书主要写给这么几类人：与 generics 实现打交道的 Swift 编译器开发者、想弄清 Swift 是怎么一路演化过来的其他语言设计者、好奇想掀开盖子看一眼的 Swift 程序员，以及对 string rewriting 和 Knuth-Bendix completion procedure 的一个实际应用感兴趣的数学家。

> 译注：本库 MachOSwiftSection 是上面这份名单之外的第五类读者——从编译产物往回读的人。编译器把 generic signature、substitution map、conformance 编码进 Mach-O 的 `__swift5_*` section 与 metadata，本库再把它们解码成声明模型，所以书里讲的编码规则就是本库的解码依据。本库的整体演化脉络见 [ProjectEvolutionLog.md](../ProjectEvolutionLog.md)。

从编译器开发者的视角看，**user** 指的是写下那段待编译代码的开发者。构成用户程序的声明、类型、语句和表达式，到了编译器这里都变成它必须去分析和操作的**数据结构**。我假定读者对这些概念、以及一般意义上的编译器构造有基本的了解。背景阅读可参考 Muchnick 1997，《Advanced Compiler Design and Implementation》；Cooper 与 Torczon 2004，《Engineering a Compiler》；Nystrom 2021，《Crafting Interpreters》；Siek 2023，《Essentials of Compilation: An Incremental Approach in Racket》。

本书分为五个部分。

> 译注：原文如此，但源码树的 `generics.tex` 里只有四个 `\part{}`（Syntax、Semantics、Subtleties、The Requirement Machine），第五个部分指的是书末的三个附录（`math-summary.tex`（中译 [SwiftGenericsMathSummary.md](SwiftGenericsMathSummary.md)）、`derived-requirements-summary.tex`（中译 [SwiftGenericsDerivedRequirements.md](SwiftGenericsDerivedRequirements.md)）、`type-substitution-summary.tex`（中译 [SwiftGenericsSubstitutionAlgebra.md](SwiftGenericsSubstitutionAlgebra.md)）），它们在 LaTeX 里走的是 `\appendix` 而非 `\part`。下面按部名而非编号引用，以免和目录对不上。

**Syntax** 部分先给出 Swift 编译器架构的高层概览，然后描述编译器如何为类型和声明——特别是 generic 的类型和声明——建模。

- Introduction（`introduction.tex`（中译 [SwiftGenericsIntroduction.md](SwiftGenericsIntroduction.md)））用一系列做透的例子把 generics 实现里的每一个关键概念过一遍，并综览其他编程语言提供的 generic programming 能力。

- Compilation Model（`compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)））讲 Swift 的编译模型与 module system，以及 **request evaluator**——它给「解析、类型检查、代码生成」这条典型的「编译流水线」加入了惰性求值的成分。

- Types（`types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)））描述编译器如何为源程序所声明的值的**类型**建模。Type 自成一门微型语言，我们常常要把它们拆开、再以新的方式拼回去。Generic parameter type、dependent member type 和 generic nominal type 是三种最基本的 type，其余的也会一并综述。

- Declarations（`declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)））讲**声明**，即 Swift 代码的构件。函数、struct、protocol 都是声明的例子。各类声明都可以是 **generic** 的。声明 generic parameter 和陈述 **requirement** 有一套共同的语法；protocol 可以声明 associated type，并以类似的方式对自己的 associated type 施加 **associated requirement**。

**Semantics** 部分聚焦 generics 实现中的核心**语义**对象。要读懂其中穿插的数学旁白，最好有过一点与定义和证明打交道的经验，微积分、线性代数或组合数学入门课的程度就够。基础数学的小结见 `math-summary.tex`。

- Generic Signatures（`generic-signatures.tex`）定义 **generic signature**，它收拢一个 generic declaration 的 generic parameter 和 explicit requirement。Generic signature 的 explicit requirement 生成一组 **derived requirement** 和 **valid type parameter**，这解释了我们如何对 generic declaration **内部**的代码做类型检查。这套形式化在实现中经由 **generic signature query** 落地。

- Substitution Maps（`substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)））定义 **substitution map**，即从 generic parameter type 到 replacement type 的一个映射。**type substitution algebra** 将解释 type substitution 与 substitution map composition 这两种运算。这解释的是我们如何对一个 generic declaration 的**引用**（有时也称作它的 **specialization**）做类型检查。

- Conformances（`conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)））定义 **conformance**，也就是「某个具体类型如何满足一个 protocol 的 requirement（尤其是它的 associated type）」的那份描述。在 type substitution algebra 里，conformance 之于 protocol，正如 substitution map 之于 generic signature。

- Archetypes（`archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)））定义 **archetype** 与 **generic environment**，这是贯穿整个编译器的两个抽象。本章还描述 **type parameter graph**，它给了我们一种直观看待 generic signature 的方式。

- Type Resolution（`type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)））描述 **type resolution**，它用 name lookup 和 substitution 把语法层面的表示解析成语义层面的 type。检查一张 substitution map 是否满足其 generic signature 的 requirement，则把前面两套形式化连在了一起。

> 译注：这五章定义的语义对象，本库都要从二进制里逆向重建：generic signature 和它的 requirement 逐字节写在 descriptor 的 generic context 里（opaque descriptor 那一路的逐字节解读见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)），substitution 由静态布局引擎在无运行时的情况下自己做一遍（见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)），conformance 则对应 `__swift5_proto` 里的 conformance descriptor 与 witness table 的归属判定（见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)）。

**Subtleties** 部分覆盖另外一些语言特性和编译器内部机制，同时把 derived requirement 的形式化与 type substitution 继续往前推：

- Extensions（`extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)））讨论 extension 声明，它给已有的类型追加成员和 conformance。Extension 还可以声明 **conditional conformance**，那有一些有趣的行为。

- Building Generic Signatures（`building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)））解释我们如何从源码里写下的语法构建出一个 generic signature，并给出 **requirement minimization** 的形式化描述。本章还展示无效的 requirement 是如何被诊断出来的，并把通过这些检查的 generic signature 定义为 **well-formed generic signature**。

- Conformance Paths（`conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)））表明 **conformance path** 给了我们一条在 type substitution algebra 里求值表达式的途径，从而使这套形式化完整。本章探讨 **recursive conformance** 的概念，最后证明 type substitution algebra 是图灵完备的。

- Opaque Result Types（`opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)），中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）描述 **opaque result type**，这是另一种 generic 抽象：它让函数对调用方隐藏自己的具体返回类型，转而只说明这个返回类型满足哪些 generic requirement。这项能力是用 generic signature、substitution map 和 archetype 搭起来的。

- Existential Types（`existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)））尚未写完。它将描述 existential type。

**The Requirement Machine** 部分描述 Requirement Machine，即 Generic Signatures 一章所讲的 derived requirement 的一个**判定过程**。这里的原创贡献在于指出：generic signature query 与 requirement minimization 都是 **string rewriting** 理论中的问题。

- Basic Operation（`basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)））从高层讲清 generic signature query 与 requirement minimization 两者如何递归地由一个 generic signature 的各 **protocol component** 的 requirement machine 构建出这个 generic signature 的 **requirement machine**。

- Monoids（`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)））引入 **finitely-presented monoid** 与 **word problem**，随后给出这样一条理论结果：一个 finitely-presented monoid 可以编码成一个 generic signature，使得 word problem 变成 generic signature query。因此 generic signature query **至少**和 word problem 一样难；也就是说，一般情形下不可判定。

- Symbols, Terms, and Rules（`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)））走相反的方向，表明一个 generic signature 可以编码成一个 finitely-presented monoid，使得 generic signature query 变成 word problem。于是 derived requirement **至多**和 word problem 一样难——而 word problem 在许多情形下可以用已知技术求解。这是我们那套判定过程的心脏。

- Completion（`completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)））描述 Knuth-Bendix 算法，它试图通过构造一个 **convergent rewriting system** 来解 word problem。基本的 generic signature query 随后便可由 **normal form algorithm** 回答。这是我们那套判定过程的大脑。

- The Property Map（`property-map.tex`（中译 [SwiftGenericsPropertyMap.md](SwiftGenericsPropertyMap.md)））尚未写完。它将描述如何从一个 convergent rewriting system 构建 **property map**；property map 负责回答那些更棘手的 generic signature query。

- Minimization（`minimization.tex`（中译 [SwiftGenericsMinimization.md](SwiftGenericsMinimization.md)））尚未写完。它将给出 rewrite rule minimization 的算法，那是构建一个新 generic signature 的最后一步。

Swift 编译器是用 C++ 写的。为了避免附带的复杂度，书中描述概念时不直接引用源代码，而是在部分章节末尾附一节 **Source Code Reference**，其结构类似 API 参考。如果你只关心理论，这部分材料可以跳过。除这些小节之外，全书不假定读者懂 C++。

书中会时不时插入一些**历史**旁白，讲某样东西是怎么来的。从 Swift 2.2 开始，Swift 语言的设计由 Swift evolution 流程引导，语言改动在公开场合被提出、辩论并定案（见 Swift evolution process，2016）。描述各项语言特性时我会引用相应的 Swift evolution 提案。参考文献里还有大量别的有趣材料，不止是 evolution 提案。

关于 generic 的分离编译在运行时一侧的情况，本书着墨不多，只在 Introduction 一章从与 type checker 的关系出发给了一个简短的概览。想深入了解的话，我推荐看两场 LLVM Developer's Conference 演讲：John McCall 与 Slava Pestov 2017 年的「Implementing Swift generics」总结了整套设计，Dario Rexin 2023 年的「Compact value witnesses in Swift」则描述了近期的一些优化。

> 译注：作者一笔带过的「运行时一侧」，恰好是本库全部工作的所在：value witness table、metadata 布局、field descriptor 这些运行时数据结构，正是本库在离线状态下读取和复算的对象。本库在没有实参、也不加载进程的前提下能把布局算到什么程度，见 [SwiftLayout.md](../Modules/SwiftLayout.md) 与 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

还有，书中绝大部分材料截至 Swift 6.2 是最新的，但有几项较近的语言扩展没有覆盖。这些特性基本都是增量式的，读对应的 evolution 提案即可理解：

1. Parameter pack（也叫 variadic generics），Swift 5.9 引入（SE-0393、SE-0398、SE-0399）。
2. Noncopyable type，Swift 6 引入（SE-0390、SE-0427）。
3. Nonescapable type，Swift 6.2 引入（SE-0446）。
4. Integer generic parameter，Swift 6.2 引入（SE-0452）。

## Source Code

本书的 TeX 源码放在 Swift 源码仓库里：

> <https://github.com/swiftlang/swift/tree/main/docs/Generics>

排版好的 PDF 会定期更新，可从 Swift 官网获取：

> <https://download.swift.org/docs/assets/generics.pdf>

## Acknowledgments

我要感谢每一位读过本书早期版本、指出笔误、提出澄清性问题的人。另外，Swift 的 generics 系统本身是无数人十余年协作的成果，其中包括编译器开发者、Swift evolution 提案的作者、evolution 社区的成员，以及所有报告过 bug 的用户。本书试图为这全部贡献的总和给出一个概览。

---

> 译自 `docs/Generics/chapters/preface.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
