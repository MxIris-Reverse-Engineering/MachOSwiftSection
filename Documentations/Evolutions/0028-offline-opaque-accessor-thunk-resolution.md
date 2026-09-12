# 0028 - 离线解析不透明类型的 accessor thunk

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-11
- **最后更新**: 2026-09-12
- **所属愿景**: 无
- **关联提案**: 无（前置修复 `collect an opaque type's generic arguments from .children` 已单独落地，见 commit `a85b172d`）
- **实现分支 / PR**: `next`
- **配套文档**: [任务报告](../Internal/TaskReports/2026-09-11-offline-accessor-thunk-resolution.md)、[收尾批次任务报告](../Internal/TaskReports/2026-09-11-accessor-thunk-resolution-follow-up.md)

## 摘要

SwiftUI 里有一批 `Body` 关联类型现在渲染成裸地址 `opaque type symbolic reference 0x367C6120.0`
（`Slider` / `Toggle` / `TextField` / `Picker` 等 15 条），因为它们的 underlying type 在 opaque type
descriptor 里存的不是 mangled name，而是一个 **kind-9 accessor thunk** 的相对指针。实测确认这批
thunk 是 **availability-conditional** 的：函数体里先调 `__isPlatformVersionAtLeast(macOS 26.0)`，
再按结果在两个类型之间二选一——所以它们本来就没有唯一答案。

本提案给库加一条**离线**解析路径：用 Capstone 反汇编 thunk、识别版本检查与分支、把两个候选各自
解出来。新增一个可选 target 承载这条路径（SPM trait 控制，默认关闭），`SwiftDeclaration` 的关联
类型 witness 旁边加一个「其它候选」字段来承载「一个声明多个答案」，渲染层决定怎么呈现。

## 动机

### 具体现象

`swift-section dump --sections associatedTypes` 对 SwiftUI（macOS 26 系统共享缓存）输出里，
15 条 `Body` 整行是一个裸地址：

```
extension SwiftUI.Slider: SwiftUI.View {
    typealias Body = opaque type symbolic reference 0x367C6120.0
}
```

`Toggle` / `TextField` / `Picker` / `ResolvedMenuStyle` 同样。这些是 SwiftUI 最常用的公开 API，
对读的人来说这一行零信息量——地址只有拿去 IDA 才有用，而 `swift-section` 的使用者未必在做逆向。

### 这是 RuntimeViewer issue #5 剩下的一半

