# Compilation Model（Swift 泛型实现手册章节中译）

> **来源**：Swift 编译器源码树 `docs/Generics/chapters/compilation-model.tex`（《Compiling Swift Generics》一书的「Compilation Model」一章），译自本机 `/Volumes/SwiftProjects/swift-project/swift` 检出的 `swift-6.4.0-RELEASE`（该文件最后一次改动 `2349b5f6`，2025-11-11）。原书作者 Slava Pestov，随 swift 仓库以 Apache License 2.0 with Runtime Library Exception 发布；本文是该许可下的中译衍生作品。
>
> **这份译文的用途**：本章讲的是 Swift 编译器「正向」的工作方式——module 怎么组织、declaration 怎么被惰性地类型检查、`.swiftmodule` 与 `.swiftinterface` 各自存了什么。本库做的事恰好是它的逆向：从 Mach-O 二进制里把这条流水线的**产物**读回成声明模型，再打印成 interface。因此本章的 Module System 一节是全书与本库贴得最紧的一段——它解释了为什么二进制里读得到 generic signature 却读不到 `where` 子句的原始写法、为什么函数体除 `@inlinable` 外一律不在、以及 library evolution 会在符号表里留下什么痕迹。
>
> **术语**：书中定义的术语一律保留英文（Swift driver、Swift frontend、frontend job、primary file / secondary file、compilation mode、delayed parsing、request evaluator、request、dependency sink / dependency source、module declaration、file unit、serialized module、textual interface、library evolution、resilience、name lookup、scope tree……），不硬造中文对应词。**所有命令行 flag（`-wmo`、`-emit-module`、`-enable-library-evolution` 等）一律保留英文原样**——原书为它们单独建了一份索引。交叉引用写成原书章节文件名加原节名，例如「`declarations.tex`（中译 [SwiftGenericsDeclarations.md](SwiftGenericsDeclarations.md)） 的 Requirements 一节」，文件都在源码树 `docs/Generics/chapters/` 下；本章内部的例子按原书的英文标题引用。

---

大多数开发者是通过 Xcode 的构建系统或者 Swift package manager 跟 Swift 编译器打交道的，但为了简单起见，这里只考虑在命令行里直接调用 `swiftc`。`swiftc` 命令运行的是 **Swift driver**，driver 再去调用 **Swift frontend** 程序，由后者实际编译每个源文件；之后按使用模式的不同，driver 还会运行别的工具（比如 linker）来产出最终的构建产物。本书绝大部分内容讲的是 frontend，不过这里先把 driver 的工作方式简要过一遍。

在 Swift 的 module 系统里，一个 module 的所有源文件必须一起构建。Swift driver 从命令行接收一串源文件，它们构成正在构建的 **main module**。默认情况下，driver 从 main module 生成一个可执行文件：

```
$ swiftc main.swift other.swift stuff.swift
```

可执行文件必须定义一个 **main function**，即运行该可执行文件时被调用的入口点。有三种办法做到这件事：

1. 如果用户只给 driver 传了一个源文件，这个文件就成为该 module 的 **main source file**。如果有多个源文件而其中一个叫 `main.swift`，那么它成为 main source file。main source file 的特殊之处在于它可以在顶层（函数体之外）写语句。顶层语句被收集成 **top-level code declaration**，frontend 会生成一个按源码顺序执行每条 top-level code declaration 的 main function。除 main source file 之外的源文件不能在顶层写语句。
2. 在没有 main source file 的情况下，用户可以给某个 struct、enum 或 class 声明加上 `@main` 属性，此时该声明必须包含一个名为 `main()` 的 static 方法，这个方法就成为 main 入口点。该属性在 Swift 5.3 引入（SE-0281）。
3. 更早的 `@NSApplicationMain` 和 `@UIApplicationMain` 属性自 Swift 5.10 起已废弃（SE-0383），它们提供的是 Apple 平台专有的类似机制。把其中之一加在分别 conform to `NSApplicationMain` 或 `UIApplicationMain` 的 class 上，会生成一个调用系统框架函数 `NSApplicationMain()` 或 `UIApplicationMain()` 的 main 入口点。

`-emit-library` 和 `-emit-module` flag 指示 driver 生成一个 shared library，连同一个 **serialized module** 文件——后者是编译器 import 这个库时要读的东西（见本章 Module System 一节）：

```
$ swiftc algorithm.swift utils.swift -module-name SudokuSolver
      -emit-library -emit-module
```

### Frontend jobs

Swift frontend 本身是单线程的，但 driver 可以并行运行多个 **frontend job**，从而吃到多核的好处。每个 frontend job 编译一个或多个源文件，这些是该 frontend job 的 **primary source file**；所有非 primary 的源文件则是该 job 的 **secondary source file**。哪些源文件成为哪个 frontend job 的 primary file，由 **compilation mode** 决定：

- driver flag `-wmo` 选择 **whole module mode**（whole module optimization），通常用于 release 构建。这个模式下 driver 只排一个 frontend job，它的 primary file 是 main module 的全部源文件，没有 secondary file。whole module mode 下 frontend 能跨源文件边界做更激进的优化，这也正是它用于 release 构建的原因。

  > 译注：这条「跨源文件边界更激进」的代价，本库在读二进制时天天遇到：whole module optimization 下 `internal` 及更窄的声明不再是 dead function elimination 的锚点，实现体会被整个删掉，而 vtable 槽位为了布局仍然保留——于是二进制里出现「有 method descriptor、却没有实现地址」的槽位。本库如何识别并标注这种槽位，见 [ClassMemberKeywordRecovery.md](../ClassMemberKeywordRecovery.md) 与 [FinalKeywordAndLazyAccessorTypeRecovery.md](../FinalKeywordAndLazyAccessorTypeRecovery.md)。

- driver flag `-disable-batch-mode` 选择 **single file mode**，每个源文件一个 frontend job。这个模式下每个 frontend job 只有一个 primary file，其余全是 secondary file。single file mode 在 Swift 4.1 之前是 debug 构建的默认模式，如今只用来测试编译器。

  single file mode 的开销在于 frontend job 之间的重复劳动：如果两个源文件都引用了第三个源文件里的某个声明，三个 frontend job 都得把那个声明解析并类型检查一遍；frontend job 之间既没有缓存，也没有共享状态。（接下来两节分别讲 frontend 如何用 delayed parsing 和 request evaluator 来应付 secondary file。）

- driver flag `-enable-batch-mode` 选择 **batch mode**，它是 whole module 与 single file 之间的折中。batch mode 把源文件列表按一个批次大小上限切成若干固定大小的批，每批里的源文件成为一个 frontend job 的 primary file。

  一个 frontend job 编译多个 primary file，就把花在 secondary file 上的解析与类型检查成本摊薄了；与此同时它仍然排出多个 frontend job，好在多核系统上并行。batch mode 在 Swift 4.2 首次引入，现在是 debug 构建的默认模式。

每个源文件恰好是一个 frontend job 的 primary source file；而在单个 frontend job 内部，primary file 与 secondary file 构成该 module 全部源文件的一个划分。因此单个源文件就是并行的最小单位。并发 frontend job 的数量默认由 CPU 核数决定，可以用 driver flag `-j` 覆盖。如果 frontend job 多到无法同时运行，driver 会把它们排队，等别的 job 完成再启动。在 batch mode 和 single file mode 下，driver 还可以复用此前编译的结果来做 **incremental build**，进一步加快编译；incremental build 见本章 Incremental Builds 一节。

driver flag `-###` 执行一次「空跑」，把所有要运行的命令打印出来而不真的做事。下面这个例子里 driver 排了三个 frontend job，每个 job 有一个 primary source file 和两个 secondary file。最后一条命令是 linker 调用，它把每个 frontend job 的输出合成我们的二进制可执行文件。

