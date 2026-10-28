# Swift 声明的 `@objc` 协议与类对 ObjC 协议的遵循

提案 [`swift-declared-objc-protocols`](../Evolutions/draft-swift-declared-objc-protocols.md) 的实现说明。

## 一句话

Swift 源码声明的 `@objc` 协议没有 protocol descriptor，类对任何 ObjC 协议的遵循也没有 conformance record，所以 `dump` 与 `interface` 原本两样都不输出。现在本库从 `__swift5_fieldmd` 认出本镜像声明的这种协议（`SwiftDeclaredObjCProtocolIndex`），从它的 ObjC 协议记录读出要求，每条要求的 Swift 写法取自实现它的类、没有实现者时按 ClangImporter 的规则从 selector 推出并用 `@objc(selector)` 钉住；类的遵循从 `class_ro_t` 与 category 的协议表读出（`ObjCProtocolAdoptionIndex`），打在类头部与 `extension X: P {}` 上。

## 编译器给这种协议留下了什么

- **没有 protocol descriptor**：`GenMeta.cpp` 的 `emitProtocolDecl` 在 `isObjC()` 分支直接返回，`__swift5_protos` 里没有它，本库所有从 protocol descriptor 出发的路径都看不见它。
- **一条 field descriptor**：`emitFieldDescriptor` 在那个分支之前调用，所以本模块声明的每个 `@objc` 协议都有一条 kind 为 `ObjCProtocol` 的 field descriptor，名字是协议的 Swift mangling（`$s13DVTFoundation17DVTTeamCredentialP`）。这是「本镜像声明了它」的唯一可靠证据。
- **一条 ObjC 协议记录**（`protocol_t`，登记在 `__objc_protolist`）：运行时名默认是旧式 mangling `_TtP<模块><名字>_`，嵌套在类型里的是 `_TtPC…`，源码写了 `@objc(Name)` 就是那个名字。记录里有四张方法表、属性表与带类名的扩展类型编码（`@"NSString"32@0:8@"NSString"16^@24`）。
- **要求没有任何 Swift 符号**：探针确认，无论 public 还是 internal、开不开 library evolution，都没有。和协议有关的 Swift 符号只有 protocol extension 成员、field descriptor、typeref，以及引用属性时的 key path getter（local，`strip -x` 后就没了）。

## 认出本镜像的协议（`SwiftDeclaredObjCProtocolIndex`）

- **以 field descriptor 为准，不看 `protocol_t.flags` 的 IsSwift 位**：引用别的模块的 Swift `@objc` 协议时，Swift 也会生成一份带这一位的弱定义副本；ObjC 代码经 `-Swift.h` 引用 Swift 协议时，clang 生成的副本这一位是 0。两种记录的符号名不同（`_PROTOCOL_<名字>` 与 `_OBJC_PROTOCOL_$_<名字>`），链接时不合并，同一镜像里可能有两份同名记录。所以配对只看名字，同名两份时取这一位为 1 的那份。
- **配对**：没改名的按运行时名 `_TtP…_` 解出的限定名配；改过名的按「ObjC 名等于 Swift 名的最后一段」配（`@objc(X) protocol X`，苹果的常见写法）。ObjC 名与 Swift 名不同的配不上：声明照样打出，注明找不到记录。
- **没有反射元数据时**退回：运行时名是 `_TtP…` 且模块是本镜像的 Swift 模块之一的，算本镜像声明的。改过名的认不出来。
- **没认领的记录**：Swift 生成、却没有声明认领的记录（`unclaimedSwiftEmittedRecords`），只剩改过名的那些：别的模块改过名、被本镜像引用的，以及本镜像里改成别的名字的。下文的跨镜像查找只对这些名字做。
- `ABI` 层为此加了 `__swift5_fieldmd` 的整段遍历（`fieldDescriptors`）与 `FieldDescriptor.actualSize`：本库原本只顺着类型描述符的指针读 field descriptor，而协议没有类型描述符指向它。

