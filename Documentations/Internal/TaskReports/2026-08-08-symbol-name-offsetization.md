# 2026-08-08 SymbolIndexStore 符号名 offset 化（评审与实现，evolution 提案 0001）

## 问题

`MetadataReaderCache` 清退后，RV 五镜像 445 MB 稳态的全景剖析把头号大户定位到 `SymbolIndexStore` ≈ 215 MiB / 96 万分配，其中最大单项是 **49.4 万个驻留符号名 `String`（68.7 MiB）**——而这些名字的原文本就躺在镜像 mmap 的 LINKEDIT 字符串表里（clean 页、不计 footprint），eager 拷贝等于把免费页复制成付费脏页。用户指示做符号名惰性化 / offset 化；本仓库同日建立 Evolution 提案制，方案以提案 0001 落盘并经用户批准（「审核通过，开始实现」）。

## 调研

调研全文见提案 [0001-symbol-name-offsetization.md](../../Evolutions/0001-symbol-name-offsetization.md)（前期调研一节）。要点：

- MachOKit 无需改动：`MachOImage.Symbol` 本就带 `nameC: UnsafePointer<CChar>`，`Symbols64`/`Symbols` 公开 `stringBase`。
- `storage.symbolTable` 在 `SymbolIndexStore.swift` / `DemangledSymbol.swift` 之外零消费者，内部表示可自由替换。
- export-trie 的名字是解码产物、不在字符串表里，决定了行格式需要「私有缓冲」这条腿。
- Swift 6.2 的 `Span`/`UTF8Span` 与 swift-collections 1.6.0 的 `RigidArray` 在设计期被相中——但见下文「偏差」。

## 最终方案

提案 0001「提议方案 / 详细设计」四步：16 字节 `SymbolRow`（canonical offset + packed name reference）+ `SymbolTable`（mapped 字符串表基址 / 私有字节缓冲双名字来源）；收集循环按 reader 分腿（镜像腿字节级 `isSwiftSymbol`、零 String；文件腿沿用 `readString`、Swift 名进私有缓冲）；`tableRowByName` 退役换名字序 permutation 二分（build 期临时去重字典 freeze 时丢弃）；vend 面按需物化。公开 API 与全部调用点零改动。

## 实际执行

按方案落地，三处**实施偏差**（已逐条记入提案决策日志）：

1. **Span 家族不可用**：编译探针证实 `Span` / `Array.span` / `UTF8Span` 运行时可用性为 macOS 26.0+，本包部署下限 macOS 10.15。字节访问层改用 `UnsafeBufferPointer<UInt8>`（同样的 closure-scoped 形态 `withNameBytes(atRow:)`；`memcmp` 序 + 长度 tiebreak 代替 `bytesEqual`；`String(decoding:as: UTF8.self)` 代替 `String(copying:)`，修复语义与原 `String(cString:)` 一致）。
2. **RigidArray 放弃**：noncopyable 存 class 属性的 borrow 人体工学要 SE-0507（Swift 6.4）。走提案括号里的等价退路——freeze 时精确容量 `Array` 拷贝；因此无需新增 `BasicContainers` 依赖。
3. **搭车项裁剪**：`Optional<NodeIndex>` → 哨兵一项放弃（`NodeIndex` 构造器上游 internal，debug 布局带 store tag，为 ~1.6 MB 不值得跨仓库开 API）；`symbolRowsByOffset` 换普通 `Dictionary` 照做；standalone 表统一走私有缓冲表示（不需要提案草绘的 `[String]` 变体）。

改动面：`Sources/MachOSymbols/SymbolTable.swift`（新建：`SymbolRow` / `PackedNameReference` / `SymbolTable` / `SymbolTableBuilder` / 字节比较与字节级前缀判定）、`SymbolIndexStore.swift`（Storage 换持 + sweep 分腿 + 二分查询）、`DemangledSymbol.swift`（换持 `SymbolTable` + `offset`/`isExternal`/`name` 快路径，避免 dynamicMember 路径为读 offset 整只物化 `Symbol`）；测试三文件适配 + 新建 `SymbolTableEquivalenceTests.swift`；文档同批（AGENTS.md、提案 0001、演进日志、本报告）。

## 验证

1. 等价性测试（新增 4 个，全绿）：字节级 `isSwiftSymbol` 与 `String.isSwiftSymbol` 在 Foundation 镜像全符号表逐条一致；mapped 收集与旧 String 收集全等（行数 + last-wins canonical offset）；二分对每行自洽（镜像腿 + 文件腿）+ 负例；detach 物化正确（行数 1、symbol/node 相等）。
2. 全量 `swift test --skip IntegrationTests`：**1341 tests / 256 suites 全绿**（改动前 1337 + 新增 4，同数吻合）。
3. 渲染 A/B（`Scripts/run-rendering-ab-verification.py`，baseline `aa91b9b`，`USING_LOCAL_DEPENDENCIES=1`，双侧 sibling 均确认 `fileSystem` 解析）：**96 对全部逐字节一致、0 不一致**（当前系统 dyld cache + iOS 15.5–27.0 七个模拟器 runtime + in-process MachOImage，dump + interface；skip 项均为旧 runtime 本就不含的框架，与上次 A/B 同构）。
4. 性能与峰值内存（iOS 18.5 模拟器 SwiftUI `interface`，双侧 release 三轮交错，`/usr/bin/time -l`）：wall-clock 中位 72.5s vs 70.0s（散布 61–79s，噪声带内）——持平，输出再次逐字节一致；maxRSS 383–390 → 400–403 MiB——**文件腿构建期峰值 +~15 MiB**，成因是 build 期去重字典的 `String` 键与私有字节缓冲在 freeze 前短暂持有同一批名字字节两份（提案风险段漏算的一层），freeze 后回落；镜像腿无此代价。
5. RV footprint + heap 复测：落地后由 swift-demangling 会话协调，结果回填提案落地记录（预期堆存活 355 → ~255–285 MiB）。

## 偏差与附带发现

- 方案核心零偏差；三处实施层偏差见上，均为「设计期特性调研没踩到部署下限」一类——**Swift 6.2 语言特性可用 ≠ 目标部署可用**，`Span` 家族的运行时可用性是 macOS 26+，给低部署下限的库用要么等下限提升、要么 availability 门控（核心路径不可行）。
- A/B 首启被 Bash 10 分钟超时上限杀过一次（脚本全程 ~20 分钟），改 nohup 脱离 + monitor 收尾；期间发现被杀的是 python 外壳、其 `swift build` 子进程仍在跑并持有 scratch 锁——后续构建会静默排队等锁，勿误判为卡死。
