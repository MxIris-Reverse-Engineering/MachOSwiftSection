# Introduction（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/introduction.tex`（《Compiling Swift Generics》一书的「Introduction」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：这一章是全书的概念地图——它用一串 worked example 把 generic signature、substitution map、requirement signature、conformance 这四类语义对象，连同 runtime type metadata、witness table、field offset vector 一次走完。本库 MachOSwiftSection 做的是反方向的事：从二进制里的 descriptor、metadata 和 witness table 把这些概念读回来。因此本章几乎每一节都能在本库找到一个「读回来」的对应点，译注会逐处标出；本库的整体形状见仓库根 `CLAUDE.md` 的 Architecture Overview 与 [ProjectEvolutionLog.md](../ProjectEvolutionLog.md)。
>
> **术语**：书中定义的术语一律保留英文（generic parameter type、requirement、generic signature、substitution map、conformance、witness table、runtime type metadata、archetype、type parameter、dependent member type、associated type、type witness、requirement signature、specialization、reduced type……），不硬造中文对应词。交叉引用写成原书章节文件名加原节名，例如「`generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)） 的 Reduced Type Parameters 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的例子按原书的英文标题引用。
>
> **记法约定**（原书用 LaTeX 宏，这里改成纯文本 + Unicode）：
>
> | 记法 | 含义 |
> |---|---|
> | `τ_d_i` | depth `d`、index `i` 的 **canonical generic parameter type**。原书里名字 `T` 通常对应 `τ_0_0` |
> | `⟦T⟧` | type parameter `T` 的 **archetype**（函数体内表达式类型里出现的那种） |
> | `[T: P]` | 语境不同含义不同：在 generic signature 里是类型 `T` 对 protocol `P` 的 **conformance requirement**；单独出现时是一个 **conformance** 本身 |
> | `[T == U]` | **same-type requirement**：`T` 与 `U` 必须是同一个具体类型 |
> | `Σ`、`Σ₁`、`Σ₂` | **substitution map**。`{T ↦ Int}` 表示把 generic parameter `T` 映到 replacement type `Int`；分号后面跟的是 replacement conformance，例如 `{S ↦ Circle; [S: Shape] ↦ [Circle: Shape]}` |
> | `T ⊗ Σ` | 把 substitution map `Σ` 应用到类型 `T` |
> | `⟨P] ⊗ X` | **global conformance lookup**：查具体类型 `X` 对 protocol `P` 的 conformance |
> | `⟨P\|A ⊗ [X: P]` | **type witness projection**：从 conformance `[X: P]` 里取 associated type `A` 的 type witness |
> | `⟨Self.A: Q] ⊗ [X: P]` | **associated conformance projection**：从 conformance `[X: P]` 里取出 associated conformance requirement `[Self.A: Q]` 所对应的那个 conformance |

---

Swift 的泛型实现，最好先从编译器面对的几条设计约束看起：

1. Generic function 应当能被独立地类型检查，不必知道它将来会被哪些 generic argument 调用。
2. 导出 generic type 和 generic function 的共享库，应当能以 resilient 的方式演进，而不要求客户端重新编译。
3. Generic struct 或 enum 应当把自己的字段 inline 存储、不做 boxing，因此它们的 layout 必须以 generic argument 类型为变量、抽象地定义出来。
4. 这份灵活性只应在绝无可免时才引入运行时开销，比如跨 module 边界调用时，或者编译期拿不到完整类型信息时。

高层设计可以这样概括：

1. Generic declaration 与其调用方之间的接口，由一串 **generic parameter type** 和一串 **requirement** 给出。在 generic declaration 内部，requirement 为它的 generic parameter 规定了行为；反过来，调用方提供一串 generic argument，这些 argument 必须满足那些 requirement。
2. Generic function 的 calling convention 要求调用方为每个 generic argument 类型传入 **runtime type metadata**。一条 type metadata record 描述的是：在编译期不知道具体 layout 的前提下，如何抽象地操作该类型的值。
3. Generic struct 或 enum 的 runtime type metadata 编码了该类型的 layout。这份 layout 信息由其 generic argument 的 type metadata 递归算出。Runtime type metadata 在第一次被请求时惰性构造，随后缓存起来。
4. 如果 generic function 的定义在调用点是可见的，优化器可以针对给定的 generic argument 类型，生成该 generic function 的一份 **specialization**。做得到的时候，specialization 就消掉了抽象值操作和 runtime type metadata 的开销。

我们打算把编译器看成**一个为目标语言的概念建模的库**。Swift 的泛型实现定义了四类基本的语义对象：**generic signature**、**substitution map**、**requirement signature** 和 **conformance**。我们会看到，要理解它们，既要看它们各自的内在结构，也要看它们彼此之间的关系。后面各章会深入所有细节，但首先，我们先走一串 worked example。

> 译注：这四类语义对象在本库里都有「读回来」的对应物：generic signature 对应 descriptor 里逐字节的 generic context（见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)），substitution map 对应静态泛型实参代入（见 [GenericArgumentSubstitution.md](../GenericArgumentSubstitution.md)），conformance 对应 `__swift5_proto` 里的 conformance descriptor（见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)），requirement signature 则以 protocol 的 requirement 表形式被投影出来（见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)）。本库整体是编译器的反方向，架构见仓库根 `CLAUDE.md` 与 [ProjectEvolutionLog.md](../ProjectEvolutionLog.md)。

## Functions

考虑下面这两个相当造作的函数声明：

```swift
func identity(_ x: Int) -> Int { return x }
func identity(_ x: String) -> String { return x }
```

除了参数类型和返回类型不同，两者的定义一模一样；事实上，对任何具体类型你都能写出同样的函数。审美上我们自然想把两者合并成一个 generic function：

```swift
func identity<T>(_ x: T) -> T { return x }
```

这个函数声明虽然简单，却体现了若干重要概念，也让我们有机会引入一些术语。完整的编译流水线要到下一章才讲，眼下先采用一个简化的视角：先 parsing，再 type checking，最后 code generation。

**图：`identity(_:)` 的 abstract syntax tree**

```
function declaration: identity
├─ generic parameter list: <T>
│  └─ generic parameter declaration: T
├─ parameter declaration: _ x: T
│  └─ type representation: T
├─ type representation: T
└─ body
   └─ statement: return x
      └─ expression: x
