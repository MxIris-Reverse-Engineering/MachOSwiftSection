import Semantic
import Demangle
import MachOKit
import MachOSwiftSection
import Utilities
import Dependencies

package struct ClassDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `class`: Class

    private let configuration: DumperConfiguration

    private let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore
    
    package init(_ dumped: Class, using configuration: DumperConfiguration, in machO: MachO) {
        self.class = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get throws {
            if `class`.descriptor.isActor {
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            try name

            if let genericContext = `class`.genericContext {
                try genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO) {
                    try superclass
                }
            } else {
                try superclass
            }
        }
    }

    @SemanticStringBuilder
    package var superclass: SemanticString {
        get throws {
            if let superclassMangledName = try `class`.descriptor.superclassTypeMangledName(in: machO) {
                Standard(":")
                Space()
                try demangleResolver.resolve(for: MetadataReader.demangleType(for: superclassMangledName, in: machO))
            } else if let resilientSuperclass = `class`.resilientSuperclass, let kind = `class`.descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.dumpSuperclass(resolver: demangleResolver, for: kind, in: machO) {
                Standard(":")
                Space()
                superclass
            }
        }
    }
    
    
    package var fields: SemanticString {
        get throws {
            for (offset, fieldRecord) in try `class`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: configuration.indentation)

                let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

                let fieldName = try fieldRecord.fieldName(in: machO)

                if fieldRecord.flags.contains(.isVariadic) {
                    if demangledTypeNode.contains(.weak) {
                        Keyword(.weak)
                        Space()
                        Keyword(.var)
                        Space()
                    } else if fieldName.hasLazyPrefix {
                        Keyword(.lazy)
                        Space()
                        Keyword(.var)
                        Space()
                    } else {
                        Keyword(.var)
                        Space()
                    }
                } else {
                    Keyword(.let)
                    Space()
                }

                MemberDeclaration(fieldName.stripLazyPrefix)

                Standard(":")

                Space()

                try demangleResolver.modify {
                    if case .options(let demangleOptions) = $0 {
                        return .options(demangleOptions.union(.removeWeakPrefix))
                    } else {
                        return $0
                    }
                }
                .resolve(for: demangledTypeNode)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration

            Space()

            Standard("{")

            try fields

            for (offset, descriptor) in `class`.methodDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                dumpMethodKind(for: descriptor)

                dumpMethodKeyword(for: descriptor)

                try dumpMethodDeclaration(for: descriptor)

                if offset.isEnd {
                    BreakLine()
                }
            }

            for (offset, descriptor) in `class`.methodOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)
                
                let methodDescriptor = try descriptor.methodDescriptor(in: machO)
                
                if let symbol = try? descriptor.implementationSymbol(in: machO) {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
                } else if !descriptor.implementation.isNull {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                } else if let methodDescriptor {
                    switch methodDescriptor {
                    case .symbol(let symbol):
                        Keyword(.override)
                        Space()
                        try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
                    case .element(let element):
                        dumpMethodKind(for: element)
                        Keyword(.override)
                        Space()
                        dumpMethodKeyword(for: element)
                        try? dumpMethodDeclaration(for: element)
                    }
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            for (offset, descriptor) in `class`.methodDefaultOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                Keyword(.override)

                Space()

                if let symbol = try? descriptor.implementationSymbol(in: machO) {
                    try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            let interfaceNameString = try interfaceName.string

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.methodDescriptorMemberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment("[Method] " + kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            Standard("}")
        }
    }

    package var name: SemanticString {
        get throws {
            try _name(using: demangleResolver)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) throws -> SemanticString {
        if configuration.displayParentName {
            try resolver.resolve(for: MetadataReader.demangleContext(for: .type(.class(`class`.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .class, `class`.descriptor.name(in: machO))
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKind(for descriptor: MethodDescriptor?) -> SemanticString? {
        if let descriptor {
            InlineComment("[\(descriptor.flags.kind)]")

            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKeyword(for descriptor: MethodDescriptor) -> SemanticString {
        if !descriptor.flags.isInstance, descriptor.flags.kind != .`init` {
            Keyword(.static)
            Space()
        }

        if descriptor.flags.isDynamic {
            Keyword(.dynamic)
            Space()
        }

        if descriptor.flags.kind == .method {
            Keyword(.func)
            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodDeclaration(for descriptor: MethodDescriptor) throws -> SemanticString {
        if let symbol = try? descriptor.implementationSymbol(in: machO) {
            try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }
}