```
$ swiftc m.swift v.swift c.swift -###
swift-frontend -frontend -c -primary-file m.swift v.swift c.swift ...
swift-frontend -frontend -c m.swift -primary-file v.swift c.swift ...
swift-frontend -frontend -c m.swift v.swift -primary-file c.swift ...
ld m.o v.o c.o -o main
```

### Compilation pipeline

原书在此给出 Swift frontend 的全局视角；它与经典的多趟编译器设计相仿（可参考 Muchnick 1997,《Advanced Compiler Design and Implementation》，或 Cooper & Torczon 2004,《Engineering a Compiler》）：

1. **Parse：** 解析源文件，构建 **abstract syntax tree**。
2. **Sema：** 执行语义分析，产出类型检查过的语法树。（马上就会看到，前两个阶段并不是完全顺序执行的。）
3. **SILGen：** 把语法树 lower 成 **raw SIL**。SIL 就是 Swift Intermediate Language，一种 SSA（static single assignment）形式的程序表示。
4. **SILOptimizer：** raw SIL 经过一系列 **mandatory pass** 变成 **canonical SIL**；这些 pass 分析控制流图并产出诊断，例如 **definite initialization** 保证所有存储位置都被初始化过。

   指定命令行 flag `-O` 时，canonical SIL 还会再经过一系列 **performance pass**，以改善运行时性能和代码体积。
5. **IRGen：** 优化后的 SIL 被转换成 LLVM IR。
6. **LLVM：** 最后 LLVM IR 交给 LLVM，由它做各种更低层的优化并生成机器码。（LLVM 当然就是那个旧称「Low Level Virtual Machine」的项目。）

```
Parse → Sema → SILGen → SILOptimizer → IRGen → LLVM
```

> 译注：原书此处是一张 TikZ 流程图（The compilation pipeline），这里用一行箭头图转述；图的原貌见官方 PDF 对应章节。

> 译注：本库的输入正是这条流水线最后两级的产物——IRGen 发射到 `__swift5_types` / `__swift5_proto` 等 section 里的 metadata，加上 linker 写下的符号表。换句话说，本库从不解析源码、不走 Sema，能看见的只有 IRGen 认为值得写进二进制的那部分事实。这条边界划在哪里，见 [SelfContainedABILayer.md](../SelfContainedABILayer.md)。

### Debugging flags

编译器提供了各种命令行 flag，可以让流水线跑到某个阶段为止，并把该阶段的输出 dump 到终端（或者配合 `-o` flag 输出到别的文件）。它们在调试编译器时很有用：

- `-dump-parse` 只运行 parser，并把语法树打印成一个 **s-expression**。（这个说法来自 Lisp。s-expression 用嵌套的括号列表表示树结构；例如 `(a (b c) d)` 是一个有三个子节点 `a`、`(b c)`、`d` 的节点，而 `(b c)` 又有两个子节点 `b` 和 `c`。）
- `-dump-ast` 只运行 parser 和 Sema，并把类型检查过的语法树打印成 s-expression。
- `-print-ast` 把类型检查过的语法树打印成接近源码写法的形式。想知道编译器都合成了哪些声明时它很有用，比如 `Equatable` 这类 protocol 的 derived conformance。
- `-emit-silgen` 只运行 Sema 和 SILGen，并打印 SILGen 输出的 raw SIL。
- `-emit-sil` 打印 SIL optimizer 输出的 canonical SIL。想看 performance 流水线的输出，还要同时传 `-O`。
- `-emit-ir` 打印 IRGen 输出的 LLVM IR。
- `-S` 打印 LLVM 输出的汇编。

流水线的每个阶段都可能发出警告和错误，统称 **diagnostic**。parser 会尝试从错误中恢复，所以存在解析错误并不妨碍 Sema 运行。反过来，如果 Sema 发出了错误，编译就此停止：SILGen 不会试图把一棵无效的抽象语法树 lower 成 SIL（但 SILGen 自己也能发出诊断，其中就包括对 secondary file 里的声明做惰性类型检查所产生的那些）。

编译流水线会因 driver 和 frontend 被要求产出什么而略有不同。当 frontend 被要求只发射 serialized module 文件而不发射 object file 时，编译在 SIL optimizer 之后就停止。当要生成 textual interface 文件或 TBD 文件时，编译在 Sema 之后停止。（textual interface 见本章 Module System 一节。TBD 文件是一份 shared library 的符号清单，可供 linker 消费，且比生成 shared library 本身快得多；这里不展开讲。）

### Frontend flags

上面列出的那些用于 dump 各阶段编译器输出的 flag，driver 和 frontend 都认得，driver 会把它们往下传给 frontend。另外还有许多用于编译器开发与调试的 flag 只有 frontend 认识。如果调用 driver 时把 `-frontend` 作为第一个命令行 flag，那么 driver 不再去排 frontend job，而是直接派生单个 frontend job，把命令行余下的部分原封不动传给它：

```
$ swiftc -frontend -typecheck -primary-file a.swift b.swift
```

另一种把 flag 传给 frontend 的机制是 driver flag `-Xfrontend`。这个 flag 出现在命令行调用里时，driver 照常去排 job，但紧跟其后的那个命令行参数会被直接传给每个 frontend job：

```
$ swiftc a.swift b.swift -Xfrontend -dump-requirement-machine
```

## Name Lookup

Name lookup 是把 identifier 解析到 declaration 的过程。Swift 编译器没有单独的「name binding」阶段；name lookup 是在 frontend 流程的各个地方按需查询的。大体上，name lookup 分两类：**unqualified lookup** 和 **qualified lookup**。unqualified lookup 解析单个 identifier「`foo`」，而 qualified lookup 相对于一个 base 解析 identifier「`bar`」，比如 member reference expression「`foo.bar`」里那样。在这两种基本形式之外，还有三个重要变体，分别用于查找别的 module 里的 top-level declaration、解析 operator，以及对 Objective-C 方法做动态查找。

### Unqualified lookup

unqualified lookup 总是相对于 identifier 实际出现的那个 source location 来做。这个 source location 既可能在 primary file 里，也可能在 secondary file 里。

unqualified lookup 查阅的是源文件的 **scope tree**，它由遍历源文件的抽象语法树构建而来。根 scope 就是源文件本身。每个 scope 有一个关联的 source range 和零个或多个子 scope；每个子 scope 的 source range 必须是其父 scope 的 source range 的子区间，而兄弟 scope 的 source range 互不相交。每个 scope 引入零个或多个 **variable binding**。

unqualified lookup 先找到包含该 source location 的最内层 scope，然后沿 scope tree 一路向上走到根，在每个父节点里搜索以给定 identifier 命名的 binding。如果查找一直走到根节点，接着就执行一次 **top-level lookup**：它先在 main module 的所有源文件里、再在所有 import 进来的 module 里，寻找以该 identifier 命名的 top-level declaration。

frontend flag `-dump-scope-maps` 会 dump main module 里每个源文件的 scope map。例如对这段程序：

```swift
func id<T>(_ t: T) -> T {
  return t
}
```

我们得到下面的 scope map：

```
ASTSourceFileScope 0x14c131908, [1:1 - 5:1] 'id.swift'
`-AbstractFunctionDeclScope 0x14c1392c0, [1:1 - 4:1] 'id(_:)'
  `-GenericParamScope 0x14c139118, [1:1 - 4:1] param 0 'T'
    |-ParameterListScope 0x14c139238, [1:11 - 1:18] 
    `-FunctionBodyScope 0x14c1392c0, [1:25 - 4:1] 
      `-BraceStmtScope 0x14c139510, [1:25 - 4:1] 
        `-PatternEntryDeclScope 0x14c139450, [2:7 - 4:1] entry 0 'x'
          `-PatternEntryInitializerScope 0x14c139450, [2:11 - 2:11] entry 0 'x'
```

