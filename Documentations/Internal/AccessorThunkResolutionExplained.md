# Accessor thunk 解析专题：`accessor function at N` 是怎么变成真实类型的

> 配套提案：[0028 离线解析不透明类型的 accessor thunk](../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md)、[0029 accessor thunk 的类型构造求值](../Evolutions/0029-thunk-type-construction-evaluation.md)。
> 这篇是**导读**：从零讲清这个功能在做什么、为什么非得读汇编、读出来的东西怎么进输出。读者不需要懂汇编，每一段汇编都逐行翻成人话。要看当时的决策过程与备选方案，去提案；要看渲染路径的历史演进，去 [AccessorFunctionReferenceRendering.md](AccessorFunctionReferenceRendering.md)。

## 一句话

Swift 的元数据里有一类地方，编译器没有写「这个类型叫什么」，而是写了「调这个函数，它会告诉你」。离线读二进制时我们不能调函数，于是这个功能把那个函数的机器码读出来，**不执行、只推演**，算出它会返回什么类型；算不出就诚实地打 `accessor function at N`。

## 先看结果

改之前，SwiftUI 的 interface 里这一行是个裸地址，读的人一无所获：

```swift
extension SwiftUI.FeedbackGenerator: SwiftUI.ViewModifier {
    typealias Body = opaque type symbolic reference 0x….0
}
```

现在（macOS 26 的共享缓存）：

```swift
extension SwiftUI.ResolvedMenuStyle: SwiftUI.View {
    // Body is picked at run time by an availability check (SE-0360):
    //   macOS 26.0 or later: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.Menu<…>, SwiftUI.AccessibilityAttachmentModifier>, SwiftUI.AllowsWindowActivationEventsModifier.Static>
    //   before macOS 26.0:   SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.Menu<…>, SwiftUI.AccessibilityAttachmentModifier>, SwiftUI.AllowsWindowActivationEventsModifier.Dynamic>
    typealias Body = SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.Menu<…>, SwiftUI.AccessibilityAttachmentModifier>, SwiftUI.AllowsWindowActivationEventsModifier.Static>
}
```

两支都在，`typealias` 那一行是最新系统上会用的那支。SwiftUI 里这样的 witness 有 17 条，现在全部解出；`dump` 里连 field record 的同类引用也解出了（`Drag.LazyItem<A>.state` 读成 `Synchronization.Mutex<Drag.LazyItem<A>.State>`）。

## 问题从哪来

### 元数据里平时写的是什么

编译器为每个类型、每个字段、每条关联类型的 witness 都留了「类型名」。它不是源码里的 `Int`，而是一串编码过的名字，叫 **mangled name**（例如 `Si` 就是 `Swift.Int`）。运行时和我们的离线读取器都靠解码这串名字（demangle）知道类型是谁。这条路不需要执行任何代码，所以离线读文件也能走。

### 两种情况编译器写不出名字

有两种情况，「类型叫什么」在编译期就没有一个固定答案，或者有答案但写不出来：

1. **类型取决于运行时的系统版本**。Swift 5.7 起（SE-0360）允许 `some View` 这样的不透明返回类型在 `if #available` 的两支里返回不同的具体类型。SwiftUI 大量用这个写法。这时 `Body` 到底是哪个类型，要等到程序跑起来问过系统版本才知道。
2. **名字用到了旧系统不认识的写法**。比如一个泛型参数带 `~Copyable`。这种 mangled name 的语法是新版本 runtime 才会解码的；如果这个 framework 要向后部署到旧系统，直接写这个名字会让旧系统解码失败。

两种情况编译器的做法一样：不写名字，写一个**函数指针**——元数据里放一个字节 `0x09`，后面跟一个相对偏移，指向一个由编译器生成的小函数。运行时遇到 `0x09` 就不再解码，直接调用那个函数拿类型。这个小函数叫 **metadata accessor thunk**（下文简称 thunk）；这种引用叫 **kind-9 accessor-function symbolic reference**（`0x09` 就是 kind 9）。

