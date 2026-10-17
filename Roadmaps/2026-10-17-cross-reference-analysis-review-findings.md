# 交叉引用分析审查记录（`feature/cross-reference-analysis`，2026-10-17）

审查对象：`feature/cross-reference-analysis` 相对 `0.23.0`（`b7be58ec`）的全部提交（`0c0ebce3` … `c2cefa9c`），即提案 [draft-cross-reference-analysis](../Documentations/Evolutions/draft-cross-reference-analysis.md) 的第一、二批。同一轮也审了 RuntimeViewer 的 `feature/cross-references`，那边的条目（编号 C 开头的大部分、D1、D4、D10–D13）记在 RuntimeViewer 的 `Documentations/KnownIssues/2026-10-17-cross-references-review-findings.md`。

**方式**：四个子代理按模块并行通读（只读），交回 47 条候选，去掉重复 43 条（两个仓库合计）；每条都由本人回到代码复核，能造出复现的造复现。编号沿用审查时的分组：A 扫描与寄存器跟踪，B 分析器与预筛，C RuntimeViewer 引擎侧，D 测试与文档，N 公开接口的小毛病。

**四问的共同答案**：本模块是这个分支新写的，`0.23.0` / `main` 上没有；GitHub 上没有相关 PR 或 issue；[ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md) 在这一轮之前没有覆盖这些发现的条目。所以每条都是「本分支引入、以前没修过」，例外写在各条的「既往」里。

**状态**：用户 2026-10-17 批准按建议修。修了的每条都先写了修复前失败的测试（修前修后的实测写在各条），判为不修或误报的登记在 ReviewAdjudications A62–A67。A5（循环与跳转表）按约定先量数据给用户定修法，数据见该条。修复过程中机器死过一次（同时跑 release 全量构建与两套测试），之后重任务一次只跑一个。

## 总表

| # | 问题 | 严重度 | 处理 | 测试 |
|---|---|---|---|---|
| A1 | 带回写的读写、原子指令、寄存器对与 `casp` 的第二个寄存器、`umov` / `smov`、定点转换、SVE / SME、`sysl`、`svc` 写了寄存器却没作废 | 中 | 已修；SwiftThunkAnalysis 的同类两处一并修 | `RegisterFileTests`、`ThunkRegisterTrackerTests`、`ThunkTypeEvaluatorTests.aWriteBackPairMovesItsBase` |
| A4 | `XPAC` 的注释说保留寄存器，代码其实作废 | 低 | 已改注释 | —（行为不变） |
| A5 | 循环头与跳转表落点保留 `x19`–`x28` 的旧值 | 中 | 量了：错 0.02%–0.04% 的引用，精确修法多花 35%–60% 时间；待用户定 | 见该条 |
| A6 | 待到目标的排序插入、夹在代码里的数据线性查找 | 低（性能） | 量了，不修（A66） | — |
| A7 | 直接跳转型的桩不跟；槽位指向不认识的地址时不退回导入名 | 低 | 暂缓：本机无法复现（A64） | — |
| A8 | `bc.cond` 不解码；共用 selector 桩读字符串前不检查；`svc` 不作废 `x0` / `x1` | 低 | `svc` 并入 A1 修；其余不修（A65） | `RegisterFileTests` 的 `svc` 用例 |
| B1 | 被别的镜像改名再导出的 C 函数与类，跨库查调用者时漏掉按新名字导入的镜像 | 高 | 已修 | `RenamedReexportTests` |
| B2 | 类型查询里的 demangle 结果钉进进程级缓存，永不淘汰 | 中 | 已修 | `TypeNameRetentionTests` |
| B3 | 缓存外的镜像以安装名为路径：主程序与 bundle 是空串，框架是 `@rpath/…` | 高 | 已修 | `StandaloneImageTests` 新增三个 |
| B4 | `-bundle_loader` 的插件不算主程序的依赖方；同一安装名的两份拷贝只认第一份 | 低 | 随 B3 修 | `aBundleCountsAsLinkingTheMainExecutable` |
| B5 | 分析器存活期间缓存外镜像被卸载，会读到已释放的内存 | 低 | 不修，文档写明（A63） | — |
| B6 | `approximateByteCount` 不算字符串 | 低 | 补文档；RuntimeViewer 侧判为误报 | — |
| B7 | 按镜像的缓存用手写锁加字典，不用 `SharedCache` | — | 不修，有意设计（A62） | — |
| N1 | `swiftTypeDescriptorLocations` 承诺「一个或没有」，回退路径可能多个、顺序不定 | 低 | 已改文档 | — |
| N2 | `CodeReferenceTable.keys` 暴露 `Dictionary.Keys` | 低 | 改为 `some Collection<Key>` | 编译 |
| D2 | 类型名查询测试里四个标准库类型与被测代码同一套解开，等于没测 | 低 | 已改测试与模块文档的说法 | — |
| D3 | 与 Capstone 的对照只查「扫描没漏」，注释说「一处不多」 | 低 | 改成双向对照 | `callSitesMatchCapstone` |
| D5 | super 发送的类测试分辨不出类来自 `__objc_superrefs` 还是方法符号 | 低 | 补一个只有槽位能通过的测试（经变异验证） | `superSendsInBlocksNameTheClassOfTheirMethod` |
| D6 | 测试注释说「换系统版本不影响成立」，部分断言钉的是 macOS 27.2 的代码 | 低 | 改注释；不按系统版本门控（A67） | — |
| D8 | AGENTS.md 说「只为起名用元数据、从不用于扫描」「整个缓存约一秒扫完」，引用种类缺类与类型 | 中 | 已改 | — |
| D9、D14–D17 | 提案与模块文档的数字对不上、方案一节过时、内存说法缺了索引、镜像数差一 | 低 | 已改 | — |

