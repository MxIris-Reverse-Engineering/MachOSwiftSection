# Draft - Swift 源码定义的 `@objc` 协议，以及类对 ObjC 协议的遵循

- **状态**: In Progress
- **创建日期**: 2026-10-28
- **最后更新**: 2026-10-28
- **所属愿景**: 无
- **关联提案**: [0048-objc-member-selector-recovery](0048-objc-member-selector-recovery.md)（ObjC 成员表：按 selector 把类的 ObjC 方法联结到 Swift 成员，本提案从这里取实现者的签名）、[0078-objc-classes-without-class-objects](0078-objc-classes-without-class-objects.md)（没有 class object 的类的 `class_ro_t`，它们的协议表也从那里读）
- **实现分支 / PR**: `feature/swift-declared-objc-protocols`（worktree `.worktrees/MachOSwiftSection-SwiftDeclaredObjCProtocols`，自 `next` 分出）
- **配套文档**: 落地时写实现说明

## 摘要

Swift 源码里定义的 `@objc` 协议在 `dump` 和 `interface` 里都不出现。编译器给这种协议只生成 ObjC 运行时的协议记录（`protocol_t`，登记在 `__objc_protolist`），不在 `__swift5_protos` 里生成 protocol descriptor（`GenMeta.cpp` 的 `emitProtocolDecl` 在 `isObjC()` 分支直接返回），而本库只从 protocol descriptor 认协议。这些协议现在只以两种形式出现：作为类型被引用时的名字，以及 protocol extension 成员组成的 `extension DVTFoundation.DVTTeamCredential { … }`。同一个原因带出第二个缺口：ObjC 协议没有 witness table，`__swift5_proto` 里也就没有遵循记录，所以 Swift 类对任何 ObjC 协议的遵循在 interface 里全部丢失——Swift 定义的协议是这样，`NSCopying`、各种 delegate 这类导入的协议也是这样（`class DVTIconReference: __C.NSObject` 少了 `DVTResourceReference, NSCopying`）。需求由 RuntimeViewer 会话转来，样本是 Xcode 的 DVTFoundation，里面有 11 个这样的协议。本提案从 ObjC 元数据与反射元数据把两者都还原出来。

## 方案

### 哪些 `@objc` 协议是本镜像定义的

- **以 `__swift5_fieldmd` 为准**：`emitProtocolDecl` 在进入 `isObjC()` 分支之前就调用了 `emitFieldDescriptor`，所以本模块定义的每个 `@objc` 协议都有一条 kind 为 `ObjCProtocol` 的 field descriptor，名字是协议的 Swift mangling。DVTFoundation 实测正好 11 条，两个用 `@objc(Name)` 改过名的也在其中。ABI 层要新增 `__swift5_fieldmd` 的整段遍历：本库目前只顺着类型描述符的指针读 field descriptor，而协议没有类型描述符指向它。
- **不靠 `protocol_t.flags` 的 bit 0（`ProtocolDescriptorFlags::IsSwift`）**：这一位只说明这份记录是哪个编译器生成的，两个方向都会错。
  - 本镜像引用别的模块定义的 Swift `@objc` 协议时，Swift 也会生成一份带这一位的弱定义副本（`GenObjC.cpp` 的 `getObjCProtocolGlobalVars`），只看这一位会把别人的协议当成自己的。
  - ObjC 代码经生成的 `-Swift.h` 头文件引用 Swift 协议时，clang 生成的副本这一位是 0。DVTFoundation 里 DVTNFASupport 定义的 `_TtP13DVTNFASupport24NFAImageDownloadObserver_` 就是这样，引用它的 `NFAImageDownloaderDelegate` 是 ObjC 类。
  - Swift 与 clang 生成的记录符号名不同（Swift 的是 `_PROTOCOL_<名字>`，clang 的是 `_OBJC_PROTOCOL_$_<名字>`），链接时不会合并。一个 Swift 协议若既被 Swift 代码引用、又被 ObjC 代码经 `-Swift.h` 引用，同一镜像的 `__objc_protolist` 里就有两份同名记录，一份这一位是 1，一份是 0。
  - 所以配对与退回路径都只看名字；同名的两份都在时，协议体取这一位为 1 的那份（Swift 自己生成的）。
