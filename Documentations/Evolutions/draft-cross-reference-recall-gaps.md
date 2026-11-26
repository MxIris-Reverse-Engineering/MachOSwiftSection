# Draft - 交叉引用补漏：按 Swift 类型查询、GOT 槽地址、selector 引用与 ivar 读法

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-26
- **最后更新**: 2026-11-26
- **所属愿景**: [不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)（第 1 阶段的补漏）
- **关联提案**: [0097-offline-cross-references-and-symbolication](0097-offline-cross-references-and-symbolication.md)（离线交叉引用与这次复测的对象）、[0098-move-cross-reference-layers](0098-move-cross-reference-layers.md)（三层的归属）、RuntimeViewer [0056-cross-references](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer/blob/next/Documentations/Evolutions/0056-cross-references.md)（界面与查询层）
- **实现分支 / PR**: `feature/cross-reference-recall-gaps`（MachOKitExtensions、MachOObjCSection、本库、RuntimeViewer 同名分支；worktree 为各仓库的 `.worktrees/<项目名>-CrossReferenceRecallGaps`）
- **配套文档**: 不另写——调用方契约在 CLI 的 skill（`AgentPlugins/swift-section/skills/swift-section-cli/references/cross-references.md`）与 README，实现细节在三份模块文档；测量办法在 `Scripts/CrossReferenceRecall/README.md`
- **网页版**: 同目录同名的 `.html`

## 摘要

2026-11-26 在 Finder 26.5.2 与 ControlCenter 26.7 上按 2026-11-18 的方法复测交叉引用的召回：`swift-section refs` 0.25.0 找到 527 条代码引用里的 476 条（90.3%），IDA 一次查询 97.0%、两跳 99.4%。漏掉的 51 条里，13 条是按设计不报的 `__objc_superrefs` 载入，其余 38 条来自四处缺口：CLI 没有按 Swift 类型查的入口（27 条）、Swift 代码把 ObjC 类的 GOT 槽地址交给编译器生成的元数据辅助函数时不认类引用（8 条）、selector 只被当作参数用时不报（2 条）、一种 ivar 偏移的读法漏记（1 条）。本提案补齐这四处，改动跨 MachOKitExtensions（核心层）、MachOObjCSection（ObjC 层）、本库（Swift 层、门面与 CLI）和 RuntimeViewer（两处穷尽 switch），并把这次的测量脚本收进本库当验收工具：补完后同一组样本应到 514/527（97.5%），剩下的 13 条就是 `super` 的载入。第 5 步还把「取函数地址」记成对函数的引用——它不在这次测量的类别里，但决定了调用链能不能穿过 block 与闭包。

## 动机

完整动机见愿景《[不依赖 IDA 的逆向](../Visions/ReverseEngineeringWithoutIDA.md)》。这一步特有的部分：

- **0097 落地时没有做全面核对。** 0097 决策日志 2026-11-19「第 4 步完成」一行只抽样了 ControlCenter 的 3 个函数，「全面核对没有重做」一段说明生成标准答案的脚本已经不在卷上。2026-11-26 从 2026-11-18 那次对比的对话记录里原样取回了标准答案与选目标的代码，复现出同一批 120 个目标，补做了这次核对（方法与数字见「前期调研」，结论写进了愿景「我们选的方向」第 1 条的复测段）。
- **差距集中在几处可以修的地方，而不是扫描整体不行。** 导入函数、内部 `bl`、字符串三类与 IDA 一样全中；selector 发送（95/97）与类引用里的页对齐类对象还比 IDA 一次查询多中几条。漏报按原因归成五组，每组都有具体地址（见「前期调研」）。
- **影响面比样本里的条数大。**
  - GOT 槽地址那一组：ControlCenter 里有 554 处 `bl 0x10000b4a8`，每一处都把一个 ObjC 类的 GOT 槽地址放进 `x2`。这是 Swift 代码取 ObjC 类元数据的通用写法，Swift 为主的镜像里按类查引用会整批漏掉这一类。
  - Swift 类型那一组：经 CLI 工作的 agent 现在根本问不了「哪些代码用到了 Swift 类型 X」，只有 RuntimeViewer 的界面能问（Find 导航页的 Type References）。
  - selector 那一组：`respondsToSelector:` 的参数、返回 selector 的函数；`performSelector:`、target-action 的 `setAction:` 也是同一形态（推测，样本里没有抽到）。逆向时「谁把这个方法设成了按钮的 action」是常见问题。

## 前期调研

### 测量方法与复现

- **样本**：`/Volumes/RE/Finder/26.5.2/Finder`（ObjC 为主）与 `/Volumes/RE/ControlCenter/26.7/ControlCenter`（Swift 为主）的 arm64e 切片，UUID 分别是 `1E2E81F7-9B9D-317A-A102-F55ADAF6A0A0`、`5782ED6B-471B-3CAC-9258-93734B6009C3`，与卷上两个 `.i64` 相同。
- **标准答案**：不依赖任何一个被测工具，由 `otool -tV` 加独立的 `adrp` 寄存器跟踪、`dyld_info -fixups`、相对方法列表与 `__swift5_types` 解码生成。代码从 2026-11-18 那次对比的子 agent 对话记录（`~/.claude/projects/-Users-JH/4cad8a68-…/subagents/agent-a43f33e89a2f7bb07.jsonl` 的第 24、31、51、56 次工具调用）原样取回，只换了临时目录。
- **复现核对**：两份标准答案的引用总数（511,138 与 359,773）、`__objc_stubs` 数（8,809 与 1,363）、各类目标列表与 2026-11-18 的输出逐项一致；按原打分规则（第 69 次工具调用）重算 IDA 一列，仍是 97.0% / 99.4%。所以这次的数字可以直接与那次比。
- **查询**：每个目标调一次 `swift-section refs <文件> --json`（`--selector`、`--class`、`--symbol`、`--function`、`--string`、`--ivar`），共 128 次，零报错；Finder 单次中位 0.31 秒、ControlCenter 0.13 秒，都含建分析器的时间。外部类另加一次 `--symbol _OBJC_CLASS_$_<类>`，结果与只查 `--class` 相同，说明 `--class` 已经覆盖导入的类。
- **脚本**：在 `/tmp/claude-xref-2026-11-26/scripts/`（`run_all.sh` 一条命令跑完，约 30 秒）。`/tmp` 会被系统清理，所以落地步骤第 0 步先把它们收进本库；万一已被清掉，可从 2026-11-26 那次会话的对话记录里取回（脚本都是用 Write 工具写的）。

### 分类别结果（两个镜像合计，代码引用）

