import Semantic
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import Utilities

private struct ClassDumper<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>: NamedDumper {
    let `class`: Class
    let options: DemangleOptions
    let machO: MachO

    var body: SemanticString {
        get throws {
            if `class`.descriptor.isActor {
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            let name = try self.name

            let interfaceNameString = try interfaceName.string

            name

            if let genericContext = `class`.genericContext {
                if genericContext.currentParameters.count > 0 {
                    try genericContext.dumpGenericParameters(in: machO)
                }
            }

            if let superclassMangledName = try `class`.descriptor.superclassTypeMangledName(in: machO) {
                Standard(":")
                Space()
                try MetadataReader.demangleType(for: superclassMangledName, in: machO).printSemantic(using: options)
            } else if let resilientSuperclass = `class`.resilientSuperclass, let kind = `class`.descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.dumpSuperclass(using: options, for: kind, in: machO) {
                Standard(":")
                Space()
                superclass
            }

            if let genericContext = `class`.genericContext, genericContext.currentRequirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(using: options, in: machO)
            }
            Space()

            Standard("{")

            for (offset, fieldRecord) in try `class`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

                let fieldName = try fieldRecord.fieldName(in: machO)

                if fieldRecord.flags.contains(.isVariadic) {
                    if demangledTypeNode.hasWeakNode {
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

                demangledTypeNode.printSemantic(using: options.union(.removeWeakPrefix))

                if offset.isEnd {
                    BreakLine()
                }
            }

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

                if let methodDescriptor = try descriptor.methodDescriptor(in: machO) {
                    switch methodDescriptor {
                    case .symbol(let symbol):
                        Keyword(.override)
                        Space()
                        try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
                    case .element(let element):
                        dumpMethodKind(for: element)
                        Keyword(.override)
                        Space()
                        dumpMethodKeyword(for: element)
                        try? dumpMethodDeclaration(for: element)
                    }
                } else {
                    Keyword(.override)
                    Space()
                    if let symbol = try? descriptor.implementationSymbol(in: machO) {
                        try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
                    } else if !descriptor.implementation.isNull {
                        FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                    } else {
                        Error("Symbol not found")
                    }
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
                    try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            Standard("}")
        }
    }

    var name: SemanticString {
        get throws {
            try _name(using: options)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .interface)
        }
    }

    private func _name(using options: DemangleOptions) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.class(`class`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    private func dumpMethodKind(for descriptor: MethodDescriptor) -> SemanticString {
        InlineComment("[\(descriptor.flags.kind)]")

        Space()
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
            try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }
}

extension Class: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(class: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ClassDumper(class: self, options: options, machO: machO).body
    }
}
