# 只剩 `@objc` thunk 或 initializing entry point 的成员

> 提案 [draft-thunk-only-objc-members](../Evolutions/draft-thunk-only-objc-members.md) 的实现说明。读者：维护者。为什么要做、范围怎么定的在提案里，本文讲落地后的形状、几个看代码看不出来的决定，以及边界。

## 一句话

成员模型从实现符号建成员。优化构建会把实现符号删掉，只留下同一个成员的另一个入口：`@objc` 成员的函数体被内联进它的 Objective-C thunk（`$s…To`），Swift entry point 随后被删掉；class 的 initializer 的 allocating entry point（`…fC`）被内联进调用方后删掉，只剩 initializing entry point（`…fc`）。现在符号索引把每个 `To` thunk 也按它进入的成员登记一份；`indexMembers` 和 extension 索引在真实符号与提案 0054 的 `Tq` 替身之后，再用这两种入口造替身，补上缺的成员；dump 在类的成员列表后面加 `[ObjC Thunk]` 一节。

## 规模

- Xcode 27.2 的 `Xcode Service` 可执行文件（Release 构建，整模块优化）：36 个 `To` thunk 里有 28 个旁边没有 Swift entry point。其中 6 个是 ivar destroyer（`…fETo`），不是成员；其余 22 个成员分布在 7 个类里，比如 `MenuBarPanelWindow` 的 `canBecomeKey`、`XcodeServiceAppDelegate` 的 `applicationShouldOpenUntitledFile(_:)`。另有 9 个 class initializer 只剩 `fc`。改动前 dump 与 interface 一个都不打。
- 只有 internal 成员会这样：整模块优化看得到它的每一处使用，所有使用都内联完了，entry point 才能删。public 与 open 成员的 entry point 要留给模块外的调用方，删不掉。所以这是 app 和 app 内嵌组件的形状；系统框架的公开 API 基本不受影响。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| MachOSymbols | `SymbolIndexStore.swift` | 扫描时，以 `objCAttribute` 开头的符号照旧进 thunk 属性的标记表，此外经 `processMemberSymbol` 按它进入的成员归类，存进第四个成员索引 `objcThunkMemberSymbolRowsByKind`。它与实现符号、`Tq`、protocol witness 三个索引并列，键同样是「成员类别 → 类型名 → 类型节点」，存的是 thunk 自己的行。查询是 `objcThunkMemberSymbols(of:for:in:)`、两个带 node 的重载和 `objcThunkMemberSymbols(of:excluding:in:)`。 |
| SwiftDeclaration | `Components/Building/StandInMemberSymbols.swift` | 造替身与去重：`memberStandIn(forObjCThunkSymbol:in:)`、`allocatorStandIn(forInitializerSymbol:in:)`、`supplementing(_:with:)`、`declaredEntityKey(of:)`（从 `ClassDispatchLookups` 挪过来，0054 的 `Tq` 替身也用它），以及造之前按名字预筛的 `imageKeepsTheMemberSymbol(replacedBy:symbolIndexStore:in:)`。`TypeMembers` 是一个类型自己成员的替身表，`supplementingExtensionMembers(_:symbolIndexStore:in:)` 补 extension 成员。 |
| SwiftDeclaration | `TypeDefinition+MemberIndexing.swift` | 七类成员的 builder 输入都按「真实符号 → `Tq` 替身 → 这两种替身」的顺序拼起来。 |
| SwiftIndexing | `SwiftDeclarationIndexer.indexExtensions()` | 按类型分组之前先补替身；成员全是替身的类型也会得到 extension。 |
| SwiftDump | `ClassDumper` | 成员符号各节之后，按成员类别列出只剩 thunk 的成员（`/* [ObjC Thunk] Function */` 等），行尾照常挂 ObjC 方法表的注释。 |
| SwiftDiffing | `ABISnapshotDocument.currentFormatVersion` | 加一：旧基线会把新建出来的成员全报成新增。 |

## 替身为什么长这样

与 0054 同一个思路：替身照它顶替的实现符号的样子造，mangled 名和成员树都与实现符号相同，偏移用镜像里留下的那个入口。