## A1 — 写了寄存器却没作废的指令

- **问题**：扫描器的规矩是「不建模的指令写了哪个寄存器就忘掉它」。`RegisterFile.forgetRegistersWritten(by:)` 漏了：前 / 后变址的单寄存器与寄存器对读写会把基址寄存器改掉（`ldr x9, [x8], #16` 之后 `x8` 加了 16）；SIMD 与浮点的读写在入口就返回，连它们的基址回写也一起漏掉；不带内存序的原子指令（`ldadd`、`swp`，位 23–22 为 00）被当成存储；`ldxp` 的第二个寄存器、`casp` 的 `Rs+1`；从向量寄存器取值的 `umov` / `smov`；浮点转定点的 `fcvtzs xd, dn, #fbits`；SVE / SME 里写通用寄存器的几条（`cntd`、`addvl`、`rdvl`、`rdsvl`）；`sysl`；系统调用 `svc`（结果在 `x0`、`x1`）。
- **复现**：`RegisterFileTests.forgetsEveryRegisterAnInstructionWrites`，48 条汇编器编出的指令，每条给出架构写的寄存器。修复前 34 个用例失败（`svc` 后补，单独确认过失败）。`capstoneNamesNoOtherWrittenRegister` 用 Capstone 的寄存器访问表独立核对这张表没有漏项；Capstone 把 `cas` / `casp` 的基址也算成被写，架构上并不写，测试里列为已知偏差。`aPlainAccessForgetsOnlyWhatItLoads` 钉住普通读写只作废目标寄存器，不多忘。
- **修法**：判断改写成纯函数 `RegisterFile.registersWritten(by:)`，返回位掩码（调用返回调用方保存的寄存器），`forgetRegistersWritten(by:)` 按掩码作废。按 A64 读写编码的分组（位 29–28）逐类判断，未分配或不常见的形态一律多忘。
- **影响**：只会让扫描多忘，原本正确的结果不会丢。全缓存里这些形态多在 `memcpy` 一类循环和原子操作里，影响了多少结果没有单独量。
- **横向排查**：SwiftThunkAnalysis 有自己的寄存器跟踪。`ThunkRegisterTracker` 对带回写的寄存器对不作废基址（`ObjCMethodThunkReferences` 用它找 thunk 引用的地址）；`ThunkTypeEvaluator` 只在基址是 `sp` 时作废（经 `forgetStack()`）。两处都改为作废基址。修前 `ThunkRegisterTrackerTests.aWriteBackPairForgetsItsBase` 与 `aWriteBackPairMovesItsBase`（读与写两半各自确认过）失败。单寄存器的回写这边本来就对：Capstone 的写入表里带着基址。
- **既往**：`forgetRegistersWritten` 出自 `0c0ebce3`，之后没改过；SwiftThunkAnalysis 的两处出自 `09c08453`（2026-09-12），thunk 里成对回写只用在 `sp` 上，所以一直没暴露。

