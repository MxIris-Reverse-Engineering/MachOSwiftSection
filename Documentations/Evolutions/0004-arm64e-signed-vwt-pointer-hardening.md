# 0004 - arm64e 签名 VWT 指针加固：进程内裸读 strip + 真 PAC 环境的回归验证形态

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-08-09
- **最后更新**: 2026-08-09
- **所属愿景**: 无
- **关联提案**: 无（与 0002/0003 的内存线正交；崩溃场景与 0002 的下游验收同在 RV 注入路径上被发现。0002/0003 的提案文件在 `feature/node-store-migration` 分支上，尚未并入 main）
- **实现分支 / PR**: `main`（用户裁定：基线旧 bug、影响面大，不并入优化分支，直接在 main 修复；提案随之从 `feature/node-store-migration` 迁至 main）
- **配套文档**: [RuntimeEnumCaseProjection.md](../Internal/RuntimeEnumCaseProjection.md)（其 arm64e 验证记录将由本案修正）；崩溃报告由 RV 侧会话提供（App Store 主二进制，macOS 26.6，注入 RuntimeViewer 后导出 interface 崩溃）

## 摘要

arm64e 进程里，metadata 前一字长的 value witness table（VWT）指针带 PAC 签名（`__ptrauth_swift_value_witness_table`：asda key、address diversity、discriminator 0x2E3F）。`RuntimeEnumCaseProjector` 把它按普通 `UnsafeRawPointer` 裸读后直接解引用——在真 arm64e 进程里必崩（SIGSEGV），已有真实崩溃报告与本地探针双重复现。本案把这处**全库进程内读取中唯一绕过 `Pointer` 抽象的裸读**拉回既有的 strip 惯用法（`stripPointerTags`，`PointerProtocol.resolve()` / `InProcessContext` 每次进程内解引用都在走的 VA 掩码剥法）；并针对调查中发现的验证陷阱——**`swift test` 的测试进程是 PAC 不生效的 arm64e 环境，签名类 bug 在其中恒过**——建立「spawn 正常 arm64e 子进程」的真验证测试形态，同批修正既有文档里的失实验证记录。

## 动机

### 崩溃与机制

- **崩溃现场**（RV 侧会话提供）：App Store 主二进制（macOS 26.6，arm64e），注入 RuntimeViewer 后导出 interface 即崩。崩在 memmove：`x1 = 0x00418001010521e8`（带 PAC 位），`x2 = 0x58 = 88` 字节——正是 `ValueWitnessTable.Layout` 的尺寸（8 个函数指针 64 + size 8 + stride 8 + flags 4 + numExtraInhabitants 4）；去签后地址落在该二进制 `__DATA` 段内。
- **崩溃点**：`Sources/SwiftInspection/RuntimeEnumCaseProjector.swift:94-98`——`enumMetadataPointer.load(fromByteOffset: -8, as: UnsafeRawPointer.self)` 读出**带签名的**表指针，下一行 `tablePointer.load(as: ValueWitnessTable.Layout.self)` 解引用即 fault。
- **触发条件**：RV 注入 arm64e 宿主进程 + 生成选项开启 Print Enum Layout（`RuntimeFieldLayoutBackend` 的运行时 enum-layout 路径把门）。
- **本地复现**（探针实测，本机 boot-args `-arm64e_preview_abi`）：arm64e 正常进程里**一切来源**的活 metadata——探针二进制内的静态 enum、`Optional`/泛型运行时实例化、stdlib `Int`、OS framework `Date`——VWT 槽全部带 PAC 位；解引用一律 SIGSEGV（exit 139）。arm64 对照全部干净。

### 四问裁决（按 code-review 纪律）

1. **能复现吗**：能，当场复现（上节探针）；崩溃报告参数逐项吻合。非误报。
2. **main 也有吗**：有。`755c3fc`（main）同代码——基线旧问题，非 0002/0003 引入。
3. **值得修吗**：值得。RV 注入 arm64e 应用（App Store 应用即典型）导出 interface 必崩，用户可直接踩到；修法小而定向。
4. **以前修过吗 / 为何存在至今**：未修过，且存在链条完整——
   - `028e32fb`（2026-07-22）有意删掉 arm64e 的 `return nil` 兜底、给**表内函数指针槽**接了 ptrauth 限定符 stub，但漏了**指向表本身的指针**（其读取发生在更前面）；
   - 配套写好的 `__ptrauth_strip_asda()`（`MachOSwiftSectionC/Functions.c:37`）与 discriminator 常量 `SpecialPointerAuthDiscriminators.valueWitnessTable = 0x2E3F` 全仓库**零调用**——为此而写、忘了接线；
   - `642de8ee`（2026-07-23）声称「宿主已启 `-arm64e_preview_abi`，全套件 1253 测试以 arm64e 进程通过，projector 测试真跑了 PAC 签名 witness」。**该验证真实运行过但无效**（见下节）——这是问题存活至今的直接原因。

