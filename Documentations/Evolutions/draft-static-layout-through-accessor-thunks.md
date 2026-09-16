# Draft - 静态布局引擎读取 accessor thunk 背后的字段类型

- **状态**: Draft
- **创建日期**: 2026-09-16
- **最后更新**: 2026-09-16
- **所属愿景**: 无
- **关联提案**: [draft-raw-layout-artificial-field-handling](draft-raw-layout-artificial-field-handling.md)（调研非标准库 `@_rawLayout` 使用者时暴露的缺口）
- **实现分支 / PR**: 未开始
- **配套文档**: [Modules/SwiftLayout.md](../Internal/Modules/SwiftLayout.md)、[Modules/SwiftThunkAnalysis.md](../Internal/Modules/SwiftThunkAnalysis.md)

## 摘要

部署目标低于 macOS 27 / iOS 27 时，编译器（`NoncopyableReflectionSafety`）把每个**非拷贝**字段的类型记录成 kind-9 的 accessor function 符号引用而不是直接的 mangled 类型，旧运行时反射这类字段才不会崩。thunk 读取器（`SwiftThunkAnalysis`，Capstone 符号求值）已经能把这种引用解成类型名，interface 与 dump 打出的字段类型是对的；但静态布局引擎拿到的是原始 mangled name，demangle 出 `AccessorFunctionReference` 节点就报 `unsupported type kind`，该字段及其后所有字段的偏移一律「unknown」。Swift 6.4 之后这个缺口会更常撞到：用户自己写的 `@_rawLayout` 类型全是 `~Copyable`，`Mutex` / `Atomic` 字段也是。

## 方案

在 `SwiftDeclarationRendering` 的离线路径（`StaticFieldLayoutBackend` 一侧）把 thunk 解出的类型节点交给 `SwiftLayout` 的 `layout(forTypeNode:in:)`，而不是让引擎自己 demangle 含 accessor 引用的 mangled name：对每条字段记录，先用既有的 `AccessorThunkResolution` 求值（版本条件取最新分支，与类型名渲染一致），得到不含 `accessorFunctionReference` 的节点后再进入聚合布局。引擎内部也应对 `.accessorFunctionReference` 给出明确的 `LayoutUnknownReason`（「类型藏在 accessor thunk 后面」），而不是笼统的 unsupported type kind。thunk 求值失败的字段照旧 unknown，理由照旧诚实。

尚未决定：解出的节点交给引擎的位置（在 `StaticLayoutCalculator.fieldLayout(of:)` 内部接受一个「字段类型改写器」闭包，还是在渲染层预先算好每条字段的类型节点再喂），以及 in-process 读者是否需要同样处理（`MachOImage` 路径直接调用 thunk 取运行时元数据，可能本来就不受影响）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-16 | 创建为 Draft | 用户裁定：非标准库 `@_rawLayout` 那批不并入 thunk 字段的布局修复，另开提案 |
