// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// Three async function pointer records, picked by `…Tu` symbol: a
// top-level async function, an async class method a vtable slot
// points at, and a distributed thunk (the largest async context in
// the fixture).

enum AsyncFunctionPointerBaseline {
    static let registeredTestMethodNames: Set<String> = ["functionAddress", "layout", "offset"]

    struct Entry {
        let offset: Int
        let functionOffset: Int?
        let expectedContextSize: UInt32
    }

    static let globalFunction = Entry(
    offset: 0x3d918,
    functionOffset: 0x28d60,
    expectedContextSize: 16
    )

    static let vtableMethod = Entry(
    offset: 0x3fa50,
    functionOffset: 0x9cd0,
    expectedContextSize: 16
    )

    static let distributedThunk = Entry(
    offset: 0x3af58,
    functionOffset: 0xf004,
    expectedContextSize: 208
    )
}
