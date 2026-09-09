# 2026-09-09 `MetadataReader` 改名为 `SymbolicDemangler`

对应提案：[0022-rename-metadata-reader-to-symbolic-demangler](../../Evolutions/0022-rename-metadata-reader-to-symbolic-demangler.md)

## 问题

对照上游 `swift/include/swift/Remote/MetadataReader.h` 与 `swift/include/swift/RemoteInspection/` 做能力盘点时，用户问上游的 `MetadataReader` 是不是「读一个 metadata 换成 Node」，如果是，我们这个类型的名字就有问题：当年照上游名字取的，实际与 metadata 无关。

## 调研

上游 `MetadataReader<Runtime, Builder>` 干三件事：从 `MemoryReader` 读 metadata 记录、context descriptor、mangled name、ObjC 类数据；把远程 mangled name 里的 symbolic reference 解析成 context 树后 demangle 成 Node；把 metadata 指针或 mangled name 变成 `Builder` 的产物（`readTypeFromMetadata`、`readTypeFromMangledName`）。名字里的 metadata 指整个运行时反射面。

我们的 `MetadataReader` 是 `@_spi(Internals) public enum` 命名空间，全部静态函数：按 mangled name、symbol、context descriptor、generic requirement 四种输入产出 Node，外加缓存开关，从不碰 `Metadata` 记录。它只对应上游第二件事，也就是运行时里 `ResolveAsSymbolicReference` 加 `_swift_buildDemanglingForContext` 那一半。运行时从 mangled name 得到 Node 靠的是 `Demangler`（`MetadataLookup.cpp:472`），`TypeDecoder` 只消费 Node；metadata 变 Node 的反方向是 `_swift_buildDemanglingForMetadata`（`Demangle.cpp:235`），我们没有这一段，`SpecializedMetadataNodeSubstitution` 借 stdlib 的 `_mangledTypeName` 绕了一圈。

引用面：源码 48 个文件、测试 28 个文件、AGENTS.md 4 处、`Documentations/` 39 个文件；RuntimeViewer 的 `RuntimeSwiftInterfaceIndexer.swift` 有一处外部调用。

## 方案

新名 `SymbolicDemangler`：区别于普通 `Demangler` 的正是 symbolic reference 要回到镜像里解析。备选 `DemanglingBuilder` 照搬上游 `buildDemanglingFor…` 的命名，但项目里 Builder 已专指 `TypeBuilder` 一族，弃用。留一个 `@available(*, deprecated, renamed:)` 的 typealias 过渡一个版本。

## 实际执行

- `git mv` 源文件与两个测试文件；`sed` 整体替换 `MetadataReaderCache` 与五个测试 suite 名，再替换裸 `MetadataReader`。第一轮用 `\b` 边界在 BSD sed 里不生效，第二轮改成先替换复合名再替换裸名，结果 225 处裸名、12 处缓存名、5 个 suite 名全部换掉，`Sources/` 与 `Tests/` 里旧名归零。
- `SymbolicDemangler.swift` 顶部补类型注释说明职责与改名缘由，旧名以 deprecated typealias 保留。
- 文档：AGENTS.md 全文替换并重写 SwiftInspection 段的条目；术语表新增 `SymbolicDemangler（旧名 MetadataReader）`；`Documentations/README.md` 索引里以旧名命名的两篇说明保留文件名、摘要加一句现名；`ProjectEvolutionLog.md` 加一节。带日期的记录（task report、review、已落地提案）不改写。
- 同日早先完成、与本批一起落地的提案 0021（符号引用解析去搜索化）及其任务报告在正文里保留旧名 `MetadataReader`：它们记录的是改名前的状态；代码里的 MARK 注释引用提案 slug，不受影响。

## 验证

- 改名后 `swift build --build-tests` 退出码 0。
- 定向套件（`SymbolicDemangler*`、`CImportedTypeIdentity*`、`TypeContextDescriptorProtocolTests`、`MachOSwiftSectionCoverageInvariantTests`）49 条 / 10 个 suite 全部通过，退出码 0。
- 全量 `swift test --skip IntegrationTests` 的结果见 [TypeImportInfo 的任务报告](2026-09-09-type-import-info-identity.md)，两批改动在同一棵工作树上一起跑：最终一次 1676 条 / 313 个 suite，只剩 `SharedCacheTests` 的已知假失败。落地时提案 0021 与 0022 合为一个 commit（0021 早先完成但未提交，改名紧接其后，两者只碰同一个命名空间），该 commit 单独做过 `swift build --build-tests` 编译校验。

## 与提案的偏离

无。

## 环境备忘

构建与测试全部走 `--scratch-path /tmp/claude/SwiftPM/MachOSwiftSection`。fixture 二进制沿用本日早先构建到 `/tmp/claude/DerivedData/SymbolTests` 的那份（worktree 的 `Tests/Projects/SymbolTests/DerivedData` 符号链接已指向它）。
