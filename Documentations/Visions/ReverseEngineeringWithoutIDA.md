# 愿景：不依赖 IDA 的逆向

- **状态**: Active
- **最后更新**: 2026-11-26
- **相关提案**: [0097-offline-cross-references-and-symbolication](../Evolutions/0097-offline-cross-references-and-symbolication.md)、[draft-cross-reference-recall-gaps](../Evolutions/draft-cross-reference-recall-gaps.md)（召回补漏）

愿景**不做具体决定**，它划定一个方向的边界与取舍原则，让后续每个提案不必重新论证一遍。
具体怎么做写在各自的提案里。

## 这是什么领域

从 Mach-O 的字节出发，产出 agent 读懂一段代码在做什么所需的全部材料，覆盖 Apple 平台的 arm64 / arm64e
二进制：dyld shared cache 里的系统镜像（包括 `/Volumes/DyldSharedCaches` 下归档的各个版本）、独立 app 与它
内嵌的框架、Xcode 的私有框架。具体包括：

- **函数边界与命名**：每个函数从哪开始、到哪结束、叫什么，包括没有符号的函数、block、`.cold` 片段。
- **地址符号化**：任意一个地址是什么——哪个镜像的哪个函数加多少偏移、哪个桩最终跳到哪、哪个槽里装着谁。
- **交叉引用**：谁调用了某个函数、谁发送了某个 selector、谁读了某个类对象、某个 ivar、某个字符串，跨镜像、
  跨整个 cache。
- **带注解的反汇编**：每个调用、地址生成、槽读取都标上真实名字或字符串内容的汇编。
- **控制流与局部数据流**：跳转表恢复、基本块划分、函数内的寄存器常量追踪（selector、调用的常量参数）。
- **数据常量解码**：CFString、ObjC 字面量、KeyPath、Swift 字符串、相对指针、fixup 指针。
- **两个构建之间逐函数比较**。
- **分析结果的持久化**（如果实测证明需要）。
- **查询入口**：`swift-section` 的子命令、RuntimeViewer 的 CLI 与 MCP，以及全局 `reverse-engineering`
  skill 规定的逆向流程。

涉及的仓库：MachOKit（fork）、MachOKitExtensions、MachOObjCSection、本库（`CrossReferenceAnalysis`、
`SwiftThunkAnalysis`、`swift-section`）、swift-capstone、RuntimeViewer。

**不算在内的**，见文末「不在此愿景内」：伪代码、运行时检查与跟踪、交互式标注、x86_64。

## 为什么值得系统性投入

今天逆向的第三阶段完全交给 IDA：全局 `reverse-engineering` skill 规定「先类型定义，再成员地址，最后
反编译」，第三步经 idalib MCP 调 IDA。2026-11-18 统计本机全部 Claude Code 对话记录，agent 对 IDA 的调用
（调用量前 30 的工具合计）约 4.76 万次，其中 `decompile` 27,447 次（约 58%）、`disasm` 9,454 次、
`xrefs_to` 2,304 次、`xref_query` 441 次，其余是开关库与读字节。

但 agent 真正离不开 IDA 的，是**给地址起名**和**查引用**，伪代码反而是可替代的那一块（见「现状与代价」）。
要替代的这几块——地址符号化、交叉引用、注解反汇编、控制流、数据解码、持久化——每一块都要面对同一组问题：
扫描用哪个解码器、地址按哪种约定换算、符号化放在哪一层、输出给 agent 的契约长什么样、要不要落盘。不先定
方向，每份提案都会把这组取舍重新吵一遍。

## 现状与代价

以下都可在所引的记忆、笔记或文档里核实（`~/.claude/agent-memory/reverse-explorer*/`、各项目的 agent 记忆、
全局 `reverse-engineering` skill 的 `references/ipsw-cache-recipes.md`）。