离线读取器（`MachOFile`）不能执行目标二进制的代码。在这个功能之前，它只能把那个偏移原样打出来，这就是裸地址和 `accessor function at N` 的来历。

## 这个函数长什么样

thunk 都很短，几条到一百来条指令，而且只会做几件固定的事：问系统版本、查一个运行时标志、拿某个类型的 metadata、把几个类型组合成一个泛型类型、返回。下面是三段真实样本，每条指令后面的分号是人话翻译。看不懂指令本身没关系，只看翻译就够了。

### 样本一：版本二选一，再包一层（`ResolvedMenuStyle.Body`，SwiftUI）

```asm
pacibsp                            ; arm64e 的指针签名，开场例行公事
stp  x20, x19, [sp, #-0x20]!       ; 保存两个寄存器，例行公事
ldr  x19, [x0]                     ; x0 指向「泛型实参缓冲区」，取出第 0 个实参存到 x19，后面要用
mov  w0, #1                        ; 参数 1：平台编号 1 = macOS
mov  w1, #26                       ; 参数 2：主版本 26
mov  w2, #0                        ; 参数 3：次版本 0
mov  w3, #0                        ; 参数 4：补丁版本 0
bl   __isPlatformVersionAtLeast    ; 问系统：现在是 macOS 26.0 或更新吗？答案（0 或 1）回到 w0
adrp x8, … ; add x8, x8, #0x810    ; 候选 A 的 metadata 地址
adrp x9, … ; add x9, x9, #0x888    ; 候选 B 的 metadata 地址
cmp  w0, #0                        ; 看看刚才的答案是不是 0
csel x2, x9, x8, eq                ; 答案是 0（版本不够）选 B，否则选 A，放进 x2
…                                  ; 把 x19（第 0 个实参）和 x2（选中的类型）作为实参
b    ModifiedContent 的 metadata accessor   ; 跳过去让它造出 ModifiedContent<实参 0, 选中的类型>，它的返回值就是本函数的返回值
```

所以这个 thunk 的答案不是「A 或 B」，而是「`ModifiedContent<实参 0, A>` 或 `ModifiedContent<实参 0, B>`」——实测版本满足那支是 `ModifiedContent<…, AllowsWindowActivationEventsModifier.Static>`，不满足那支是 `…Dynamic`。最后那一跳很容易漏：它不是 `bl`（调用后回来）而是 `b`（跳过去不回来），叫 **tail call**。0028 第一版就是漏了它，把 A / B 本身当成了答案，报出一个真实、全限定、但错误的类型——这类错误肉眼看不出来，只有拿运行时的答案对照才能发现，后面「验证」一节会说。

### 样本二：版本二选一，两支各调一个函数（`OnModifierKeysChangedModifier.Body`，SwiftUI）

```asm
mov  w0, #1 ; mov w1, #26 ; mov w2, #4 ; mov w3, #0
bl   __isPlatformVersionAtLeast    ; macOS 26.4 或更新吗？
cbz  w0, <另一支>                  ; 答案是 0 就跳到「另一支」
bl   类型 X 的 metadata accessor    ; 满足支：拿类型 X 的 metadata
ret                                ; 返回
<另一支>:
bl   类型 Y 的 metadata accessor    ; 不满足支：拿类型 Y 的 metadata
ret
```

这里两支各自调用一个函数。函数本身在 strip 过的二进制里没有名字，但每个类型的描述符（descriptor）里记着「我的 metadata accessor 在哪」，反查一遍就知道 X、Y 是谁。

### 样本三：查运行时标志（fixture 的 `~Copyable` 字段）

```asm
adrp x8, … ; ldr x8, [x8, #…]      ; 读运行时变量 _swift_runtimeSupportsNoncopyableTypes
cbz  x8, <fallback>                ; 当前系统的 runtime 不支持 noncopyable 类型？跳 fallback
adrp x8, … ; add x8, x8, #…
add  x0, x8, #0x10                 ; 直接给出类型的 metadata 地址
ret
```