## A4 — `XPAC` 的注释

- 注释说「PAC、AUT、XPAC 原样保留寄存器」，掩码 `0xFFFF_C000` 却只覆盖 opcode 位 13–10，`XPACI` / `XPACD`（位 14 置位）实际被作废。作废是保守的，只改注释：PAC 与 AUT 原地签名或认证、含义不变，保留；XPAC 作废。

## A5 — 循环头与跳转表落点保留 `x19`–`x28`

- **问题**：分支跟踪（`00c5a040`）在循环头（向后分支的目标）与跳转表落点（无条件转移之后、没有向前分支指向的指令）只作废调用方保存的 `x0`–`x18`。`x19`–`x28` 留下的是文本上前一块末尾的值：循环体里改了 `x22`、跳回循环头，扫描器仍以为 `x22` 是进循环前的值；switch 的某个 case 改了 `x20` 后跳走，下一个 case 拿到的是它留下的值。
- **当初为什么这样做**：提案给循环头的理由是「回边的状态此时还不知道」——这个理由对 `x19`–`x28` 同样成立，文档没有说为什么保留它们，判断是疏漏。
- **测量方法**：一个临时的测量测试（量完已删，代码另存），对同一批函数用几种做法各扫一遍，逐函数比较报出的引用。范围：六个大镜像（AppKit、Foundation、CoreFoundation、SwiftUICore、libobjc、Mac Catalyst 的 UIKitCore，共 3,317,645 条引用），以及缓存里每 16 个取 1 个（257 个镜像，7,105,278 条）。做法：
  1. 全部作废：循环头与没人指向的落点忘掉所有寄存器。
  2. 精确：含循环的函数反复扫，循环头与上一遍回边带回的状态取交集，直到回边的状态不再变化（第一遍乐观；平均每个含循环的函数扫 2.1 遍，8 遍封顶，全部样本里只有 1 个函数没收敛）。按构造，它与现行做法的每一处差异都是现行做法在本模型下错了或漏了。
  3. 精确，外加跳转表：跳转表的 `br` 之后、没人指向的落点取 `br` 那一刻的状态。
- **结果**（release，单线程，扫描时间是这批镜像的合计）：

  | 做法 | 六个大镜像：改变的引用 | 257 个镜像：改变的引用 | 扫描时间（六个 / 257 个） |
  |---|---|---|---|
  | 现行 | — | — | 1.15 s / 3.26 s |
  | 全部作废 | 约 3.9 万：`self` 发送少 30,390，类引用少 4,425，类字面量发送少 3,062 | 约 1.5 万：`self` 发送少 7,666，类引用少 4,415 | 0.91 s / 2.52 s |
  | 精确 | 1,203 条变了或没了、1,175 条新出现（0.04%）：`self` 发送 −665 / +62，类字面量发送 −36 / +123，间接调用的表内偏移 −259 / +189 | 1,584 / 1,771（0.02%）：间接调用 −1,080 / +1,196，类引用 −7 / +192，`self` 发送 −152 / +23 | 1.63 s / 5.26 s（+42% / +61%） |
  | 精确外加跳转表 | 约 1,360 / 1,325 | 约 2,000 / 2,220 | 1.54 s / 5.01 s |

- **抽查**：`-[NSMenuItem _titlePathForUserKeyEquivalents]` 是典型：`x22` 先是 `self`，循环体把它换成父菜单项（`ldr x22, [x8, x26, lsl #3]`）再跳回，循环头之后的 `_titleForUserKeyEquivalents` 发送现行做法说「发给 self」，精确做法说「接收者未知」。
- **试过、弃用的近似**：只作废「循环区间里写过的寄存器」的几种写法（按合并后的区间、按循环头、排除不能回到回边的块、排除异常落点），每一版都还会丢掉正确的事实：`@synchronized` 的异常落点 `mov x19, x0` 写进了共享的解锁代码，循环前一次性 `adrp` 出的页地址被算进循环的写集合，等等。所以只留精确做法作为候选。
- **值不值得修**：现行做法错的只占引用的 0.02%–0.04%，几乎都是循环里发送的接收者提示（「确定」与「按 selector」之间，极少数情况会把真实的调用者按类排除掉）；精确做法要多花 35%–60% 的扫描时间。
- **处理**：待用户定（选项与建议见给用户的汇报）。

