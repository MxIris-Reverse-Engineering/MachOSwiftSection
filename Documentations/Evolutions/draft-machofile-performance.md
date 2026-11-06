# Draft - 离线读取追平进程内：去掉 MachOFile 独有的开销，再压两边共用的部分

- **状态**: Accepted
- **创建日期**: 2026-11-06
- **最后更新**: 2026-11-06
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

新增可执行 target `reader-benchmark`（`Sources/Executables/reader-benchmark`，不作为 product 对外）。它在普通进程里按同一份配置分别经 `MachOImage`（`dlopen` 后取镜像）与 `MachOFile`（本机 cache 或给定文件加依赖搜索路径）跑 `prepare()` 与 `printRoot()`，分段报告 CPU 时间、墙钟与 instructions retired（`proc_pid_rusage`）。每一步改动前后各量一次。

### 第一期：去掉离线独有的开销

1. **依赖镜像索引**（SwiftLayout：`ImageReference`、`ImageUniverse`）
   - 类型名沿描述符的父链直接读出（模块、类型、扩展上下文的名字），不再经 `SymbolicDemangler` 为依赖镜像建符号索引；父链里有匿名上下文的类型不进跨镜像的名字索引，因为别的镜像无法按名字引用它。扩展上下文的被扩展类型仍按 mangled name 还原。
   - 七张表各自按需建，用到哪张建哪张。
   - `ImageReference` 按镜像进 `SharedCache`，所有 universe 共用一份；淘汰组跟随符号索引。
   - 按模块名直接找到依赖镜像（模块名到镜像的对照表随依赖闭包一起建），名字未命中时不再把剩下的依赖全部折叠一遍。
2. **cache 里的 ObjC 方法表**（MachOObjCSection）：`DyldCache._machO(at:)` 现在每次调用都重建整张 header info 列表、线性查找、再逐个子 cache 尝试构造镜像；改为每个 cache 只建一次「镜像序号 → 镜像」的对照表。
3. **读取层**（MachOKit fork、MachOKitExtensions、本库 MachOReading）
   - `MachOFile` 的读取直接从映射指针按偏移取值：不再每读一次就查一次关联对象、做一次动态类型转换、分配一个 `Data`。
   - cache 镜像的「地址区间 → 子文件映射」表与独立文件的段表各只算一次，`resolveOffset(at:)` 不再每次重读 load command。
   - `identifier` 等每次查找都要用到的值改为存在实例上，不再经全局锁保护的关联对象。

### 第二期：两种读取器共用的部分

4. **统计模块名**（SwiftInterface）：把节点池扫一遍，不再对每个符号的整棵树做一次泛型遍历（每次调用都要向运行时实例化一次 opaque 类型）。
5. **主镜像符号索引**（MachOSymbols）：把符号名还原成节点树这一步分到多个线程做，再按原顺序驻留，索引内容与顺序不变。
6. **索引器与打印的热点**：按前几步做完后的采样逐个处理，方向是减少临时分配、去掉热循环里没有特化的泛型调用。

### 不变的部分

- `dump` 与 `interface` 的输出逐字节不变，以渲染 A/B 验证。
- 公开 API 不变；新增的只有上游仓库的 SPI。
- CLI 的 flag 与行为不变。

### 落地步骤

1. 基准程序，记录基线（本库）。
2. 依赖镜像索引，按上面四条依次做，每条各量一次（本库）。
3. cache 里的 ObjC 方法表（MachOObjCSection）。
4. 读取层（MachOKit fork → MachOKitExtensions → 本库）。
5. 统计模块名（本库）。
6. 主镜像符号索引多线程（本库）。
7. 索引器与打印的热点（本库）。
8. 收尾：全量测试、渲染 A/B、Xcode 26.6 编译检查；上游按依赖顺序发版（MachOKit fork、MachOKitExtensions、MachOObjCSection），本库抬依赖下限；更新演进账本与相关模块文档。

开发期间本库经 `swift package edit` 指向上游的功能分支，不动任何共享检出的依赖链接。

### 采用的假设

- 进程内的数字以基准程序为准；渲染对照测试只用来做 A/B。
- 第二期第 5 项若发现节点驻留无法安全分线程，就只把还原节点树分出去、驻留留在单线程，并在决策日志里记下。
- 测试进程里那次 `dlsym` 不在本提案范围内，记为后续项。

### 后续项

- 测试进程里 swift-dependencies 的 `TestContext.current` 每次都 `dlsym`：拖慢所有经 `@Dependency` 的测试，可在测试支撑里预先建立依赖上下文，或向上游提修复。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-11-06 | 创建为精简提案，用户批准：两期都做，加开发用基准程序，MachOObjCSection、MachOKitExtensions、MachOKit fork 可以改并各自发版（MachOKit 只进 fork）；状态 Accepted | 上一轮修复后离线仍慢约 1.75 倍，采样显示差距几乎全在离线独有的计算上 |
