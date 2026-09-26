# Derived Requirements（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/derived-requirements-summary.tex`（《Compiling Swift Generics》一书的「Derived Requirements」一章，全书三个附录之一），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `7ad160a9`，2024-11-16）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这是 derived requirement 那套形式系统的规则总表——6 条 elementary statement 加 17 条 inference rule，一页看全。对本库（MachOSwiftSection）而言，**推导本身不在本库的职责里**：二进制里写下的是编译器推完并 minimize 之后的结果。但表里的五种 requirement kind（conformance / same-type / concrete same-type / superclass / layout）正是 descriptor 的 generic context 里逐字节编码的那五种，而 `T.[P]A` 这种 bound dependent member type 正是本库解析 associated type witness 时要还原的形状，所以这张表是读那批字节时的对照表。
>
> **术语**：书中定义的术语一律保留英文（derived requirement、valid type parameter、elementary statement、inference rule、derivation、derivation step、generic signature、requirement signature、conformance requirement、same-type requirement、superclass requirement、layout requirement、associated requirement、associated type declaration、bound / unbound dependent member type、equivalence class、protocol `Self` type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Derived Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下。
>
> **记法约定**（本附录属规约 §6 的 B 类，用 Markdown LaTeX 数学 `$...$` / `$$...$$`）。全书中译分两种风格，下表给出两套写法的对照——左边是本文用的 LaTeX，中间是散文章节（如 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）用的纯文本 Unicode：
>
> | LaTeX（本文） | 纯文本（散文章节） | 含义 |
> |---|---|---|
> | `$\vdash$` → $\vdash$ | `⊢` | turnstile；$G\vdash D$ 表示 $D$ 属于 $G$ 的 theory |
> | `$\tau_{d,i}$` → $\tau_{d,i}$ | `τ_d_i` | depth `d`、index `i` 的 generic parameter |
> | `$[\texttt{T: P}]$` | `[T: P]` | conformance requirement |
> | `$[\texttt{T == U}]$` | `[T == U]` | 两个 type parameter 之间的 same-type requirement |
> | `$[\texttt{T == X}]$` | `[T == X]` | concrete same-type requirement |
> | `$[\texttt{T: C}]$` | `[T: C]` | superclass requirement |
> | `$[\texttt{T: AnyObject}]$` | `[T: AnyObject]` | layout requirement |
> | `$[\texttt{Self.U: Q}]_{\texttt{P}}$` | `[Self.U: Q]_P` | protocol `P` 的 associated conformance requirement（下标标明它属于哪个 protocol） |
> | `$[\texttt{Self.U == Self.V}]_{\texttt{P}}$` | `[Self.U == Self.V]_P` | protocol `P` 的 associated same-type requirement |
> | `$\texttt{X}^\prime$`、`$\texttt{C}^\prime$` | `X′`、`C′` | 把 `X`、`C` 里的 `Self` 换成 `T` 之后得到的东西 |
> | `$\dfrac{\text{前提}}{\text{结论}}$` | — | inference rule。**原书不用分式**，它把一条 derivation step 写成一行：结论在前，右边小型大写字母给出这一步的「kind」，后面跟前提清单，即 $\textit{conclusion}\ (\textsf{KIND}\ \textit{assumption})$。本译文按规约改成横线形式，信息量相同 |
>
> 原书的 `\uptau`（直立 tau）在 Markdown 数学里渲染不出来，本文一律写 `\tau`。

---

设 $G$ 是一个 generic signature。我们从一个有限的 elementary statement 集合出发，反复施用 inference rule，从而生成 $G$ 的 theory。一次 derivation 通过列出一串 derivation step 来证明某个元素属于这个集合，其中每一步的前提都是之前某些步骤的结论。名称约定如下：

| 记号 | 说明 |
|---|---|
| $\texttt{T}$、$\texttt{U}$、$\texttt{V}$ | type parameter |
| $\texttt{Self.U}$、$\texttt{Self.V}$ | 根在 protocol `Self` type 上的 type parameter |
| $\texttt{X}$ | 一个 concrete type |
| $\texttt{C}$ | 一个 concrete class type |
| $\texttt{X}^\prime$、$\texttt{C}^\prime$ | 把 $\texttt{X}$、$\texttt{C}$ 里的 $\texttt{Self}$ 换成 $\texttt{T}$ 之后得到的 |
| $\texttt{P}$、$\texttt{Q}$ | protocol |
| $\texttt{A}$ | $\texttt{P}$ 的某个 associated type 的名字 |
| $\texttt{[P]A}$ | $\texttt{P}$ 的一个 associated type declaration |
| $\texttt{T.[P]A}$、$\texttt{T.A}$ | bound 与 unbound dependent member type |
| $[\texttt{T: P}]$ | 一条 conformance requirement |
| $[\texttt{T == U}]$ | 两个 type parameter 之间的一条 same-type requirement |
| $[\texttt{T == X}]$ | 一条 concrete same-type requirement |
| $[\texttt{T: C}]$ | 一条 superclass requirement |
| $[\texttt{T: AnyObject}]$ | 一条 layout requirement |
| $[\texttt{Self.U: Q}]_{\texttt{P}}$ | protocol $\texttt{P}$ 的一条 associated requirement |

细节见 `generic-signatures.tex` 的 Derived Requirements、Valid Type Parameters 与 Bound Type Parameters 三节。

