# 0070 - Swift 6.4 的 `borrow` / `mutate` 访问器与关联类型上的 `~Copyable`

- **状态**: Implemented
- **创建日期**: 2026-10-10
- **最后更新**: 2026-10-16

## 摘要

Swift 6.4 带来了两种二进制里会出现、而我们读不出来的声明形态，都是从 Swift 论坛 2026-08-31 的「6.4 实现状态汇总」顺藤摸瓜、再用 Swift 6.4 编出的探针库与 macOS 27 的 libswiftCore 实测确认的：

1. **`borrow` / `mutate` 访问器**（SE-0507，6.4 默认开启）。只有这两种访问器的属性和下标，在 `interface` 与 `dump` 里整个消失；协议要求 `var element: Int { borrow mutate }` 让协议印成空的 `protocol P {}`。原因是符号索引只把 getter / setter 符号收作成员，声明模型的 `AccessorKind` 也只认 get / set / read / modify，而编译器给这两种访问器发的符号是 `…vb` / `…vz`（demangle 成 `borrowAccessor` / `mutateAccessor` 节点），vtable 与协议要求里的 method descriptor 类型是 `Method` 而不是 `Getter`。
2. **关联类型上的 `~Copyable` / `~Escapable`**（SE-0503，6.4）。`associatedtype Element: ~Copyable` 我们印成 `associatedtype Element`，把可以是 noncopyable 的关联类型说成了 Copyable。这一条**二进制本身不记录**：IRGen 只给泛型参数发反向要求（`GenericRequirementKind.invertedProtocols`），关联类型的反向要求在 `addGenericRequirements` 里直接丢弃，协议成员的 mangled name 也不带。唯一可靠的间接证据是同一镜像里这个协议的 extension 签名写了 `where Self.Element: ~Copyable`——SE-0503 规定协议没把 `Element` 声明成可抑制时这样写会编译报错，所以出现即证明。而且只有**主关联类型**（`protocol P<Element>` 尖括号里的）能留下这种证据：SE-0503 只给 extension 补主关联类型的 `Copyable` 默认值，普通关联类型上写 `where Strategy: ~Copyable` 不抑制任何东西，mangling 里也就什么都没有（Swift 6.4 实测）。

## 方案

### `borrow` / `mutate` 访问器

- **符号索引**（`MachOSymbols`）：`borrowAccessor` / `mutateAccessor` 与 getter / setter 同等对待——成员符号、全局符号、`isGlobal` / `isAccessor` 判断都认它们，于是 `dump` 的成员清单也随之列出它们。
- **声明模型**（`SwiftDeclaration`）：公开枚举 `AccessorKind` 新增 `.borrowAccessor` / `.mutateAccessor`（地址注释标签 `borrow` / `mutate`），`AccessorRepresentable` 新增 `hasBorrowAccessor` / `hasMutateAccessor`。`DefinitionBuilder` 选声明节点时 getter 与 borrow 都算「读访问器」，变量与下标因此不再因为没有 getter 被丢弃；协议要求走同一条路，所以协议也随之修好。属性包装器识别（`wrappedValue` 的访问器形状）与 `declaredTypeNode` 的节点下行同样认这两种节点。
- **打印**（`SwiftPrinting`）：访问器块不再写死 `get`：读访问器有 `borrow` 印 `borrow`，否则印 `get`；写访问器有 `mutate` 印 `mutate`，否则有 setter 印 `set`。SE-0507 规定 `borrow` 与 `get` 互斥、`mutate` 必须配 `borrow`，所以这条规则覆盖全部合法组合；编译器为满足协议而合成的 getter 不会盖掉 `borrow`。`let` / `var` 的判断里 `mutate` 与 setter 等价。
- **ABI diff**（`SwiftDiffing`）：成员记录的访问器 token 加 `borrow` / `mutate`。
- **不做**：`yielding borrow` / `yielding mutate`（SE-0474）。6.4 里仍是实验特性，打开后编译器会给普通属性也合成这两种访问器（像今天的 `_read` / `_modify` 一样不该印出来），印不印要另定规则，留到 6.5 落地时单独处理。类没有这两种访问器（SE-0507 禁止），vtable 相关的分支不动。

