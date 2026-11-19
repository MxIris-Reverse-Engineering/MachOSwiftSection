// Self-contained wrapper around libswiftDemangle.dylib.
// Uses dlopen/dlsym at runtime — no Swift or LLVM headers required.

#include "CDemangleTree.h"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <string>

// ---------------------------------------------------------------------------
// ABI-compatible declarations (matches the compiled layout in the dylib)
// ---------------------------------------------------------------------------

// llvm::StringRef is { const char*, size_t } — 16 bytes, passed in 2 regs.
struct StringRef {
    const char *data;
    size_t length;
};

// Opaque node pointer.
struct Node;

// swift::Demangle::Context is 8 bytes (a single NodeFactory pointer).
struct alignas(8) Context {
    uint64_t _storage;
};

// ---------------------------------------------------------------------------
// Function pointer types
// ---------------------------------------------------------------------------

using CtxCtorFn  = void (*)(Context *);
using CtxDtorFn  = void (*)(Context *);
using DemangleFn = Node *(*)(Context *, StringRef);
using TreeStrFn  = std::string (*)(Node *);

// ---------------------------------------------------------------------------
// Lazy symbol resolution
// ---------------------------------------------------------------------------

static void       *sLib      = nullptr;
static CtxCtorFn   sCtxCtor  = nullptr;
static CtxDtorFn   sCtxDtor  = nullptr;
static DemangleFn  sDemangle = nullptr;
static TreeStrFn   sTreeStr  = nullptr;

static bool ensureLoaded() {
    if (sLib) return true;

    // Try well-known Xcode toolchain path, then fall back to DYLD search.
    static const char *paths[] = {
        "/Applications/Xcode.app/Contents/Developer/Toolchains/"
        "XcodeDefault.xctoolchain/usr/lib/libswiftDemangle.dylib",
        "libswiftDemangle.dylib",
        nullptr
    };

    for (int i = 0; paths[i]; ++i) {
        sLib = dlopen(paths[i], RTLD_LAZY);
        if (sLib) break;
    }
    if (!sLib) return false;

    // C++ mangled symbol names (stable across Swift 5.x / 6.x releases).
    sCtxCtor  = (CtxCtorFn)  dlsym(sLib, "_ZN5swift8Demangle7ContextC1Ev");
    sCtxDtor  = (CtxDtorFn)  dlsym(sLib, "_ZN5swift8Demangle7ContextD1Ev");
    sDemangle = (DemangleFn) dlsym(sLib,
        "_ZN5swift8Demangle7Context20demangleSymbolAsNodeEN4llvm9StringRefE");
    sTreeStr  = (TreeStrFn)  dlsym(sLib,
        "_ZN5swift8Demangle19getNodeTreeAsStringEPNS0_4NodeE");

    return sCtxCtor && sCtxDtor && sDemangle && sTreeStr;
}

// ---------------------------------------------------------------------------
// Public C API
// ---------------------------------------------------------------------------

char *swift_demangle_getNodeTreeAsString(const char *mangledName) {
    if (!mangledName || !ensureLoaded())
        return nullptr;

    Context ctx;
    sCtxCtor(&ctx);

    StringRef ref = { mangledName, strlen(mangledName) };
    Node *node = sDemangle(&ctx, ref);

    char *result = nullptr;
    if (node) {
        std::string tree = sTreeStr(node);
        result = static_cast<char *>(malloc(tree.size() + 1));
        memcpy(result, tree.c_str(), tree.size() + 1);
    }

    sCtxDtor(&ctx);
    return result;
}