## 要求怎么写

### 取自实现者

`ObjCProtocolWitnesses`（SwiftThunkAnalysis）对每条要求，在采纳了这个协议（或它在本镜像里的子协议）的类里找实现它的成员：

- 采纳者来自 `ObjCProtocolAdoptionIndex` 的反查，类按 class-list 顺序、再到 category 的目标类，所有要求都找到就停。
- 成员来自类的 ObjC 成员表（[ObjCMemberRecovery.md](ObjCMemberRecovery.md)），只认 `To` 符号与 thunk 代码两档证据，不认只按名字的第三档。**Swift 类的表必须按 Swift 全名取（`table(forSwiftClassQualifiedName:)`）**：按运行时名取的表是给 ObjC 类用的，它要求 thunk 代码引用的成员属于 `__C.<运行时名>`，Swift 类的成员因此在 strip 过的镜像里一个都联结不上——只有 `To` 符号那一档不查归属，没 strip 时看不出来。
- 声明照抄那个成员的符号，去掉 `@objc` thunk 标记，initializing entry point 读成 allocating 的，**上下文换成协议**：模型与 dump 里这条要求读作协议自己的（`SameNameRenamed.ping()`），不是实现者的。
- **是否写 `@objc(selector)`**：成员表对 witness 一律不给显式 selector 的判定，因为 witness 的 selector 继承自协议；而协议声明里这条要求本身就是声明处，没有继承可言，所以按 `ObjCMemberShape.isDefaultSelector` 移植的编译器推导判断——推出来的与实际的不同才写，推不出来时照写。
- 来源的类名是 `TypeName`，经 resolver 打印，模块选择器才能生效。

### 只有 selector

`ObjCProtocolRequirementBuilder`（SwiftInspection）按记录顺序构造声明的 node，形状与 demangle 成员符号得到的一样（`Global > Function`、`Global > Static > Getter > Variable`、`Global > Allocator`、`Global > Getter > Subscript`），打印器照打成员的方式打它：

- **名字**：`ObjCImporterNaming` 移植 importer 的 `omitNeedlessWords`（`lib/Basic/StringExtras.cpp`）与 `ImportName.cpp` 的相关部分：在第一段的最后一个介词处拆出基名与第一个标签、按参数与返回值的类型名删词、初始化器去掉 `With`、`…error:` 与 `…AndReturnError:` 还原成 `throws`、subscript 访问器。再加本库自己的一步：第一个标签以 `with` 开头、后面还有词时去掉 `with`，这是 Swift 插入 `With` 那条规则的逆运算。completion handler 保持 closure，不改写成 `async`。
- **类型**：`ObjCTypeEncodingParser` 读扩展类型编码，照 importer 的桥接写成 Swift 类型（`NSString` → `String`、`NSArray` → `[Any]`、`id` → `Any`、`id<P>` → 协议存在类型、block → closure），可空性未知写 `!`（`Swift.ImplicitlyUnwrappedOptional<T>`，interface 的打印器写成 `T!` 与 `init!`）。MachOObjCSection 的 `extendedMethodTypes(in:)` 只返回表里第一条，本库按下标读整张表。
- 属性的 getter 与 setter 归到属性，`objectAtIndexedSubscript:` 这类归到 subscript，类方法打 `static`，optional 的打 `optional`。
- 所有这种要求都打 `@objc(selector)`，协议体开头一行注释说明 Swift 名是推出来的。命名规则的测试以真实 ClangImporter 对同一批 selector 与类型的输出为准（`ObjCImporterNamingTests`）。

## 类对 ObjC 协议的遵循（`ObjCProtocolAdoptionIndex`）

