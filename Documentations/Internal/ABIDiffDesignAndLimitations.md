# ABIDiff — Design and Limitations

> 面向维护者的设计说明。记录 `SwiftDiffing` 模块（ABI 变更比对引擎）的架构、
> 关键设计取舍，以及一组**当前的已知局限**——其中大多数源于 ABI 信息本身不在
> 二进制里，而非实现取巧。代码中每条局限都对应一个 `TODO(P2)` 注释。
>
> 配套文档：注释化接口渲染见 [`DiffableInterfacePlan.md`](DiffableInterfacePlan.md)
> （两者共用同一套 `ABIKey` 匹配，互不依赖）。

## 概述

`ABIDiffer` 比对两个已索引 Swift 模块的 ABI：把每个声明按其 remangle 后的
`Node`（`ABIKey`）建索引，再对 types、protocols、四类 extension bucket、以及
globals 做**递归三路集合差分**。

核心性质：**diff 本身不接触 Mach-O**。一旦两侧索引完成，比对纯粹在
`SwiftDeclaration` 模型（值数据）上进行。这带来两个入口：

- **Live**：`diff(old: ABIModule, new: ABIModule)` —— 直接比对两个 live 模块。
- **Frozen**：`diff(old: ABISnapshot, new: ABISnapshot)` —— 比对两个冻结快照
  （`Codable`，可持久化为 baseline）。

二者**共用一套算法**：live 入口先 `snapshot(of:)` 再调用 frozen 入口
（`ABIDiffer.swift`），所以"一次 live diff"与"一次 baseline diff"在构造上
不可能给出不同结果。

## 架构

### 身份键与载荷键（`ABIKey` 的两个角色）

`MemberRecord` 用两个 `ABIKey` 驱动算法（见 `MemberRecord.swift`）：

- **`identityKey`** —— 在两侧之间**匹配**成员（added / removed / common）。
  对有 symbol 的成员（function / variable / subscript）它是 remangle 后的声明
  节点，即 ABI 身份；对无 symbol 的实体（stored field、enum case、deinit、
  associated type）它是带命名空间前缀的源码名（如 `"field:foo"`、`"case:bar"`），
  所以重命名表现为 add + remove。
- **`payloadKey`** —— 在**已匹配**的成员之间检测变更。它折入身份未编码的
  ABI 相关属性：variable / subscript 折入 accessor 集合（故 `let` → `var` 报
  `.modified`），field 折入类型（故同名 retype 报 `.modified`），enum case 折入
  discriminant `tag`（故重排 / 中插报 `.modified`）。

> **关于 function：identity == payload。** 对 function，mangled 声明节点已编码
> static-ness 与 flavor（allocator / init），故身份即载荷——一个被匹配上的
> function symbol "by construction" 就是未变的。**因此 function 签名一旦改变，
> 身份随之改变、匹配不上，表现为 add + remove 而非 modified。这是有意设计**
> （不同 mangled symbol = 不同 ABI 入口点），不是缺陷。"modified" 只发生在
> identity 稳定而 payload 变化的成员/容器上。

### 三路匹配

`threeWayMatch` 是唯一的通用匹配器：把两侧按 identity 建索引，分为
old-only（`removed`）、new-only（`added`）、双侧都有（`common`，成对）。
调用方决定如何比较每个 `common` 对（成员级比 `payloadKey`，容器级递归 diff 成员）。
输出按 `(sortKey, status)` 确定性排序，重复运行结果一致。

### Extension bucket 合并

索引器把一个类型的多个 conformance、条件块、合成嵌套块拆成多个
`ExtensionDefinition`，归在同一个 `ExtensionName` 下。快照阶段**每个
`ExtensionName` 冻结成一个 container，跨该 bucket 下所有 definition 合并成员
记录**（`extensionBucketSnapshots`）。理由：extension 边界本身不导出，导出的是
成员；合并让"新增/移除整个 conformance"可见，并避免 per-definition 键的
碰撞丢弃。

## 已知局限

### 1. `@frozen` 不可从二进制恢复 → 兼容性判定一视同仁

兼容性判定（`Compatibility.swift`）把"新增声明"判为 `.additive`、"移除/改签名"
判为 `.breaking`。这对 resilient 类型正确，但**对 `@frozen` 类型，追加存储字段
实为 ABI-breaking 却被判 `.additive`**。

根本原因：`@frozen` 无法从二进制恢复。它是源码/ABI 概念，编译器在布局期消费后
**不写进任何元数据**——已核验 `swift/include/swift/ABI/MetadataValues.h`：

- `TypeContextDescriptorFlags`（每个 struct/enum/class 都带）**没有 frozen 位**，
  只有 `MetadataInitialization`(2-bit)、`HasImportInfo` 和 Class 专属位。
