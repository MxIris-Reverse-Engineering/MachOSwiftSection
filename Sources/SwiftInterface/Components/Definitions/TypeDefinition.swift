import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox
import Dependencies
@_spi(Internal) import MachOSymbols

public final class TypeDefinition: Definition {
    public enum ParentContext {
        case `extension`(ExtensionContext)
        case type(TypeContextWrapper)
        case symbol(Symbol)
    }

    public let type: TypeContextWrapper

    public let typeName: TypeName

    @Mutex
    public weak var parent: TypeDefinition?

    @Mutex
    public var typeChildren: [TypeDefinition] = []

    @Mutex
    public var protocolChildren: [ProtocolDefinition] = []

    @Mutex
    public var parentContext: ParentContext? = nil

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

    public init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeContextWrapper, in machO: MachO) throws {
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
        
//        var methodDescriptorByNode: [Node: MethodDescriptorWrapper] = [:]
//        
//        if case let .class(cls) = type {
//            cls.methodDescriptors
//        }
        
        
        self.allocators = DefinitionBuilder.allocators(for: symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: typeName.name, in: machO))
        self.hasDeallocator = !symbolIndexStore.memberSymbols(of: .deallocator, for: typeName.name, in: machO).isEmpty
        self.variables = DefinitionBuilder.variables(for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: typeName.name, in: machO), fieldNames: fieldNames, isGlobalOrStatic: false)
        self.staticVariables = DefinitionBuilder.variables(for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: true, isStorage: false), .variable(inExtension: false, isStatic: true, isStorage: true), for: typeName.name, in: machO), fieldNames: fieldNames, isGlobalOrStatic: true)

        self.functions = DefinitionBuilder.functions(for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: typeName.name, in: machO), isGlobalOrStatic: false)
        self.staticFunctions = DefinitionBuilder.functions(for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: typeName.name, in: machO), isGlobalOrStatic: true)
        self.subscripts = DefinitionBuilder.subscripts(for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: typeName.name, in: machO), isStatic: false)
        self.staticSubscripts = DefinitionBuilder.subscripts(for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: typeName.name, in: machO), isStatic: true)
    }
}
