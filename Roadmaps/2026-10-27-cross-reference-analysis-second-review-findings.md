# 交叉引用分析第二轮审查记录（0.24.0，2026-10-27）

审查对象：`0.23.0..0.24.0` 的 61 个提交，重点是 0.24.0 新加的 `CrossReferenceAnalysis`（提案 [0072-cross-reference-analysis](../Documentations/Evolutions/0072-cross-reference-analysis.md)）。`main` 与 `next` 在审查时完全相同，0.24.0 已发版。上一轮审查见 [2026-10-17 审查记录](2026-10-17-cross-reference-analysis-review-findings.md)。

**方式**：一个审查代理通读，交回 12 条候选（下文编号沿用它的顺序）；每条都由本人回到代码与本机的 dyld 缓存复核，四问逐条回答，能造出复现的造复现。核对第 9 条时另发现一条更严重的问题，编为 N1。指令形态的计数用 `dyld_info -disassemble` 直接反汇编运行中的缓存，环境是 macOS 26.6 的 10 核 Mac Studio。

**四问的共同答案**：本模块在 0.24.0 新写，0.23.0 没有；GitHub 上没有相关 PR 或 issue；[ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md) 已覆盖第 6 条（A66）与第 8 条（A71），理由仍成立，直接跳过。所以其余每条都是「0.24.0 引入、以前没修过」，例外写在各条的「既往」里。

**状态**：用户 2026-10-27 批准修建议修的五条（N1、1、2、11、12）。每条修复都先写了修复前失败的测试：前四条的 9 个测试在原始代码上一起跑过一次，全部按预期失败，两个只核对扫描逻辑本身的测试通过；第 2 条的两组测试（16 个用例）在前四条修好、它自己还没修的代码上跑过，全部按预期失败。修复后全部通过，全量 `swift test --skip IntegrationTests` 在 JHs-Mac-Studio-Ultra（macOS 27.2，Xcode 26.6）上 2588 个测试全部通过。判为不修或误报的五条登记在 ReviewAdjudications A76–A80；横向排查到、交给用户定的两条（MachOKit 的桩解码缺口、单字母泛型参数），用户定暂不处理，登记在 A81、A82。第 2 条要改变查询结果，按提案制先写了精简提案 [0076-objc-runtime-send-entry-points](../Documentations/Evolutions/0076-objc-runtime-send-entry-points.md)，用户点头后实现。

## 总表

| # | 问题 | 严重度 | 处理 | 测试 |
|---|---|---|---|---|
| N1 | 写死的 47 位地址掩码在 iOS 系真机上留下签名位 | 高 | 已修；第 9 条（同一掩码重复六处）并入 | `AddressMaskScanTests` |
| 1 | ld64 改写出的字面量 `ldr` 与 `adr` 不解码 | 中 | 已修；横向排查又修了两处：改写过的桩、SwiftThunkAnalysis 的解码器；MachOKit 的同一缺口暂不报上游（A81） | `LinkerOptimizationHintTests`（4 个）、`linkerRewrittenSlotStub`、`aLiteralLoadNamesItsSlot` |
| 2 | `objc_alloc_init` 一类 libobjc 入口不算消息发送 | 高 | 按精简提案修 | `RuntimeSendEntryPointTests`（16 个用例）、`selectorPrefilterKeepsEverySender` 加 `isKindOfClass:` |
| 3 | 目标算得出来的寄存器调用仍记成 `.indirect` | 低 | 不修（A76） | — |
| 4 | 懒绑定的槽位指向 `__stub_helper` | — | 误报（A80） | `LazyBindingTests`，26.6 上也通过 |
| 5 | 没有符号的类型算 key 时，demangle 结果留在按镜像的缓存里 | — | 不修，有意设计（A78）；文档改准 | — |
| 6 | 夹在代码里的数据线性查找 | — | 已裁决（A66），跳过 | — |
| 7 | 映射区间线性查找 | 低 | 不修（A79） | — |
| 8 | 协议打印时多读关联类型名 | — | 已裁决（A71），跳过 | — |
| 9 | 47 位掩码重复六处 | — | 并入 N1 | — |
| 10 | `swiftTypeIdentity` 每次线性走一遍镜像的类 | 低 | 暂不修（A77） | — |
| 11 | 查导入类型时先按 +8 读名字、后判断是不是类型描述符 | 中 | 已修 | `importedTypeQueriesReadNoNameWhereNoTypeDescriptorIs` |
| 12 | 缩写的名字 `pc`、`lhs` / `rhs` | 低 | 已改，全仓库的 `lhs` / `rhs` 一并改；单字母泛型参数暂不改（A82） | `AbbreviatedIdentifierScanTests` |