- **跨镜像查「谁用了它」没有工具**。约 15 条逆向笔记靠手工两跳：先按字节扫 `__objc_selrefs` 或 GOT 槽
  （低 4 字节是 `VA - 0x180000000`），再反汇编 stub island 找 `adrp x1` + `add x1`，最后 `ipsw dyld a2s`
  起名（`reverse-explorer/cross-cache-caller-search.md`）。
  - `ipsw dyld xref` 不跟进 stub island，结果为空什么也证明不了；`dyld_info -imports` 静默漏掉大部分 bind。
  - 2026-10-29 有一次把「某个类没人实例化」判错：漏查了经 GOT 读**本镜像自己**类对象的两处调用。
  - 列出导入某个类的镜像，只能对 4,115 个镜像各跑一次 `ipsw dyld macho --symbols`，28 核 2 分 40 秒。
- **cache 里的调用目标常常没名字或名字是错的**。
  - `dyld_info -disassemble` 把 macOS 26.7 SwiftUICore 的 2,195 个 `__auth_stubs` 桩标成同一个错名，
    15.3 万条 `bl` 的目标名字错（RuntimeViewer 记忆 `dyld-info-mislabels-cache-stubs.md`）。
  - 27.0 起 `objc_msgSend$…` 桩合并到 cache 级区域，`ipsw dyld a2s` 对它只回 `?`。
  - IDA 单镜像库里的导入桩被叫成 `j___<该镜像第一个局部符号>_N`。
  - 整个 cache 1,308 万个函数起点里 37.8% 没有符号（macOS 26.7）。
- **IDA 本身在拖后腿**。
  - 23 个会话在 `idb_open` 时报 `Remote end closed connection`（1.6–2.5 GB 的库，60 秒工具超时）。
  - `idb_close(save: false)` 照样回写 `.i64`，之后再开常报 `internal error 1228`。
  - `xrefs_to` / `disasm` 只回 10 行却报 `done: true`。
  - 一个库只装得下几个镜像，跨镜像的引用在库里看不到；漏一个镜像就得重建，几分钟起步。
- **伪代码有系统性错误**。约 16 条笔记记着 Hex-Rays 的误判：丢掉 `@try` / `@catch`、返回多个 `double`
  的函数只剩 `d0`、7 个参数的签名被截成 5 个、带 label 的分支里祖先 `if` 的条件不再成立。skill 早就规定
  「汇编与伪代码冲突时信汇编」。
- **手工解码与比对的成本**。32 个会话手写过 `struct.unpack`；SourceEditor 为逐函数比对原版与重建版的汇编，
  写了 30 个 Python 脚本和一份 981 行的规整规则（`SourceEditor/Documentations/Internal/AssemblyComparison.md`）。

基础其实已经有一半：本库的 `CrossReferenceAnalysis`（提案 0072）在进程内 1.6–3.0 秒扫完整个 cache、
认得 27 的 cache 共用桩和 stub island；`SwiftThunkAnalysis` 里已有一套离线的桩链与槽解析；swift-capstone
7 已经把 AArch64 的指令、操作数、别名都包成 Swift 类型。缺的是把它们接到磁盘文件、接到命令行，并补齐其余几块。

## 根本的设计取舍

1. **agent 的主读物：汇编还是伪代码。** 伪代码短、结构一目了然，但有上面那类系统性错误，而且离不开 IDA；
   汇编是地面真值，但裸汇编里的 `bl 0x19…` 没有名字，长函数很长。
2. **扫描用哪个解码器：手写子集还是 capstone。** 手写的 `ARM64InstructionDecoding` 只认交叉引用用得到的
   指令形态，单线程比 capstone 快 25–50 倍；capstone 覆盖全部指令和完整的操作数语义，有上游背书。两套并存
   就得保证它们对同一条指令的理解一致。
3. **要不要像 Binary Ninja 那样建完整的中间表示。** Binary Ninja 把代码提升成多层 IL 并在 SSA 上做常量传播，
   引用识别的上限高，但这是一个反编译器级别的工程；只做函数内的轻量寄存器追踪，能覆盖 `adrp` + `add`、
   `adrp` + `ldr` 槽、`mov x1` 这些常见模式，跨基本块的复杂数据流会漏。