fallback 那一支通常是「用另一条旧系统认识的 mangled name 现场实例化」（调 `__swift_instantiateConcreteTypeFromMangledName`）。这个标志在任何我们关心的系统上都是「支持」，所以离线读取时把它当成 true。

## 我们怎么不执行就读出答案

离线读取器（`SwiftThunkAnalysis` 模块）分四步。

### 第一步：把机器码变成指令列表（反汇编）

从 thunk 的地址读 1024 字节，交给 Capstone（一个开源反汇编库，只启用 ARM64 后端）解码成指令，最多 160 条，遇到「函数结束」就停。什么算函数结束是个坑：ARM64e 的返回指令写作 `retab` / `retaa` 而不是 `ret`，第一版解码器不认识它，读过了函数末尾进了下一个函数；还有前面样本一里的 `b`——它跳去的地方如果是另一个已知函数，当前函数就到此为止。这两个坑都在 0029 修掉了。

解码出来的不是 Capstone 的原始对象，而是我们自己的一小套「指令词汇表」（`ThunkInstruction`）：搬数（`mov`）、算地址（`adrp` / `add`）、读内存（`ldr`）、写内存（`str`）、比较（`cmp`）、条件选择（`csel`）、条件跳转（`cbz` / `cbnz` / `b.eq`）、调用（`bl`）、跳转（`b`）、返回。这样后面的分析层可以用手写的指令序列做单元测试，不需要真实二进制。

### 第二步：给每个调用目标起名

thunk 里每个 `bl` / `b` 都要知道「调的是谁」，否则无从推演。`MachOThunkEnvironment` 按下面的顺序认：

- **同一镜像里某个类型的 metadata accessor**：预先扫一遍 `__swift5_types`，把每个类型描述符里记录的 accessor 地址建成索引（`MetadataAccessorIndex`），地址一查就知道是哪个类型。
- **跨镜像的调用**：共享缓存里调别的 framework 不是直接跳过去，而是先跳到一小段桥接代码（stub），stub 从一个槽位（GOT 槽）里读出真正的目标地址再跳。我们解码 stub、找到槽位、读出目标，再按目标地址查它落在哪个镜像（主缓存的 image 表）、打开那个镜像查它的 accessor 索引或导出表。
- **runtime 的几个入口**按名字认：`__isPlatformVersionAtLeast`（版本检查）、`swift_getWitnessTable`（拿 protocol 的见证表）、`swift_checkMetadataState`（等 metadata 就绪，对我们来说是恒等）、`__swift_instantiateConcreteTypeFromMangledName`（按另一条 mangled name 实例化）。
- 认不出的：不猜，让那一支降级。

这里有一个反复踩过的坑值得单独记住：共享缓存里，`MachOSwiftSection` 用的「偏移」是 `虚拟地址 − 共享区域起始地址`，不是文件偏移。`segment.fileOffset`、`MachOFile.fileOffset(of:)`、`FullDyldCache.address(of:)` 是三套互不相同的账，混用不会报错，只会算出一个像模像样但错了几十字节的地址，最后指向隔壁 framework 的数据。

### 第三步：符号求值——寄存器里装的不是数，是「类型表达式」

真正执行时寄存器里放的是地址和数字。我们不执行，而是照着指令顺序走一遍，让每个寄存器和栈槽里放一个**类型表达式**（`ThunkTypeExpression`）：

| 表达式 | 意思 | 从哪来 |
|---|---|---|
| `argument(k)` | 泛型实参缓冲区的第 k 个 | `ldr xN, [x0, #8k]` 这类从参数缓冲区读出来的值 |
| `constantMetadata(address)` | 某个具体类型的 metadata，地址已知 | `adrp` + `add` 算出来的常量地址 |
| `bound(accessor, [实参…])` | 「用这些实参调这个类型的 accessor」得到的类型 | 调用一个已认出的 metadata accessor 之后，x0 里的值 |
| `instantiatedFromMangledName(…)` | 按另一条 mangled name 实例化出来的类型 | 调用 `__swift_instantiateConcreteTypeFromMangledName` 之后 |
| `witnessTable` | 一张见证表（不是类型，传参时要跳过） | 调用 `swift_getWitnessTable` 之后 |