unqualified lookup 是 type resolution 的重要一环（见 `type-resolution.tex`（中译 [SwiftGenericsTypeResolution.md](SwiftGenericsTypeResolution.md)） 的 Identifier Type Representations 一节）。

### Qualified lookup

qualified lookup 在一组 type declaration 里搜索具有给定名字的成员。qualified lookup 会递归访问每个 struct、enum、class 声明所 conform 的 protocol，以及每个 class 声明的 superclass。如果找到的成员来自某个 protocol 或 superclass，我们要应用一张 substitution map，这在 `type-resolution.tex` 的 Member Type Representations 一节描述。而只搜索单个 type declaration 及其 extension 的那个原语操作，叫做 **direct lookup**（见 `extensions.tex`（中译 [SwiftGenericsExtensions.md](SwiftGenericsExtensions.md)） 的 Direct Lookup 一节）。

### Module lookup

base 是一个 module declaration 的 qualified lookup，会在给定 module 以及它通过「`@_exported import`」再导出的其他 module 里搜索 top-level declaration。

### Dynamic lookup

base 是 `AnyObject` 类型的 qualified lookup，实现的是「向 `id` 发消息」这一遗留的 Objective-C 行为，它可以调用任何 Objective-C class 或 protocol 里定义的任何方法。在 Swift 里，这种所谓的 **dynamic lookup** 搜索的是一张全局查找表，表里收录了所有 class 和 protocol 的所有 `@objc` 成员：

- 任何 class 都可以含有 `@objc` 成员，这个属性既可以显式写出，也可以在方法 override 了 superclass 的 `@objc` 方法时被推断出来。
- protocol 的成员只有在 protocol 本身是 `@objc` 时才是 `@objc` 的。

### Operator lookup

operator 符号由 **operator declaration** 声明在 module 的顶层。operator declaration 带有 fixity（prefix、infix 或 postfix），而 infix operator 还带一个 **precedence group**。precedence group 之间构成一个偏序。于是像 `+`、`*` 这样的标准 operator 及其 precedence group 都定义在标准库里，而不是内建于语言本身。

parser 把 `2 + 3 * 6` 这样的算术表达式解析成一串扁平的节点与 operator 符号，称为 **sequence expression**。parser 不知道 `+` 和 `*` 的优先级、fixity 和结合性；说实在的，它压根不知道它们存在。表达式类型检查器的 **pre-check** 趟会去查找 operator 符号（这里就是 `+` 和 `*`），并按 operator 的 fixity、优先级与结合性把 sequence expression 变换成我们更熟悉的嵌套树形式。

operator 符号本身没有实现，它们只是名字。一个 operator 符号可以用作某个函数的名字，由该函数为某个具体类型（prefix 和 postfix operator）或某一对具体类型（infix operator）实现这个 operator。operator 函数既可以声明在顶层，也可以作为某个类型的成员。就 name lookup 而言，operator 函数有意思的一点在于：它们是全局可见的，哪怕声明在某个类型内部。查找 operator 函数走的是 operator 查找表，表里既有顶层的 operator 函数，也有所有已声明类型的成员 operator 函数。

编译器类型检查表达式 `2 + 3 * 6` 时，必须从所有可能中为 `+` 和 `*` 各挑出一个具体的 operator 函数，这个表达式才能通过类型检查。这里选中的是 `Int` 的那两个重载，因为 `Int` 是字面量 `2`、`3`、`6` 的默认字面量类型。

下面这段代码（原书标题 Operator lookup in action）展示了一些自定义 operator 和 precedence group 的定义：