```

> 译注：原书此处是一张 TikZ 画的树图，这里用 ASCII 树转述；图的原貌见官方 PDF 对应章节。

**Parsing.** 上面那张图画的是 type checking 之前 parser 产出的 abstract syntax tree。其中的关键部分：

1. **Generic parameter list** `<T>` 引入了一个名为 `T` 的 **generic parameter declaration**。这条声明声明了 generic parameter type `T`，其作用域覆盖这个函数的整段源码范围。
2. 参数声明 `_ x: T` 和 `identity` 的返回类型里，都含有 **type representation** `T`。Type representation 是一种语法形式，表示对某个已有类型的引用。Parser 不做 name lookup，所以这里的 type representation `T` 只是一个标识符，它还没有和 generic parameter declaration `T` 关联起来。
3. 函数体由一条 `return` 语句构成，语句里是表达式 `x`。同样地，parser 不做 name lookup，所以这个表达式也只是标识符 `x`，还没有和参数声明 `_ x: T` 关联起来。

**Type checking.** Type checker 把这些语法形式翻译成更高层的语义对象：

1. Generic parameter list 声明的那些 **generic parameter type**，被收集进函数的 **generic signature**。本例中 generic signature 的打印形式是 `<T>`。除了非 generic 声明所带的空 generic signature 之外，这是最简单的一种 generic signature；更有意思的 generic signature 很快就会出现。

2. **Type resolution** 过程通过一次 name lookup，把参数的 type representation `T` 解析成 generic parameter type `T`。

3. 函数返回类型的 type representation 同样解析成 generic parameter type `T`。

Generic signature 连同解析好的参数类型与返回类型，被打包成一个 **generic function type**，它就是这个函数声明的 **interface type**。我们把这个 generic function type 记作：

```
<T> (T) -> T
```

名字「`T`」除了供 name lookup 用之外没有任何语义意义。我们后面会学到，每个 generic parameter type 在它的词法作用域内，由它的 **depth** 与 **index** 唯一确定。上面这个 generic function type 的 **canonical type** 记作下面这样，其中 `T` 被换成了 **canonical generic parameter type** `τ_0_0`：

```
<τ_0_0> (τ_0_0) -> τ_0_0
```

> 译注：「名字不重要、depth 与 index 才是身份」这条事实，在二进制里表现得最直白——mangled name 只编码 depth 与 index，generic parameter 的源码名字根本没有落盘。本库的 demangler 把符号解回 `Node` 树时拿到的就是这套坐标，随后按位置重新取名 `A`、`B`……见 [Modules/MachOSymbols.md](../Modules/MachOSymbols.md)。

**Interface type** 完整描述了「引用一个声明」这件事在类型检查中的行为。算出函数的 interface type 之后，type checker 转向函数体。`return` 语句里表达式的类型必须与函数声明的返回类型匹配。类型检查 `return` 后面的表达式 `x` 时，我们用 name lookup 找到参数声明 `_ x: T`。这条参数声明的 interface type 是 generic parameter type `T`，它要相对于函数的 generic signature 来理解。但赋给这个表达式的类型，是 `T` 所对应的 **archetype**，记作 `⟦T⟧`。我们后面会学到，archetype 是 type parameter 的一种自描述形式，它的行为像一个具体类型。

**Code generation.** 我们已经成功地把函数声明类型检查完了。下一步是把函数真正降级成可执行代码。回想一下合并成 generic function 之前的那两份具体实现：

```swift
func identity(_ x: Int) -> Int { return x }
func identity(_ x: String) -> String { return x }
```

这两个函数的 **calling convention** 差别很大：

1. 第一个函数在机器寄存器里接收并返回那个 `Int` 值。`Int` 类型是 **trivial** 的，意思是它的值可以直接拷贝和移动，不需要做任何额外的事。（C++ 把这种类型叫作「POD」。）
2. 第二个函数要麻烦一些。`String` 在内存里是一个 16 字节的值，其中含有一个指向 reference-counted 缓冲区的指针。操作 `String` 这种非 trivial 类型的值时，内存 ownership 就要登场了。

Swift 函数的默认 ownership 规则是：调用方保留它传给被调用方的那些参数值的 ownership，而被调用方把返回值的 ownership 转移给调用方。因此 `identity(_:)` 的 generic 实现必须先对 `x` 做一次逻辑上的拷贝，再把这份拷贝移动回调用方，而且要以一种能抽象于一切具体类型的方式做到。

Generic function 的 calling convention 会为函数 generic signature 里的每个 generic parameter 传入 **runtime type metadata**。Runtime type metadata 描述一个具体类型的 size 与 alignment，并提供 **move**、**copy**、**destroy** 三种操作的实现。

Trivial 类型的 move 与 copy 就是拷贝字节，destroy 什么也不做。换成 reference type，值是一个 reference-counted 指针，所以 copy 与 destroy 会更新 reference count，而 move 不改变 reference count。Struct 与 enum 的值操作由其成员递归定义。最后，weak reference 和 existential type 也各有自己特殊的值操作。

对 copyable 类型而言，一次 move 在语义上等价于「一次 copy 接一次 destroy」，只是更高效。按传统，语言里所有类型都是 copyable 的。Swift 5.9 引入了 **noncopyable type**（SE-0390），Swift 6 把泛型扩展到能处理 noncopyable type（SE-0427）。本书不讨论 noncopyable type。

> **更多细节**
>
> - Types：见 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)）
> - Generic parameter list：见 `declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 的 Generic Parameters 一节
> - Function declaration：见 `declarations.tex` 的 Functions 一节
> - Archetype：见 `archetypes.tex`（中译 [SwiftGenericsArchetypes.md](SwiftGenericsArchetypes.md)）
> - Type resolution：见 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)）

**Substitution maps.** 现在把注意力转向 generic function 的调用方。一个 **call expression** 把一个 **callee** 和一串实参表达式凑在一起。Callee 是某个具有 function type 的表达式；它可以是对一个具名函数声明的引用，可以是对一个类型的引用（那是调用构造器的语法糖），可以是对一个 function type 的参数或局部变量的引用，最一般地，还可以是另一个 call expression 的结果。在我们的例子里，可以按名字调用 `identity(_:)` 函数：

