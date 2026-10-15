# direct method 的新 ABI 与 Swift `@objcDirect`

- **上游链接**：Swift 提案 [swift-evolution#3501](https://github.com/swiftlang/swift-evolution/pull/3501)（第二次 pitch，[论坛帖](https://forums.swift.org/t/pitch-2-objcdirect-direct-dispatch-for-objective-c-exposed-methods/89708)）、实现 [swiftlang/swift#91894](https://github.com/swiftlang/swift/pull/91894)；clang 侧 [LLVM RFC](https://discourse.llvm.org/t/rfc-optimizing-code-size-of-objc-direct-by-exposing-function-symbols-and-moving-nil-checks-to-thunks/88866)、[llvm-project#170616](https://github.com/llvm/llvm-project/pull/170616)、[llvm-project#170618](https://github.com/llvm/llvm-project/pull/170618)
- **上游状态**：clang 侧已合入，随 LLVM 23 发布；Swift 侧是 pitch，提案状态 "Awaiting review"，实现 PR 未合，且只能在实验开关 `-enable-experimental-feature ObjCDirect` 下使用
- **最后核对**：2026-10-09
- **我们的动作**：观望，未立提案

## 一句话

direct method 是不走 `objc_msgSend` 的 ObjC 方法：调用方把它当普通 C 函数直接调用，它没有 selector，也不进类的 method list（ObjC runtime 用来按 selector 查找实现的那张表）。clang 从 2019 年起就支持 `__attribute__((objc_direct))`，LLVM 23 给它换了一套跨编译器可用的 ABI；Swift 提案在这套 ABI 之上新增 `@objcDirect`，让 Swift 方法也能以 direct method 的形式暴露给 ObjC。对我们来说，这类方法在 ObjC metadata 里不留痕迹，**ObjC 成员恢复会静默漏掉它们**；不会崩，也不会读错。

## 上游变了什么

### clang 侧：两代 ABI

| | 2019 设计（clang 10 起） | LLVM 23 的新 ABI（`-fobjc-direct-precondition-thunk`） |
|---|---|---|
| 符号名 | `\01-[Class sel]`，强制 hidden | `-[Class sel]D`，不再强制 hidden |
| receiver 为 `nil` 的检查 | 在被调用方里，每次都做 | 在调用方生成的 `-[Class sel]D_thunk` 里，只在调用方证明不了 receiver 非 `nil` 时才调用这个 thunk |
| class method 的类初始化（realization） | 被调用方里先发一次 `[self self]` | 在同一个 thunk 里，只在类可能尚未初始化时做 |
| `_cmd` 参数 | 留在签名里，调用方不赋值 | 不在签名里 |

`-[Class sel]D_thunk` 是 `linkonce_odr` 加 hidden：每个调用方的编译单元各自生成一份，链接时折叠，定义 direct method 的镜像里不一定有它。编译开关在 clang 22 就有，但只改符号名、不生成 thunk，真正可用的下限是 clang 23。

这套新 ABI **不依赖 Swift 提案是否通过**：用 clang 23 加这个开关编译的纯 ObjC 二进制，本身就会带 `-[Class sel]D` 符号。

### Swift 侧：`@objcDirect`

提案把编译器原本为每个 `@objc` 成员生成的桥接函数（符号以 `To` 结尾的 `@objc` thunk）原样复用，只改两处：符号名换成 `-[Class sel]D`，签名去掉 `_cmd`。Swift 原生入口 `$s…F`、vtable、method descriptor 都不变，提案明确说这个属性不改变 Swift ABI。

能写在哪里（编译器在这些位置之外都会报错）：

- 非泛型类的方法与 initializer，且必须是静态派发：不能是 `override`、`dynamic`（含 `@NSManaged`）、`required init`、`@IBAction`，也不能有子类覆写它。非 `final` 的方法只要没有子类覆写就可以写。
- 不能是 `private` / `fileprivate`，不能是协议 requirement，不能是 `async`。
- 不支持 property、accessor、subscript、`deinit`（提案把它们列为 future direction）。
- 可以写在 `@objc @implementation` extension 里，但必须与头文件里的 `objc_direct` 声明一致。SE-0436 原本把 `objc_direct` 列为 `@implementation` 表达不了的东西，这个提案补上了。

普及的门槛：import 生成头文件的**每一个** ObjC 编译单元都必须开同一个 clang 开关，否则链接时找不到符号。所以这是整个构建系统的设置，不是单个 target 能决定的。

## 二进制里会变成什么样

以一个 `@objc` 方法改成 `@objcDirect` 为例：

| 二进制里的事实 | 普通 `@objc` 方法 | `@objcDirect` 方法 |
|---|---|---|
| 类的 method list 条目（selector、type encoding、IMP） | 有 | 没有 |
| selector 字符串 | 有 | 没有（除非别处也用到同名 selector） |
| `@objc` thunk 的符号 | `$s…FTo`，local | 没有 `To` 符号，同一个函数改名为 `-[Class sel]D` |
| thunk 的参数 | `self, _cmd, 实参…` | `self, 实参…` |
| thunk 符号的可见性 | 永远 local | 方法的有效访问级别是 `public` 时导出，否则 hidden |
| Swift 原生入口、vtable、method descriptor | 有 | 不变 |
| `.swiftinterface` | `@objc` | `@objcDirect`，且 `swift-module-flags` 里记下 `-enable-experimental-feature ObjCDirect` |

符号里的类名是**生成头文件里的 `@interface` 名**：有 `@objc(Name)` 就是 `Name`，否则是 Swift 类的简单名（如 `Cache`），**不是** ObjC runtime 名（`_TtC3Mod5Cache`）。class method 用 `+[Class sel]D`，`throws` 方法在末尾多一个 `NSError **` 参数，`@objc(renamedSelector)` 改的是符号里的 selector 段。

## 对我们的影响

### 不受影响

- ABI 读取层（`MachOSwiftSection`）、demangler、`SwiftLayout`：Swift metadata 和 mangling 都没变。`-[Class sel]D` 不是 Swift 符号，符号索引对它的处理和对今天已有的 `-[Class sel]` 一样。
- Swift 侧 ABI diff（`SwiftDiffing`）：它本来就不比较 `@objc`，与提案「不改变 Swift ABI」一致。

### 静默漏信息

1. **ObjC 成员恢复看不到 direct method**。`ObjCMembers.table(...)`（`Sources/Analysis/SwiftThunkAnalysis/ObjCMembers/ObjCMembers.swift`）从类的 method list 出发，三档证据都要先有一个 IMP：第一档看 IMP 处的 `To` 符号，第二档反汇编 IMP 处的 thunk，第三档按 selector 名字匹配 method list 条目。direct method 不在 method list 里，三档都轮不到它。结果是 interface 和 dump 把它印成普通 Swift 方法，不带 `@objc`，也不带 `@objcDirect`。
   - 写了 `final` 的 direct method 没有 method descriptor，也没有 `@objc` 证据，`recoverFinalMembers`（`TypeDefinition+FinalRecovery.swift:64`）会给它补上 `final`，与源码一致。
   - 没写 `final` 的（提案允许，只要没有子类覆写）有没有 vtable 条目，提案没说，要等工具链可用后用 fixture 实测。
2. **`@objc @implementation` 类的 ObjC 段不再完整**。[ObjCImplementationClassRecognition.md](../ObjCImplementationClassRecognition.md) 的前提之一是「ObjC 方法表永远完整」，direct 成员打破了它：dump 的 ObjC 段会少掉这些方法。Swift 侧还能不能从符号里看到这些成员，要等工具链实测。
3. **`swift-section objc` 把「改成 direct」报成「删除」**。`objc diff` 看到的是 method list 少了一个条目，而这个方法其实变成了一个导出符号，我们没有读。纯 ObjC 的 direct method 在 2019 设计下本来就看不见，这不是新问题；新 ABI 让 `public` 的 direct method 有了可读的导出符号，才变成「能读而没读」。

## 将来支持时的要点

这里只记约束，方案到时候写进提案。

- **证据来源是符号名**：`-[Class sel]D` / `+[Class sel]D`，非 `public` 的在 local 符号表里（只在未 strip 的二进制里有），`public` 的在 export trie 里。从名字能读出类名、selector、实例方法还是 class method；读不到 type encoding，因为它没有 method list 条目。
- **系统 cache 里只剩 `public` 的**：hidden 符号会和 `To` thunk 一样被 strip 掉（AppKit 的 cache 镜像就是这样）。
- **联结到 Swift 成员可以复用第二档的 thunk 解码**：`-[Class sel]D` 的函数体就是原来的 `@objc` thunk，同样会调用 Swift 实现。区别是少了 `_cmd`，实参寄存器整体前移一位（第一个实参在 `x1`，不在 `x2`）；解码器只找调用目标时不受影响，读实参时要注意。
- **类名要按头文件名查**：没有 `@objc(Name)` 的类，符号里是 Swift 简单名，现有按 runtime 名查找的入口（`ObjCClassMethodIndex.runtimeNames(forSwiftClassQualifiedName:)`、`SwiftClassObjectIndex`）都对不上，需要新增一个按头文件名查找的入口。
- **不要把 direct method 记成 `.objc`**，要单独加一个属性 case。今天有两处把 `.objc` 读成「经 ObjC runtime 派发」：
  - `recoverFinalMembers` 把「有 `.objc` 且无 descriptor」当作 `@objc dynamic`、不补 `final`，而 direct method 恰恰是静态派发。
  - `--exported-only` 过滤（`SwiftDeclarationPrinter+ExportFilter.swift` 的 `isExcludedByExportFilter`）保留所有 `@objc` 成员，理由是镜像外能经 runtime 调到它们；hidden 的 direct method 在镜像外调不到，应当被过滤掉。
- **调用方镜像里的 `-[Class sel]D_thunk` 不是定义**：它是调用方为自己生成的前置检查函数，不能当作「这个镜像里有这个方法」的证据。反过来，调用方镜像里对 `-[Class sel]D` 的未定义引用能说明它跨镜像调用了哪些 direct method。
- **显式 selector 的判定照旧**：`@objc(renamedSelector) @objcDirect` 的符号里是改过的 selector，`ObjCMemberShape` 用编译器的推导规则比对的做法不需要改。
- **ObjC ABI diff 要把导出的 `-[Class sel]D` 当作链接期 ABI**：删掉一个 `public` direct method，旧客户端在 dyld 加载时就报找不到符号，而不是运行时报 unrecognized selector。

## 什么时候该动手

满足任意一条就立提案：

- 提案进入审查并被接受。
- Swift 的正式工具链里能用这个功能（不再需要实验开关）。
- 在真实二进制里见到第一个 direct 符号。检查方法：`nm <binary> | grep -E '[-+]\[[^ ]+ [^]]+\]D$'`，加 `(_thunk)?` 可以同时看调用方的 thunk。

## 核对记录

- 2026-10-09：swift-evolution#3501 open（第二次 pitch，"Awaiting review"）；swiftlang/swift#91894 open；llvm-project#170616 于 2026-01-05 合入，llvm-project#170618 于 2026-03-30 合入。尚未普查已有的系统二进制里有没有 `-[Class sel]D` 符号。