```swift
prefix operator <&>
infix operator ++: MyPrecedence
infix operator **: MyPrecedence

precedencegroup MyPrecedence {
  associativity: right
  higherThan: AdditionPrecedence
}

// Member operator examples
struct Chicken {
  static prefix func <&>(x: Chicken) {}
  static func ++(lhs: Chicken, rhs: Chicken) -> Int {}
}

struct Sausage {
  static func ++(lhs: Sausage, rhs: Sausage) -> Bool {}
}

// Top-level operator example
func **(lhs: Sausage, rhs: Sausage) -> Sausage {}

// Global operator lookup finds Sausage.++
// `fn' has type (Sausage, Sausage) -> Bool
let fn = { ($0 ++ $1) as Bool }
```

注意 struct `Chicken` 里 `++` 的那个重载返回 `Int`，而 struct `Sausage` 里 `++` 的重载返回 `Bool`。存进 `fn` 的那个闭包值把 `++` 应用到两个匿名闭包参数 `$0` 和 `$1` 上。它们没有声明类型，但仅仅靠把**返回类型**强制为 `Bool`，我们就能毫不含糊地挑出 `Sausage` 里声明的那个 `++` 重载。（这算不算好风格，留给读者评判。）

最初 infix operator 是用一个整数值来定义优先级的；Swift 3 引入了具名的 precedence group（SE-0077）。operator 函数走全局查找这件事，可以追溯到所有 operator 函数都只能声明在顶层的年代。Swift 3 同时引入了把 operator 函数声明为类型成员的能力，但全局查找的行为被保留了下来（SE-0091）。

## Delayed Parsing

前面描述的那个「编译流水线」模型，其实是对实际情况的过度简化。归根结底，每个 frontend job 只需要为它自己 primary file 里的声明生成机器码，所以从 SILGen 往后的所有阶段都只作用于该 frontend job 的 primary file。解析和类型检查时的情况要微妙一些，因为 name lookup 必须能在别的源文件里找到声明，包括 secondary file。这就要求 secondary file 也得有抽象语法树。可是，如果每个 frontend job 都被要求完整解析所有 secondary file，效率会很低：花在 parser 上的时间将正比于 frontend job 数乘以源文件数，并行带来的好处也就被抵消了。

**delayed parsing** 这项优化解决了这个两难。第一次解析一个 secondary file 时，parser 不为顶层类型、extension 和函数的体构造语法树节点，而是切换到一种高速模式：跳过注释、配对花括号，除此之外几乎什么都不做。这样每个 secondary file 得到一份「骨架」表示。（whole module mode 下没有 delayed parsing：既没有 secondary file，而对 primary file 里的声明做 delayed parsing 也没有意义，反正类型检查和代码生成都需要它们。）如果之后我们确实需要某个 secondary file 里某个类型或 extension 声明的体——比如在类型检查 primary file 里的某个表达式时，要向这个声明里做一次 name lookup——那就再解析一遍该声明的 source range，这一次构建完整的语法树。

虽然可以构造出一个病态程序，让每个源文件都触发对其他所有文件中全部声明的 delayed parsing，但这在实践中不大可能发生。

### Operator lookup

delayed parsing 要成立，被跳过的类型与 extension 成员就必须对编译没有可观测的影响。这一点总是成立，只有两个例外：operator lookup 和 dynamic lookup。如上一节所述，operator 函数是全局可见的，哪怕被声明为某个类型的方法。为了应付这一点，parser 在跳过 secondary file 里某个类型或 extension 的体时，会留意关键字「`func`」后面跟着 operator 符号的情形。第一次执行 operator lookup 时，所有含有 operator 函数的类型和 extension 的体都会被重新解析一遍。大多数类型和 extension 并不定义 operator 函数，所以这在实践中很少发生。

### Dynamic lookup

dynamic lookup 的情况类似，因为对 `AnyObject` 类型的值做方法调用，必须查阅一张由各 class 的 `@objc` 成员和 `@objc` protocol 的（隐式 `@objc` 的）成员构造出来的全局查找表。与 operator 函数不同的是，class 和 `@objc` protocol 在 Swift 程序里相当常见，不过 `AnyObject` lookup 本身很少用到。一个 frontend job 第一次遇到 `AnyObject` 上的动态方法调用时，所有被标记为可能含有 `@objc` 方法的 class 体都会被急切地解析。

这里其实还有一层麻烦。class 可以嵌套在别的类型里，而后者若出现在 secondary file 中，其体是被跳过的。为了在构建 `AnyObject` 查找表时找到这类 class，我们依赖跟 operator lookup 类似的花招：parser 跳过某个类型的体时，会留意「`class`」关键字的出现。如果体里含有这个关键字，我们就把这一事实记下来，以便之后需要时再完整解析这个类型。

大多数 Swift 程序——哪怕是重度使用 Objective-C 互操作的那些——也不会在每个源文件里都写一次 `AnyObject` 上的动态方法调用，所以 delayed parsing 依然有效。

**例.** 下面这段程序（原书标题 Delayed parsing with `AnyObject` lookup）演示了这个行为。程序由三个文件组成：

```swift
// a.swift
func f(x: AnyObject) {
  x.foo()
}
```

```swift
// b.swift
func g() {
  f()
}
```

```swift
// c.swift
struct Outer {
  class Inner {
    @objc func foo() {}
  }
}
```

假设 driver 启动了三个 frontend job，每个 frontend job 一个 primary file。各个 frontend job 分别做这些事：

- primary file 为 `a.swift` 的那个 frontend job 会把 `b.swift` 和 `c.swift` 当作 secondary file 解析。`b.swift` 里 `g()` 的体被跳过。parser 同样跳过 `Outer` 的体，但记下它含有 `class` 关键字。`a.swift` 里的函数 `f()` 含有一次 `AnyObject` 动态调用，所以这个 frontend job 会去构造全局查找表，从而触发对 `c.swift` 里 `Outer` 和 `Inner` 的解析。
- primary file 为 `b.swift` 的那个 frontend job 会把 `a.swift` 和 `c.swift` 当作 secondary file 解析。这个 primary file 完全没有引用 `c.swift` 里的任何东西，所以在这个 frontend job 里 `Outer` 始终没被解析。类型检查 `g()` 里对 `f()` 的调用，也不需要解析 `f()` 的**体**。
- primary file 为 `c.swift` 的那个 frontend job 会把 `a.swift` 和 `b.swift` 当作 secondary file 解析，跳过 `f()` 和 `g()` 的体。

## Request Evaluator

**request evaluator** 把 delayed parsing 背后的想法推广到了整个类型检查。和解析一样，那种由单趟语义分析按源码顺序遍历声明的经典编译器设计，并不适合 Swift：

- 在一个 Swift 源文件里，声明可以按任意顺序书写，不需要前向声明（不像 Pascal 或 C）。表达式和类型标注也可以不受限制地引用别的源文件里的声明。最后，某些形式的循环引用是被允许的。

  具体来说，这意味着在单个 frontend job 内部，primary file 里的某个实体可能引用一个尚未被类型检查、或者正在被类型检查的声明。

- 撇开顺序问题不谈，frontend job 之间还有重复劳动的潜在开销。每当一个 frontend job 去类型检查某个 secondary file 里的声明，并行带来的好处就损失了一部分，因为这个 secondary file 必然是另外某个 frontend job 的 primary file，同一个声明在那个 job 里还得再被类型检查一遍。

  因此，我们希望把花在类型检查 secondary file 声明上的时间降到最低。

于是，类型检查的工作被拆成一个个细粒度的 **request**，按需求值而非顺序执行。仍然有一趟语义分析按源码顺序访问每个 primary file 的声明，但它做的只是发起 request 和产出诊断。

具体说来，一个 **request** 把一串输入参数和一个 **evaluation function** 打包在一起。除了产出诊断之外，request 函数的结果应当只依赖这些输入，以及其他 request 的结果。request evaluator 直接调用 evaluation function，并缓存结果。客户端只通过 request evaluator 框架来求值 request，而框架会在有缓存值时返回缓存、自动检测 request 循环，并为 incremental build 追踪依赖信息。

Swift frontend 定义了数百种 request；就本书的目的而言，最重要的是这几个：

- **type-check primary file request** 访问一个 primary source file 里的每个声明。它负责发起足够多的 request，以保证在所有 request 都成功且没有产出诊断的情况下 SILGen 能顺利进行。
- **AST lowering request** 是进入 SILGen 的入口，它从一个源文件的抽象语法树生成 SIL。
- **unqualified lookup request** 和 **qualified lookup request** 执行上一节描述的两种 name lookup。
- **interface type request** 在 `declarations.tex` 里讲解。
- **generic signature request** 在 `building-generic-signatures.tex`（中译 [SwiftGenericsBuildingGenericSignatures.md](SwiftGenericsBuildingGenericSignatures.md)） 里讲解。

**例.** 看看类型检查这段程序时会发生什么：

```swift
let food = cook()
func cook() -> Food {}
struct Food {}
```

注意 `food` 的 initial value expression 引用了 `cook()` 函数，而 `cook()` 的返回类型是紧随其后声明的 `Food` struct，同时 `Food` 又是 `food` 被推断出来的类型。这件事在 request evaluator 里是这样展开的：

1. **type-check primary file request** 先访问 `food` 的声明，执行各种语义检查。
2. 其中一项检查以 `food` 的声明为输入求值 **interface type request**。这是一个 variable declaration，所以 evaluation function 会类型检查其 initial value expression 并返回结果的类型。
   1. 为了类型检查表达式 `cook()`，**interface type request** 被再次求值，这次的输入参数是 `cook` 的声明。
   2. `cook()` 的 interface type 尚未算出，于是 request evaluator 调用 request 的 evaluation function。
3. 算出 `food` 的 interface type 并执行完其他语义检查之后，**type-check primary file request** 继续处理 `cook` 的声明：
   1. **interface type request** 又一次被求值，输入参数是 `cook` 的声明。
   2. 结果已经缓存过了，所以 request evaluator 立刻返回缓存的结果，不再重算。
4. 最后我们类型检查 `Food` 的声明，求值余下的所有 request。

**type-check primary file request** 比较特殊，因为它不返回值；求值它是为了产出诊断这一副作用，而大多数 request 是要返回值的。**type-check primary file request** 的实现保证：只要没有产出诊断，SILGen 就能为 primary file 里的所有声明生成有效的 SIL。不过下一个例子会表明，SILGen 仍可能撞上无效的声明，并在 secondary file 里诊断出错误。

**例.** 假设我们以下面这个文件为 primary file 运行一个 frontend job：

```swift
// a.swift
func open(_: Box) {}
```

我们来看看当 `Box` 定义在一个含有语义错误的 secondary file 里时会发生什么：

```swift
// b.swift
struct Box {
  let contents: DoesNotExist
}
```

我们这个 frontend job 在语义分析趟里不会产出任何诊断，因为类型检查 primary file `a.swift` 时，`Box` 的 `contents` 存储属性其实并没有被引用到。可是 SILGen 运行时，它需要判断 `open()` 函数那个 `Box` 类型的参数应当直接用寄存器传递，还是通过地址传递——办法是计算 `Box` 类型的 **type lowering**。type lowering 过程会递归计算 `Box` 每个存储属性的 type lowering；这就为 `Box` 的 `contents` 属性求值了 **interface type request**，而它会产出一个诊断，因为 identifier「`DoesNotExist`」解析不到有效的类型。该存储属性的 interface type 于是变成 error type。type lowering 将在 `substitution-maps.tex`（中译 [SwiftGenericsSubstitutionMaps.md](SwiftGenericsSubstitutionMaps.md)） 的 SIL Type Lowering 一节讨论。

request evaluator 框架在 Swift 4.2 首次引入。在此后的各个版本里，各种临时机制被逐步改写成 request evaluator 的 request，编译器的性能、稳定性和实现的可维护性都因此获益。

### Cycles

在一门允许前向引用的语言里，可以写出语法上完全合法、所有 identifier 都指向有效声明，但程序仍然无效的情况——因为存在循环。这方面的经典例子是两个互相继承的 class：

```swift
class A: B {}
class B: A {}
```

为检测循环而实现专门的逻辑既容易出错又枯燥，而漏掉一处循环检查，就可能让编译器在遇到无效的输入程序时崩溃或死循环。request evaluator 通过维护一个 **active request** 栈，把循环检测集中了起来。求值一个 request 之前，request evaluator 先检查 active request 栈里是否已经有一个相等的 request。若有，调用 evaluation function 就会导致无限递归，于是 request evaluator 转而诊断一个错误，并返回该 request 特有的哨兵值。

```
$ swiftc cycle.swift
cycle.swift:1:7: error: `A' inherits from itself
class A: B {}
      ^
cycle.swift:2:7: note: class `B' declared here
class B: A {}
      ^
