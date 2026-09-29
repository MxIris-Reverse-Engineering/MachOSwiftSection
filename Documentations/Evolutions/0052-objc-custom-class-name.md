# 0052 - 改过 ObjC 运行时名的 Swift 类：打印 `@objc(Name)`，并按描述符指针配对它的类对象

- **状态**: Implemented
- **创建日期**: 2026-09-27
- **最后更新**: 2026-09-29
- **所属愿景**: 无
- **关联提案**: [0047-objc-ancestor-override-recovery](0047-objc-ancestor-override-recovery.md)、[0048-objc-member-selector-recovery](0048-objc-member-selector-recovery.md)（成员恢复靠的配对正是本提案要补的那一处）
- **实现分支 / PR**: `feature/objc-custom-class-name`
- **配套文档**: [CustomObjCClassNames.md](../Internal/CustomObjCClassNames.md)（实现说明）、[ObjCMemberRecovery.md](../Internal/ObjCMemberRecovery.md)

## 摘要

AppKit 等系统框架里有一批 Swift 类用 `@objc(Name)` 改过 ObjC 运行时名（macOS 27 的 `NSColorModel`，26.6 和 27 都有的 `NSScrollPocket`），它们的类对象在 `class_ro_t` 里记的是这个名字，而不是 `_TtC6AppKit14NSScrollPocket` 这样的 mangling。今天生成的接口完全看不出这件事，RuntimeViewer 那边需要接口打印成 `@objc(NSColorModel) class NSColorModel: __C.NSObject`。

调研时发现同一个根因还造成了两处可见的缺陷：仓库里「ObjC 类对象 ↔ Swift 类」的配对都是把运行时名 demangle 成 Swift 限定名来做的，改过名的类 demangle 不出来，于是一律配不上。一是成员恢复（提案 0047 / 0048）找不到这些类，成员的 `override` / `@objc` 全丢：macOS 27 的 AppKit 上，`_TtC…` 命名的 `NSView` 子类打印 `@objc override func layout()`，`NSScrollPocket` 同样的方法只剩 `func layout()`；仓库自己的 interface 快照里，`@objc(SymbolTestsCoreObjCBridgeClass) class ObjCBridge` 的 `init()` 也少了 `override`，而没改名的 `ObjCAttributeClass` 有。二是静态布局引擎拿不到这些类自己的 `class_ro_t.instanceStart`，ObjC 运行时滑动 ivar 的那种情况会算错起点。

本提案改用类元数据里自带的描述符指针配对，打印 `@objc(Name)`，并让上面两处也覆盖改过名的类。这是路线图 [P2-14](../../Roadmaps/2026-04-13-swiftinterface-dump-improvements.md)（2026-04-15 以「缺真实用例、需要按地址配对」搁置）的复活：用例现在有了，配对也不需要当年设想的符号表匹配。

## 方案

**配对。** `SwiftInspection` 新增按镜像懒建、随其他 per-image 缓存一起淘汰的 `SwiftClassObjectIndex`：

- `__objc_classlist` 里 Swift 位置位的类对象，本身就是这个类的 Swift 元数据（address point 重合）。在类对象 +0x28 读 `flags`，在 +0x40 读 `Description` 指针得到描述符 offset。这个指针在文件里是 rebase / chained fixup，在 arm64e 上还带签名，所以要先按字段位置解 rebase（`Pointer.resolve(from:in:)`）再求 offset；不能走现成的 `descriptor(in:)`，它在 cache 镜像上拿到的是没解码的原值。带 `IsStaticSpecialization` / `IsCanonicalStaticSpecialization`（0x8 / 0x10）的预特化元数据跳过。这一条覆盖 Fixed / FixedOrUpdate / Update 三种元数据策略，也就是所有进 classlist 的类。
- 父类在另一个 resilience domain 的非泛型类（Resilient 策略）不进 classlist：它的描述符经 `SingletonMetadataInitialization` 指向 `ResilientClassMetadataPattern`，那里有同一个 `flags` 字和 `class_ro_t` 的相对指针。AppKit 里就有这种类（`SwiftUIPlatformViewDefinition: SwiftUI.PlatformViewDefinition`），所以一并覆盖。泛型类和泛型祖先的类（Singleton 策略）编译器不允许写 `@objc(Name)`，不覆盖。
- 产物是两张表：描述符 offset → 名字、写法与类对象自己的 `instanceStart`；改过名的类另有一张 Swift 限定名 → 运行时名，给按名字查找的 ObjC 侧索引合并用。

**名字与写法。** 只有 `HasCustomObjCName`（0x4）置位才算改过名；名字与 Swift 类名相同（`@objc(NSScrollPocket) class NSScrollPocket`）也照样打印，因为不写它运行时名就是 mangling。`@objc(Name)` 和 `@_objcRuntimeName(Name)` 在二进制里都只剩这一位加名字，按 `UsesSwiftRefcounting`（0x2）区分：清零表示 ObjC 对象模型（有 ObjC 祖先），印 `@objc(Name)`；置位表示原生 Swift 对象模型，`@objc` 在它上面不合法，只可能是 `@_objcRuntimeName(Name)`（标准库的 `__EmptyArrayStorage` 一类）。唯一例外是 `@objc actor`：引用计数是原生的，但隐式继承 `NSObject`，描述符里有父类，印 `@objc(Name)`。公开类型 `CustomObjCClassName`（名字 + 写法）放在 `SwiftInspection`。

