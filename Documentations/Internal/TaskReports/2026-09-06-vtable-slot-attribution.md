# 2026-09-06 vtable 槽归属改用 method descriptor 符号

对应提案：[0020-vtable-slot-attribution-via-method-descriptor-symbols](../../Evolutions/0020-vtable-slot-attribution-via-method-descriptor-symbols.md)

## 问题

用户在 Hopper 里看 `SwiftUI.GraphHost`（iOS 18.5 simruntime 的 SwiftUICore，arm64）的 vtable 布局，发现与 `swift-section dump` 的输出对不上。

## 调研

直接解析二进制取真值，不依赖工具自身的输出：

- 类描述符在 `0x98c9c8`，`VTableDescriptorHeader` 给出 `vTableOffset = 20`、`vTableSize = 10`，十条 method descriptor 连续排在 `0x98c9fc`–`0x98ca44`。
- 每条 descriptor 自带一个 `Tq` 符号（`nm` 里是 `S` 型全局数据符号），demangle 后就是这个槽的真实成员。
- 与 dump 输出对照：槽 23/24/25 正确，槽 26–29 **四条全错**——真值是 `instantiateOutputs` / `uninstantiateOutputs` / `timeDidChange` / `isHiddenForReuseDidChange`，dump 打的是 `isHiddenForReuseDidChange` 加三条属于嵌套 struct `GraphHost.Data` 的协程 resume 函数。
- 槽 20/21/22 打 `Symbol not found`。读 class metadata（`0xaaa000`）的对应 word 发现它们是 chained-fixup **bind** 槽，import ordinal `0xc1c` 解出来是 `_swift_deletedMethodError`：成员被删除、槽位为 ABI 保留、调用即 trap。descriptor 侧 implementation 为 null 正是这个缘故。

根因两条：

1. 归属主源选错。`ClassDumper` 用实现地址反查符号，而 linker 的 identical code folding 把字节相同的函数体折叠到一个地址——`0x9330`（空 `ret`）上有 **2878** 个符号，这个映射没有逆。
2. 候选筛选过松。`node.first(of: .class)` 找的是树里**任意位置**的第一个 class 节点，`GraphHost.Data.graph.modify` 的 context 链是 `class GraphHost → struct Data`，于是嵌套类型的成员被当成本类的。

影响面（171 个非泛型带 vtable 的类 / 512 个槽）：16.2% 的槽实现地址上有多个符号，14.1% 与别的槽共享同一地址（必然至少错一个），71.7% 的槽 descriptor 自带 `Tq` 可精确归属。

## 方案

`Tq` 是每个成员一个、位于 descriptor 自身地址的数据符号，ICF 影响不到——提案 0006 修 `final` 误判时已经确认过这条性质，但只用作否定证据。这次把它用作正向归属的主源，实现地址反查降级为回退。

## 实际执行

按提案做完主 vtable 循环 + interface 索引路径 + `validNode` 上下文修正后，有两处必须靠测试才发现的错误：

1. **override 不能走 `Tq`**。最初把 `attributedMemberNode` 也给了 `MethodOverrideDescriptor` / `MethodDefaultOverrideDescriptor`（经它们指向的父类 descriptor 取 `Tq`）。结果 `override` 关键字从 interface 输出里整个消失：`TypeDefinition.index` 的 joinKey 是要跟**本类**成员符号对上的，父类形状的节点匹配不到任何东西。`SymbolTestsCoreE2ETests.outputContainsOverrideKeyword` 抓住了。
2. **`dumpMethodDeclaration` 里的残留**。撤回后仍在这个 helper 里留了 `Tq` 主源，而 override 循环的 `.element` 腿会用**父类的** descriptor 调它，于是 `override ResilientChild.init()` 被打成 `override ResilientBase.init()`，还丢掉了实现符号携带的 `vtable thunk … dispatching to …` 细节。这一处单元测试没覆盖，是逐条审查快照 diff 时发现的。

教训是同一个：`Tq` 回答的是「这个 descriptor 声明了谁」，override 槽问的是「本类的实现是谁」，两者不是同一个问题。

另有一处主动放弃：`ProtocolDumper.validNode` 按同样思路收窄上下文匹配后，`base conformance descriptor for P: Q` 这类**没有 entity 节点**的要求描述符被整批丢弃，SwiftUICore 的协议输出 1033 行退化为 `[Stripped Symbol]`。协议侧符号不只是成员，需要自己的证据模型，已回退并在代码注释里写明原因。

## 验证

- **红/绿**：源码改动整体回退后新增的 5 条测试红 3 条（9 个 issue），恢复后 5 条全绿。
- **fixture 复现**：`open class Host` 三个空方法 + 一个嵌套 `class Nested` 的空方法，`-Xlinker -deduplicate` 强制折叠。修复前 dump 出 `beta`/`alpha`/`gamma`（符号表顺序），修复后 `alpha`/`beta`/`gamma`（`Tq` 地址顺序）。嵌套串味在这个规模复现不出来（取决于 linker 把嵌套成员排在符号表的哪个位置），相关两条测试是防御性的，已在注释里写明。
- **全库 A/B**（SwiftUICore）：828 条声明行变化；7 处 `.resume.` 串味全部消失、零新增；`Symbol not found` 358 → 0（195 条拿到真名，163 条转为带墓碑注释的 `<unnamed vtable slot>`）；零行从有名字退化成 `sub_` 地址。
- **机械比对**：1199 个 `Tq` 符号按地址排序作真值与 dump 槽序列逐类比对，55 个可比对的类里 54 个相对顺序完全一致，0 个顺序错配（余下 1 个是比对脚本把嵌套类成员按名字前缀算给了外层类）。
- **`validNode` 隔离 A/B**：单独回退这一处，输出逐字节不变——`Tq` 主源已覆盖所有出问题的槽，它是纯加固。
- **快照**：10 份基线更新，逐条审查确认全部为修正（详见提案决策日志）。其中两条意外收获：`FinalMembersTest` 的 kind 注释与名字系统性错位（`[Setter]` 配 `plainMethod()`）得到修正；interface 里 `classMethod` 从 `static func` 修正为 `class func`——fixture 源码写的就是 `public class func`，此前因归属错位没 join 上 descriptor 而误印。
- **全量测试**：`swift test --skip IntegrationTests` 通过（退出码取自 `swift test` 本身，不看 xcsift 摘要）。

## 与提案的偏离

- 提案原计划三类 descriptor 都用 `Tq`，实际收窄到只有 `MethodDescriptor`，理由见上。
- 提案原计划一并修 `ProtocolDumper` 的同类模式，实测退化后回退。
- 提案说渲染 A/B 脚本的逐字节判据「会红且属预期」，实际改用上面的定量比对（`Tq` 真值机械核对 + 分类统计）作为验收证据，比人工看 diff 更可证伪。

## 环境备忘

新建的 worktree 里 `Tests/Projects/SymbolTests/DerivedData` 不存在（gitignore 从不检出），fixture 绑定的测试会在毫秒内全部失败并报 `NSCocoaErrorDomain Code=4 "The file 'SymbolTestsCore' doesn't exist."`。本次按 AGENTS.md 的规程处理：确认分支相对 `next` 在 `Tests/Projects/` 下无 diff、且仓库根已有的 fixture 二进制比源码新，然后符号链接过去，未重新构建。