### 验证陷阱：`swift test` 的 arm64e 测试进程 PAC 不生效

调查中的决定性实验（同一台机、同一探针逻辑、同为 arm64e 产物）：

| 运行方式 | VWT 槽原始值 | 解引用 |
|---|---|---|
| shell 直接 spawn（`swiftc` 或 SwiftPM `--triple arm64e` 构建均同） | **带 PAC 位** | **SIGSEGV（139）** |
| `swift test --triple arm64e-apple-macosx` 的测试进程内 | **裸指针（无 PAC 位）** | 安然通过 |

测试进程确为 arm64e（runner 二进制 `Mach-O 64-bit bundle arm64e`、Swift Testing 报 `Target Platform: arm64e-apple-macos14.0`），但其内 auth fixup 以 strip 形式应用——**任何依赖「测试以 arm64e 跑过」的签名类验证都是安慰剂**。这直接否定了「给 CI/本地加 `--triple arm64e` 跑套件」作为防线的可行性，也解释了 `642de8ee` 为何全绿。GitHub 托管 runner 另有一层限制：未启（也无法启）`-arm64e_preview_abi`（runner-images #9461 悬而未决），arm64e 三方进程根本无法执行。

## 前期调研

- **同类横向排查（审阅期修订后的最终结论）**：库内进程内读取**本已系统性地 strip**——`PointerProtocol.resolve()`（无参 leg）对 `address` 先过 `stripPointerTags(of:)`（`MachOExtensions`，按架构/平台的 VA 掩码，arm64 macOS = `0x0000_7FFF_FFFF_FFFF`，一并剥 PAC 与 objc tagged-pointer 位）再解引用，`InProcessContext.readElement` 亦每读先 `ptr.stripPointerTags()`。因此进程内 `MetadataWrapper.valueWitnessTable()`（经 `valueWitnesses.resolve()`）**已受保护，不是同类实例**（初版提案的误判，见决策日志）。`RuntimeEnumCaseProjector` 是唯一绕过 `Pointer` 抽象、直接裸指针算术的进程内读取点。`MetadataAccessorFunction` 的两处 `UnsafeRawPointer` 是**写**参数缓冲（`toByteOffset:`），非同类。
- **离线路径不受影响**：`MachOFile` 读的是文件字节（fixup 前的形态，无签名）；相对指针（int32 偏移）与签名无关。受影响的只有「进程内读绝对指针」且槽位在 ABI 中被签名的路径。
- **stub 调用链的隐含要求**：`swift_section_vwt_getEnumTag` / `swift_section_vwt_destructiveInjectEnumTag` 的槽位限定符是**address diversity**的——discriminator 由槽位真实地址 blend 计算。传入带 PAC 位的表指针，槽位地址本身就是错的，auth 分支照样 fault。所以 strip 必须发生在**读出表指针之后、一切使用之前**，stub 收到的必须是 strip 后的地址。
- **修复着点确认**：`UnsafeRawPointer.stripPointerTags()`（`MachOExtensions` 的 package extension，`SwiftInspection` 同包可见）即修复入口；用崩溃报告指针验算掩码：`0x00418001010521e8 & 0x0000_7FFF_FFFF_FFFF = 0x1010521e8`，正是去签后落在 `__DATA` 段内的合法地址。`__ptrauth_strip_asda()` 维持未接线预留（其仅 arm64e 编译的定义与无条件声明的错配留给日后清理或删除，本案不动）。

## 提议方案

1. **`RuntimeEnumCaseProjector`**：读出表指针后立即经 `stripPointerTags()` strip（回归既有惯用法），后续解引用与两个 stub 调用一律使用 strip 后指针。
2. **`MetadataWrapper.valueWitnessTable()` 进程内 leg**：审阅期查实已受 `PointerProtocol.resolve()` / `InProcessContext` 的 strip 保护，无需修改；在其解引用点补一句注释指向本案，防止未来重构绕开惯用法。
4. **回归验证（双层，均永久保留）**：
   - **探针层**：测试先以 canary 探测宿主能否执行 arm64e 三方进程（现场编译并运行一个最小 arm64e 程序）；能则现场编译真验证探针并 spawn 为**正常 arm64e 子进程**（修复前崩 139、修复后正常输出投影结果），不能则显式 skip 并留痕（GitHub 托管 runner 即此情形）。
   - **符号层**：断言 `SwiftInspection` 构建产物引用 `stripPointerTags` 的 mangled 符号（`028e32fb` 用过的符号级验证思路），处处可跑（含 GitHub CI），锁「接线不被后续改动删掉」。