### 关联类型上的 `~Copyable` / `~Escapable`

- **推断**（`SwiftInspection`，新增 `SuppressedAssociatedTypeInference`）：给定协议，查符号索引里这个协议 extension 中的全部成员符号，取每个符号 extension 节点上的泛型签名，收集主语是 `Self.<名字>`（深度 0、下标 0 的泛型参数的关联类型）的反向要求，结果按关联类型名给出 `~Copyable` / `~Escapable` 的集合。只认协议自己声明的关联类型；继承来的同名关联类型不归到这个协议上。
- **dump**：`ProtocolDumper` 直接调用推断函数。
- **interface**：`ProtocolDefinition.index(in:)` 把推断结果存进模型（`suppressedInvertibleProtocolsByAssociatedTypeName`），`renderProtocolAssociatedTypes` 从模型读。两条路都印 `associatedtype Element: ~Swift.Copyable`（与我们其余输出一样带模块前缀）。
- **覆盖不全是预期的**：没有这种 extension 的协议、以及所有非主关联类型，照旧印 `associatedtype Element`。推断只有正证据，不会把 Copyable 的关联类型错印成 `~Copyable`。ABI diff / evolution 的成员记录不带这个事实——证据有无随版本里写没写 extension 变化，带上会产生假的 API 变化。

### 测试

