# 改过 ObjC 运行时名的 Swift 类

> 提案 [draft-objc-custom-class-name](../Evolutions/draft-objc-custom-class-name.md) 的实现说明。读者：维护者。为什么要做、范围怎么定的在提案里，本文讲落地后的形状、几个看代码看不出来的决定，以及边界。

## 一句话

源码写了 `@objc(NSColorModel)` 的类，ObjC 运行时认的是这个名字，不是 `_TtC6AppKit12NSColorModel` 这样的 mangling。二进制里只剩两样东西记着这件事：类元数据 flag 字里的 `HasCustomObjCName`（0x4），和类对象 `class_ro_t` 里的名字本身。`SwiftClassObjectIndex` 顺着类元数据自带的描述符指针，把这两样东西配到 Swift 类的描述符上；interface 与 dump 据此打印 `@objc(Name)`（或 `@_objcRuntimeName(Name)`），成员恢复和静态布局引擎也靠它找到这些类的类对象——在此之前它们按「demangle 运行时名」配对，改过名的类一律配不上。

## 落地形状

| 层 | 文件 | 做什么 |
|---|---|---|
| SwiftInspection | `CustomObjCClassName.swift` | 公开值类型：名字 + 写法（`.objc` / `.objcRuntimeName`）。 |
| SwiftInspection | `SwiftClassObjectIndex.swift` | 按镜像的 `SharedCache`，只记改过名的类：描述符 offset → 名字与写法、类对象自己的 `instanceStart`；另有「Swift 限定名 → 运行时名」，给按名字查找的 ObjC 侧索引合并用。随 `ObjCClassHierarchies.removeCache(for:)` 驱逐。 |
| SwiftInspection | `ObjCClassMethodIndex.runtimeNames(forSwiftClassQualifiedName:in:)` | 查询时把上面那张限定名表的结果并进自己的表的结果。四个调用点（类本体、类的 extension、dump 的祖先链注释与成员注释）都不用改。 |
| SwiftLayout | `StaticTypeLayoutResolver.classFieldStartOffset` | classlist 的 `instanceStart` 表按限定名查不到时，按描述符问改名类的 `instanceStart`。 |
| SwiftDeclaration | `TypeDefinition.customObjCClassName`、`attributeArgument(for:)`；`SwiftAttribute.objcRuntimeName` | `index(in:)` 里填；新 case 放在枚举末尾，已有 case 的 raw value 不变。 |
| SwiftAttributeInference | `TypeAttributeInferrer.inferObjCType` | 原来是个空函数，现在按写法产出 `.objcType` / `.objcRuntimeName`。 |
| SwiftPrinting / SwiftInterface | 完整打印与 diff / evolution 的类型头部 | 属性关键字后补 `(Name)`，与成员级 `@objc(selector)` 同一写法。 |
| SwiftDump | `ClassDumper.body` | `class` 声明行上方打同样一行。 |

## 两条读取路径

**进 classlist 的类（Fixed / FixedOrUpdate / Update 三种元数据策略）**：Swift 类的类对象就是它的 Swift 元数据，address point 重合，所以 flag 字在类对象 +0x28、描述符指针在 +0x40（`ClassMetadataObjCInterop.Layout.offset(of:)`）。先读 flag 字（普通数据，不需要解 fixup），置位才去读描述符指针和名字，所以没改名的类只多花一次 4 字节的读取。

描述符指针是绝对指针：在文件里是 rebase 或 chained fixup，在 cache 里按 slide info 编码，arm64e 上还带签名。**必须按字段位置读**（`Pointer<ClassDescriptor?>.resolve(from: 类对象 offset + 0x40, in:)`，它对 `MachOFile` 先走 `resolveRebase(fileOffset:)`），不能先把整个元数据结构读出来再调 `descriptor(in:)`——后者拿到的是 cache 里没解码的原值。进程内镜像的指针是真指针，`resolveOffset(at:)` 会剥掉签名。读到的描述符再核对一次 kind 是 class。带 `IsStaticSpecialization` / `IsCanonicalStaticSpecialization`（0x8 / 0x10）的是泛型类的预特化元数据，跳过。

