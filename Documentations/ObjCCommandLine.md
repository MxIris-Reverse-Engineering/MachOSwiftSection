# Objective-C Command Line — `swift-section objc`

> 中文版：[ObjCCommandLine_zh.md](ObjCCommandLine_zh.md)

`swift-section objc` reads the Objective-C side of a binary from disk: its declarations as
headers, and its API compared across versions. The binary is never loaded into a process, so
you can:

- analyze an arm64e binary on an x86_64 machine;
- analyze iOS or watchOS binaries on macOS;
- analyze samples whose signature does not match, whose dependencies are missing, or that are
  deliberately damaged;
- diff interfaces and export headers in CI without loading anything.

These commands used to ship as a separate `objc-section` executable from
[MachOObjCSection](https://github.com/MxIris-Reverse-Engineering/MachOObjCSection), last released
as 0.8.106. Options, output and exit codes are unchanged; replace `objc-section <subcommand>`
with `swift-section objc <subcommand>`. The Objective-C libraries underneath still live in
MachOObjCSection.

**Everything that neither the signatures nor `--help` will tell you is in
[Things you must know](#things-you-must-know).** The rest of this page is ordinary usage.

## Five subcommands

```bash
# Every Objective-C declaration in a binary
swift-section objc dump <file>

# One class, protocol, category, struct or union
swift-section objc interface <name> <file>

# Freeze a binary's Objective-C API as a baseline snapshot (JSON)
swift-section objc snapshot <file> --label 26.0 -o baseline.json

# Compare the Objective-C API of two binaries (or snapshots)
swift-section objc diff <old> <new>

# Follow every declaration across N ≥ 2 versions
swift-section objc evolution <v1> <v2> <v3> --labels 17.0,18.0,26.0
```

`dump` is the default, so `swift-section objc <file>` is `swift-section objc dump <file>`.

## Input: files, cache images, fat binaries

The same spelling as the Swift commands, so one set of arguments works on both sides of the
tool:

| Option | Meaning |
|---|---|
| `<file>` | A Mach-O file, or a dyld shared cache file |
| `--dyld-shared-cache` | `<file>` is a cache, not a single Mach-O |
| `--uses-system-dyld-shared-cache` | Use the running system's cache; no `<file>` needed |
| `-n, --cache-image-name <name>` | Pick a cache image by name, e.g. `Foundation` |
| `-p, --cache-image-path <path>` | Pick a cache image by its full path |
| `-a, --architecture <arch>` | Which slice of a fat binary (`x86_64` / `arm64` / `arm64e`) |

A fat binary without `-a` is an error that lists the available architectures. The Swift
commands' `--dependency-search-path` is not available here: nothing on the Objective-C side
reads other images yet (see the first item under [Things you must know](#things-you-must-know)).

## Filtering and output (`dump`, `interface`)

| Option | Meaning |
|---|---|
| `-s, --sections <kinds>` | Only these kinds, **comma-separated**: `--sections classes,protocols`. Values: `classes` `protocols` `categories` `structs` `unions` |
| `-f, --filter <text>` | Only declarations whose name contains this text, case-insensitively |
| `-o, --output-path <path>` | Write to a file instead of stdout |
| `-c, --color-scheme <scheme>` | Terminal colors: `none` (default) / `light` / `dark` |
| `-v, --verbose` | Report indexing progress on stderr; stdout keeps only the declarations |

`interface` also takes `--kind` to disambiguate a name that is, say, both a class and a struct.
Without it the first match wins, in the order classes → protocols → categories → structs →
unions.

## Ten generation switches

All of them default to off: with none given, the output is the metadata as it stands, nothing
removed and nothing annotated.

| Switch | Effect |
|---|---|
| `--strip-protocol-conformance` | Drop the `<Protocol, …>` list, and the members those protocols already declare |
| `--strip-overrides` | Drop members that merely override a superclass member (**strips less on files — see below**) |
| `--strip-synthesized-ivars` | Drop ivars synthesized by `@property` |
| `--strip-synthesized-methods` | Drop getters and setters synthesized by `@property` |
| `--strip-ctor-method` | Drop `.cxx_construct` |
| `--strip-dtor-method` | Drop `.cxx_destruct` |
| `--emit-ivar-offsets` | An offset comment after each ivar |
| `--emit-property-attributes` | The raw attribute string after each property |
| `--emit-method-imp-addresses` | `// IMP: 0x…` after each method |
| `--emit-property-accessor-addresses` | Getter and setter IMP addresses after each property |

## Comment templates

```bash
# Respell C primitive types; repeatable
swift-section objc dump Foo --c-type-replacement "long long=NSInteger" --c-type-replacement double=CGFloat

# A whole set at once; individual replacements still override it
swift-section objc dump Foo --c-type-preset foundation

# The wording and radix of the ivar offset comment (both imply --emit-ivar-offsets)
swift-section objc dump Foo --ivar-offset-template 'ivar @ ${offset}' --ivar-offset-decimal
```

C types are accepted in both spellings: as in source (`unsigned long long`, quoted in a shell)
and in camel case (`ulongLong`). A misspelled type name is an error that lists every supported
name; it is never silently ignored. `--c-type-preset` has three sets: `stdint` (`uint32_t` and
friends), `foundation` (`NSInteger` / `CGFloat`) and `mixed` (stdint for integers, Foundation for
long integers and floating point).

These templates are separate from the Swift commands' `--transformer-config`, which ignores the
Objective-C keys of a configuration file.

## snapshot / diff / evolution

The inputs are interchangeable. Every input of `diff` and `evolution` can be a Mach-O / fat
binary, a dyld shared cache, or a JSON produced by `snapshot`; a file whose first non-blank byte
is `{` is read as a snapshot, and anything else is indexed on the spot. Following a system
framework across OS versions typically looks like this:

```bash
# One baseline per OS version (indexing is the slow part; comparing takes milliseconds)
swift-section objc snapshot 15.5/dyld_shared_cache_arm64e --dyld-shared-cache -n CoreLocation \
    --label 15.5 -o CoreLocation-15.5.json

# From then on, comparisons need no cache
swift-section objc diff CoreLocation-15.5.json CoreLocation-26.5.json
swift-section objc evolution CoreLocation-*.json --summary-only
```

| Option (`diff` and `evolution`) | Meaning |
|---|---|
| `--summary-only` | Only the verdict (`diff`: the breaking line; `evolution`: the transition summary) |
| `--json` | Structured JSON instead of the text report (not together with `--summary-only`) |
| `--fail-on-breaking` | Exit nonzero when there is an API-breaking change, for CI gating |
| `-o, --output-path <path>` | Write to a file instead of stdout (progress and logs always go to stderr) |
| `--labels a,b,c` | `evolution` only: the version axis, one label per input; defaults to each snapshot's stored label or the file name |

The input options (`--dyld-shared-cache` / `-n` / `-p` / `-a`) are the same as `dump`'s; for
`diff` and `evolution` they mean "every input is a cache, extract the same image from each".
`snapshot` rejects `--uses-system-dyld-shared-cache`: the running system's cache has no stable
path to record in the baseline.

## Things you must know

Each of these lets a normal-looking output lead to a wrong conclusion, and none of them shows
in a signature or in `--help`.

### 1. On a file, the superclass chain stops at the image boundary — so `--strip-overrides` strips less

`--strip-overrides` works off the superclass chain: it collects what every superclass declares
and subtracts it from the class. How far that chain reaches depends on what you read:

- **A standalone Mach-O file** — the chain stops at the first superclass defined in another
  binary. A class that inherits from `NSObject` has a chain of length 1 (itself), so nothing
  inherited can be stripped and `init`, `dealloc` and the like stay in the output.
- **An image inside a dyld shared cache** — the chain crosses binaries within that cache.
- **An image loaded into a process** (the library's `MachOImage` path, as used by RuntimeViewer)
  — every dependency is mapped, and the chain reaches the root class.

This is not a bug; resolving superclasses across binaries needs image search and dependency
resolution that the Objective-C side does not do. When you need the full chain, analyze the
image inside its cache.

### 2. Pure-Swift classes' ivar records are not reliable

For a pure-Swift class (a name like `_TtC8ModuleName9TypeName`) the compiler emits an
Objective-C compatibility record whose `ivar_t.offset` reads differently depending on how the
binary is read: 0 in-process, another value when read from a file after rebases. Some ivars can
even drop out in-process when their offset cannot be read, so the ivar counts may differ too.
Swift classes with `@objc(ExplicitName)` use ordinary Objective-C ivar records and are not
affected. Do not treat ivar offsets of pure-Swift classes as exact.

### 3. Baselines do not cross format versions

A `snapshot` JSON carries a `formatVersion` header (currently 1). Its key scheme (namespace
strings such as `method:-…`, `attr:…`, `adopts:…`) is the de facto persistence format, and a key
scheme change would make an old baseline compare **silently wrong** against a new tool. So the
version is checked strictly on decode: any other value is an error
(`Unsupported ObjC API snapshot format version …`) asking you to regenerate the baseline with
the current tool. That trades a class of silent misreports for one explicit error; regenerating
costs one indexing pass, so keep the OS version in the baseline's file name or directory when
storing it in git. Baselines written by `objc-section` 0.8.106 are format version 1 and read
unchanged.

Two more things to know when reading a diff:

- **A pure layout change of an ivar is invisible.** Offsets are deliberately left out of the
  comparison: the non-fragile ABI slides them at run time, and one inserted ivar would report
  every ivar after it. A change of an ivar's type is still reported.
- **The verdict cannot tell public API from private implementation.** Objective-C has no access
  control, so renaming a private selector is reported as API-breaking just the same; judge the
  meaning yourself.

### 4. An empty `dump` says why on stderr — and still exits 0

When `dump` emits no declaration at all, it writes one line to **stderr** naming the kind of
"empty", and the **exit code stays 0**:

| stderr | Meaning |
|---|---|
| `no Objective-C metadata found in <image>` | The whole index is empty: the binary carries no Objective-C |
| `no <kind> found in <image>` | A kind you named with `--sections` is empty in this binary (one line per kind) |
| `--filter '<text>' matched none of the <N> declarations in <image>` | The index has N declarations, and none matches `--filter` |

The first and the second are exclusive: an entirely empty index gets only the first line. The
second is never printed for kinds you did not name, or every dump of a pure-Swift binary would
complain about four kinds nobody asked for.

**Keeping exit code 0 is deliberate**: these are diagnostics, not failures, and no existing
script or CI job should turn red over them. For gating, use `diff --fail-on-breaking`.
