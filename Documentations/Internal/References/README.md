# References —— 外部权威资料的中译与摘录

本目录放**外部资料的中译**，与 `Internal/` 其余文档（本库自己的设计说明）性质不同：这里的内容不描述本库，而是本库赖以成立的外部事实。译文正文忠于原著，只在确有对应关系处用「译注」标出本库的落点。

## 《Compiling Swift Generics》全书中译

Slava Pestov 所著 *Compiling Swift Generics*，讲 Swift 编译器如何实现泛型。源文件是 swift 仓库的 `docs/Generics/`，随仓库以 **Apache License 2.0 with Runtime Library Exception** 发布——该许可明确授予制作并分发衍生作品（翻译即其一）的权利，条件是保留署名与许可声明，故每份译文的文件头与文末都写明了出处、原作者、许可与对应 commit。

**译自** `swift-6.4.0-RELEASE`（本机 `/Volumes/SwiftProjects/swift-project/swift`）。官方 PDF：<https://download.swift.org/docs/assets/generics.pdf>。

**为什么本库要读这本书**：这本书讲的是「Swift 源码怎么编成二进制」，而本库做的是反方向的事——从 Mach-O 里把 Swift 的类型、protocol、conformance 读回来。书里定义的每一个语义对象（generic signature、substitution map、conformance、archetype）在二进制里都有对应的编码形态，本库的解码规则就是书里编码规则的倒影。

### 前言

| 中译 | 原文 | 源行 → 译行 | 讲什么 |
|---|---|---|---|
| [Preface](SwiftGenericsPreface.md) | `preface.tex` | 92 → 102 | 全书导览。每章都标了源文件名，可当目录用 |

### 第一部分 Syntax —— 编译器怎么为类型和声明建模

| 中译 | 原文 | 源行 → 译行 | 与本库的关系 |
|---|---|---|---|
| [Introduction](SwiftGenericsIntroduction.md) | `introduction.tex` | 562 → 640 | 全书概念地图，一串做透的例子走完四类语义对象；另有与 C++/Rust/Haskell 等的横向对比 |
| [Compilation Model](SwiftGenericsCompilationModel.md) | `compilation-model.tex` | 746 → 703 | module system 与 `.swiftinterface`——本库离线重建 interface 的依据；也解释了二进制里**读得到什么、读不到什么** |
| [Types](SwiftGenericsTypes.md) | `types.tex` | 960 → 875 | 编译器的 type 树 ≈ 本库 demangle 出的 `Node` 树；sugar 与 canonical 的区别正是还原源码拼写的难点 |
| [Declarations](SwiftGenericsDeclarations.md) | `declarations.tex` | 1236 → 1129 | nominal type descriptor、protocol requirement、extension 的声明形态 |

### 第二部分 Semantics —— 泛型实现的核心语义对象

| 中译 | 原文 | 源行 → 译行 | 与本库的关系 |
|---|---|---|---|
| [Generic Signatures](SwiftGenericsGenericSignatures.md) | `generic-signatures.tex` | 1488 → 1509 | 全书理论核心：derived requirement 的推理规则、reduced type、**canonical 顺序**——本库判断 same-type 哪边是被约束参数靠它 |
| [Substitution Maps](SwiftGenericsSubstitutionMaps.md) | `substitution-maps.tex` | 1386 → 1470 | `⊗` 替换代数。本库的静态布局引擎把这套运算在无运行时的条件下重做了一遍 |
| [Conformances](SwiftGenericsConformances.md) | `conformances.tex` | 1336 → 1550 | normal / specialized / abstract 三种 conformance 与 witness table；本库的 conformance 归属判定依据 |
| [Archetypes](SwiftGenericsArchetypes.md) | `archetypes.tex` | 772 → 726 | archetype 与 generic environment、type parameter graph |
| [Type Resolution](SwiftGenericsTypeResolution.md) | `type-resolution.tex` | 1071 → 1190 | 语法→语义的解析。本库的 `MetadataReader` 走的是同一套语义，只是入口是 mangled name |

### 第三部分 Subtleties —— 语言特性与更细的机制

| 中译 | 原文 | 源行 → 译行 | 与本库的关系 |
|---|---|---|---|
| [Extensions](SwiftGenericsExtensions.md) | `extensions.tex` | 913 → 938 | extension 与 conditional conformance。二进制里没有 extension descriptor，本库按四元组归拢容器 |
| [Building Generic Signatures](SwiftGenericsBuildingGenericSignatures.md) | `building-generic-signatures.tex` | 1589 → 1771 | requirement 的分解脱糖与 minimization——本库在 descriptor 里读到的就是这一步的产物 |
| [Conformance Paths](SwiftGenericsConformancePaths.md) | `conformance-paths.tex` | 1471 → 1475 | 运行时如何沿 witness table 取到 associated conformance；后半用 conformance path 模拟图灵机证明不可判定性 |
| [Opaque Result Types](SwiftGenericsOpaqueResultTypes.md) | `opaque-result-types.tex` | 1106 → 1115 | `some P` 的完整机制。本库还原不透明返回类型的直接依据 |
| [Existential Types](SwiftGenericsExistentialTypes.md) | `existential-types.tex` | 606 → 572 | existential 容器的布局规则——本库 `ExistentialLayoutBridge` 的来源。**原书此章未定稿** |

