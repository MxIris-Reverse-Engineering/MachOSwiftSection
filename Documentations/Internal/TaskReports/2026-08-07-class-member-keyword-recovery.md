# 2026-08-07 · class / static 成员关键字的还原

## 问题

interface 输出把所有类型级成员渲染成 `static`，源码里的 `class func` /
`class var` / `class subscript` 无法还原。且输出中存在**非法 Swift 语法**
`override static func` / `override static var`（`static` 不可 override）：
iOS 18.5 SwiftUI（arm64）19 处，项目 interface 快照基线 2 处
（`StaticMemberSubclassTest`）。

## 调研结论（前一日与 agent 的讨论，实机验证过）

- **符号层面永远分不出**：编译器 mangle 只看 `isStatic()`，`class func` 和
  `static func` 都是 true（`ASTMangler.cpp:4440`），demangle 一律 `static`。
- **vtable 层面能分出**：class 里的 `static` 成员被隐式推成 final
  （`TypeCheckDecl.cpp:296`），final 成员不生成 method descriptor
  （`TypeCheckDecl.cpp:1049`）；`class` 成员非 final、有 descriptor
  （`GenMeta.cpp:299`，`isInstance = !isStatic()`）。探针 dylib `nm` 实测证实：
  只有 `class func` / `class var` 有 descriptor。
- **ABI 里没有 final 位**（`ClassFlags` / `TypeContextDescriptorFlags` class 段 /
  `class_ro_t` 三处查证），且 final class 与「成员全 final 的 class」dump 完全
  同构——但判据是正向的 descriptor 存在性，不需要 final。
- **判据用 `methodDescriptor` 不用 `vtableOffset`**：SwiftUI 有 6 个 override
  成员槽位解析失败但 descriptor 在。
- **无法识别的四类**（`final class func`、final class 里的 `class func`、
  extension 里的 `class func`、`@objc dynamic class func`）ABI 上与 `static`
  完全一致，保守输出语义等价的 `static`（class 里 `static` 就是 `final class`
  的别名）。

## 最终方案

数据早已在模型上（`FunctionDefinition.methodDescriptor` /
`Accessor.methodDescriptor`），只做接线：

1. `SwiftDeclaration`：`FunctionDefinition.isClassMember`（`kind == .function &&
   isGlobalOrStatic && methodDescriptor != nil`）、
   `AccessorRepresentable.hasVTableAccessor`、`VariableDefinition` /
   `SubscriptDefinition` 的 `isClassMember`（类型级标志 && hasVTableAccessor）。
2. `SwiftPrinting` 三个 node printer 加 `isClassMember` 参数（默认 false），
   `.static` 分支按它写 `class` / `static`。
3. `SwiftDeclarationPrinter` 三个构造点传入 `definition.isClassMember`。
4. `ClassDumper.dumpMethodKeyword`：vtable 段落 `Keyword(.static)` →
   `Keyword(.class)`（该段落条目必有 descriptor）。

明确不动：dump override table 行里 demangler 还原的 `static` 符号前缀
（那是忠实 demangle 输出，不是 interface 语法）；extension / protocol /
global 路径（构建时不传 vtable lookup，`methodDescriptor` 恒 nil）。

## 实际执行

- 与方案一致，无偏差。行号相对讨论时有漂移（main 已重写到 0.14.1 基线）：
  printer 构造点在 `SwiftDeclarationPrinter.swift:453/463/473`，
  `ClassDumper` 关键字在 412 行。
- 回归测试：`NodePrinterTests` 新增 7 个用例——三个 printer 各一对
  `isClassMember` true/false（手工构造 mangled symbol，`swift-demangle`
  验证过），外加 `override class func` 组合（修复前该组合输出非法的
  `override static func`）。
- 快照基线重录 2 份：`staticMembersSnapshot`（dump）、`interfaceSnapshot`
  （interface）。fixture `StaticMembers.swift` 原本就覆盖
  `class var` / `class func` / `override class` 与 `static` 对照组，未新增。
- 文档：[ClassMemberKeywordRecovery.md](../ClassMemberKeywordRecovery.md)
  实现说明、演进日志第 27 节、`Documentations/README.md` 索引、AGENTS.md
  SwiftPrinting 段各同步一处。

## 验证

- 环境：`/tmp/claude/Workspace` worktree + 本地 sibling 依赖符号链接 +
  `.package.env`（与主 checkout 同构，排除依赖版本漂移）；fixture 二进制在
  worktree 内新建（`xcodebuild … -derivedDataPath
  Tests/Projects/SymbolTests/DerivedData/SymbolTests`）。
- 结果见下（构建 + 受影响套件 + 全量 `--skip IntegrationTests`）。
