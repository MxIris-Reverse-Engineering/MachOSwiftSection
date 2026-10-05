# 0061 - 测试用的 dyld shared cache 路径按版本取

- **状态**: Implemented
- **创建日期**: 2026-10-05
- **最后更新**: 2026-10-05

## 摘要

测试支撑代码里的 `DyldSharedCachePath`（`Sources/TestSupport/MachOFixtureSupport/DyldSharedCachePath.swift`）原是一个以 `String` 为原始值的 enum，每用一个归档 cache 就得手写一个 case 和它的完整路径。本次把它改成以 `String` 为原始值的结构体（与 `SymbolicManglingReference.Kind` 同一种写法），新增按版本号拼出路径的 `macOS(_:)` / `iOS(_:)`；并在 IntegrationTests 的单版本、diff、evolution 三个套件里各加一个只需填版本号的 `ArchivedDyldCacheTests`。

## 方案

- **类型**：`DyldSharedCachePath: RawRepresentable, Hashable, Sendable`，`rawValue` 就是路径。`macOS("26.6")` 得到 `/Volumes/DyldSharedCaches/macOS/26.6/dyld_shared_cache_arm64e`，`iOS("27.0")` 得到 `/Volumes/DyldSharedCaches/iOS/27.0/dyld_shared_cache_arm64e`。版本就是卷上的目录名，原样拼进路径（`14.0(Internal)` 也行）；不检查文件在不在，和以前一样由调用方判断——卷上有的目录只放导出的头文件，没有 cache（例如 26.4.1、26.5.1）。
- **原有常量**：8 个 case 变成同名的 `static let`，调用点一处不改。四个 macOS 常量改由 `macOS(_:)` 生成，`MachOTestingSupportTests` 的 `DyldSharedCachePathTests` 钉住它们与原来写死的路径完全相同——这些常量只在不会自动运行的 IntegrationTests 里用，拼错了平时没人发现。
- **只给 macOS 与 iOS 出版本函数**：卷上的 `iOS-Simulator/` 目录里只有导出的头文件，没有 cache；模拟器 runtime 的 cache 在 CoreSimulator 卷里，卷名带 build 号（`iOS_24A434`），从版本号推不出路径，所以 `iOS_27_0_Simulator` 仍然写死。
- **IntegrationTests**：`SwiftInterfaceBuilderTestSuite`、`SwiftDiffableInterfaceBuilderTestSuite`、`SwiftEvolutionInterfaceBuilderTestSuite` 各加一个 `ArchivedDyldCacheTests`，分别只填 `cacheVersion`、`oldCacheVersion` / `newCacheVersion`、`cacheVersions`，镜像默认 AppKit，各自沿用所在套件现有的基类。evolution 那个直接拿版本号当轴标签，标签全是数字，于是打开 `@available(macOS, …)` 输出（提案 [0060](0060-evolution-interface-available-annotations.md)）；为此 `SwiftEvolutionInterfaceDumpTests` 的两个辅助函数加了一个默认 `nil` 的 `availabilityAnnotationPlatform` 参数，现有调用不受影响。默认版本 15.8.1、26.6、27.0 在卷上都有 cache。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-05 | Created | 用户：「DyldSharedCachePath改成String Type Enum结构体，支持传递版本返回路径」 |
| 2026-10-05 | 三个套件各加一个按版本号取 cache 的类 | 用户：「再加一个SwiftInterfaceBuilderTests加上Diff和Evolution版本」。三个套件本来就有，问过一轮，用户选「每个套件加一个按版本号的类」 |
| 2026-10-05 | 顺带发现的两处先不改 | `macOS_26_5_1` 指向的目录是空的，diff 套件里两处拿它当旧版本，一跑就失败；`iOS_18_5` / `iOS_26_1` 指向没挂载的 `/Volumes/Generic`，全仓没有调用。用户选「都先不动」 |
| 2026-10-05 | 验证 | 全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra，Swift 6.4，远端依赖）2270 个测试 / 423 个套件全部通过，原始退出码 0，比改动前多出的正是新加的 1 个套件、2 个测试；只有早已登记的 `SymbolicManglingIndexTests` known issue。IntegrationTests 按项目规矩只编译、不运行：三个新类与改过的辅助函数编译通过，没有新警告。默认的 15.8.1、26.6、27.0 在卷上都有 cache 文件 |
| 2026-10-05 | Implemented，编号 0061 | 按共享分支编号（`next` 最大为 0060），合入 `next`；演进账本第 80 节。不另写专题文档，无新术语 |
