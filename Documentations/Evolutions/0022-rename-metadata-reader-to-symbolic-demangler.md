# 0022 - `MetadataReader` 改名为 `SymbolicDemangler`

- **状态**: Implemented
- **创建日期**: 2026-09-09
- **最后更新**: 2026-09-09

## 摘要

`SwiftInspection` 里的 `MetadataReader` 是一个只有静态函数的命名空间：按 mangled name、symbol、context descriptor、generic requirement 四种输入产出 demangle 后的 `Node`，其中 symbolic reference 回到镜像里解析。它从不碰 `Metadata` 记录。名字抄自上游 `swift/Remote/MetadataReader.h`，但上游那个类型的主业是「从远程进程内存读运行时元数据（metadata 记录、descriptor、mangled name）再交给 Builder」，我们只对应它「demangle 加 build context mangling」那一半，也就是运行时里 `_swift_buildDemanglingForContext` 加 `ResolveAsSymbolicReference` 的组合。改名为 `SymbolicDemangler`：区别于普通 `Demangler` 的正是 symbolic reference 要回到镜像里解析。

## 方案

- `Sources/SwiftInspection/MetadataReader.swift` 改名为 `SymbolicDemangler.swift`，`public enum MetadataReader` 改为 `public enum SymbolicDemangler`，可见性仍是 `@_spi(Internals)`。文件内私有的 `MetadataReaderCache` 一并改为 `SymbolicDemanglerCache`。
- 保留一个过渡别名一个版本：`@_spi(Internals) @available(*, deprecated, renamed: "SymbolicDemangler") public typealias MetadataReader = SymbolicDemangler`。RuntimeViewer 的 `RuntimeSwiftInterfaceIndexer.swift` 有一处调用，不会立刻断。
- 源码 48 个文件、测试 28 个文件的调用点整体替换；测试文件 `MetadataReaderTests.swift`、`MetadataReaderFixedShapeExtractionTests.swift` 与其中的 suite 名同步改名。
- 文档：AGENTS.md 架构段的条目改为现名并写清职责；`Documentations/Glossary.md` 登记 `SymbolicDemangler`，注明旧名；`Documentations/README.md` 索引里以旧名命名的两篇说明（`MetadataReaderRefactoring.md`、`MetadataReaderCacheRetirement.md`）保留文件名，摘要里加一句现名。带日期的记录（task report、review、已落地提案、实现说明里描述当时状态的段落）不改写，术语表负责新旧名对照。
- 不动的地方：函数签名、缓存语义、`@_spi` 分组、`RuntimeMetadataTypeBuilder` 等不含该名字的类型。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-09 | Created as Draft | 用户确认上游 `MetadataReader` 的职责后指出我们的类型与 metadata 无关，要求改名 |
| 2026-09-09 | 新名取 `SymbolicDemangler`，不取 `DemanglingBuilder` | 项目里 Builder 已专指 `TypeBuilder` 一族；「symbolic」直指它与普通 `Demangler` 的差别 |
| 2026-09-09 | 留一个 deprecated typealias 过渡 | 是 public API 改名，RuntimeViewer 有外部调用；走轻量档而非完整档，因为改动是机械替换 |
| 2026-09-09 | Accepted | 用户回复「改成 SymbolicDemangler 可以」 |
| 2026-09-09 | Implemented | 改名、过渡别名、测试与文档同批落地；术语表登记 `SymbolicDemangler（旧名 MetadataReader）`，不需要独立的使用指南或实现说明（任务报告已覆盖）；编号 0022 于落地 `next` 的 commit 分配 |