```swift
let x = identity(3)
let y = identity("Hello, Swift")
```

在 Swift 里，调用一个 generic function 时语法上并不写出 generic argument 类型；type checker 会把 callee 的 function type 与各实参表达式的类型相匹配，并在有期望结果类型时一并纳入匹配，从而推断出 generic argument。推断出来的 generic argument 收进一张 **substitution map**——这是一种数据结构，它为 callee 的 generic signature 里的每个 generic parameter type 指派一个 **replacement type**。

`identity(_:)` 的 generic signature 只有一个 generic parameter type，所以它的每张 substitution map 都只装一个具体类型。这里引入一些记法。下面是对应上面那两次调用的两张 substitution map：

```
Σ₁ := {T ↦ Int}          Σ₂ := {T ↦ String}
```

要得到一次调用的返回类型，我们取函数声明的返回类型，再把对应的 substitution map 应用上去。这个应用操作记作「`⊗`」。眼下它做的事很简单，就是把里面存的具体类型取出来：

```
T ⊗ Σ₁ = Int          T ⊗ Σ₂ = String
```

Substitution map 在 code generation 里也有角色。降级一次对 generic function 的调用时，编译器生成代码，为该 call expression 的 substitution map 里的每一个 replacement type 构造 runtime type metadata。在我们的例子里，`Int` 和 `String` 是标准库定义的 **nominal type**，它们不是 generic 的、layout 固定，所以它们的 runtime type metadata 是通过调用一个由标准库导出的函数取得的，该函数返回一个常量符号的地址。

> **更多细节**
>
> - Substitution map：见 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)）

**Specialization.** 把 runtime type metadata 具现出来、再通过它间接地操作值，是要付性能代价的。作为替代，如果 generic function 的定义在调用点可见，优化器可以生成这个 generic function 的一份 **specialization**：把定义克隆一份，并把 substitution map 应用到函数体里出现的所有类型上。在定义所在的 module 内部，generic function 的定义对 specializer 总是可见的。共享库的作者还可以用 `@inlinable` 属性，主动把函数体导出到 module 边界之外。

> **更多细节**
>
> - `@inlinable` 属性：见 `compilation-model.tex`（中译 [SwiftGenericsCompilationModel.md](SwiftGenericsCompilationModel.md)） 的 Module System 一节

## Nominal Types

下一个例子我们看一个简单的 generic struct 声明：

```swift
struct Pair<T> {
  let first: T
  let second: T

  init(first: T, second: T) {
    self.first = first
    self.second = second
  }
}
```

Struct 声明是 **nominal type declaration** 的一个例子。像 `Pair<Int>` 或 `Pair<String>` 这样的 **generic nominal type**，是「对一个 generic nominal type declaration 的引用」加上「一串 generic argument 类型」。

一个 struct 值的内存 layout 由它那些 stored property 的 interface type 决定。我们的 `Pair` struct 声明了两个 stored property，`first` 和 `second`，两者的 interface type 都是 `T`。因此一个 `Pair` 的 layout 取决于 generic parameter type `T` 的 layout。

把 generic parameter type `T` 自己作为实参代入所形成的 generic nominal type `Pair<T>`，叫作 `Pair` 的 **declared interface type**。类型 `Pair<Int>` 则是 declared interface type `Pair<T>` 的一个 **specialized type**。应用一张 substitution map 就能从 `Pair<T>` 得到 `Pair<Int>`：

```
Pair<T> ⊗ {T ↦ Int} = Pair<Int>
```

上面这张 substitution map 叫作 `Pair<Int>` 的 **context substitution map**。每个 specialized type 都有一张 context substitution map，把这张 map 应用到它的 declared interface type 上，就能拿回这个 specialized type。现在假设我们声明一个类型为 `Pair<Int>` 的局部变量：

```swift
let twoIntegers: Pair<Int> = ...
```

编译器必须在栈上为这个值分配存储。我们取 context substitution map，把它应用到每个 stored property 的 interface type 上。由于 `Pair` 有两个类型为 `T` 的 stored property，我们得到：

```
T ⊗ {T ↦ Int} = Int
```

所以一个 `Pair<Int>` 由两个相邻的 `Int` 组成，这让 `Pair<Int>` 的总 size 是 16 字节、alignment 是 8 字节。由于 `Pair<Int>` 是 trivial 的，离开作用域时这次栈分配不需要任何特殊清理。

现在我们把局部变量声明补全，写上调用构造器的 **initial value expression**：

```swift
let twoIntegers: Pair<Int> = Pair(first: 1, second: 2)
```

在调用点，这个值的类型是 `Pair<Int>`；但在构造器内部，正被初始化的那个值的类型是 `Pair<T>`。我们调用 `Pair` 的 **metadata access function**，把 `Int` 的 runtime type metadata 作为实参传进去，从而构造出 `Pair<Int>` 的 runtime type metadata。`Pair<Int>` 的 metadata 分两部分：

1. 一段所有 runtime type metadata 共有的前缀，其中包括一个值的总 size 与 alignment，以及 move、copy、destroy 三种操作的实现。
2. 一段专属于 `Pair` 这个声明自己的私有区域，里面存着 `T` 的 runtime type metadata，后面跟着 **field offset vector**，记录 `Pair<T>` 的这个 specialization 中每个 stored property 的偏移。

Generic type 的 metadata access function 接收每个 generic argument 的 metadata，算出每个 stored property 的偏移，同时也得到整个值的 size 与 alignment。聚合类型的 move、copy、destroy 操作则委派给 generic argument metadata 里对应的操作。`Pair` 的构造器随后同时用上 `Pair<T>` 和 `T` 的 runtime type metadata，把两个组成部分正确地初始化成那个聚合值。

> 译注：这一段描述的是运行时怎么算 field offset。本库做的是它的离线版本：不加载进程、不调用 metadata access function，直接从 Mach-O 文件里把同一套规则算一遍，得出 stored property 的偏移与整型的 size/alignment/extra inhabitant。引擎见 [Modules/SwiftLayout.md](../Modules/SwiftLayout.md)，逐条规则的来历与实测对账见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