- **field descriptor 与 `protocol_t` 的配对**：没改名的按运行时名 `_TtP<模块><名字>_` 配；改过名的按「ObjC 名等于 Swift 名的最后一段」配，DVTFoundation 的两个都是 `@objc(X) protocol X` 这种写法。运行时名与默认的 `_TtP…` 不同，就说明源码写了 `@objc(Name)`，interface 照样打出来。ObjC 名与 Swift 名不同的配不上：照样打出声明，协议体里写一行注释说明找不到它的 ObjC 记录；dump 列出没配上的记录。
- **镜像没有反射元数据时**（编译时关掉了）退回：运行时名是 `_TtP…` 且模块是本镜像的 Swift 模块之一的，算本镜像定义。这时改过名的协议认不出来。
- 结果放进 SwiftInspection 的一个按镜像的索引（`SharedCache`，带驱逐组），同时给出「运行时名 → Swift 名」的换算，第二部分与 SwiftLayout 都用它。

### 协议声明怎么写

- **头部**：`@objc protocol X: A, B`，改过名的加 `@objc(运行时名)`。继承的协议来自 `protocol_t` 的协议表，名字的换算见下文「ObjC 协议名换成 Swift 名」。
- **要求**：逐条读 `protocol_t` 的四张方法表（required / optional 各分实例与类）、属性表，以及带类名的扩展类型编码（extended method types，例如 `teamNameFor:error:` 是 `@"NSString"32@0:8@"NSString"16^@24`）。
  - 属性的 getter 与 setter selector 归到属性上；有没有 setter 看属性表的 readonly 标记与 setter selector。
  - `objectAtIndexedSubscript:` 这类归到 subscript；`init` 家族的 selector 是初始化器。
  - 类方法打 `static`，optional 的要求打 `@objc optional`。
- **二进制里没有要求的 Swift 符号**：探针确认，无论 public 还是 internal、开不开 library evolution，编译器都不给 `@objc` 协议的要求生成任何 Swift 符号。和协议有关的 Swift 符号只有 protocol extension 成员、field descriptor、typeref，以及用 key path 引用属性时生成的 key path getter（local 符号，`strip -x` 后就没了）。剥过 local 符号的镜像里只剩导出的 protocol extension 成员。
- **Swift 签名有两个来源**：
  1. **本镜像里的 Swift 实现者**，签名是精确的。采纳这个协议的 Swift 类（读第二部分的协议表，采纳子协议的也算）有 ObjC 成员表（提案 0048），按 selector 找到联结上的 Swift 成员，照抄它的签名，并打一行注释说明取自哪个实现者。只认符号与 thunk 联结的前两档，不认只按名字的第三档。签名在协议自己的索引里经成员表读取，不去索引实现者的类型定义——索引期不许索引别的定义。
  2. **只有 selector**：Swift 名照 ClangImporter 的规则从 selector 推出，再用 `@objc(原 selector)` 把 selector 钉住。Swift 拼法可能与源码不同，ObjC 层面的含义不变。
     - 名字移植 importer 的 `omitNeedlessWords`（`lib/Basic/StringExtras.cpp`）：
       - 在第一段的最后一个介词处拆出基名与第一个参数标签（`splitBaseName`，`instantiateWithOwner:options:` → `instantiate(withOwner:options:)`）；
       - 按参数与返回值的类型名删掉多余的词（`nameForObject:` 的参数是 `id`，删掉 `Object` 得到 `name(for:)`）；
       - 初始化器去掉 `With`（`initWithFrame:` → `init(frame:)`）；
       - `…error:` 与 `…AndReturnError:` 按编译器的 error 约定还原成 `throws`；
       - completion handler 保持 closure 形式，不改写成 `async`：importer 两种都给，一条协议要求只能打一种。
     - 再去掉 Swift 在第一个参数标签前插入的 `With`：第一个标签以 `with` 开头、后面还有词时去掉 `with`（`hangPoints(withInput:)` → `hangPoints(input:)`）。这是编译器那条插入规则的逆运算，探针里 4 条只差 `with` 的全部改对；源码本来就写了 `withInput:` 这种标签的会被改成 `input:`，同样由 `@objc(selector)` 钉住。
     - 类型从扩展类型编码换算，也照 importer 的桥接规则：`NSString` → `String`、`NSArray` → `[Any]`、`NSDictionary` → `[AnyHashable : Any]`、`id` → `Any`、`id<P>` → 协议存在类型、block → closure；Swift 类按 `_TtC` 名 demangle，改过运行时名的 Swift 类经 `SwiftClassObjectIndex` 换回 Swift 名。可空性不知道，一律写 `!`，与 importer 对没有可空性标注的 ObjC 声明的做法相同。编码由本库自己的小解析器读（只覆盖扩展类型编码）；类型以 node 构造、经打印器输出，不拼字符串，模块选择器才能生效。
     - 协议体里有这种要求时，开头打一行注释，说明 Swift 名是从 selector 推出来的。
     - 探针（2026-10-28，Swift 6.4.2）的做法：只拿二进制里的事实拼出 ObjC 头文件，交给真正的 ClangImporter（`swift-synthesize-interface`）导入，再和源码原名对比。
       - 编译器自己推导 selector 的 15 条要求，12 条还原出源码原名（其中 `refresh() async throws` 对上的是 importer 另给的 async 版本）。没对上的 3 条都差在 Swift 插入的 `With`：`hangPoints(input:)` 成了 `hangPoints(withInput:)`。
       - 照苹果写法显式写了 selector 的 10 条，5 条对上，包括 `@objc(nameForObject:) func name(for:)`、`@objc(indexOfObject:) func index(of:)`。没对上的有 `@objc(removeObjectAtIndex:) func remove(at:)`（成了 `removeObject(at:)`）、`@objc(stringByAppendingString:) func appending(_:)`（成了 `string(byAppending:)`），以及 `@objc(isEnabled) var enabled`：属性表里记的名字就是 `isEnabled`。
       - 对不上的都由 `@objc(selector)` 钉住，含义不变。

  DVTFoundation 的两个协议会打成这样：

  ```swift
  @objc protocol DVTActorProtocol {
      // Swift names follow the ClangImporter's rules for these selectors;
      // the binary records no Swift names for them.
      @objc(userVisibleRolesForDeveloperTeamId:)
      func userVisibleRoles(forDeveloperTeamId: Swift.String!) -> [Any]!
      @objc(teamNameFor:error:)
      func teamName(for: Swift.String!) throws -> Swift.String
      @objc(developerTeamIds)
      var developerTeamIds: [Any]! {
          get
      }
  }

  @objc protocol DVTResourceReference: __C.NSObjectProtocol {
      // Taken from the conformer DVTFoundation.DVTIconReference.
      var resourceKey: __C.NSCopying {
          get
      }
  }
  ```

