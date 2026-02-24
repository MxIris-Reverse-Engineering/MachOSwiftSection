import MCP

/// All MCP tool definitions for swift-section.
enum ToolDefinitions {
    static let allTools: [Tool] = [
        openBinary,
        openDyldCacheImage,
        listTypes,
        dumpType,
        listProtocols,
        dumpProtocol,
        listConformances,
        generateInterface,
        demangleSymbol,
    ]

    // MARK: - Binary Loading

    static let openBinary = Tool(
        name: "open_binary",
        description: "Load a Mach-O binary file for analysis. Must be called before other analysis tools.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "path": .object([
                    "type": "string",
                    "description": "Absolute path to the Mach-O binary file",
                ]),
                "architecture": .object([
                    "type": "string",
                    "description": "Architecture to select for fat binaries (arm64, arm64e, x86_64). Defaults to the current system architecture.",
                    "enum": .array([.string("arm64"), .string("arm64e"), .string("x86_64")]),
                ]),
            ]),
            "required": .array([.string("path")]),
        ]),
        annotations: .init(
            title: "Open Mach-O Binary",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    static let openDyldCacheImage = Tool(
        name: "open_dyld_cache_image",
        description: "Load an image from the dyld shared cache for analysis. Provide either imageName or imagePath. If no cachePath is given, the system dyld shared cache is used.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "imageName": .object([
                    "type": "string",
                    "description": "Name of the image in the dyld shared cache (e.g. 'Foundation')",
                ]),
                "imagePath": .object([
                    "type": "string",
                    "description": "Full path of the image in the dyld shared cache (e.g. '/usr/lib/swift/libswiftCore.dylib')",
                ]),
                "cachePath": .object([
                    "type": "string",
                    "description": "Path to a custom dyld shared cache file. If omitted, uses the system cache.",
                ]),
            ]),
        ]),
        annotations: .init(
            title: "Open dyld Shared Cache Image",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    // MARK: - Type Analysis

    static let listTypes = Tool(
        name: "list_types",
        description: "List all Swift types (structs, enums, classes) in the loaded binary. Returns type names grouped by kind.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "filter": .object([
                    "type": "string",
                    "description": "Filter by type kind",
                    "enum": .array([.string("struct"), .string("enum"), .string("class"), .string("all")]),
                ]),
            ]),
        ]),
        annotations: .init(
            title: "List Swift Types",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    static let dumpType = Tool(
        name: "dump_type",
        description: "Dump detailed information about a specific Swift type, including fields, methods, and conformances.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "name": .object([
                    "type": "string",
                    "description": "Name of the type to dump (can be a partial match)",
                ]),
                "includeFieldOffsets": .object([
                    "type": "boolean",
                    "description": "Include field offset comments in the output",
                ]),
            ]),
            "required": .array([.string("name")]),
        ]),
        annotations: .init(
            title: "Dump Swift Type",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    // MARK: - Protocol Analysis

    static let listProtocols = Tool(
        name: "list_protocols",
        description: "List all Swift protocols defined in the loaded binary.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ]),
        annotations: .init(
            title: "List Swift Protocols",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    static let dumpProtocol = Tool(
        name: "dump_protocol",
        description: "Dump detailed information about a specific Swift protocol, including requirements and associated types.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "name": .object([
                    "type": "string",
                    "description": "Name of the protocol to dump (can be a partial match)",
                ]),
            ]),
            "required": .array([.string("name")]),
        ]),
        annotations: .init(
            title: "Dump Swift Protocol",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    // MARK: - Conformance Analysis

    static let listConformances = Tool(
        name: "list_conformances",
        description: "List all protocol conformances in the loaded binary. Can filter by protocol name or type name.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "protocolName": .object([
                    "type": "string",
                    "description": "Filter conformances by protocol name (partial match)",
                ]),
                "typeName": .object([
                    "type": "string",
                    "description": "Filter conformances by conforming type name (partial match)",
                ]),
            ]),
        ]),
        annotations: .init(
            title: "List Protocol Conformances",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )

    // MARK: - Interface Generation

    static let generateInterface = Tool(
        name: "generate_interface",
        description: "Generate a Swift interface file from the loaded binary, similar to .swiftinterface files. This can be a long-running operation for large binaries.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "showCImportedTypes": .object([
                    "type": "boolean",
                    "description": "Include C-imported types in the output",
                ]),
            ]),
        ]),
        annotations: .init(
            title: "Generate Swift Interface",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: false,
            openWorldHint: false
        )
    )

    // MARK: - Symbol Demangling

    static let demangleSymbol = Tool(
        name: "demangle_symbol",
        description: "Demangle a Swift mangled symbol name into a human-readable string.",
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "symbol": .object([
                    "type": "string",
                    "description": "The mangled Swift symbol (e.g. '$s4main5HelloV')",
                ]),
                "isType": .object([
                    "type": "boolean",
                    "description": "If true, parse as a type mangling (no prefix required). Defaults to false.",
                ]),
            ]),
            "required": .array([.string("symbol")]),
        ]),
        annotations: .init(
            title: "Demangle Swift Symbol",
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )
    )
}