## A6 — 待到目标的排序插入、夹在代码里的数据线性查找

- **问题**：`carry(to:)` 把向前分支的目标与约 640 字节的快照插进按地址排序的数组，近处的分支插在一长串远处目标前面时要整体搬动；`isInDataInCode` 对每条指令线性查一遍数据区间。
- **测量**（release，同一个临时测量测试）：
  - 数据区间：抽样的 257 个缓存镜像里一条都没有（缓存镜像的 `LC_DATA_IN_CODE` 是空的），线性查找实际不发生。
  - 排序插入：向前目标最多的函数确实更慢。WebCore 平均每条指令 51 ns，`FormatConverter::convert`（5,529 个向前目标、9.3 万条指令）270 ns，扫一遍 25 ms；JavaScriptCore 平均 84 ns，`FTL::LowerDFGToB3::compileNode`（6,745 个目标）718 ns、61 ms；AppKit 里目标最多的函数只有一百多个，看不出差别。JavaScriptCore 目标最多的三个函数合计约 100 ms，占这个镜像扫描时间的 13% 左右；WebCore 的前三个约占 8%。
- **值不值得修**：慢只在少数巨型函数上，每个几十毫秒，跨库查询是 27 个线程并发扫几千个镜像，这几个函数不在关键路径上。
- **处理**：不修，登记 A66。若采用 A5 的精确做法（含循环的函数要扫两遍），或有用户在具体镜像上感到慢，再按审查建议的修法（排序数组只存 16 字节的「目标、快照序号」，快照另放一个只追加的数组）重议。

## A7 — 直接跳转型的桩、认不出目标的槽位

- **问题**：`ImageFunctionTable` 只收 `Stub.Branch.viaSlot` 的桩。MachOKit 把缓存构建器优化过的桩（单条 `b target`，或 `adrp x16; add x16; br x16`）读成 `.direct(target)`，这种桩的槽位为空，调用于是退回桩的导入名（`.importedSymbol`），拿不到目标函数。另外，槽位读出的指针落在所有镜像之外时，解析返回 `.unrecognized`，挡住了退回导入名。
- **复现 / 是否误报**：本机复现不了。macOS 27.2 的缓存镜像已经没有桩（AppKit、libswiftCore、libsystem_c、Foundation、libobjc 的 `__auth_stubs` / `__stubs` 都是 0 字节），缓存外镜像的桩都经槽位，dyld 加载时就绑好；槽位指向镜像之外只发生在被 interpose 到非镜像内存之类的情况。`.direct` 桩真实存在于 macOS / iOS 26 及更早的缓存里——引擎在被查看的进程里扫，用户在这些系统上用时会遇到：调用按导入名报，按名字查调用者仍能找到，按位置的不行，改名再导出（B1）的别名也对不上。
- **处理**：暂缓，登记 A64。规则要求修复带修复前失败的测试，本机造不出；等有 26.x 环境（另一台机器或经批准的模拟器）时补测试再修。

## A8 — 三处小缺口

- `bc.cond`（FEAT_HBC，位 4 置位）不解码：Apple 的核心没有实现这个扩展，编译器不会生成。不修。
- 共用 selector 桩读字符串前只确认第一个字节可读，没有做 `selectorString(atRuntimeAddress:)` 那样的可打印与终止符检查：这种桩要严格匹配 `adrp x1; add x1; b <objc_msgSend 副本>` 才认，而 `x1` 只会指向缓存的 selector 字符串区。造不出会读坏的输入，判为疑似误报，不修。
- `svc` 写 `x0`、`x1`：并入 A1 修。
- 登记 A65。

## B1 — 改名再导出

