import Semantic
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection

extension Class: NamedDumpable {
    
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.class(descriptor)), in: machOFile).printSemantic(using: options)
    }
    
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.class)

        Space()

        try dumpName(using: options, in: machOFile).replacing(from: .typeName, to: .typeDeclaration)

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
        }

        if let superclassMangledName = try descriptor.superclassTypeMangledName(in: machOFile) {
            Standard(":")
            Space()
            try MetadataReader.demangleType(for: superclassMangledName, in: machOFile).printSemantic(using: options)
        } else if let resilientSuperclass, let kind = descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.dumpSuperclass(using: options, for: kind, in: machOFile) {
            Standard(":")
            Space()
            TypeName(superclass)
        }

        if let genericContext, genericContext.requirements.count > 0 {
            Space()
            Keyword(.where)
            Space()
            try genericContext.dumpGenericRequirements(using: options, in: machOFile)
        }
        Space()

        Standard("{")

        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machOFile), in: machOFile)

            let fieldName = try fieldRecord.fieldName(in: machOFile)

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

            demangledTypeNode.printSemantic(using: options.subtracting(.showPrefixAndSuffix))

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            dumpMethodKind(for: descriptor)
            
            dumpMethodKeyword(for: descriptor)

            try dumpMethodDeclaration(for: descriptor, using: options, in: machOFile)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)
            
            if let methodDescriptor = try descriptor.methodDescriptor(in: machOFile) {
                switch methodDescriptor {
                case .symbol(let symbol):
                    Keyword(.override)
                    Space()
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                case .element(let element):
                    dumpMethodKind(for: element)
                    Keyword(.override)
                    Space()
                    dumpMethodKeyword(for: element)
                    try dumpMethodDeclaration(for: element, using: options, in: machOFile)
                }
            } else {
                Keyword(.override)
                Space()
                if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodDefaultOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.override)

            Space()

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else if !descriptor.implementation.isNull {
                FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
            } else {
                Error("Symbol not found")
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
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
    
    @MachOImageGenerator
    @SemanticStringBuilder
    private func dumpMethodDeclaration(for descriptor: MethodDescriptor, using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
            try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }
}

extension Node {
    var hasWeakNode: Bool {
        first { $0.kind == .weak } != nil
    }
}


extension String {
    var insertSubFunctionPrefix: String {
        "sub_" + self
    }
}
