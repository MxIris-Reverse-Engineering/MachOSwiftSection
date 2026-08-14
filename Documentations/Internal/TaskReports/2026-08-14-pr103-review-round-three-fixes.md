# PR #103 第三轮 review：15 条发现的四问、交叉复核与分批实现

- **日期**：2026-08-14
- **分支**：`feature/node-store-migration`（PR #103 head `b2eabe6`，基线 `aa38ff5`）
- **相关**：第二轮见 [2026-08-13-pr103-review-round-two-fixes.md](2026-08-13-pr103-review-round-two-fixes.md)；第一轮见 [2026-08-09-pr103-review-fix-implementation.md](2026-08-09-pr103-review-fix-implementation.md)

---

## 问题

对 PR #103 跑第三轮 max 级 code review（审的是第二轮修复落地之后的状态），产出 15 条发现。按 CLAUDE.md 的「发现必答四问」逐条查证（能否复现 / main 是否也有 / 值不值得修 / 以前修过吗），再决定修复清单。

第一、二轮已裁决的条目（`ReviewAdjudications.md` A1–A8）不重复审。

## 调研

### 四问推翻的结论

四问改掉了初版报告的三条实质结论，每一条都靠查证而非推理：

- **`OrderedMember.minSymbolOffset` 「每次比较分配一个 String」是误报。** 初版称 `f.symbol.offset` 会走 `DemangledSymbol.symbol` 这个会 `String(decoding:)` 物化 mangled name 的计算属性。实际 `f.symbol` 的静态类型就是 `DemangledSymbol`，`.offset` 命中的是它自己的**具体属性**（`canonicalOffset(atRow:)`，纯数组读）——SE-0195 规定 `@dynamicMemberLookup` 只在常规成员查找失败后参与，具体成员必然优先。初版同时称「`:456/463/471` 用对了、`OrderedMember` 用错了」，但两处是**完全相同的表达式形状**，这个区分不成立。真正的两跳读法只有 4 处（`deallocatorSymbol.symbol.offset` / `destructorSymbol?.symbol.offset`），已并入批次 3。
- **diff 头行渲染失败的影响面被夸大。** 初版称丢掉的声明会「从 change list、`--json` 和 `--fail-on-breaking` 里消失」。查 `DiffCommand.swift:86-88`：`--fail-on-breaking` 即使配 `--interface` 也走 `ABIDiffer().diff(old:new:)`，change list 与 `--json` 走 snapshot 文档。`SwiftDiffableInterfaceRenderer` 只产出注释化 interface 文本，CI 判定不受影响。
- **主 interface 路径的枚举 case 不会静默降级。** 初版称 payload 打印失败会让 `case foo(Payload)` 悄悄变成 `case foo`。主路径用的是 `printThrowingEnumCase`（`+Members.swift:103`），**会抛错**且按 `.hasMangledTypeName` 门控；静默的 `printEnumCase` 只服务 diff 渲染器那条路径。另外 `SwiftInterfaceBuilder.swift:129-131` 两处不传 context 是有书面理由的（内层 `printVariable` / `printFunction` 各自已派发）。

### 四问查到的历史事实

- **opaque 改写返回错变量**：`git log -L20,21` 追到 `5e7373f`（2025-12-16「Increase the underlying type unfolding of opaque types」），**引入即如此，从未修过**，与 main 的缺陷代码逐字相同。不是本 PR 回归。
- **mpenum 缓存的循环级 catch**：一路追到被 `ebb04d3` 删掉的原始 `EnumDumper` 缓存，从来就不是逐条容错。本 PR 新增的行内注释「one bad descriptor degrades only its own enum」是新的过度声明；缺陷代码本身与 main 相同。
- **A/B 脚本的子串匹配**：与第二轮 A1（双边失败但退出码不同）同根因的第三个实例——「验证工具自身无法失败」。第一轮已把这一类列为三大共因之一。
- **`allOpaqueTypeDescriptorSymbols` 的键类型**：在 `NodeStoreMigrationOpenIssues.md` 第 3 条（2026-08-03）已被明确裁决为**不修**，并连带覆盖同形态的 `memberSymbols(of:excluding:in:)`（本轮 review 未点到后者）。本轮经维护者决定**推翻该裁决**，两处一起改（见批次 3）。