**Structural type**——例如 function type、tuple type 和 metatype——和 generic nominal type 类似，也是调用一个 metadata access function 来取得 runtime type metadata，只不过这一次 metadata access function 属于 Swift runtime。举例来说，要构造 tuple type `(Int, Pair<String>)` 的 metadata，我们先调用 `Pair` 的 metadata access function 得到 `Pair<String>`，再调用 runtime 里的一个入口点得到 `(Int, Pair<String>)`。

> **更多细节**
>
> - Declaration：见 `declarations.tex`
> - Context substitution map：见 `substitution-maps.tex` 的 Nominal Types 一节
> - Structural type：见 `types.tex` 的 More Types 一节

## Protocols

我们的 `identity(_:)` 和 `Pair` 声明抽象于任意具体类型，但这反过来也把它们的 generic parameter `T` 限制在所有类型共有的那点能力上——move、copy、destroy。通过写出 **generic requirement**，一个 generic declaration 可以对用作 generic argument 的具体类型施加各种限制，而这又反过来让它的 generic parameter type 获得那些具体类型提供的新能力。

**Protocol** 规定了一个具体类型可能具备的一些额外能力。Generic declaration 可以对一个 generic parameter type 写出 **conformance requirement**，调用方必须拿一个 **conform** 于这个 protocol 的具体类型来满足它：

```swift
protocol Shape {
  func draw()
}

func drawShapes<S: Shape>(_ shapes: Array<S>) {
  for shape in shapes {
    shape.draw()
  }
}
```

`drawShapes(_:)` 函数接收一个数组，其中的值类型全部相同，且必须 conform 于 `Shape`。到目前为止我们只见过 generic signature `<T>`。更一般地说，一个 generic signature 列出一个或多个 generic parameter type，连同它们的 requirement。`drawShapes(_:)` 的 generic signature 有唯一一条 requirement `[S: Shape]`。带 requirement 的 generic signature 我们采用下面的记法：

```
<S where S: Shape>
```

`drawShapes(_:)` 的 interface type 把这个 generic signature 并进了一个 generic function type：

```
<S where S: Shape> (Array<S>) -> ()
```

我们可以改写 `drawShapes(_:)`，用一个尾随的 `where` 子句来写这条 conformance requirement；或者干脆不给 generic parameter `S` 取名，改用 **opaque parameter type**：

```swift
func drawShapes<S>(_ shapes: Array<S>) where S: Shape
func drawShapes(_ shapes: Array<some Shape>)
```

`drawShapes(_:)` 的这三种写法最终是等价的，因为它们定义出同一个 generic signature（至多相差一个 generic parameter 名字的选择）。一般而言，当同一个底层语言构造因为语法糖而有不止一种拼法时，语义对象会把这些差异「去糖」成同一个统一表示。

> **更多细节**
>
> - Protocol：见 `declarations.tex` 的 Protocols 一节
> - Requirement：见 `declarations.tex` 的 Requirements 一节
> - Generic signature：见 `generic-signatures.tex`

**Qualified lookup.** 有了 generic signature，就可以对 `drawShapes(_:)` 的函数体做类型检查了。`for` 循环引入了一个类型为 `⟦S⟧` 的局部变量 `shape`（再强调一遍：在函数体内部，generic parameter type `S` 表示为 archetype `⟦S⟧`，不过眼下这个区分还不重要）。这个变量在 `for` 循环里被 **member reference expression** `shape.draw` 引用：

```swift
  for shape in shapes {
    shape.draw()
  }
```

我们的 generic signature 带有 conformance requirement `[S: Shape]`，所以调用方必须为 `S` 提供一个 conform 于 `Shape` 的 replacement type。调用方那一侧我们马上就会回头看；而在被调用方内部，这条 requirement 同时告诉我们：archetype `⟦S⟧` conform 于 `Shape`。为了解析 member reference `shape.draw`，type checker 在 base type `⟦S⟧`（也就是 `shape` 的类型）上对标识符 `draw` 做一次 **qualified lookup**。对 archetype 做 qualified lookup 会访问该 archetype 所 conform 的每一个 protocol，于是我们找到并返回 `Shape` protocol 的 `draw()` 方法。

那么 call expression `shape.draw()` 要怎么降级成可执行代码？除了 `S` 的 runtime type metadata 之外，`drawShapes(_:)` 的 calling convention 还有另一个参数，对应 conformance requirement `[S: Shape]`。这个参数用来传递该 conformance 的 **witness table**。Witness table 的 layout 由 protocol 决定；一张「对 `Shape` 的 conformance」的 witness table 只有一个条目，即 `draw()` 方法的实现。所以要调用 `shape.draw()`，我们从 witness table 里加载这个函数指针并调用它，把 `shape` 传进去。

> **更多细节**
>
> - Name lookup：见 `compilation-model.tex` 的 Name Lookup 一节

**Conformances.** 下面这个 `Circle` struct 写出了对 `Shape` protocol 的一条 **conformance**：

```swift
struct Circle: Shape {
  let radius: Double
  func draw() {...}
}
```

**Conformance checker** 确认 `Circle` 的声明里含有 `Shape` 的 `draw()` 方法的一个 **witness**，并把这个事实记录成一条 **normal conformance**。我们把这条 normal conformance 记作 `[Circle: Shape]`。Code generation 阶段访问 `Circle` 时，我们发射它的 runtime type metadata，连同 normal conformance `[Circle: Shape]` 的 witness table。这张 witness table 里含有一个指向 `Circle.draw()` 实现的指针。

现在，我们拿一个装满圆的数组去调用 `drawShapes(_:)`，看看这次调用的 substitution map：

```swift
drawShapes([Circle(radius: 1), Circle(radius: 2)])
```

当 callee 的 generic signature 带有 conformance requirement 时，substitution map 必须为每条 conformance requirement 存一个 conformance。这是「具体的 replacement type 确实按要求 conform 于该 protocol」的那份**证明**。带 conformance 的 substitution map 我们这样记：

