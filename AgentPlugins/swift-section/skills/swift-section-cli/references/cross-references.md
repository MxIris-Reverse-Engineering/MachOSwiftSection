# `refs` and `symbolicate`

Two subcommands that read arm64 machine code rather than metadata: who references a selector,
a symbol, a class, a function, an instance variable or a string — and what an address is. They
work on a whole dyld shared cache (an archived one, another device's, or the running system's,
read from its files) or on a set of standalone Mach-O files read together, without IDA and
without loading anything into a process.

```bash
# Every send of a selector across a whole cache
swift-section refs --selector makeKeyAndOrderFront: \
  --dyld-shared-cache /Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e

# References to a class, only in the images named
swift-section refs --class NSWindow --uses-system-dyld-shared-cache --in-image AppKit --json

# What one function calls, in instruction order
swift-section refs --function 0x1880a1000 --callees --uses-system-dyld-shared-cache

# An app's executable and its frameworks, read together; a fat file needs -a
swift-section refs --symbol _objc_msgSend Foo.app/Contents/MacOS/Foo \
  Foo.app/Contents/Frameworks/Bar.framework/Bar -a arm64e

# What these addresses are
swift-section symbolicate 0x19012345 0x1e1226590 --uses-system-dyld-shared-cache
```

## What a `refs` line says

```
<site>  <image>  <function>+<offset>  <kind>  <route>  <target>
```

- **site** — the referencing instruction's address. **function** — the function it lies in,
  by its symbol, or, where the symbol table names none, by the export trie, the Objective-C
  method lists or the Swift metadata (`-[NSWindow …]`, `…Ma`); its address when nothing names it.
- **kind** — `call`, `tailCall` (a branch out that does not return), or `reference` (an
  address taken: a class object, a type's metadata, a string, an ivar offset).
- **route** — how the code got there: `direct`, `imageStub`, `stubIsland`, `cacheSharedStub`
  (macOS / iOS 27's selector and GOT stubs outside every image), `pointerSlot`,
  `addressMaterialization`, `literalLoad`, `indirect`. A reference that went through a stub is
  as real as a direct one; the route is what to check before trusting it.
- **target** — `send sel:` (`to self`, `to NSWindow` when the receiver is known), a function
  and its image, a class, `ivar Class._name`, a string, `type …`, `indirect` (`at offset …` when the callee was loaded from memory).

A one-line summary goes to stderr: how many references, in how many images, and how many images
were scanned.

## Things that will bite

- **Addresses are unslid**, in and out — the ones IDA, `ipsw` and `dyld_info` show. A cache's
  images share one address space; **standalone files each have their own**, and two dylibs
  linked at 0 overlap. `--function` names the file with `--function-image` when the address is
  ambiguous (the command says so), and `symbolicate` takes `--in-image` for the same reason.
- **A fat file needs `-a`**, as everywhere in this tool. Only arm64 / arm64e slices can be
  analyzed; anything else fails with "holds no arm64 code".
- **`--in-image` narrows where to look, not where the subject is.** `refs --symbol _foo
  --in-image AppKit` finds `_foo` wherever it is defined and lists AppKit's calls to it. It takes
  a path or a file name; a file name can match two images in a macOS cache (the Mac Catalyst
  variant under `/System/iOSSupport`), and both are searched.
- **Only the images that can reference the subject are scanned**: the ones whose
  `__objc_selrefs` hold the selector, that import the symbol or class, or that link the image
  defining a Swift function. `--string` is the exception — any image can hold a literal — so on a
  whole cache, name the images.
- **`--class` on a class no symbol exports** (most private classes in a cache) reads every
  image's class list first; the first such query takes a few seconds longer.
- **`--json`** prints one document whose every address is a hexadecimal string, never a number.
  Its field names are a contract. `--limit` keeps the first references in image and address
  order and sets `isTruncated`.
- **Not reported, by design or not yet**: a call through a vtable, a witness table or any
  register says `indirect` with what the call site shows (the offset of the load, the pointer-
  authentication discriminator) but no callee — never which table it was; a Swift class's stored-property offset variables are not
  reported as ivar references; an app read together with the running system's cache is not
  supported — read the app's files alone, and a call into a system library stays the imported
  symbol it is.
