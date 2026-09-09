# 0023 - 读取 TypeImportInfo，按运行时规则给 C 导入类型定名字和种类

- **状态**: Implemented
- **创建日期**: 2026-09-09
- **最后更新**: 2026-09-09

## 摘要

C 导入类型的 type context descriptor 在名字字符串后面还跟着一串以空字符分隔的 import info：`N` 前缀是 ABI 名覆盖，`S` 前缀是符号命名空间（值 `t` 表示这是一个被提升为独立类型的 C typedef），`R` 前缀是关联实体名。运行时 `_swift_buildDemanglingForContext`（`stdlib/public/runtime/Demangle.cpp`）据此改写 demangling 树，AST mangler 给这些类型的符号也是同一套拼法。我们只读了 `hasImportInfo` flag，后面的字符串没读，于是描述符推出来的节点与符号 demangle 出来的节点在名字和种类上不一致：`Decimal` 应是 `__C.NSDecimal` 的 typeAlias，`NSRange` 应是 `__C._NSRange`，`CGColor` 应是 `__C.CGColorRef` 的 typeAlias，NS_ENUM 导入的枚举应是 structure，importer 合成的错误类型应带 `relatedEntityDeclName`。这批把 import info 读出来并按运行时的四条规则改写。

## 方案

**规则来源**是运行时版本而不是 `Remote/MetadataReader.h` 的版本：Remote 版只在 import info 存在时才做 tag 枚举改 structure，漏掉了没有 import info 的 NS_ENUM（`_isCImportedTagType` 不依赖 import info），而 AST mangler 对所有 Clang TagDecl 都发 `V`。以下期望值均由编译器 `_mangledTypeName` 实测：

| 类型 | 编译器 mangling | 现在的节点 | 改后的节点 |
|------|----------------|-----------|-----------|
| `Decimal`（typedef 匿名 struct） | `So9NSDecimala` | `structure __C.Decimal` | `typeAlias __C.NSDecimal` |
| `CMTime` | `So6CMTimea` | `structure __C.CMTime` | `typeAlias __C.CMTime` |
| `CGColor`（CF 类） | `So10CGColorRefa` | `class __C.CGColor` | `typeAlias __C.CGColorRef` |
| `NSRange`（tag `_NSRange`） | `So8_NSRangeV` | `structure __C.NSRange` | `structure __C._NSRange` |
| `NSTextAlignment`（NS_ENUM，无 import info） | `So15NSTextAlignmentV` | `enum __C.NSTextAlignment` | `structure __C.NSTextAlignment` |
| `CKError`（NS_ERROR_ENUM 合成） | `SC11CKErrorCodeLeV` | `structure __C_Synthesized.CKError` | `structure __C_Synthesized.related decl 'e' for CKErrorCode` |

**ABI 层**（`MachOSwiftSection`）：新增 `TypeImportInfo`（`abiName` / `symbolNamespace` / `relatedEntityName`，派生 `isCTypedef`、`isRelatedEntity`），`TypeContextDescriptorProtocol.typeImportInfo(in:)` 三种读法，flag 未置位返回 nil。解析规则照 `ParsedTypeIdentity::parse`：从名字末尾往后逐个读 C 字符串，空串结束，首字符定组件，不认识的组件忽略。

**`SymbolicDemangler`**（`buildContextDescriptorMangling`）：对 class / struct / enum 三种类型上下文，名字节点用 ABI 名（无覆盖则用户可见名）；typedef 命名空间改节点种类为 `typeAlias`；否则若描述符是 enum、不是关联实体、根模块是 `__C` 或 `__C_Synthesized`，改为 `structure`；有关联实体名则把名字节点包进 `relatedEntityDeclName(identifier(实体名), 名字)`。四条规则与运行时逐条对应。

