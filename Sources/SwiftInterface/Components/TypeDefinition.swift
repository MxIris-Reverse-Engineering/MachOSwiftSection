import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox
import Dependencies

public final class TypeDefinition: Definition {
    public let type: TypeWrapper

    public let typeName: TypeName

    @Mutex
    public weak var parent: TypeDefinition?

    @Mutex
    public var typeChildren: [TypeDefinition] = []

    @Mutex
    public var protocolChildren: [ProtocolDefinition] = []

    @Mutex
    public var extensionContext: ExtensionContext? = nil

    @Mutex
    public var extensions: [ExtensionDefinition] = []

    @Mutex
    public var fields: [FieldDefinition] = []

    @Mutex
    public var variables: [VariableDefinition] = []

    @Mutex
    public var functions: [FunctionDefinition] = []

    @Mutex
    public var subscripts: [SubscriptDefinition] = []
    
    @Mutex
    public var staticVariables: [VariableDefinition] = []

    @Mutex
    public var staticFunctions: [FunctionDefinition] = []

    @Mutex
    public var staticSubscripts: [SubscriptDefinition] = []
    
    @Mutex
    public var allocators: [FunctionDefinition] = []

    @Mutex
    public var constructors: [FunctionDefinition] = []
    
    @Mutex
    public var hasDeallocator: Bool = false

    @Mutex
    public var hasDestructor: Bool = false
    
    public var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty ||
        !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || hasDeallocator || hasDestructor
    }

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeWrapper, in machO: MachO) throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        self.type = type
        let typeName = try type.typeName(in: machO)
        self.typeName = typeName
        var fields: [FieldDefinition] = []
        let typeContextDescriptor = try required(type.contextDescriptorWrapper.typeContextDescriptor)
        let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        for record in records {
            let node = try record.demangledTypeNode(in: machO)
            let name = try record.fieldName(in: machO)
            let isLazy = name.hasLazyPrefix
            let isWeak = node.contains(.weak)
            let isVar = record.flags.contains(.isVariadic)
            let isIndirectCase = record.flags.contains(.isIndirectCase)
            let field = FieldDefinition(node: node, name: name.stripLazyPrefix, isLazy: isLazy, isWeak: isWeak, isVar: isVar, isIndirectCase: isIndirectCase)
            fields.append(field)
        }

        self.fields = fields

        let fieldNames = Set(fields.map(\.name))

        self.allocators = DefinitionBuilder.allocators(for: symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: typeName.name, in: machO).map(\.demangledNode))
        self.hasDeallocator = !symbolIndexStore.memberSymbols(of: .deallocator, for: typeName.name, in: machO).isEmpty
        self.variables = DefinitionBuilder.variables(for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames, isGlobalOrStatic: false)
        self.staticVariables = DefinitionBuilder.variables(for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: true, isStorage: false), .variable(inExtension: false, isStatic: true, isStorage: true), for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames, isGlobalOrStatic: true)

        self.functions = DefinitionBuilder.functions(for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: typeName.name, in: machO).map(\.demangledNode), isGlobalOrStatic: false)
        self.staticFunctions = DefinitionBuilder.functions(for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: typeName.name, in: machO).map(\.demangledNode), isGlobalOrStatic: true)
        self.subscripts = DefinitionBuilder.subscripts(for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: typeName.name, in: machO).map(\.demangledNode), isStatic: false)
        self.staticSubscripts = DefinitionBuilder.subscripts(for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: typeName.name, in: machO).map(\.demangledNode), isStatic: true)
    }
}