### 交叉复核

15 条结论交同项目另一会话独立复核，四点修正全部采纳：

- 误报判定成立，复核方补了**排他性普查**：全 `Sources/` 的 `.symbol.` 共 13 处，慢的只有 deallocator/destructor 那 4 处；且 `Symbol` 只有 `offset`/`name`/`isExternal` 三个存储成员而 `DemangledSymbol` 对三者都有具体快路径，`demangledNode` 又被自身存储属性遮蔽——不存在 grep 看不见的隐式慢读。「慢的只有那 4 处」是穷尽结论。
- **新增一条我漏掉的发现**：`ConformanceProvider.swift` 的子类映射（见批次 1 第 3 项）。
- **修法前提被推翻**：diff 渲染器补诊断不能用事件——它的 printer 由 `.init(in:)` 建、公开 init 不接 handler，派发出去没有 sink，必须走 stderr。
- **措辞精确化**：mpenum 与 opaque 两个**文件**并非与 main 逐字节相同（都有 `print(error)` → stderr 的改动），准确说法是「缺陷代码与 main 相同」；`printCatchedThrowing` 在 main 上「没有 failed 事件」只在 **definition 级**成立，main 的 `dispatchingCatchedThrowing`（`:438`）在成员级本来就派发。

## 最终方案

分三批，每批独立可编译可测试。

| 批 | 内容 |
|---|---|
| 1 | 静默产生错误结果的 4 处：opaque 改写、mpenum 逐条容错、子类映射诊断、A/B 脚本行锚定 |
| 2 | 可观测性与测试：协议事件顺序与命名、无 sink 的 catch 落 stderr、diff 渲染器留痕、NodeStore 不变量做成真守卫 |
| 3 | 清理与台账：4 处 offset 快路径、`missingSymbolWitnesses` 的注释修正、公开字典键类型（推翻 08-03 裁决）、`ReviewAdjudications.md` A9 起、两份裁决台账合并 |

维护者决定：`missingSymbolWitnesses` **不删**（改注释即可），公开字典键类型 **推翻旧裁决、两处一起改**。

## 实际执行

### 批次 1（本节）

先做**不改行为的可测试性重构**，再写会失败的复现测试，最后上修复——顺序是刻意的，用来证明测试真的抓住了问题。

1. **可测试性重构**（零行为变化）
   - `Node+OpaqueType.swift`：`OpaqueTypeGenericParameterRewriter` 由 `private` 改 `internal`。端到端驱动它需要一个恰好含该 opaque 形状的二进制（SwiftUI / WidgetKit 有，fixture 没有）。
   - `MultiPayloadEnumDescriptorCache.swift`：把索引循环抽成 `indexDescriptors(_:in:)`，保持原有的循环级 catch。section 读取本身是唯一的整表失败，抽出来后测试才能把一条坏 descriptor 拼进序列——这是 section 支持的属性表达不了的。

2. **复现测试（修复前全部失败，已验证）**
   - `OpaqueTypeGenericParameterSubstitutionTests`（新增，3 例）：手工构造 `.dependentGenericParamType`（两个 `.index` 子节点，与 demangler 的构造一致）+ 类型表，断言替换结果是具体类型。修复前实测打印出 `"0"` 和 `"1"`——正是参数自己的 depth 字面量。
   - `MultiPayloadEnumDescriptorCacheTests.oneUnreadableDescriptorDoesNotDropTheOnesAfterIt`（新增）：把一条「真实 layout 重新包在越界 offset」的 descriptor 拼到列表最前（沿用 `DiffRendererHeaderFailureTests` 的手法），断言其后的真实 descriptor 仍在表里。修复前 **12 条全部丢失**。
   - `SubclassMapMaterializationFailureTests`（新增）：注入一个 wrapper 不可 materialize 的 class 定义，捕获 stderr。
   - `test-run-rendering-ab-verification.py` 新增 4 例（含只有 iOSSupport 路径的 ActivityKit 场景与一般化的子串误命中场景），修复前 2 例失败。