| 类别 | 标准答案 | IDA 一次 | IDA 两跳 | 本库 0.25.0 |
|---|---|---|---|---|
| A selector 发送 | 97 | 92 | 97 | 95 |
| B ObjC 类引用 | 87 | 76 | 84 | 66 |
| C 导入函数 | 91 | 91 | 91 | 91 |
| D 内部函数 `bl` | 70 | 70 | 70 | 70 |
| E 字符串 | 46 | 46 | 46 | 46 |
| F ivar（仅 Finder） | 32 | 32 | 32 | 31 |
| G Swift 元数据访问器（仅 ControlCenter） | 104 | 104 | 104 | 77 |
| 合计 | 527 | 97.0% | 99.4% | 90.3% |

另有 49 条数据引用（方法表的 IMP、只在 vtable / 见证表里出现的函数、GOT 槽本身等），IDA 全中，本库按 0097 的非目标不做，记 0。本库多报 1 条：`0x1005273f8 ldr x0, [x20]`，是先 `adrp; add x20, <NSAppleEventDescriptor 的 GOT 槽>` 再经 `x20` 载入，标准答案的线性跟踪把这条引用记在 `add` 上，核对后是真引用。

### 51 条漏报的五组原因

1. **取访问器地址当函数指针用（27 条，G 类）。** 形如 ControlCenter `0x1000cd564`：`adrp x16, …; add x16, x16, #0xd38`（访问器 `0x1003e3d38`）→ `mov x17, #0x882f; pacia x16, x17; mov x1, x16`，把签过名的访问器地址交给调用方。分析器其实记下了：`refs --function=0x1000cd568 --callees` 显示 `0x1000cd568 reference addressMaterialization swiftType`（Swift 会话把访问器地址认领为类型引用，见 `CrossReferenceAnalysis.md`「Swift 类型引用」第 2 种来源）。漏在 CLI：`--function` 只返回调用者，而 `ReferencesRequest`（`Sources/Commands/SwiftSectionKit/CrossReferences/ReferencesRequest.swift:262-310`）的六种主体里没有 Swift 类型。Swift 类型的引用表按描述符位置归档（`CodeReferenceTable.Key.swiftTypeDescriptor`），查询要经比对器 `references(toSwiftType:inImageAt:)`（`Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer+SwiftTypes.swift:57`），不能像其它主体那样换成表键。
2. **`__objc_superrefs` 的载入（13 条，B 类，按设计）。** Finder `0x1006604a0 ldr x8, [x8, #0x358]` 读的是 `__objc_superrefs` 的 `0x100b4b358`，随后 `stp x0, x8, [sp]` 拼出 `objc_super` 交给 `_objc_msgSendSuper2`。13 条全是这种。`CrossReferenceAnalysis.md`「类引用（第二批）」写明这一载入不算类引用（「报出来只会让每个调 `super` 的方法都『引用』了自己的类」），引用记成带类名的 `superMessageSend`。标准答案把 `__objc_superrefs` 算作类引用的槽（2026-11-18 的报告「经 `__objc_superrefs` 加载类对象，这类已并入 ground truth」）。
3. **GOT 槽地址交给元数据辅助函数（8 条，B 类）。** ControlCenter `0x1006455c8`：`adrp x2, …; add x2, x2, #0x2a0`（`_OBJC_CLASS_$_OS_os_log` 的 GOT 槽 `0x10083a2a0`）→ `mov x0, #0; bl 0x10000b4a8`。`0x10000b4a8` 是编译器生成的共用辅助函数：`ldr x0, [x1]; cbnz …; ldr x0, [x2]; bl _objc_opt_self; bl _swift_getObjCClassMetadata; stlr x0, [x19]`——`x1` 是缓存变量，`x2` 是类的 GOT 槽。ControlCenter 里有 554 处调用它。核心层 `ReferenceScanner.noteAddress`（MachOKitExtensions `Sources/Analysis/MachOCodeReferences/Scanning/ReferenceScanner.swift:366`）把数据段里的地址交给会话的 `recordAddressReference`，ObjC 会话只认类对象本身（MachOObjCSection `Sources/ObjCCodeReferences/ObjCCodeReferenceRecognizer.swift:305`），GOT 槽的地址不是类对象，于是什么都不记。读槽的入口 `noteSlotReference(fromSlot:at:)`（`ReferenceScanner.swift:441`）已经能解本镜像的 GOT、classref、cache 的共用 GOT 池与独立文件的 bind，只是取槽地址的路径没有走到它。IDA 也要两跳（2026-11-18 报告的 IDA 漏报第 2 条，同一个 `0x1006455cc`）。
4. **selector 只当参数用（2 条，A 类）。** Finder `0x1003ee048`：`adrp x8, …; ldr x1, [x8, #0x6d0]`（`coalescingNodeObserver:openSyncCompleted:` 的 selref）→ `mov x0, x19; bl _objc_opt_respondsToSelector`；ControlCenter `0x100674e00`：`adrp x8, …; ldr x0, [x8, #0x378]; ret`，一个返回 selector `name` 的函数。ObjC 会话只在发送时从 `x1` 的来源槽读出 selector（`selectorInSelectorRegister`），它观察的槽只有 `__objc_superrefs` 与 `__objc_ivar`（`ObjCCodeReferenceRecognizer.swift:209`），没被发送用掉的 selref 载入什么都不留。`objc_opt_respondsToSelector` 作为 libobjc 的发送入口记成一次 `respondsToSelector:` 发送（`recordCallStandIn` 的 `.entryPoint`），`x1` 里那个作参数的 selector 被丢掉。
5. **`adrp; add` 之后 `ldrsw [xN]` 读 ivar 偏移（1 条，F 类，原因待查）。** Finder `-[TTaskErrorOrConflictViewController setResolutionsForKind:]` 的 `0x1002bbb14`：`adrp x9, …; add x9, x9, #0x28; ldrsw x9, [x9]; str w8, [x0, x9]`（ivar `_rightResolution`）。同一个 ivar 在别的函数里的两处 `adrp; ldrsw [x8, #imm]` 都找到了，同一函数里别的 ivar 的 11 处也都找到了。读代码排除了几种可能：机器码 `d00047a9 9100a129 b9800129` 都在解码器覆盖内（`ARM64InstructionWord.wordLoad` 认 `0xB980_0000`，`addImmediate` 认 `0x9100_0000`）；函数起点表里 `0x1002bba08`–`0x1002bbb28` 是一个函数；`RegisterFile.add` 对 `.address` 状态的源寄存器给出 `.address`。`0x1002bbb14` 是三条 `b` 的共同目标、又从上一条顺序落下，是汇合点——推测问题与汇合处的寄存器状态有关，未证实。第 4 步先写复现测试再定位。

### 赢过 IDA 的地方

