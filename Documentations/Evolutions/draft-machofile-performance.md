# Draft - 离线读取追平进程内：去掉 MachOFile 独有的开销，再压两边共用的部分

- **状态**: In Progress
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-07
- **关联提案**: [0086-shared-dependency-openings](0086-shared-dependency-openings.md)（依赖定位器按路径共享 cache 与 Mach-O 文件的打开，本提案的依赖镜像索引建在它之上）
- **实现分支 / PR**: 本库 `perf/machofile-performance`；MachOObjCSection、MachOKitExtensions、MachOKit fork 各开同名分支

## 摘要

RuntimeViewer 离线（`MachOFile`）读二进制的 Swift 部分比进程内（`MachOImage`）慢。上一轮修掉了独立文件每读一次就重开文件等四处根因之后，本机 dyld cache 里的 SwiftUI 打开全部布局注释（RuntimeViewer 的默认）生成 interface，离线仍要约 27.8 秒 CPU，进程内约 15.9 秒。采样显示差距几乎全在离线独有的计算上：静态布局引擎给依赖镜像建索引 12 秒，在 cache 里定位 ObjC 方法表 1.7 秒，读取原语约 1.4 秒。本提案分两期：第一期去掉这三块，目标是追平进程内；第二期压两种读取器共用的部分（主镜像符号索引、统计模块名、索引与打印的热点），RuntimeViewer 的加载也随之变快。另加一个开发用的基准程序，用来在同一进程里比较两种读取器。所有改动输出逐字节不变、公开 API 不变。

## 方案

### 基线

release 构建，Mac Studio Ultra（macOS 27.2），`sample` 按阶段采样，单位是忙碌样本对应的 CPU 秒。

本机 cache 里的 SwiftUI，`interface` 打开五类布局注释（字段偏移、成员地址、vtable 偏移、类型布局、枚举布局），命令行共 27.8 秒：

| 部分 | CPU 秒 | 只有离线才有 |
|---|---|---|
| 给依赖镜像建索引（`ImageReference.init`，算跨模块字段布局用） | 12.0 | 是 |
| 在 cache 里定位 ObjC 方法表（MachOObjCSection `DyldCache._machO(at:)`） | 1.7 | 是 |
| 读取原语（取映射、地址换算、拷贝、取 identifier） | 约 1.4 | 是 |
| 统计模块名（`SwiftInterfaceBuilder.collectModules`，只有命令行走） | 2.1 | 否 |
| 主镜像符号索引、索引器 `prepare`、其余打印 | 约 10.6 | 否 |

- **依赖镜像索引为什么贵**：`ImageReference.init` 一次建齐七张表。其中给类型起名要走 `SymbolicDemangler.demangleContext`，碰到匿名上下文（私有类型、局部类型）就去查符号，于是为每个依赖镜像建一整张符号索引，这一项 7.7 秒。`BuiltinTypeLayoutIndex` 4.8 秒，ObjC 协议名 2.6 秒（与前者有重叠）。依赖按顺序折叠，一次名字未命中就把剩下的传递依赖全部建一遍。`ImageReference` 也不跨 universe 共用：每个打印器建一个 universe，RuntimeViewer 换一个镜像就把共同的依赖（SwiftUICore、Foundation……）再建一遍。
- **单个文件也一样**：iOS 18.5 模拟器的 SwiftUI 带上运行时根目录做依赖搜索路径时共 19 秒，不带只要 11.7 秒，多出的部分同样是依赖镜像索引。
- **进程内对照**：同一份 SwiftUI 经 `MachOImage` 约 15.9 秒，量自 `RenderingVerificationTests`，已扣掉下一条所说的开销。
- **为什么不用渲染对照测试的墙钟**：测试进程里 swift-dependencies 每取一次 `@Dependency` 就调 `TestContext.current`，后者用 `dlsym` 查一个不存在的符号，查不到不缓存，占采样忙碌时间 45–60%。墙钟两次运行能差一倍。

### 测量：开发用基准程序

新增可执行 target `reader-benchmark`（`Sources/Executables/reader-benchmark`，不作为 product 对外）。它在普通进程里按同一份配置分别经 `MachOImage`（`dlopen` 后取镜像）与 `MachOFile`（本机 cache 或给定文件加依赖搜索路径）跑 `prepare()` 与 `printRoot()`，分段报告 CPU 时间、墙钟与 instructions retired（`proc_pid_rusage`）；`--mode index` 只跑 `SwiftDeclarationIndexer.prepare()`，即 RuntimeViewer 加载镜像时等的那一步。每一步改动前后各量一次。

基准程序量出的基线（release，本机 cache 里的 SwiftUI，CPU 秒 / instructions retired，两次运行的范围）：

