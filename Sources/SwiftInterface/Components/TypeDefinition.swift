import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

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
    var fields: [TypeFieldDefinition] = []

    @Mutex
    var variables: [VariableDefinition] = []

    @Mutex
    var functions: [FunctionDefinition] = []

    @Mutex
    var staticVariables: [VariableDefinition] = []

    @Mutex
    var staticFunctions: [FunctionDefinition] = []

    @Mutex
    var allocators: [FunctionDefinition] = []

    @Mutex
    var hasDeallocator: Bool = false

    var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty || hasDeallocator
    }

    init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeWrapper, in machO: MachO) throws {
        self.type = type
        let typeName = try type.typeName(in: machO)
        self.typeName = typeName
        var fields: [TypeFieldDefinition] = []
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
            let field = TypeFieldDefinition(node: node, name: name.stripLazyPrefix, isLazy: isLazy, isWeak: isWeak, isVar: isVar, isIndirectCase: isIndirectCase)
            fields.append(field)
        }

        self.fields = fields

        let fieldNames = Set(fields.map(\.name))

        self.variables = DefinitionBuilder.variables(for: SymbolIndexStore.shared.memberSymbols(of: .variable, for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames, isStatic: false)
        self.staticVariables = DefinitionBuilder.variables(for: SymbolIndexStore.shared.memberSymbols(of: .staticVariable, for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames, isStatic: true)

        self.functions = DefinitionBuilder.functions(for: SymbolIndexStore.shared.memberSymbols(of: .function, for: typeName.name, in: machO).map(\.demangledNode), isStatic: false)
        self.staticFunctions = DefinitionBuilder.functions(for: SymbolIndexStore.shared.memberSymbols(of: .staticFunction, for: typeName.name, in: machO).map(\.demangledNode), isStatic: true)
        self.allocators = DefinitionBuilder.allocators(for: SymbolIndexStore.shared.memberSymbols(of: .allocator, for: typeName.name, in: machO).map(\.demangledNode))
        self.hasDeallocator = !SymbolIndexStore.shared.memberSymbols(of: .deallocator, for: typeName.name, in: machO).isEmpty
    }
}