- **数据从哪来**：编译器把一个声明写的 ObjC 协议遵循记进它那份类数据的协议表（`GenClass.cpp` 的 `visitConformances`）。**同一模块里的 extension 并进类自己的数据**，它写的遵循也记在类的 `class_ro_t` 里，探针里这种镜像根本没有 `__objc_catlist`。只有 extension 别的模块的类（ObjC 类，或别的模块的 Swift 类），并且有 `@objc` 成员时，才生成 category。索引读本镜像每个 Swift 类的 `class_ro_t`（没有 class object 的类经 [ClassesWithoutClassObjects.md](ClassesWithoutClassObjects.md) 的索引）与每个 category 的协议表。
- **隐含的协议**：类遵循一个继承了 ObjC 协议的 Swift 协议时，编译器把那个 ObjC 协议也记进表里（`getObjCProtocols` 的递归）。索引走一遍本镜像的遵循记录：协议是本镜像的 Swift 协议、它的 requirement signature 里 `Self` 的协议要求（递归经本镜像的其它 Swift 协议）出现了 ObjC 协议，这些 ObjC 协议就记作这个类隐含的。类按描述符的限定名对，category 的目标若是 ObjC 类，按遵循记录里的 ObjC 类名（`directObjCClassName`、`indirectObjCClass` 的 `_OBJC_CLASS_$_` 符号）对。先判协议有没有这种祖先、再给类型起名，绝大多数遵循在第一步就跳过了。
- **为什么是新索引**：找实现者要「谁采纳了协议 P」，打印要「类 X 采纳了哪些」，两种查法在一次构建里建好；`ObjCClassMethodIndex` 与 RuntimeViewer 用的 provider 接缝不动，下游不用跟着改。

## ObjC 协议名换成 Swift 名（`ObjCRuntimeNames`）

- `_TtP…_` 按旧式 mangling 解出。
- 本镜像改过名的查上面的索引。
- **别的模块改过名的**：运行时名不带模块。只有本镜像里「没认领的记录」的名字才去找（clang 生成的记录名字的就是 ObjC 协议），到 ObjC 祖先链用的同一个依赖闭包里找。只查带 `__swift5_fieldmd` 的镜像（改过名的协议只能经 field descriptor 认出），系统缓存里 clang 写的框架一个都不读；第一个命中为准，按名字缓存在解析器上。**建索引要 demangle，所以在解析器的锁外建，锁内只做不存在才插入**（项目规则：持锁时不许发生 demangle 跳转）。改成别的名字的协议在它自己的镜像里也配不上，找不到，按 ObjC 名写。
- **导入的协议在 `__C` 里保留 ObjC 名**（`__C.NSObject`），与编译器的 mangling（`So8NSObject_p`）和现有输出一致；`NSObjectProtocol` 这种 Swift 名由打印时的 type database 按 APINotes 给出。自己加 `Protocol` 后缀会让 type database 按 C 名查不到。

## 模型与输出

| | 模型 | interface | dump |
|---|---|---|---|
| 协议 | `ObjCProtocolDefinition`（indexer 的 `objcProtocolDefinitions` / `allObjCProtocolDefinitions`），要求是 `ObjCProtocolRequirementDefinition`，在 `index(in:)` 里读；protocol extension 挂成它的 `defaultImplementationExtensions` | `@objc protocol X: P`（改过名加 `@objc(Name)`），排在 Swift 协议之后；嵌套在类型里的打进 `extension 父类型 { … }`；默认实现跟在后面 | `protocols` 段，两种排序都有：每条要求一行 Swift 声明，行尾注释写 selector、required / optional、类型编码、实现者与联结依据；段末一行列出没认领的记录，找到 Swift 名的写在箭头后面 |
| 类的协议 | `TypeDefinition.objcProtocolNames`，在类的 `index(in:)` 里读 | 类头部、父类之后 | 类头部下一行 `// ObjC protocols: …`，隐含的标注 `(implied by a Swift conformance)` |
| category 的协议 | indexer 的 `objcCategoryConformances`（`ObjCCategoryConformance`），`prepare()` 时收集 | 每个 category 一个 `extension X: P {}`，排在所有 extension 之后 | `protocolConformances` 段，`extension X: P {} // ObjC category at 0x…` |