| 场景 | `MachOImage` | `MachOFile` |
|---|---|---|
| 只建索引 | 4.8–5.1 / 67 G | 6.0–6.4 / 86 G |
| interface 准备 | 7.1–7.8 / 111 G | 8.4–9.0 / 131 G |
| interface 打印（五类布局注释） | 5.1–5.6 / 69 G | 20.1–22.0 / 304 G |

iOS 18.5 模拟器的 SwiftUI（单个文件，运行时根目录作依赖搜索路径）：只建索引 6.9–7.2 / 100 G，准备 9.1–10.0 / 139 G，打印 8.0–8.5 / 111 G。

### 第一期：去掉离线独有的开销

1. **依赖镜像索引**（MachOSymbols：`SymbolIndexStore`；SwiftLayout：`ImageReference`、`ImageUniverse`）
   - 符号索引分两段：第一段只收符号表、按偏移的行索引、`_symbolic` 表与导出事实，不 demangle；把每个名字还原成节点树的第二段在第一次有查询要用树时才建。给依赖镜像的私有类型起名只查「这个地址上的符号」，从此不再 demangle 整个依赖镜像。**已完成**：打印 304 G → 200 G。
   - 七张表各自按需建，用到哪张建哪张；四种查找（类型、协议、ObjC 类、assocty witness）各自折叠依赖，类型查找不再顺带读路过的每个镜像的 ObjC 协议表。读失败的表当空表，不再连累整个镜像。**已完成**。
   - `ImageReference` 按镜像进 `SharedCache`（淘汰组 `layoutImageIndexes`；它不指向别的组的存储，所以不跟随任何组），所有 universe 共用一份。**已完成**：与上一条合计，打印 200 G → 153 G。
   - 按模块名直接找到依赖镜像，名字未命中时不再把剩下的依赖全部折叠一遍：待前几步做完后按采样再定。
2. **cache 里按地址、按序号找镜像**（MachOObjCSection）
   - `DyldCache.machO(containing:)` 每次调用都把 cache 里的全部镜像逐个构造出来、逐段比较地址（macOS 27 的 cache 约四千个镜像），读协议列表、类与 category 时每个指针调一次；`DyldCacheLoaded` 的同名函数（进程内）也一样。改为每个 cache 只建一次按地址排序的区间表，二分查找，同一地址落在几个镜像里时仍取原来遍历顺序里的第一个。
   - `DyldCache._machO(at:)` 每次调用都重建整张 header info 列表、线性查找、再逐个子 cache 尝试构造镜像；改为每个 cache 只建一次「镜像序号 → 镜像」的对照表。
   - **已完成**（MachOObjCSection 分支 `perf/machofile-performance`）：文件一侧的表挂在 cache 文件打开的 file handle identity 上，进程内的表随进程存活（已加载的 shared cache 从不卸载）。只建索引 86 G → 79 G，准备 131 G → 124 G，打印 153 G → 118 G。
3. **读取层**（MachOKit fork、本库 MachOReading）
   - `MachOFile` 的读取直接从 MachOKit 打开文件时做的那份映射里按偏移取值（fork 新增 `@_spi(Support) fileBytes`）：不再另外映射一遍文件（`SharedFileMapping` 删除），不再每读一次就查一次关联对象、做一次动态类型转换、分配一个 `Data`。**已完成**：准备 117 G → 116 G，打印 111 G → 107 G，只建索引 72 G → 71 G。
   - 原计划的「地址区间表、段表各算一次」与「`identifier` 存在实例上」不做：采样显示从完整 cache 枚举出的镜像本来就带着自己文件的 `DyldCache`，`cacheAndFileOffset` 只是每次读取走一遍已记住的映射表，剩下的这几项合计不到 1%。

### 第二期：两种读取器共用的部分

