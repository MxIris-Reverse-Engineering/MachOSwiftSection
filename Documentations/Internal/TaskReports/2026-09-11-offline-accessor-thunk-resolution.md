# 2026-09-11 离线解析不透明类型的 accessor thunk

对应提案：[0028](../../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md)

## 问题

`swift-section dump --sections associatedTypes` 对 SwiftUI（macOS 26 系统共享缓存）输出里，有 17 条
关联类型witness 整行是个裸地址：

```
extension SwiftUI.ResolvedMenuStyle: SwiftUI.View {
    typealias Body = opaque type symbolic reference 0x367C6120.0
}
```

其中包括 RuntimeViewer [issue #5](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/issues/5)
报的 `FeedbackGenerator.Body`——它的另一半（泛型实参收集错位）已由 commit `a85b172d` 修掉，剩下这一半。

## 调研：三件事和提案初稿写的不一样

提案是在上一轮会话里写的，实现阶段对着真实二进制重测，推翻了其中三处。**这三处都已回写进提案的
「前期调研」章节**，这里只记结论和它们为什么会写错。

### 1. 地址换算：真正的规则只有一行，提案里那一套是错误换算逼出来的

提案写的是「segment 反查 + `FullDyldCache.cache(for:)` + `resolveOptionalRebase`」。真正的规则在
`Sources/MachOSwiftSection/MachOFile+Swift.swift` 的 `_sectionOffsetAndSize`：

```swift
let offset = if let cache = machO.cache {
    section.address - cache.mainCacheHeader.sharedRegionStart.cast()
} else {
    section.offset
}
```

**对共享缓存里的 image，`MachOSwiftSection` 全链路的 `offset` 不是文件偏移，而是
`unslidVirtualAddress - sharedRegionStart`。** 换算就是一次加减。

上一轮之所以堆出那一套，是因为一开始用 `segment.fileOffset` 去算虚拟地址，得到的地址**偏了
0x88000**，于是候选落到了别的 image 的段里（实测报成 `TextRecognition` 的 `__AUTH_CONST`、
`libfaceCore` 的 `__TEXT`），然后为了「跨 subcache 定位」把 `FullDyldCache` 那一套搬了进来——解决的是
自己制造的症状。

**这个坑要单独记住，因为它不会报错**：`adrp` 的页基准来自指令自身地址，小于一页的误差**不改变**
算出来的候选地址，只是让它指向错的地方。也就是说错误的换算会给出一个「能算、看着也合法」的地址。

三套账的对照（全部实测于 SwiftUI / macOS 26）：

| 用法 | 账 |
|------|-----|
| `readElements(offset:)` / 一切 `MachOSwiftSection` 的 offset | `虚拟地址 − sharedRegionStart` |
| `segment.fileOffset` / `headerStartOffsetInCache` | subcache 文件内偏移（对 SwiftUI 差 557056） |
| `MachOFile.fileOffset(of:)` | 文件账，**与 `readElements` 不互逆** |
| `FullDyldCache.address(of:)` | 第三套（再差 16384） |

定位方法留档：把 `readElements` 返回的字节拿到**已加载**的 SwiftUI 里做内存搜索，看它落在 image
起点加多少——这是唯一能把「MachOKit 内部自洽但与我的算式不一致」这件事切开的办法。

### 2. `csel` 选出来的是类型的 metadata 地址，不是 opaque type descriptor

提案猜是 descriptor。实测是 **metadata**（第一个 word = `0x200`，Swift struct metadata kind）。这反而更
好办：metadata 的 `…VN` 符号是**导出**的，strip 不掉，所以至少一侧能直接从符号表拿到完整类型名。

```
候选 x9 = 0x1f22c5888  符号 _$s7SwiftUI36AllowsWindowActivationEventsModifier…7DynamicVN
候选 x8 = 0x1f22c5810  无符号 → 走 metadata → context descriptor → 名字 → …Static
```

进程内 runtime（执行 thunk）对同一条记录给的是 `.Static`，与离线解出的「版本满足」分支一致——
oracle 成立。

### 3. 规模：17 条记录只对应 3 个 thunk

初稿写 15 条（实测 17），而且没注意到去重后只剩 **4 个 opaque type descriptor / 3 个 thunk**。杠杆比
预期好得多：解掉三个 thunk 就能修好全部 17 行。

三个 thunk 的形态与可解性：

| 形态 | 样本 | 结果 |
|------|------|------|
| 版本检查 + `cmp`/`csel` 在两个 metadata 地址间二选一 | `ResolvedMenuStyle.Body` | 两支全解 |
| 版本检查 + `cbz` 分两支，各自 `bl` 一个 metadata accessor | `OnModifierKeysChangedModifier.Body` | 两支全解（`_TaskModifier2` / `_TaskModifier`） |
| 一支干净，另一支是一长串真实构造代码（多次 `bl`、`pacda` 签名的函数指针调用） | `DefinesSearchCompletionModifier.Body` | 两支都未解 |

## 最终方案

### 模块

`Sources/SwiftThunkAnalysis/`，由 SPM trait `ThunkAnalysis` 控制，**默认关闭**。每个源文件都包在
`#if THUNK_ANALYSIS` 里，所以关掉时这个 target 仍然构建，只是编译成空模块、不链 Capstone。

**trait 不能避免的事**：SwiftPM 仍然会 resolve 并 clone `swift-capstone`。trait 管的是编译，不是
checkout。这一点在 `Package.swift` 的 trait 声明处记了。

依赖方向是**反的**，这是有意的：`SwiftDeclarationRendering` 声明 `AccessorThunkResolving` seam，
`SwiftThunkAnalysis` 实现并注册。反过来就会让所有下游都吃一个 C 反汇编引擎。

### 分层

```
CapstoneThunkDecoder      唯一知道 Capstone 存在的文件；字节 → ThunkInstruction
ThunkInstruction          与引擎无关的指令词汇表（10 个 case）
ThunkRegisterTracker      线性抽象解释：只跟踪「已知地址」和「小整数」
AccessorThunkAnalyzer     形态识别 → AccessorThunkProgram（版本条件 + 候选 + 未读清单）
ThunkAddressSpace         offset ↔ 虚拟地址，上面那条规则的唯一实现
MetadataAccessorIndex     accessor 函数地址 → type descriptor（一次扫 __swift5_types，按 image 缓存）
AccessorThunkReader       串起来：偏移 → 类型节点
```

把指令词汇表与 Capstone 隔开，是为了让识别层能用**合成指令序列**做单测——不需要二进制、不需要
反汇编器，也就不会随 OS 升级漂移。13 个单测都是这么写的。

### 诚实降级

三处刻意「不猜」：

1. **一支里有多于一个 `bl`** → 判定这一支不是简单查表，记 `branchIsNotASingleLookup(callCount:)`，
   **不出候选**。取第一个 `bl` 会给出一个真实、全限定、但错误的类型——正是 `.children` 那个 bug
   之所以长期没被发现的失败模式，不值得再犯一次。
2. **`csel` 的条件码不认识** → 不出候选。在两个真类型之间抛硬币比占位符更糟。
3. **metadata 的 kind 不是 struct/enum/optional** → 不读。class 的 descriptor 在别的偏移，按这个
   layout 读会把无关的 word 当指针。

而且这三处都只影响**那一支**：另一支照常解出，半个答案不会被整个丢掉。

### 绕开一个既有缺陷

`ValueMetadataProtocol.descriptor(in:)` 走 `Pointer.resolve(in:)` → `resolveOffset(at:)` →
`fileOffset(of:)`，在共享缓存 image 上答的是文件账，而后续读取要的是 section 账，于是
`offsetOutOfBounds`（实测两个候选都中）。这是**离线读绝对指针**的既有缺口，不是本批次引入的——
ABI 模型自己的读取走的是**相对**指针，纯加减、不跨账，所以碰不到。

绕法：`resolveRebase(fileOffset:)` 直接答在正确的账里。代码注释里写清了为什么不用那条路。

## 验证

- **单测 13 个**（`AccessorThunkAnalyzerTests`）：合成指令序列，钉三种形态、条件码方向、诚实降级、
  寄存器跟踪（caller-saved 清除、地址与整数分开、内存加载置未知）。
- **端到端 2 个**（`AccessorThunkReaderTests`）：对真实 SwiftUI 断言**形状**而非类型名——名字随 OS
  升级漂移，钉了就会周期性变红；要求的是「解出版本条件 + 两个互不相同的具名类型，且都不含
  `symbolic reference` / `accessor function at`」。
- **渲染集成 2 个**（`OpaqueTypeRenderingIntegrationTests`）：注册 resolver 前后对比，断言裸地址条数
  **减少**；另一个断言不注册时输出不变。
- **回归**：trait 关 105 测试 / 14 套件通过；trait 开 279 测试 / 44 套件通过（含 SwiftInterfaceTests
  的快照）。默认输出零变化——resolver 不注册就不走新分支。
- **CLI 实测**：`swift-section dump --sections associatedTypes` 对 SwiftUI，裸地址 **17 → 5**，
  整文件 diff 24 行，全部是修复本身。

`FeedbackGenerator.Body`（issue #5）：

```
- typealias Body = SwiftUI.StaticIf<…, ModifiedContent<ModifiedContent<opaque type symbolic reference 0x367D5978.0, _ValueActionModifier2<A>>, _AppearanceActionModifier>, …>
+ typealias Body = SwiftUI.StaticIf<…, ModifiedContent<ModifiedContent<SwiftUI._TaskValueModifier2,          _ValueActionModifier2<A>>, _AppearanceActionModifier>, …>
```

注意这条的 kind-9 引用**嵌在树中间**，不在根上——所以渲染层那一步写成了 rewriter 而不是根节点
检查。

## 与计划的偏差

- 提案的「详细设计」按实现修正了两处：候选是 metadata（不是 descriptor）、seam 传 `Node`（不是
  `NodeReference`，因为调用点 `Node+OpaqueType.swift` 全程操作 `Node`）。
- **模型侧的「其它候选」字段没做。** 提案写的是在关联类型 witness 投影旁加一个条件候选列表，
  供宿主展示「另一个版本会是什么」。当前批次只把**当前系统对应的那一支**接进了渲染，多候选停在
  `AccessorThunkResolving` 的返回值上（宿主已经能拿到，只是模型里没有落位）。留待下一批。
- **进程内路径没做**，按原计划它排在离线之后。
- **回落文案没改**。提案定了「换成说人话并带实参」，但那个文案出自 `Demangling` 包的 `NodePrinter`，
  改它要在渲染层拦截并重生成一批快照基线。本批次的价值不依赖它，合在一起会把一个「默认输出零变化」
  的改动变成会动基线的改动。
- 剩余 5 条裸地址来自第三个 thunk 及引用它的记录，需要符号执行或更多形态识别，未做。
