# Objective-C 命令行 —— `swift-section objc`

> English version: [ObjCCommandLine.md](ObjCCommandLine.md)

`swift-section objc` 直接从磁盘读取二进制里 Objective-C 的那一面：把声明导出成头文件，以及跨版本
比较它的 API。二进制不会被加载进进程，所以可以：

- 在 x86_64 机器上分析 arm64e 的二进制；
- 在 macOS 上分析 iOS / watchOS 的二进制；
- 分析签名不匹配、依赖缺失、故意损坏的样本；
- 在 CI 里比较接口、批量导出头文件，不需要加载任何东西。

这组命令原先是 [MachOObjCSection](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection)
仓库里单独的 `objc-section` 可执行文件，最后一个版本是 0.8.106。参数、输出和退出码都没有变，把
`objc-section <子命令>` 换成 `swift-section objc <子命令>` 即可。底层的 Objective-C 库仍在
MachOObjCSection 里。

**从签名和 `--help` 里看不出来、但踩了就会得出错误结论的东西，全在「[必须知道的四件事](#必须知道的四件事)」一节**，
其余部分是常规用法。

## 五个子命令

```bash
# 导出二进制里所有的 Objective-C 声明
swift-section objc dump <file>

# 只导出一个类 / 协议 / 分类 / struct / union
swift-section objc interface <name> <file>

# 把二进制的 Objective-C API 冻结成基线快照（JSON）
swift-section objc snapshot <file> --label 26.0 -o baseline.json

# 比较两个二进制（或快照）的 Objective-C API
swift-section objc diff <old> <new>

# 跨 N ≥ 2 个版本追踪每个声明的生命线
swift-section objc evolution <v1> <v2> <v3> --labels 17.0,18.0,26.0
```

`dump` 是默认子命令，所以 `swift-section objc <file>` 等于 `swift-section objc dump <file>`。

## 输入：文件、cache 里的镜像、fat 二进制

拼写和 Swift 那几个命令完全一样，同一套参数在两边都能用：

| 选项 | 作用 |
|---|---|
| `<file>` | Mach-O 文件路径，或 dyld shared cache 文件路径 |
| `--dyld-shared-cache` | 声明 `<file>` 是一个 cache，而不是单个 Mach-O |
| `--uses-system-dyld-shared-cache` | 用当前系统的 cache，不需要给 `<file>` |
| `-n, --cache-image-name <name>` | 按名字取 cache 里的镜像，例如 `Foundation` |
| `-p, --cache-image-path <path>` | 按完整路径取 cache 里的镜像 |
| `-a, --architecture <arch>` | fat 二进制里取哪个架构（`x86_64` / `arm64` / `arm64e`） |

fat 二进制不给 `-a` 会报错，并列出可选的架构。Swift 命令的 `--dependency-search-path` 这里没有：
Objective-C 这边目前不读取别的镜像（见「必须知道的四件事」第一条）。

## 筛选与输出（`dump`、`interface`）

| 选项 | 作用 |
|---|---|
| `-s, --sections <kinds>` | 只导出这几类，**逗号分隔**：`--sections classes,protocols`。可选值 `classes` `protocols` `categories` `structs` `unions` |
| `-f, --filter <text>` | 只导出名字包含这段文本的声明，不区分大小写 |
| `-o, --output-path <path>` | 写进文件，而不是打印到 stdout |
| `-c, --color-scheme <scheme>` | 终端配色：`none`（默认）/ `light` / `dark` |
| `-v, --verbose` | 把索引进度打到 stderr；stdout 里只有声明本身 |

`interface` 还有一个 `--kind`，用来区分一个既是类名又是 struct 名的名字。不给的话按
类 → 协议 → 分类 → struct → union 的顺序取第一个找到的。

## 十个生成开关

全部默认关闭：一个开关都不加时，输出就是元数据的原样，不删任何东西，也不加任何注释。

| 开关 | 作用 |
|---|---|
| `--strip-protocol-conformance` | 去掉 `<Protocol, …>` 列表，以及这些协议已经声明过的成员 |
| `--strip-overrides` | 去掉只是覆写父类的成员（**分析单个文件时剥得更少，见下文**） |
| `--strip-synthesized-ivars` | 去掉 `@property` 合成的 ivar |
| `--strip-synthesized-methods` | 去掉 `@property` 合成的 getter / setter |
| `--strip-ctor-method` | 去掉 `.cxx_construct` |
| `--strip-dtor-method` | 去掉 `.cxx_destruct` |
| `--emit-ivar-offsets` | 每个 ivar 后面加偏移注释 |
| `--emit-property-attributes` | 每个属性后面加原始的 attribute 字符串 |
| `--emit-method-imp-addresses` | 每个方法后面加 `// IMP: 0x…` |
| `--emit-property-accessor-addresses` | 每个属性后面加 getter / setter 的 IMP 地址 |

## 注释模板

```bash
# 把 C 基本类型换一种写法，可以重复给
swift-section objc dump Foo --c-type-replacement "long long=NSInteger" --c-type-replacement double=CGFloat

# 一次换一整套，之后单独给的替换仍然优先
swift-section objc dump Foo --c-type-preset foundation

# ivar 偏移注释的措辞和进制（两个都会自动打开 --emit-ivar-offsets）
swift-section objc dump Foo --ivar-offset-template 'ivar @ ${offset}' --ivar-offset-decimal
```

C 类型两种写法都认：源码里的写法（`unsigned long long`，在 shell 里要加引号）和驼峰写法
（`ulongLong`）。类型名写错会直接报错，并列出所有支持的名字，不会悄悄忽略。`--c-type-preset`
有三套：`stdint`（换成 `uint32_t` 这类）、`foundation`（换成 `NSInteger` / `CGFloat`）、`mixed`
（整数用 stdint，长整型和浮点用 Foundation）。

这些模板和 Swift 命令的 `--transformer-config` 是分开的，后者读配置文件时会忽略 Objective-C 的键。

## snapshot / diff / evolution

输入可以混用：`diff` 和 `evolution` 的每个输入，既可以是 Mach-O / fat 二进制、dyld shared cache，
也可以是 `snapshot` 生成的 JSON。第一个非空白字节是 `{` 的文件按快照读取，其余的当场索引。
跨 OS 版本追踪系统框架，一般这样用：

```bash
# 每个 OS 版本存一份基线（慢的是索引，比较只要几毫秒）
swift-section objc snapshot 15.5/dyld_shared_cache_arm64e --dyld-shared-cache -n CoreLocation \
    --label 15.5 -o CoreLocation-15.5.json

# 之后比较就不再需要 cache
swift-section objc diff CoreLocation-15.5.json CoreLocation-26.5.json
swift-section objc evolution CoreLocation-*.json --summary-only
```

| 选项（`diff` 和 `evolution` 都有） | 作用 |
|---|---|
| `--summary-only` | 只打印结论（`diff`：是否破坏兼容的那一行；`evolution`：各次版本变化的摘要） |
| `--json` | 输出结构化 JSON，而不是文本报告（不能和 `--summary-only` 一起用） |
| `--fail-on-breaking` | 有破坏 API 兼容的变化时以非零退出码结束，给 CI 把关用 |
| `-o, --output-path <path>` | 写进文件，而不是 stdout（进度和日志一律走 stderr） |
| `--labels a,b,c` | 只有 `evolution` 有：版本轴的标签，每个输入一个；不给时取快照里存的标签或文件名 |

输入选项（`--dyld-shared-cache` / `-n` / `-p` / `-a`）和 `dump` 一样；在 `diff` 和 `evolution` 里的
意思是「每个输入都是 cache，从每一份里取同一个镜像」。`snapshot` 不接受
`--uses-system-dyld-shared-cache`：当前系统的 cache 没有一个稳定的路径可以记进基线。

## 必须知道的四件事

下面每一条，都会让一份看起来正常的输出把你引向错误的结论，而且签名和 `--help` 里都看不出来。

### 一、分析单个文件时，父类链到镜像边界就断了，所以 `--strip-overrides` 剥得更少

`--strip-overrides` 靠父类链工作：把每一级父类声明过的成员收集起来，从当前类里减掉。父类链能走多远，
取决于读的是什么：

- **单独的 Mach-O 文件**：链在第一个定义在别的二进制里的父类处停住。一个继承 `NSObject` 的类，
  链长只有 1（它自己），继承来的成员一个都剥不掉，输出里会留着 `init`、`dealloc` 这类东西。
- **dyld shared cache 里的镜像**：在同一个 cache 内部可以跨二进制往上走。
- **已加载进进程的镜像**（库里的 `MachOImage` 路径，RuntimeViewer 用的就是它）：所有依赖都已映射，
  链一路走到根类。

这不是 bug：跨二进制解析父类需要一整套镜像搜索和依赖解析，Objective-C 这边没有做。需要完整的父类链时，
分析 cache 里的那个镜像。

### 二、纯 Swift 类的 ivar 记录不可靠

编译器给纯 Swift 类（名字形如 `_TtC8ModuleName9TypeName`）生成的 Objective-C 兼容记录里，
`ivar_t.offset` 的值取决于怎么读：在进程里读到 0，从文件里读、做完 rebase 后是另一个值。个别 ivar
在进程里读不到偏移，会被整条丢掉，所以两边的 ivar 条数也可能不同。带 `@objc(ExplicitName)` 的 Swift
类用的是普通的 Objective-C ivar 记录，不受影响。纯 Swift 类的 ivar 偏移不要当准确值用。

### 三、基线快照不能跨格式版本使用

`snapshot` 生成的 JSON 带一个 `formatVersion` 头（当前是 1）。快照里的键格式（`method:-…`、`attr:…`、
`adopts:…` 这些命名空间字符串）就是事实上的持久化格式；键格式一变，旧基线和新工具比出来的结果会
**悄悄出错**。所以解码时严格校验版本号：不相等就直接报错
（`Unsupported ObjC API snapshot format version …`），要求用当前的工具重新生成。这是拿一次明确的报错，
换掉一整类悄无声息的误报。重新生成只需要一次索引，把基线存进 git 时，建议在文件名或目录里带上 OS 版本。
`objc-section` 0.8.106 生成的基线是格式版本 1，照样能读。

读 diff 结果时还要知道两点：

- **ivar 单纯的布局变化看不到。** 偏移故意不参与比较：non-fragile ABI 下它由运行时调整，而且中间插进
  一个 ivar，会让它后面的所有 ivar 都报变化。ivar 的类型变化仍然会报出来。
- **结论分不清公开 API 和私有实现。** Objective-C 没有访问控制，私有 selector 改名一样会报成破坏兼容，
  需要你结合语义自己判断。

### 四、`dump` 什么都没导出时，会在 stderr 说明原因，退出码仍然是 0

`dump` 一个声明都没导出时，会往 **stderr** 写一行，说明是哪一种「空」，**退出码仍然是 0**：

| stderr | 含义 |
|---|---|
| `no Objective-C metadata found in <image>` | 整个索引是空的：这个二进制里没有 Objective-C |
| `no <kind> found in <image>` | 你用 `--sections` 点名的某一类在这个二进制里是空的（每类一行） |
| `--filter '<text>' matched none of the <N> declarations in <image>` | 索引里有 N 个声明，但没有一个匹配 `--filter` |

第一种和第二种不会同时出现：整个索引为空时只报第一种。没有点名的类别不会报第二种，否则每次
dump 一个纯 Swift 二进制，都会为你根本没问过的四类刷屏。

**退出码保持 0 是有意的**：这些是诊断信息，不是失败，不应该让任何现有的脚本或 CI 因此变红。
需要把关时，用 `diff --fail-on-breaking`。
