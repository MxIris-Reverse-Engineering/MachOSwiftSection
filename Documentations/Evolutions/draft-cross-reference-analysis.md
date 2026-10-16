# Draft - 交叉引用分析：从机器码读出每个函数引用了什么

- **状态**: In Progress
- **创建日期**: 2026-10-16
- **最后更新**: 2026-10-16
- **关联**: RuntimeViewer 的 [draft-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/feature/cross-references/Documentations/Evolutions/draft-cross-references.md)。交叉引用的整体设计、前期调研与实测数据都在那里，本提案只定本库这一层。

## 摘要

新增 public target `CrossReferenceAnalysis`（`Sources/Analysis/CrossReferenceAnalysis`）：给出一个镜像的函数表，以及每个函数引用了什么——直接调用与尾调用、ObjC 消息发送、super 发送、跨库调用、类型引用、间接调用及其候选目标。RuntimeViewer 的交叉引用（调用者、被调、类型引用）建在它上面。规则放在本库，沿用「二进制分析的规则放在 MachOSwiftSection，RuntimeViewer 只负责显示」的做法。

## 方案

- **读取**：只读进程内的 `MachOImage`，只支持 arm64 / arm64e。`MachOFile` 与 swift-section 子命令留给以后的提案。
- **函数表**：边界取自 `LC_FUNCTION_STARTS`（MachOKit 在内存镜像上给出的 `FunctionStart.offset` 已经是未滑动的绝对地址，与它的文档注释不符）。名字依次取自符号表、ObjC 方法表（`ObjCClassMethodIndex`）、Swift 方法描述符的实现（`implementationSymbols`）；同一地址上的多个名字（代码合并）归为一个函数；都叫不出名字时 `name` 为 `nil`，照样扫描。
- **解码**：手写，只认调用、尾调用、间接调用、`adrp` / `add` / `ldr` 取地址、`movk` / `mov` 鉴别常量、`autda` / `ldraa` 这几类，其余指令只作废它写的寄存器。实测比 Capstone 快 25–50 倍，Capstone 只在测试里作对照。`__text` 里夹着数据，读任何跳转目标之前先确认它落在缓存的可执行映射或本镜像里。
- **调用目标**：镜像自带的 `__objc_stubs` / `__stubs` / `__auth_stubs`（macOS 26、iOS 26 及更早，以及 Simulator）；macOS 27 / iOS 27 全缓存共用的 selector 桩（`x1` 就是 selector 字符串，以字符串地址为键）与 GOT 桩（进程内读出槽位里已绑定的指针）；stub island。GOT 桩与 island 的形状识别和 `MachOThunkEnvironment` 共用一份：把它的 `stubSlotAddress` / `stubIslandTarget` 抽成两边都能调用的 package 级纯函数。
- **间接调用**：按 `autda` 的常量分出虚表（isa，0x6ae1）、value witness table（0x2e3f）与协议见证表；value witness 调用标为运行时辅助调用。虚表与见证表调用按（鉴别常量、表内偏移）反查本镜像的根声明：常量是带 `$s` 前缀的 `SILDeclRef` mangling 经 `getPointerAuthStableSipHash` 再取 `% 0xFFFF + 1`。闭包调用只给签名形态。
- **类型引用**：`$s…Ma` 元数据访问器、`__swift_instantiateConcreteTypeFromMangledName*` / `swift_getTypeByMangledName*`（名字取自 `x0` 指向的缓存变量）、ObjC 类引用。
- **运行时辅助调用**：名单由本库维护，结果里只打标记，过滤交给宿主。
- **预筛**：按符号表的未定义符号与 `__objc_selrefs`，筛出可能引用某个符号或 selector 的镜像。
- **不缓存**：每次调用都重新读；整镜像扫描返回一个值，留多久由宿主决定（RuntimeViewer 按字节预算做 LRU），所以不新增 `SharedCache`。
- **分三批落地**，每批单独可用：① 函数表（符号表与函数起点）、解码、两种桩布局、selector、辅助调用标记、单函数与整镜像 API、预筛，发一个版本后 RuntimeViewer 就能开始它的第 3 步；② ObjC 方法表与 Swift 元数据命名、类型引用；③ 间接调用的表来源、鉴别常量反查与候选。
- **测试**：解码器用合成的指令字单测；SymbolTestsCore fixture（arm64）测函数表与直接调用；arm64e 才有的形状用自编的 arm64e 目标文件和进程内的系统缓存测，并以 Capstone 的反汇编作对照。

第一批落地的 API。草图原是一组接收 `MachOImage` 的静态函数；实现时发现跨镜像解析目标要用到整个进程的镜像表，改成一个由宿主持有的分析器：

```swift
public final class CrossReferenceAnalyzer: @unchecked Sendable {
    /// The current process's images — the whole shared cache plus the images loaded outside it; nil off arm64.
    public init?()
    public let images: [MachOImage]
    public let imagePaths: [String]
    public func imageIndex(forPath path: String) -> Int?
    public func location(ofRuntimeAddress address: UInt) -> CodeLocation?
    public func functions(inImageAt imageIndex: Int) -> [CodeFunction]
    public func function(containing location: CodeLocation) -> CodeFunction?
    /// Names many results at once without keeping the images' tables.
    public func functions(containing locations: some Sequence<CodeLocation>) -> [CodeLocation: CodeFunction]
    public func symbolName(at location: CodeLocation) -> String?
    public func references(madeBy function: CodeFunction) -> [CodeReference]
    /// Every function's references in one image, grouped by what they reference.
    public func referenceTable(ofImageAt imageIndex: Int) -> CodeReferenceTable
    /// Only the references filed under `keys` — what a callers query needs.
    public func references(to keys: Set<CodeReferenceTable.Key>, inImageAt imageIndex: Int) -> [CodeReference]
    public func imageIndices(importing symbolName: String, among candidates: some Sequence<Int>) -> [Int]
    public func imageIndices(referencingSelector selector: String, among candidates: some Sequence<Int>) -> [Int]
}
```