- `GenMeta/GenStruct/GenEnum.cpp` 不发射 frozen 字段；反射 `Records.h`
  （FieldDescriptor）也无 frozen/resilient 位。
- resilience 是 AST 期计算（`AST/Decl.h` 的 `isResilient()`，依赖
  `isFormallyResilient()` + accessing module + `ResilienceExpansion`），不序列化。

唯一代理 `hasSingletonMetadataInitialization` 表示"是否需要运行时补全布局"，
与 `@frozen` 在真实场景下分叉：

- **假阴性**：`@frozen` 类型含一个别模块的 resilient 字段 → 自身大小仍依赖其
  运行时尺寸 → 仍是 `SingletonMetadataInitialization`，被误判为非 frozen。
- **假阳性**：未开 library evolution 的模块 → 所有类型固定布局 →
  `NoMetadataInitialization`，但谁都没写 `@frozen`、也没承诺 ABI 稳定。
- 泛型类型无论 frozen 与否都需实例化。

把这个不可靠代理塞进 `backward-compatible: true/false` 头牌结论会"带着自信
出错"，故判定**一律按 resilient 处理**，字段增删的 frozen 语义由读者自行判断。

> 真正的修复需要模型从源头携带可靠的 frozen/resilience 标志，而该标志在二进制
> 中不存在。除非改为消费源码（`.swiftinterface` / AST），否则无解。

### 2. `ABIKey` 的 `.mangled` / `.printed` 跨侧不对称

`ABIKey.make(for:)` 在 remangle 成功时返回 `.mangled`、抛错时返回 `.printed`，
两者是不同 case，永不相等，故分支属于身份的一部分。remangle 对给定节点是确定的，
所以两侧呈现**相同节点**时稳定。但若两个二进制对"同一声明"发射**结构不同**的
demangle 树（例如不同 toolchain 构建），且一棵能 remangle、另一棵抛错，身份就会
`.mangled` ↔ `.printed` 翻转，声明表现为 removed + added 而非 modified。

窄——需要罕见的抛错路径恰好只出现在一侧；且树结构不同通常**本就**意味着真实变更。
故文档化而非绕过：一个与 remangle 成败无关的身份需要重做键，且会损失别处精度，
不划算。见 `ABIKey.swift` 的 `make(for:)` 注释。

### 3. `keyed` 碰撞静默丢弃

`keyed`（`ABIDiffer.swift`）在键碰撞时保留首个、丢弃其余，**可能掩盖一次
removal**（breaking 被误判为 compatible）。单个容器内碰撞基本不可能（合法重载有
不同 mangled 键，field / case / associated type 各有命名空间）。唯一现实场景是
**合并后的 extension bucket**：两个条件 extension（`where T: P` vs `where T: Q`）
各声明一个成员、而 mangling 未编码 `where` 子句，合并进同一 bucket 后撞键。

正经修复需要在 `ABIDiff` 上加一条**诊断通道**（结果类型目前没有），故当前丢弃是
静默的。见 `keyed` 的 `TODO(P2)`。

### 4. resilience-aware 的字段顺序 / flags 未折入

- 存储字段顺序**故意不**折入 `payloadKey`：对 resilient struct 重排字段是
  二进制兼容的，折入会造成假阳性。（enum case 顺序无条件 ABI-significant，
  用 `makeCase(_:tag:)` 单独处理。）
- 字段 flags（`weak` / `lazy` / `indirect`）尚未折入 `payloadKey`，故仅 flag
  变化（名+类型不变）当前不可见。见 `MemberRecord.swift` 的 `make(_ field:)`
  `TODO(P2)`。

### 5. 每 conformance / per-`where`-block 归属未做

extension bucket 合并到 `ExtensionName` 粒度，未按具体 conformance / 条件块
归属变更。需要索引器把已解析的 protocol 名 plumb 到每个 definition 上。
见 `extensionBucketSnapshots` 的 `TODO(P2)`。同理，conformance-extension 的
associated-type witness 因 name 访问器 Mach-O-bound，暂无法 Mach-O-free 投影。

## 局限 → 代码位置对照

| 局限 | 位置 |
|---|---|
| 1. frozen 不可恢复 | `Compatibility.swift`（enum doc + `isBackwardCompatible`） |
| 2. ABIKey 跨侧不对称 | `ABIKey.swift` `make(for:)` |
| 3. keyed 碰撞丢弃 | `ABIDiffer.swift` `keyed` |
| 4. 字段顺序 / flags | `MemberRecord.swift` `make(_ field:)` |
| 5. per-conformance 归属 | `ABIDiffer.swift` `extensionBucketSnapshots` / `memberRecords(of: ProtocolDefinition)` |
