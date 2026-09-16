# Draft - `@_rawLayout` 人造字段、空名字 enum case 与静态布局的依赖搜索路径

- **状态**: In Progress
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **关联提案**: [draft-builtin-borrow-support](draft-builtin-borrow-support.md)（同一分支的前一批，提供本批依赖的 bitwise-borrowable / addressable-for-dependencies 两个事实）
- **实现分支 / PR**: `feature/swift-6.4-adaptation`
- **配套文档**: [Modules/SwiftLayout.md](../Internal/Modules/SwiftLayout.md)（同批补 raw layout 一段）

## 摘要

Swift 6.4 的编译器给 `@_rawLayout(like:)` 结构体的字段描述符多发一条**人造字段记录**（flag `isArtificial`，名字 `_rawLayout`，类型 = like 类型），专门让离线工具能算出这类类型的大小；macOS 27.0 cache 里 `Synchronization.Atomic` 与 `_Cell` 已经带着它。本库把它当普通存储属性：dump / interface 打出 `let _rawLayout: A`，`diff` 把它报成新增字段并判 ABI-breaking，静态布局引擎则继承了 like 类型的 extra inhabitants（上游 RemoteInspection 在同一版本修掉的错：raw layout 类型没有 extra inhabitant，`Optional<_Cell<指针>>` 会少算一个 tag 字节）。同版本还开始为「运行时不可达」的 enum case 发空名字、空类型的记录（只在实验特性 custom availability domain 下出现），本库会把空指针读成空字符串再打出 `case `。第三件事是调研时发现的既有缺口：`--dependency-search-path` 只喂给 accessor thunk 解析器，静态布局的依赖闭包写死用宿主机 cache，跨 OS 版本算不了布局。

## 方案

**打印（SwiftPrinting）**：`renderModelFields` 跳过 `isArtificial` 字段；`printIncludedTypeDefinition` 在类型级 attribute 之后，若存在名为 `_rawLayout` 的人造字段，多打一行 `@_rawLayout(like: <like 类型>)`——这是源码里真正写着的东西。`movesAsLike` 二进制里没有记录，不猜、不打。

**dump（SwiftDump）**：dump 的契约是「记录里写了什么就打什么」，所以人造记录仍打，但前面加一行注释说明它是 `@_rawLayout(like:)` 的存储描述而非存储属性。

**diff（SwiftDiffing）**：人造字段不进 member record——它不是成员。代价是 like 类型改变（等价于 raw layout 尺寸改变）不会被 diff 捕捉；这在 6.4 之前本来就捕捉不到，属既有边界，记入文档。

**静态布局（SwiftLayout）**：`fieldLayouts(ofFieldDescriptorOwner:)` 对人造记录做三处修正后再折叠进 `BasicLayout`：extra inhabitant 记 0（raw layout 类型没有）、bitwise-borrowable 记否（`RawLayoutFlags` 注释：raw layout 类型目前都不可按位借用）、addressable-for-dependencies 记是（SIL `TypeLowering` 对 `@_rawLayout` 无条件 `setDefinitelyAddressableForDependencies`）；size / stride / alignment 沿用 like 类型。bitwise-takable 仍沿用 like 类型——`movesAsLike` 不可知，这是一个只影响 flag、不影响任何偏移的已知偏差。字段偏移渲染路径（`accumulateFieldLayout`）对人造记录同样把 extra inhabitant 记 0。

**空名字记录（MachOSwiftSection + 两条打印路径）**：`FieldRecord.fieldName` 在相对指针为 0 时明确返回空串（此前是「碰巧读到四个零字节」）；`printThrowingEnumCase` 与 `EnumDumper` 对空名字的 case 打一行注释而不是 `case `，enum 布局照常把它算作一个 case（编译器仍给它留 tag）。

**CLI**：`--dependency-search-path` 同时决定静态布局的依赖闭包：用户路径在前、宿主机 cache 兜底，dump 与 interface 两个子命令一致；帮助文本相应改写。

**非标准库的 `@_rawLayout`**：它是实验特性（`.enableExperimentalFeature("RawLayout")`），任何模块都能用，上面的判定只看 flag 加名字、不看模块名，这一点本来就成立；但 attribute 有三种写法，二进制里留下的东西各不相同（Xcode 27 编的探针 dylib 实测）：

| 写法 | 二进制里有什么 | interface | 静态布局 |
|---|---|---|---|
| `like: T`（含泛型） | 人造 `_rawLayout` 记录（非泛型时还有 builtin 描述符） | `@_rawLayout(like: T)` | 按人造记录 |
| `size: N, alignment: M` | 只有 `__swift5_builtin` 描述符 | `@_rawLayout(size: N, alignment: M)` 加一句来源注释 | 引擎本来就先查 builtin 描述符，正确 |
| `likeArrayOf: T, count: N`（非泛型） | 只有 builtin 描述符 | 同上（记录里分不出这两种写法，注释说明「源码可能写的是 likeArrayOf」） | 正确 |
| `likeArrayOf: T, count: N`（泛型） | **什么都没有** | 无 attribute | **算成 0 字节且无法检测**：与空泛型 struct 在二进制里无法区分；这是上游 6.4 只给标量 `like:` 发人造记录留下的缺口，只能记录 |