4. **统计模块名**（SwiftInterface）：把节点池扫一遍，不再对每个符号的整棵树做一次泛型遍历（每次调用都要向运行时实例化一次 opaque 类型）。**已完成**：`SymbolIndexStore.moduleNamesInAllSymbols(in:)` 在节点池里前序遍历、共享子树只进一次，名字与首次出现的顺序不变；interface 准备阶段 116 G → 70 G，与只建索引持平。
5. **主镜像符号索引**（MachOSymbols）：把符号名还原成节点树这一步分到多个线程做，再按原顺序驻留，索引内容与顺序不变。**已完成**：每批最多 16 × 512 行，提前一批分给各线程还原，驻留与分类留在建索引的线程上按行号顺序做。只建索引的墙钟 6.6 秒 → 3.7 秒；CPU 时间升到约 12 秒——swift-demangling 0.7.2 的 `Demangler` 在 `require(pop())` 上会整份复制自身，多线程同时复制节点栈时抢引用计数。沙盒里只修这一处（`require` 标成 `mutating`），CPU 回到约 6.5 秒、指令数少约 5%，要不要改 swift-demangling 并发版待用户决定（见决策日志）。
6. **索引器与打印的热点**：按前几步做完后的采样逐个处理，方向是减少临时分配、去掉热循环里没有特化的泛型调用。**已做两处**：`MangledName.resolve` 不再每个字符调一次 `String(format: "%c")`（离线打印约 4.6%，进程内约 1.8%）；类约束泛型参数的替身 `Swift.AnyObject` 的 assocty witness 查找直接答没有（它是 SwiftUI 布局里唯一一次查不到的 witness 查找，却让 552 个依赖镜像全部建了 witness 表）。打印阶段 107 G → 92 G。剩下的大头：类型查找为找到第 33、46、56、59 个依赖镜像里的四个类型，把前面的镜像全建了类型表（约占离线打印 4%，其中三分之二是为给依赖镜像的匿名上下文起名而建整张符号表第一段）；swift-demangling 的 `Remangler` 销毁替换表时走未特化的值见证（进程内打印约 5%）。

第二期之后（本机 cache 里的 SwiftUI，instructions retired / 墙钟，输出与基线逐字节相同）：

| 场景 | 基线 `MachOFile` | 现在 `MachOFile` | 现在 `MachOImage` |
|---|---|---|---|
| 只建索引 | 86 G / 6.4 秒 | 70 G / 3.5 秒 | 65 G / 3.1 秒 |
| interface 准备 | 131 G | 70 G | 65 G |
| interface 打印（五类布局注释） | 304 G / 21 秒 | 92 G / 6.3 秒 | 67 G / 4.5 秒 |

只建索引与准备阶段的 CPU 时间目前约 11.4 秒（单线程时约 5.2 秒），原因见第 5 项。

### 不变的部分

- `dump` 与 `interface` 的输出逐字节不变，以渲染 A/B 验证。
- 公开 API 不变；新增的只有上游仓库的 SPI。
- CLI 的 flag 与行为不变。

### 落地步骤

1. 基准程序，记录基线（本库）。**已完成**
2. 依赖镜像索引，按上面四条依次做，每条各量一次（本库）。前三条已完成，第四条待定。
3. cache 里按地址、按序号找镜像（MachOObjCSection）。**已完成**，待发版。
4. 读取层（MachOKit fork → 本库）。**已完成**，fork 待发版；MachOKitExtensions 不用改。
5. 统计模块名（本库）。**已完成**。
6. 主镜像符号索引多线程（本库）。**已完成**。
7. 索引器与打印的热点（本库）。做了两处，其余见上。
   - 期间查出 MachOKit 的竞态（fork 修复，见决策日志）：`DyldCache`、`FullDyldCache`、`MachOFile` 把算过的映射表、main cache、full cache、symbol cache 记在不加锁的存储属性里，两个线程第一次同时读同一个镜像时会 use-after-free。
8. 收尾：全量测试、渲染 A/B、Xcode 26.6 编译检查；上游按依赖顺序发版（MachOKit fork、MachOKitExtensions、MachOObjCSection），本库抬依赖下限；更新演进账本与相关模块文档。

开发期间本库经 `swift package edit` 指向上游的功能分支，不动任何共享检出的依赖链接。

### 采用的假设

- 进程内的数字以基准程序为准；渲染对照测试只用来做 A/B。
- 第二期第 5 项若发现节点驻留无法安全分线程，就只把还原节点树分出去、驻留留在单线程，并在决策日志里记下。
- 测试进程里那次 `dlsym` 不在本提案范围内，记为后续项。

### 后续项

