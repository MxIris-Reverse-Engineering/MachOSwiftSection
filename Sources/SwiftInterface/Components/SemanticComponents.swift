import Semantic

// MARK: - Offset Comment

/// An offset comment that outputs a comment when enabled.
struct OffsetComment: SemanticStringComponent {
    let prefix: String

    let offset: Int?

    let emit: Bool

    init(prefix: String, offset: Int?, emit: Bool) {
        self.prefix = prefix
        self.offset = offset
        self.emit = emit
    }

    func buildComponents() -> [AtomicComponent] {
        guard emit, let offset else { return [] }

        return Comment("\(prefix): 0x\(String(offset, radix: 16))").buildComponents()
    }
}

// MARK: - Address Comment

/// An address comment that outputs a member address comment when enabled.
struct AddressComment: SemanticStringComponent {
    let addressString: String?

    let label: String?

    let emit: Bool

    init(addressString: String?, label: String? = nil, emit: Bool) {
        self.addressString = addressString
        self.label = label
        self.emit = emit
    }

    func buildComponents() -> [AtomicComponent] {
        guard emit, let addressString else { return [] }

        if let label {
            return Comment("Address (\(label)): 0x\(addressString)").buildComponents()
        } else {
            return Comment("Address: 0x\(addressString)").buildComponents()
        }
    }
}

// MARK: - VTable Offset Comment

/// A vtable offset comment that outputs a vtable slot offset comment when enabled.
struct VTableOffsetComment: SemanticStringComponent {
    let vtableOffset: Int?

    let label: String?

    let emit: Bool

    let transformer: (@Sendable (Int, String?) -> SemanticString)?

    init(vtableOffset: Int?, label: String? = nil, emit: Bool, transformer: (@Sendable (Int, String?) -> SemanticString)?) {
        self.vtableOffset = vtableOffset
        self.label = label
        self.emit = emit
        self.transformer = transformer
    }

    func buildComponents() -> [AtomicComponent] {
        guard emit, let vtableOffset else { return [] }

        if let transformer {
            return transformer(vtableOffset, label).buildComponents()
        } else if let label {
            return Comment("VTable offset (\(label)): \(vtableOffset)").buildComponents()
        } else {
            return Comment("VTable offset: \(vtableOffset)").buildComponents()
        }
    }
}

// MARK: - Imports Block

/// A block of import statements.
struct ImportsBlock: SemanticStringComponent {
    let modules: [String]

    init(_ modules: [String]) {
        self.modules = modules
    }

    init(_ modules: String...) {
        self.modules = modules
    }

    func buildComponents() -> [AtomicComponent] {
        guard !modules.isEmpty else { return [] }

        var result: [AtomicComponent] = []
        for module in modules {
            result.append(contentsOf: Standard("import \(module)").buildComponents())
            result.append(contentsOf: BreakLine().buildComponents())
        }
        return result
    }
}