- **导出状态**：这种协议自己没有符号，新增无结论 case `ExportStatus.declarationHasNoSymbol`，`--exported-only` 下照样保留。下游四个仓库（RuntimeViewer、MachOKitUI、swift-decompiler、MachOViewer）都没有穷举 `ExportStatus` 的 `switch`。
- **diff 与 evolution 不收录**：类头部的协议只由单版本 interface 的 `printTypeDefinition` 传给头部渲染器（`objcProtocolNames:` 参数），diff 渲染器的 `printTypeHeader` 不传；category 的遵循不进 `conformanceExtensionDefinitions`，只由 `SwiftInterfaceBuilder` 打印。ABI 快照不记这两样，两边一致，快照与二进制对比时不会出现假差异。
- **SwiftLayout**：`ObjCProtocolIndex` 认存在类型里的 Swift 声明 `@objc` 协议，原本只读 `_TtP<模块><名字>_` 两段式的记录名，改过名的与嵌套在类型里的都认不出，那个存在类型的布局就算不出来。现在并上 `SwiftDeclaredObjCProtocolIndex` 给出的本镜像协议；原读法保留，别的模块协议在本镜像的副本、没有反射元数据的镜像仍靠它。

## 已知限制

- ObjC 名与 Swift 名不同的改名协议（`@objc(PRBDifferentlyNamed) protocol DifferentlyNamed`）配不上记录，要求列不出来，类头部里它按 ObjC 名写（`__C.PRBDifferentlyNamed`）。
- 只有 selector 的要求，Swift 名是 importer 规则推出来的，可能与源码不同（探针里照苹果写法显式写 selector 的 10 条对上 5 条）；ObjC 层面的含义由 `@objc(selector)` 保住。
- 隐含的协议只认本镜像的 Swift 协议：遵循的是别的镜像的 Swift 协议时，它继承的 ObjC 协议照样打出来。
- 同一模块里 extension 写的遵循与类声明写的分不出来，都在类头部；链接器做 category merging 时 category 里的也一样。
- 别的模块的 Swift 类在本镜像里的 category，目标类名取运行时名；改过名的别的模块的 Swift 类按 ObjC 名写成 `__C.<名字>`。
- 实现者只在本镜像里找，不到别的镜像里找。

## 验证