```
{S ↦ Circle; [S: Shape] ↦ [Circle: Shape]}
```

为了找到这个 conformance，type checker 拿具体类型与 protocol 做一次 **global conformance lookup**。Global conformance lookup 我们用这个记法：

```
⟨Shape] ⊗ Circle = [Circle: Shape]
```

为这次对 `drawShapes(_:)` 的调用生成代码时，我们逐个访问 substitution map 里的条目，为每个 replacement type 发射一个指向 runtime type metadata 的引用，为每个 conformance 发射一个指向 witness table 的引用。在我们的例子里，传进去的是 `Circle` 的 runtime type metadata 和 `[Circle: Shape]` 的 witness table。

> 译注：本库读的正是这一侧的产物。`__swift5_proto` 里的 protocol conformance descriptor 就是「哪个类型 conform 了哪个 protocol」这条记录，而 witness 的归属（某个成员到底是哪条 conformance 的 witness）本库按 (conforming type, protocol, where 指纹, retroactive) 逐条归属，见 [PerConformanceAttribution.md](../PerConformanceAttribution.md)。Witness table 本身在被 strip 过的系统框架里没有符号，本库改为按槽位投影，见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)。

> **更多细节**
>
> - Conformance：见 `conformances.tex`（中译 [SwiftGenericsConformances.md](SwiftGenericsConformances.md)）
> - Conformance lookup：见 `conformances.tex` 的 Conformance Lookup 一节

**Existential types.** 注意 `drawShapes(_:)` 操作的是一个**同质的**（homogeneous）形状数组。数组里元素个数任意，但 `drawShapes(_:)` 只收到 `S` 的一份 runtime type metadata，以及 conformance requirement `[S: Shape]` 的一张 witness table，这两样东西合起来描述了数组中每个元素的行为。如果我们想要的是一个接收**异质的**（heterogeneous）形状数组的函数，可以把 **existential type** 用作数组的元素类型：

```swift
func drawShapes(_ shapes: Array<any Shape>) {
  for shape in shapes {
    shape.draw()
  }
}
```

这个函数以一种新方式使用了 `Shape` protocol。Existential type `any Shape` 是一个容器，装着某个具体类型的值，连同它的 runtime type metadata 和描述该 conformance 的 witness table。这个容器把小的值 inline 存放，否则就指向一个堆上分配的 box。注意对比：前一个版本的 `drawShapes(_:)` 里是类型 `Array<S>`，这里则是 `Array<any Shape>`。后者的每一个元素都带有自己的 runtime type metadata 与 witness table，所以我们可以在一个数组里混装多种形状。在实现层面，existential type 是搭建在泛型系统的核心原语之上的。

> 译注：existential 容器的尺寸（opaque 形式 `32 + 8N`、class-bound `8·(1+N)`、`any Error` 8 字节）本库有一份离线实现 `ExistentialLayoutBridge`，它从每个 protocol 的 class constraint 推出容器形状，见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

> **更多细节**
>
> - Existential type：见 `existential-types.tex`（中译 [SwiftGenericsExistentialTypes.md](SwiftGenericsExistentialTypes.md)）

## Associated Types

标准库的 `IteratorProtocol` 声明了一个 associated type。这让我们可以抽象于「元素类型取决于 conformance」的那类迭代器：

```swift
protocol IteratorProtocol {
  associatedtype Element
  mutating func next() -> Element?
}
```

一个 conforming type 必须声明一个名为 `Element` 的成员类型，以及一个返回该类型的 optional 值的 `next()` 方法。这个成员类型（可以是 type alias，也可以是 nominal type）就是 associated type `Element` 的 **type witness**。

我们来声明一个 conform 于 `IteratorProtocol` 的 `Nat` 类型，它的 `Element` 类型是 `Int`，用来生成一个无穷的连续自然数流：

```swift
struct Nat: IteratorProtocol {
  typealias Element = Int  // (can also be omitted in this case)
  var x = 0

  mutating func next() -> Int? {
    defer { x += 1 }
    return x
  }
}
```

我们说：在 conformance `[Nat: IteratorProtocol]` 中，`Int` 是 `[IteratorProtocol]Element` 的 **type witness**。用我们的类型代入代数来表达，就是对 normal conformance 做 type witness **projection** 操作：

```
⟨IteratorProtocol|Element ⊗ [Nat: IteratorProtocol] = Int
```

（更准确地说，这里的 type witness 是那个 `Element` **type alias type**，它的 canonical type 是 `Int`。）最后要说的是，上面 `Element` type alias 的声明其实可以省略，那种情况下 **associated type inference** 能替我们推断出来。

> **更多细节**
>
> - Type witness：见 `conformances.tex` 的 Type Witnesses 一节
> - Associated type inference：见 `conformances.tex` 的 Associated Conformances 一节

**Dependent member types.** 下面这个函数从一个迭代器里读出一对元素：

```swift
func readTwo<I: IteratorProtocol>(_ iter: inout I) -> Pair<I.Element> {
  return Pair(first: iter.next()!, second: iter.next()!)
}
```

返回类型是 generic nominal type `Pair<I.Element>`，由 `Pair` 的声明和 generic argument 类型 `I.Element` 构造而成。这个 generic argument 类型是一个 **dependent member type**，由 base type `I` 和一个指向 associated type declaration `[IteratorProtocol]Element` 的引用组成。这个 dependent member type 代表的是 conformance `[I: IteratorProtocol]` 里的那个 type witness。

假设我们拿一个 `Nat` 类型的值去调用 `readTwo(_:)`：

```swift
var iter = Nat()
print(readTwo(&iter))
```

这次调用的 substitution map 里存着 replacement type `Nat`，以及 `Nat` 对 `IteratorProtocol` 的 conformance。把这张 substitution map 记作 `Σ`：

```
Σ := {I ↦ Nat;
      [I: IteratorProtocol] ↦ [Nat: IteratorProtocol]}
```

要得到这次调用的返回类型，我们求值 `Pair<I.Element> ⊗ Σ`。把 substitution map 应用到 generic nominal type 上，就是把它递归地应用到每个 generic argument 上，所以剩下要定义的是 `I.Element ⊗ Σ`。既然这个 dependent member type 抽象的是 conformance 里的 type witness，那就必然有 `I.Element ⊗ Σ = Int`。我们最终会推出下面这个把「dependent member type 代入」与「type witness projection」联系起来的等式：