- **名字**：thunk 的名字就是成员的 mangled 名后面接 `To`，去掉后缀就是实现名；initializer 的两个入口只差最后的 `fc` / `fC`。下游按名字推导的几处——导出判定往名字后面拼 `Tj` / `Tq`，ObjC 方法表按「名字 + `To`」联结（initializer 按 allocator 名换成 `…fcTo`），`applyThunkAttributes` 按成员名打 `@objc`——都不用改。
- **树**：thunk 的树是 `global(objCAttribute, <entity>)`，去掉标记节点得到 `global(<entity>)`，与实现符号 demangle 出来的形状一样，所以 vtable 的 `Tq` 按节点联结照常命中。`handleTick(_:)` 这种实现指针为 null 的槽也能联结上，成员于是按槽号排序。initializing entry point 的 entity 是 `constructor`，要改写成 `allocator`：builder 只认 allocator，vtable 槽、ObjC 方法表与 ABI 身份也都按 allocator 记。
- **偏移**：thunk 是 `@objc` 成员唯一的代码，initializing entry point 是 initializer 唯一的代码，地址注释就指向它们。注意 thunk 用的是 Objective-C 的调用约定（`x0` 是 `self`，`x1` 是 `_cmd`），不是 Swift 的。
- **一个 initializer 两个入口都剩下**（`XcodeServiceAppDelegate.init()` 有 `fc` 与 `fcTo`，没有 `fC`）：initializing entry point 的替身排在 thunk 的替身前面，先到者胜，地址落在 Swift 的入口上。

## 什么时候不补

- **真实符号或 0054 的 `Tq` 替身已经声明了这个成员**：按成员实体节点结构相等判断（`declaredEntityKey(of:)`，merged function 先跳过它开头的标记节点）。造替身之前还会先按名字查实现符号在不在，在就不造：没有被优化掉的镜像里，几乎每个 `@objc` 成员和 initializer 都是这种情况，这一步省掉了逐个物化、intern 再丢弃的开销。
- **`…ToTm`**：几个 thunk 合并后共用的函数体。`Xcode Service` 里 `canBecomeKey` 等三个 thunk 都是 `mov w2, #imm; b` 跳进同一个 `…ToTm`。它不是成员，扫描时第一个子节点是 `mergedFunction`，根本进不了新索引。
- **`__ivar_destroyer`**（`…fETo`）：`processMemberSymbol` 不认它，同样不进新索引。

## 边界

- **泛型类与经 `__objc_stublist` 登记的类没有静态的 class object**，读不到它们的 ObjC 方法表，替身成员只有 thunk 给的 `@objc`，没有 `override`，显式 selector 也不判。ObjC 侧另立提案，需要 MachOObjCSection 先让索引器接受宿主补进来的类（issue #137 第二部分）。
- **`class` 与 `static`**：没有 vtable 槽的类型级成员照旧打成 `static`，与有实现符号时一样（见 [ClassMemberKeywordRecovery.md](ClassMemberKeywordRecovery.md)）。
- **interface 里替身成员与普通成员看起来一样**，替身从哪来只在 dump 里写明。从 initializing entry point 建出的 initializer，dump 本来就列在 `/* Constructor */` 下，没有改。
- **0054 的「ABI 墓碑不补」照旧**：墓碑槽本身不造替身。槽对应的成员若还剩 initializing entry point 或 `@objc` thunk，由那一边的替身补上，槽号经节点联结照常挂上。

## 验证

- `ThunkOnlyMemberFixture`（MachOTestingSupport）把同一份源码编两次：`-Onone` 保留每个入口，是独立的事实；`-O -wmo` 复现 app 的 Release 构建。内部类的 ObjC 覆写（`description`、`isEqual(_:)`、`init()`）、`@objc` 方法与 `@objc class func`、同模块 extension 里的 `@objc` 方法、`NSObject` extension 里的 `@objc` 方法、泛型类的覆写与它合成的 `init()`，以及只剩 `fc` 的 `init(values:)`。
- `ThunkOnlyObjCMemberTests`（SwiftInterfaceTests）：先钉住前提（优化版里 `isEqual(_:)` 只有 thunk、`init(values:)` 只有 `fc`，否则后面的断言会在不再删 entry point 的编译器上空过）；两份构建打印出的各声明块成员集合相同；`@objc` / `override` 按 ObjC 方法表给出，泛型类只有 `@objc`；替身的地址是 thunk 或 `fc` 的地址；进程内 `MachOImage` 与文件打印相同。
- `ThunkOnlyObjCMemberDumpTests`（SwiftDumpTests）：优化版的 dump 有 `[ObjC Thunk]` 各节和方法表注释，未优化版没有这一节，泛型类的 thunk 行不带 ObjC 注释。
