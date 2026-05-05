// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework
//
// ObjCResilientClassStubInfo is the trailing-object record on a
// class whose metadata strategy is Resilient/Singleton (i.e. the
// metadata requires runtime relocation/initialization). The
// Suite drives `ObjCResilientStubFixtures.ResilientObjCStubChild`
// (parent `SymbolTestsHelper.Object`, cross-module) and asserts
// cross-reader agreement on the record offset and the stub
// reference's relative-offset scalar.

enum ObjCResilientClassStubInfoBaseline {
    static let registeredTestMethodNames: Set<String> = ["layout", "offset"]

    struct Entry {
        let sourceClassOffset: Int
        let offset: Int
        let layoutStubRelativeOffset: Int32
    }

    static let resilientObjCStubChild = Entry(
        sourceClassOffset: 0x35da4,
        offset: 0x35e10,
        layoutStubRelativeOffset: 115880
    )
}