- **问题**：查一个 C 函数的跨库调用者时，预筛只拿函数在本镜像里的名字比对别的镜像的导入表。别的镜像若把它改名再导出，调用方导入的是新名字：libsystem_c 把 libsystem_platform 的 `__platform_strlen` 导出成 `_strlen`，CoreGraphics 把 SkyLight 的 `_SLSMainConnectionID` 导出成 `_CGSMainConnectionID`。按旧做法，这些调用方全被筛掉。
- **规模**（`dyld_info -exports -all_dyld_cache`，macOS 27.2）：12 个镜像里 1,438 条改名再导出——CoreGraphics 从 SkyLight 1,112 条、Metadata 从 MetadataUtilities 165 条、libHeimdalProxy 从 Heimdal 118 条、libsystem_c 从 libsystem_platform 22 条、UIFoundation 把 CoreText 的两个 ObjC 类改名，等等。AppKit 一个镜像就按 CoreGraphics 的名字导入了 273 个 SkyLight 函数。审查时只看了 libSystem 与十几个大框架，报的「23 个」低估了。
- **复现**：`RenamedReexportTests`：`__platform_strlen` 与 `_SLSMainConnectionID` 的候选里要有 AppKit（同时确认 AppKit 确实调用它们），CoreText 的 `CTEmojiImageAsset` 的候选里要有按 `NSEmojiImageAsset` 导入它的 CharacterPicker。修复前三个都失败。
- **修法**：新文件 `Scanning/RenamedReexportIndex.swift`：第一次需要时并发走一遍所有镜像的导出表，只记改名的再导出（名字只在命中时才拼出），按「被再导出的镜像与名字」归档；条目里的库序号经加载命令换成镜像。新公开接口 `reexportedNames(ofSymbolsNamed:inImageAt:)` 顺着改名再改名、以及经伞形框架整体再导出的情形（acfsSupport 从 CoreServices 再导出 Metadata 的 `_kMDConfigErase`）找全别名；`imageIndices(callingFunctionAt:symbolNames:among:)` 与类预筛把别名一并比对。
- **既往**：`a5895b4c` 修过同一个预筛的 Swift 那一半（改按链接关系），C 名字这一半没动过，也没考虑改名再导出。

## B2 — demangle 结果永久驻留

- **问题**：`swiftTypeKeys(in:)` 与 `SwiftTypeIndex.key(ofDescriptorAt:)` 用 `demangleAsNode`，把整棵树钉进全局 `NodeCache`；`swiftTypeKeys(in:)` 的 mangled 名字一路用 `SymbolicDemangler.demangleType(for:in: InProcessContext.shared)`，结果进了进程级、永不淘汰的 memo。查询碰到的名字没有上限，长期运行的引擎服务里内存只涨不降。AGENTS.md 明令 Sources 不得在无界输入上用 `demangleAsNode`。
- **复现**：`TypeNameRetentionTests`：用每次随机的标识符造一个访问器符号、一段内存里的 mangled 名字，再用测试包里一个只在这里出现的类型的 `…Mn` 符号，查询之后检查 `NodeCache` 是否已有这个标识符的叶子、进程级 memo 是否已有这个名字（新增的包内探针 `SymbolicDemangler.processScopedMemoHoldsType(for:)`，与既有的 `cacheExists(for:)` 同类）。修复前三个都失败，且都只在驻留断言上失败。
- **修法**：改用 `demangleAsNodeTransient` 与 `demangleTypeUncached`。按镜像缓存的 `demangleContext(for:in: image.context)` 是仓库通行写法，可随镜像淘汰，不动。修前修后 `SwiftTypeReferenceTests` 的耗时没有变慢。
- **横向排查**：Sources 里此外没有 `demangleAsNode` 调用。

## B3、B4 — 缓存外镜像的路径与链接关系

- **问题**：`imagePaths` 取 `MachOImage.path`，即 `LC_ID_DYLIB` 的安装名。主程序与插件 bundle 没有安装名，路径是空串；App 自带的框架是 `@rpath/…`。宿主（RuntimeViewer）用 dyld 给的真实路径查，对不上，报找不到镜像；在这些镜像里找到的调用者带着空串或 `@rpath` 路径。B4：用 `-bundle_loader` 链接宿主的插件经 `EXECUTABLE_ORDINAL` 绑定主程序，没有加载命令指向它，链接关系里不算依赖方；两份同安装名的框架拷贝，链接关系只认第一份。
- **复现**：`StandaloneImageTests` 新增三个：SymbolTestsCore fixture 的路径是解析符号链接后与加载路径相同的绝对路径、能按它查回来、安装名也能查回来；测试包自己（`MH_BUNDLE`）的路径等于 `dladdr` 给的路径；测试包算作主程序的依赖方。修复前前两个各两处断言失败、第三个失败。
- **修法**：缓存外的镜像取 `dladdr` 读到的加载路径（按头读，不按序号，免得中途有镜像加载或卸载时错位），缓存里的仍取安装名；另建「安装名 → 全部镜像」的表供加载命令解析，同名的拷贝都算；`imageIndex(forPath:)` 先按路径、再按安装名找。链接关系里每个 `MH_BUNDLE` 都算作每个 `MH_EXECUTE` 的依赖方（超集，预筛只是多扫几个镜像）。