## N1 — 47 位地址掩码在 iOS 系真机上算错地址

- **问题**：模块从进程内存读指针时，用写死的 `0x0000_7FFF_FFFF_FFFF` 去掉指针认证位：`SwiftTypeIndex.addressMask`、`ObjectiveCClassIndex.addressMask` 两个常量，加上预筛、函数表、扫描器与补充名字里的四处字面量。这是 Mac 的用户地址宽度。XNU 在没有启用大内存配置的设备上把用户地址设为 39 位（`apple_arm64_common.h` 定义 `__ARM64_PMAP_SUBPAGE_L1__`，`proc_reg.h` 据此取 `T0SZ_BOOT = 25`），arm64e 的签名从第 39 位开始，47 位掩码会留下第 39–46 位。受影响的读取：GOT 槽里的函数指针（跨库调用落成 `.unrecognized`，且不退回导入名）、Swift 类元数据 +0x40 与值类型元数据 +8 处的描述符、类列表、`isa`、selector 引用。RuntimeViewer 的 `RuntimeViewerServer` 面向 iphoneos / appletvos / watchos / xros 编译，并无条件装上交叉引用。
- **复现**：真机上没有复现，那需要真机和用户授权；模拟器用 macOS 的地址空间，复现不了。机制从 XNU 源码核实。`AddressMaskScanTests` 扫遍库的源码，找 33 到 62 位宽的地址掩码常量：修复前报出这六处，修复后为零；`theScanDiscriminates` 核对它认得出掩码、不把 32 位掩码与 `Int64.max` 当成掩码。
- **修法**：`InProcessContext` 本来就按平台取 MachOKitExtensions 的 `vmaddrMask`（Mac 与 Mac Catalyst 47 位，其余 arm64 平台 36 位），改为 `package` 可见；交叉引用新加 `StoredPointer.address(in:)` 统一用它，六处都换掉，两个常量删掉。测试里的同类一处也一并换掉。
- **横向排查**：整个 `Sources` 里只有这六处；其余读取都经 `stripPointerTags`，与 `InProcessContext` 同源。`vmaddrMask` 对 iOS 模拟器给 36 位，模拟器进程用的是 Mac 的地址空间，但交叉引用读到的都是镜像里的地址，远低于 64 GiB，不受影响。
- **既往**：`InProcessContext` 早就用按平台的掩码，这个模块新写时没有沿用；开发与测试都只在 macOS 上，所以一直没暴露。

## 1 — ld64 改写出的字面量 `ldr` 与 `adr`

- **问题**：ld64（Xcode 14 及更早，或 Xcode 15、16 加 `-ld_classic`）排好地址后按 linker optimization hint 改写指令：槽位在一兆字节以内的 `adrp` / `ldr` 变成 `nop` / `ldr xN, <槽>`，地址在一兆字节以内的 `adrp` / `add` 变成 `adr xN, <地址>` / `nop`。`ARM64InstructionWord.load(_:)` 不认字面量 `ldr`，载入的 `x1` 成了未知，这次发送被记成对 `objc_msgSend` 的普通调用；类引用只在 `add` 那一步报，`adr` 不报。
- **当初为什么这样做**：提案 0072 与模块文档写着「`adr` 与字面量 `ldr` 两种形态在缓存与几个缓存外的系统 App 里都没有，不解码」。那次只量了 Apple 自己的二进制：Xcode 26 的链接器不做这种改写，本机验证过（同一份源码，默认链接器保留 `adrp` / `ldr`，`-ld_classic` 改写成 `nop` / `ldr`），Apple 的二进制里一处都没有。第三方 App 里却常见：抽查 12 个，2 个有，其中 Asset Catalog Viewer（macOS 12 SDK）有 357 处 selector 引用和 71 处类引用以字面量 `ldr` 载入。
- **横向排查**（同一类：ld64 改写出的形态没人读）：
  1. **改写过的桩**。Asset Catalog Viewer 的 212 个桩全是 `nop` / `ldr x16, <槽>` / `br x16`。MachOKit（0.54.101）的 `StubDecoder` 不认这种形态，给 `.unknown`，函数表于是没有槽位，经桩的调用只剩导入名：这个 App 里经桩调用 `objc_msgSend` 的发送一处也认不出来，光修函数体里的字面量 `ldr` 也没用。修法：`ImageFunctionTable` 在 MachOKit 给不出槽位时用 `ARM64Trampoline` 读桩自己的字节，`ARM64Trampoline` 认字面量 `ldr`。SwiftThunkAnalysis 也经 `ARM64Trampoline` 认桩，一并受益。MachOKit 的 `StubDecoder` 出自上游作者，同样的缺口在上游也有；用户定暂不报上游、也不在 fork 里修（A81）。
  2. **SwiftThunkAnalysis 的 Capstone 解码器**把字面量 `ldr` 当成不建模的指令，载入的值丢失。新增 `ThunkOperation.loadFromSlot`，求值时按槽位读，与 `adrp` / `ldr` 共用一段代码；32 位的 `ldr wN, <label>` 仍不建模。Capstone 把标签记成没有基址寄存器的内存操作数、位移是槽位地址，不是立即数（`adr` 才是）；第一版按立即数认，没有生效，`aLiteralLoadNamesItsSlot` 与 Capstone 对照测试当轮就抓到了。
  3. `__objc_stubs`：本机用 `-ld_classic` 编的样本里 ld64 不改写它，MachOKit 照常读得出 selector 引用。