地址一律是 `CodeLocation`（镜像在 `images` 里的位置，加该镜像的未滑动地址），因为缓存外两个镜像的未滑动地址可能重合。实现细节见 [Modules/CrossReferenceAnalysis.md](../Internal/Modules/CrossReferenceAnalysis.md)。

## 第一批的实现与验证（2026-10-16）

- **落地模块**：新 target `ARM64InstructionDecoding`（`Sources/Support`：`ARM64InstructionWord` 手写读取少数几类编码，`ARM64Trampoline` 按形状认 GOT 桩、stub island 与全缓存共用的 selector 桩）；新 target `CrossReferenceAnalysis`（`Sources/Analysis`）；SwiftThunkAnalysis 的 `MachOThunkEnvironment.stubSlotAddress` / `stubIslandTarget` 改用 `ARM64Trampoline`，此前用 Capstone 加寄存器跟踪认同样的形状。
- **与方案的出入**：①API 改成宿主持有的 `CrossReferenceAnalyzer`（上文）。②分析器只记住宿主让它起过名的镜像的函数表；这不是全局的按镜像缓存，释放分析器即释放，所以仍不需要 `SharedCache`。③ObjC 方法的 `x0` 接收者提示（`methodReceiver`）这批就做了：寄存器跟踪本来就在，代价只是多一个状态。④新增 `references(to:inImageAt:)`（见下「内存」）。
- **内存**（用库写的 release 基准量）：整镜像扫描起初也记住函数表，扫完一遍 macOS 27.2 缓存后常驻 1.5 GB，改为扫描临时建表、用完即丢（`wholeImageScansKeepNoFunctionTable`，改前红、改后绿）。剩下的 1.2 GB 不是活对象（`heap` 只见一两 MB），是 28 个线程同时建整表（大镜像一张 121 MiB）后分配器没还的脏页，由峰值决定；查调用者改用只留命中引用的 `references(to:inImageAt:)` 后，同样扫完全缓存常驻约 170 MB。
- **吞吐**：建分析器 0.02 秒；每个镜像都建整表 28 核 1.6–1.8 秒、4 线程 5.9 秒；`init` 的调用者（预筛出 2,759 个镜像）28 核 1.5 秒、4 线程 6.1 秒；`makeKeyAndOrderFront:`（105 个镜像）0.3 秒。比探针慢的部分是起名与建引用，见模块参考。
- **懒绑定**：曾以为懒绑定的老式二进制在函数第一次调用前槽位指向 `__stub_helper`，加了退回导入名的防护和测试；测试在去掉防护后照样通过。用探针看：macOS 27.2 的 dyld 以 `RTLD_LAZY` 加载时就绑好了槽。防护是死代码，撤掉；测试改成哨兵 `LazyBindingTests`，断言调用直接解析到 `puts`。
- **验证**（JHs-Mac-Studio-Ultra，macOS 27.2，Xcode 27.2，依赖全部走远端发布版本）：`CrossReferenceAnalysisTests` 20 个测试通过，其中 `callSitesMatchCapstone` 抽样 AppKit 的 400 个函数，Capstone 找到的每一处调用与跳出函数的跳转，扫描都找到了；`SwiftThunkAnalysisTests` 82 个测试通过，包括经 stub island 解析的两个离线 iOS 缓存测试；全量 `swift test --skip IntegrationTests` 见演进账本本批一节。
- **第一次测试的教训**：Capstone 不开 detail 模式就不给操作数，按位置取操作数会越界；比对「跳出函数的跳转」那半边因此一度什么都没比。测试现在断言这半边比对过不止一处。
- **留给后续批次**：过滤扫描按键提前跳过（现在先建好每条引用再丢）；`CodeReference` 的紧凑存储。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-16 | Created as Draft | RuntimeViewer 提案落地第二步要求先写本库的提案；整体方向用户已在那份提案里确认 |
| 2026-10-16 | 采用的假设 | 只读 `MachOImage`；target 名 `CrossReferenceAnalysis`；不新增缓存；分三批落地；GOT 桩与 island 的识别与 SwiftThunkAnalysis 共用 |
| 2026-10-16 | 状态 → Accepted → In Progress | 用户批准按本方案动手（「可以，开始第一批」），跳板识别从 SwiftThunkAnalysis 抽出共用；开始第一批 |
| 2026-10-16 | API 改为宿主持有的 `CrossReferenceAnalyzer`，位置用 `CodeLocation` | 跨镜像解析目标要整张进程镜像表；缓存外两个镜像的未滑动地址可能重合 |
| 2026-10-16 | 整镜像扫描不记函数表；新增只留命中引用的 `references(to:inImageAt:)` | 实测：记表时扫完全缓存常驻 1.5 GB；整表并发扫描的峰值让分配器留下 1.2 GB；过滤扫描后约 170 MB |
| 2026-10-16 | 不做懒绑定退回，留哨兵测试 | 探针实测 dyld 加载时就绑好懒绑定槽，防护是死代码 |
