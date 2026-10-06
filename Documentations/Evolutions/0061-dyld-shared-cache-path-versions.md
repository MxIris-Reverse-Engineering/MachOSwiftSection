# 0061 - 测试用的 dyld shared cache 路径按版本取

- **状态**: Implemented
- **创建日期**: 2026-10-05
- **最后更新**: 2026-10-06

## 摘要

测试支撑代码里的 `DyldSharedCachePath`（`Sources/TestSupport/MachOFixtureSupport/DyldSharedCachePath.swift`）原是一个以 `String` 为原始值的 enum，每用一个归档 cache 就得手写一个 case 和它的完整路径。本次把它改成用静态成员充当 case 的结构体，带路径（`rawValue`）和版本标签（`versionLabel`）两个字段，新增按版本号拼出路径、并拿这个版本当标签的 `macOS(_:)` / `iOS(_:)`；evolution 的 IntegrationTests 因此直接用每个 cache 的标签当轴标签，不必再另写一份标签数组。另在 IntegrationTests 的单版本、diff、evolution 三个套件里各加一个只需填版本号的 `ArchivedDyldCacheTests`；evolution 用的多版本基类会跳过 cache 里没有该镜像、或镜像不含 Swift 的版本。

## 方案

- **类型**：`DyldSharedCachePath: Hashable, Sendable`，`rawValue` 是路径，`versionLabel` 是它在版本轴上的标签，两者都在构造时给出。`macOS("26.6")` 得到 `/Volumes/DyldSharedCaches/macOS/26.6/dyld_shared_cache_arm64e`、标签 `26.6`，`iOS("27.0")` 同理。版本就是卷上的目录名，原样拼进路径、原样当标签（`14.0(Internal)` 也行）；不检查文件在不在，和以前一样由调用方判断——卷上有的目录只放导出的头文件，没有 cache（例如 26.4.1、26.5.1）。不再遵循 `RawRepresentable`：它要求只凭路径就能构造出值，而每个值都必须带标签。
- **原有常量**：8 个 case 变成同名的 `static let`，调用点一处不改。四个 macOS 常量改由 `macOS(_:)` 生成；其余四个直接写明标签：`current` 标为 `current`（标签不一定是系统版本），`iOS_18_5`、`iOS_26_1`、`iOS_27_0_Simulator` 分别标为 `18.5`、`26.1`、`27.0`。`MachOTestingSupportTests` 的 `DyldSharedCachePathTests` 钉住四个 macOS 常量的路径与原来写死的完全相同、标签与 evolution 测试原来手写的相同——这些常量只在不会自动运行的 IntegrationTests 里用，拼错了平时没人发现。
- **版本标签**：evolution 的 `MultiVersionDyldCacheImageTests` 只列 `cachePaths`，轴标签取每个 cache 的 `versionLabel`，原来与路径一一对应的 `cacheLabels` 数组删掉；默认三个 cache 给出的标签仍是 `15.5`、`26.5.2`、`27.0`，现有 evolution 输出不变。标签手动给，不从 cache 文件里解析：cache 头的 `osVersion` 只记主、次版本号，补丁号总是 0（26.5.2 的头里是 26.5.0，15.8.1 是 15.8.0），macOS 11 的 cache 干脆是 0.0.0，解析出来会让两个补丁版本撞成同一个标签。
- **只给 macOS 与 iOS 出版本函数**：卷上的 `iOS-Simulator/` 目录里只有导出的头文件，没有 cache；模拟器 runtime 的 cache 在 CoreSimulator 卷里，卷名带 build 号（`iOS_24A434`），从版本号推不出路径，所以 `iOS_27_0_Simulator` 仍然写死。
- **IntegrationTests**：`SwiftInterfaceBuilderTestSuite`、`SwiftDiffableInterfaceBuilderTestSuite`、`SwiftEvolutionInterfaceBuilderTestSuite` 各加一个 `ArchivedDyldCacheTests`，分别只填 `cacheVersion`、`oldCacheVersion` / `newCacheVersion`、`cacheVersions`，镜像默认 AppKit，各自沿用所在套件现有的基类。evolution 那个的 `cachePaths` 由 `cacheVersions` 生成，标签就是这些版本号，全是数字，于是打开 `@available(macOS, …)` 输出（提案 [0060](0060-evolution-interface-available-annotations.md)）；为此 `SwiftEvolutionInterfaceDumpTests` 的两个辅助函数加了一个默认 `nil` 的 `availabilityAnnotationPlatform` 参数，现有调用不受影响。evolution 那个起初只列 15.8.1、26.6、27.0，后续改为卷上 macOS 11.0.1 → 27.0 每个次版本一个（共 51 个；11.0、12.0 在卷上只有 `11.0.1`、`12.0.1`），镜像换成 SwiftUI。这些目录在卷上都有 cache。
- **跳过没有 Swift 的版本**：`MultiVersionDyldCacheImageTests` 打开每个 cache 后，cache 里没有这个镜像、或镜像没有任何 `__swift5_*` 节的，这个版本就不上轴，也不报错；打不开的 cache 照旧抛错。起因是 AppKit 在 macOS 14 之前把 Swift API 放在 `/usr/lib/swift/libswiftAppKit.dylib`，AppKit 本体在 11.0.1–13.7 一个 Swift 节都没有。索引这样的镜像时，索引器对类型、协议、conformance、associated type 各报一次提取失败；测试没挂事件处理器，这四条失败都会以 error 级别写进日志。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-05 | Created | 用户：「DyldSharedCachePath改成String Type Enum结构体，支持传递版本返回路径」 |
| 2026-10-05 | 三个套件各加一个按版本号取 cache 的类 | 用户：「再加一个SwiftInterfaceBuilderTests加上Diff和Evolution版本」。三个套件本来就有，问过一轮，用户选「每个套件加一个按版本号的类」 |
| 2026-10-05 | 顺带发现的两处先不改 | `macOS_26_5_1` 指向的目录是空的，diff 套件里两处拿它当旧版本，一跑就失败；`iOS_18_5` / `iOS_26_1` 指向没挂载的 `/Volumes/Generic`，全仓没有调用。用户选「都先不动」 |
| 2026-10-05 | 验证 | 全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra，Swift 6.4，远端依赖）2270 个测试 / 423 个套件全部通过，原始退出码 0，比改动前多出的正是新加的 1 个套件、2 个测试；只有早已登记的 `SymbolicManglingIndexTests` known issue。IntegrationTests 按项目规矩只编译、不运行：三个新类与改过的辅助函数编译通过，没有新警告。默认的 15.8.1、26.6、27.0 在卷上都有 cache 文件 |
| 2026-10-05 | Implemented，编号 0061 | 按共享分支编号（`next` 最大为 0060），合入 `next`；演进账本第 80 节。不另写专题文档，无新术语 |
| 2026-10-05 | 后续：加 `versionLabel`，evolution 测试不再另写标签 | 用户：「DyldSharedCachePath这里再嵌入或者解析dyld cache的系统版本，evolution那边就不用再写一次label了」。查到 cache 头的 `osVersion` 不带补丁号、macOS 11 没有这个值，解析会丢信息；用户随后定为「手动传吧，静态常量直接写上，调方法的就拿那个作为版本label，这个不是一定得是系统版本，应该叫versionLabel」。`RawRepresentable` 因此去掉，`cacheLabels` 删掉 |
| 2026-10-05 | 后续的验证 | 按用户「不用全部跑一遍，编译过了就行」，只编译：全部测试目标（含 IntegrationTests）编译通过，改动的文件没有新警告；没有运行测试，`DyldSharedCachePathTests` 新加的标签断言也没有跑过 |
| 2026-10-06 | 后续：evolution 的归档套件改列 51 个版本 | 用户：「SwiftEvolutionInterfaceBuilderTestSuite.ArchivedDyldCacheTests.cacheVersions，把这个属性填完……只写x.y版本，忽略x.y.z版本」。每个次版本取 x.y 目录；11.0、12.0 在卷上只有 x.0.1 目录，照用户写下的第一项 `11.0.1`，12.0 取 `12.0.1`；`14.0(Internal)` 不收。`cachePaths` 改由 `cacheVersions` 生成、镜像换成 SwiftUI，这两处是用户自己改的 |
| 2026-10-06 | 后续：没有 Swift 的版本跳过，不报错 | 用户：「没有swift信息不报错，跳过」。用 `ipsw dyld macho … --loads` 核对过：AppKit 本体在 11.0.1、12.0.1、13.7 没有 `__swift5_*` 节，14.0 起才有；同期 `libswiftAppKit.dylib` 里有 7 个（11.0.1）到 43 个（13.7）类型，14.0 起为 0。判断放在基类，看节名前缀；cache 里没有这个镜像也算没有 Swift，一并跳过 |
| 2026-10-06 | 后续的验证 | 全部测试目标（含 IntegrationTests）编译通过，没有新警告。按用户「测试一下SwiftUI会不会爆内存」运行过一次 `evolutionInterfaceFile`，第 140 秒在 13.5 上因 MachOKit 的整数下溢崩溃，内存没到 5 GB 的上限；其余测试没有运行。实测数字见演进账本第 80 节，崩溃的根因与修复见第 81 节 |