两种形态都只有 Swift 6.4 编译器能编出来，而 CI 用 Xcode 26.6（Swift 6.3：`borrow` 访问器报「experimental feature cannot be enabled in production compiler」），`SymbolTestsCore` 也不能动（会挪动 ABI baseline 钉住的偏移）。所以测试现场编译 fixture，用 Swift 6.4 及以上的工具链：先看默认工具链，再看 `/Applications` 下其它 Xcode；找不到就整套跳过（`.enabled(if:)`），CI 上因此不跑。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-10 | Created | 抓 Swift 论坛近期帖子评估影响后，用户：「修一下」 |
| 2026-10-10 | 关联类型一项改为按 extension 证据推断 | 查编译器源码与实验后发现二进制不记录关联类型上的反向要求，先前「我们漏读」的判断有误；问过一轮，用户选「按 extension 证据推断」 |
| 2026-10-10 | 推断只对主关联类型有效，写进注释与测试 | 实测普通关联类型上的 `where Strategy: ~Copyable` 不进 mangling；fixture 留一个非主关联类型 `Strategy` 当反例 |
| 2026-10-10 | `yielding borrow` / `yielding mutate` 不在本次范围 | 6.4 里仍是实验特性，且需要「合成的不印」的规则，等 SE-0474 落地再做 |
| 2026-10-10 | `AccessorKind` 加 case 是源码不兼容变更 | RuntimeViewer 的 `RuntimeSwiftSection.swift` 对它做了穷举 `switch`，合入 `next` 前要同批给它补两个 case |
| 2026-10-10 | 测试的工具链探测去掉继承的 `SDKROOT` / `DYLD_*` | `swift test` 把自己工具链的 `SDKROOT` 与含 PrivateFrameworks 的 `DYLD_FRAMEWORK_PATH` 交给测试进程，子进程换 Xcode 27 后 `xcrun` 以 72 退出，整套被静默跳过（0.001 秒「通过」） |
| 2026-10-10 | 验证 | JHs-Mac-Studio，Xcode 26.6（Swift 6.3.3）跑测试，fixture 由 Xcode 27.0（Swift 6.4）现场编译，本地兄弟依赖。新加两套 8 个测试函数（20 个用例）全部通过；把修复代码换回 `next` 后 15 处断言失败，只有三个「不该印 `~Copyable`」的对照用例照旧通过。全量 `swift test --skip IntegrationTests`：2371 个测试 / 453 个套件，原始退出码 1，失败的只有 `MultiPayloadEnumDescriptorCacheTests` 两条，切到 `next` 原样跑同样两条、同样位置失败（本机既有问题）；另有早已登记的 known issue。真实系统库 A/B（两侧 debug CLI，`next` @ `cd248de9` 对本分支）：macOS 27.0 归档 cache 里 libswiftCore 的 interface 与 dump 各只差两行，正是 `BorrowingIteratorProtocol.Element` 与 `Iterable.Element` 补上 `: ~Swift.Copyable`，与 Xcode 27 SDK 里的 swiftinterface 一致；libswift_Concurrency、Combine、libswiftObservation、libswiftSynchronization、SwiftData 的 interface 与 dump 逐字节一致。macOS 27 SDK 的 `.tbd` 里没有一个导出的 borrow / mutate 访问器（stdlib 里的全是 `@_alwaysEmitIntoClient`），所以系统库这一项看不到变化。项目规定的三条 reader 路径渲染 A/B 脚本没有跑 |
| 2026-10-16 | 找回改动 | 10-10 的改动一直只暂存、没有提交，工作树在 10-12 到 10-15 之间被删。分支一次都没提交过，`merge-base --is-ancestor` 判它「已合并」，`git log --all` 也看不到它。主体从对象库里一个不可达的临时提交 `c517f4e4` 恢复（当时为了验证「修复前测试会失败」先提交、后 `reset --soft` 撤销）；提交之后改的三处文档（`Modules/MachOSymbols.md` 一段、本表两行、演进账本一节）从当天的对话记录原样重放 |
| 2026-10-16 | rebase 到 0.23.0 之后的 `next` | 四处冲突与两处跟进。`DefinitionBuilder` 的两处选节点，改用局部类型那次引入的 `memberSubtree`，同时保留 `borrow` 判断。`accessorKind` 的搜索表把局部类型那次加的 `.variable` / `.subscript` 与 `borrow` / `mutate` 合在一起。两份文档索引两边的条目都保留。关联类型行调用的 `dumpInvertedProtocolsInheritance`，按模块选择器那次改成带 `resolver:` 的 async 函数：dump 用 `demangleResolver`，interface 用 `typeDemangleResolver` |
| 2026-10-16 | 合入前重新验证 | JHs-Mac-Studio，Xcode 26.6（Swift 6.3.3），本地兄弟依赖，内容与已发布的 swift-demangling 0.7.2、swift-semantic-string 0.5.0、MachOObjCSection 0.8.200、MachOKit 0.54.101、MachOKitExtensions 1.2.0 一致；fixture 按 CI 的方式用 Xcode 26.6 ad-hoc 签名现编。新加的 8 个测试函数（20 个用例）全部通过，fixture 由本机的 Xcode 27 现场编译。全量 `swift test --skip IntegrationTests`：2450 个测试 / 470 个套件，原始退出码 1，失败的只有本机既有的两条 `MultiPayloadEnumDescriptorCacheTests`（`:101`、`:130`），与 0.23.0 发版时相同；测试数比 0.23.0 多的 8 个就是新加的测试。渲染 A/B（基线 `next` @ `b7be58ec`，两侧 release，经构建队列预构建后带 `--skip-build` 跑）：90 对全部逐字节一致，即归档 cache 15.5 与 26.6.2 各 12 对、iOS 15.5 / 18.5 / 18.6 / 26.5 模拟器 42 对、MachOImage 腿 24 对；iOS 27.1 / 27.2 模拟器的框架在 cache 里、不是文件，按设计跳过。macOS 27.0 归档 cache 里的 libswiftCore（两侧 release CLI）：interface 17,488 行、dump 24,521 行，各只差两行，仍是 `BorrowingIteratorProtocol.Element` 与 `Iterable.Element` 补上 `: ~Swift.Copyable` |
| 2026-10-16 | Implemented，编号 0070 | 同批给 RuntimeViewer 的 `kindString` 补上 `.borrowAccessor` / `.mutateAccessor` 两个 case。不另写使用指南或实现说明：行为说明已在 `Modules/SwiftDeclaration.md` 的「访问器种类与关联类型的抑制」与 `Modules/MachOSymbols.md`，读输出的提示在插件 skill 里。术语表不新增：`borrow` / `mutate` 访问器与「抑制的关联类型」是 SE-0507 / SE-0503 的叫法，不是本项目自造的词 |