4. **按需现算还是落盘索引。** 现算没有失效问题，重复查询却要重扫；落盘快，但要管 cache 版本、格式演进和磁盘
   占用。
5. **统一地址空间还是按镜像建模。** Binary Ninja 把整个 cache 放进一个地址空间，跨镜像的引用就是普通地址；
   本库的 `CodeLocation` 是「镜像下标 + 未滑动地址」，RuntimeViewer 已经按它建了一层查询。
6. **新能力放在哪一层。** MachOKit 是 p-x9 上游的 fork，fork 已落后上游 33 个提交，越加越难合；
   MachOKitExtensions 是自有的通用层，正在接收本库的读取层（MachOKitExtensions 草案
   `move-reading-and-resolving-modules`，之后又接收了整个 Mach-O 层，见下文「我们选的方向」第 6 条）；
   本库的 Analysis 层离使用方最近，但通用的东西放这里，别的仓库
   （MachOKitUI、swift-decompiler）拿不到。
7. **正确性的标准答案用谁。** 反汇编有 `otool -tV` / `llvm-objdump`；fixup 有 `dyld_info -fixups`（只读本机
   cache）；交叉引用没有天然的地面真值，IDA 自己就会漏，Binary Ninja 更全但只能在它的界面里跑。

## 我们选的方向

