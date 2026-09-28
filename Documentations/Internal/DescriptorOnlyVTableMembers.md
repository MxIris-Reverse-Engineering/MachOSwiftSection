# interface 里只剩 method descriptor 符号的 class 成员

> 提案 [draft-interface-descriptor-only-vtable-members](../Evolutions/draft-interface-descriptor-only-vtable-members.md) 的实现说明。读者：维护者。为什么要做、范围怎么定的在提案里，本文讲落地后的形状、几个看代码看不出来的决定，以及边界。

## 一句话

interface 的成员一直是从「实现函数的符号」建出来的。用 library evolution 编译的模块只导出 class 方法的 dispatch thunk（`Tj`）和 method descriptor（`Tq`），实现符号是 local 的，所以镜像的 local 符号一被剥掉——系统 dyld shared cache 里的 AppKit、`strip -x` 过的二进制——public 的 class 方法和访问器就一个也建不出来。现在 `TypeDefinition.classDispatchLookups(in:)` 为本类每个 `Tq` 能命名、实现指针非 null 的 vtable 槽造一个「替身成员符号」，`indexMembers` 在实现符号没有声明这个成员时用它补建；打印时 class 的 vtable 成员按槽号顺序排在最前。

## 规模：「没导出」不等于「没符号」

只看导出表（`dyld_info -exports`）会以为问题很大：AppKit、SwiftUI、SwiftUICore、Foundation 里 class 的 public vtable 成员，除了 init（客户端直接调用 allocating init `fC`，子类的 `super.init` 调用 initializing init `fc`，所以都导出）之外，实现函数一个都没导出。但 interface 读的是镜像的整张符号表，local 符号也在里面，只要镜像没被剥就有名字。实测（渲染 A/B，macOS 26.6.2 与 26.7 的 cache、iOS 15.5–26.5 模拟器 runtime）：

| 镜像 | 改动后多出的成员 |
|---|---|
| AppKit（macOS cache） | 53 个：40 个方法、11 个计算属性、2 个下标；另有存储属性的访问器挂上了 vtable 槽号 |
| SwiftUI、SwiftUICore、Foundation（macOS cache 与模拟器 runtime） | 0：这些镜像保留了 local 符号，实现函数本来就有名字 |

统计时还要把协议 requirement 排除掉：它们也有 `Tq`（AppKit 里 65 个），但协议从协议描述符打印，本来就不缺。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| SwiftInspection | `Descriptor+MethodDescriptorSymbols.swift` | `MethodDescriptor.attributedMember(in:)`：`Tq` 归属连同 `Tq` 符号本身一起返回（`MethodDescriptorAttribution.AttributedMember`），`implementationSymbolName` 是去掉 `Tq` 后缀的名字。原有的 `attributedMemberNode(in:)` 改为转调它，结果不变。 |
| SwiftDeclaration | `TypeDefinition+ClassDispatch.swift` | 走本类 `methodDescriptors` 时，`Tq` 归属成功的槽额外造一个替身符号，按槽号顺序存进 `ClassDispatchLookups.vtableSlotMemberSymbols`。 |
| SwiftDeclaration | `ClassDispatchLookups.swift` | `supplementing(_:in:)`：真实成员符号加上本类别里真实符号没有声明的替身。 |
| SwiftDeclaration | `TypeDefinition+MemberIndexing.swift` | 六类成员的输入都先经 `supplementing`。 |
| SwiftDeclaration | `OrderedMember.swift` | `vtableOrdered(_:)`：有槽号的成员按槽号排序；`classOrdered` 改为复用它。 |
| SwiftPrinting | `SwiftDeclarationPrinter.printMembersByCategory` | 先打 `vtableOrdered` 的结果，再按类别打没有槽号的成员。 |
| SwiftPrinting | `FunctionNodePrinter.initFailabilityKind` | 只看 initializer 自己函数类型的直接 `returnType`，声明在 `Optional` 上的 init 要再剥一层（顺带修的 `init?` 误判，见下文）。 |
| SwiftDiffing | `ABISnapshotDocument.currentFormatVersion` | 5 → 6。 |

## 替身符号为什么长这样

**名字用实现函数的 mangled 名，不用 `Tq` 符号的名字。** 下游有三处按「成员的实现符号名」推导别的东西：导出判定往名字后面拼 `Tj` / `Tq` / `Tu` 去查 export trie（`isExportedIncludingDerivedSymbols`）；ObjC 方法表按实现符号名 join（`ObjCMemberApplication`）；ABI diff 的成员身份是重整后的声明节点。用实现函数的名字，这三处把替身当成它顶替的那个符号来读，一行不用改；用 `Tq` 的名字，导出判定会去查 `…TqTj` 这种不存在的符号。去掉后缀就能得到实现名，是因为 mangling 规则是把 `Tq` 原样追加在实体名后面。