```
I.Element ⊗ Σ
  = ⟨IteratorProtocol|Element ⊗ [I: IteratorProtocol] ⊗ Σ
  = ⟨IteratorProtocol|Element ⊗ [Nat: IteratorProtocol]
  = Int
```

有了上面这些，就可以断定我们这次对 `readTwo(_:)` 的调用的返回类型是 `Pair<I.Element> ⊗ Σ = Pair<Int>`。

> **更多细节**
>
> - Dependent member type 的代入：见 `conformances.tex` 的 Abstract Conformances 一节，以及 `conformance-paths.tex`（中译 [SwiftGenericsConformancePaths.md](SwiftGenericsConformancePaths.md)）

**Type parameters.** Generic parameter type 与 dependent member type 是 **type parameter** 的两个种类。`readTwo(_:)` 的 generic signature 定义了两个 type parameter：`I` 和 `I.Element`。

和 generic parameter type 一样，dependent member type 在 generic function 的函数体里也映射为 archetype。现在可以多透露一点 archetype 的结构了：archetype 把一个 type parameter 和一个 generic signature 打包在一起。Type parameter 像是一个「名字」，只有相对于某个 generic signature 才说得清；而 archetype 本身就「知道」自己受哪些 requirement 约束。

> 译注：本库的 `DependentMemberTypeBridge` 做的正是这段描述的离线版本——当一个字段的类型停在 `I.Element` 这样的 dependent member type 上时，它去 `__swift5_assocty` 里查该 conformance 的 associated type witness，再把 base 自身的 generic argument 代进去，从而把 `Array<Int16>.Element` 落到 `Int16`。见 [StaticLayoutEngine.md](../StaticLayoutEngine.md)。

> **更多细节**
>
> - Type parameter：见 `types.tex` 的 Fundamental Types 一节
> - Primary archetype：见 `archetypes.tex` 的 Primary Archetypes 一节

**Bound and unbound.** Dependent member type 其实有两个种类。**Bound** dependent member type 引用的是一个 associated type declaration，我们把它记作 `I.[IteratorProtocol]Element`——尽管这不是合法的语言语法。**Unbound** dependent member type 引用的是一个标识符，我们按源码语言的风格记作 `I.Element`。两种形式的表示截然不同，但我们会看到它们在很强的意义上是等价的。为了记法上的方便，我们往往偏好 unbound 形式；不过在后面研究 type substitution 时，bound dependent member type 会变得重要起来。

> **更多细节**
>
> - Member type representation：见 `type-resolution.tex` 的 Identifier Type Representations 一节
> - Bound type parameter：见 `generic-signatures.tex` 的 Bound Type Parameters 一节

**Code generation.** 在 `readTwo(_:)` 的函数体内部，call expression `iter.next()` 的类型是 `⟦I.Element⟧?`，我们用 `!` 运算符强制解包，得到一个类型为 `⟦I.Element⟧` 的值。要抽象地操作这个类型的值，我们需要它的 runtime type metadata。

要在运行时把一个 dependent member type 的 runtime type metadata 恢复出来，我们去查该 conformance 的 witness table。这与编译期的做法互为镜像：编译期我们是通过从 conformance 里 projection 出一个 type witness 来代入 dependent member type 的。

一张「对 `IteratorProtocol` 的 conformance」的 witness table 由一对函数指针组成：第一个用来恢复 `Element` 的 runtime type metadata，第二个是 `next()` 的实现。因此我们那张 `[Nat: IteratorProtocol]` 的 witness table 引用的是标准库里 `Int` 的 runtime type metadata。

**Same-type requirements.** 为了引入另一种基本的 requirement 种类，我们换个方式把 `Pair` 和 `IteratorProtocol` 组合起来，写一个接收两个迭代器、各读一个元素的函数：

```swift
func readTwoParallel<I, J>(_ i: I, _ j: J) -> Pair<I.Element>
    where I: IteratorProtocol, J: IteratorProtocol,
          I.Element == J.Element {
  return Pair(first: i.next()!, second: j.next()!)
}
```

`readTwoParallel(_:)` 的 generic signature 写出了 **same-type requirement** `[I.Element == J.Element]`：

```
<I, J where I: IteratorProtocol, J: IteratorProtocol,
            I.Element == J.Element>
```

这个 generic signature 定义了四个 type parameter：`I`、`J`、`I.Element` 和 `J.Element`，其中后两个抽象的是同一个具体类型，构成一个 **equivalence class**。用某个有代表性的 type parameter 来指代整个 equivalence class 往往很方便。为了让这个选择是确定性的，我们给 type parameter **排序**，并把一个 equivalence class 里最小的那个 type parameter 称作 **reduced type**。在我们的例子里，`I.Element` 是 `J.Element` 的 reduced type。

有了 same-type requirement 之后，一个 archetype 代表的是一个 reduced type parameter（因而也就代表了一整个 type parameter 的 equivalence class）。在 `readTwoParallel(_:)` 的函数体里，表达式 `i.next()!` 与 `j.next()!` 都返回类型 `⟦I.Element⟧`，而对 `Pair` 构造器的调用是带着这张 substitution map 做出的：

```
{T ↦ ⟦I.Element⟧}
```

> **更多细节**
>
> - Reduced type parameter：见 `generic-signatures.tex` 的 Reduced Type Parameters 一节
> - Type parameter graph：见 `archetypes.tex` 的 The Type Parameter Graph 一节

**Checking generic arguments.** 对一次 `readTwoParallel(_:)` 的调用做类型检查时，我们必须确认 same-type requirement 得到满足。假设我们定义两个新的迭代器类型 `BabyNames` 和 `CatNames`，两者都用 `String` 来 witness `Element` 这个 associated type，然后拿它们去调用 `readTwoParallel(_:)`：

```swift
var i = BabyNames()
var j = CatNames()
print(readTwoParallel(&i, &j))
```

这次调用带的是这张 substitution map：