1. **agent 默认读带注解的汇编，IDA 是后备。**
   - **IDA**：负责本方向工具还覆盖不到的交叉引用、控制流特别复杂的超长函数，以及 swift-decompiler 的研究
     （它以 IDA 的 microcode 为输入）。
   - **Binary Ninja**：只在用户手动使用时作参照，不进 agent 的默认流程。
   - 2026-11-18 用户曾选定「Binary Ninja 负责交叉引用、IDA 负责复杂函数」的分工，前提是 Binary Ninja 的
     交叉引用更强；同日的实测（见下）推翻了这个前提，用户改定 IDA 为主。dyld cache 里跨镜像的引用两家都受
     「一个库或一个视图只装得下部分镜像」所限，交给第 1 阶段的新工具。
   - 改 skill 的默认流程之前，先量一次：挑几十个函数，比较注解汇编和 Hex-Rays 伪代码的 token 数与正确率，
     结果写进本愿景。
   - **放弃**：伪代码作为默认读物；Hex-Rays 的类型恢复带来的那部分可读性。

   Binary Ninja 6（6.0.10601）起自带 MCP 服务器，以下是评估时查到与实测到的情况：
   - GUI 内的 HTTP 版随所有 GUI 版本提供，包括用户的 Personal 版：设置里开 `ui.mcp.enabled`、重启、
     `Plugins > MCP > Start Server`，默认 `http://127.0.0.1:24642/mcp`。无界面的 `binaryninja_mcp` 只随
     Commercial / Ultimate。
   - 2026-11-18 在本机实测连通（服务名 `binaryninja_ui_mcp` 0.1.0，未设令牌）：共 75 个工具，读的有
     `bn_function_callers` / `bn_function_callees`、`bn_function_xrefs_to` / `_from`、`bn_data_xrefs_to` /
     `_from`、`bn_type_xrefs_to` / `_from`、`bn_function_disassembly`、`bn_function_il`、
     `bn_function_decompile`、`bn_function_basic_blocks`、`bn_memory_read`；写的有改名、注释、定义类型与
     数据变量。
   - 限制：必须开着界面；当前视图跟随界面，多个 agent 同时用会互相抢；工具清单里**没有**从 dyld shared
     cache 加载某个镜像的工具，cache 里的镜像要在界面里加载；函数相似度比对（含 BinDiff）只有 Ultimate 版有。
   - **实测（2026-11-18）：在独立二进制上，经 MCP 查交叉引用，Binary Ninja 不如 IDA。**
     - 样本：Finder 26.5.2（ObjC 为主）与 ControlCenter 26.7（Swift 为主），arm64e，120 个目标、527 条代码
       引用、49 条数据引用。标准答案由 `otool -tV` 加独立的 `adrp` 寄存器跟踪、`dyld_info -fixups`、相对方法
       列表与 `__swift5_types` 解码生成，不依赖任何一方。
     - 代码引用召回：IDA 一次查询 97.0%、两跳 99.4%，裁决后没有真误报；Binary Ninja 经 MCP 一次查询 67.6%，
       另有 22 条 `adrp` 页地址误报。Binary Ninja 的分析里其实有 97.7%（按函数粒度算，偏宽），差距出在 MCP
       接口：`bn_data_xrefs_to` 只报「数据 → 数据」，没有「代码 → 数据地址」的反查，所以类引用、字符串、ivar
       三类经 MCP 都是 0%；`bn_function_callers` 不认 objc stub 调用，要再调 `bn_function_xrefs_to`；方法列表
       的 IMP 字段只找到 8/16。
     - 双方各自的盲点：IDA 漏掉恰好页对齐的类对象（`adrp; add #0`），按类符号查询只给一跳；Binary Ninja 漏掉
       Swift 大字符串的 `adrp; add; sub #0x20` 写法（13 处只中 2 处），也没给 `retab` 之后的异常清理代码建函数。
     - 耗时：Binary Ninja 从打开到分析完成，Finder 224 秒、ControlCenter 81 秒；IDA 打开现成 `.i64` 约 3 秒
       （建库时间未计）。
     - 没测到的：dyld shared cache 里的跨镜像引用。IDA 的弱点主要在这里（一个库只装得下几个镜像），而
       Binary Ninja 的 MCP 又没法加载 cache 镜像，这一场景要用户在界面里手动加载后才能比。
   - **复测（2026-11-26）：本方向的工具在同一组样本上，代码引用召回 90.3%（476/527）；IDA 一次查询 97.0%、
     两跳 99.4%。**
     - 被测的是 `swift-section refs` 0.25.0（0097 之后交叉引用只有重构，行为与 `next` 相同），每个目标查一次。
       标准答案与选目标的代码从 2026-11-18 那次的对话记录原样取回，复现出同一批 120 个目标；引用总数、目标列表与
       当时逐项一致，IDA 一列按原规则重算仍是 97.0% / 99.4%，所以两次的数字可以直接比。
     - 分类别：导入函数（91）、内部 `bl`（70）、字符串（46）全中，与 IDA 持平；selector 发送 95/97（IDA 一次
       92）；ivar 31/32；ObjC 类引用 66/87（IDA 一次 76、两跳 84）；Swift 元数据访问器 77/104（IDA 104）。
       49 条数据引用按 0097 的非目标不做，记 0。多报 1 条，核对后是真引用。单次查询 0.1–0.3 秒，不用建库。
     - 漏掉的 51 条分五组：27 条是代码取了访问器的地址当函数指针用——分析器记成了 Swift 类型引用，但 CLI 没有
       按类型查的入口；13 条是 `__objc_superrefs` 的载入，按设计不算类引用；8 条是 Swift 代码把 ObjC 类的 GOT
       槽地址交给编译器生成的元数据辅助函数（ControlCenter 里有 554 处这种调用）；2 条是 selector 只当参数用
       （`respondsToSelector:`、返回 selector 的函数）；1 条是 `adrp; add` 之后 `ldrsw [xN]` 读 ivar 偏移，
       原因待查。
     - 比 IDA 强的地方：页对齐的类对象、经 `ldr` 读 selref 的经典发送都一次查到。
     - 后四组缺口的修复是提案
       [draft-cross-reference-recall-gaps](../Evolutions/draft-cross-reference-recall-gaps.md)，修完的目标是
       514/527（97.5%），剩下的就是 `super` 的那 13 条。测量脚本随那份提案进仓库，以后改交叉引用就拿它验收。
2. **两个解码器分工。** 扫描整个 cache 的热路径用手写的 `ARM64InstructionDecoding`；给人和 agent 读的反汇编
   文本、需要完整操作数语义的地方（跳转表、寄存器追踪）用 swift-capstone。两者之间用对拍测试保持一致：
   同一批函数两边解码，结果逐条比。swift-capstone 因此要加大维护——拿 `otool -tV` 整镜像对拍正确性（重点是
   arm64e 的 PAC 指令、LSE 原子指令和 Apple 专有指令），并提供把地址操作数换成名字的符号化接口。
   - **放弃**：只维护一套解码器的简单。