```

循环诊断可以按 request 种类定制；默认的那句就是「circular reference」。如果调用编译器时带上 frontend flag `-debug-cycles`，active request 栈也会被打印出来：

```
$ swiftc cycle.swift -Xfrontend -debug-cycles
===CYCLE DETECTED===
 `--TypeCheckPrimaryFileRequest(source_file "cycle.swift")
     `--SuperclassDeclRequest(cycle.(file).A@cycle.swift:1:7)
         `--SuperclassDeclRequest(cycle.(file).B@cycle.swift:2:7)
             `--SuperclassDeclRequest(cycle.(file).A@cycle.swift:1:7)
```

### Performance analysis

编译器提供了若干命令行 flag，帮助理解编译期性能。`-stats-output-dir` flag 后面跟一个目录名，该目录必须已存在。每个 frontend job 都会往这个目录写一个新的 JSON 文件，里面是各种计数器和计时器。配合 `-fine-grained-timers` flag 使用时，编译器会统计 request 求值的次数，以及花在 request 求值上的总时间，并按 request 种类分列。输出可以用各种方式切分；虽然格式是 JSON，但用「`awk`」（Aho、Kernighan、Weinberger 2023,《The AWK Programming Language》）其实就相当好使：

```
$ mkdir /tmp/stats
$ swiftc -stats-output-dir -fine-grained-timers /tmp/stats ...
$ awk -f '/InterfaceTypeRequest.wall/ { x += $2 } END { print x }' \
    /tmp/stats/*.json
```

另一个命令行 flag 是 `-trace-stats-events`。它必须与 `-stats-output-dir` 一起传，作用是在统计目录里输出一个 trace 文件。trace 文件是一串带时间戳的事件，标记每次 request 求值函数的开始与结束，格式为 CSV。这些 flag 的更多细节见 Graydon Hoare 的《Swift compiler performance》文档。

## Incremental Builds

request evaluator 还会记录依赖信息，用于由 driver flag `-incremental` 启用的增量编译。增量编译的目标是以尽可能不保守的方式，证明哪些文件不需要重新构建。一个增量编译实现的质量可以这样评判（作者在此感谢 David Ungar 给出的这个说法）：

1. 对程序中所有源文件做一次干净构建，并把 object file 收集起来。
2. 修改输入程序里的一个或多个源文件。
3. 做一次增量构建，它会重新构建输入程序中源文件的某个子集。如果某个源文件被重新构建了，但产出的 object file 与第 1 步保存的那个完全相同，那么这次增量构建做了**无用功**。
4. 最后，再做一次干净构建，把输入程序的所有源文件统统重新构建一遍。如果某个源文件被重新构建后，产出的 object file 与第 1 步保存的那个不同，那么这次增量构建是**不正确的**。

这凸显了增量编译问题的难处。重建**太多**文件只是让人心烦；重建**太少**文件则是正确性问题。一个正确但无效的实现，就是每次都重建全部源文件。而反过来，只重建自上次调用编译器以来发生变化的那些源文件，又过于激进。要看出它为什么不正确，考虑下面这段程序（原书标题 Rebuilding a file after adding a new overload）。假设程序员先构建一次程序，然后加上重载 `f: (Int) -> ()`，再构建一次。新重载更特定，所以 `b.swift` 里的调用 `f(123)` 现在指向新重载；因此 `b.swift` 也必须重新构建。

```swift
// a.swift
func f<T>(_: T) {}

// new overload added in second version of file
func f(_: Int) {}
```

```swift
// b.swift
func g() {
  // new overload is selected after a.swift is updated
  f(123)
}
```

Swift 编译器采取的办法是构造一张**依赖图**。frontend 为每个源文件输出一个 **dependency file**，记录该源文件**提供**的所有名字，以及类型检查器在编译该源文件时**需要**的所有名字。dependency file 采用二进制格式，文件名扩展名是「`.swiftdeps`」。dependency file 里的 provided 名字清单，是通过遍历抽象语法树、收集每个源文件里所有可见声明生成的；required 名字清单则由 request evaluator 借助 active request 栈生成。每个被缓存的 request 都有一份 required 名字清单，而一个 request 可以可选地充当 dependency sink 或 dependency source：

- **dependency sink** 是一个记录 required 名字的 name lookup request。求值一个 dependency sink request 时，request evaluator 会遍历 active request 栈，把该 identifier 加进每个 active request 的 required 名字清单。于是对每个 request，我们都记录下了其 evaluation function 里发生过的那些 name lookup。

  一个重要的注意点是：当一个已有缓存值的 request 再次被求值时，该 request 缓存下来的 required 名字清单必须再「重放」一遍，把它们加进每个依赖这个缓存值的 active request。

- **dependency source** 是位于 request 栈顶的 request，比如 **type-check primary file request** 或 **AST lowering request**。dependency source 把一定量的工作圈定到某个源文件的范围内。

  一个 dependency source request 求值完成后，所有归属于该 request 的 required 名字都会被加进这个源文件的 required 名字清单。

driver 利用 frontend 生成的 dependency file 来真正执行增量构建。这分两个阶段：

1. 第一阶段重新构建自上次编译以来发生过变化的所有源文件。这是必须重建的最小集合。
2. 第二阶段读取 dependency file，收集第一阶段重建的那些源文件所提供的全部名字，然后重新构建依赖这些名字的源文件。

**例.** 要理解 request 缓存与依赖记录是如何互相作用的，考虑下面这段程序（原书标题 Recording incremental dependencies）：

```swift
// a.swift
func breakfast() {
  soup(nil)
}
```

```swift
// b.swift
func lunch() {
  soup(nil)
}
```

```swift
// c.swift
func soup(_: Pumpkin?) {}
struct Pumpkin {}
```

假设 driver 决定把 `a.swift` 和 `b.swift` **两个**文件放进同一个 frontend job 编译（事实上，眼下这个问题只可能出现在 batch mode 下，也就是一个 frontend job 有不止一个 primary file 的时候）。首先，**type-check primary file request** 以源文件 `a.swift` 运行。

1. 类型检查 `breakfast()` 的体时，类型检查器求值 **unqualified lookup request** 来解析 identifier「`soup`」。
2. 这会把 identifier「`soup`」记进每个 active request 的 required 名字清单。当前有一个 active request，即 `a.swift` 的 **type-check primary file request**。
3. 这次查找在 `c.swift` 里找到 `soup()` 的声明。
4. 类型检查器以 `soup()` 的声明求值 **interface type request**。
   1. **interface type request** 以 identifier「`Pumpkin`」求值 **unqualified lookup request**。
   2. 这会把 identifier「`Pumpkin`」记进每个 active request 的 required 名字清单，此刻有两个：`soup()` 的 **interface type request**，以及 `a.swift` 的 **type-check primary file request**。
5. `a.swift` 的 **type-check primary file request** 完成。这个 request 的 required 名字清单含有两个 identifier——「`soup`」和「`Pumpkin`」；两者都被加进源文件 `a.swift` 的 required 名字清单。

接下来，**type-check primary file request** 以源文件 `b.swift` 运行。

1. 类型检查 `lunch()` 的体时，类型检查器以 identifier「`soup`」求值 **unqualified lookup request**。
2. 这会把 identifier「`soup`」记进每个 active request 的 required 名字清单。当前有一个 active request，即 `b.swift` 的 **type-check primary file request**。
3. 这次查找在 `c.swift` 里找到 `soup()` 的声明。
4. 类型检查器以 `soup()` 的声明求值 **interface type request**。
5. 这个 request 已经被求值过了，于是返回缓存的结果。该 request 的 required 名字清单就是单个 identifier「`Pumpkin`」。这份 required 名字清单会被重放一遍，就好像这个 request 是头一次被求值一样。于是 identifier「`Pumpkin`」被加进每个 active request 的 required 名字清单，此刻只有一个：`b.swift` 的 **type-check primary file request**。
6. `b.swift` 的 **type-check primary file request** 完成。这个 request 的 required 名字清单含有两个 identifier——「`soup`」和「`Pumpkin`」；两者都被加进源文件 `b.swift` 的 required 名字清单。

frontend job 完成时写出 `a.swift` 和 `b.swift` 的 dependency file。两个源文件都需要名字「`soup`」和「`Pumpkin`」。`b.swift` 对「`Pumpkin`」的依赖之所以被正确记录下来，正是因为求值一个有缓存值的 request 时会重放它的 required 名字清单，即上面的第 2 步。

增量构建的故事其实还没讲完；尤其是我们没谈「interface hash」机制——它的用意是当改动只限于注释、空白或函数体时，避免重建依赖它的源文件。不过我们离「描述 Swift 泛型」这个目标已经跑得够远了，好奇的读者可以参考 Doug Gregor 的《Request evaluator》与 Jordan Rose 的《Dependency analysis》两份文档。

## Module System

frontend 用一个 **module declaration** 来表示 module，其中含有一个或多个 **file unit**。一次编译器调用里的源文件列表构成 **main module**。main module 是特殊的，因为它的抽象语法树是直接解析源码构建出来的，其 file unit 就是 **source file**。此外还有另外三种 module：

1. **Serialized module**，由一个或多个 **serialized AST file unit** 构成。当 main module import 另一个用 Swift 写的 module 时，frontend 读取的就是此前构建好的 serialized module。

2. **Imported module**，由一个或多个 **Clang file unit** 构成。这些是用 C、Objective-C 或 C++ 实现的 module。

3. **builtin module**，它恰好只有一个 file unit，里面是编译器自身实现的类型和 intrinsic。

main module 通过 `import` 关键字依赖别的 module，`import` 会解析成一条 **import declaration**。解析之后，语义分析最早的阶段之一就是加载 main module import 的所有 module。标准库定义在 `Swift` module 里，它会被自动 import，除非 frontend 是带着 `-parse-stdlib` flag 调用的（构建标准库本身时才这么用）。至于 builtin module，它通常是不可见的，但 `-parse-stdlib` flag 也会让它被隐式 import（见 `types.tex`（中译 [SwiftGenericsTypes.md](SwiftGenericsTypes.md)） 的 Special Types 一节）。

### Serialized modules

`-emit-module` flag 指示编译器生成一个 **serialized module**。serialized module 文件的扩展名是「`.swiftmodule`」。serialized module 以二进制格式存储，与 Swift 编译器的具体版本紧密绑定。（要构建一个用于分发的 shared library，更好的做法是发布一份 textual interface，见本节末尾。）

向 serialized module 做 name lookup 时，会按需从这种二进制格式里反序列化记录，惰性地构造出声明。反序列化出来的声明通常看起来跟解析并完整类型检查过的声明一样，但有时携带的信息更少。举例来说，在 `declarations.tex` 的 Requirements 一节我们会遇到 requirement 的各种语法表示形式，比如 `where` 子句。由于这类信息只在类型检查该声明时才用得上，它不会被序列化；反序列化出来的声明只需要存一个 generic signature（见 `generic-signatures.tex`（中译 [SwiftGenericsGenericSignatures.md](SwiftGenericsGenericSignatures.md)））。

> 译注：这正是本库能读到什么、读不到什么的分水岭。二进制里留存的是 generic signature 层面的 requirement——一条条打包好的 kind + 主体 + 内容，而不是源码里 `where` 子句的原始写法。本库怎样把这些字节重新读成 requirement（以及由此重建出的约束为何可能与源码写法不同形但同义），见 [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)。

解析出来的函数声明有一个体，由语句和表达式构成。这个体不会被序列化保留，所以反序列化出来的函数声明没有体。为了实现 `@inlinable` 属性——它让一个函数定义可以跨 module 边界被内联和特化——我们序列化该函数的 SIL 表示。

### Imported modules

imported module 是用 C、Objective-C 或 C++ 实现的。Swift 编译器内嵌了一份 Clang，用它来解析 module map、头文件和二进制预编译头。向 imported module 做 name lookup 时，会从对应的 Clang 声明惰性地构造出 Swift 声明。Swift 编译器里负责这件事的组件人称「Clang importer」。

如果入口点此前已由 Clang 发射且可从外部获得，那么 import 进来的函数声明通常没有体。Clang importer 偶尔会合成访问器方法之类的琐碎东西，它们确实有体，以 Swift 的语句和表达式表示。至于不能从外部获得的 C 函数，比如头文件里声明的 `static inline` 函数，则由 Swift IRGen 回调 Clang 来发射。

调用编译器时带上 `-import-objc-header` flag 并跟一个头文件名，就指定了一个 **bridging header**。这是一条捷径：它让 bridging header 里的 C 声明对 main module 的所有其他源文件可见，而不必先定义一个单独的 Clang module。它的实现方式是往 main module 里加一个与该 bridging header 对应的 Clang file unit。正因如此，编译器代码不应假定 main module 里的所有 file unit 都是 Swift 源文件。

### Textual interfaces

二进制 module 格式依赖编译器内部实现，它完全不打算跨编译器版本保持兼容。要构建一个用于分发的 shared library，更好的做法是生成一份 **textual interface**：

```
$ swiftc Horse.swift -enable-library-evolution -emit-module-interface
```

与 serialized module 格式不同，textual interface 只描述一个 module 的 public 声明。`-enable-library-evolution` flag 启用 **resilience**（library evolution），这是发射 textual interface 的前提。resilience 指示客户端改用更抽象的访问方式，保证只依赖该 module 的 public 声明；比方说，它允许给一个 public struct 新增存储属性。resilience 的文档见 Slava Pestov 的博客《Library evolution in Swift》与仓库里的《Library Evolution》文档。

> 译注：resilience 会在二进制里留下可以被探测到的痕迹——public 成员的实际实现符号保持 local，对外导出的是 dispatch thunk（`Tj` 符号）。本库据此在生成的 interface 头部写一行「detected / not detected」的 library-evolution 判断，并用 export trie 给成员标注导出状态，见 [InterfaceHeaderAndExportStatusAnnotations.md](../InterfaceHeaderAndExportStatusAnnotations.md)；把非导出声明直接滤掉的那一半功能见 [ExportedOnlyInterfaceFiltering.md](../ExportedOnlyInterfaceFiltering.md)。

textual interface 文件的扩展名是「`.swiftinterface`」。它们由 **AST printer** 生成，后者把声明打印成非常接近 Swift 源码的形式，只有几处例外：

1. 非 `@inlinable` 的函数体被跳过。`@inlinable` 函数的体原样打印，注释也一并保留，只有 `#if` 条件会被求值掉。
2. 各种合成出来的声明——比如来自 associated type inference 的 type alias 声明、`Equatable` 这类 derived conformance 的 witness 等等——都被显式地写出来。
3. Opaque result type 也需要特殊处理（见 `opaque-result-types.tex`（中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)） 的 Opaque Type Witnesses 一节，中译 [SwiftGenericsOpaqueResultTypes.md](SwiftGenericsOpaqueResultTypes.md)）。

注意上面第 (1) 条意味着 textual interface 格式是分目标平台的；每个目标平台都要在 shared library 之外单独生成一份 textual interface。

> 译注：本库离线从 Mach-O 二进制重建的，正是这份 `.swiftinterface` 的形状——但走的是完全不同的路。编译器有完整的 AST，本库只有 IRGen 留下的 metadata 与符号表，于是上面三条例外在本库这边各自变成一个可判定性问题：函数体一律没有（第 1 条的另一半，被删实现连符号都可能没有）；合成声明能不能还原取决于它在二进制里留没留痕迹（`Equatable` 靠 `__derived_*_equals` 符号，library evolution 下这条线索就失效）；opaque result type 要从 opaque type descriptor 逐字节读回。整体流程见 [SwiftInterface.md](../Modules/SwiftInterface.md)。

当一个由 textual interface 定义的 module 第一次被 import 时，会有一个 frontend job 解析并类型检查这份 textual interface，生成一个 serialized module 文件，再由最初那个 frontend job 消费。这样生成的 serialized module 文件会被缓存，可以在同一编译器版本的多次调用之间复用。

`@inlinable` 属性在 Swift 4.2 引入（SE-0193）。Swift ABI 在 Swift 5 正式稳定，那时标准库成为 Apple 平台上操作系统的一部分。library evolution 支持与 textual interface 在 Swift 5.1 成为用户可见的特性（SE-0260）。最近有一篇论文给出了一套推理 Swift ABI 的形式模型（Wagner、Eisbach、Ahmed 2024,《Realistic Realizability: Specifying ABIs You Can Count On》）。

## Source Code Reference

Swift driver 如今是用 Swift 实现的，放在与编译器其余部分分开的一个仓库里：

<https://github.com/swiftlang/swift-driver>

Swift frontend、标准库和运行时都在主仓库里：

<https://github.com/swiftlang/swift>

Swift frontend 的各个主要组件分别住在主仓库自己的子目录下。建模抽象语法树的那些实体定义在 `lib/AST/` 和 `include/swift/AST/` 里；其中 type 和 declaration 对本书尤为重要，将分别在 `types.tex` 和 `declarations.tex` 里讲解。SIL 中间语言的核心实现在 `lib/SIL/` 和 `include/swift/SIL/`。

编译流水线的每个阶段都有自己的子目录：

- `lib/Parse/`
- `lib/Sema/`
- `lib/SILGen/`
- `lib/SILOptimizer/`
- `lib/IRGen/`

### The AST Context

关键源文件：

- `include/swift/AST/ASTContext.h`
- `lib/AST/ASTContext.cpp`

**`ASTContext`**：这是一个表示 frontend 实例的单例类。一个 AST context 提供内存分配 arena、编译器各处用到的各种不可变数据类型的唯一化分配，以及其他各种全局单例的存储。

### Request Evaluator

关键源文件：

- `include/swift/AST/Evaluator.h`
- `lib/AST/Evaluator.cpp`

**`SimpleRequest`**：每种 request 都是 `SimpleRequest` 的一个子类。子类通过覆写 `SimpleRequest` 的 `evaluate()` 方法来实现 evaluation function。

**`RequestFlags`**：`SimpleRequest` 的模板参数之一就是这个类型的值。其中若干 flag 指定缓存策略，下面这些必须**恰好**指定一个：

- `RequestFlags::Uncached` 表示不做任何缓存。
- `RequestFlags::Cached` 表示结果应当被自动缓存。
- `RequestFlags::SeparatelyCached` 表示该 request 的结果应由 request 的实现自己来缓存。
- `RequestFlags::SplitCached` 是一种混合策略，把自动缓存和单独缓存结合起来，下文详述。

另有一对 flag 定义该 request 如何与增量构建的依赖追踪机制交互（见本章 Incremental Builds 一节）。下面这些至多指定一个：

- `RequestFlags::DependencySource` 把该 request 标记为 dependency source。直接执行 name lookup 的 request 设置这个 flag。
- `RequestFlags::DependencySink` 把该 request 标记为 dependency sink。与整个源文件关联的顶层 request 设置这个 flag。

（译注：原书此处对 `DependencySource` 与 `DependencySink` 的描述与前文 Incremental Builds 一节相反——按前文，执行 name lookup 的是 dependency sink，位于栈顶、与整个源文件关联的才是 dependency source。以前文为准。）

由于 C++ 表达能力的限制，定义一种新 request 需要写一点样板代码。以 `InterfaceTypeRequest` 为例，它接收一个 `ValueDecl` 作为输入、返回一个 `Type` 作为输出：

- request 的 type ID 声明在 `include/swift/AST/TypeCheckerTypeIDZone.def`。
- `InterfaceTypeRequest` 类声明在 `include/swift/AST/TypeCheckRequests.h`。
- `InterfaceTypeRequest::evaluate()` 方法定义在 `lib/Sema/TypeCheckDecl.cpp`。
- 该 request 是单独缓存的，所以 `InterfaceTypeRequest` 类还覆写了下文讲的 `isCached()`、`getCachedResult()` 和 `cacheResult()` 方法。

这几个方法实现在 `lib/AST/TypeCheckRequestFunctions.cpp`。

**`Evaluator`**：`Evaluator` 类是一个单例，存放在全局 `ASTContext` 单例的 `evaluator` 实例变量里。

求值 request 的办法是调用顶层函数 `evaluateOrDefault()`。这个函数接收 request evaluator 单例、待求值的 request，以及遇到循环时要返回的哨兵值。request evaluator 要么返回缓存值，要么调用 evaluation function 并缓存结果。

例如，`ValueDecl::getInterfaceType()` 方法的实现就是这样求值 `InterfaceTypeRequest` 的：

```cpp
Type ValueDecl::getInterfaceType() const {
  auto &ctx = getASTContext();
  return evaluateOrDefault(
    ctx.evaluator,
    InterfaceTypeRequest{const_cast<ValueDecl *>(this)},
    ErrorType::get(ctx)));
}
```

#### Request Caching

下面讨论通过指定 `RequestFlags` 可以得到的各种缓存形式。

当 evaluation function 只是包装了另一段自己做缓存的代码，或者外部条件保证该 request 对每个可能的输入只会被求值一次时，`Uncached` request 是合适的。

`Cached` request 把结果存进一张按 request 种类划分的 `DenseMap`，键是传给 evaluation function 的那些输入。这不需要 request 一侧做额外工作，缺点是当不同键的数量太大时，`DenseMap` 的开销就变得可观。这种情况下 request 的实现只需要额外声明一个方法，名为 `isCached()`。它允许只对某些输入选择不缓存；最常见的实现是总是返回 `true`。

`SeparatelyCached` request 必须像上面那样声明 `isCached()`，外加两个方法 `getCachedResult()` 和 `cacheResult()`。单独缓存实现起来要多花些工夫，但当缓存值可以直接存在输入值内部时，它避免了 `DenseMap` 的开销。

举例来说，在 whole-module 构建里，`InterfaceTypeRequest` 几乎会对每一个 `ValueDecl` 求值一次。正因如此，`InterfaceTypeRequest` 采用单独缓存，把 interface type 直接存在 `ValueDecl` 自身的一个实例变量里。

`SplitCached` request 与 `SeparatelyCached` 类似，也必须声明 `isCached()`、`getCachedResult()` 和 `cacheResult()` 方法供 evaluator 调用。evaluator 同样会像 `Cached` 那样分配一张 `DenseMap`，但 evaluator 自己不往里面存任何东西。该 request 的 `getCachedResult()` 和 `cacheResult()` 方法要么把结果存到它们自己选定的地方，要么通过 `Evaluator` 单例上的一对方法把结果交给 evaluator 的缓存：

- `getCachedNonEmptyOutput()` 接收一个 request，返回一个带缓存值的 `std::optional`，没有缓存值时返回 `std::nullopt`。
- `cacheNonEmptyOutput()` 接收一个 request 和结果，更新缓存。

当一个 request 要对大量输入求值，但结果几乎总是某个空的占位值时，split 缓存效果最好。思路是：空值直接就地存下（也许只占一个 bit），而所有其他结果则由 request evaluator 缓存。

例如，我们对 `opaque-result-types.tex` 里的 `OpaqueResultTypeRequest` 采用 split 缓存。这个 request 几乎会对每个 `ValueDecl` 求值，但大多数 value declaration 并没有 opaque result type，所以结果几乎总是 `nullptr`。我们不希望建一张键遍历所有 value declaration、而大多数值都是 `nullptr` 的 `DenseMap`；也不希望用单独缓存，因为那要求给 `ValueDecl` 新增一个几乎总是 `nullptr` 的实例变量。split 缓存让我们可以在 `ValueDecl` 里留出一个 bit 表示 opaque result type 是否存在，而 opaque result type 的实际声明则存进 request evaluator 的缓存——且只为那些确实有 opaque result type 的 value declaration 存。

如果指定了 frontend flag `-analyze-request-evaluator`，frontend job 会在完成时打印关于 request evaluator 缓存的统计信息。为一种新 request 挑选合适的缓存策略时，这些信息很有用。

### Name Lookup

关键源文件：

- `include/swift/AST/NameLookup.h`
- `include/swift/AST/NameLookupRequests.h`
- `lib/AST/NameLookup.cpp`
- `lib/AST/UnqualifiedLookup.cpp`

「ASTScope」子系统实现针对局部 binding 的 unqualified lookup。这部分代码是 name lookup 实现的内部细节；编译器的其余部分一般不直接与 ASTScope 打交道：

- `include/swift/AST/ASTScope.h`
- `lib/AST/ASTScope.cpp`
- `lib/AST/ASTScopeCreation.cpp`
- `lib/AST/ASTScopeLookup.cpp`
- `lib/AST/ASTScopePrinting.cpp`
- `lib/AST/ASTScopeSourceRange.cpp`

**`UnqualifiedLookupRequest`**：unqualified lookup 通过求值这种 request 的一个实例来执行。该 request 接收一个 `UnqualifiedLookupDescriptor` 作为输入。

**`UnqualifiedLookupDescriptor`**：封装一次 unqualified lookup 的输入参数：

- 要查找的名字。
- 查找起始处的 declaration context。
- 该名字在源码中书写位置的 source location。不指定时，这次查找变成 top-level lookup。
- 各种 flag，见下。

**`UnqualifiedLookupFlags`**：作为 `UnqualifiedLookupDescriptor` 一部分传入的 flag。

- `UnqualifiedLookupFlags::TypeLookup`：置位时，查找忽略 type declaration 以外的声明。type resolution 会用到它。
- `UnqualifiedLookupFlags::AllowProtocolMembers`：置位时，查找会找到 protocol 和 protocol extension 的成员。一般来说总该置位，除非为了避免 request 循环——那要求已知查找结果不可能出现在 protocol 或 protocol extension 里。
- `UnqualifiedLookupFlags::IgnoreAccessControl`：置位时，查找忽略访问控制。一般来说永远不该置位，只有在诊断里从错误中恢复时才用。
- `UnqualifiedLookupFlags::IncludeOuterResults`：置位时，查找在最内层 scope 里找到结果后就停止，或者说总是继续走到 top-level lookup。

**`DeclContext`**：declaration context 将在 `declarations.tex` 里引入，`DeclContext` 类见 `declarations.tex` 的 Source Code Reference 一节。

- `lookupQualified()` 的各个重载向给定的 base type 执行一次 qualified name lookup。这里的「`this`」参数——也就是被调用方法所属的那个 `DeclContext *`——决定了经由 import 和访问控制查得的声明的可见性；`this` **不是**这次查找的 base type。

**`NLOptions`**：与 `UnqualifiedLookupFlags` 类似，但用于 `DeclContext::lookupQualified()`。

- `NL_OnlyTypes`：置位时，查找忽略 type declaration 以外的声明。type resolution 会用到它。
- `NL_ProtocolMembers`：置位时，查找会找到 protocol 和 protocol extension 的成员。一般来说总该置位，除非为了避免 request 循环——那要求已知查找结果不可能出现在 protocol 或 protocol extension 里。
- `NL_IgnoreAccessControl`：置位时，查找忽略访问控制。一般来说永远不该置位，只有在诊断里从错误中恢复时才用。

**`NominalTypeDecl`**：nominal type declaration 将在 `declarations.tex` 里引入，`NominalTypeDecl` 类见 `declarations.tex` 的 Source Code Reference 一节。direct lookup 与惰性成员加载的实现见 `extensions.tex` 的 Source Code Reference 一节。

- `lookupDirect()` 执行一次 direct lookup，它只搜索该 nominal type declaration 本身及其 extension，并忽略访问控制。

**`lookupInModule()`**：在一个 module 内搜索 top-level 声明。按给定参数的不同，它以两种模式之一工作：

- 向特定 module 的 qualified lookup。在给定 module 及其所有 `@_exported` import 里查找。
- 从某个源文件顶层发起的 unqualified lookup。在该源文件 import 的所有 module 里查找，外加 main module 中其他源文件的 `@_exported` import。

### Primary File Type Checking

关键源文件：

- `lib/Sema/TypeCheckDeclPrimary.cpp`

`TypeCheckPrimaryFileRequest` 调用全局函数 `typeCheckDecl()`，后者用访问者模式按 declaration 的种类分派。对每种 declaration，它执行各种语义检查，并发起可能产出诊断的 request。

### Module System

**`ModuleDecl`**：一个 module。

- `getName()` 返回该 module 的名字。
- `getFiles()` 返回一个 `FileUnit` 数组。
- `isMainModule()` 回答这是不是 main module。

**`FileUnit`**：表示 file unit 的抽象基类。

**`SourceFile`**：表示一个从磁盘解析来的源文件，继承自 `FileUnit`。

- `getTopLevelItems()` 返回该源文件中所有 top-level item 的数组。
- `isPrimary()` 在这是 primary file 时返回 `true`，是 secondary file 时返回 `false`。
- `isScriptMode()` 回答这是不是该 module 的 main file。
- `getScope()` 返回供 unqualified lookup 使用的 scope tree 的根。

#### Imported and serialized modules

对 imported module 和 serialized module 的支持分别在两个子目录里：

- `lib/ClangImporter/`
- `lib/Serialization/`

#### AST printer

AST printer 负责生成 textual interface 文件：

- `include/swift/AST/ASTPrinter.h`
- `lib/AST/ASTPrinter.cpp`

---

> 译自 `docs/Generics/chapters/compilation-model.tex`（swift-6.4.0-RELEASE，`2349b5f6`）。原书 © Slava Pestov / The Swift Project，Apache License 2.0 with Runtime Library Exception。