- `SwiftDeclaredObjCProtocolsFixture`（MachOTestingSupport）测试时现编两个镜像。kit 声明三个 `@objc` 协议（没改名、改成自身名字、改成别的名字）；客户端声明六种形状的协议（编译器推导 selector、改成自身名字、改成别的名字、继承另一个、internal、嵌套在类型里）、在类声明与同模块 extension 里采纳它们的类、采纳 kit 协议的类、遵循继承 `NSCopying` 的 Swift 协议的类、extension `DateFormatter` 采纳协议（category），以及装着改名协议与嵌套协议存在类型的结构体；`.full`、关掉反射元数据、`strip -x` 三个变体。
- `SwiftDeclaredObjCProtocolIndexTests`、`ObjCImporterNamingTests`、`ObjCProtocolRequirementBuilderTests`（SwiftInspectionTests）：配对、退回路径、没认领的记录；命名规则对照真实 ClangImporter 的输出（含 DVTFoundation 的 selector）；要求的种类、访问器、类成员与 optional。
- `ObjCProtocolDefinitionIndexingTests`（SwiftIndexingTests）：文件、进程内、strip 后的文件三条路径的模型——要求的来源（selector 或实现者）、strip 后经 thunk 代码联结、继承的协议、默认实现、类与 category 的协议、跨镜像找回的改名协议、隐含协议的剔除。
- `SwiftDeclaredObjCProtocolInterfaceTests`（SwiftInterfaceTests）、`SwiftDeclaredObjCProtocolDumpTests`（SwiftDumpTests）、`SwiftDeclaredObjCProtocolRequestTests`（SwiftSectionKitTests）：两种输出、两种 dump 排序、进程内与文件的 interface 一致。
- `SwiftDeclaredObjCProtocolExistentialLayoutTests`（SwiftLayoutTests）：存在类型的静态布局对照运行时的字段偏移，进程内与文件两条路径。
- SymbolTestsCore 的快照：interface 多了三个 `@objc` 协议的声明（`ObjCProto` 嵌在 enum 里，打进 `extension`），`ObjCBridgeWithProto` 的头部带上 `ObjCProto`；dump 里这个类多一行 `// ObjC protocols:`。
- 全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra，Xcode 26.6，远端依赖）：510 个套件、2648 个测试全部通过。已有测试里只动了两处：SymbolTestsCore 的两份快照（重录，见上一条），以及 `ExportStatusTests` 里对 `ExportStatus` 的穷举 `switch` 补上新 case。
- 渲染 A/B（2026-10-28，JHs-Mac-Studio-Ultra，基线是 `next` 5f09ca46 的 `git archive`，两侧同一份 `Package.resolved`、Xcode 26.6）：96 对里 32 对一致（Combine 与 SwiftData 的各条腿），64 对不同（SwiftUI、SwiftUICore、WidgetKit、ActivityKit 的各条腿）。逐行归类，没有一行说不清：
  - 删掉的行只有两种：769 处类头部，每处都换成只多了 ObjC 协议的新头部（`class FetchController<A, B, C>: __C.NSObject, __C.NSFetchedResultsControllerDelegate where …`，泛型的 `NSHostingView<A>` 也带上了 `SwiftUI.XcodeViewDebugDataProvider`）；35 行挪了位置，全是 Swift 声明的 `@objc` 协议的 protocol extension（`extension WidgetKit.WidgetExtensionSession`、iOS 15.5 模拟器的 `extension SwiftUI.PlatformAccessibilityElement`），连同成员与地址注释挪到了协议声明后面。没有任何已有的声明或成员被删掉或改动。
  - 新增的 1979 行都属于预期的几类：协议声明及其要求、三种说明注释、dump 的 `// ObjC protocols:` 行与协议段的事实注释、category 的 `extension`（SwiftUICore 的 `extension __C.NSObject: SwiftUI.PlatformAccessibilityElementProtocol {}`，它的要求因此取自 `__C.NSObject`）。
  - SwiftUI 本身不声明 `XcodeViewDebugDataProvider` 与 `PlatformAccessibilityElementProtocol`：两者是 SwiftUICore 声明的（ABI 模块名同为 `SwiftUI`），SwiftUI 里只有引用它们时生成的副本，声明出现在 SwiftUICore 的输出里。
  - 两侧渲染耗时持平：72 次 CLI 渲染总计 1196 秒对 1236 秒（8 路并发下的总和），cache-26.6 的 SwiftUI interface 都是 20 秒。
- DVTFoundation（Xcode 26.6）手工核对：11 个协议都打出来，两个改过名的带 `@objc(Name)`；`DVTIconReference` 的头部是 `__C.NSObject, DVTFoundation.DVTResourceReference, __C.NSCopying`；只是被引用的 `NFAImageDownloadObserver`（DVTNFASupport）不打成声明。`BackendCredentialsProvider` 重复列出父协议的两个属性，它自己的记录里就有，源码重新声明过。

## 延伸阅读

- 提案 [`swift-declared-objc-protocols`](../Evolutions/draft-swift-declared-objc-protocols.md)，决策日志记着每处偏离方案的地方。
- [ObjCMemberRecovery.md](ObjCMemberRecovery.md)：ObjC 成员表，实现者的签名从这里取。
- [ClassesWithoutClassObjects.md](ClassesWithoutClassObjects.md)：没有 class object 的类的 `class_ro_t`。
- [Modules/SwiftLayout.md](Modules/SwiftLayout.md)：存在类型的布局。
