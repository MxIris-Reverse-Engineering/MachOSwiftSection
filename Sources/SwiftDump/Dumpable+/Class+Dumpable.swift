import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import Demangle
import MachOFoundation

extension Class: Dumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.class)

        Space()

        try MetadataReader.demangleContext(for: .type(.class(descriptor)), in: machOFile).printSemantic(using: options).replacing(from: .typeName, to: .typeDeclaration)

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


            dumpMethodKeyword(for: descriptor)

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else if !descriptor.implementation.isNull {
                FunctionOrMethodDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
            } else {
                Error("Symbol not found")
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, descriptor) in methodOverrideDescriptors.offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            Keyword(.override)

            Space()

            if let methodDescriptor = try descriptor.methodDescriptor(in: machOFile) {
                switch methodDescriptor {
                case .symbol(let symbol):
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                case .element(let element):
                    dumpMethodKeyword(for: element)
                }
            } else {
                if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                    try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
                } else if !descriptor.implementation.isNull {
                    FunctionOrMethodDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
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
                FunctionOrMethodDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
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
    private func dumpMethodKeyword(for descriptor: MethodDescriptor) -> SemanticString {
        InlineComment("[\(descriptor.flags.kind)]")

        Space()
        
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
    
}

extension Node {
    var hasWeakNode: Bool {
        first { $0.kind == .weak } != nil
    }
}

extension Dumpable {
    func addressString<MachO: MachORepresentableWithCache>(of fileOffset: Int, in machOFile: MachO) -> String {
        if let cache = machOFile.cache {
            return .init(cache.mainCacheHeader.sharedRegionStart.cast() + fileOffset, radix: 16, uppercase: true)
        } else {
            return .init(0x100000000 + fileOffset, radix: 16, uppercase: true)
        }
    }
}

extension String {
    var insertSubFunctionPrefix: String {
        "sub_" + self
    }
}
