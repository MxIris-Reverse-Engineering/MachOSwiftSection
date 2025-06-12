import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import Demangle

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

//            "\(fieldName.stripLazyPrefix): \(demangledTypeNameString.stripWeakPrefix)"
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

            InlineComment("[\(descriptor.flags.kind)]")

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

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else if !descriptor.implementation.isNull {
                Standard("\(descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)))")
            } else {
                InlineComment("Symbol not found")
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

            if let symbol = try? descriptor.implementationSymbol(in: machOFile) {
                try MetadataReader.demangleSymbol(for: symbol, in: machOFile).printSemantic(using: options)
            } else {
                InlineComment("Symbol not found")
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
            } else {
                InlineComment("Symbol not found")
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        Standard("}")
    }
}

extension Node {
    var hasWeakNode: Bool {
        first { $0.kind == .weak } != nil
    }
}