规则很朴素：`mov` 把表达式从一个寄存器搬到另一个；`str` / `ldr` 在栈槽和寄存器之间搬；调用一个 accessor 时按 ARM64 的调用约定收集实参（x1、x2、x3，超过三个从 x1 指向的栈缓冲区取），实参里的见证表按被调类型的泛型签名跳过；`ret` 或尾调用时，x0 里的表达式就是答案。

控制流也照走：函数内的 `b` 就跳过去；到已知函数的 `b` 是尾调用，等于「调它然后返回它的结果」。条件分支分两种：**能判定的**直接判定——比如样本三那个运行时标志，我们当它是 true；比较立即数也算得出来。**判定不了的**只有一种：版本检查的结果。遇到它就按两种策略各跑一遍（`BranchPolicy`：假设条件为假 / 为真），两次的结果就是 `if #available` 的两支；被判定的那条指令的种类（`cbz` / `cbnz` / `csel eq` / `csel ne`）说明哪一次对应「版本满足」。

求值器（`ThunkTypeEvaluator`）最多走 1024 步，防止死循环。

### 第四步：把表达式变回类型名

表达式要变成 demangler 的 `Node`（类型名的树）才能进渲染管线（`ThunkTypeNodeBuilder`）：

- `constantMetadata(address)`：读那块 metadata，找到它的描述符，从描述符还原类型名。只认 struct / enum / optional 三种 kind，class 的描述符不在那个位置，不猜。
- `bound(accessor, 实参)`：accessor 对应一个描述符，从描述符还原类型名，再按它的泛型参数层级把实参逐层填进去（`Outer<A>.Inner<B>` 这种嵌套要一层一层包），得到 `ModifiedContent<…, …>` 这样的节点。只有 key 参数（真正占实参位置的参数）能填，遇到非 key 参数的链拒绝。
- `argument(k)`：这是 thunk 主人的第 k 个泛型实参。它对应哪个泛型参数，要看主人的泛型上下文：参数缓冲区的布局是「每一层的 key 参数按签名顺序排，然后是见证表」，所以给 seam 传一份「每层哪些参数是 key」（`AccessorThunkOwnerLayout`），就能把第 k 个词映射成第 `(depth, index)` 个参数节点，交给既有的泛型实参替换管线换成真实实参（或未特化时打印成 `A`）。
- `instantiatedFromMangledName`：直接 demangle 那条 mangled name。

### 宁可不猜

整条链的原则是「宁可留占位符，不出一个真实但错误的类型」，因为后者肉眼看不出来。具体的拒绝点：调用目标认不出、`csel` 的条件码没建模、metadata 的 kind 不是 struct / enum / optional、非 key 参数的泛型链、类型实参命不了名。每个拒绝只影响那一支，另一支照常。

## 进程内的另一条路

在进程内读（`MachOImage`）时不需要这套推演：runtime 就在手边，直接让它执行 thunk。做法是把整条 witness 的 mangled name 连同 conforming type 的描述符和它 metadata 里的泛型实参区一起交给 `swift_getTypeByMangledNameInContext`——这正是 runtime 自己解析关联类型 witness 时的调用方式，thunk 第一条指令 `ldr x19, [x0]` 读的就是那块实参区，所以必须传真实的区，不能传空。答案通过 `_mangledTypeName` 拿回来再 demangle。

这条路的限制：只能得到**当前系统这一支**（runtime 只会走一条），带泛型参数的 conformer 没有实参就没有 metadata、runtime 会答 nil，class conformer 的实参区偏移不是常量也没接。SwiftUI 的 17 条 witness 里它能答 5 条。

两条路互为验证：进程内的答案是权威的（那就是真的会发生的事），离线的答案必须和它逐字相等——见下面的 oracle 测试。