### 第四部分 The Requirement Machine —— 泛型签名背后的重写系统

本库**不实现**这套重写系统，只消费它算完的结果：二进制里的 requirement 已经 minimize 过，type parameter 已是 reduced form。这几章解释那个结果**为什么长成那样**。

| 中译 | 原文 | 源行 → 译行 | 讲什么 |
|---|---|---|---|
| [Basic Operation](SwiftGenericsBasicOperation.md) | `basic-operation.tex` | 723 → 647 | 这台机器整体怎么跑；protocol 依赖图的强连通分量分解 |
| [Monoids](SwiftGenericsMonoids.md) | `monoids.tex` | 1473 → 1523 | 全书数学最纯的一章：monoid presentation、字符串重写、word problem 不可判定性，以及泛型签名到 monoid 的翻译 |
| [Symbols, Terms and Rules](SwiftGenericsSymbolsTermsAndRules.md) | `symbols-terms-and-rules.tex` | 1851 → 1735 | 机器的基本数据结构；全书算法最多的一章（17 个） |
| [Completion](SwiftGenericsCompletion.md) | `completion.tex` | 1864 → 1882 | Knuth-Bendix completion：critical pair 如何汇合、为什么可能不终止。全书最长、交换图最密 |
| [The Property Map](SwiftGenericsPropertyMap.md) | `property-map.tex` | 675 → 641 | 从重写系统回答更一般的查询。**原书此章未定稿** |
| [Minimization](SwiftGenericsMinimization.md) | `minimization.tex` | 149 → 144 | 用 homotopy reduction 删冗余规则。**原书此章基本只有提纲** |

### 附录

| 中译 | 原文 | 源行 → 译行 | 讲什么 |
|---|---|---|---|
| [Mathematical Conventions](SwiftGenericsMathSummary.md) | `math-summary.tex` | 63 → 95 | 全书数学记号总表。**两套记法的对照表在这里** |
| [Derived Requirements](SwiftGenericsDerivedRequirements.md) | `derived-requirements-summary.tex` | 88 → 154 | derived requirement 的全部推理规则 |
| [Substitution Algebra](SwiftGenericsSubstitutionAlgebra.md) | `type-substitution-summary.tex` | 87 → 161 | 替换代数的记号总表 |

## 读这套译文需要知道的几件事

**术语一律保留英文。** generic signature、requirement、conformance、substitution map、archetype 这些都不译，也不做「泛型签名(generic signature)」式的中英黏合。中文只承担行文。

**记法分两套，可互相对照。** 第一到第三部分与前言用**纯文本 + Unicode**（`τ_0_0`、`⊗`、`↦`、`⟦T⟧`、`↻T`），每份文件头有记法表；第四部分与三个附录用 **Markdown LaTeX 数学**（`$...$`），因为那里公式密度高一个量级，硬转 Unicode 会丢结构。[Mathematical Conventions](SwiftGenericsMathSummary.md) 的记法表同时给出两套写法，可在两种风格间对号。

**原书的图全部有产物。** 全书 159 张 TikZ / tikzcd 图无法直接搬进 Markdown：交换图（rewrite path 如何汇合这类**实质论证**）画成保留原标签的 Unicode 箭头图并补一句「这张图断言了什么」，数据结构图画成 ASCII 图，每张图后都有一行降级说明，指向官方 PDF 看原貌。

**原书笔误照译，另加译注。** 遇到前后矛盾、编号引用错、算法步骤写错的地方，一律**照译原文**再加一行译注说明矛盾在哪、以哪一处为准，不替作者改正文。第四部分标出的几处尤其要紧——Tarjan 算法第 8 步、Normal form 算法第 2 步、Import rules 算法第 7 步的回跳目标都写错了，照着原书实现会死循环或清空栈；这几处经核对编译器源码后在译注里写明了实际实现。

**编号一律不保留。** 原书的「Example 3.12」「Lemma 4.7」这类编号在中译里去掉了，交叉引用改用名字（「见 `generic-signatures.tex` 的 Type Parameter Order 一节」）。要对照官方 PDF 时按节名找。

**`\ifWIP` 块照译并标注。** 三章（Existential Types、The Property Map、Minimization）的正文大部分包在 `\ifWIP` 条件块里，官方 PDF **不输出**这些内容，那是作者的草稿。译文照译以备参考，每块开头都有标注，不要拿它们当权威。
