import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox
import Dependencies

final class TypeDefinition: Definition {
    let type: TypeWrapper

    let typeName: TypeName

    @Mutex
    weak var parent: TypeDefinition?

    @Mutex
    var typeChildren: [TypeDefinition] = []

    @Mutex
    var protocolChildren: [ProtocolDefinition] = []

    @Mutex
    var extensionContext: ExtensionContext? = nil

    @Mutex
    var extensions: [ExtensionDefinition] = []

    @Mutex
    var fields: [FieldDefinition] = []

    @Mutex
    var variables: [VariableDefinition] = []

    @Mutex
    var functions: [FunctionDefinition] = []

    @Mutex
    var subscripts: [SubscriptDefinition] = []
    
    @Mutex
    var staticVariables: [VariableDefinition] = []

    @Mutex
    var staticFunctions: [FunctionDefinition] = []

    @Mutex
    var staticSubscripts: [SubscriptDefinition] = []
    
    @Mutex
    var allocators: [FunctionDefinition] = []

    @Mutex
    var constructors: [FunctionDefinition] = []
    
    @Mutex
    var hasDeallocator: Bool = false

    @Mutex
    var hasDestructor: Bool = false
    
    var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty ||
        !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || hasDeallocator || hasDestructor
    }

    init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeWrapper, in machO: MachO) throws {
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
