# Draft - interface 按 vtable 槽位顺序打印类成员，补上只剩 method descriptor 符号的成员

- **状态**: In Progress
- **创建日期**: 2026-09-28
- **最后更新**: 2026-09-28
- **实现分支 / PR**: `feature/interface-vtable-members`（worktree `.worktrees/MachOSwiftSection-InterfaceVTableMembers`）
- **配套文档**: [DescriptorOnlyVTableMembers.md](../Internal/DescriptorOnlyVTableMembers.md)（实现说明）

## 摘要

用 library evolution 编译的模块里，class 的 public 方法的实现函数符号是 local 的，对外只导出 dispatch thunk（`Tj`，经 vtable 跳转的小桩函数）和 method descriptor（`Tq`，vtable 条目描述符自己的数据符号）。镜像的 local 符号一旦被剥掉，这些实现函数就没有名字了——系统 dyld shared cache 里的 AppKit 就是这样。interface 路径的成员全部从实现符号建（`TypeDefinition+MemberIndexing.swift` 的 `indexMembers`），vtable 只拿来给已经存在的成员补注释，于是这类成员在 interface 里整个消失：macOS 26.7 的 AppKit 里，`NSTableViewDiffableDataSource` 和 `NSCollectionViewDiffableDataSource` 各自只剩 `init` 和 `deinit`，整个 AppKit 少了 53 个成员（40 个方法、11 个属性、2 个下标，渲染 A/B 实测）。同一份 cache 里 SwiftUI、SwiftUICore、Foundation 保留了 local 符号，不受影响。dump 路径逐个 vtable 槽打印、用 `Tq` 命名，一直不缺这些成员。

本提案让 interface 也从 vtable 槽出发：槽的成员没有实现符号时，用它的 `Tq` 符号把成员建出来；class 的 vtable 成员按槽位顺序打印；哪个符号都给不出名字的槽跳过不打印。顺带修掉 `init?` 误判：`Node.initFailabilityKind` 用整棵树的前序搜索找 `returnType`，先碰到的是闭包参数的返回类型，于是非可失败的 `init(collectionView:itemProvider:)`（它的 item provider 返回 `NSCollectionViewItem?`）被打成了 `init?`。

## 方案

**补建成员（索引期，`SwiftDeclaration`）。** `TypeDefinition.classDispatchLookups(in:)` 本来就逐个走本类自己的 `MethodDescriptor`，并优先用 `Tq` 给槽命名。它额外为每个「有 `Tq`、实现指针非 null」的槽造一个成员符号：

- demangled node 取 `Tq` 解开后的成员节点（`global(<entity>)`），和实现符号 demangle 出来的形状相同；
- 名字取 `Tq` 符号名去掉 `Tq` 后缀，也就是实现函数本来的 mangled 名；
- 偏移取 descriptor 里的实现偏移。async 方法的实现指针指向的是 async function pointer（`Tu` 常量），要再跳一次才到函数入口，这样地址注释才和有实现符号时一致。

`indexMembers` 把这些成员符号并进对应类别的输入，但只补实现符号里没有的成员（按成员实体节点结构相等判断），真实符号永远优先。名字之所以用实现函数的 mangled 名，是为了让下游按符号名推导的逻辑原样工作：导出判定（查 `Tj` / `Tq` 等派生形态）、ObjC 方法表 join、ABI diff 的成员身份（重整后的声明节点）。

**打印顺序（`SwiftPrinting`）。** 默认的 `byCategory` 模式下，class 的 vtable 成员（模型里有 vtable 槽号的成员，自己的槽和 override 槽都算）先按槽号顺序打印，也就是 class metadata 里 vtable 的排列顺序；本类自己的槽按源码声明顺序排列，所以这一段读起来和源码一致。其余成员照旧按类别分组打印。`byOffset` 模式本来就按 `orderedMembers`（vtable 成员在前）打印，不变。extension、protocol、值类型不变。

**`init?` 判定。** `initFailabilityKind` 只看 initializer 自己函数类型的直接 `returnType` 子节点（泛型上下文里先跨过 `dependentGenericType` 那一层），可失败的条件是它是 Self 的 Optional。只有一个类型需要特殊对待：声明在 `Optional` 上（含其 extension）的 init，返回 `Wrapped?` 本来就是它的 Self，要再包一层（`Wrapped??`）才算可失败。旧的整树搜索两个方向都会错：闭包参数返回 Optional 时误加 `?`（AppKit 的 `init(collectionView:itemProvider:)`），闭包返回别的类型、而 init 真的可失败时漏掉 `?`（SwiftUI 的 `CoreDisplayLink.init?(displayID:handler:)`）。

**不做的事与默认假设（未单独询问）：**