- **protocol extension 成员**（现在单独打成 `extension DVTFoundation.DVTTeamCredential { … }`）改作协议的默认实现，打在协议声明后面，与普通 Swift 协议一致。
- 嵌套在类型里的 `@objc` 协议（SE-0404，少见）打进顶层的 `extension 父类型 { … }`。

### 类对 ObjC 协议的遵循

- **数据从哪来**：编译器把类声明本身写的 ObjC 协议遵循记进 `class_ro_t` 的协议表，每个 extension 写的记进它那个 category 的协议表（`GenClass.cpp` 的 `visitConformances` 用 `getLocalConformances(.OnlyExplicit)` 按声明位置取）。逐个读本镜像 Swift 类的这两种表；没有 class object 的类从提案 0078 的 `SwiftClassWithoutClassObjectIndex` 取 `class_ro_t`。`ObjCClassMethodIndex` 已经在读这些协议表，目前只取 selector，改为同时记下协议名；provider 接缝（RuntimeViewer 交来的 `ObjCClassHierarchy`）一并带上协议名。
- **interface**：`class_ro_t` 里的协议打进类声明头部、父类之后（`class DVTIconReference: __C.NSObject, DVTFoundation.DVTResourceReference, __C.NSCopying`）；category 里的协议打成单独的 `extension X: P {}`。编译器还会把「非 ObjC 协议继承的 ObjC 协议」记进表里（`getObjCProtocols` 的递归），能从那个 Swift 协议的 requirement signature 判定出来的就去掉，不打。
- **dump**：类的 dump 加一行 `// ObjC protocols: …`，category 里的协议标出来自 category。

### ObjC 协议名换成 Swift 名

两部分共用这一套：

