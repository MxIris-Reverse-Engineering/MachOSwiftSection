# CodeAddressResolution

从 Mach-O 文件里离线读出「一次调用最终落到哪」所需的几样东西：一个镜像的地址空间（`ImageAddressSpace`）、调用途经的跳板链（`StubChainResolver`）、任意指针槽里装着谁（`SlotResolver`），以及 dyld shared cache 里某个地址属于哪个镜像（`CacheImageLocator`）。不认识 Swift、ObjC 的任何元数据。

- 提案：[draft-offline-cross-references-and-symbolication](../../Evolutions/draft-offline-cross-references-and-symbolication.md) 第 3 步从 `SwiftThunkAnalysis` 抽出。原来 `ThunkAddressSpace`、`CacheImageResolver` 与 `MachOThunkEnvironment` 里的桩链和槽解析都在那里，只给 accessor thunk 读取用；交叉引用的文件模式（第 4 步）也要同样的东西，于是抽成两边共用的模块。
- 依赖：MachOKit、MachOKitExtensions、`MachOReading`（`MachOFile.readElements`）、`ARM64InstructionDecoding`（跳板形状）。不是 library product，接口都是 `package` 级。
- 用到它的：`SwiftThunkAnalysis`（`MachOThunkEnvironment` 经它读槽、读桩、找 cache 镜像）、`SwiftDeclarationRendering`（导出表偏移换地址），第 4 步起还有 `CrossReferenceCore` 的文件模式。
- 将来的落脚处：MachOKitExtensions，改名 `MachOAddressResolution`，随交叉引用核心层一起迁（迁移提案另写）。

## 四个类型

| 类型 | 做什么 | 原来在哪 |
|---|---|---|
| `ImageAddressSpace` | 本库的 offset 与虚拟地址互换；段范围判断「在不在本镜像」；符号表的 `n_value`、导出表的相对 mach header 偏移各自换成地址 | `SwiftThunkAnalysis` 的 `ThunkAddressSpace` |
| `CacheImageLocator` | cache 里按地址找镜像（按 `imageInfos` 的加载地址二分），按路径懒打开并保留；镜像导出表里某个地址是哪个名字 | `SwiftThunkAnalysis` 的 `CacheImageResolver` |
| `StubChainResolver` | 读一个地址上的跳板（GOT 桩、ld64 改写的桩、stub island、27 的 cache 共用 selector 桩），给出这一跳（`Hop`）；或者从一个地址起一路跟到终点，记下每一跳 | `MachOThunkEnvironment` 的 `trampoline(at:)` 一族 |
| `SlotResolver` | 任意指针槽里装着谁：bind 给符号名，rebase 给未滑动的目标地址。GOT、auth GOT、ObjC 的各类引用槽、ivar 偏移变量共用，哪个节算哪种槽由调用方说 | `MachOThunkEnvironment` 的 `pointer(at:)` 与 `slotSymbolName(at:)` 里的解码 |

## 关键契约

- **地址的口径**：cache 镜像的 offset 是「未滑动虚拟地址减 `sharedRegionStart`」，不是文件偏移；另外三种口径看着能用却会算出邻居镜像里的地址。来龙去脉写在 `ImageAddressSpace` 的文档注释里，也见 [SwiftThunkAnalysis](SwiftThunkAnalysis.md)「偏移口径」一节。cache 镜像的 offset 换算对整个 cache 都答得出，「在不在本镜像」只能用 `containsAddress(_:)` 的段范围判断。
- **导出表的偏移相对 mach header**：一律经 `address(forExportedSymbolOffset:)` 换算，dylib、可执行文件、cache 镜像通用。
- **槽先看 bind 再看 rebase**：独立文件的导入是 bind，给的是名字；`MachOKitExtensions.resolveRebase(fileOffset:)` 对 cache 镜像答的是「目标减 `sharedRegionStart`」、对独立文件答的是目标地址本身，`SlotResolver` 统一换成未滑动地址。独立文件里绑到自己导出符号的 bind（self-bind）在这里也只是名字，换成地址是交叉引用文件模式的事。
- **跳板按形状认，载入之后必须紧跟经同一寄存器的跳转**：开头是 `adrp; ldr` 的普通函数（读一个 Swift 字段偏移的 getter 就是）在前两条指令上和 GOT 桩一模一样。`ARM64Trampoline` 原先读到 `ldr` 就认定是桩，iOS 26.3.1 设备 cache 里一条经 stub island 到达 UIKitCore `UIHostingViewBase.viewGraph` getter 的调用因此被读成「从字段偏移变量里取目标」，落到 `sharedRegionStart + 0x38`。第 3 步修掉，回归测试 `ARM64TrampolineTests.aFunctionLoadingAGlobalIsNoSlotStub`。进程内的扫描器只对不落在任何镜像里的地址认跳板，所以不受这个 bug 影响；线程读取器在调用目标落在别的镜像、又不是 accessor 或运行时入口时会走到它，得出的是 `unknown`，结果也没变。
- **链的长度有上限**：`StubChainResolver.maximumHops` 是 8（一般一跳，每跨一个 subcache 多一跳）。`hops(from:isDestination:followSlot:)` 的 `isDestination` 让调用方在已知的函数起点停下，`followSlot` 由调用方决定怎么解一个槽（文件里用 `SlotResolver`）。cache 共用的 selector 桩是链的终点：它把 selector 字符串的地址放进 `x1`，`Hop.registerSettingStub` 记下寄存器号与常量，这个常量是 selector 由 ObjC 层解释，本模块不认识 selector。
- **自己不做按镜像缓存**：`CacheImageLocator` 内部用一把锁保护已打开镜像与导出名表；按镜像共用一个 locator 是调用方的事——线程读取器把它放在 `thunkResolution` 组的 `SharedCache` 里（`MachOThunkEnvironment.cacheImageLocator(cacheOf:)`），本模块因此不依赖 `MachOCaches`，将来能原样搬走。

## 测试锚点

- `CodeAddressResolutionTests`（只在带 dyld shared cache 的 arm64 进程里跑，拿进程里 dyld 已经 rebase、bind 过的内容当标准答案）：
  - `stubChainCarriesTheSelectorRegisterConstantOfACacheSharedSelectorStub`：AppKit 文件里经 cache 共用 selector 桩的调用，`x1` 的常量读出的 selector 与进程内同一条指令上记下的发送一致（核对 50 处）。
  - `stubChainRecordsEveryStubIslandHop`：iOS 26.3.1 设备 cache 的 SwiftUI，经 stub island 的调用一百条以上，每一跳都从上一跳的终点开始，链停在不是跳板、落在某个镜像里的地址上。卷上没有这个 cache 时跳过。上面那个跳板误认的 bug 就是它发现的。
  - `slotResolverMatchesTheProcessForEveryGlobalOffsetTableSlotOfAppKit`：AppKit 的每个 GOT 与 auth GOT 槽，文件里解出的目标等于进程里的指针去掉签名、减去 slide；其中有指向 AppKit 自己的（类对象）。
  - `slotResolverResolvesStandaloneBinds`：SymbolTestsCore fixture 的 GOT 是按名字绑到 Swift 运行时与 Foundation 的 bind。
  - `cacheImageLocatorFindsTheImageAnAddressLiesIn`：AppKit 与 libobjc 的 `__TEXT` 里的地址找回各自的镜像。
- `SwiftThunkAnalysisTests` 全套守着抽取前后线程读取的结果不变：归档的 iOS 设备 cache（stub island）、归档的 macOS cache（合并 accessor）、模拟器运行时、独立文件。
