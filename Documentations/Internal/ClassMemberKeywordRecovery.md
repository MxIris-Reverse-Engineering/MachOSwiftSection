# class / static 成员关键字的还原（vtable method descriptor 判据）

## 背景：符号层面永远分不出 `class func` 和 `static func`

编译器 mangle 类型级成员时只看 `isStatic()`，而 `class func` 和 `static func` 的
`isStatic()` 都是 true（swiftlang/swift `ASTMangler.cpp:4440`）。两者 demangle
出来一律是 `static ...`，所以 interface 输出此前把所有类型级成员都渲染成
`static`，包括那些源码里写的是 `class` 的。

这不只是"不够准"——**输出里存在非法 Swift 语法**：`static` 成员不可被
override，但 `override static var` / `override static func` 曾出现在 iOS 18.5
SwiftUI（arm64）的 interface 输出里（19 处），以及本项目自己的
`interfaceSnapshot` 基线里（`StaticMemberSubclassTest` 的 2 处）。

## 判据：有 vtable method descriptor 的类型级成员必然是 `class`

原因在编译器的两条规则：

- class 里的 `static func` 被隐式推成 `final`（`TypeCheckDecl.cpp:296` —
  `KeywordStatic` ⇒ final），而 final 成员不进 vtable（`TypeCheckDecl.cpp:1049`
  — `decl->isFinal()` 直接返回 false，不生成 method descriptor）。
- `class func` 非 final，进 vtable，其 method descriptor 的
  `isInstance = !isStatic()` = false（`GenMeta.cpp:299`）。

探针 dylib 实测（`nm` 观察 method descriptor 符号）：只有 `class func` /
`class var` 有 method descriptor；`static func`、`final class func`、final
class 里的 `class func`、extension 里的 `class func` 全都没有。

判据是**正向的**：不需要先推断类是不是 final（ABI 里也确实没有 final 位——
`ClassFlags`、`TypeContextDescriptorFlags` 的 class 段、ObjC `class_ro_t`
三处都查过），只看「这个成员有没有 method descriptor」。

**用 `methodDescriptor` 而不是 `vtableOffset`**：SwiftUI 里有 6 个 override
成员的 `vtableOffset` 解析失败（父类 vtable 查不到槽位）但 `methodDescriptor`
在——descriptor 存在性才是 ABI 事实，槽位号只是附加解析结果。

## 实现

数据早就挂在模型上（`FunctionDefinition.methodDescriptor` /
`Accessor.methodDescriptor`，索引期由 `TypeDefinition` 从 class 的
vtable/override table 构建 lookup 填入），本次只是把它接到关键字选择上：

1. **模型判据**（`SwiftDeclaration`）：
   - `FunctionDefinition.isClassMember = kind == .function && isGlobalOrStatic && methodDescriptor != nil`
     （`kind` 门排除 allocator/constructor——init 也有 descriptor 但不是
     类型级成员）；
   - `AccessorRepresentable.hasVTableAccessor = 任一 accessor 的 methodDescriptor != nil`；
   - `VariableDefinition.isClassMember = isGlobalOrStatic && hasVTableAccessor`、
     `SubscriptDefinition.isClassMember = isStatic && hasVTableAccessor`
     （instance 成员的 accessor 也有 descriptor，所以必须与类型级标志合取）。
2. **三个 node printer**（`SwiftPrinting`）：`FunctionNodePrinter` /
   `VariableNodePrinter` / `SubscriptNodePrinter` 各加一个 `isClassMember`
   构造参数（默认 false，保守输出 `static`），`.static` 节点分支按它写
   `"class"` 或 `"static"`。
3. **构造点**（`SwiftDeclarationPrinter.printThrowingVariable/Function/Subscript`）：
   把 `definition.isClassMember` 传进 printer。interface、diff 注释渲染
   （`SwiftDiffableInterfaceRenderer`）、global 路径全部汇聚到这三个入口，
   一处接线全覆盖。
4. **dump 的 vtable 段落**（`ClassDumper.dumpMethodKeyword`）：该段落里的
   每个条目都有 method descriptor，类型级条目（`!isInstance && kind != .init`）
   源码必然写的是 `class`，`Keyword(.static)` 直接改 `Keyword(.class)`。

### 不会误判的原因

- extension / protocol / global 三条路径构建 Definition 时不传 vtable
  lookup（默认空字典），`methodDescriptor` 恒为 nil，继续输出 `static`。
  protocol 里 Swift 本来也只允许 `static`（`class` 拼写已废弃），保持 `static`
  是对的。
- `override static` 从此结构性不可能：`isOverride` 本身就派生自
  `methodDescriptor`（`FunctionDefinition.swift` / `Accessor.swift`），一个成员
  被判定为 override 必然有 descriptor，也就必然走 `class` 分支。

### dump 路径里 override table 的 `static` 前缀不动

dump 输出的 override table 行如
`override static Foo.SubClass.classMethod() -> Swift.Int`——这里的 `static`
来自 **demangler 对符号的忠实还原**（`demangleResolver.resolve`，与
`swift-demangle` 输出一致），不是 interface 语法。dump 本就是符号列表而非可编译
Swift 源码，改掉它等于篡改 demangle 结果，明确不动。本次只改
`dumpMethodKeyword` 从 descriptor flags 派生的那个关键字（vtable 段落行首，
原输出形如 `static func static Foo...`，现为 `class func static Foo...`）。

## 识别不了的（保守输出 `static`）

`final class func`、final class 里的 `class func`、extension 里的
`class func`、`@objc dynamic class func`——这四类在 ABI 上与 `static func`
完全一致（都没有 method descriptor），无法区分。渲染成 `static` 不产生错误
代码：在 class 里 `static` 就是 `final class` 的别名（编译器对两种拼写推出同一个
final 状态，此后除诊断与源码打印外不再区分；mangling 也一致）。丢失的只是
源码作者的写法偏好，不是语义——那个区别只存在于 `.swiftinterface` /
`.swiftmodule` 这类源码级产物里，二进制里没有任何信息能再往下分。

| 源码写法 | 输出 | 说明 |
|---|---|---|
| `class func`（可 override） | `class func` | 精确还原 |
| `override class func` | `override class func` | 精确还原（曾输出非法的 `override static`） |
| `static func` | `static func` | 精确还原 |
| `final class func` 等四类 | `static func` | 语义等价，写法丢失 |

## 测试

- `NodePrinterTests`：三个 printer 各加 `isClassMember` true/false 用例，
  外加 `override class func` 组合用例（修复前该组合输出非法的
  `override static func`）。
- 快照基线：`staticMembersSnapshot`（dump，vtable 段落 `static`→`class`）与
  `interfaceSnapshot`（`StaticMemberClassTest` 的 `class var` / `class func` +
  `StaticMemberSubclassTest` 的 `override class`）重录；fixture
  `StaticMembers.swift` 本就覆盖 `class var` / `class func` / `override class`
  与同名 `static` 对照组，未新增。