**偏移用 descriptor 记录的实现偏移，async 方法再跳一次。** 地址注释读的是成员符号的偏移，替身的偏移必须和「有实现符号时」的那个一样，fixture 的完整版与剥离版逐字比对才能对上。async 方法的 vtable 槽里放的不是代码地址，而是 async function pointer（`Tu` 常量，调用方从它读 async context 的大小），实现符号在它指向的函数入口，所以要经 `AsyncFunctionPointer` 读一次 `function` 字段。读这个记录时要显式标注非可选类型：`resolve(from:in:)` 有一个返回可选值的重载，推断到那个重载会按另一种内存形状去读。

**demangled node 就是 `Tq` 解开后的成员节点。** 它和实现符号 demangle 出来的形状一样（`global(<entity>)`），所以 `dispatch(forMemberNode:implementationOffset:)` 的 join 键直接命中，槽号、method descriptor、`dynamic` 标记都照常挂上。

## 为什么不走看起来更简单的路

- **直接把 `Tq` 符号当成员符号用**：symbol index 本来就把 `Tq` 按成员类别分好了桶（`methodDescriptorMemberSymbols`），拿来直接喂给 builder 最省事。但那样成员符号的名字和偏移都是 descriptor 的：地址注释会指向 `__TEXT,__const` 里的 descriptor，导出判定拼后缀会查错名字。而且桶里的 `Tq` 不经过 vtable，墓碑槽和 modify / read 协程的 `Tq` 也会混进来，还得再按 descriptor 过滤一遍。从 vtable 槽出发，这些判断都在一个地方做完。
- **让打印层直接遍历 vtable**（dump 就是这么做的）：interface 打印的是声明模型，RuntimeViewer、diff、ABI snapshot 读的都是同一个模型。在打印层补，模型里依然没有这些成员，snapshot 和 diff 照样缺，`@Wrapper` 恢复、导出过滤也看不到它们。所以在索引期补进模型，打印层只负责排序。
- **只补、不改顺序**：补出来的成员会按类别插进去，看不出它在类里的位置。vtable 顺序就是本类成员的声明顺序，按它打印，class 的 interface 读起来接近源码，和 dump 的槽位列表也能对着看。

## 什么时候不补

- **ABI 墓碑**：实现指针是 null，镜像里没有这个成员的代码，只剩槽位。dump 带着墓碑注释列出它；interface 不补，和改动前一致。
- **modify / read 协程**：符号索引从不把这两种访问器当成员，有实现符号的 class 在 interface 里也看不到它们，补了会让剥离前后的输出形态不同。属性的 `{ get set }` 已经由 getter / setter 表达。
- **真实符号已经声明了这个成员**：按成员实体节点结构相等判断，merged function thunk 先跳过它开头的标记节点，因为 builder 会把 thunk 归到它代表的成员上。所以 fixture 这种没剥离的二进制，模型一个成员都不会多，也一个都不会变。
- **叫不出名字的槽**：internal 成员的 `Tq` 和实现符号一样是 local 的，剥离后这个槽谁也叫不出名字。按用户的指示跳过，不打占位符；dump 里它显示为 `sub_…` 或 `<unnamed vtable slot>`。
- **override table 里的槽**：它们没有自己的 `Tq`，指向的是父类的 descriptor，用父类的名字归属会把成员归到父类身上（[提案 0020](../Evolutions/0020-vtable-slot-attribution-via-method-descriptor-symbols.md) 的决策日志记着这次撞车）。没有实现符号时仍然缺席。

## 顺带修的 `init?` 判定

initializer 可失败，指的是它自己的返回类型是 Self 的 Optional。旧判定用整树的前序搜索找第一个 `returnType`，而闭包参数的 `returnType` 在前序里排在 initializer 自己的前面，于是两个方向都会错：闭包返回 Optional 时误加 `?`（AppKit 的 `NSCollectionViewDiffableDataSource.init(collectionView:itemProvider:)`，SwiftUI 里约 20 处），闭包返回别的类型、而 init 真的可失败时漏掉 `?`（SwiftUI 的 `CoreDisplayLink.init?(displayID:handler:)`）。现在只取 initializer 自己函数类型的直接 `returnType` 子节点，泛型上下文先跨过 `dependentGenericType`。

唯一的特例是声明在 `Optional` 上的 init（`Optional.init(_:)`，SwiftUI 的 `extension Optional { init(if:then:) }`）：它的 Self 就是 `Wrapped?`，返回 `Wrapped?` 不是失败，返回 `Wrapped??` 才是。第一轮 A/B 正是靠这个 `init(if:then:)` 发现了这个缺口——旧判定在这里碰巧是对的，因为它先看到的是 autoclosure 的返回类型。

## 边界