- Finder 的三个页对齐类对象（`adrp; add #0x0`，如 `0x100131f8c`）IDA 漏，本库一次查到。
- 经 `ldr` 读 selref 的经典发送，本库一次查到；IDA 要再查 selref 一跳（A 类 IDA 一次 92、本库 95）。
- 不需要先建 IDA 库；单次查询 0.1–0.3 秒。

### 相关的现成能力

- RuntimeViewer 按类型查引用时用类型的 mangling（`RuntimeObject.name`，如 `7SwiftUI4TextV`）找描述符：`swiftTypeDescriptorLocations(withKey:inImageAt:)` → `swiftTypeIdentity(ofDescriptorAt:)` → 预筛 `imageIndices(referencingSwiftType:among:)` → 每个候选镜像 `references(toSwiftType:inImageAt:)`（RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift:300-380`）。CLI 照搬这条路即可，写法也与它一致。
- 按名字定位符号：`locations(ofSymbolNamed:among:)`（`CrossReferenceAnalyzer+Linkage.swift:11`），查 `$s…Mn` 比逐镜像算 key 快得多。
- 核心层的读槽、槽认领缓存（`slotClaims`）与导入名（`importedSlotNames`）都现成。寄存器表有按寄存器的标记（`RegisterFile.setTag` / `tag(of:)`，ObjC 会话用它标方法接收者），但打标记会把寄存器改成 `.tagged` 状态、丢掉地址（`RegisterFile.swift:83`），不能拿来标「已记过」；按寄存器的位掩码（`constantMask`、`blendedMask`）是现成的另一种写法。
- 下游穷尽 switch：RuntimeViewer `CrossReferenceQuery.swift` 的 `switch reference.target`（`:92`、`:727`）与 `switch target`（`:949`）。0097 加三种新目标时的做法是在 RuntimeViewer 里补 case、先不显示（0097「源码兼容性」一节与决策日志 2026-11-19「第 8 步完成」）。

## 提议方案

1. **CLI 加 `--type`。** `swift-section refs --type <mangling>` 列出对一个 Swift 结构体、枚举或类的全部引用，写法与 RuntimeViewer 相同：类型的 mangling（`7SwiftUI4TextV`），也收它的描述符、访问器或元数据符号（`$s…Mn`、`$s…Ma`、`$s…N`，前面的 `_` 可有可无），去掉前后缀得到 mangling。定义它的镜像先按 `$s<mangling>Mn` 符号在全部镜像里找；找不到（缓存里的内部类型没有这个符号）时，独立文件逐个镜像按 key 找，dyld cache 要求用 `--type-image` 指定镜像，否则报错并提示。结果是这些身份在各候选镜像里的 `references(toSwiftType:inImageAt:)` 之并。
2. **取到引用槽地址也算一次槽引用（核心层）。** `adrp; add` 或 `adr` 算出的地址如果正好落在引用槽上（本镜像的 GOT 与会话报的引用节，或 cache 的共用 GOT 池），就在这条指令上按读槽处理：走 `noteSlotReference(fromSlot:at:)`，路线记 `.pointerSlot`，由会话认出类，或在独立文件里记成导入符号。寄存器记下「已作为槽引用记过」，之后经它做零位移载入时不再重记，免得 `adrp; add; ldr [x]` 在同一处用法上记两行；寄存器里的地址照常保留，后面的发送仍能认出类字面量接收者。与语言无关，不写任何运行时名字。
3. **selector 引用（ObjC 层）。** 查询里含 selector 键时，ObjC 会话也观察 `__objc_selrefs` 的载入：每次载入先记为待定；经典发送或 `super` 发送用 `x1` 里这个 selector 发送时，把它消掉；离开函数时，没被消掉的记成 selector 引用（新目标 `CodeReferenceTarget.selector(String)`，种类 `.reference`），归在已有的 `.selector` 表键下，`--selector` 因此同时返回发送与引用。libobjc 的发送入口（`objc_opt_respondsToSelector` 等）不消掉它，那里的 `x1` 是参数。核心层的会话协议加一个 `leaveFunction()`，默认什么都不做。经 `__objc_stubs` 的发送在代码里不载入 selref，不受影响。
4. **ivar 读法（核心层）。** 先用夹具编出这段指令写复现测试，确认修复前失败，再定位、修复。
5. **取函数地址记成对函数的引用（核心层）。** `adrp; add` 或 `adr` 算出的地址正好是本镜像函数表里的一个函数起点时，记一条 `.reference`，目标是 `.function(location)`，路线 `.addressMaterialization`；会话同时认领它（Swift 访问器）时两条都记。只在查询含函数键或建整表时找。`--function` 和 RuntimeViewer 的调用层级因此会列出取了它地址的代码：建栈上 block 的函数、把回调传给 `dispatch_async` / `CFRunLoop` 的函数、返回闭包的函数。这一步不在这次测量的类别里，用户决定并入（见决策日志）。
6. **测量脚本进仓库，作为验收。** 收进 `Scripts/CrossReferenceRecall/`，`03_query_swift_section.py` 对 G 类改用 `--type`（mangling 取自访问器的符号名）；落地时重跑，结果写回愿景。

### 非目标

- **`__objc_superrefs` 的载入不算类引用**：0097 定下的理由不变（见「替代方案考量」）。这 13 条是验收目标与 100% 之间的差。
- **数据引用**（方法表的 IMP、vtable 与见证表里的函数、函数指针表、GOT 槽本身作为被引用者）：愿景第 3 阶段。
- **按点分隔的 Swift 名字查类型**（`ControlCenter.Foo`）：要知道每一层的种类（结构体、类、枚举）才能拼出 mangling，先只收 mangling 与符号。
- **RuntimeViewer 显示 selector 引用**：先在两处 switch 里补 case 并过滤掉，与 0097 处理新目标的做法一致；界面上怎么显示另提。第 5 步若并入，调用层级里取地址的行会和调用行一样显示，区分显示也另提。
- **按辅助函数形状认 ObjC 类**（见「替代方案考量」）。
- **x86_64**；**Binary Ninja 一列不重测**（2026-11-18 的结论是它经 MCP 只有 67.6%，不作参照）。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| 本库 `Scripts/CrossReferenceRecall/`（`prepare.sh`、`ground_truth.py`、`verify_reproduction.py`、`query_swift_section.py`、`score.py`、`run_all.sh`、`ida-2026-11-18.txt`、`README.md`） | 新增 | 2026-11-26 的测量脚本，按完整命名改写；IDA 的逐类结果存成数据文件；README 写样本路径、怎么跑、怎么读结果、基线数字 | 验收工具不能再丢 | 0 |
| 本库 `Scripts/CrossReferenceRecall/query_swift_section.py` | 新增 | 被测的二进制由 `SWIFT_SECTION` 指定；G 类仍用 `--function`（决策日志 2026-11-26「验收时 G 类仍用 `--function`」） | 验收 | 0 |
| 本库 `Sources/Commands/SwiftSectionKit/CrossReferences/ReferencesRequest.swift` · `CrossReferenceSubject` | 修改 | 加 `.swiftType(String, imageName: String?)`；`ResolvedQuery` 加按类型的查询分支；写法归一与定义镜像的查找 | `--type` 的库侧 | 1 |
| 本库 `Sources/Commands/SwiftSectionKit/CrossReferences/ReferencesRequest.swift` · `CrossReferenceRequestError` | 修改 | 加 `swiftTypeNotFound(String)`、`swiftTypeNeedsImage(String)` | 找不到类型、缓存里的内部类型 | 1 |
| 本库 `Sources/Executables/swift-section/Commands/ReferencesCommand.swift` | 修改 | `--type`、`--type-image`；`validate()` 计入新主体；`--selector` 的帮助文字改成「发送与引用」 | CLI 入口 | 1、3 |
| 本库 `Sources/Executables/swift-section/…/CommandLineErrorTranslation` | 修改 | 两个新错误的措辞 | 用法错误照旧是退出码 64 | 1 |
| 本库 `Sources/Commands/SwiftSectionKit/CrossReferences/CrossReferenceFormatting.swift` | 修改 | `.selector` 目标的文字（`selector <名字>`）与 JSON（`{"selector": …}`） | 新目标的输出 | 3 |
| 本库 `Sources/Analysis/CrossReferenceAnalysis/Models/CodeReference.swift` · `CodeReferenceTarget` | 修改 | 加 `case selector(String)` | selector 引用的目标 | 3 |
| 本库 `Sources/Analysis/CrossReferenceAnalysis/Models/CodeReferenceTable.swift` | 修改 | `.selector` 目标归 `.selector` 键 | `--selector` 与 RuntimeViewer 的 selector 查询都能取到 | 3 |
| 本库 `Sources/Analysis/CrossReferenceAnalysis/Models/CodeReferenceIndex.swift` · `Target` | 修改 | 常驻索引加 `.selector` 组 | RuntimeViewer 常驻用的紧凑索引要能存 | 3 |
| 本库 `Sources/Analysis/CrossReferenceAnalysis/CrossReferenceAnalyzer.swift` · `ReferenceCollector` | 修改 | 实现 `recordSelectorReference`；`findsSelectorReferences`（键含 `.selector` 或建整表）传给 ObjC 会话；第 5 步实现 `recordFunctionAddressReference` 与开关 | 门面拼装 | 3、5 |
| 本库 `Sources/Analysis/CrossReferenceAnalysis/Symbolication/AddressSymbolication.swift` | 修改 | selref 槽的含义从 `.messageSend(selector:receiver: .unknown)` 改为 `.selector` | 0097 第 6 步留的说明「目标类型里没有单独的 selector」不再成立 | 3 |
| 本库 `AgentPlugins/swift-section/skills/swift-section-cli/references/cross-references.md`（及 `SKILL.md` 里列到 `refs` 选项的地方） | 修改 | `--type`、`--type-image`、selector 引用、取槽地址的类引用；第 5 步的取地址行 | 项目规定：改 CLI 同批改 skill | 1、3、5 |
| 本库 `README.md` 的 `refs` 一节 | 修改 | 加 `--type` 的例子 | 对外文档 | 1 |
| 本库 `Tests/SwiftSectionKitTests/…`（新文件 `ReferencesRequestSwiftTypeTests.swift`） | 新增 | `--type` 的解析、写法、错误 | 第 1 步行为 | 1 |
| 本库 `Tests/CrossReferenceAnalysisTests/…`（新文件 `SelectorReferenceTests.swift`、`SlotAddressReferenceTests.swift`，第 5 步 `FunctionAddressReferenceTests.swift`） | 新增 | 经门面的行为测试 | 各步行为 | 2、3、5 |
| 本库 `Documentations/Internal/Modules/CrossReferenceAnalysis.md` | 修改 | 引用种类、类引用、selector、`--type`、测试锚点；召回一节指向愿景 | 总说明 | 1–5 |
| 本库 `Documentations/Visions/ReverseEngineeringWithoutIDA.md` | 修改 | 复测段（本批已写）；落地后补上修复后的数字 | 愿景是活文档 | 6 |
| MachOKitExtensions `Sources/Analysis/MachOCodeReferences/Scanning/ReferenceScanner.swift` · `noteAddress` | 修改 | 落在引用槽上的地址改走 `noteSlotReference`；需要知道目标寄存器，签名加 `destination` | 第 2 步 | 2 |
| MachOKitExtensions `ReferenceScanner.swift` · `scanFunction` 的载入分支 | 修改 | 经已记过槽引用的寄存器做零位移载入时不重记 | 防重复 | 2 |
| MachOKitExtensions `ReferenceScanner.swift`（具体位置待第 4 步的测试定位） | 修改 | 修 ivar 漏记 | 第 4 步 | 4 |
| MachOKitExtensions `ReferenceScanner.swift` · `noteAddress` | 修改 | 落在函数起点的地址记成对函数的引用 | 第 5 步 | 5 |
| MachOKitExtensions `Sources/Analysis/MachOCodeReferences/Scanning/RegisterFile.swift` | 修改 | 加一个按寄存器的位 `recordedSlotMask`：这个地址已作为槽引用记过；改写寄存器时清掉，汇合时比较 | 防重复，且不丢地址（现成的 `setTag` 会把地址状态覆盖掉） | 2 |
| MachOKitExtensions `Sources/Analysis/MachOCodeReferences/Recognition/CodeReferenceRecognition.swift` · `CodeReferenceRecognitionSession` | 修改 | 加 `func leaveFunction()`，协议扩展给空实现；扫描器在每个函数扫完时调用 | selector 待定载入的冲刷点 | 3 |
| MachOKitExtensions `CodeReferenceRecognition.swift` · `CodeReferenceRecording` | 修改 | 加 `recordFunctionAddressReference(toFunctionAt:at:)` | 第 5 步 | 5 |
| MachOKitExtensions `Tests/MachOCodeReferencesTests/…`（新文件 `ScanShapesFixture.swift`、`SlotAddressScanTests.swift`、`InstanceVariableMergePointTests.swift`、`FunctionAddressScanTests.swift`；测试目标加 `MachOFixtureSupport`） | 新增 | 用 `FixtureCompiler` 汇编出夹具库，钉住指令序列 | 复现测试 | 2、4、5 |
| MachOKitExtensions `Documentations/Internal/MachOCodeReferences.md` | 修改 | 新契约与测试 | 实现说明 | 2、4、5 |
| MachOObjCSection `Sources/ObjCCodeReferences/ObjCCodeReferenceRecognizer.swift` · `ObjCCodeReferenceRecording` | 修改 | 加 `recordSelectorReference(selector:at:)` | 第 3 步 | 3 |
| MachOObjCSection `ObjCCodeReferenceRecognizer.swift` · 会话 | 修改 | `findsSelectorReferences` 开关；`watchedSlotRanges` 加 `selectorReferenceRange`；待定载入、发送消掉、`leaveFunction` 冲刷 | 第 3 步 | 3 |
| MachOObjCSection `Tests/ObjCCodeReferencesTests/…`（新文件 `SelectorReferenceRecognitionTests.swift`） | 新增 | ObjC 夹具：`respondsToSelector:`、`setAction:`、经典发送不重复 | 第 3 步 | 3 |
| MachOObjCSection `Documentations/Internal/ObjCCodeReferences.md` | 修改 | selector 引用的认法 | 实现说明 | 3 |
| RuntimeViewer `RuntimeViewerCore/Sources/RuntimeViewerCrossReferences/Analysis/CrossReferenceQuery.swift` | 修改 | `:92`、`:727`、`:949` 三处 switch 补 `.selector`（不显示）；selector 查询结果滤掉 `.selector` 目标 | 穷尽 switch 会编译失败；界面先不变 | 3 |

## 架构图

改了什么（扫描一个函数时的分派，`+` 新增，`~` 修改）：

```text
ReferenceScanner.scanFunction                                   (MachOCodeReferences)
├── adrp/add/adr → noteAddress(address, destination)            ~ takes the register
│   ├── + address in a reference slot (own GOT, classrefs, cache GOT pool)
│   │       → noteSlotReference(fromSlot:) → ObjC session: class │ file mode: imported symbol
│   │       → mark the register: slot address recorded (address kept)
│   ├── + address == a function start   → recording.recordFunctionAddressReference   (step 5)
│   └──   other data → sessions.recordAddressReference                               (unchanged)
├── ldr/ldrsw [base, #d] → noteLoad / noteWatchedLoad
│   ├── + base marked as recorded slot address and d == 0 → skip (no second row)
│   └── ObjC session.noteWatchedSlotLoad
│       ├── __objc_ivar   → ivar reference                       ~ step 4 fixes a miss
│       └── + __objc_selrefs → pending selector load
├── bl <send> → ObjC session.recordCallStandIn
│   ├── classic / super send → messageSend   + consumes the pending load behind x1
│   └── entry point (objc_opt_respondsToSelector …) → send       (x1 stays pending: an argument)
└── + function scanned → session.leaveFunction()
        → ObjC: each pending load left → recordSelectorReference → target .selector(name), key .selector
```

CLI 的查询分支（`+` 新增）：

```text
swift-section refs (ReferencesCommand → SwiftSectionKit.ReferencesRequest)
├── --selector S   → keys [.selector(S)]            → sends + selector references (step 3)
├── --function A   → keys [.function(loc), imported names]  → calls (+ address-taking, step 5)
├── --class / --symbol / --ivar / --string           (unchanged)
└── + --type T [--type-image I]
      → normalize T: strip _ / $s prefix, Mn / Ma / N suffix → mangling key
      → defining images: locations(ofSymbolNamed: "_$s" + key + "Mn")
                         else every image (files) │ else --type-image required (cache)
      → swiftTypeDescriptorLocations(withKey:inImageAt:) → swiftTypeIdentity(ofDescriptorAt:)
      → candidates: imageIndices(referencingSwiftType:among: scope)
      → per candidate image: references(toSwiftType:inImageAt:)  (union over identities)
```

## 详细设计

### 第 1 步：`--type`

```swift
public enum CrossReferenceSubject: Sendable, Hashable {
    // … the six existing cases …
    /// A Swift struct, enum or class by its mangling — `7SwiftUI4TextV` — or a
    /// `$s…Mn`, `$s…Ma` or `$s…N` symbol of it, defined in the image
    /// `imageName` names, or in whichever image exports its descriptor.
    case swiftType(String, imageName: String?)
}
```

```swift
// ReferencesCommand
@Option(name: .customLong("type"), help: "Every reference to the Swift struct, enum or class with this mangling (7SwiftUI4TextV), or to the one a $s…Mn, $s…Ma or $s…N symbol names.")
var swiftType: String?

@Option(name: .customLong("type-image"), help: "The image that defines --type's type, by path or file name: needed in a dyld shared cache for a type no image exports.")
var swiftTypeImage: String?
```

- `validate()`：`--type` 计入「恰好一个主体」；`--type-image` 只能和 `--type` 一起用（与 `--function-image` 同样的报错写法）。
- 写法归一：去掉前导 `_`，去掉前导 `$s`；末尾依次试 `Mn`、`Ma`、`N`，去掉后剩下的部分能 demangle 成一个名义类型才算数，否则当作原样的 mangling。名义类型的 mangling 以种类字母（`V`、`C`、`O`，`__C` 类型的 `a` 等）结尾，不会被误剥。
- 找定义镜像：`--type-image` 给了就只在它里面找；否则 `locations(ofSymbolNamed: "_$s" + key + "Mn", among: 全部镜像)`；仍然没有时，独立文件逐个镜像 `swiftTypeDescriptorLocations(withKey:inImageAt:)`，dyld cache 抛 `swiftTypeNeedsImage`（逐镜像算 key 要几分钟）。macOS 与 Mac Catalyst 两个变体都定义时，两个身份都查，结果取并集。
- 查询：`ResolvedQuery.Search` 加 `case swiftTypes([SwiftTypeIdentity], candidates: [Int])`；`run(output:)` 在候选镜像上并发调 `references(toSwiftType:inImageAt:)`，与 `.callers` 的并发写法相同（`ReferencesRequest.swift:142`）。`--in-image` 照旧限定扫描范围。
- 输出：目标照已有的 `swiftType` / `swiftTypeName` / `objectiveCClass`（Swift 类也比它的 ObjC 类对象位置）格式输出，不新增格式。

### 第 2 步：取到引用槽地址

```swift
// ReferenceScanner (MachOCodeReferences)
private mutating func noteAddress(_ address: UInt64, builtInto destination: Int, at site: ScanSite, mayNameAString: Bool) {
    if isReferenceSlot(address) {
        noteSlotReference(fromSlot: address, at: site.reached(by: .pointerSlot))
        registers.markRecordedSlotAddress(of: destination)
        return
    }
    // … unchanged …
}

/// A slot of this image's GOT or of a session's reference sections, or one
/// of the GOT pool the shared cache keeps outside every image.
private func isReferenceSlot(_ address: UInt64) -> Bool
```

- `isReferenceSlot` 复用 `noteSlotReference` 开头的判断（`referenceSlotRanges` 与 `images.isSlotOutsideEveryImage`），两处共用一个私有函数，免得以后只改一处。
- 载入分支：`load.displacement == 0` 且 `registers.isRecordedSlotAddress(load.base)` 时不调 `noteLoad`，寄存器照常更新（目标寄存器仍是 `.loadedFromSlot`，类字面量接收者照认）。
- `RegisterFile` 的 `Contents` 加 `recordedSlotMask`，与 `constantMask` 同样处理：`overwrite` 清位，`Snapshot.agrees` 比较它，`meet` 不一致时清掉。不用现成的 `setTag`：它把寄存器改成 `.tagged` 状态，地址就没了（`RegisterFile.swift:83`）。
- 只在 `looksForAddressReferences` 为真时做，与现状一致：只查 selector 或函数时不付这份代价。

### 第 3 步：selector 引用

```swift
// MachOObjCSection, ObjCCodeReferences
@_spi(Internals) public protocol ObjCCodeReferenceRecording: CodeReferenceRecording {
    // … existing …
    /// A load of the selector reference to `selector` that no send used:
    /// the selector handed on as data — to `respondsToSelector:`,
    /// `performSelector:`, a control's action.
    func recordSelectorReference(selector: String, at site: ScanSite)
}
```

```swift
// MachOKitExtensions, MachOCodeReferences
@_spi(Internals) public protocol CodeReferenceRecognitionSession: AnyObject {
    // … existing …
    /// The scan is done with the function it last entered.
    func leaveFunction()
}

extension CodeReferenceRecognitionSession {
    @_spi(Internals) public func leaveFunction() {}
}
```

```swift
// MachOSwiftSection, CrossReferenceAnalysis
public enum CodeReferenceTarget: Hashable, Sendable {
    // … existing …
    /// A selector the code loads but sends no message with: it hands the
    /// selector on — to `respondsToSelector:`, `performSelector:`, a
    /// control's action.
    case selector(String)
}
```

- ObjC 会话：`findsSelectorReferences` 为真时 `watchedSlotRanges` 加上 `sections.selectorReferenceRange`（`ObjCImageSections` 已有这个字段）。`noteWatchedSlotLoad` 落在它上面时读出 selector 名，追加到 `pendingSelectorLoads: [(slot: UInt64, site: ScanSite)]`。
- 消掉：`recordCallStandIn` 的 `.classicSend` 与 `.superSend` 分支取 `registers.slotAddress(of: 1)`，从 `pendingSelectorLoads` 末尾往前删掉第一个同槽的条目。`.entryPoint` 与 `.selector`（`__objc_stubs`）不删。
- 冲刷：`leaveFunction()` 把剩下的逐条交给 `recordSelectorReference`，清空数组。`enterFunction` 也清一次，防扫描器提前返回时漏冲刷（`scanFunction` 的 `guard` 早退）。
- 顺序：冲刷发生在函数末尾，所以一个函数里 selector 引用排在该函数的其它引用之后；收集器按地址排序后输出，不影响结果顺序（实现时核对 `ReferenceCollector` 是否排序，若不排则在冲刷前按地址插入）。
- 门面：`ReferenceCollector.findsSelectorReferences` = 查询键含 `.selector`，或建整表。`recordSelectorReference` → `keep(.selector(selector), at: site)`；`CodeReferenceTable` 把它归在 `.selector(selector)` 键下。
- 符号化：selref 槽的含义改为 `.selector(name)`（`AddressSymbolication.swift`），`swift-section symbolicate` 对 selref 槽的输出从 `send <名字>` 变成 `selector <名字>`。

### 第 4 步：ivar

- 夹具：一个 ObjC 类，三个 ivar；一个方法用 `__asm__` 写出与 Finder `0x1002bba08` 同构的序列——前面几个分支 `b` 到同一个标签，标签处 `adrp x9, _OBJC_IVAR_$_…@PAGE; add x9, x9, _OBJC_IVAR_$_…@PAGEOFF; ldrsw x9, [x9]; str w8, [x0, x9]`。另写一个不经汇合点的对照方法。
- 测试先红（经汇合点的那条找不到、对照那条找到），由此确认是汇合还是别的原因，再修。
- 结果（实现时补记）：根因与修法见决策日志 2026-11-26「第 4 步定位到根因」。夹具改为两条路径各算一个偏移变量地址、在载入处汇合；对照方法的引用记在 `add` 上而不是 `ldrsw` 上。

### 第 5 步：取函数地址

```swift
// MachOKitExtensions, CodeReferenceRecording
/// Code built the address of the function at the unslid `address` — to call
/// it later, sign it and hand it on, or put it in a block.
func recordFunctionAddressReference(toFunctionAt address: UInt64, at site: ScanSite)
```

- `noteAddress` 里 `isCode` 且这个地址是函数起点时记一条；会话随后照常被问（Swift 会话认领访问器，两条都记）。开关 `recordsFunctionAddressReferences` 由门面按查询键（含 `.function`）或建整表给出。
- 判断是不是函数起点：`ImageFunctionTable.functionIndex(containing:)`（`ImageFunctionTable.swift:249`）取到的函数起点等于这个地址。
- 门面把它记成 `kind == .reference`、目标 `.function(location)`，归 `.function` 键。

## 替代方案考量

- **只让 `--function` 查访问器时也返回类型引用，不加 `--type`**：能补上这 27 条，但只覆盖访问器；泛型实例的访问器、按 mangled name 实例化、元数据地址这几种类型引用仍然问不到，而 RuntimeViewer 早已按类型查。否。
- **GOT 槽地址按辅助函数的形状认**：在 Swift 层认出 `ldr x0, [x2]; bl objc_opt_self; bl swift_getObjCClassMetadata` 这种函数，在调用点从 `x2` 取类。更准，但只覆盖这一个辅助函数，还要 Swift 层认 libobjc 的名字；核心层按「地址落在引用槽」处理与语言无关，覆盖一切先取槽地址再用的写法。否。
- **每次 selref 载入都记一条引用**：实现最简单，但经典发送（不走 `__objc_stubs` 的二进制）每次发送都会多一条同位置的引用行。否。
- **selector 引用另开一个表键**：`--selector` 就要查两个键，RuntimeViewer 的 selector 查询也要改；归在同一键下、靠目标区分更省事，下游想只要发送时按目标过滤即可。否。
- **把 `__objc_superrefs` 的载入报成类引用**：召回能到 100%、与 IDA 对齐，但每个调 `super` 的方法都会「引用」自己的类，按类查引用的结果会被这些行淹没（Foundation 1,803 处、AppKit 8,336 处 super 发送，见 `CrossReferenceAnalysis.md`「类引用」）。0097 的理由仍然成立。否。
- **测量脚本放在 `/Volumes/RE` 或个人目录**：2026-11-18 那次就是这样丢的。进仓库、跟着交叉引用的代码走。否。

## 影响

### 源码兼容性（source compatibility）

**有破坏**：

- `CodeReferenceTarget` 加 `case selector(String)`：下游对它的穷尽 switch 编译失败。已知调用点是 RuntimeViewer `CrossReferenceQuery.swift` 的 `:92`、`:727`、`:949`。改法：

  ```swift
  // before
  switch reference.target {
  case .function(let location): …
  // … every case …
  case .constantString(let characters): …
  }
  // after: one more case, shown as nothing for now
  case .selector:
      return nil
  ```

- `CrossReferenceSubject`（SwiftSectionKit）加 `case swiftType`：本库以外没有使用方（RuntimeViewer 用自己的查询层）。
- MachOKitExtensions 与 MachOObjCSection 的改动全在 `@_spi(Internals)` 接口上（`CodeReferenceRecognitionSession.leaveFunction` 有默认实现；`ObjCCodeReferenceRecording` 与 `CodeReferenceRecording` 各加一个要求，实现方只有本库的 `ReferenceCollector` 与 MachOKitExtensions 测试里的识别器）。SPI 不承诺稳定（`MachOCodeReferences.md`「接口只给 MachOSwiftSection 用」）。
- 行为变化（不是编译错误）：`--selector` 与 RuntimeViewer 按 selector 的查询多出 `.selector` 目标的行（RuntimeViewer 先滤掉）；按类查引用多出取槽地址的行；`symbolicate` 对 selref 槽的说法变了；第 5 步若并入，`--function` 与调用层级多出取地址的行。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`CrossReferenceAnalysis`、`SwiftSectionKit`、`swift-section` 可执行文件，以及 `CrossReferenceAnalysisTests`、`SwiftSectionKitTests`。整表变大（多出取槽地址、selector 引用，第 5 步再多出取函数地址），`ScanThroughputBenchmarkTests` 要重量。
- MachOKitExtensions（核心层）、MachOObjCSection（ObjC 层）：同批改、同批发版。依赖顺序 MachOKitExtensions → MachOObjCSection → 本库。
- RuntimeViewer：三处 switch；按 0097 的经验，本库 `next` 一合进新 case，RuntimeViewer 的 `next` 要同批跟上（它按本地路径依赖本库）。
- MachOKitUI、REAgent：不用交叉引用（`grep` 过 `CrossReferenceAnalysis`、`ObjCCodeReferences`），不受影响。

### 文档与示例

- `README.md` 的 `refs` 一节、`AgentPlugins/swift-section/skills/swift-section-cli/references/cross-references.md`。
- 三份模块文档：本库 `Documentations/Internal/Modules/CrossReferenceAnalysis.md`、MachOKitExtensions `Documentations/Internal/MachOCodeReferences.md`、MachOObjCSection `Documentations/Internal/ObjCCodeReferences.md`。
- 愿景的复测段，落地后补修复后的数字。

## API 演进与废弃策略

- 没有被替代的 API，不废弃任何东西。
- 版本：本库 0.x 的下一个 minor（`CodeReferenceTarget` 新 case 按 0.x 惯例走 minor，0097 同样处理）；MachOKitExtensions 下一个 minor（SPI 变化，但 MachOObjCSection 要求它的新版本）；MachOObjCSection 下一个 minor。

## 落地步骤

0. **测量脚本进仓库**（已完成） —— 改动地图第 1 行
   - 行为：`run_all.sh` 对 0.25.0 复现 476/527（90.3%），IDA 列 97.0% / 99.4%，复现核对通过
   - 行为：README 记下基线数字与每类的漏报原因，供以后对照
1. **`--type`**（已完成） —— 改动地图第 2–7、13–15 行
   - 行为：`typeSubjectFindsTheReferencesTheAnalyzersSwiftTypeQueryFinds`（与直接调 `references(toSwiftType:)` 的结果逐条相同，在进程内的 SwiftUICore 上）
   - 行为：`typeSubjectAcceptsTheManglingAndItsDescriptorAccessorAndMetadataSymbols`
   - 行为：`typeSubjectLooksForAnUnexportedTypeInEveryStandaloneFile`
   - 行为：`typeSubjectInACacheNeedsTheTypeImageForAnUnexportedType`（报 `swiftTypeNeedsImage`，CLI 退出码 64）
   - 行为：`typeImageWithoutTypeIsAUsageError`
   - 行为：测量脚本 G 类改用 `--type` 后 104/104
2. **取到引用槽地址也算槽引用**（已完成） —— 改动地图第 19–20、22、26 行
   - 行为：`slotAddressHandedToAHelperIsAClassReference`（Swift 夹具引用一个 ObjC 类的元类型，生成同形的辅助函数调用）
   - 行为：`slotAddressInAStandaloneFileIsAnImportedSymbolReference`
   - 行为：`aLoadThroughARecordedSlotAddressIsNotRecordedAgain`
   - 行为：`slotAddressesAddOnlySlotReferencesToTheWholeImageTable`（AppKit、SwiftUICore、Foundation 整表与改前比，多出的只有取槽地址的类引用）
   - 行为：测量脚本 B 类 74/87（剩下的 13 条是 `super`）
3. **selector 引用**（已完成） —— 改动地图第 6、8–12、23、25、28–32 行
   - 行为：`respondsToSelectorArgumentIsASelectorReference`
   - 行为：`anActionSelectorHandedToSetActionIsASelectorReference`
   - 行为：`aClassicSendLeavesNoSelectorReferenceBehind`
   - 行为：`stubSendsLeaveNoSelectorReference`
   - 行为：`selectorQueriesReturnSendsAndSelectorReferences`
   - 行为：`selectorReferencesSurviveTheCompactIndex`
   - 行为：`symbolicationCallsASelectorReferenceSlotASelector`
   - 行为：RuntimeViewer `selectorReferencesAreNotShownYet`
   - 行为：测量脚本 A 类 97/97
4. **ivar 读法**（已完成） —— 改动地图第 21、26–27 行
   - 行为：`instanceVariableLoadThroughAnAddedAddressAtAMergePoint`（修复前失败）
   - 行为：`instanceVariableLoadThroughAnAddedAddressOutsideAMergePoint`（对照）
   - 行为：测量脚本 F 类 32/32
5. **取函数地址**（已完成） —— 改动地图第 23–24 行及第 11、16 行的第 5 步部分
   - 行为：`takingAFunctionsAddressIsAReferenceToIt`
   - 行为：`aSignedAccessorAddressIsBothAFunctionAndATypeReference`
   - 行为：`aStackBlockIsReferencedByTheFunctionThatBuildsIt`
   - 行为：`functionQueriesReturnCallsAndAddressTakingSites`
6. **验收与文档**（已完成） —— 改动地图第 17–18 行与三份模块文档
   - 行为：测量脚本代码引用 ≥ 514/527（97.5%），多报为 0，或逐条核对为真引用
   - 行为：`ScanThroughputBenchmarkTests` 各项比改前慢不超过 5%（超过就把数字和原因写进模块文档，由用户定）
   - 行为：愿景复测段补上修复后的数字

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不另写：调用方契约写进 CLI 的 skill 与 README，实现细节写进三份模块文档。
- **有没有引入新术语** —— 「selector 引用」（selector 被载入但没有用来发送）可能要登记进 `Documentations/Glossary.md`；落地时判断。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-26 | Created as Draft | 按 2026-11-18 的方法补做 0097 落地时没做的全面核对：本库 90.3%、IDA 一次查询 97.0%。用户批准写一份提案修复测出的四处缺口，并把结果写进愿景 |
| 2026-11-26 | 第 5 步列为待定 | 「取函数地址」不在这次测量的类别里，但决定调用链能不能穿过 block 与闭包；是否并入本提案由用户定 |
| 2026-11-26 | 第 5 步并入 | 用户决定把「取函数地址记成对函数的引用」并入本提案，同批实现 |
| 2026-11-26 | Accepted | 用户批准，开始实现。四个仓库各开 `feature/cross-reference-recall-gaps`，按依赖顺序 MachOKitExtensions → MachOObjCSection → 本库 → RuntimeViewer 提交；构建与测试都在 Ultra 上跑（四个工程都在公司那台不编译的清单里），用 `/Volumes/DerivedData/Agents.noindex/claude/LocalDependencies/CrossReferenceRecallGaps/` 下按仓库名放的功能分支拷贝解析本地依赖 |
| 2026-11-26 | 第 4 步定位到根因，修法推广到观察的槽 | Finder 那个函数开头是跳转表，`0x1002bba68` 的 `b 0x1002bbb1c` 带着 `_middleResolution` 的偏移变量地址（`add x9, x9, #0x24`）直接跳到 `ldrsw`，与顺序落下、带着 `_rightResolution`（`#0x28`）的路径在载入处汇合，`x9` 两边不一致被作废——这条载入本来就读两个 ivar 之一，标准答案和 IDA 都把引用记在各自的 `add` 上。核心测试按这个形状写出后先红；修法与第 2 步同一套：算出的地址落在会话观察的槽上（`__objc_ivar`、`__objc_superrefs`、`__objc_selrefs`）时，在这条指令上通知会话、给寄存器打「已记过」的位，之后零位移的 32 位与 64 位载入不再重记。代价是 ObjC 会话总观察 `__objc_superrefs`，每个 `add` / `adr` 都要进 `noteAddress`，吞吐另量 |
| 2026-11-26 | 核心层接口名 | 寄存器表用 `markRecordedSlotAddress(of:)` / `isRecordedSlotAddress(_:)` 与位掩码 `recordedSlotMask`（与设计相同）；取函数地址的记录方法定为 `recordFunctionAddressReference(to: CodeLocation, at:)`，传位置而不是裸地址：核心层知道镜像下标，门面不必再拼 |
| 2026-11-26 | `--type` 的写法归一不 demangle | 只对 `$s`（可带 `_`）开头的符号去掉 `Mn` / `Ma` / `N` 后缀；不带 `$s` 的原样当 mangling。名义类型的 mangling 本身以种类字母结尾，不会撞上这些后缀，不必解开验证。测试发现 mangling 会对与模块名重复的词做替换（`HiddenTypeReferences` 里的 `Hidden` 类型不是 `6HiddenV`），这正是只收准确 mangling、不收点分名字的原因 |
| 2026-11-26 | 验收时 G 类仍用 `--function` | 第 5 步让 `--function` 也列出取访问器地址处，正好覆盖那 27 条；`--type` 还会列出元数据地址、mangled name 等标准答案不算的类型引用，打分时会被算成多报。`--type` 由 `ReferencesRequestSwiftTypeTests` 单独验证，测量脚本不改 G 类 |
| 2026-11-26 | selector 引用在 cache 里认不出，记为后续项 | dyld cache 的构建器把 selref 载入改写成 `adrp; add` selector 字符串的地址（`selectorInSelectorRegister` 里已有说明），所以只在独立文件与 cache 外的镜像里有 selector 引用；cache 里的要从「地址落在 selector 字符串上」去认，另提 |
| 2026-11-26 | 测量脚本按完整命名改写后进仓库 | 从对话记录取回的脚本满是缩写，按仓库「标识符不缩写」的规定改写成 `Scripts/CrossReferenceRecall/`（标准答案合成一个 `ground_truth.py`，数据里的键也改成完整单词）。`verify_reproduction.py` 核对改写后仍复现 11 月 18 日的总数与目标列表，0.25.0 仍是 476/527 |
| 2026-11-26 | 第 6 步验收 | 测量脚本对功能分支：514/527（97.5%），多报 0，剩下 13 条是 `__objc_superrefs`；selector 发送 97/97、ivar 32/32、访问器 104/104、类引用 74/87。吞吐（Ultra，release，与三个仓库的 `next` 交替各两轮取最好）：整表 2.419 → 2.464 秒（+1.9%，引用 1.296 亿 → 1.338 亿条），`init` 调用者扫描 1.516 → 1.545 秒（+1.9%），`makeKeyAndOrderFront:` 0.292 → 0.299 秒（+2.4%），都在 5% 以内；数字记进模块文档的吞吐一节 |
| 2026-11-26 | 实现完成，待用户看过后收尾 | 第 0–6 步都已完成。验证都在 Ultra：MachOKitExtensions 全量测试通过；本库全量（跳过 IntegrationTests）通过；MachOObjCSection 全量有 `MachOObjCSectionTests.testCategories2InCacheFile`（读不到 cache 文件后崩溃）与 `ObjectiveCSymbolLanguageTests.cAndCPlusPlusStoreLeavesObjectiveCNamesOut` 两处失败，在三个仓库的 `next` 上同样失败，属基线；RuntimeViewer 交叉引用模块整模块并发跑时「分析器换新后重新读名字」两条失败、单跑这一组 18 条全过，与 0097 决策日志记的基线现象相同。文档判断：不另写使用指南或实现说明（见头部「配套文档」）；新术语「selector 引用」已登记进术语表。四个仓库的功能分支在本地合进各自的 `next` 检出，没有推送 |
