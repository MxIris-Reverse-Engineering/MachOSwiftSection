# 2026-08-03 旧格式 bind 支持：LC_DYLD_INFO opcode 回退 + interface 逐项降级

## 问题

系统框架渲染 A/B 验证（同日前一任务）发现：iOS 15.5 模拟器的三个框架 interface 输出只剩 import 和全局函数（Combine 10 行 / WidgetKit 17 行 / SwiftUI 139 行），日志里 `Error resolving ContextDescriptorWrapper: offsetOutOfBounds / invalidContextDescriptor` 成百上千条，而同一批二进制 dump 输出完全正常。维护者要求查根因并修复（明确表示两处都修），同时希望完整了解这类问题的调试方法。

## 调研（调试方法学 walkthrough）

全程没有用交互式调试器，六步收敛，每一步都把假设空间砍掉一半：

1. **grep 错误文案找吞错点**：`Error resolving` 全部来自 `ContextDescriptorWrapper` 的「catch → print → 返回 nil」可选解析包装。这一步同时解释了为什么断点难打——错误被就地吞掉，全局 Swift Error 断点会淹死在无差别 throw 里。
2. **用日志位置代替断点**：错误行夹在哪两条进度 INFO 之间 → 一次运行拿到全量分布——「Types: 271 successful, 2 failed」之后、「Conformances: 370 extensions, **356 failed**」之前有 387 条，打印阶段只有 3-6 条。索引期 conformance 是重灾区，打印期只有零星几条。
3. **健康/病态对照**：macOS 15.5 cache（2025 年二进制）完全健康 → 排除「15.5」版本号因素，指向二进制年代；dump 健康 vs interface 全空 → 说明还有一个 interface 侧的放大器。
4. **顺着计数抓矛盾**：「类型 271 成功」却「输出 0 类型」→ 读 `printRoot` → 整块 `try` 循环 + 块级 catch，第一个抛错的类型吞掉整个类型块——放大器找到。
5. **错误类型溯源**：`offsetOutOfBounds` 在本仓库和 MachOKit 都 grep 不到 → 逐层往依赖找 → swift-fileio 的 `FileIOError`，语义是「拿非法文件偏移去读」→ 指向指针解析错误而非数据损坏。
6. **领域知识收口**：什么会让间接槽位变成垃圾偏移 → bind 未解析 → `otool -l` 对比两代二进制一行定案（15.5 = `LC_DYLD_INFO_ONLY`，18.5 = `LC_DYLD_CHAINED_FIXUPS`）→ grep `resolveBind` 实现，`guard let fixup = dyldChainedFixups else { return nil }` 一锤定音。

**根因链**：① `MachOExtensions/MachOFile+.swift` 的 `resolveBind(fileOffset:)` 只认 chained fixups，旧格式二进制（部署目标 < macOS 12 / iOS 16）的所有 bind 查询返回 nil，指向其它镜像的外部引用（外部 protocol 的 conformance、外部父类）全部按裸指针误读；本地引用不受影响（旧格式磁盘槽位本就存目标地址）。② `SwiftInterfaceBuilder.printRoot` 块级 catch 把单类型打印失败放大成全部类型消失。

可复现性武器：`swiftc -target arm64-apple-macosx11.0` 编译即可强制产出 `LC_DYLD_INFO_ONLY` 格式——旧格式 fixture 可以在测试里即时构建，不依赖模拟器 runtime。

## 方案

1. **fix 1（治本）**：`resolveBind` 在 chained fixups 缺席时回退到 `LC_DYLD_INFO(_ONLY)` bind opcode 流——用 MachOKit 现成的 `bindOperations` / `weakBindOperations` 按 dyld 状态机（segment index / segment offset / symbol name）解释出「文件偏移 → 符号名」索引，惰性构建、按镜像缓存（`@AssociatedObject`）。arm64e 的 threaded 旧格式编码方式不同，遇到即放弃该流（不索引错误偏移）；lazy 流只含 stub，不索引。
2. **fix 2（治放大器）**：`printRoot` 四个 `try` 块（类型 / 特化 / 协议 / 扩展）全部改为循环内逐项 `printCatchedThrowing`——单个定义抛错只丢它自己。横向排查出第五处同类：`SwiftDeclarationPrinter.printThrowingProtocol` 里根协议的 default-implementation extensions 整块 try，一并逐项化。

## 实际执行

- 新增 `Tests/SwiftInterfaceTests/LegacyDyldInfoBindTests.swift`（3 项，永久保留）：fixture 在测试内即时编译（约 1.5 秒）；`fixtureUsesLegacyDyldInfoFixups` 钉住格式前提，`externalProtocolConformancesResolveOnLegacyBinaries` 钉 fix 1（外部 protocol 的 conformance 扩展必须渲染），`interfaceContainsEveryTypeOnLegacyBinaries` 钉住批次整体契约（五个类型一个不能少）。
- **红→绿的阶梯**（每步都实测）：未修 = 7 处断言失败；只上 fix 2 = 4 处（类型缺失从「全部」收敛到「恰好 1 个」——打印期抛错的是 `enum LegacyState`，其余全部恢复，独立证明了逐项降级的价值）；fix 1 + fix 2 = 全绿。
- 代码改动三处：`MachOExtensions/MachOFile+.swift`（opcode 索引 + resolveBind 分支）、`SwiftInterface/SwiftInterfaceBuilder.swift`（printRoot 五处逐项化中的四处）、`SwiftPrinting/SwiftDeclarationPrinter.swift`（第五处）。

## 验证

- 全量 `swift test --skip IntegrationTests`：**1315 测试 / 250 套件全过**（较上批 +3 = 新套件），逐字节 interface 快照未变——现代二进制输出零影响（chained 路径原样）。
- 修复后的 release CLI 重跑 iOS 15.5 模拟器：Combine 10 → 6907 行、WidgetKit 17 → 2795 行、SwiftUI 139 → **81157 行**；三者 `Error resolving` 全部归零，conformance 失败 356/289 计数 → **0**（SwiftUI 7616 个全数解析）。这批二进制上逐项降级甚至没被触发——根因修干净了。
- 横向排查：`dyldChainedFixups` 假设仅此一处；`try await BlockList` 整块模式仅剩的一处已一并修复；`resolveRebase` 无需改动（旧格式本地引用走裸地址路径，A/B 已证实正常）。

## 偏离与教训

- **A/B 基线含义更新**：本批之后 feature 分支对旧格式二进制的 interface 输出与 main **合理地不再一致**（feature 更完整）。渲染 A/B 验证流程文档已同步标注；main 合并本批后恢复对等。
- 打印期抛错的类型起初猜是外部父类的 `LegacyDecoder`，实测是 `enum LegacyState`（raw-value 枚举渲染要解析外部 protocol descriptor）——「先猜后测、以测为准」又一例。
- `swiftc -target` 老部署目标即可在测试内造出旧格式二进制，这个手法值得记住：格式类回归从此不依赖机器上恰好装着的旧模拟器。