- **补建出来的成员没有 `@objc`，也没有「覆盖 ObjC 父类成员」的 `override`。** 这两个事实靠 ObjC 方法表 join：tier 1 看 IMP 处的 `To` thunk 符号，tier 2 解码 thunk、看它调用的地址上有什么符号——剥离过的镜像里（系统 cache 里的 AppKit）`To` thunk 和实现函数都没有符号。例如 AppKit 的 `NSTableViewDiffableDataSource.numberOfRows(in:)` 实现的是 `NSTableViewDataSource` 的 `@objc` 方法，interface 里打出来是 `func numberOfRows(in:)`。要补，得让 tier 2 在「被调用地址没有符号」时回头查本类 vtable 的替身表，那是 SwiftThunkAnalysis 的改动，没有放进这一批。
- **合成的 Codable / Hashable 成员仍可能整个消失。** `deduplicateSynthesizedProtocolMembers()` 默认 conformance extension 里一定有一份，于是把类体里的那份去掉；剥离镜像里 extension 那份的 witness 也没有符号，结果两边都不显示。AppKit 的 `IncrementalUpdateAction.encode(to:)` 就是这样。改动前它同样缺席，不是回归。
- **diff / evolution 的多版本渲染仍按类别排序。** 两个版本的 vtable 顺序可能不同，没有一个统一的槽号顺序可用。新补的成员照样进入多版本渲染和 ABI snapshot，只是排序不变。
- **ABI snapshot 的 `formatVersion` 升到 6**：key 方案没有变，但剥离镜像的 class 容器多出这批成员，旧 baseline 对新 snapshot 会把它们全部报成新增。拿旧 snapshot 做 diff 会得到一个明确的版本错误，要用新工具重新生成。

## 验证

- **新测试，修复前逐条确认失败**。`DescriptorOnlyVTableMemberTests`：现场编译一个 library-evolution 的小库，一份保留全部符号、一份 `strip -x`，镜像 AppKit 的形状（两个 `Hashable` 泛型参数、存储与计算属性、接受返回 Optional 的闭包的非可失败 init、普通 / `open` / `class` / `async` 方法、下标，外加不占槽的 `final` 与 `static` 方法）。四条断言：剥离版的类声明与完整版逐字一致（开着 vtable 槽号与成员地址，async 方法的地址验证了多跳的那一次）；两个版本都按槽号顺序打印；剥离版装进进程、经 `MachOImage` 读出来也一样（RuntimeViewer 的路径）；internal 方法的槽被跳过、不留占位。`InitializerFailabilityPrintingTests`：10 个 mangled 名，覆盖闭包返回 Optional 的非可失败 init（含泛型上下文与 AppKit 原例）、Optional 参数、可失败 init（含闭包返回 Optional、闭包返回 `()` 的 `CoreDisplayLink`）、声明在 `Optional` 上的 init（`Optional.init(_:)`、extension 里的非可失败与可失败各一）。`Optional` 那三条是第一轮 A/B 发现缺口后补的，同样先在当时的代码上确认失败。
- **fixture 快照**：SymbolTestsCore 的 interface 快照去掉空行、忽略缩进后，行集合与改动前完全相同——没剥离的二进制一个成员都不多、不少，差异只有顺序和 10 个分组空行。逐类对照 fixture 源码，新顺序就是声明顺序（例如 `OpenAccessTest` 是 `openProperty → openMethod → publicMethod → init()`，旧输出是 `init` 打头再按类别分组）。
- **渲染 A/B**（基线：`next` b521c339 的干净 worktree；候选：本分支最终代码；框架 AppKit / Foundation / SwiftUI / SwiftUICore）：46 对里 23 对 dump 全部逐字节一致；23 对 interface 里 22 对有差异，按行集合逐对归类，只有两类——`init` / `init?` 的修正（SwiftUI 每份约 20 处、SwiftUICore 1–2 处、Foundation 在模拟器上 1 处，两个方向都有），以及 AppKit 找回的成员；任何一对里「被删掉且没有对应项」的行都是 0。进程内（MachOImage）那一腿与文件那一腿给出同样的 54 条声明，开着注释时另有 92 条 vtable 槽号、60 条地址。脚本的 cache 腿找不到 `Versions/C` 下的 AppKit / Foundation，这两个用两侧的 release CLI 手动渲染：macOS 26.6.2 与 26.7 的 cache 上，AppKit 各多出 53 个成员、1 处 `init?` 修正，Foundation 只有 `Optional` 的 `init(from:configuration:)` 那 1 处修正，dump 一致。
- **全量测试**：`swift test --skip IntegrationTests`，2121 个测试 / 402 个 suite，原始退出码 1，失败的 6 条都与本改动无关：`SharedCacheTests` 的 3 条墙钟并行度断言（全量时被挤成假失败，单独跑通过）、`MultiPayloadEnumDescriptorCacheTests` 的 2 条（在未改动的 `next` 上同样失败）、`argumentCandidatePathSpecializesNonGenericCandidate`（`.candidate` 与 `.metatype` 拿到两份 metadata 的既有随机失败，单独跑通过），另有 1 条既有的 known issue。
- **与 SDK 对照**：macOS 26.7 的 `NSTableViewDiffableDataSource` 与 `NSCollectionViewDiffableDataSource`，SDK swiftinterface 里的每个成员现在都在，顺序与 SDK 一致，`init(collectionView:itemProvider:)` 不再带 `?`；另外多出的 `NSTableViewDiffableDataSourceWrapper`、`impl`、`wrapper` 等是 SDK 隐藏的内部存储，从字段记录读出，属于预期。