- **复现**：`LinkerOptimizationHintTests` 现编两个 dylib（Xcode 27 已不带 `ld-classic`，所以照常链接后按 ld64 的做法改写指令、重新签名再加载）：字面量 `ldr` 载入的 selector 认成 `description` 发送、字面量 `ldr` 载入的类与 `adr` 取的类认成类引用、改写过的桩跟到 libsystem_c 的 `puts`。修复前四个测试都失败：发送记成对 `objc_msgSend` 的 `.function`，两处类引用都没有，桩只剩 `.importedSymbol("_puts")`。`ARM64TrampolineTests.linkerRewrittenSlotStub` 修复前得到 `nil`；`CapstoneThunkDecoderTests.aLiteralLoadNamesItsSlot` 修复前得到 `.unmodelled`（修复前跑的版本只断言「不是 `.unmodelled`」，因为新的 case 那时还不存在；修复后加上了精确断言）。解码器的单元测试 `linkerRewrittenAddressesAndLoads` 与 Capstone 对照随修复一起加。
- **修法**：`ARM64InstructionWord.loadLiteral(_:at:)`；`addressMaterialization` 多返回一个 `isPageAddress`，扫描器在 `adr` 处像在 `add` 处一样报类与类型引用；字面量 `ldr` 记成从已知槽位载入（`RegisterFile.load(into:fromSlotAt:)`），载入的偏移记成槽位在页内的偏移，与改写前那对指令记下的相同，于是间接调用的证据也与改写前一致；载入之后的处理（`__objc_superrefs`、类与类型引用）抽成 `noteLoad`，两种载入共用。
- **影响**：只影响用旧工具链链接的第三方二进制，对它们则是从「几乎什么都认不出」到正常。
- **既往**：无；当初是有意不解码，前提只量过 Apple 的二进制。

## 2 — `objc_alloc_init` 一类入口不算消息发送

- **问题**：clang 把 `[[Foo alloc] init]`、`[x isKindOfClass:]` 等编成对 libobjc 专用入口的调用，`ReferenceScanner.functionTarget` 只把 `objc_msgSend` 与 `objc_msgSendSuper2` 当发送。macOS 26.6 的 AppKit：`objc_alloc_init` 2,488 处，按 selector 发送的 `init` 只有 720 处，查 `init` 的调用者漏掉约 78%；`objc_alloc` 4,180、`objc_opt_class` 6,492、`objc_opt_isKindOfClass` 3,369、`objc_opt_respondsToSelector` 2,977、`objc_opt_new` 590，后三者对应的 selector 一次直接发送都没有。第三方 App 也一样：A Better Finder Rename 12 有 380 处 `objc_alloc_init`，按 selector 发送的 `init` 约 217 处。RuntimeViewer 那边也没有补这一层。
- **处理**：会改变查询结果（按函数查这些 C 入口的调用者不再有结果），并有几处取舍（`objc_alloc_init` 记几条发送、`init` 的接收者怎么记、预筛怎么补），按提案制先写精简提案，用户点头后实现：八个入口（`Scanning/MessageSendEntryPoints`）按 libobjc 里的位置认，桩跟不过去时按导入名认，记成 `.messageSend`，接收者按 `x0`；`objc_alloc_init` 在同一条指令上记 `alloc` 与 `init`，`init` 的接收者记 `.unknown`；这些调用不再同时记成对 C 函数的调用；`objc_opt_self` / `objc_opt_class` 之后 `x0` 照旧保留；selector 预筛另外留下导入或定义对应入口的镜像。`objc_retain` 一类不认。
- **复现**：`RuntimeSendEntryPointTests` 现编一个 dylib，八个入口各调用一处（本机先核对过 clang 确实用了这八个入口，且 dylib 里一个 selector 引用都没有）。修复前八处都是对 libobjc 函数的 `.function`，八个 selector 的预筛都把这个镜像丢掉。整个缓存上，`selectorPrefilterKeepsEverySender` 加了 `isKindOfClass:`：预筛丢掉的镜像里抽样扫描，一处这个发送也不许有。
- **既往**：没有。提案 0072 只把 `objc_opt_self`、`objc_opt_class` 当成「原样返回传入的类」，用来认类字面量接收者。