## 读出来的答案怎么进输出

- **原位替换**。kind-9 引用可以嵌在类型树的任何位置（`FeedbackGenerator.Body` 的引用在 `ModifiedContent<ModifiedContent<…>, _AppearanceActionModifier>` 的中间），所以渲染侧是一个 `Node` 的 rewriter（`AccessorFunctionReferenceRewriter`），在树里找到引用、换成答案，外面的 `ModifiedContent<…>` 链和泛型实参照常保留。关联类型 witness 和 field record 走同一个 rewriter。
- **两支都保留**。rewriter 用当前平台那支（版本满足支）替换，同时把每个 thunk 的全部候选记进一个账本；要另一支时用「选第 n 支」再跑一遍 rewriter，得到整条 witness 按那一支替换后的全文。这就是模型里 `AssociatedTypeWitnessProjection.conditionalCandidates` 的来源（每支带平台版本条件、thunk 那一支的类型、整条 witness 全文），也是 `interface` / `dump` 里 `typealias` 上方那几行注释的来源（`ConditionalWitnessComment`）。
- **diff 不看它**。哪个系统上读的二进制不是 ABI 事实，所以候选不进 ABI diff 的 key。
- **失败时**：树保留，引用位置打 `accessor function at N`（这句来自上游 `NodePrinter`，快照归一化认识它）。之前的做法是整棵树放弃、只打一个裸的描述符地址，把实参全丢了。

## 代码地图

```
Sources/SwiftThunkAnalysis/
├── SwiftThunkAnalysis.swift                    # 模块说明
├── Instructions/
│   ├── ThunkInstruction.swift                  # 我们自己的指令词汇表（寄存器、操作、条件码）
│   └── CapstoneThunkDecoder.swift              # 第一步：Capstone 解码 → 词汇表；函数边界判定
├── Analysis/
│   ├── ThunkTypeExpression.swift               # 第三步的值域：类型表达式、被调方分类、求值环境协议
│   ├── ThunkTypeEvaluator.swift                # 第三步：符号求值器，照走控制流，两种分支策略
│   ├── AccessorThunkAnalyzer.swift             # 两次策略求值 → 候选列表（哪次是满足支）
│   ├── AccessorThunkProgram.swift              # 候选、条件、版本检查、降级原因的数据结构
│   └── ThunkRegisterTracker.swift              # 0028 遗留的寄存器跟踪（单次查表读法的回落）
└── Resolution/
    ├── AccessorThunkReader.swift               # 入口：偏移 → 反汇编 → 分析 → 每支的类型节点
    ├── MachOThunkEnvironment.swift             # 第二步：给调用目标起名（accessor 索引、stub、槽位、跨镜像）
    ├── MetadataAccessorIndex.swift             # accessor 地址 → 类型描述符（按镜像缓存）
    ├── ThunkAddressSpace.swift                 # 共享缓存偏移与地址的换算（三套账的坑就在这里收口）
    ├── ThunkTypeNodeBuilder.swift              # 第四步：表达式 → 类型名节点
    └── AccessorThunkOwnerLayout.swift          # thunk 主人的泛型参数布局（argument(k) 对应哪个参数）

Sources/SwiftDeclarationRendering/
├── AccessorThunkResolution.swift               # 渲染层用的 resolver（默认就是反汇编读取器）与测试注入点
├── ConditionalWitnessComment.swift             # `typealias` 上方那几行分支注释
├── InProcessAccessorFunctionResolution.swift   # 进程内那条路
└── Extensions/Node+OpaqueType.swift            # rewriter、候选账本、按支重跑
```

## 验证与怎么信它

