# `LocatableLayoutWrapper` 三项要求收进 `@LocatableLayoutWrapping` 宏

- **日期**：2026-09-11
- **提案**：[locatable-layout-wrapping-macro](../Evolutions/0027-locatable-layout-wrapping-macro.md)（轻量档）
- **起因**：用户："给 ResolvableLocatableLayoutWrapper 的要求写一个宏吧，现在太多这几行代码了"

## 问题

`ResolvableLocatableLayoutWrapper`（= `LocatableLayoutWrapper & Resolvable`）有三项存储级要求，
每个 wrapper 都得逐字写一遍：

```swift
public var layout: Layout
public let offset: Int

public init(layout: Layout, offset: Int) {
    self.layout = layout
    self.offset = offset
}
```

一个典型的 wrapper 里，这 7 行比真正承载信息的 `Layout` struct 还长。

## 调研

### 样板的实际规模与形状

全库统计（`Sources/` 下全文扫描，按 brace 配对定位宿主 struct）：

- **97 处**样板 init，全部集中在 `Sources/MachOSwiftSection/Models/`，分布在 96 个文件里
  （`ProtocolRequirement.swift` 一个文件里有两个 struct）。
- 97 个 init 体只有**一种**差异：两条赋值语句谁先谁后（51 处 `layout` 在前，46 处 `offset` 在前）。
  没有任何一处带校验、日志或额外赋值。
- 属性形状 84 处是 `public var layout` + `public let offset`，3 处偶然写成 `public var offset`
  （`ProtocolDescriptor` / `ProtocolWitnessTable` / `AssociatedTypeRecord`）。全库检索 `.offset = `
  确认没有任何地方给它们赋值，`var` 纯属历史偶然。
- 泛型宿主只有两个：`AnyLocatableLayoutWrapper<Layout: LayoutProtocol>`（`Layout` 是泛型参数）
  和 `FullMetadata<Metadata: MetadataProtocol>`。

### 基础设施已经齐备

项目已有 `MachOMacros` 宏 target（现存 `@Layout`，贴在 layout protocol 上生成字段偏移枚举）
与 `Sources/Utilities/Macros/` 的宏声明位置。`MachOSwiftSection/Exported.swift` 的
`@_exported import MachOBase` 加上 `MachOBase` 的 `@_exported import Utilities`，使宏在该模块
每个文件里都可见，97 个文件无需新增 import。

### 一处不做调研就会踩的连带影响

`PublicMemberScanner`（覆盖率不变式的「预期集合」来源）是**纯源码扫描**，看不到宏展开结果，
而 `layout` / `offset` 恰恰被它当作 public 成员统计：170 个 baseline 文件中有 **96 个**的
`registeredTestMethodNames` 含这两个名字，`CoverageAllowlistEntries.swift` 里也有大量条目带它们。
样板一旦移进宏，`MachOSwiftSectionCoverageInvariantTests` 的「② extra —— 注册了却找不到对应声明」
会大面积变红。

好消息是 `init(layout:offset:)` 早就被扫描器显式跳过（`isMemberwiseSynthesizedInit`，注释里
还留着已经不存在的 `@MemberwiseInit` 的痕迹），这一项不受影响。

## 最终方案

用户在一轮澄清提问里对三个决策点全部选了推荐项：

1. **宏只生成三项要求，不生成 conformance**——协议名留在声明处，源码可搜；带多重 conformance
   的类型不必一半手写一半生成。
2. **97 处一次性全换**——形状唯一，分批只会让两种写法长期并存。
3. **改扫描器认宏**——而不是从 96 个 baseline 里删掉 `layout` / `offset`。

宏命名 `@LocatableLayoutWrapping` 而非 `@LocatableLayout`，与已有的 `@Layout` 区分开：那个描述
字段布局，这个让类型满足 `LocatableLayoutWrapper`。

## 实际执行

| 位置 | 动作 |
|------|------|
| `Sources/MachOMacros/LocatableLayoutWrappingMacro.swift` | 新增 `MemberMacro` |
| `Sources/MachOMacros/MachOMacroPlugin.swift` | 注册 |
| `Sources/Utilities/Macros/LocatableLayoutWrapping.swift` | 宏声明 |
| `Sources/MachOFixtureSupport/Coverage/PublicMemberScanner.swift` | 见到该属性就补回 `layout` / `offset` 两个 key |
| `Sources/MachOSwiftSection/Models/**`（96 个文件） | 删样板、加属性行 |

宏的两个设计细节：

- **生成成员跟随宿主的访问修饰符**。现存 97 处全是 `public`，但今后的内部工具类型不该被迫公开。
- **宿主已手写同名成员时跳过该项并发 warning**。静默跳过会让「宏没生效」难以察觉。

### 迁移方式

写了一个一次性 Python 脚本（`/tmp/claude/migrate-locatable-layout-wrapping.py`，不入库），
拒绝式设计：只删精确形状、且必须在宿主 struct 的**顶层**（brace 配对判定，不是全文正则）、
三项缺一不可、init 体必须恰好是那两条赋值、成员上方挂着注释或属性就拒绝——任一条不满足就
报告位置并让**整个文件原样不动**。实跑 94 个文件零异常（另外 2 个在验证宏时已手工改完）。

脚本的第一版用全文件正则做空行清理（`\n\n+(\s*)\}` 之类），那会把库里所有「闭括号前的空行」
都吃掉、改到与本次无关的代码；改成只在被编辑的 struct 体内收拾。

## 验证

1. **展开文本逐字一致**（提案里列的第 4 项，也是「不跑渲染 A/B」这个决定的前提）：
   `-Xswiftc -Xfrontend -Xswiftc -dump-macro-expansions` 抽查 `MethodDescriptor`，展开为

   ```swift
   public var layout: Layout

   public let offset: Int

   public init(layout: Layout, offset: Int) {
       self.layout = layout
       self.offset = offset
   }
   ```

   与被删掉的手写代码逐字相同。
2. **全量 `swift test --skip IntegrationTests`**：1796 个测试 / 333 个套件，唯二的失败是
   `SharedCacheTests` 的两处墙钟并行度断言（`elapsedSeconds < parallelBudget`）——已知 flaky，
   全量并行跑负载高时假失败，单独复跑 0.41 秒通过（预算 0.8 / 1.2），且所在模块
   （`MachOCaches`）与本次改动无关。
3. **覆盖率不变式四条全绿**，且 `__Baseline__/` 与 `CoverageAllowlistEntries.swift` 的
   `git status` 为空——扫描器补偿写对了的直接证据。
4. **ABI 字面量基线套件绿**：它们断言的正是从这些 wrapper 读出的绝对实现偏移，是展开后读取
   行为不变的最强证据。
5. 不跑渲染 A/B：不触及 demangling / printing / indexing / reader 栈的任何逻辑，展开产物与
   手写代码逐字相同。

## 与方案的偏差

无。三个决策点按批准的方案执行，验证项全部落实。

一处提案里没预见、实际做时补上的：`PublicMemberScanner` 里 `isMemberwiseSynthesizedInit` 的
注释说的是「`@MemberwiseInit` 展开出来的 init」——这个宏早已不在该文件的语境里，顺手改成了
现在的事实（手写与 `@LocatableLayoutWrapping` 生成的一视同仁跳过）。