3. **不建完整的中间表示，只做函数内的轻量常量追踪。** 在 `RegisterFile` 的基础上扩展：基本块内向前追踪
   `adrp` / `add` / `ldr` / `mov` 产生的常量，遇到调用清掉调用者保存的寄存器；跨基本块只在单前驱、或多个
   前驱的值一致时传递。这是 Binary Ninja SSA 常量值的一个子集，覆盖它做 ObjC selector 识别时用到的那部分。
   - **放弃**：跨函数数据流、类型传播。Swift 的字段级引用（谁读写了某个结构体字段）依赖类型传播，等常量追踪
     落地后再评估。
4. **先现算，量过再落盘。** 0072 与 RuntimeViewer 0056 都定过「不做存盘索引」；离线模式的吞吐要实测，冷启动
   读几个 GB 的 cache 若明显拖慢重复查询，持久化再作为独立阶段提出。
5. **保留按镜像的 `CodeLocation`，另给一张全 cache 的地址符号化表。** 统一地址空间里最有价值的是「任何地址
   都能说出它是什么」，这一点用符号化器单独提供，不推翻已有的模型和 RuntimeViewer 的查询层。
6. **分层：与语言无关的部分归 MachOKitExtensions，ObjC 专属的归 MachOObjCSection，Swift 专属的与命令入口留在本库。** 与语言无关的包括读取、地址换算、桩与槽的解析，也包括分析本身的核心——指令扫描、函数表、字符串、符号化；ObjC 专属的是消息发送、类引用、ivar、方法列表这类识别。核心经扩展点接纳各语言层的识别，不认识任何一种语言，对新语言封闭、对扩展开放。自 MachOKitExtensions 2.0.0 起，本库原来的整个 Mach-O 层（读取、指针、按镜像的缓存、依赖闭包、符号表与采集，外加一个 C/C++ 符号索引）都在那里，本库的 `Sources/MachO/` 分组已经没有了（MachOKitExtensions 草案 `move-macho-infrastructure-modules`）；不依赖 Swift 元数据的新通用代码直接写进 MachOKitExtensions。交叉引用是先在本库按这几层写成独立模块、用源码扫描守住每层能 import 什么、量过之后再整体搬过去的（0097 拆层，提案 [0098 move-cross-reference-layers](../Evolutions/0098-move-cross-reference-layers.md) 搬家）；本库里的模块名刻意不同于落脚处的名字，免得与已发布版本的同名模块冲突。除了修 bug，不往 MachOKit fork 里加新能力。
7. **标准答案**：反汇编对 `otool -tV`；fixup 对本机 cache 的 `dyld_info -fixups`；交叉引用以 IDA（查到两跳）
   为主要参照，Binary Ninja 为辅——第 1 条的实测里，IDA 两跳的召回是 99.4%，Binary Ninja 经 MCP 是 67.6%。
   最可靠的仍是 `otool -tV` 加独立寄存器跟踪生成的标准答案，那次实测就是这样做的。

## 分阶段设想

只给轮廓，实际提案可以调整顺序或合并拆分。

1. **交叉引用与地址符号化扩展到磁盘文件和归档 cache**——本库已有的进程内分析器支持文件，补几类引用，新增
   符号化器，`swift-section refs` / `symbolicate` 两个子命令，RuntimeViewer 的 CLI 与 MCP 接上交叉引用。
   提案 [0097-offline-cross-references-and-symbolication](../Evolutions/0097-offline-cross-references-and-symbolication.md)。
2. **函数清单与带注解的反汇编**——边界来自 `LC_FUNCTION_STARTS`、符号表、ObjC 方法表的 IMP 与 unwind 信息，
   包括 block 和 `.cold`；用 swift-capstone 出文本，每个调用、地址生成、槽读取都经第 1 步的符号化器标名。
   swift-capstone 的对拍与符号化接口在这一步做。