3. **修复**
   - **opaque 改写**：返回 `type.firstChild`（解开 `.type` 包装的被替换类型）而非 `node.firstChild`。`isKind(of: .type)` 那道 guard 本来就是为解包 `type` 而存在的。
   - **mpenum**：catch 移进循环并 `continue`。循环级 catch 会在第一条坏记录处退出，其后每个枚举都静默落到 `calculateTaggedMultiPayload`——那是**错的**布局而不是缺失的布局，而且被外层 `SharedCache` 记住一整轮。
   - **子类映射**：把 wrapper materialize 的 catch 与 `superclassNode` 的 catch 分开。proposal 0002 之前 wrapper 是存储属性、此处不可能失败，那个 catch 只为一个原因而写；合并进去会让该 class 无声无息地从映射里消失，`subclasses(of:)` 据此收窄特化搜索。unreadable wrapper 现在报 stderr，读不到超类链仍静默（那是绝大多数 class 都会走的「没有可用父类」的正常情况）。
   - **A/B 脚本**：成员判断改为按行锚定。规范路径是 iOSSupport 路径的字面子串，所以包含式判断永远到不了那个 Mac Catalyst 回退分支。

### 验证

- 三个 Swift 套件 **9 tests / 3 suites 全通过，`swift test` 退出码 0**；`test-run-rendering-ab-verification.py` **9/9 OK**。
- **真实二进制端到端**：用修复后的 CLI 重新离线 dump WidgetKit（15.5_24F74 归档 cache 与当前系统 cache 各一次），裸整数泛型实参从 1 / 2 处归零；目标行由
  `CustomSpecifiedPreferenceModifier<A1, 1>` 变为
  `CustomSpecifiedPreferenceModifier<A1, (extension in WidgetKit):SwiftUI.ContainerBackgroundPlacement.WidgetSpecifiedKey>`。
  整份 8011 行的 dump **只差这一行**，爆炸半径确认为零。
- A/B 脚本子串 bug 的复现是端到端做实的：15.5 归档 cache 的 map 里 ActivityKit 只有 iOSSupport 一条（`grep -cx` 验证 exact-canonical=0），CLI 走规范路径 `exit=1 Error: The specified image was not found in the dyld shared cache`、走 iOSSupport 路径 `exit=0` 且输出 6587 行。两边同样失败 → 一对相等的 `.skip` → 报 `SKIPPED (both sides)` 且不计入 `examined_pair_count`，整轮仍宣称完全一致。
- **全量回归**：`swift test --skip IntegrationTests` 跑出 **1418 tests / 268 suites**（基线 1413 / 266，差值正是本批新增的 5 个测试与 2 个套件），退出码 1，**2 个 issue 全部来自已知的墙钟 flaky** —— `SharedCacheTests` 的 `differentKeysParallelViaTaskGroup`（elapsed 1.209s vs budget 0.8s）与 `differentKeysParallelViaAsyncLet`（1.540s vs 1.200s）。这两条用墙钟断言并行度，全量并发下必然假失败；单独跑 `--filter differentKeysParallel` **2/2 通过、退出码 0**。除此之外零失败。

## 与方案的差异

- 批次 1 原计划只有 3 项；交叉复核补进了子类映射一项，共 4 项。
- 子类映射一项的定性在执行中被收窄：初版描述暗示映射会被截断，实际 `catch { continue }` 只跳过当前条目。真实缺陷是**新增的静默丢失面**（proposal 0002 之前该 class 不会掉），修复因此以诊断为主、行为不变。
