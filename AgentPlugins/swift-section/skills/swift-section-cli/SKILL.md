---
name: swift-section-cli
description: >-
  Recovering Swift and Objective-C declarations and ABI facts from a Mach-O binary or a dyld
  shared cache with the `swift-section` CLI — dumping types / protocols / conformances,
  generating a .swiftinterface offline, Objective-C headers with IMP addresses, diffing the API
  of two builds, tracking it across OS versions, and the static field-offset / type-layout /
  enum-layout comments. Read before running swift-section, and whenever a task needs type
  information out of a binary without loading it into a process. Triggers on swift-section,
  swift-section objc, objc-section, MachOSwiftSection, __swift5_types, swiftinterface,
  ABI diff, ABI baseline.
---

# swift-section

A CLI that reads Swift metadata straight out of a Mach-O file — the compiler-emitted
`__swift5_*` sections plus the symbol table — and reconstructs source-level declarations from
it. Nothing is loaded into a process and no source or `.swiftmodule` is needed, so it works on
a stripped OS framework, a third-party app binary, or an image inside a dyld shared cache. Its
`objc` subcommand does the same for the Objective-C metadata (§1).

**Where it sits next to other reverse-engineering tools.** It is the offline, scriptable form
of the library [RuntimeViewer](https://github.com/MxIris-Reverse-Engineering/RuntimeViewer)
uses. Reach for it when the target is a file rather than something loadable, when the build is
not the one running on this machine (an archived cache, another OS version, another platform),
or when the answer must be diffed or committed. swift-section recovers *declarations, layout
and addresses*, never instruction-level behaviour: for what a method actually does, take its
address from here (`--emit-member-addresses`, or the IMP comments of `objc`) and hand that
address to a disassembler or decompiler opened on **the same build**. An address from one build
means nothing in another.

## 0. Confirm the version before trusting a flag

The installed binary (`brew install swift-section`, on `PATH`) is often older than the
repository, and flags are added frequently. Confirm before building a command line on one:

```bash
swift-section --version
swift-section interface --help | grep -- --exported-only    # empty ⇒ this build lacks it
```

Flags added comparatively late, and therefore worth checking: `--emit-header`,
`--emit-export-status`, `--exported-only`, `--jobs`, `evolution --interface`,
`--supplementary-apinotes`, and from 0.20.0 `--dependency-search-path`,
`--infer-objc-overrides` and the whole `objc` subcommand group. When one is missing, say so
rather than silently producing a weaker answer — the alternative is usually "upgrade
(`brew upgrade swift-section`), or do without that annotation".

## 1. Pick the subcommand

| The question | Subcommand |
|---|---|
| What Swift types / protocols / conformances does this binary contain? | `dump` |
| Give me something that reads like Swift source (or pastes into an editor) | `interface` |
| What changed in the ABI between these two builds? | `diff` |
| Freeze today's ABI so a future build can be compared without keeping the binary | `snapshot` |
| How did this API evolve across N OS versions? | `evolution` |
| Reformat the memory-layout comments the two above emit | `transformer` |
| Objective-C headers, IMP addresses, or an Objective-C API diff (0.20.0+, formerly the separate `objc-section` executable) | `objc` — read `references/objc.md` first |

`dump` is the default subcommand: `swift-section <path>` is `swift-section dump <path>`.

**`dump` versus `interface` is not a cosmetic choice.** `dump` walks the sections one by one
and prints what each record literally says — descriptors, witness-table entries, associated
types — in binary order if asked. `interface` builds a whole declaration model first: it
indexes every symbol in the image, merges extensions, joins accessors to their vtable entries,
recovers `final` / `class` keywords, and only then prints. That model is what makes the output
readable, and it is also why `interface` costs orders of magnitude more (see §5). Start with
`dump` to find out whether the type is even there; escalate to `interface` when you need to
read it.

## 2. Pointing it at the binary

Three input shapes, and the option that selects each:

```bash
# 1. A file on disk. A fat (universal) binary REQUIRES an architecture — the tool
#    refuses to pick a slice and lists what it found.
swift-section dump /path/to/Foo.framework/Foo --architecture arm64e

# 2. An image inside the running system's shared cache (frameworks are not on disk
#    as separate files on modern macOS/iOS).
swift-section dump --uses-system-dyld-shared-cache --cache-image-name SwiftUICore

# 3. An image inside a specific cache file (an archived one, a simulator runtime's).
swift-section dump --dyld-shared-cache --cache-image-path /System/Library/.../SwiftUI /path/to/dyld_shared_cache
```

- `-n` / `--cache-image-name` takes a **bare image name** (`SwiftUICore`); `-p` /
  `--cache-image-path` takes the **install path**. Pass exactly one — both together is an
  error. Prefer `-p` when a leaf name is ambiguous inside the cache (a macOS cache carries
  Mac Catalyst builds under `/System/iOSSupport` with the same leaf names).
- `diff` and `evolution` read `--dyld-shared-cache` differently: it means "every input path is
  a cache, extract the same `-n` image from each". They have no
  `--uses-system-dyld-shared-cache`, and `snapshot` rejects it on purpose (a baseline needs a
  stable recorded path).
- Neither `-n` nor `-p` does anything without one of the cache flags.
- **A standalone file's dependencies are looked for, not given.** Some facts live in another
  image: a type behind a metadata accessor (an availability-conditional `some View`), a
  cross-module type's layout, an Objective-C superclass (`override`, explicit selectors). By
  default the tool infers paths from where the binary sits and falls back to the running
  system's cache — which never offers an image of another platform. So an iOS binary read on a
  macOS host needs `--dependency-search-path` (`dump`, `interface`, `snapshot`; repeatable)
  naming its runtime: a Mach-O file, a cache file (`dyld_shared_cache_*` /
  `dyld_sim_shared_cache_*`), or a directory used as a system root such as a simulator
  runtime's `RuntimeRoot`. Named paths are consulted before the running system's cache. When
  those facts are missing from an iOS binary's output, suspect this flag before the binary.

## 3. Never redirect `interface`'s stdout — pass `-o`

`interface` writes its progress lines to **stdout**, mixed into the product:

```
$ swift-section interface -a arm64e /bin/ls > out.txt   # WRONG
$ head -3 out.txt
Preparing to build Swift interface...
[INFO] Extracted 0 symbol index
[INFO] Types: 0 successful, 0 failed, ...
```

Use `--output-path` / `-o` for anything that will be read back, diffed, or committed. The same
holds for `dump`, whose per-declaration error lines also land on stdout — a `dump` redirect
silently mixes `Error: …` lines into the product.

`diff` / `snapshot` / `evolution` are the well-behaved ones: progress and degradation
diagnostics go to stderr, the report to stdout, so `>` is safe there. Their stderr chatter
(dropped declarations, unresolved dependencies) is **normal reporting, not failure** — judge
those runs by the exit code.

## 4. `dump` and `interface` do not share flag spellings

The single most common mistake. Same underlying comment, different name:

| Comment | `dump` | `interface` |
|---|---|---|
| Field offsets | `--emit-field-offsets` | `--emit-offset-comments` (field **and** PWT offsets) |
| PWT addresses | `--emit-pwt-addresses` | folded into the above |

Spelled the same on both: `--emit-type-layout`, `--emit-enum-layout`, `--emit-member-addresses`,
`--emit-vtable-offsets`, `--emit-expanded-field-offsets` (implies the field-offset flag),
`--emit-header`, `--emit-export-status`, `--color-scheme`, `--output-path`,
`--dependency-search-path` (§2).

Only `dump` has: `--sections`, `--preferred-binary-order`, and the demangler option group
(`--demangle-options default|simplified|interface` plus ~22 `--enable-…` / `--disable-…`
switches).

Only `interface` has: `--exported-only`, `--sort-members-by-offset`,
`--parse-opaque-return-type`, `--show-c-imported-types`, `--resolve-c-module-names`,
`--supplementary-apinotes`, `--infer-objc-overrides`.

`--infer-objc-overrides` is off by default for a reason. An override whose body the optimizer
inlined into its thunk (`viewDidHide`, `encodeWithCoder:` in an OS framework) ties to no Swift
symbol; the flag attributes it anyway, to the one member whose name is the importer's spelling
of the selector. `dump` always shows such ties, marked `(selector name, no symbol evidence)`;
an interface has nowhere to say a keyword rests on a name, so it adds `override` only when
asked.

### `--sections` has two traps

```bash
swift-section dump --sections types,protocols /path/to/binary      # ERROR: comma is not a separator
swift-section dump --sections types protocols /path/to/binary      # ERROR: the path is eaten as a section
swift-section dump /path/to/binary --sections types protocols      # correct — path first
swift-section dump --sections types protocols -- /path/to/binary   # correct — `--` ends the list
```

It consumes values up to the next option, so the positional file path must not follow it.
Both wrong forms above are the ones a comma-separated habit produces, and neither fails in an
obvious way if you are skimming — read the error text. The habit is easy to pick up in this
very executable: `swift-section objc dump --sections` **is** comma-separated
(`--sections classes,protocols`).

Also: **with no `--sections`, a section that is missing or unreadable is skipped silently** —
a binary with no Swift content produces zero output and exit status 0. Pass the section
explicitly to get the diagnosis (`Swift section __swift5_assocty not found …`). So "empty
output" never by itself means "no Swift in there"; confirm with an explicit `--sections`.

## 5. `interface` is expensive; `dump` is not

`interface` builds the whole image's demangled symbol index before printing anything. On a
large system framework (SwiftUI, SwiftUICore) that is tens of seconds to minutes and a lot of
resident memory. Budget for it:

- Explore with `dump` (optionally `--sections types`) first; run `interface` once you know the
  target is there.
- Never run `interface` over a whole dyld shared cache image set casually.
- `diff` and `evolution` index **every** input, so cost multiplies by the number of versions.
  `--jobs N` bounds how many index at once (default: processor count); each in-flight input
  holds its indexed image in memory, so lower it when memory is the constraint, not `1` for
  speed's sake.
- Anything long-running belongs in a background run written to a file with `-o`, not in a
  foreground command that will be waited on.

## 6. Comment templates

The five layout comment kinds (field offset, vtable offset, member address, type layout, enum
layout) render from `${token}` templates, and `dump` / `interface` accept the template options
directly.

```bash
swift-section transformer templates --module field-offset   # names accepted by the options
swift-section transformer tokens --module enum-layout       # placeholders those templates take
```

- A value containing `${` is a literal template; anything else must **name** a built-in
  template (matched case / space / hyphen / underscore insensitively). A name that matches
  nothing is a hard error, never a silently constant comment.
- Passing any template option turns on the comment kind it formats — no separate `--emit-…`
  needed. The reverse does not hold.
- `--enum-layout-style` is a whole-module preset: `detailed` (default) / `explained` (bit
  ranges in words) / `standard` / `inline` / `compact`.
- `swift-section transformer config …  -o comments.json` freezes a command line for reuse via
  `--transformer-config`; it is the same JSON shape RuntimeViewer persists.

## 7. `diff` / `snapshot` / `evolution`

```bash
swift-section diff old/Foo new/Foo                              # change list + verdict
swift-section diff old/Foo new/Foo --interface --format unified # annotated interface
swift-section snapshot /path/Foo --label 26.0 -o foo-26.0.json  # freeze a baseline
swift-section evolution 17.0.json 18.0.json /path/Foo --labels 17.0,18.0,26.0
```

- `--json`, `--summary-only` and `--interface` are mutually exclusive, and `--format` only
  applies with `--interface`.
- `--interface` renders from live models, so **every input must be a binary or cache** —
  snapshot JSON is rejected there, though it is fine for the change-list / lineage reports.
- `evolution` needs ≥ 2 inputs **in version order, oldest first**; `--labels` is comma-separated
  and must have exactly one label per input.
- `--fail-on-breaking` makes a breaking change a nonzero exit — that, not the report text, is
  the CI signal.
- Compare binaries in **similar strip states**. A symbol-rich build against a stripped one
  reports the same protocol requirement as a member swap, because a stripped protocol diffs by
  witness-table slot rather than by symbol.
- **A snapshot does not cross format versions.** The JSON carries a `formatVersion`; any other
  version is rejected with a typed error, and the fix is to regenerate the baseline with the
  current tool. Format 6 (0.21.0 and later) rejects every format-5 baseline: in an image stripped
  of its local symbols the newer tool also records the class members that only their method
  descriptor names (see §9), which an old baseline would report as added wholesale.

## 8. `--resolve-c-module-names` (interface, macOS only)

Turns `__C.NSString` into `Foundation.NSString`. Needs macOS 13+ and an Xcode installation, and
the first run per SDK generates module interfaces through sourcekitd — slow once, cached after.
Attribution against a non-macOS binary is limited (it warns and degrades rather than failing).
`--supplementary-apinotes` only does anything alongside it.

## 9. Reading the output: things that look like bugs and are not

- **`// not exported`** is an export-trie fact, not an access-level claim. A missing entry
  means "not statically callable from outside this image", which is not the same as `internal`.
- **A type member printed `static`** may have been `class` in the source: the four
  descriptor-less `class` spellings are ABI-identical to `static`, so the printer picks the
  spelling that is always legal.
- **`Field offset: unknown (<reason>)`** is the layout engine declining to guess, and the
  reason names what it could not resolve. It is distinct from the flag being off (which emits
  nothing at all).
- **A generic type printed with unresolved fields** is expected when no arguments were
  supplied: an unconstrained `T` has no layout until it is bound. Class-bound parameters and
  parameter metatypes do resolve unspecialized.
- **`pwtslot:` records in a protocol diff** are the fallback view used when requirement symbols
  are stripped — see the strip-state warning in §7.
- **A class's members print in vtable slot order**, not grouped by kind: for the class's own
  members that is the source's declaration order, so an `init` can sit between two methods.
  Only the members that own no slot (`final`, `static`, `@objc dynamic`, an ObjC-inherited
  `init`) follow, grouped by kind.
- **In an image stripped of its local symbols (AppKit in the OS dyld shared cache), a public
  class method may print without `@objc` or `override`.** Its implementation symbol is gone
  (a library-evolution image exports only the dispatch thunk `Tj` and method descriptor `Tq`),
  so the member is rebuilt from the `Tq` symbol — the name and signature are exact, but the
  `@objc` / ObjC-override facts are joined through the implementation's symbol and are
  missing. A vtable slot nothing names (an internal member in a stripped image) is
  left out; `dump` lists it as `sub_…` or `<unnamed vtable slot>`.
- **Enum-layout patterns marked "not resolved offline"** mean only the extra-inhabitant *index*
  is derivable statically; the concrete bytes need the live metadata.
- **`@objc(Name)` above a class** is the name the Objective-C runtime knows it by, and matters
  even when it equals the Swift name (`@objc(NSScrollPocket) class NSScrollPocket`): without it
  the runtime name would be the `_TtC…` mangling. That is also the class name `objc` headers
  and `-[Class selector]` comments use. **`@_objcRuntimeName(Name)`** is the same fact on a
  class with no Objective-C ancestor, where `@objc` would not be legal Swift (mostly the
  standard library) — not a typo.

## 10. Where the details live

The repository is [MachOSwiftSection](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection).

| Need | Read |
|---|---|
| Worked examples of every subcommand and flag | its `README.md`, section "swift-section CLI Tool" |
| How to read an enum-layout comment | `Documentations/SwiftEnumLayout.md` (`_zh` companion) |
| Writing supplementary `.apinotes` for a private framework | `Documentations/SupplementaryTypeMappings.md` |
| The `objc` subcommands in full, including the snapshot / diff / evolution workflow | `Documentations/ObjCCommandLine.md` (`_zh` companion); the traps are in `references/objc.md` beside this file |
| What each flag does, authoritatively | `swift-section <subcommand> --help` (and `swift-section objc <subcommand> --help`) — generated from the code, so it cannot drift |