- ABI 墓碑（实现指针为 null 的槽：dead method elimination 删掉了实现、只保留槽位，见术语表）即使有 `Tq` 也不补建：本镜像里没有这个成员的代码，dump 已经带着墓碑注释列出它。
- 只补 init、方法、getter、setter。modify / read 协程访问器不补：符号索引本来就不把它们当成员，有实现符号时 interface 也从不显示它们，补了反而让剥离前后的输出形态不一致。
- override 槽（override table 里的条目）没有自己的 `Tq`，指向的是父类的 descriptor；没有实现符号时仍然跳过。用父类 `Tq` 归属 override 槽会把名字归到父类身上，见 [0020](0020-vtable-slot-attribution-via-method-descriptor-symbols.md) 的决策日志。
- 补建出来的成员拿不到 `@objc` 和「覆盖 ObjC 父类成员」的 `override`：这两个事实靠 ObjC 方法表按实现符号名 join，剥离过的镜像里（系统 cache 里的 AppKit）实现函数没有符号，thunk 解码也找不到名字。记为已知遗留。
- 合成的 Codable / Hashable 成员在剥离镜像里仍可能缺席：`deduplicateSynthesizedProtocolMembers()` 默认 conformance extension 里一定有一份，于是把类体那份去掉，而剥离镜像里 extension 那份的 witness 也没有符号（AppKit 的 `IncrementalUpdateAction.encode(to:)`）。改动前同样缺席，不在这批处理。
- diff / evolution 的多版本渲染仍按类别排序：两个版本的 vtable 顺序可能不同，没有单一的槽号顺序可依。
- ABI snapshot 的 `formatVersion` 从 5 升到 6：key 方案没变，但剥离过的镜像里 class 容器会多出这批成员，旧 baseline 和新 snapshot 对比会把它们全部误报为新增，理由与 v4 引入 `pwtslot:` 时相同。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-28 | Created as Draft | 用户发现本库生成的 AppKit interface 里 `NSTableViewDiffableDataSource` / `NSCollectionViewDiffableDataSource` 几乎是空的；调研确认原因是 interface 只从实现符号建成员，而系统 cache 里的 AppKit 剥掉了 local 符号，这些实现函数没有名字 |
| 2026-09-28 | 方法跟 dump 一样按 vtable 顺序打印；没有符号的槽跳过不打印；`init?` 误判顺带修；开 worktree 直接修，进入 In Progress | 用户看过原因分析后的指示：「开worktree修，方法跟dump一样按vtable顺序打印吧，没有符号的跳过不打印，第二个问题顺带修了」。走轻量档，方案一节里的默认假设随实现一起交用户过目 |
| 2026-09-28 | 替身成员符号用实现函数的 mangled 名和实现偏移（async 方法再跳一次到函数入口），不直接拿 `Tq` 符号当成员符号 | 导出判定、ObjC 方法表 join、ABI 身份都按实现符号名推导，地址注释也要和有实现符号时一致；直接用 `Tq` 符号，地址会指向 descriptor，导出判定会拼出不存在的名字。验证用现场编译的 fixture：`strip -x` 版与完整版的类声明逐字一致（含槽号与地址） |
| 2026-09-28 | 规模改用渲染 A/B 的实测结果 | 最初按「导出的 `Tq` 里实现符号没导出的」估算，错了两处：把协议 requirement 也算了进去（AppKit 的 180 个里有 65 个，协议从描述符打印，本来就不缺）；更关键的是「没导出」不等于「没符号」——SwiftUI、SwiftUICore、Foundation 在 cache 里保留了 local 符号，实现函数有名字，A/B 里它们一个成员都没多。实测只有 AppKit 被剥光，少了 53 个成员 |
| 2026-09-28 | ABI snapshot `formatVersion` 5 → 6 | key 方案没变，但剥离镜像的 class 容器会多出这批成员，旧 baseline 会把它们全部误报为新增；与 v4 引入 `pwtslot:` 时同一理由 |
| 2026-09-28 | 顺带把渲染 A/B 脚本的归档 cache 常量从 `26.6` 改回 `26.6.2` | 卷上目录又改了名；常量对不上时这条腿静默消失，验证文档记过前两次 |
| 2026-09-28 | `init?` 判定补上「声明在 `Optional` 上」这一种：返回 `Wrapped?` 不算可失败，`Wrapped??` 才算 | 第一轮 A/B 里 SwiftUICore 的 `extension Optional { init(if:then:) }` 被新判定打成 `init?`（旧的整树搜索碰巧先看到 autoclosure 的返回类型，反而没错）。先补测试确认红，再修；第一轮 A/B 的其余 `init` 差异逐条核过都是修正，两个方向都有 |
