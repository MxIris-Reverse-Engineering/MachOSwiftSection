# `@objc @implementation` 类的识别

> 提案 [draft-objc-implementation-class-recognition](../Evolutions/draft-objc-implementation-class-recognition.md) 的实现说明。读者：维护者。二进制事实与判据的推导过程在提案里，本文只讲落地后的形状、为什么这样落、以及边界。

## 一句话

SE-0436 的 `@objc @implementation extension` 让 ObjC 头文件里声明的类由 Swift 实现，编译器把它编成纯 ObjC class object，`__swift5_*` 里没有它。本仓库现在从 `__objc_classlist` 与符号表的联合里把这类类找回来：`SwiftInspection.ObjCImplementationClassIndex` 建每镜像索引，interface 把对应的 extension 打成 `@objc @implementation extension X` 并把存储属性还原成 `var`，dump 新增 `objcImplementationClasses` 段把 ObjC 侧与 Swift 侧能读到的全部事实打出来。macOS 26.7 的 AppKit 里命中 38 个类，与「导出表里有 `$sSo<类>CMa`」的普查逐一吻合；六个 A/B 框架里为零。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| SwiftInspection | `ObjCImplementationClassFacts.swift` | 值类型：类名、superclass、class object 偏移、`class_ro_t` 事实、证据档位（`Evidence`）、ivar 列表（含与 `Wvd` 符号 join 出的 Swift 属性名与类型节点）、实例 / 类方法表（selector、type encoding、IMP 偏移、IMP 处的 Swift 符号）、属性表、协议名。 |
| SwiftInspection | `ObjCImplementationClassIndex.swift` | `SharedCache` 子类（package），reader-split 的构建器；对外是 `public enum ObjCImplementationClasses` 门面：`facts(forClassNamed:in:)`、`all(in:)`、`skipped(in:)`、`removeCache(for:)`、`cImportedClassName(of:)`。 |
| SwiftDeclaration | `ExtensionDefinition.objcImplementation` / `attachObjCImplementation(_:)` / `unrepresentedObjCImplementationInstanceVariables` | 模型上的事实；`absorbMembers(of:)` 合并时 OR 保留。`VariableDefinition.objcImplementationStorage` 标出「这个由访问器符号建出来的成员其实是存储属性」。 |
| SwiftDeclaration | `Building/MemberAttributeApplication.swift`、`ExtensionDefinition+ThunkAttributes.swift` | thunk 符号推断 `@objc` / `@nonobjc` / `distributed` 的匹配逻辑抽成共享实现，extension 成员从此也能得到这些 attribute。 |
| SwiftIndexing | `SwiftDeclarationIndexer.indexExtensions()` | 目标为 `__C` class 的 extension 查索引、挂事实；没有任何成员符号的命中类合成一个空 extension 承载事实；派发 `objcImplementationClassRecognized` / `objcImplementationClassSkipped` 事件；索引随符号表一起在 `deinit` 清理。 |
| SwiftPrinting | `SwiftDeclarationPrinter.printExtensionHeader` / `SwiftDeclarationPrinter+ObjCImplementation.swift` | 头部 `@objc @implementation`（inferred 档在同一行内联 `/* inferred from ObjC class data: … */`）；存储属性打成 `var name: Type` 并带真实 field offset；没有成员定义代表的 ivar 单独渲染。 |
| SwiftDump | `ObjCImplementationClass+Dumpable.swift`、`Dumper/ObjCImplementationClassDumper.swift` | dump 段的渲染。 |
| swift-section | `SwiftSection.objcImplementationClasses`、`DumpCommand` | 新段默认开启，`--preferred-binary-order` 按 class object 偏移排序。 |

## 判据在代码里的位置

前置条件在 `ObjCImplementationClassIndex.build(in:)` 的循环开头：`__objc_classlist` 里的 class object，`isSwift == false`。之后按代价排序地判定：