5. **文档修正（同批）**：修正 `642de8ee` 写入 AGENTS.md 与 [RuntimeEnumCaseProjection.md](../Internal/RuntimeEnumCaseProjection.md) 的失实验证记录，把「`swift test` 的 arm64e 测试进程 PAC 不生效」这一陷阱连同证据写进后者——这是下次有人想「用测试验证签名行为」时必须先撞见的知识。

### 非目标

- **进程内签名槽的全面 ABI 审计**（class vtable 项、heap destructor、existential 内 witness table 指针、metadata accessor 返回值等其它签名点）：本案只修 VWT 指针这一类（有崩溃实证的类）；全面审计的面与验证成本另立提案，不在此案夹带。
- **CI workflow 拓扑变更**（self-hosted arm64e runner job）：本机已具备条件（boot-args 已启），要不要挂进 GitHub Actions 由用户单独拍板；本案的符号层断言不依赖它。
- **`auth` 替代 `strip`**：见「替代方案考量」。

## 详细设计

### strip 点

```swift
// RuntimeEnumCaseProjector.projectCasePatterns —— 修改后形态（示意）
let signedTablePointer = enumMetadataPointer.load(
    fromByteOffset: -MemoryLayout<UnsafeRawPointer>.size,
    as: UnsafeRawPointer.self
)
// arm64e: the slot is signed (asda, address-diversified, discriminator
// 0x2E3F); strip before ANY use — the stubs' per-slot discriminators are
// blended from real slot addresses, so a PAC-carrying table pointer
// faults there too. Same idiom every in-process resolve path already
// uses (PointerProtocol.resolve() / InProcessContext.readElement).
let tablePointer = try signedTablePointer.stripPointerTags()
```

`MetadataWrapper` 侧无需改动：其进程内 leg 经 `valueWitnesses.resolve()`，`PointerProtocol.resolve()` 已对 `address` strip；文件 leg（`in machO:`）读的是 fixup 前的文件字节，不涉签名。

### 探针层测试的结构

- canary：现场 `clang -arch arm64e` 编译最小 C 程序并运行；退出码即宿主能力判据。
- 探针：现场编译的小 Swift 程序，对**自身进程内**的活 enum metadata 走「读槽 → strip → 解引用 → 调 witness 投影」的最小复刻，输出投影结果；测试 spawn 它并断言退出码与输出。子进程由测试进程正常 `posix_spawn`，不继承 `swift test` 环境的 PAC 豁免（实验已证：探针直接 spawn 即真 PAC 环境）。
- 探针复刻逻辑与库代码的同步风险由**符号层**兜底：探针验证机制（strip 后不崩），符号断言锁库代码接线（`stripPointerTags` 的引用消失即红）。
- skip 语义：宿主不能执行 arm64e（如 GitHub 托管 runner，见 runner-images #9461）时显式 skip 并输出原因，不静默通过。

### 风险与接受的约束

- **strip 而非 auth**：strip 放弃了伪造检测。本工具是逆向分析器，读的是自身注入进程内的 metadata，威胁模型里没有「被伪造的 VWT 指针」需要防；且这正是 `__ptrauth_strip_asda` 当初被写下的用途。
- **探针层在 CI 恒 skip**：GitHub 托管 runner 无法执行 arm64e 三方进程，探针层只在本机（及未来可能的 self-hosted runner）生效。接受——符号层保证 CI 上接线不丢，真 PAC 行为由本机验证覆盖。

## 替代方案考量