```
Σ := {I ↦ BabyNames,
      J ↦ CatNames;
      [I: IteratorProtocol] ↦ [BabyNames: IteratorProtocol]
      [J: IteratorProtocol] ↦ [CatNames: IteratorProtocol]}
```

Type checker 把 `Σ` 应用到 same-type requirement 的两边，得到 `I.Element ⊗ Σ = String` 和 `J.Element ⊗ Σ = String`。两边结果都是 `String`，于是我们得到下面这条 **substituted requirement**：

```
[I.Element == J.Element] ⊗ Σ = [String == String]
```

这条 substituted requirement 得到满足，所以代码是良类型的，而且我们看出这次调用返回 `Pair<String>`。反过来，假设我们把 `I` 代入成 `Nat`：

```swift
var i = Nat()
var j = CatNames()
print(readTwoParallel(&i, &j))  // error
```

这种情况下我们得到的 substituted requirement 是 `[Int == String]`，它不被满足，所以这次调用是病构的，type checker 必须报出一个错误。

> **更多细节**
>
> - 检查 generic argument：见 `type-resolution.tex` 的 Generic Arguments 一节

## Associated Requirements

Protocol 可以对自己的 associated type 施加 **associated requirement**，conforming type 随后必须满足这些 requirement。正是这项能力，给了 Swift 泛型很大一部分独特风味。最简单的例子大概是标准库里的 `Sequence` protocol，它抽象的是「能按需产生一个新迭代器」的那类类型：

```swift
protocol Sequence {
  associatedtype Element
  associatedtype Iterator: IteratorProtocol
    where Element == Iterator.Element

  func makeIterator() -> Iterator
}
```

一个 protocol 的 associated requirement 记录在该 protocol 的 **requirement signature** 里。`Sequence` protocol 写出了两条 associated requirement：

- Conformance requirement `[Self.Iterator: IteratorProtocol]`，这里用的是加糖形式，写作 `Iterator` 这个 associated type 的继承子句里的一个 constraint type。
- Same-type requirement `[Self.Element == Self.Iterator.Element]`，我们把它写在附着于该 associated type 的尾随 `where` 子句里。

Associated requirement 和 generic signature 里的 requirement 是一类东西，只不过它们扎根于 protocol 的 `Self` 类型。同样地，写出它们的等价语法形式不止一种。比如我们可以把那条 conformance requirement 显式地写出来，而上面那个 `where` 子句也可以改附在 protocol 本身上，语义效果相同。

现在考虑下面这个 generic signature，把它叫作 `G`：

```
<T, U where T: Sequence, U: Sequence,
            T.Element == U.Element>
```

我们可以把 `G` 的 type parameter 按 equivalence class 分类，来非正式地描述它：

- `T`，conform 于 `Sequence`。
- `U`，conform 于 `Sequence`。
- `T.Element`、`U.Element`、`T.Iterator.Element` 和 `U.Iterator.Element`，它们全在同一个 equivalence class 里。
- `T.Iterator`，conform 于 `IteratorProtocol`。
- `U.Iterator`，conform 于 `IteratorProtocol`。

为了让这类分析变得精确，我们会发展出一套 **derived requirement** 的理论，用来推断那些没有被显式写出、却是其它 requirement 之逻辑后果的 requirement。下面是 `G` 的几条有意思的 derived requirement：

```
[T.Iterator: IteratorProtocol]
[U.Iterator: IteratorProtocol]
[T.Element == T.Iterator.Element]
[U.Element == U.Iterator.Element]
[T.Iterator.Element == U.Iterator.Element]
```

讲到这里值得澄清一点：type parameter 具有递归结构；`U.Iterator.Element` 的 base type 是另一个 dependent member type，即 `U.Iterator`。要注意，并非每一种这样的组合都有意义。Derived requirement 的理论同时也会刻画出一个 generic signature 的 **valid type parameter** 是哪个子集。

**Conformances.** 一条 normal conformance 还会为它那个 protocol 的每条 associated conformance requirement 存一个 **associated conformance**。**Associated conformance projection** 操作把这个 conformance 取回来。在运行时，一条 conformance 的 witness table 会为每个 associated conformance 留一个对应的条目。举例来说，一张「对 `Sequence` 的 conformance」的 witness table 有四个条目：

1. `Element` 的一个 metadata access function。
2. `Iterator` 的一个 metadata access function。
3. `[Self.Iterator: IteratorProtocol]` 的一个 **witness table access function**。
4. `makeIterator()` 实现的一个函数指针。

**Protocol inheritance** 关系表示为一条 subject type 是 `Self` 的 associated conformance requirement。例如标准库的 `Collection` protocol 继承自 `Sequence`，所以 associated conformance requirement `[Self: Sequence]` 出现在 `Collection` 的 requirement signature 里：

```swift
protocol Collection: Sequence {...}
```

从一条 conformance `[Array<Int>: Collection]` 出发，我们可以经由 associated conformance projection 拿到对 `Sequence` 的 conformance：

```
⟨Self: Sequence] ⊗ [Array<Int>: Collection] = [Array<Int>: Sequence]
```

这也意味着在运行时，我们可以从一张「对 `Collection` 的 conformance」的 witness table，恢复出一张「对 `Sequence` 的 conformance」的 witness table。`Collection` protocol 的其它 associated requirement 我们到时候再细看。这会把我们引向**递归的** associated conformance requirement 这个话题；我们将会证明，它让类型代入代数足以编码任意可计算函数。

> **更多细节**
>
> - Requirement signature：见 `generic-signatures.tex` 的 Requirement Signatures 一节
> - Derived requirement：见 `generic-signatures.tex` 的 Derived Requirements 一节
> - Valid type parameter：见 `generic-signatures.tex` 的 Valid Type Parameters 一节
> - Associated conformance：见 `conformances.tex` 的 Associated Conformances 一节
> - 递归 conformance：见 `conformance-paths.tex` 的 Recursive Conformances 一节

## Related Work