- `_TtP…_` 按旧式 mangling 解出模块与名字。
- 本镜像改过名的 Swift 协议查上面的索引。
- 别的镜像定义、又改过名的 Swift 协议，到依赖闭包里那个镜像的同一种索引里找（与 ObjC 祖先链用同一个闭包）；找不到就按 ObjC 名写，并在 dump 里注明。
- 导入的 ObjC 协议写成 `__C.<名字>`；与同名 ObjC 类冲突的加 `Protocol` 后缀（`NSObject` → `NSObjectProtocol`），这是 importer 的规则。

### 其余

- **dump**：放进现有的 `protocols` 段，按段排与按二进制顺序排两种方式都放。每条要求同时写出 Swift 声明与 ObjC 侧的事实：selector、类型编码、required 还是 optional、联结上的实现者。
- **模型**：SwiftDeclaration 新增一个独立的定义类型（暂名 `ObjCProtocolDefinition`），indexer 新增对应的集合。要求用自己的类型表示（selector、实例还是类、required 还是 optional、类型编码、Swift 声明的 node、签名来源），不伪造符号。不把 `ProtocolDefinition.protocolDescriptor` 改成可选：那会破坏下游源码。
- **`--exported-only`**：这种协议自己没有符号，判断不了是否导出，按无结论保留。用现有的无结论 case 还是新增一个，落地时看下游有没有穷举 `ExportStatus` 的 `switch` 再定。
- **SwiftLayout**：`ObjCProtocolIndex` 改用新索引给出的 Swift 名，存在类型的布局也能认出改过名的协议；没有反射元数据时仍按 `_TtP` 名认。
- **默认开启**，不加 CLI flag。

### 不做

- ABI snapshot、diff、evolution 暂不收录这两类事实：要改快照格式，记为后续。
- 不到别的镜像里找协议的实现者。
- APINotes 的 `SwiftName` 改名不还原，这种导入协议按 ObjC 名写。
- 链接器把 category 合并进类（category merging）时，extension 里写的遵循会出现在类声明头部，分不出来。

### 验证

- 测试时现编的 fixture，覆盖：没改名的协议、`@objc(同名)` 与 `@objc(不同名)` 的协议；required 与 optional、实例与类、只读与可写属性、subscript、初始化器、`throws`、block 参数；继承 `NSObjectProtocol` 与另一个 `@objc` 协议；protocol extension 成员；在类声明里与在 extension 里采纳协议的 Swift 实现者；采纳 `NSCopying` 的类；没有实现者的协议；引用另一个模块定义的 Swift `@objc` 协议（证明副本不会被当成本镜像定义的）；关掉反射元数据的变体（退回路径）。
- 命名规则的单元测试以探针里真实 ClangImporter 的输出为准：同一批 selector 与类型，移植的规则要给出与 importer 相同的 Swift 名。
- SymbolTestsCore 已有三个 Swift `@objc` 协议，快照随之更新。`ObjCClassWrappers.swift` 里说 `@objc protocol` 会生成 Swift protocol descriptor 的注释是错的，同批改正。
- DVTFoundation 手工核对：11 个协议都打出来；`DVTIconReference` 的头部有 `DVTResourceReference, NSCopying`；只是被引用的 `NFAImageDownloadObserver`（DVTNFASupport 定义）不打成声明。
- 渲染 A/B：差异只应是新增的协议声明、类头部与 extension 上的 ObjC 遵循，以及挪到协议后面的 protocol extension，不应有消失的声明。

### 落地步骤

每一步都能单独编译通过、带上自己的测试，完成后提交并推送功能分支。测试在 Ultra 上跑。

1. **找出本镜像定义的 `@objc` 协议**：ABI 层遍历 `__swift5_fieldmd`；SwiftInspection 的按镜像索引，含配对、退回路径与「运行时名 → Swift 名」的换算；读 `protocol_t` 的方法表、属性表与扩展类型编码。MachOObjCSection 的 `extendedMethodTypes(in:)` 只返回表里第一条，本库按下标读整张表。测试用测试时现编的 fixture，带一个引用另一个模块 Swift `@objc` 协议的镜像，以及关掉反射元数据的变体。
2. **从 selector 推出 Swift 声明**：移植 importer 的命名规则、去掉 Swift 插入的 `With`、类型编码解析与桥接，构造声明的 node。测试以探针里真实 ClangImporter 的输出为准。
3. **声明模型与索引**：`ObjCProtocolDefinition` 与要求的类型、indexer 的集合、实现者的签名、protocol extension 改作默认实现、导出状态。
4. **打印**：interface 的协议声明，以及 dump 的 `protocols` 段。
5. **类对 ObjC 协议的遵循**：读 `class_ro_t` 与 category 的协议表，打在类声明头部、`extension X: P {}` 与 dump 里。
6. **SwiftLayout 的 `ObjCProtocolIndex`** 改用新索引。
7. **验证**：SymbolTestsCore 的快照、全量测试、渲染 A/B、DVTFoundation 手工核对。
8. **文档**：实现说明、模块文档、`CLAUDE.md` 的模块清单、术语表、演进账本、插件 skill、文档索引。