**父类在另一个 resilience domain 的非泛型类（Resilient 策略）**：元数据运行时才按 pattern 建，classlist 里没有它。它的描述符尾部有 `SingletonMetadataInitialization`，那条记录里平时放「未完成元数据」的字段，此时指向 `ResilientClassMetadataPattern`，里面有同一个 flag 字和指向 `class_ro_t` 模板的相对指针——全是相对指针，三种读取器都不用碰 fixup。这条路径要遍历镜像的类型描述符、为这类类临时物化一次 `Class`，只在索引构建时做。macOS 27 的 AppKit 里走这条路径的有 5 个类（父类都在 SwiftUI），在系统 cache 上读出的 pattern 都是 `_TtC6AppKit…` 名、flag 字 0x2——没有改过名的，这条路径的实例目前只在 fixture 里。

泛型类与带泛型祖先的非泛型类（Singleton 策略）编译器不允许 `@objc(Name)`，两条路径都不找。

## 为什么不走看起来更简单的路

- **按名字配（ObjC 类名 == Swift 类名）**：RuntimeViewer 那边最早的粗筛就是这样，macOS 27 的 AppKit 估出约 41 个；按 flag 实际是 74 个。名字不一定相同（`@objc(NSFoo) class Foo`），同名也不代表改过名。
- **按符号配**（路线图 P2-14 当年设想的 `$s…N` 元数据符号）：OS 框架 strip 掉了；描述符指针在元数据里，strip 碰不到。
- **把改名类塞进 `ObjCClassMethodIndex` 自己的限定名表**：那张表在每个镜像建索引时急切建好，而祖先链会为每个经过的祖先镜像建它（SwiftUI 的类沿链走到 AppKit）。塞进去就要在这些镜像上也读描述符、demangle 限定名、把结果留进它们的缓存。按 Swift 限定名查询只发生在正在被索引或 dump 的镜像上，祖先链从不这样查，所以放在查询时，只有这些镜像才会建 `SwiftClassObjectIndex`。
- **只在查不到时才回退**：第一版就是这样写的，但限定名会去掉 private 鉴别符，同一模块两个同名 private 类共用一个键，旧逻辑靠「一个键两条运行时名」判为歧义、拒绝归属。两个里有一个改过名时，只查旧表会只看到没改名的那个，把它的成员表错配给改过名的那个。两边的结果合并之后，这种情况照样判为歧义（fixture 的 `PrivateTwin`）。
- **成员恢复改成全按描述符配**：能顺带解决同名私有类的歧义，但 `_TtC…` 类的既有路径会整体换成新读法，一旦新读法在某种 cache 格式上出错，所有类的成员恢复都会退化。现在的改法只往查找结果里加改名类，`_TtC…` 类照旧由 demangle 出的表给出，出错面限制在改过名的类上。

## 写法判据

`@objc(Name)` 与 `@_objcRuntimeName(Name)` 在二进制里都只剩「flag + 名字」，按类的对象模型区分：`UsesSwiftRefcounting`（0x2）清零就是 ObjC 对象模型（有 ObjC 祖先，编译器 `ClassDecl::getObjectModel()` 的判定），印 `@objc(Name)`；置位是原生 Swift 对象模型，`@objc` 在它上面不合法，只可能是 `@_objcRuntimeName(Name)`（标准库的 `__EmptyArrayStorage` 一类）。唯一例外是 `@objc` actor：它保留 Swift 引用计数，却隐式继承 `NSObject`——描述符里记的父类实际是 `SwiftNativeNSObject`，interface 打出来是 `actor RenamedActor: __C.SwiftNativeNSObject`。actor 只可能有这一种父类，所以「是 actor 且有父类」就印 `@objc(Name)`。

已知局限：`NSObject` 子类上写的 `@_objcRuntimeName(Name)` 会被印成 `@objc(Name)`，二进制里分不开。名字与 Swift 类名相同（`@objc(NSScrollPocket) class NSScrollPocket`）照样打印：不写它，运行时名就是 mangling。

## 布局引擎那一处