1. 两次字典查找：`$sSo<类>CMa` 是否被本镜像**导出**（`symbols(of: .typeMetadataAccessFunction)` 预先按 `__C` 类名分桶，且 `isExported == true`）、是否有 `…vpWvd` 字段偏移全局变量（`symbols(of: .fieldOffset)` 按 extension 目标类名分桶）。accessor 必须是导出的：imported 类的 formal linkage 是 `PublicNonUnique`，任何需要它 metadata 的镜像（一句 `String(describing: X.self)` 就够）都会发一个 hidden 的 non-unique accessor，dyld cache 的本地符号表里也留着——渲染 A/B 就抓到 SwiftUICore 里 clang 编的 `DateFormattingContext` 因此被误认；只有实现该类的主模块发出的 public unique accessor 会进导出表。
2. 读 ivar 列表，数有几个 encoding 是 `?` 或空串。
3. 上面两步一个都不命中就跳过，**不读方法表**。镜像里绝大多数类是 clang 类，每个都读方法表会让索引的代价变成一次 class-dump。
4. 命中的类才读方法表；IMP 处的 Swift 符号只作**佐证**，不作触发。方案初稿把它列为第三种确定性证据，落地时降级，理由就是第 3 条的代价。

三档的含义见 `ObjCImplementationClassFacts.Evidence` 的注释。

## 两个 join 是怎么做的

- **ivar ↔ `Wvd` 符号**：按**偏移值**。ivar_t 的 `offset` 字段指向的就是 `Wvd` 符号命名的那个全局变量，索引读出该全局变量的值（一个 word）与 `ivar.offset(in:)` 相等即配对。之所以不按名字：即时编译的 fixture 里头文件声明的 `title` 属性其 ivar name 字段是空指针；名字只作兜底。`Wvi`（间接字段偏移）不参与，`@implementation` 类没有 field offset vector，编译器也不会给它发 `Wvi`。
- **存储属性 ↔ 成员定义**：按 Swift 属性名。`attachObjCImplementation(_:)` 把 `VariableDefinition.objcImplementationStorage` 填上，打印器据此改打存储形态；没对上的 ivar 由 `unrepresentedObjCImplementationInstanceVariables` 单独渲染，有 `Wvd` 的打 `var name: Type`，没有的打一行诚实注释。

## 边界与已知限制

- **category 形式的 `@implementation` 分不开**：`@objc(Extras) @implementation` 的方法被链接器合并进主类方法表，mangling 也不带 category 名。
- **selector 不反推 `@objc`**：importer 的 selector 到 Swift 名规则反过来推有歧义；`@implementation` 头部本身表示成员默认 `@objc`，有 `To` 符号时沿用 thunk 归属。
- **不进 ABI 快照**：`objcImplementation` 不在 `ABIDiffer` 的容器 key 里，存储属性也不投影成 `MemberRecord`，`formatVersion` 不变。
- **IMP 偏移语义随 reader 变**：MachOFile 上 ObjC reader 给的是相对 header（cache 镜像为相对主 cache）的偏移，MachOImage 上是地址；索引按 reader 各自换算，dump 用 `addressString(forOffset:)` 打印。
- **在非主模块实现的 `@implementation`**（头文件在别的框架里）只得到 non-unique accessor，不进导出表；那种类靠 `Wvd` 或 inferred 档。
- **`-exported_symbols_list` 为空再 `strip -x` 的 app 二进制**只剩 inferred 档；一个存储属性类型全部 ObjC 可表示的类（没有 `?` / 空 encoding）在这种镜像里识别不到，输出维持今天的形态。

## 副作用：extension 成员的 `@objc`

`MemberAttributeApplication` 让 `indexExtensions()` 对**每个** extension 的成员做 thunk 归属，不只 `@implementation` 的。之前 `@objc` 只出现在类型自身的成员上，`extension NSView { @objc func foo() }` 这类成员一直缺 `@objc`。这是本提案顺带修正的忠实度问题，会让含 `@objc` extension 成员的 interface 输出多出 attribute。

## 验证

- `ObjCImplementationClassRecognitionTests`（SwiftInterfaceTests）：即时编译的 fixture 三个变体各测一档，clang 类与普通 Swift 类作反例，事件派发。
- `AppKitObjCImplementationClassTests`：系统 cache 的 AppKit，NSGlassEffectView 为 definitive 且 ≥ 9 个字段偏移符号，NSScreen / NSGradient / NSScene 命中，NSView / NSWindow 不命中，命中总数 ≥ 30；macOS 26 以下跳过。
- `ObjCImplementationClassDumpTests`（SwiftDumpTests）：dump 段的三段渲染与开关。
- `DumpSectionsOptionTests`（SwiftSectionCommandTests）：`--sections objcImplementationClasses`。
- 渲染 A/B：预期 dump 侧六个框架无差异（`So…CMa` 普查为零），interface 侧差异仅为 extension 成员新增的 `@objc` 等 attribute；见任务报告。