**下游跟着改的地方**：
- `SwiftLayout`：`StaticTypeLayoutResolver` 的种类分派新增 `.typeAlias`，先查 builtin 索引，再按解析到的描述符种类分派（foreign class 一个指针，struct 走结构路径，enum 走枚举路径）；`NodeTypeNaming.unwrappedNominal` 接受 `.typeAlias`，否则 `ImageReference` 的类型索引会漏掉这些描述符。
- `TypeIndexing`：`CImportedTypeNameCategory(nodeKind:)` 对 `.typeAlias` 归 `.other`，现有表回退已覆盖（`Typedefs` 与 `Tags` 表、CF `Ref` 剥除规则）。
- 测试：SwiftLayout 里写死 `"__C.Decimal"` 的期望改为 `"__C.NSDecimal"`；dump / interface 快照里的 `__C.Decimal` 同步。
- `SwiftDeclaration`：`TypeName` 与 `ExtensionName` 的相等与哈希只看节点结构，不再比较 `kind`。`kind` 是派生信息，三个生产者各自推导（描述符自己的种类、demangle 树的遍历），对 C 导入类型恰好不一致：tag 枚举描述符说 `enum`、树说 `structure`；typedef 提升的类型树是 `typeAlias`，原来没有对应的 `TypeKind`，关联类型记录整条被丢。键里带 `kind` 会把同一类型的 conformance 描述符、`__swift5_assocty` 记录和 witness 符号拆开，接口里 conformance 块丢 `typealias` 见证、见证变成尾部的裸 extension 块。`Node.typeKind` 对 `typeAlias` 树给 `.struct`，只为让名字能建出来并入键，没有任何声明关键字会由它打印。 这条修正对原生 Swift 类型同样有效：嵌套在 enum 命名空间里的 struct，树遍历先碰到外层的 `enum`，与描述符的 `struct` 不等，其关联类型见证从来没有并进 conformance 块，而是拖在接口末尾当裸 `extension` 块——提案 0007 记录的「已知外观残留」正是这个原因，本批一并消失（fixture interface 快照末尾 175 行裸块归位到各自的 conformance 块）。

**已知的可见变化与留作后续的事**：默认输出（不带 `--resolve-c-module-names`）里 C 导入类型改按编译器与运行时的拼法打印，见上表。开了 `--resolve-c-module-names` 时前几种由 APINotes 改回 Swift 拼法；importer 合成的错误类型（related entity）目前会按运行时拼法打印，把它改写回 `CloudKit.CKError` 一类 Swift 拼法属于 TypeIndexing 的后续工作，不在本批。

**验证**：
- 新增 on-the-fly fixture（Swift 源加 bridging header），一个 struct 的字段覆盖七种形态：NS_ERROR_ENUM 合成的错误类型与其 Code、NS_ENUM、NS_OPTIONS、`swift_name` 改名的 struct、匿名 tag 的 typedef struct、`swift_wrapper` typedef，加上 SDK 的 `Decimal` / `CGColor` / `NSRange`。先断言字段的 mangled name 确实带指向描述符的 symbolic reference，再断言 demangle 后 remangle 回的字符串等于编译器 `_mangledTypeName` 给出的字面量。
- ABI 层 fixture 套件对 SymbolTestsCore 里的 `__C.Decimal` 描述符断言 import info 三个分量。
- 全量 `swift test --skip IntegrationTests`。
- 用系统 dyld cache 里的真实框架跑改前改后的 `dump` 与 `interface`，逐行分类 diff，确认每一处变化都落在上表描述的形态内。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-09 | Created as Draft | 上游能力对照时列为「建议搬的第一项」，用户指定先做 |
| 2026-09-09 | 规则以运行时 `_swift_buildDemanglingForContext` 为准，不照抄 Remote 版 | Remote 版漏掉无 import info 的 NS_ENUM；编译器实测 `NSTextAlignment` 为 `So15NSTextAlignmentV` |
| 2026-09-09 | 接受默认输出里 C 导入类型名字的变化 | 目标就是让描述符推出的节点与编译器、符号一致；Swift 拼法回写是 TypeIndexing 的职责 |
| 2026-09-09 | related entity 的 Swift 拼法回写不在本批 | 需要 importer 的命名规则（`XxxCode` 去 `Code` 后缀），属 TypeIndexing 后续 |
| 2026-09-09 | Accepted | 用户指定「先做第一项和 C import info 那一块」 |
| 2026-09-09 | `TypeName` / `ExtensionName` 的键不再含 `kind`，`Node.typeKind` 接受 `typeAlias` | 真机对比暴露：NS_ENUM 的 conformance 块丢 `typealias` 见证、`swift_wrapper` typedef 的关联类型记录被整条丢弃；根因是三个生产者对 `kind` 的推导不一致，而节点结构已足以标识类型。回归测试 `CImportedTypeConformanceInterfaceTests` 修复前红、修复后绿 |
| 2026-09-09 | Implemented | 全量测试通过；SwiftUI 与 Foundation 真机前后对比逐类核对；术语表登记 `TypeImportInfo`，不需要独立的使用指南（AGENTS.md 与任务报告已覆盖实现细节）；编号 0023 于落地 `next` 的 commit 分配 |