> 译注：表中最后五行的五种 requirement kind，正是 Swift ABI 在 generic context 里逐字节编码的那五种（conformance / same-type / 带 concrete 右端的 same-type / superclass / layout）。本库从 opaque type descriptor 的 requirement 列表里逐条读出它们、再还原成 `where` 子句的过程，见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

### Elementary statements

对 $G$ 的每个 generic parameter $\tau_{d,i}$，以及 $G$ 的每条 explicit requirement（按 kind 分），都有一条 elementary derivation step。它们没有前提，直接给出结论：

| Kind | 结论 | 何时可用 |
|---|---|---|
| **Generic** | $\tau_{d,i}$ | $G$ 的每个 generic parameter $\tau_{d,i}$ |
| **Conf** | $[\texttt{T: P}]$ | $G$ 的每条 explicit conformance requirement |
| **Same** | $[\texttt{T == U}]$ | $G$ 的每条 explicit same-type requirement（两端都是 type parameter） |
| **Concrete** | $[\texttt{T == X}]$ | $G$ 的每条 explicit concrete same-type requirement |
| **Super** | $[\texttt{T: C}]$ | $G$ 的每条 explicit superclass requirement |
| **Layout** | $[\texttt{T: AnyObject}]$ | $G$ 的每条 explicit layout requirement |

### Requirement signatures

假设已经推出 $G\vdash[\texttt{T: P}]$。对 $\texttt{P}$ 的每个 associated type $\texttt{A}$，有三条 inference rule：

**AssocName**

$$\dfrac{[\texttt{T: P}]}{\texttt{T.A}}$$

**AssocDecl**

$$\dfrac{[\texttt{T: P}]}{\texttt{T.[P]A}}$$

**AssocBind**

$$\dfrac{[\texttt{T: P}]}{[\texttt{T.[P]A == T.A}]}$$

> 译注：`T.[P]A` 这种 bound dependent member type（把 associated type 明确绑到声明它的 protocol 上）正是本库在离线算布局时要解析的形状：`DependentMemberTypeBridge` 拿着 `T.[P]A`，去声明该 conformance 的那个镜像的 `__swift5_assocty` 里查 type witness，再把 base 自己的 generic argument 代进去。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

对 $\texttt{P}$ 的每条 associated requirement（按 kind 分），各有一条 inference rule。横线上方左边那个带下标的前提是 $\texttt{P}$ 的 requirement signature 里的一个元素，右边那个才是在 $G$ 里推出来的语句；在固定 generic signature 里列 derivation 时，原书会把前者从前提清单里略去，因为不会有歧义：

**AssocConf**

$$\dfrac{[\texttt{Self.U: Q}]_{\texttt{P}} \qquad [\texttt{T: P}]}{[\texttt{T.U: Q}]}$$

**AssocSame**

$$\dfrac{[\texttt{Self.U == Self.V}]_{\texttt{P}} \qquad [\texttt{T: P}]}{[\texttt{T.U == T.V}]}$$

**AssocConcrete**

$$\dfrac{[\texttt{Self.U == X}]_{\texttt{P}} \qquad [\texttt{T: P}]}{[\texttt{T.U}\ \texttt{==}\ \texttt{X}^\prime]}$$

**AssocSuper**

$$\dfrac{[\texttt{Self.U: C}]_{\texttt{P}} \qquad [\texttt{T: P}]}{[\texttt{T.U}\texttt{:}\ \texttt{C}^\prime]}$$

**AssocLayout**

$$\dfrac{[\texttt{Self.U: AnyObject}]_{\texttt{P}} \qquad [\texttt{T: P}]}{[\texttt{T.U: AnyObject}]}$$

### Equivalence

Same-type requirement 生成一个 equivalence relation：

**Reflex**

$$\dfrac{\texttt{T}}{[\texttt{T == T}]}$$

**Sym**

$$\dfrac{[\texttt{T == U}]}{[\texttt{U == T}]}$$

**Trans**

$$\dfrac{[\texttt{T == U}] \qquad [\texttt{U == V}]}{[\texttt{T == V}]}$$

### Compatibility

一条 derived 的 conformance、superclass 或 layout requirement，对同一个 equivalence class 里的所有 type parameter 都成立：

**SameConf**

$$\dfrac{[\texttt{U: P}] \qquad [\texttt{T == U}]}{[\texttt{T: P}]}$$

**SameConcrete**

$$\dfrac{[\texttt{U == X}] \qquad [\texttt{T == U}]}{[\texttt{T == X}]}$$

**SameSuper**

$$\dfrac{[\texttt{U: C}] \qquad [\texttt{T == U}]}{[\texttt{T: C}]}$$

**SameLayout**

$$\dfrac{[\texttt{U: AnyObject}] \qquad [\texttt{T == U}]}{[\texttt{T: AnyObject}]}$$

如果两个 type parameter 等价，那么它们各自对应的 member type 也等价：

**SameName**

$$\dfrac{[\texttt{U: P}] \qquad [\texttt{T == U}]}{[\texttt{T.A == U.A}]}$$

**SameDecl**

$$\dfrac{[\texttt{U: P}] \qquad [\texttt{T == U}]}{[\texttt{T.[P]A == U.[P]A}]}$$

---

> 译自 `docs/Generics/chapters/derived-requirements-summary.tex`（swift-6.4.0-RELEASE，`7ad160a9`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