## 11 — 查导入类型时先读名字、后判断类型

- **问题**：查 `So…` / `SC…` 开头的导入类型（`CGRect`）时，`SwiftTypeQuery.matchesDescriptor(at:)` 先用 `SwiftTypeIndex.name(ofDescriptorAt:)` 按描述符 +8 处的相对指针读名字、`strcmp`，之后才算 key。传进来的位置可能来自 mangled 名字里的符号引用，它指向任何上下文描述符；不透明类型（`some View`）的描述符在 +8 放的是泛型头，参数个数与约束个数读成偏移，每个约束约 64 KiB。大镜像里只是白读；小的缓存外镜像可能读出镜像之外，在宿主进程里崩溃——RuntimeViewer 是注入运行的，崩的是被查看的 App。
- **复现**：`importedTypeQueriesReadNoNameWhereNoTypeDescriptorIs` 在子进程里造一个假的不透明类型描述符，放在可读页的末尾，后面全是不可读的页，拿 SwiftUICore 里的 `CGRect` 去比它。修复前子进程以 SIGBUS 结束。
- **修法**：`SwiftTypeIndex.name(ofDescriptorAt:)` 先看标志位低五位的种类，只有类型描述符（16–31）才读 +8。审查原本建议在 `matchesDescriptor` 里先查 `describesType`，但那要为扫到的每个镜像建一份类型索引，并由分析器留到它被释放；种类检查只读四个字节，也把这个函数的另外两个调用方一起护住。
- **横向排查**：`name(ofDescriptorAt:)` 的另外两个调用方（按名字筛类型、建查询时读被查类型的名字）拿到的本来就是类型描述符；改在函数本身之后，以后的调用方也不会再踩。
- **既往**：无。

## 12 — 缩写的名字

- `ReferenceScanner` 里 37 行用 `pc` 指当前指令的地址，改成 `instructionAddress`，与公开模型 `CodeReference.instructionAddress` 同名。`lhs` / `rhs` 不只本模块：`Sources` 下 17 个文件（含测试支持模块）、`Tests` 下 1 个文件，`==`、`<`、数组的 `+` 与排序闭包的参数改成 `left` / `right`，`AddressArithmetic` 的运算符要求按文档注释改成 `address` / `offset`、`end` / `start`，测试里重复字符串的 `*` 改成 `repeated` / `count`。都是参数的内部名字，不涉及调用方。
- 不动 `Tests/Projects` 下的 fixture 源码：它的 `test(lhs:rhs:)` 是参数标签，进了 fixture 二进制的符号与快照基线。
- `AbbreviatedIdentifierScanTests` 扫 `Sources` 与 `Tests`，修复前报出全部这些行。
- 同类但不在这次范围里的：单字母的泛型参数，库里约 167 处、测试里约 126 处（部分在字符串里），用户定暂不安排清理（A82）。
- **既往**：`4e8f4a7f`（2026-10-08）清理过特化器新代码里的缩写，这个模块写在那之后，没有跟上。

## 不修与误报

见 ReviewAdjudications：A76（第 3 条）、A77（第 10 条）、A78（第 5 条）、A79（第 7 条）、A80（第 4 条）、A81（第 1 条横向排查到的 MachOKit 桩解码缺口）、A82（第 12 条同类的单字母泛型参数）。

另：已暂缓的 A64（缓存构建器优化成直接跳转的桩）当初因为手头没有 macOS 26 的机器才暂缓，这次在 26.6 上核过：AppKit、Foundation、SwiftUI、libswiftCore 的 `__auth_stubs` 全是经槽位的形态，没有直接跳转型，仍复现不了，继续暂缓（条目已补记）。