一种围绕「类型的运行时表示」建立的 calling convention，早在 1996 年的一篇论文里就被探讨过（Harper 与 Morrisett，《Compiling Polymorphism Using Intensional Type Analysis》；原书正文写的是 1996 年，参考文献条目标的则是 POPL '95）。Swift 的 protocol 在精神上与 Haskell 的 type class 相近，后者的描述见 Wadler 与 Blott 1989 的《How to Make Ad-Hoc Polymorphism Less Ad Hoc》，以及后续的 Hall 等 1996《Type Classes in Haskell》与 Peyton Jones 等 1997《Type classes: an exploration of the design space》。Swift 的 witness table 走的是 type class 的「dictionary passing」实现策略。

Associated type 由 Chakravarty 等 2005 的《Associated Types with Class》引入。用 Swift 的说法，那篇论文最初的表述大致对应于这样一个世界：每个 associated type 都由一个各不相同的嵌套 nominal type 来 witness，模型里没有 associated requirement。他们论文里最初的示范例子翻成 Swift 是这样：

```swift
protocol ArrayElem {
  associatedtype Array
  func index(_: Array, _: Int) -> Self
}
```

随后的工作（Chakravarty 等 2005，《Associated Type Synonyms》）引入了 **associated type synonym**。在 Swift 里，这对应于由一个 type alias 来 witness 的 associated type，同样没有 associated requirement。那篇论文的示范例子在 Swift 里长这样：

```swift
protocol Collects {
  associatedtype Elem
  static var empty: Self { get }
  func insert(_: Elem) -> Self
  func toList() -> [Elem]
}
```

Haskell 圈子里其它相关的论文包括 Schrijvers 等 2008 的《Type Checking with Open Type Functions》和 Kiselyov 等 2009 的《Fun with type functions》。

**C++.** 在很多程序员眼里 C++ template 就是「泛型编程」的同义词，但和多数带 parametric polymorphism 的语言相比，C++ 其实相当不寻常，因为 template 在本质上是语法性的。编译一条 template 声明只做极少量的语义分析，大部分类型检查都推迟到 template 展开**之后**。语言里没有「对 template parameter 的 requirement」这个正式概念，所以某个展开点上 template 展开成功还是失败，完全取决于 template 的函数体如何使用给定的 template argument。

这种不寻常的灵活性成就了一些高级元编程技巧（Vandevoorde、Josuttis 与 Gregor 2017，《C++ Templates: The Complete Guide》）。另一方面，由于 template 声明的函数体必须在每个展开点都可见，大量使用 template 从根本上与分离编译相冲突。库作者可能发现自己不得不把大量逻辑写进头文件里，而 template 展开失败时的错误信息又往往难以读懂。

Swift 的「value semantics」是一种源自 C++ 社区的哲学的演化产物（Stepanov 与 McJones 2019，《Elements of Programming》）。Swift 泛型还从「C++0x concepts」那里汲取了灵感——那是一份给 C++ template 加上受检 requirement 的提案，其基础正是 type class 与 associated type（Gregor 等 2006《Concepts: Linguistic Support for Generic Programming in C++》，以及 Siek 与 Lumsdaine 2005《Essential Language Support for Generic Programming》）。Concept 甚至能写出 associated requirement，只是这件事的全部后果，当时的作者们大概还没完全意识到：

> *「Concept 常常包含对 associated type 的 requirement。例如，一个容器的 associated iterator `A` 会被要求 model `Iterator` 这个 concept。这种形式的 concept 组合与 refinement 略有不同，但两者足够接近，我们不想让表述变得杂乱［……］」*

**Rust.** Rust 泛型是分离地做类型检查的，但 Rust 没有为未 specialize 的泛型代码定义 calling convention，因此没有分离编译。取而代之的是，generic function 的实现会针对每一组不同的 generic argument 被 **specialize**（也叫 **monomorphize**）一次。

Rust 的 **trait** 与 Swift 的 protocol 相似；trait 可以声明 associated type 和 associated conformance requirement。Rust 泛型还允许一些 Swift 不支持的抽象，例如 lifetime 变量、generic associated type（Rust RFC 1598）和 const generic（Rust RFC 2000）。反过来，Rust 不允许完全一般地写出 same-type requirement（见 rust-lang/rust issue 20041）。作为替代，trait bound 可以用一种形似 Swift 的 parameterized protocol type（`declarations.tex` 的 Protocols 一节）的语法来约束 associated type；不过我们会在 `completion.tex`（中译 [SwiftGenericsCompletion.md](SwiftGenericsCompletion.md)） 的一个例子里证明，Swift 的 same-type requirement 更一般——那个例子讨论的是一个 protocol `S`，其 associated type `C` 又 conform 于 `S` 本身，由此产生无穷多个 equivalence class。

Rust 的「`where` 子句推演」（`where` clause elaboration）比 Swift 的 derived requirement 形式体系更受限，associated requirement 有时需要在 generic declaration 的 `where` 子句里重新写一遍（见 rust-lang/rust issue 20671）。形式化 Rust trait 的一次早期尝试见 2015 年的一篇博士论文（Milewski 2015，《Formalizing Rust traits》，不列颠哥伦比亚大学）。更近的一次努力是「Chalk」，一个基于 Horn 子句、类 Prolog 的求解器实现（The Chalk Book）。

**Java.** 传统的 Java 泛型的实现方式是在编译期擦除 generic argument 类型，于是 generic parameter type 的值一律表示为对象指针，原始值类型必须先 boxing。这避开了 dependent layout 的复杂性，代价是更多的运行时检查与堆分配。Java 泛型还支持 **variance**，即同一个 generic type 的不同实例化之间的一种 subtyping，它按对应 generic argument 上的 subtype 关系来定义（Angelika Langer，《Java Generics FAQs》，2004）。目前正在进行的一项工作是扩展 Java 虚拟机，使其支持用户定义的值类型与 reified 泛型（Project Valhalla）。

**Hylo.** Hylo 是一门研究性语言，重点在 mutable value semantics（Abrahams 与 Racordon，hylo-lang.org）。Hylo 的泛型编程能力与 Swift、Rust 相似。Hylo 的编译器实现吸收了本书的一些想法，用字符串重写理论来推理 generic requirement（Racordon 2024，hylo-lang/hylo PR #1482）。

---

> 译自 `docs/Generics/chapters/introduction.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