## B5 — 分析器存活期间镜像被卸载

- 分析器持有缓存外镜像的 `MachOImage` 与映射区间，之后若有镜像被 `dlclose` 卸载，读它会读到已释放的内存。要求恰好在一次查询进行中卸载一个缓存外镜像，实际极少见；RuntimeViewer 的会话在镜像列表变化时换新的分析器。不修，在 `CrossReferenceAnalyzer` 的文档里写明，登记 A63。

## B6 — `approximateByteCount` 与字符串

- 估算只算引用、键与索引的定长部分。复核发现引用里的字符串几乎都共用存储：selector 与导入名在扫描器里按指针记忆、类名在类索引里按类记忆、访问器符号随调用目标的解析记忆，所以同一次扫描里重复的名字只占一份。审查说「实际占用可能到预算的两倍」不成立。只在文档里写明字符串不计、但同一次扫描里共用；RuntimeViewer 侧按误报登记。

## B7 — 手写锁加字典，不用 `SharedCache`

- AGENTS.md 要求按镜像的缓存用 `SharedCache`。本模块的函数表、类索引、类型索引、链接关系、改名再导出表都属于一个 `CrossReferenceAnalyzer` 实例，随实例释放；`SharedCache` 管的是进程级、要靠注册表淘汰的缓存。不修，登记 A62。

## N1、N2

- N1：`swiftTypeDescriptorLocations(withKey:inImageAt:)` 的文档说「一个位置，或没有」，可只有找到 `…Mn` 符号时如此；退回逐个算 key 时返回全部同 key 的描述符，顺序不定。改文档如实说明（行为不变：目前见过的镜像里都只有一个）。
- N2：`keys` 的类型 `Dictionary<Key, [Int32]>.Keys` 把实现暴露在公开接口上，改为 `some Collection<Key>`。还没发版，现在改不破坏任何调用方（RuntimeViewer 不用它）。

## D2、D3、D5、D6 — 测试的说法与鉴别力

- D2：`queriesKeepExactlyTheNamesThatMentionTheType` 里四个标准库类型，查询退回的正是测试拿来比对的同一套解开，它们只守着「符号引用不指错描述符」。改测试注释与模块文档的说法。
- D3：`callSitesMatchCapstone` 原来只查 Capstone 找到的调用扫描都找到了。改成双向：扫描报的每一处调用或跳出函数的跳转，Capstone 也要认为是调用或跳转（`br` 例外：Capstone 分不出跳转表与尾调用）；比对过的跳出函数的跳转要不止一处。改后在 macOS 27.2 上通过，即扫描没有多报。
- D5：`superSendsNameTheClassOfTheirMethod` 的两个方法，槽位里的类与方法符号里的类相同，而扫描读不到槽位时正是退回方法符号，所以这个测试分辨不出。新增 `superSendsInBlocksNameTheClassOfTheirMethod`：Block 的符号不是方法名，只有槽位能给出类。临时去掉读槽位的那一行，新测试失败、旧测试照样通过，已恢复。
- D6：`FallbackNamingTests` 的注释改为如实说明挑的镜像是 macOS 27.2 剥得最狠的那几个。不按系统版本门控（A67）。

## D8、D9、D14–D17 — 文档

- D8：AGENTS.md 两处：模块依赖那句改为「起名，以及认出扫描碰到的类与类型」；模块条目改为「两到三秒扫完」，补上类引用与类型引用、加载路径、分析器生命期里留着的索引、改名再导出。
- D9：提案里 AppKit 的类引用数有两组（3,311 / 51,706 与 3,318 / 52,668），分别注明是设计阶段与实现阶段两次探针，口径差别没有记录。
- D14：提案「方案」一节三处已被第二批修订的说法加注。
- D15：模块文档「缓存、内存与生命周期」补上类索引、类型索引、链接关系、改名再导出表也随分析器留着；那里的 170 MB 是第二批之前测的，已注明。
- D16：模块文档的 4,114 个镜像注明是缓存的 4,113 个加基准程序自己。
- D17：提案说类型预筛「凡有 `__swift5_typeref` 节的镜像都算」，代码是任何非空的 `__swift5_*` 节，改提案。
