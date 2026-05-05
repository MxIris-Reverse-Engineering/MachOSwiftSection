// AUTO-GENERATED — DO NOT EDIT.
// Regenerate via: Scripts/regen-baselines.sh
// Source fixture: SymbolTestsCore.framework

enum MethodDescriptorKindBaseline {
    static let registeredTestMethodNames: Set<String> = ["description"]

    struct Entry {
        let rawValue: UInt8
        let description: String
    }

    static let method = Entry(rawValue: 0x0, description: "Method")
    static let `init` = Entry(rawValue: 0x1, description: " Init ")
    static let getter = Entry(rawValue: 0x2, description: "Getter")
    static let setter = Entry(rawValue: 0x3, description: "Setter")
    static let modifyCoroutine = Entry(rawValue: 0x4, description: "Modify")
    static let readCoroutine = Entry(rawValue: 0x5, description: " Read ")
}
