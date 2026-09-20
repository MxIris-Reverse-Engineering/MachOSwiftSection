# Minimization（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/minimization.tex`（《Compiling Swift Generics》一书的「Minimization」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：**必须先说清楚——本章在原书里基本还是一份提纲，不是成文的论述。** 原书自己的 README 把 Minimization 列在「not yet written」（尚未写成）名单里；源文件总共 149 行，除了章标题、六个节标题和几条索引指令之外，其余内容**全部**包在 `\ifWIP` 条件块里（本章共 7 个），而 `\ifWIP` 在 `generics.tex` 里被定义成 `\iffalse`，所以官方 PDF 会把这些内容整段丢弃：正式排版出来的 Minimization 一章，只有一个章标题加六个空节标题，正文一个字也没有。本译文按翻译规约把这些草稿块照译下来——里面是作者给自己列的写作要点，能看出他打算怎么讲这件事，对想理解 minimization 的人仍有参考价值——但**读者不应拿它当完整论述**：它没有定义、没有算法、没有证明，也没有经过作者定稿，个别条目还是作者写给自己看的速记。真正成文的 Requirement Machine 内容在 `basic-operation.tex`（中译 [SwiftGenericsBasicOperation.md](SwiftGenericsBasicOperation.md)）、`monoids.tex`（中译 [SwiftGenericsMonoids.md](SwiftGenericsMonoids.md)）、`symbols-terms-and-rules.tex`（中译 [SwiftGenericsSymbolsTermsAndRules.md](SwiftGenericsSymbolsTermsAndRules.md)）、`completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 几章；本章只在那些章之上补最后一步：**在不改变 rewrite system 所定义的 monoid 的前提下删掉冗余 rule**。
>
> **术语**：书中定义的术语一律保留英文（minimization、homotopy reduction、rewrite rule、rewrite path、rewrite loop、parallel paths、homotopy relation、redundant rule、elimination order、conformance path、critical pair、connected component、concrete contraction、requirement builder、associated type、type alias、superclass、equivalence class、anchor、GSB（GenericSignatureBuilder）、ABI……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`completion.tex` 的 Critical Pairs 一节」，文件都在源码树 `docs/Generics/chapters/` 下。
>
> **记法约定**：本章属翻译规约 §6 的 B 类（Part IV），数学记号本应写成 Markdown LaTeX（`$...$`）——但本章尚未成文，**源文件里没有出现任何公式**，唯一的展示性内容是两段 requirement 列表（按代码块处理）。本章所倚赖的记号（term、rewrite rule、rewrite path、loop、whisker 等）都定义在 `symbols-terms-and-rules.tex` 与 `completion.tex`，那两章的中译里有完整的记法表。

---

> 译注：本库（MachOSwiftSection）**不实现** minimization，也不实现它所属的整套 Requirement Machine——本库是反方向的：从 Mach-O 二进制把 Swift 类型与 requirement 读回来。但这一章决定了本库**能读到什么**：二进制里的每一条 requirement 都已经是 minimize 过的结果，冗余 rule 在编译期就被删掉了，留下的条数与顺序正是本章这套算法的输出。最直观的例子是 opaque 结果类型的 descriptor：源码里写了两条 same-type 约束，二进制里可能只剩一条（同一个 equivalence class 只保留 canonical anchor），本库照着读就只能看见一条。逐字节的解读与这一现象的实测记录，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

TODO：

- 理论部分：parallel paths。
- 某条 rule 在 empty context 里只出现一次。
- 我想删掉一条 rule，同时不改变这个 rewrite system。
- 有两条 parallel path：一条就是这条 rule 本身，另一条完全不涉及这条 rule。
- 在一个 rewrite loop 里，我可以把其中一条 parallel path 换成另一条。
- 具体地说，我可以把我那条 rule 换成它的 defining path。
- 这样一来，就没有任何 loop 再提到这条 rule 了。
- 那原来那个 loop 又会变成什么样？
- 几何空间的类比：空间里有个洞，有一个环绕着这个洞打转；这个环没办法收缩成一个点。
- 我们把这个洞填上，于是环就能收缩成一个点了。
- Homotopy relation。

## Homotopy Reduction

> 译注：原书此处有两条索引指令，把下面两个 frontend flag 登记进全书的 flag 索引：`-debug-requirement-machine=homotopy-reduction` 与 `-debug-requirement-machine=homotopy-reduction-detail`。索引指令本身不译，但 flag 名字保留在这里——本节正文尚未写成，它们是这一节仅有的实质信息。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

TODO：

- 找出那些在 empty context 里只出现一次的 rule，并把这个结果按 rewrite loop 逐个缓存起来。
- 删掉没有价值的 loop。
- Rewrite path 的求值器。
- 挑出最佳候选。
- 用一条 path 替换掉一条 rule。
- 把 rule 标记为 redundant。
- 记录下 replacement path。
- 用来 dump redundant path 的 flag。
- 传播 explicit 标志位。
- 传播 explicit ID。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