**模型与打印。** `TypeDefinition.customObjCClassName` 在 `index(in:)` 里填好。`SwiftAttribute` 在末尾新增 `.objcRuntimeName`（放末尾是为了不改动已有 case 的 raw value），`TypeAttributeInferrer.inferObjCType` 这个空函数按写法产出 `.objcType` / `.objcRuntimeName`。打印器的两条路径（完整打印，以及 diff / evolution 用的类型头部）在属性关键字后面补 `(Name)`，与成员级 `@objc(selector)` 同一写法。`dump` 在 `class` 声明行上方打同样一行。diff / evolution 的接口视图会分别渲染两侧头部，ObjC 名变了自然显示成改动。

**补上另外两处配对。** `ObjCClassMethodIndex.runtimeNames(forSwiftClassQualifiedName:in:)` 查询时把 `SwiftClassObjectIndex` 限定名表的结果并进来，`ObjCMembers` 于是找得到改过名的类：成员的 `@objc` / `override` / 显式 selector 恢复，`dump` 的 ObjC 祖先链注释也出现；类本体、类的 extension、dump 的两处共四个调用点都不用改。布局引擎的 `classFieldStartOffset` 同样在按限定名查不到时，按描述符取改名类自己的 `instanceStart`。`_TtC…` 命名的类仍走原来的 demangle 路径、一行不动，新代码出错也只影响改过名的类。

**测试。** SymbolTestsCore 已有两个 `@objc(…)` 类（`ObjCClassWrapperFixtures.ObjCBridge` / `ObjCBridgeWithProto`），不改共享 fixture，也不动 ABI baseline；它们的 interface / dump 快照会按预期变化（多出属性行，`init()` 补上 `override`，dump 多出祖先链与成员注释）。`@_objcRuntimeName`、嵌套类、resilient 父类、同名 private 类这几种形态用现场编译的三镜像 fixture 覆盖，MachOFile 与 MachOImage 两个读者都测。系统框架上用 rendering A/B 验收：期望的差异只有新增的属性行和改名类恢复出的成员事实。

**不做。** ABI diff 的变更列表不记录 ObjC 名的变化；不提供公开的配对 API（RuntimeViewer 自己做角标与互跳）；NSObject 子类上写的 `@_objcRuntimeName` 会被印成 `@objc(Name)`，二进制里分不开，记为已知局限。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-27 | 创建为 Draft | RuntimeViewer 会话代用户转来的需求：让生成的接口给改过 ObjC 名的 Swift 类打印 `@objc(ClassName)`，配对由 RuntimeViewer 自己做 |
| 2026-09-27 | 范围扩到成员恢复与布局引擎的配对 | 调研确认两者与本需求同一根因（按 demangle 运行时名配对），macOS 27 AppKit 与仓库快照里都能直接看到缺陷；新配对只补改名类，不碰 `_TtC…` 类的既有路径 |
| 2026-09-27 | 覆盖 Resilient 策略的类，不覆盖 Singleton 策略与泛型类 | 前者 AppKit 里实际存在且信息全在相对指针里；后两者编译器不允许 `@objc(Name)` |
| 2026-09-27 | `@objc` / `@_objcRuntimeName` 按 `UsesSwiftRefcounting` 区分，`@objc actor` 例外 | 与编译器 `ClassDecl::getObjectModel()` 的判定一致；一律印 `@objc(Name)` 会在标准库这类原生类上印出不合法的 Swift |
| 2026-09-27 | Accepted，随即 In Progress | 用户：「写完直接开工，不用问我」 |
| 2026-09-27 | 名字键放在查询时补，而不是在 `ObjCClassMethodIndex` 建表时补键 | 那张表在祖先链经过的每个镜像上都会建（SwiftUI 的类沿链走到 AppKit），建表时补键会让这些镜像也去读描述符、demangle 限定名并留进缓存；按 Swift 限定名查询只发生在被索引或 dump 的镜像上 |
| 2026-09-27 | 查询时两边合并，不是查不到才回退 | 第一版是查不到才回退；自查时发现限定名去掉了 private 鉴别符，两个同名 private 类里一个改过名时，只查旧表会把没改名那个的成员表错配给改过名的那个。合并后照旧判为歧义，fixture 加了 `PrivateTwin` 钉住 |
| 2026-09-27 | 布局引擎的回退按描述符查，不按限定名 | `classFieldStartOffset` 手上就有描述符，省一次 demangle |
| 2026-09-27 | 测试 fixture 另起现场编译的三镜像 fixture（`RenamedObjCClassFixture`），不改 SymbolTestsCore | 共享 fixture 改动会让 ABI baseline 整体漂移；resilient 父类、原生对象模型、实现文件里藏 ivar 的 ObjC 父类这几种形态也需要多个镜像 |
| 2026-09-29 | In Progress → Implemented，落地编号 0052 | 代码已于 2026-09-28 以 `28c0e6c9`–`b521c339` 三个提交直接落在 `next` 上，当时状态停在 In Progress、没有取号；0.21.0 发版时按合入顺序补取。配套文档见头部，已随代码更新；术语表「renamed class」已同批登记 |