[issue #5](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/issues/5) 报的是
`FeedbackGenerator.Body` 类型信息不完整。该 issue 的另一半（泛型实参收集错位）已由
commit `a85b172d` 修复，SwiftUI 上 178 条错误类型归零。但 `FeedbackGenerator` 本身修复后停在：

```
ModifiedContent<ModifiedContent<opaque type symbolic reference 0x367D5978, _ValueActionModifier2<A>>, _AppearanceActionModifier>
```

内层那个 opaque 的 underlying type 就是一个 accessor thunk，正是本提案要解的东西。

### 为什么离线这条先做

进程内（`MachOImage`）路径只要把整条 mangled name 交给 `swift_getTypeByMangledNameInContext`，
runtime 自己会执行 thunk——一行调用，已实测可行（见前期调研）。但它**只会返回当前系统对应的那一个
分支**，另一个分支永远看不到。离线路径反而能给出更完整的事实：两个候选加各自的版本条件。所以离线
是真正需要设计的那条，进程内那条可以随后补。

## 前期调研

### kind-9 引用的结构（实测）

`__swift5_typeref` 里这条记录的字节是 `09` 后跟 4 字节相对偏移，指向 `__text` 里一个函数：

```
@0x1850: tag=0x09 rel=-761 -> target=0x1558
```

这是编译器的逃生门：当 mangled name 用到了部署目标的 runtime demangler 不认识的特性时，
IRGen 的 `getTypeRefByFunction`（`lib/IRGen/GenReflection.cpp`）不再嵌入类型名，改嵌一个
函数地址，让运行时调函数拿 metadata。既有实现说明见
[`Documentations/Internal/AccessorFunctionReferenceRendering.md`](../Internal/AccessorFunctionReferenceRendering.md)。

### 符号的命运（实测，未 strip 的 fixture）

编译一个带 always-noncopyable 字段的 fixture（那是 kind-9 的第二条触发路径，不看部署目标），
`nm -a` 给出：

```
0000000000001850 s _get_type_metadata 12ThunkFixture6TicketV noncopyable.1
0000000000001864 s _get_type_metadata 12ThunkFixture7WrapperVyAA6TicketVG noncopyable.2
0000000000004050 S _$s12ThunkFixture6TicketVN
```

- 前两个符号名里**内嵌完整类型 mangling**（`12ThunkFixture7WrapperVyAA6TicketVG` 就是
  `Wrapper<Ticket>`），但小写 `s` 表示 local symbol——strip 第一个拿掉。**OS 框架上查不到**，
  这是既有实现说明里「层 2 离线符号表还原」方案对系统框架失效的原因，已在 SwiftUI 上验证：
  thunk 地址处 `symbols` 为空。
- 注意这两个符号的地址落在 `__swift5_typeref`（0x1832–0x186A）里，说明它们标的是**那条 typeref
  数据**而不是 thunk 函数；真正的函数在相对指针另一头。
- 第三个是 metadata 符号，大写 `S` = 导出，**strip 拿不掉**。

### thunk 内部引用了什么（实测）

fixture 上两种形态：

```asm
; 形态 A —— 具体类型
adrp x8, … ; ldr x8, [x8, #…]      ; _swift_runtimeSupportsNoncopyableTypes
cbz  x8, <fallback>
adrp x8, … ; add x8, x8, #…
add  x0, x8, #0x10                  ; ← metadata 地址，那里是导出的 …VN 符号
ret

; 形态 B —— 泛型实例化
adrp x0, … ; add x0, x0, #…         ; cache 变量
adrp x1, … ; add x1, x1, #…         ; ← 指向一个相对指针
bl   __swift_instantiateConcreteTypeFromMangledNameV2
```

形态 B 的 x1 解引用后落回 `__swift5_typeref`，那里是**另一条 mangled name**（实测
`01 7d ff ff ff …`，带符号引用的正常形式）。这条一定是 runtime 认识的形式——逃生门存在的理由
就是原来那条它不认识，所以换了一条认识的，因此 demangle 必定成功。

### SwiftUI 的真实形态：availability-conditional（实测）

把 SwiftUI 的真实 thunk 字节读出来反汇编（`ResolvedMenuStyle.Body`，thunk 在文件偏移
891681920 / VM `0x1b52e7c80`）：

```asm
pacibsp                            ; arm64e 指针认证
stp  x20, x19, [sp, #-0x20]!
ldr  x19, [x0]
mov  w0, #1                        ; platform = macOS
mov  w1, #26                       ; major = 26
mov  w2, #0                        ; minor
mov  w3, #0
bl   #0x1b67570e4                  ; __isPlatformVersionAtLeast
adrp x8, #0x1f234d000 ; add x8, x8, #0x810    ; ← 候选 A
adrp x9, #0x1f234d000 ; add x9, x9, #0x888    ; ← 候选 B
cmp  w0, #0
csel x2, x9, x8, eq                ; 按版本选一个
```

`OnModifierKeysChangedModifier.Body` 参数是 `(1, 26, 4, 0)`（macOS 26.4），且用 `cbz` 分到两个
不同的 `bl`。三个样本调的都是同一个版本检查函数。

**所以这批不是「mangling 特性不支持」，而是 SE-0360 的 availability-conditional opaque type
（`if #available` 返回不同类型）。它们本来就没有唯一答案。**

### 进程内路径已验证可行（实测）

`dlopen` SwiftUI 后把整条记录的 mangled name 交给 `swift_getTypeByMangledNameInContext`：

```
SwiftUI.ResolvedMenuStyle.Body
  现在:    opaque type symbolic reference 0x1BC202120.0
  runtime: SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.Menu<MenuStyleConfiguration.Label,
           MenuStyleConfiguration.Content>, SwiftUI.AccessibilityAttachmentModifier>,
           SwiftUI.(unknown context at $1bc20227c).AllowsWindowActivationEventsModifier.Static>
```

runtime 自己执行了 thunk。泛型 conforming type（`Slider<Label, ValueLabel>` 等）返回 nil——
它们的 Body 依赖未绑定的泛型参数，不特化本来就没有答案。该函数的桥接**仓库里已经有**
（`Sources/MachOSwiftSectionC/include/Functions.h:108` + `RuntimeFunctions.swift`，
`GenericSpecializer` 一直在用）。

### 地址换算：真正的规则只有一条（2026-09-11 实测修正）

**提案初稿这一节是错的，实现阶段推翻并重测。** 初稿写的「segment 反查 + `FullDyldCache.cache(for:)` +
`resolveOptionalRebase`」那一套，是当时用错换算之后为了绕开症状堆出来的，其中每一步都在把误差往下传。

真正的规则在 `Sources/MachOSwiftSection/MachOFile+Swift.swift` 的 `_sectionOffsetAndSize` 里：

```swift
let offset = if let cache = machO.cache {
    section.address - cache.mainCacheHeader.sharedRegionStart.cast()
} else {
    section.offset
}
```

**对 dyld shared cache 里的 image，`MachOSwiftSection` 全链路的 `offset` 根本不是文件偏移，而是
`unslidVirtualAddress - sharedRegionStart`**（`sharedRegionStart` = `0x180000000`）。所以：

```
virtualAddress = offset + sharedRegionStart      // 反汇编要喂给 Capstone 的 PC
offset         = virtualAddress - sharedRegionStart  // adrp 算出的地址要读回来
```

一行加减，不需要 `FullDyldCache`，不需要 subcache 路由，不需要 `resolveOptionalRebase`。
非 cache 的普通 `MachOFile` 才走 segment 那条（`offset` 就是文件偏移）。

这条规则实测验证过三重：`readElement(offset: headerStartOffsetInCache)` 读出 `MH_MAGIC_64`；
`ResolvedMenuStyle.Body` 的 thunk 偏移 891681920 加上 `sharedRegionStart` 得到 `0x1b525fc80`，那里正是
`pacibsp`；把同一串字节拿到**已加载的** SwiftUI 里搜，落在 image 起点 +`0x11c80`，与该地址完全吻合。

**三个反例留在案上，因为它们都会静默给出看似合理的错地址**：

| 用法 | 在 cache image 上的表现 |
|------|--------------------------|
| `segment.fileOffset` / `headerStartOffsetInCache` | 是 subcache **文件内**偏移，与上面这套账差一个常数（SwiftUI 实测 557056），拿它算 VM 会得到一个仍落在 `__TEXT` 里、但偏了 0x88000 的地址 |
| `MachOFile.fileOffset(of:)` | 返回的是文件账，**与 `readElements(offset:)` 接受的账不是同一个**，两者不互逆 |
| `FullDyldCache.address(of:)` | 又是第三套账（实测再差 16384） |

踩上第一条的后果实测过：`adrp` 的页基准恰好不受 32 字节以内误差影响（同一 4 KiB 页），所以**候选地址仍然算得出来、看起来也合法**，只是落在了隔壁 image 的段里（实测报成 `TextRecognition` 的 `__AUTH_CONST`、
`libfaceCore` 的 `__TEXT`）。这正是「看起来对」的错误，也是选 Capstone 而非手写解码器的同一类理由。

### 候选是什么：metadata 地址（2026-09-11 实测，修正初稿猜测）

初稿猜 `csel` 选出来的是 opaque type descriptor。实测**不是**，是**具体类型的 metadata 地址**：

```
候选 x9 = 0x1f22c5888  words[0] = 0x200          ← Swift struct metadata kind
  符号 _$s7SwiftUI36AllowsWindowActivationEventsModifier33_302179F1EB9AE99B83C6A183C0B4143ELLO7DynamicVN
候选 x8 = 0x1f22c5810  words[0] = 0x200          ← 同样是 metadata，符号已 strip
```

`…VN` 是 nominal type metadata 符号，**导出、strip 不掉**，所以至少一侧可以直接从符号表拿到完整类型名，
另一侧走 metadata → type descriptor → 名字（仓库现成能力）。

交叉验证成立：进程内 runtime 对同一条记录给出的是 `…AllowsWindowActivationEventsModifier.Static`，
而离线解出的另一分支是 `.Dynamic` —— 正是同一个 `if #available` 的两侧。

### 规模与形态：17 条 / 4 个 descriptor / 3 个 thunk（2026-09-11 实测）

对 SwiftUI（macOS 26 系统共享缓存）4698 条关联类型记录全量统计：

- **17 条**渲染为裸地址（初稿写 15，数字更正）；
- 它们只指向 **4 个**不同的 opaque type descriptor，去重后只有 **3 个**不同的 thunk —— 解掉这几个就能修好全部 17 行；
- 渲染里出现的是 `opaque type symbolic reference 0x…` 而不是 `accessor function at …`：`Node+OpaqueType.swift`
  的 rewriter 在 underlying type 解出来不是 `.type` 节点时就整支放弃，kind-9 节点根本没走到打印。初稿说的因果对，
  但触发路径要在这里记清楚。

三个 thunk 的形态与可解性各不相同：

| 形态 | 样本 | 离线可解性 |
|------|------|------------|
| 版本检查 + `cmp`/`csel` 在两个 metadata 地址间二选一 | `ResolvedMenuStyle.Body`（覆盖 8 条记录） | **完全可解**，已端到端跑通 |
| 版本检查 + `cbz` 分两支，各自 `bl` 一个 metadata accessor | `OnModifierKeysChangedModifier.Body` | 可解，但候选是函数，要从 accessor 地址反查类型 |
| 版本满足支干净，不满足支是一长串真实构造代码（多次 `bl`、`pacda` 签名的函数指针调用） | `DefinesSearchCompletionModifier.Body` | 满足支可解；不满足支要完整符号执行，**本批次不做** |

### swift-capstone 可用（实测）

`/Volumes/Repositories/Private/Org/MxIris-Reverse-Engineering/swift-capstone`，Capstone v5 的 Swift
绑定。用真实 thunk 字节跑通：

```
0x1b52e7ca4 bl       #0x1b67570e4       imm=0x1b67570e4
0x1b52e7ca8 adrp     x8, #0x1f234d000   imm=0x1f234d000
0x1b52e7cac add      x8, x8, #0x810     imm=0x810
```

关键三点：

1. `operand.immediateValue: Int64?` 是**结构化**的，且 `adrp` / `bl` 的值是**算好的绝对地址**
   （传对 `disassemble(code:address:)` 的 address 即可）——正是手工解码最容易错的那一步。
2. arm64e 的 `pacibsp` 正确识别，不会当成未知字节卡住。
3. 该 fork 的 `Package.swift` 带**按架构裁剪的 traits**，`traits: ["ARM64"]` 只编 ARM64；
   且自带 C 库 fork，不依赖 `brew install capstone`。`swift-tools-version: 6.2`，与本仓库一致。

## 提议方案

### 新增一个可选 target

`Sources/SwiftThunkAnalysis/`，依赖 swift-capstone（`traits: ["ARM64"]`）与 `MachOFoundation`。
用 SPM trait 控制，**默认关闭**：不开的下游压根不编 Capstone，行为回落到占位渲染。
（2026-09-12 起没有开关了：trait、每个文件的 `#if`、进程全局注册一并撤销，`SwiftDeclarationRendering` 直接依赖
`SwiftThunkAnalysis` 并调用读取器；见决策日志末行。）

`SwiftDeclarationRendering` **不依赖**它，而是声明一个 seam 协议；`SwiftThunkAnalysis` 实现并
注册。这与 `SwiftLayout` 相对 `MachOObjCSection` 是同一种关系。

### 解析链路

```
kind-9 节点的 thunk 偏移
  → + sharedRegionStart 得到 PC，Capstone 反汇编到函数边界
  → 线性跟踪寄存器里的已知地址（adrp / add / mov 的组合）
  → 识别 __isPlatformVersionAtLeast 调用，读出四个立即数得到版本条件
  → 识别 csel / cbz 两支各自选中的候选地址
  → - sharedRegionStart 转回 offset
  → 候选处的 …VN 符号直接给类型名；无符号则 metadata → type descriptor → 名字
```

函数边界要自己定：thunk 没有符号也没有大小，`__TEXT` 里紧挨着下一个函数。规则是线性扫描那条 ——
`ret`，或目标在已解码范围外的 `b`（尾调用）结束函数，**但前提是没有更靠后的条件分支目标**。
这个前提是必需的：`if #available` 的满足支正是以一条跳过不满足支的 `b` 结尾，在那里停会悄悄丢掉两个
候选中的一个。

### 模型：保留单值，旁边加候选

关联类型 witness 现在是单值。**现有字段不动**（放最新版本对应的那个），另加一个可选的条件候选
列表。现有调用方一行不改，想要完整事实的宿主去读新字段。

### 两条读取路径各走各的

- **离线**（`MachOFile`）：反汇编，拿到全部候选与版本条件。
- **进程内**（`MachOImage`）：调 `swift_getTypeByMangledNameInContext`，拿当前系统那一个。

两边结果不一致是预期内的，且正好互为验证（见落地步骤的测试策略）。

### 回落文案

不开 trait、或识别不了 thunk 形态时，那一行不再是裸地址，而是说人话的文案 **并带上节点自带的
实参信息**——`Slider` 那条的实参里其实是完整的 `ModifiedContent<…ResolvedSliderStyle…>` 链，
现在整个被丢了。

### 非目标

- **field record 里的 kind-9**（现在渲染成 `accessor function at 750396`）。机制相同，但量更大、
  要单独考虑性能，留待后续批次。
- **x86_64**。thunk 指令形态不同，要另写一套模式匹配，且手头没有真实样本可验证。
- **进程内路径改走反汇编**。已定为各走各的。
- **执行 thunk 代码**。离线路径只读不跑，这是它相对进程内的安全性优势。
- **泛型 conforming type 的特化**。`Slider<Label, ValueLabel>.Body` 依赖未绑定参数，不特化没有
  答案，那是 `GenericSpecializer` 的职责。

## 详细设计

### seam 协议（放在 `SwiftDeclarationRendering`）

```swift
/// 一个 accessor thunk 在某个版本条件下给出的 underlying type。
public struct ConditionalUnderlyingType: Sendable {
    /// `nil` 表示无条件（thunk 里没有版本检查）。
    public let availability: PlatformAvailabilityCondition?
    /// 落地时从 `NodeReference` 改成 `Node`：调用点 `Node+OpaqueType.swift` 全程操作 `Node`。
    public let typeNode: Node
}

public struct PlatformAvailabilityCondition: Sendable, Hashable {
    public let platform: UInt32      // __isPlatformVersionAtLeast 的第一个实参
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32
    /// true = 版本满足时走这个候选；false = 否则分支。
    public let isSatisfiedBranch: Bool
}

/// 由 `SwiftThunkAnalysis` 实现；trait 关闭时无人注册，解析回落占位。
public protocol AccessorThunkResolving: Sendable {
    /// 最当前的分支排第一位；形态读不出来时返回空数组（落地时去掉了 `throws`：
    /// 读不出来是**预期结果**而不是错误，调用点在 rewriter 里，抛错只会被吞掉）。
    func underlyingTypes(forAccessorThunkAt offset: Int, in machO: MachOFile) -> [ConditionalUnderlyingType]
}

public enum AccessorThunkResolution {
    /// 宿主在启用 trait 时注册；`Node+OpaqueType.swift` 的离线分支读它。
    public static var resolver: (any AccessorThunkResolving)?
}
```

### 模型字段（`SwiftDeclaration`）

在关联类型 witness 的投影上新增：

```swift
extension AssociatedTypeWitnessProjection {
    /// 当 underlying type 由一个 availability-conditional 的 accessor thunk 决定时，
    /// 这里是全部候选；否则为空。既有的单值字段始终等于最新版本对应的那一个。
    public var conditionalCandidates: [ConditionalUnderlyingType] { get }
}
```

### 调用点

`Sources/SwiftDeclarationRendering/Extensions/Node+OpaqueType.swift` 的
`OpaqueTypeRewriter.visit`，在 underlying mangled name 解出来是 `accessorFunctionReference`
节点这一支：MachOFile 且 resolver 已注册时走它，否则回落占位。

## 替代方案考量

- **手写 arm64 指令解码器**。零依赖，但 thunk 形态实测已有两种（`csel` 版与 `cbz` 分支版）且会随
  编译器版本漂移，还要处理 arm64e 的 PAC；手写意味着每遇一种新形态补一次位域解码。实测中我手工
  解码 `adrp` 时正是把文件偏移当成了 PC，页基准算错、读出假地址 SIGSEGV。Capstone 把这类错误整类
  消掉：模式匹配写成「看 mnemonic 和 operand」而不是位运算。
- **离线从符号表还原**（既有实现说明的「层 2」）。`_get_type_metadata <mangling>` 符号名里直接带
  完整类型，最省事——但它是 local symbol，OS 框架 strip 掉，实测 SwiftUI 上查不到。对未 strip 的
  用户二进制仍然有效，可以作为反汇编之前的快速路径，本提案不排斥，但不能作为主方案。
- **只渲染最新分支**。输出最干净，但丢掉了离线相对进程内唯一的优势（看到全部分支）。
- **单值字段直接换成多候选类型**。语义最干净（没有「代表值」这种人为选择），但是破坏性 API 变更，
  RuntimeViewer 和所有渲染路径都要跟着改。
- **两条路径统一走反汇编**。行为一致、能直接 A/B 对拆，但进程内放弃了「调 runtime 就行」的捷径，
  且 runtime 的答案是权威的（它就是实际会发生的事），放弃可惜。

## 影响

### 源码兼容性（source compatibility）

**纯新增**。新 target、新协议、新模型字段，既有单值字段语义不变（仍是单一类型，只是当 thunk 有多
候选时明确为「最新版本对应的那个」）。现有调用点一行不改。

唯一的行为变化是**回落文案**：不开 trait 时那一行从裸地址变成说人话的文案。这会改变 `dump` /
`interface` 对含 kind-9 的二进制的输出，快照基线需要重新生成——但那 15 条本来就是无效输出。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：新增 `SwiftThunkAnalysis`；`SwiftDeclaration` 加字段；`SwiftDeclarationRendering` 加
  seam 与回落文案；`Package.swift` 加 trait 与依赖。
- RuntimeViewer：**不开 trait 时零改动**。想要真实类型则开 trait 并注册 resolver，另可读新字段
  做「按版本切换」的交互。
- 新增一个 C 语言依赖链（swift-capstone → capstone fork）。trait 默认关闭意味着不开的人不付这个
  成本，这是选「默认关闭」而非「默认开启」的全部理由。

### 文档与示例

- 落地时写实现说明，记录 thunk 的指令形态与地址换算链路（下次维护必踩，代码本身看不出来）。
- 既有的 [`AccessorFunctionReferenceRendering.md`](../Internal/AccessorFunctionReferenceRendering.md)
  要更新：它的「层 1 / 层 2」阶梯需要补上本提案发现的第三种情况（availability-conditional），并
  改掉「离线构造上不可解析」这句——那句在 availability-conditional 这一类上不成立。
- `AGENTS.md` 的模块依赖图加 `SwiftThunkAnalysis`。

## API 演进与废弃策略

无废弃。纯新增，不需要 semver major 跃迁。

## 落地步骤

1. ✅ `Package.swift` 加 trait 与 swift-capstone 依赖；建空的 `SwiftThunkAnalysis` target，确认开关两种
   状态都能构建。
2. ✅ thunk 反汇编与形态识别，13 个单测用**合成指令序列**钉住（不依赖二进制，不随 OS 漂移）。
3. ✅ 地址换算（`ThunkAddressSpace`）——实现时发现真正的规则比提案设想的简单得多，见前期调研。
4. ✅ 接上 `Metadata` / `ContextDescriptor` 取类型名，打通端到端；accessor 形态另建
   `MetadataAccessorIndex`（一次扫 `__swift5_types`，按 image 缓存）。
5. ✅ 渲染层接 seam；模型的「其它候选」字段由收尾批次补齐（`AssociatedTypeWitnessProjection.conditionalCandidates`，
   见「收尾批次」一节）。
6. ✅ 真实框架冒烟：SwiftUI 裸地址 17 → 5；`ResolvedMenuStyle.Body` 的「版本满足」分支与进程内
   runtime 执行 thunk 得到的答案一致。
7. ✅ 配套文档：[任务报告](../Internal/TaskReports/2026-09-11-offline-accessor-thunk-resolution.md)；
   `AGENTS.md` 加模块条目与 offset 账的坑；
   [`AccessorFunctionReferenceRendering.md`](../Internal/AccessorFunctionReferenceRendering.md) 补层 3。
   未引入新术语，术语表不动。

### 收尾批次（2026-09-11，同日第二批）

首批落地时留下的三件事，这一批做完：

- **模型的多候选字段**：`AssociatedTypeWitnessProjection.conditionalCandidates`（`SwiftDeclaration`），每支一条
  `ConditionalWitnessCandidate`——版本条件、thunk 那一支的类型文本、整条 witness 按该分支替换后的全文；解码容忍
  缺 key。渲染层加 `Node.resolveOpaqueTypeCollectingConditionalCandidates(in:)`：rewriter 里挂一本候选账本记下每个
  thunk 的全部候选，再对每个非默认分支按「thunk 偏移 → 分支下标」的选择重跑一遍拿全文。索引期投影
  （`resolvedWitnessProjections`）改走它，并顺带解析 opaque（见决策日志「投影口径」一条）。
- **回落渲染保留实参**：`OpaqueTypeRewriter` 对含 kind-9 的 underlying type 不再整支放弃，照常替换实参与展开嵌套，
  kind-9 位置由既有的 `accessor function at N` 兜底。文案沿用，措辞换不换是另一个决定（要同步动上游 `NodePrinter`）。
- **进程内路径**：`InProcessAccessorFunctionResolution`（`SwiftDeclarationRendering`），`MachOImage` 上把整条 witness
  的 mangled name 交给 `swift_getTypeByMangledNameInContext`，context 与实参取 conforming type 的 descriptor 与
  metadata 泛型实参区，与 runtime 自己的 `swift_getAssociatedTypeWitnessSlow` 同一套调用；泛型 conformer 与
  class conformer 不猜。三个 witness 调用点统一走 `Node.resolveOpaqueType(witnessMangledName:conformingTypeName:in:)`。

实测（SwiftUI，macOS 26 共享缓存）：不开 trait 时 17 条全部从裸地址变成「类型里嵌一个未读引用」，开 trait 后剩
5 条如此，候选字段对 `FeedbackGenerator.Body` 给出 `≥ 26.4` / `< 26.4` 两份全文（`_TaskValueModifier2` 与
`_TaskValueModifier`）；进程内 17 条里 5 条由 runtime 答出，含离线读不了的 `DefinesSearchCompletionModifier.Body`。

### 仍然不做

- ~~剩余 5 条离线未读引用：`DefinesSearchCompletionModifier.Body` 那个 thunk，一支是真实构造代码链（要符号
  执行），另一支调的不是普通 metadata accessor。~~ 由后续提案
  [0029](0029-thunk-type-construction-evaluation.md) 的类型构造求值解掉
  （SwiftUI 离线 6 → 0），并顺带修正了本提案两种「查表」读法各一处误读（`csel` 之后的尾调用被丢、`cbz`
  分支里的尾调用没被数进调用次数）。
- field record 里的 kind-9、x86_64——原提案就列在非目标里。
- `accessor function at N` 的措辞——要同步动 swift-demangling 的 `NodePrinter`，另议。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-11 | Created as Draft | 用户要求「先写提案，离线的先做，进程内的简单放后面」。完整档，两轮澄清提问后落盘。 |
| 2026-09-11 | 渲染语义：模型里表达多候选 | 备选是「只出注释」与「只取最新分支」。选多候选是因为离线相对进程内唯一的优势就是能看到全部分支，压成一行注释等于把这个优势丢掉；宿主也拿不到结构化数据做交互。 |
| 2026-09-11 | 依赖边界：新 target + trait，默认关闭 | 备选是「默认开启」与「直接加进 SwiftDeclarationRendering」。MachOSwiftSection 是被 RuntimeViewer 等宿主依赖的库，不该让所有下游都跟着吃一个 C 反汇编引擎；直接加进渲染层则以后拆不出来。 |
| 2026-09-11 | 范围：只做关联类型的 opaque | field record 的 kind-9 机制相同但量更大，先验证整套机制再扩。 |
| 2026-09-11 | 架构：只 arm64 / arm64e | x86_64 要另写模式匹配，且手头没有真实样本可验证。 |
| 2026-09-11 | 模型形状：保留单值 + 旁加候选字段 | 备选是「单值字段直接换成多候选」（破坏性，RuntimeViewer 要跟着改）与「另开旁路查询 API」（一个声明的完整事实被拆到两处）。 |
| 2026-09-11 | 两条读取路径各走各的 | 备选是「统一走反汇编」。runtime 的答案是权威的（就是实际会发生的事），且进程内只要一行调用，放弃可惜；两边结果不一致本就是预期，正好互为验证。 |
| 2026-09-11 | 回落文案换成说人话并带实参 | 裸地址只对做逆向的人有用；而节点自带的实参信息（Slider 那条是完整的 ModifiedContent 链）现在被整个丢弃了。 |
| 2026-09-11 | Accepted | 用户「开始实现提案」即批准，按落地步骤逐步推进。 |
| 2026-09-11 | 实现阶段推翻三处调研结论 | 地址换算（真正的规则是 `虚拟地址 − sharedRegionStart` 一行，提案那套是错误换算逼出来的症状解）、候选语义（是 metadata 不是 descriptor）、规模（17 条而非 15，且只对应 3 个 thunk）。三处已回写进前期调研。 |
| 2026-09-11 | 单测改用合成指令序列，不用编译 fixture | 原计划「当场编译带 `@available` 的 fixture」。改因：要钉的是**形态怎么读**，而 fixture 编出来的 thunk 形态由编译器决定、不一定覆盖 SwiftUI 的三种；合成序列直接照抄实测反汇编，且不随工具链漂移。真实框架那条另有端到端测试，只断言形状不断言类型名。 |
| 2026-09-11 | seam 传 `Node` 而非 `NodeReference` | 调用点 `Node+OpaqueType.swift` 全程操作 `Node`，传 `NodeReference` 要在两侧各转一次，还得决定 intern 到哪个 store。 |
| 2026-09-11 | 模型的多候选字段推迟到下一批 | 渲染侧已能用（取当前系统那一支），多候选也已在 seam 返回值里。加模型字段要动 `SwiftDeclaration` 的投影与 ABI 快照口径，与本批次的技术风险无关，单独一批更清楚。 |
| 2026-09-11 | Implemented | 落地步骤 1–4、6、7 完成，第 5 步部分完成（渲染接通、模型字段未做）。实测 SwiftUI 裸地址 17 → 5。 |
| 2026-09-11 | 测试：fixture 钉行为 + runtime 结果做 oracle | 真实框架的类型随 OS 升级漂移，直接断言类型名必然周期性变红；用 runtime 结果做期望值则两边同步漂移，断言长期稳定，同时能抓住反汇编解错。 |
| 2026-09-11 | 收尾批次在本提案原地进行，状态回 `In Progress` | 第 5 步剩下的三件事（模型候选字段、回落渲染保留实参、进程内路径）都在已批准的范围内，与 0023 / 0026 在决策日志里记后续修正的先例一致；第三个 thunk 的符号执行、field record 里的 kind-9、x86_64 仍按非目标处理，不进本批 |
| 2026-09-11 | 索引期投影顺带解析 opaque type | 用户裁定。此前 `resolvedWitnessProjections` 打印的是未展开的 `opaqueType` 节点，任何 `some View` 的 witness 在 ABI 快照里都是 `opaque type symbolic reference 0x<描述符偏移>.0`，而 `assocwitness:` 的 payload key 直接含这段文本，偏移随构建漂移，两个 OS 版本之间每个 `Body` 都被报成 `.modified`。提案说的「单值字段始终等于最新分支」要成立，投影就必须解析；顺带消掉这个噪音。备选「不动投影、只加候选」被否：那样单值等于最新分支只在渲染输出成立，模型里不成立 |
| 2026-09-11 | 回落文案沿用 `accessor function at N`，只恢复被丢弃的树 | 用户裁定。裸地址的来源是 rewriter 在 underlying type 不是 `.type` 节点时整支放弃，于是 `printOpaqueType` 打出描述符地址并丢掉实参；改成含 kind-9 的树照常走实参替换与嵌套展开，kind-9 位置由两条打印路径既有、parity 测试钉着、快照归一化认得的 `accessor function at N` 兜底。换措辞要同步动 swift-demangling 的 `NodePrinter`，是另一个决定 |
| 2026-09-11 | 候选同时带「thunk 那一支的类型」与「整条 witness 全文」 | 未提问自定。宿主做「按版本切换」时要的是整条 witness 在那个版本的样子，不该要求它知道 thunk 嵌在树的哪一层（`FeedbackGenerator.Body` 的 kind-9 在 `ModifiedContent` 链中间）；thunk 那一支的类型单独给出，是为了让「到底哪一段在变」可见。实测每条 witness 只含一个 thunk，全文按每个候选单独替换生成，没有笛卡尔积 |
| 2026-09-11 | 进程内只对无泛型参数的 opaque 上下文走 runtime，候选列表进程内为空 | 未提问自定。runtime 执行 thunk 只给当前系统这一支，「全部候选」是离线独有的事实；带泛型参数的上下文不特化本来没有答案，且给 runtime 传空实参进 thunk 的 `ldr [x0]` 有空指针风险 |
| 2026-09-11 | 进程内路径改挂在 witness 调用点，门控改为「conforming type 能不带实参实例化」 | 原定放在 rewriter 的 `MachOImage` 分支、按 opaque 上下文有无泛型参数门控。一次性探针证明 SwiftUI 的 thunk 第一条就是 `ldr x19, [x0]`，实参缓冲必须是真实的区（runtime 的 `swift_getAssociatedTypeWitnessSlow` 传的是 conforming type metadata 的泛型实参区），而 rewriter 手里只有 opaque descriptor 没有 conforming type；三个 witness 调用点手里有 `conformingTypeName`，判据更直接。探针实测 17 条里 5 条答出、12 条泛型 conformer 返回 nil、零崩溃 |
| 2026-09-11 | 收尾批次落地，状态回 `Implemented` | 三件事全部完成。专项 14 个测试全绿；trait 开 506 测试 / 81 套件绿，trait 关 428 测试 / 68 套件绿，快照基线零改动；SwiftUI CLI A/B 恰好 5 行差异且全部是引用原位替换。配套文档：收尾批次任务报告（已登记在头部）、`AccessorFunctionReferenceRendering.md` 层 1 与层 3 补记、AGENTS.md 的 `SwiftThunkAnalysis` 与 `SwiftDeclaration` 条目、演进账本本节补记。未引入新术语，术语表不动 |
| 2026-09-12 | 撤销 trait 与 seam 反向依赖，改为直接依赖 | 用户裁定，两步到位。第一步先把 trait 从「编译门」改成「链接门」（SwiftPM 本来就为每个启用的 trait 定义同名编译条件，`.define` 多余；target 是普通 library，不该在源码里分叉）；随后用户进一步裁定「直接集成，不做 trait 判断，也不要 trait」。最终：`Package.swift` 删掉 trait 声明与所有条件边；`SwiftDeclarationRendering` 直接依赖 `SwiftThunkAnalysis`，kind-9 rewriter 默认用 `DisassemblingAccessorThunkResolver`（上移到渲染层）调 `AccessorThunkReader`；`AccessorThunkOwnerLayout` 下移到 `SwiftThunkAnalysis`；删掉进程全局的 `AccessorThunkResolution.resolver` 与 `installDisassemblingResolver()`，CLI 入口不再注册；`AccessorThunkResolving` 协议与 task-local 只作为测试注入点保留。代价：Capstone 的 ARM64 后端成为渲染层以上所有模块的常规依赖。收益：宿主什么都不用写就拿到解析——本仓库唯一的宿主是 CLI，RuntimeViewer 此前从未注册过，也就从未拿到过。fixture 的 kind-9 field record 随之在 dump / interface 快照里渲染成声明的类型，两份基线重录。 |