### 后续项

- RuntimeViewer 采用：列出并打印新的定义类型。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-28 | Created as Draft，轻量档 | RuntimeViewer 会话转来的需求：interface 与 dump 完全不输出 Swift 源码定义的 `@objc` 协议，样本是 DVTFoundation。 |
| 2026-10-28 | 类对 ObjC 协议的遵循放进同一份提案 | 用户决定。两部分读同一份 ObjC 协议表、用同一套 ObjC 名到 Swift 名的换算，而遵循的影响面比协议声明还大。 |
| 2026-10-28 | 只有 selector 的要求：Swift 名照 ClangImporter 的规则从 selector 推出，再用 `@objc(原 selector)` 钉住 | 用户决定。selector 钉住之后 ObjC 层面的含义不变，名字又读起来像 Swift。最初选的「Swift 名直接照抄 selector」被这个替代；「协议体里只写 ObjC 声明的注释」没有采用。类型照 importer 桥接、可空性未知写 `!`，是随之采用的假设。 |
| 2026-10-28 | 本镜像定义了哪些协议以 `__swift5_fieldmd` 为准，`protocol_t` 的 IsSwift 位只用来挑候选 | 本镜像引用别的模块的 Swift `@objc` 协议时，也有一份带 IsSwift 位的副本。DVTFoundation 实测两种来源都是 11 条，改过名的两个都在 fieldmd 里。 |
| 2026-10-28 | 新增独立的定义类型，不动 `ProtocolDefinition` | 把 `protocolDescriptor` 改成可选会破坏下游源码；新类型是纯增量，RuntimeViewer 跟进展示即可。 |
| 2026-10-28 | IsSwift 位连挑候选也不用，配对与退回路径只看名字；同名记录有两份时协议体取这一位为 1 的那份 | 核实时发现 clang 生成的副本这一位是 0（DVTFoundation 里的 `_TtP13DVTNFASupport24NFAImageDownloadObserver_`）。Swift 与 clang 的记录符号名不同（`_PROTOCOL_<名字>` 与 `_OBJC_PROTOCOL_$_<名字>`），不会合并，所以混合语言镜像里同一个 Swift 协议可能有两份同名记录，一份 1、一份 0。前面那条「IsSwift 位只用来挑候选」的决定由此作废。这一行起初把原因写成「链接器只留一份同名弱定义」，RuntimeViewer 会话用 `nm` 与 clang 源码指出不成立，已更正。 |
| 2026-10-28 | 名字移植 importer 的完整 `omitNeedlessWords`，包括依赖类型名的删词 | 用户要求先用探针验证。探针显示 `@objc(nameForObject:) func name(for:)` 这种苹果写法要靠按类型名删词才能还原（参数是 `id`，删掉 `Object`）；起初的方案只移植 `splitBaseName`，由此改正。探针也确认「只剩 selector」与访问级别无关：所有 Swift `@objc` 协议的要求都没有 Swift 符号。 |
| 2026-10-28 | 用户批准，开始实现；去掉 Swift 插入的 `With` 这一步要加 | 用户决定。 |
| 2026-10-28 | 拆出落地步骤 | 方案原来没有能逐步验证的步骤。 |
| 2026-10-28 | 扩展类型编码按下标读整张表，类型编码用本库自己的小解析器 | MachOObjCSection 0.8.201 的 `extendedMethodTypes(in:)` 只返回第一条；swift-objc-dump 的 `ObjCTypeDecodeKit` 不是对外的 product，只能经 `ObjCDump` 间接 import。两处都在本库里解决，不为此给别的仓库发版。 |