builtin 描述符是 IRGen 对 `@_alignment` / `@_rawLayout` 类型一律发的「不透明尺寸记录」，C 导入 struct 与多 payload enum 也有；打印器只在「非泛型 struct、没有任何字段记录、描述符 size > 0」时采信它——有存储属性就不可能是 `@_rawLayout`，`@_alignment` 的空 struct 记录 size 0，`like:` 写法由人造记录优先回答。索引按 `TypeName` 结构相等键控，一个打印器建一次。

两个顺带发现：**其一**，运行时与编译器对 raw layout 的 extra inhabitant 意见不一致——编译期布局（IRGen `StructLayout` 清空 spare bits）与 6.4 的 RemoteInspection 都算 0 个，`Optional<LikeCell<指针>>` 是 9 字节；但 `swift_initRawStructMetadata` / `…2` 实例化泛型 raw layout 元数据时照抄 like 类型的 `extraInhabitantCount`，同一类型经泛型函数拿到的 Optional 是 8 字节（`-Onone` 加 `_openExistential` 逼出运行时路径实测）。本库跟编译期那套，那才决定字段偏移；这是上游 bug，是否上报由用户定。**其二**，部署目标低于 macOS 27 时 `NoncopyableReflectionSafety` 把每个非拷贝字段的类型都套进 accessor thunk，thunk 读取器能解出名字，静态布局引擎见到 `AccessorFunctionReference` 就放弃——用户自己写的 raw layout 类型全是 `~Copyable`，所以含这类字段的 struct 在普通部署目标下一律算不出偏移。既有缺口，另开提案 [draft-static-layout-through-accessor-thunks](draft-static-layout-through-accessor-thunks.md)。

**验证**：布局侧用本机归档的 macOS 27.0 cache（`/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e`，按 `ArchivedIOSCacheThunkTests` 的先例以文件存在为开关）：`Synchronization._MutexHandle` 的 `value: _Cell<os_unfair_lock_s>` 应为 4 字节、0 extra inhabitant；interface 输出应含 `@_rawLayout(like: A)` 且不含 `let _rawLayout`。空名字记录没有可用语料（触发条件是实验特性），只做代码路径改动并记录为未覆盖。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | 创建为 Draft，随「开工」进入 In Progress | 调研报告第 3 批 |
| 2026-09-16 | interface 打成 `@_rawLayout(like:)` attribute，dump 保留记录加注释 | interface 的契约是「像源码」，源码里就是这个 attribute；dump 的契约是「记录原样」 |
| 2026-09-16 | diff 直接排除人造字段 | 它不是成员；like 类型变化本就不在 diff 的能力边界内，与其把工具链差异报成 ABI 变化不如诚实缺失 |
| 2026-09-16 | `movesAsLike` 不推断 | 二进制无记录；bitwise-takable 只影响 flag 不影响偏移 |
| 2026-09-16 | 人造记录的判定收窄为「`isArtificial` 且名字为 `_rawLayout`」 | 第一版只看 flag，把 actor 的 `$defaultActor` 存储（编译器同样标 artificial）从 interface 里删掉，`SymbolTestsCoreInterfaceSnapshotTests` 变红；`$defaultActor` 是真字段，要照旧打印 |
| 2026-09-16 | 实现完成并验证通过，状态保持 In Progress（落地 commit 时改 Implemented 并分配编号） | Xcode 26.6 + 本地 sibling：`SwiftLayoutTests \| SwiftInterfaceTests \| SwiftDumpTests \| SwiftPrintingTests \| SwiftDiffingTests` 478 测试 / 87 套件全绿（原始退出码 0），含新增的 `RawLayoutArtificialFieldLayoutTests`（27.0 cache：`_MutexHandle` 4 字节 0 XI、`Optional<_Cell<UnsafePointer<Int>>>` 9 字节）与 `RawLayoutAttributeRenderingTests`；渲染对比：26.6.2 cache 的 SwiftUICore dump 与 Synchronization interface 与 `next` 基线 0 差异，27.0 cache 的 Synchronization interface 只差 `_rawLayout` 相关 8 行、dump 只多 2 行注释 |
| 2026-09-16 | interface 隐藏**全部**人造字段（含 actor 的 `$defaultActor`），dump 照常打；`@_rawLayout(like:)` attribute、diff 排除与静态布局的 raw layout 规则仍按「flag 加名字」判定 | 用户裁定：`$defaultActor` 不该出现在 interface 里，`actor` 关键字 / `@globalActor` attribute 已足够表达；dump 可以标。interface 快照相应重录，diff 恰好是 6 处 `$defaultActor` 及其布局注释 |
| 2026-09-16 | 只留下 builtin 描述符的写法（`size:alignment:`、非泛型 `likeArrayOf:`）在 interface 打成 `@_rawLayout(size:alignment:)` 并加一句来源注释；泛型 `likeArrayOf:` 不打、记入文档 | 用户要求考虑非标准库使用者；三种候选（印并加注释 / 印不加注释 / 不印）中用户选了第一种：布局事实准确，写法可能与源码不同，注释把这一点说明白 |
| 2026-09-16 | thunk 字段的静态布局缺口另开提案，本批不做 | 用户裁定：涉及渲染层与布局引擎的接口，单独一份轻量提案 |
| 2026-09-16 | 运行时照抄 like 类型 extra inhabitant 的不一致只记录、不跟 | 本库对齐的是编译期布局（决定字段偏移）与 6.4 RemoteInspection；上游 bug 是否上报由用户定 |
