# SwiftThunkAnalysis 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。
>
> 入门请先读[《AccessorThunkResolutionExplained》](../AccessorThunkResolutionExplained.md)——三个真实 thunk 逐行翻译、离线四步、代码地图。本文是那份讲解的模块视角索引。

## 模块定位

SwiftThunkAnalysis 干一件事：**不执行 thunk，把它算出来**。

起因是 SE-0360 的 availability-conditional opaque result type。当一个 `some View` 的具体类型随 `if #available` 分叉时，IRGen 没法在 field record / associated type record 里写一个 mangled name，于是写下 `0x09` 加一个指向 metadata accessor thunk 的指针（所谓 **kind-9 符号引用**）。离线读到这里就是一个裸地址杵在类型该在的位置。

本模块用 Capstone 反汇编那个 thunk（仅 ARM64），把它当成一段**类型构造程序**做符号求值：寄存器与栈槽里装的不是数值而是类型表达式，每个 call 解析到 thunk 会用到的那几个运行时入口之一，函数离开时 `x0` 里的表达式就是答案。可用性检查的结果判定不了，就**两支都跑**——这两次运行正好是 `if #available` 的两个分支。

它是一个普通 library target，`SwiftDeclarationRendering` 直接依赖它，**没有开关**。（最初一版把它放在 opt-in 的 SPM trait 后面、配 per-file `#if` 和进程级注册，2026-09-12 全部删掉：没有任何消费者想关掉它，那些机关只是多几处可以出错的地方。）

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 指令解码 | `Instructions/CapstoneThunkDecoder`、`Instructions/ThunkInstruction` |
| 2. 符号求值 | `Analysis/ThunkTypeEvaluator`、`Analysis/ThunkTypeExpression`、`Analysis/ThunkRegisterTracker` |
| 3. thunk 形状识别 | `Analysis/AccessorThunkAnalyzer`、`Analysis/AccessorThunkProgram` |
| 4. 环境与调用目标解析 | `Resolution/MachOThunkEnvironment`、`Resolution/MetadataAccessorIndex`、`Resolution/DependencyImageResolver`、`Resolution/ThunkAddressSpace` |
| 5. 对外读取面 | `Resolution/AccessorThunkReader`、`Resolution/AccessorThunkOwnerLayout`、`Resolution/ThunkTypeNodeBuilder`、`SwiftThunkAnalysis` |

## 当前能读到什么

按输入形态列，这是判断「某个 witness 读不出来算不算 bug」的基准：

| 输入 | 状态 |
|---|---|
| dyld shared cache 里的镜像（macOS 14.7 – 26.6、iOS 设备 cache、iOS 27 模拟器 cache） | 完整解析。跨镜像调用是 rebase 地址或镜像间跳板（读槽的 stub / 算地址的 stub island），都跟得下去 |
| 独立文件（第三方 app、iOS 26 及更早的模拟器运行时、即时编译的 fixture） | 完整解析，前提是给得出依赖搜索路径。跨镜像调用全是 GOT bind（只有名字），靠依赖镜像的 export trie + accessor 索引解名 |
| 编译器合并的 `…MaTm` accessor | 跟进函数体求值（真正的 accessor 从 `x3` 传入，函数体只查缓存再 `blr x3`） |
| 按名字引用的、属于**别的镜像**的 opaque 类型 | 重新 mangle 出描述符符号名、定位镜像、在那个镜像里展开 |
| macOS 27.0 的 cache（`dyld_v1arm64ex1`） | **打不开**。`MachOKit` 的 `DyldCacheHeader._cpuType` 不认这个 magic，要先改 MachOKit |

## 关键契约

### 三条故意的拒绝

每一条都只降级受影响的那一支，不影响整棵树。它们的共同逻辑是：**一个真实存在、完全限定、但是错的类型名，比一个占位符坏得多**。