- **合成指令序列的单元测试**（`ThunkTypeEvaluatorTests`、`AccessorThunkAnalyzerTests`）：不用二进制，手写十几条指令钉每条求值规则——accessor 链与尾调用、栈传参、见证表跳过、未知调用降级、缓存探测形态、常量 metadata、mangled name 实例化。
- **fixture**（`FieldRecordThunkResolutionTests`、两套快照）：`SymbolTestsCore` 里 `AccessorFunctionReferences` 命名空间的 `~Copyable` 字段，要求读成源码声明的 `NoncopyableResourceTest` / `NoncopyableGenericBoxTest<Int>`，不随系统版本漂移。
- **真实框架**（`AccessorThunkReaderTests`、`OpaqueTypeRenderingIntegrationTests`）：SwiftUI 的 17 条 witness 全部解出、两支都在、注释打出来。
- **oracle 测试**（`ConstructedThunkOracleTests`）：这是整套功能里最重要的一条。对 SwiftUI 每个非泛型 conformer 的每条 kind-9 witness，离线读出的答案必须和进程内 runtime 执行 thunk 得到的答案逐字相等（私有上下文的拼写做归一化）。它抓的正是「真实、全限定、错误」的读法——0028 第一版的两处误读（漏掉尾调用、把中间结果当答案）都是它揪出来的。
- **调查用探针**（`RealThunkShapeProbe`、`ThunkResolutionSurveyProbe`，默认禁用）：把 SwiftUI 每个不同形态的 thunk 或每条引用的解析结果打印出来，遇到新形态时临时启用看一眼。

## 已知降级

| 情况 | 行为 |
|---|---|
| x86_64 | 不做，只有 ARM64 解码器；那一支留占位符 |
| thunk 调了认不出的函数 | 那一支留占位符，另一支照常 |
| 泛型 conformer 的进程内解析 | runtime 答 nil，回落离线读法 |
| class conformer 的进程内解析 | 没接（实参区偏移不是常量，也没有实测样本） |
| `csel` 的条件码没建模 | 那一支留占位符（在两个真类型之间抛硬币比占位符更糟） |

## 术语对照

| 术语 | 意思 |
|---|---|
| mangled name | 编译器给类型 / 符号编码后的名字串，例如 `Si` = `Swift.Int` |
| demangle | 把 mangled name 解回可读的类型树（`Node`） |
| metadata | 运行时描述一个具体类型的数据块；泛型类型每种实参组合各一块 |
| metadata accessor | 编译器为每个类型生成的函数，给它泛型实参、它返回 metadata |
| thunk | 编译器生成的一小段代理函数；本文里特指 kind-9 引用指向的 metadata accessor thunk |
| symbolic reference | mangled name 里嵌的「指针」而不是名字；kind 9 指向函数，其它 kind 指向描述符 |
| descriptor | 类型 / protocol 的静态描述符，写在二进制里，离线可读；metadata 是它的运行时化身 |
| witness table | 某类型对某 protocol 的实现表；传给泛型 accessor 时和类型实参并排，但不是类型 |
| stub / GOT 槽 | 跨镜像调用的桥接代码和它读的地址槽位 |
| tail call | 用 `b` 跳到另一个函数、把它的返回值当自己的返回值；不会跳回来 |
| SE-0360 | 允许 `some P` 在 `if #available` 两支返回不同类型的 Swift 提案 |
| `__isPlatformVersionAtLeast` | compiler-rt 的版本检查函数，参数是平台编号和三段版本号 |

## 延伸阅读

- 提案 [0028](../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md)（离线反汇编读取、两支进模型、进程内路径）和 [0029](../Evolutions/0029-thunk-type-construction-evaluation.md)（符号求值器、field record 接入），决策日志里有每一步为什么这样做。
- [AccessorFunctionReferenceRendering.md](AccessorFunctionReferenceRendering.md)：渲染路径的演进阶梯（占位 → 进程内 → 离线反汇编 → 类型构造求值）与实测数据。
- 任务报告：[2026-09-11 首批](TaskReports/2026-09-11-offline-accessor-thunk-resolution.md)、[2026-09-11 收尾](TaskReports/2026-09-11-accessor-thunk-resolution-follow-up.md)、[2026-09-12 求值器与后续](TaskReports/2026-09-12-thunk-type-construction-evaluation.md)。