3. **数据解码与数据引用**——`read --as cfstring | objc-literal | keypath | swift-string | relative-pointer |
   fixup-pointer`；方法表条目指向 IMP、CFString 指向字符串这类「数据 → 地址」的引用进交叉引用。
4. **控制流与常量追踪**——跳转表恢复、基本块、跨块常量传递；顺带做调用点常量参数普查（例如
   `dyld_program_sdk_at_least` 每个调用点传的版本集合）。
5. **两个构建逐函数比汇编**——按符号或 selector 配对，规整重定位与 ARC 差异，每个函数判成「完全一致 /
   只有重定位差异 / 有实质变化」三档；SourceEditor 的比对脚本收编进来。
6. **分析结果落盘**——只在前几步实测证明重复查询的代价不可接受时提出。
7. **切换默认流程**——完成「我们选的方向」第 1 条里的测量后，`reverse-engineering` skill 的第三阶段改成
   「读注解汇编」，IDA 降为后备。

## 不在此愿景内

- **伪代码与反编译器**：swift-decompiler 自己的路线，目前以 IDA 的 microcode 为输入。
- **运行时检查与跟踪**：读活对象的 ivar、列存活实例、selector 调用跟踪，属于 RuntimeViewer 自己的方向。
- **交互式标注库**：改名、注释、手工类型存回数据库，这是 IDA / Binary Ninja 的产品形态，不做。
- **x86_64 与其他架构**：只有 Apple Silicon 机器，系统二进制都有 arm64e 切片。
- **把 Binary Ninja 当 agent 的主力后端**：Personal 许可没有无界面 API，无界面的 `binaryninja_mcp` 也只随
  Commercial / Ultimate 提供；它的 GUI MCP 只能在用户开着界面时用。
- **改进 IDA 后备路径**（例如 idax 建库时写入我们的桩名和 Swift 函数名）：IDA 降为后备后按需另提，不是本
  愿景的目标。

## 待确认

- **注解汇编与伪代码的实测结果**（「我们选的方向」第 1 条的测量）。
- **dyld shared cache 跨镜像引用上 IDA 与 Binary Ninja 的差距**：实测只覆盖了独立二进制；后备已定为 IDA，
  这一项只在将来重新评估后备时才需要补测。

## 相关提案

| 提案 | 状态 | 它推进了愿景的哪一部分 |
|------|------|------------------------|
| [0097-offline-cross-references-and-symbolication](../Evolutions/0097-offline-cross-references-and-symbolication.md) | Implemented | 第 1 阶段：交叉引用与地址符号化扩展到磁盘文件和归档 cache，并接到 `swift-section` 与 RuntimeViewer 的 CLI / MCP；顺带把交叉引用按「我们选的方向」第 6 条拆成核心、ObjC、Swift 三层（真正迁出本库另写提案） |
| [0098 move-cross-reference-layers](../Evolutions/0098-move-cross-reference-layers.md) | Accepted | 「我们选的方向」第 6 条：把 0097 拆出的核心层与地址解析、ARM64 解码搬进 MachOKitExtensions，ObjC 层搬进 MachOObjCSection，随本库 0.25.0 落地 |
| [draft-cross-reference-recall-gaps](../Evolutions/draft-cross-reference-recall-gaps.md) | Accepted | 第 1 阶段的补漏：按「我们选的方向」第 1 条的复测（2026-11-26，90.3% 对 IDA 97.0%）补上四处缺口——CLI 按 Swift 类型查询、取 GOT 槽地址的类引用、selector 引用、一种 ivar 读法，并把取函数地址记成对函数的引用；测量脚本进仓库作为第 7 条「标准答案」的验收工具 |

---

> **愿景是活文档**，随认识加深可以修订，修订时更新「最后更新」。
> 这一点与提案不同 —— 提案是决策快照，落地后保持原貌不改。
>
> 方向被推翻时，状态改为 `Superseded`（并指向取代它的愿景）或 `Abandoned`（并写明为什么放弃），
> **文档保留不删** —— 它是「当初为什么往那个方向走」的唯一记录。