本节参考文献：Kobayashi 1998，《Homotopy reduction systems for monoid presentations: Asphericity and low-dimensional homology》，*Journal of Pure and Applied Algebra* 130(2)，159–195 页。

> 译注：原书此处还有一条索引指令，登记 frontend flag `-disable-requirement-machine-loop-normalization`；索引指令本身不译，flag 名字保留。

TODO：

- 把互逆的那些步骤合并掉。
- 正交的 rewrite step，以及 interchange。
- Freely reduced loop。
- 给个例子，比如做完 rule 替换之后是什么样，或者类似的东西。
- Cyclically reduced loop。
- Cyclic reduction 的例子：来自添加一条 rewrite rule，而它的 critical pair 平凡地归结掉了。
- 「由空集生成的 homotopy relation」。

## The Elimination Order

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

TODO：

- 三趟 pass。
- 每一趟按某种特定顺序考察 (rule, loop) 这样的配对。
- 逐条描述各个 heuristic。

## Conformance Minimization

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

> 译注：本节开头有两条索引指令，登记 frontend flag `-debug-requirement-machine=minimal-conformances` 与 `-debug-requirement-machine=minimal-conformances-detail`；索引指令本身不译，flag 名字保留。注意这两条在原书里也位于 `\ifWIP` 块内。

TODO：

- 举一个 homotopy reduction 最小化过头的例子。
- 不变式：把它和 conformance path 联系起来，以及把 unbound term 归约成 bound term 这件事。
- Protocol inheritance。
- Concrete conformance。
- 假的 completion 算法。
- Critical pair：conformance 对 conformance、conformance 对 same-type。
- 为了让 requirement 留在各自的「home protocol」里而做的那个 LHS simplified hack。
- 举一个必须把整个 connected component 一次性最小化的例子——因为分处两个不同 protocol 的两条 requirement 互为冗余。

## Building Requirements

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

> 译注：本节开头有五条索引指令，登记下列 frontend flag：`-requirement-machine-max-split-concrete-equiv-class-attempts`、`-debug-requirement-machine=minimization`、`-debug-requirement-machine=redundant-rules`、`-debug-requirement-machine=redundant-rules-detail`、`-debug-requirement-machine=split-concrete-equiv-class`。索引指令本身不译，flag 名字保留。这几条在原书里同样位于 `\ifWIP` 块内。

TODO：

- Same-type requirement：connected component 那套做法。
- Type alias requirement：相当于 concrete equivalence class 拆分的那件事。
- 拆分 concrete equivalence class：描述这个问题、给出例子、指明它违反了哪一条 generic signature 不变式。另一种表述方式本来也行得通，但会破坏 ABI，所以为了与 GSB 保持兼容，我们还是选择拆分 equivalence class。

Minimization 算法输出的是「circuit」这一形态：

```
T.A == T.B
T.B == T.C
T.C == T.D
```

而不是「star」这一形态：

```
T.A == T.B
T.A == T.C
T.A == T.D
```

> 译注：这段区分对本库有直接后果。同一个 same-type connected component 写进二进制时只会是上面那种链式（circuit）形态，不会是以 anchor 为中心的星形（star），所以从 descriptor 里逐条读出来的 same-type 约束需要自己把链接起来才能还原出「这几个类型属于同一个 equivalence class」。编译器做这件事的位置是 `lib/AST/RequirementMachine/RequirementBuilder.cpp` 的 `ConnectedComponent::buildRequirements`，它同时决定了哪一侧写在等号左边；本库读回这批约束、以及由此产生的「pin 物理上消失了」现象，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md) 的 §2.3 与 §2.5。

## Concrete Contraction

> 译注：本节标题下有两条索引指令，登记 frontend flag `-disable-requirement-machine-concrete-contraction` 与 `-debug-requirement-machine=concrete-contraction`，另有一条把 **concrete contraction** 登记为本节定义的术语。索引指令本身不译，flag 名字保留——这三条是本节在草稿块之外仅有的内容。

> 译注：以下内容在原书中包在 `\ifWIP` 条件块里，官方 PDF 默认不输出，属作者草稿；照译以备参考。

TODO：

- 它其实并不出现在 signature 里，所以本不该影响 minimization。
- 问题在于：它可能给出一个更小的 anchor。
- 不做 concrete contraction 就会破坏不变式。
- Concrete contraction 会把 superclass 与 concrete type 代进去。
- 还有 GSB 兼容性方面的考虑：有 `T.A`，有 `T == C`，而 `C.A` 是一个 concrete typealias、并不是 associated type。这种情况不会添加 rule。
- 开放问题：这件事有没有更有原则的做法？

## Source Code Reference

> 译注：原书这一节**只有标题**，标题之后直接就是文件结尾，没有任何 API 条目——与全章「尚未写成」的状态一致。其余各章的同名小节列的是实现这套机制的 C++ 类与方法；本章若将来补上，对应的实现位于 `lib/AST/RequirementMachine/`（`HomotopyReduction.cpp`、`MinimalConformances.cpp`、`RequirementBuilder.cpp`、`ConcreteContraction.cpp` 等）。

---

> 译自 `docs/Generics/chapters/minimization.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