编译器给「直接继承 ObjC 类」的 Swift 类排字段时，只从根类的 8 字节（isa）起算，其余交给 ObjC 运行时：类对象的 `class_ro_t.instanceStart` 记的就是 8，运行时按父类的真实大小把整块 ivar 一起往后挪，挪动量向上取整到这个类最宽字段的对齐（objc4 `moveIvars`）。引擎读 `instanceStart` 复现这个滑动；查不到时退回「从父类大小开始逐字段对齐」。两种算法只在父类大小不是字段对齐的整数倍时分叉：fixture 里 ObjC 父类的实现文件藏了 3 个 `int32_t`，真实大小 20，子类的 `Int8` / `Int64` 按滑动落在 0x18 / 0x20（运行时实测一致），按逐字段对齐会算成 0x14 / 0x18。改名类以前就是后一种。app 二进制里 `@objc(Name)` 很常见（Interface Builder、归档兼容），这处在它们身上比在系统框架上更容易碰到。

## 边界

- 改过名、父类又在另一个 resilience domain 的类不在 classlist 里，成员恢复照旧够不到它（库的读取器按类对象读方法表），只打印属性。它的 `class_ro_t` 在 metadata pattern 里，留待以后。
- ABI diff 的变更列表不记录 ObjC 名的变化；diff / evolution 的接口视图分别渲染两侧头部，名字变了会显示成头部改动。
- 不提供公开的配对 API：RuntimeViewer 用 `ClassMetadataObjCInterop.resolve(from:in:)` 与 `descriptor(in:)` 自己配（进程内镜像上这两个都可靠）。

## 验证

- 现场编译的 fixture（`RenamedObjCClassFixture`，三个镜像：library evolution 的 Swift kit、隐藏 ivar 的 ObjC 父类、客户端；客户端有 `.full` 与 `strip -x` 后的 `.strippedLocals` 两个变体）覆盖改名到别名、改名到自身、嵌套、原生对象模型、resilient 父类、`@objc` actor、未改名的对照，文件与进程内两条腿。测试在修复前的 `next` 上逐条失败（未改名的对照除外），修复后全部通过。后加的 `PrivateTwin` 用例（两个同名 private 类、一个改过名）在「查不到才回退」的第一版上失败——查到的是没改名那个的表——改成合并后通过。
- `.strippedLocals` 是 OS 框架的形态：修复前 `description`、`copy()` 被 `final` 还原误标成 `final`（`@objc` 证据缺失），修复后是 `@objc override`。
- SymbolTestsCore 快照：`ObjCClassWrapperFixtures` 的两个 `@objc(…)` 类多出属性行，`init()` 补上 `override`，dump 多出祖先链与成员注释。
- 渲染 A/B（`Scripts/run-rendering-ab-verification.py`，基线为 `next` @ `3b6672ed` 的导出快照；六个框架 × 归档 cache 15.5 / 26.6、模拟器运行时 15.5 至 26.5、进程内当前系统）：96 对里 48 对逐字节一致（Combine、SwiftData、ActivityKit，以及没有改名类的场景），另外 48 对的差异逐行归类后只有四种——新增的属性行 136 行、改名类成员补上的 `@objc` / `override` / 显式 selector 60 处、dump 新增的祖先链注释 42 条与成员注释 92 条，意料之外的改动为 0；进程内的文件与镜像两种读取器差异完全一致。显式 selector 那一例是 SwiftUICore 的 `@objc(SwiftUICoreGlue2) class CoreGlue2` 的 `makeSummarySymbolHost(isOn:font:foregroundColor:)`：IMP 处有 `To` 符号，编译器按 Swift 名默认推出的 selector 应带 `With`，实际没有，源码必然写了 `@objc(…)`，与 `_TtC…` 类一直以来的判定相同。
- 系统 AppKit（macOS 26 起）：`NSScrollPocket` 在系统 cache 与进程内都识别为 `@objc(NSScrollPocket)`，成员表的第一个祖先是 `NSView`。macOS 27（26A428）的 AppKit interface 新增 74 行 `@objc(…)`，其余差异全是这些类恢复出的 `@objc` / `override`，没有删除或改坏的行；嵌套在 `NSScrollPocket` 里的 private 类（运行时名仍是 `_TtCC6AppKit14NSScrollPocket…`）不带属性。