- **`__ptrauth_strip_asda`（`xpacd` 指令）替代 `stripPointerTags`（VA 掩码）**：`xpacd` 是架构语义精确的 strip 原语，且作为独特 C 符号更易做接线断言；但 `stripPointerTags` 是全库进程内解引用的既有惯用法（`PointerProtocol.resolve()` / `InProcessContext` 均在用）、全平台已可用，用户态 macOS 下两者结果等价（sign extension bit 为 0 时 `xpacd` 即清高位）。审阅期用户点名后选惯用法——修复的本质是「把绕过惯用法的孤立裸读拉回惯用法」，不引入第二套剥法。若日后出现掩码不适用的 VA 配置再切换。
- **`ptrauth_auth_data`（auth）替代 strip**：语义上更严格（伪造即 fault），但 discriminator 需按槽位地址 blend （`ptrauth_blend_discriminator(slotAddress, 0x2E3F)`），实现面更宽；对本工具的威胁模型无增益。被否——与 Swift 官方 RemoteMirror 对外部 metadata 的处理取向一致，用 strip。
- **恢复 arm64e 下 `return nil` 兜底**（`028e32fb` 之前的行为）：等于放弃 arm64e 宿主的整个运行时 enum-layout 能力，而 strip 修复只有几行。被否。
- **`swift test --triple arm64e` 作为回归防线**：实验已证该环境 PAC 不生效，签名类 bug 恒过——安慰剂。被否，且本案要把这个结论写进文档防止复发。
- **只修 projector、不动 `MetadataWrapper`**：同一签名槽的同类实例，「修的是这一类不是这一个」（code-review 纪律）；且 RV 的 specialization 路径在 arm64e 宿主上迟早踩到。被否。

## 影响

### 源码兼容性（source compatibility）

**无破坏。** 全部改动是内部行为修复（读取路径加 strip）；`__ptrauth_strip_asda` 是 `MachOSwiftSectionC` 既有导出，全平台化只改其定义的可用面。公开 API 零变化。

### ABI 兼容性（条件项）

不适用——SPM 源码分发（项目类型声明见 [`Documentations/README.md`](../README.md)）。

### 下游影响

- RuntimeViewer：注入 arm64e 进程 + Print Enum Layout 的崩溃消失；零源码迁移，重编即得。
- 其余下游无感知。

### 文档与示例

- [RuntimeEnumCaseProjection.md](../Internal/RuntimeEnumCaseProjection.md)：修正失实的 arm64e 验证记录，补「`swift test` PAC 不生效」陷阱及实验证据。
- AGENTS.md：SwiftInspection 段的验证声明同步修正；测试环境注意事项补一句。

## API 演进与废弃策略

无公开 API 变化，无废弃需求；随下一次常规版本发布，changelog 记录崩溃修复。

## 落地步骤

1. `RuntimeEnumCaseProjector` 改经 `stripPointerTags()` strip；`MetadataWrapper` 进程内解引用点补注释（已受保护，无行为改动）。
2. 探针层测试（canary 门 + 现场编译 + spawn 真 arm64e 子进程；**先证修复前崩 139**，再证修复后过）+ 符号层断言。
3. 全量 `swift test --skip IntegrationTests` 同数全绿（arm64 常规环境回归）。
4. 文档修正同批：RuntimeEnumCaseProjection.md + AGENTS.md。
5. RV 侧真机验证（对面协调）：注入 arm64e 应用 + Print Enum Layout，确认崩溃消失。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-09 | Created as In Review | RV 侧会话转来 App Store arm64e 崩溃报告；本会话完成机制复现（探针四来源全签名、解引用 SIGSEGV）、四问裁决、`swift test` PAC 不生效的验证陷阱实验与 GitHub CI 可行性查证；用户裁定「这个 bug 很经典，写个提案」立项成文。 |
| 2026-08-09 | 审阅修订：改用 `stripPointerTags` 惯用法，撤销「同类第二实例」判定 | 审阅期用户问「用 stripPointerTags 有用吗」；查实 `PointerProtocol.resolve()` / `InProcessContext` 的进程内解引用**本已系统性地经 `stripPointerTags` strip**（初版调研 grep 的是 `ptrauth`/`strip`/`PAC` 关键词，VA 掩码实现一个不含，漏检）。三处修订：(1) 修复改用既有惯用法 `stripPointerTags()`，`__ptrauth_strip_asda` 维持未接线预留；(2) `MetadataWrapper.valueWitnessTable()` 进程内 leg 已受保护，从修复面撤销、降为补注释；(3) 符号层断言对象随之改为 `stripPointerTags` 引用。`xpacd` vs VA 掩码的取舍记入「替代方案考量」。 |
| 2026-08-09 | In Review → Accepted，迁至 main | 用户审核通过（「审核通过，开始实现」），并裁定实施基线改为 **main**——本 bug 是 main 上就有的基线问题、影响面大，不与 `feature/node-store-migration` 的内存优化线捆绑；提案文件随之从该分支迁到 main（分支上三个未推送的提案 commit 撤下，编号 0004 不变）。 |