- 测试进程里 swift-dependencies 的 `TestContext.current` 每次都 `dlsym`：拖慢所有经 `@Dependency` 的测试，可在测试支撑里预先建立依赖上下文，或向上游提修复。
- 类型查找按模块定向（第 2 项第四条）：查一个名字时只折叠类型表里可能有这个模块前缀的镜像。每个镜像的前缀集合可以不建整张表就算出来——各类型描述符祖先里的模块名，加上嵌套类型所在扩展的被扩展类型的模块；只含标识符的名字才走定向查找（局部类型的键带 ` #`、括号，不会与之相等）。收益有限：Foundation、SwiftUICore 都扩展了 `Swift` 里的类型，查 `Swift.*` 时它们仍要建表；RuntimeViewer 在各个根之间共享依赖镜像的表，只有头一两个根受益。做之前要先在真实镜像上钉住「每个只含标识符的键的前缀都在集合里」。
- 依赖镜像的符号表第一段只为给匿名上下文起名而建：可以再拆出只按偏移查的一段，跳过按名字排序、去重哈希与导出 trie 遍历。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | 创建为精简提案，用户批准：两期都做，加开发用基准程序，MachOObjCSection、MachOKitExtensions、MachOKit fork 可以改并各自发版（MachOKit 只进 fork）；状态 Accepted | 上一轮修复后离线仍慢约 1.75 倍，采样显示差距几乎全在离线独有的计算上 |
| 2026-11-06 | 基准程序落地、记下干净基线；状态 In Progress | 测试进程的墙钟被 `dlsym` 污染，普通进程里两种读取器才可比 |
| 2026-11-06 | 依赖镜像起名改为「符号索引分两段」，不再「沿描述符父链自己拼名字」 | 自己拼名字要逐条复刻 `demangleContext` 的规则（C 导入类型的 TypeImportInfo、扩展上下文、私有类型的 discriminator），依赖镜像的私有类型又确实会被按名字查到（依赖类型的字段经 symbolic reference 指向它）；分两段后起名只查一个地址上的符号，贵的部分（demangle 整个镜像）已经去掉，名字仍由同一套代码给出，查找两侧必然一致 |
| 2026-11-06 | 依赖镜像的表按需建、按查找种类分开折叠、按镜像共享 | 各种查找折叠的镜像与顺序和原来相同，每次查找答案不变；共享的 `ImageReference` 只含值类型，不指向别的淘汰组的存储 |
| 2026-11-06 | `DyldCache.machO(containing:)` 与 `DyldCacheLoaded` 的同名函数并入第 2 项 | 符号索引分两段后重新采样，它是依赖镜像索引里剩下的最大一块（读 ObjC 协议列表时每个协议都要遍历 cache 的全部镜像） |
| 2026-11-06 | 读取改走 MachOKit 自己的映射，删掉 `SharedFileMapping` 与 `ConcurrentFileMappingTests`；`SharedFileMappingTests` 改名 `FileMappingTests`，「删掉的文件读取要抛错」改为「照样读得到」，另加越界读取抛错；CI 套件列表随之换名 | 映射在打开文件时就已建好且按打开共享，读取不再有「第一次读时映射」这一步，竞态与映射失败两种情形都不存在了；描述符反而少了一份 |
| 2026-11-06 | 第 3 项缩小为只做 `fileBytes`，MachOKitExtensions 不改 | 采样修正了「每次访问 `cache` 都新建 `DyldCache`」的判断：cache 里的镜像创建时就带着自己文件的 `DyldCache`，余下几项合计不到 1% |
| 2026-11-06 | 第 5 项按计划做：demangle 一批批分给多线程，驻留与分类留在单线程按行号顺序 | 节点序号就是驻留顺序，打印与快照依赖它；一行的树只由名字决定，分线程不改变结果 |
| 2026-11-06 | 并行 demangle 的 CPU 开销来自 swift-demangling：`try require(pop())` 这类写法里 `require` 不是 `mutating`，编译器先整份复制 `Demangler` 再求参数，之后每次 `pop()` 都写时复制节点栈 | 采样：并行时还原树的一半 CPU 在这份复制引起的 retain/release 上，单线程时也占 demangle 时间约三分之一。swift-demangling 不在已批准可改的上游里，改不改、发不发版由用户决定；本库先保留并行（墙钟减半），决策日志记下代价 |
| 2026-11-06 | 第 4 项改为在节点池里遍历，共享子树只进一次 | 结果、首次出现顺序与符号数都和逐棵树遍历相同（`moduleNamesMatchAWalkOfEveryTree` 钉住） |
| 2026-11-06 | 第 7 项先做 `MangledName.resolve` 与类约束替身的 witness 查找 | 前者逐字节核对过 `%c` 与按 Latin-1 标量追加在 0x20–0xFE 上结果相同；后者经临时插桩确认：整次运行只有这一次 witness 查不到，代价是 552 个依赖镜像的 witness 表 |
| 2026-11-06 | 修 MachOKit fork 的竞态：两张映射表在打开 cache 时就读好、改为常量；镜像组装时就带的 `DyldCache` 改为常量；其余懒得出的引用（main cache、full cache、symbol cache）经 `MemoizedReference` 加锁读写，锁外计算、只在仍为空时发布 | SwiftInterfaceTests 约一半的运行在 `mappingInfo(for:)` 里 SIGSEGV（lldb 抓栈）。缓存是上游 2026-06 加的，第 4 步之前的读取路径也走它；第 2 步让依赖镜像的表在所有 universe 间共享、`LazilyBuiltIndex` 又在锁外建表，两个测试会同时给同一个镜像建同一张表，才变得常见。热路径上的两处改成常量而不是加锁，读取不多一次加锁 |