1. 一支如果**构造**类型而不是查一个类型，就不能拿它的第一个调用当答案——那会命名一个中间值。（`FeedbackGenerator.Body` 曾因此被印成 `_TaskValueModifier`。）
2. 不认识的 `csel` 条件码不产出候选：在两个真实类型之间掷硬币，不如不答。
3. 泛型描述符的 accessor 没有实参就不给它命名。（`PlatformAccessibilitySettingsDefinition.cache` 曾因此被印成 `Array<LayoutDirection>`，实际是 `Mutex<Storage>`。）

可用性检查自身的调用**永远不跟进**——它的结果必须保持未知，后面那个 `cbz` 才会被两支都跑。

### 偏移口径：一个混用就静默出错的地方

对 dyld shared cache 里的镜像，`MachOSwiftSection` 全线使用的偏移是 `unslidVirtualAddress - sharedRegionStart`，**不是文件偏移**。同一个镜像上还并存着另外三套记账，彼此差值固定但都不等价：

- `segment.fileOffset` / `headerStartOffsetInCache`（subcache 文件偏移）
- `MachOFile.fileOffset(of:)`（文件记账，**不是** `readElements(offset:)` 所取偏移的逆运算）
- `FullDyldCache.address(of:)`（第三套）

混用不会抛错。`adrp` 是拿指令自身地址算页基址的，所以一个不到一页的误差照样能算出一个可计算、看起来合理、指向邻居镜像的候选地址（实测现象：SwiftUI 的候选看起来住在 `TextRecognition` 的 `__AUTH_CONST` 里）。本模块统一走 `resolveRebase(fileOffset:)`。

同类陷阱还有一个：`ExportedSymbol.offset` 是**相对 mach header** 的偏移，`MachOKit` 对 cache 镜像原样交出，所以它在那里不是文件偏移。唯一正确的换算是 `ThunkAddressSpace.address(forExportedSymbolOffset:)`（`__TEXT` 地址加偏移），dylib、可执行文件、cache 镜像通用。

### 「在不在本镜像内」用段范围判定

`ThunkAddressSpace.containsAddress(_:)` 是段范围测试，**不能**用 `offset(forAddress:)` 是否返回 nil 来代替：对 cache 镜像那个换算只是一次减法，cache 里任何地址它都答得出来。

## 测试注意

反汇编 resolver 是每个 task 的默认值，所以 fixture 的 kind-9 field record 在 dump / interface 快照基线里就是解析后的声明类型。需要占位符渲染（类型内部印 `accessor function at N`）的测试要自己 scope 一个什么都不答的 resolver：

```swift
AccessorThunkResolution.$taskResolver.withValue(UnreadableAccessorThunkResolver()) {
    // …
}
```

没有进程级 resolver，所以并行套件之间不会互相串。

## 相关文档

- [AccessorThunkResolutionExplained.md](../AccessorThunkResolutionExplained.md)——白话讲解与代码地图，**从这里开始读**。
- [AccessorFunctionReferenceRendering.md](../AccessorFunctionReferenceRendering.md)——读不出来时渲染层怎么表达。
- [OpaqueReturnTypeResolution.md](../OpaqueReturnTypeResolution.md)——opaque 返回类型的领域知识（描述符编码、字节级调试）。
- 演进提案（按时间顺序，一份一批）：[0028](../../Evolutions/0028-offline-opaque-accessor-thunk-resolution.md) 离线解析起步 · [0029](../../Evolutions/0029-thunk-type-construction-evaluation.md) 换成符号求值 · [0030](../../Evolutions/0030-standalone-file-thunk-resolution.md) 非 cache 文件 · [0031](../../Evolutions/0031-merged-accessor-inline-evaluation.md) 合并 accessor · [0032](../../Evolutions/0032-cache-stub-islands-and-unmodelled-instructions.md) stub island 与未建模指令 · [0033](../../Evolutions/0033-by-name-opaque-reference-expansion.md) 按名字的跨镜像 opaque 展开。
