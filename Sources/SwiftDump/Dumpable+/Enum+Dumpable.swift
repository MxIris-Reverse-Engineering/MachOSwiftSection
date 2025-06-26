import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols

extension Enum: NamedDumpable {
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.enum(descriptor)), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.enum)

        Space()

        try dumpName(using: options, in: machOFile)

        if let genericContext {
            try genericContext.dumpGenericParameters(in: machOFile)
            if genericContext.requirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(using: options, in: machOFile)
            }
        }
        Space()
        Standard("{")
        for (offset, fieldRecord) in try descriptor.fieldDescriptor(in: machOFile).records(in: machOFile).offsetEnumerated() {
            BreakLine()

            Indent(level: 1)

            if fieldRecord.flags.contains(.isIndirectCase) {
                Keyword(.indirect)
                Space()
                Keyword(.case)
                Space()
            } else {
                Keyword(.case)
                Space()
            }

            try MemberDeclaration("\(fieldRecord.fieldName(in: machOFile))")

            let mangledName = try fieldRecord.mangledTypeName(in: machOFile)

            if !mangledName.isEmpty {
                let demangledName = try MetadataReader.demangleType(for: mangledName, in: machOFile).printSemantic(using: options)
                let demangledNameString = demangledName.string
                if demangledNameString.hasPrefix("("), demangledNameString.hasSuffix(")") {
                    demangledName
                } else {
                    Standard("(")
                    demangledName
                    Standard(")")
                }
            }

            if offset.isEnd {
                BreakLine()
            }
        }

        for kind in SymbolIndexStore.IndexKind.SubKind.allCases.map({ SymbolIndexStore.IndexKind.enum($0) }) {
            for (offset, function) in SymbolIndexStore.shared.symbols(of: kind, for: try dumpName(using: .interface, in: machOFile).string, in: machOFile).offsetEnumerated() {
                
                if offset.isStart {
                    BreakLine()
                    
                    Indent(level: 1)
                    
                    switch kind {
                    case .enum(let subKind):
                        switch subKind {
                        case .function:
                            InlineComment("Functions")
                        case .functionInExtension:
                            InlineComment("Functions In Extension")
                        case .staticFunction:
                            InlineComment("Static Functions")
                        case .staticFunctionInExtension:
                            InlineComment("Static Functions In Extension")
                        case .variable:
                            InlineComment("Variables")
                        case .variableInExtension:
                            InlineComment("Variables In Extension")
                        case .staticVariable:
                            InlineComment("Static Variables")
                        case .staticVariableInExtension:
                            InlineComment("Static Variables In Extension")
                        }
                    default:
                        fatalError("unreachable")
                    }
                }
                
                BreakLine()
                
                Indent(level: 1)
                
                try MetadataReader.demangleSymbol(for: function, in: machOFile).printSemantic(using: options)
                
                if offset.isEnd {
                    BreakLine()
                }
            }
        }
        
        
        Standard("}")
    }
}
