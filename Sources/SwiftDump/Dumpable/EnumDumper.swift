import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

package struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache>: NamedDumper {
    let `enum`: Enum
    let options: DemangleOptions
    let machO: MachO

    package var body: SemanticString {
        get throws {
            Keyword(.enum)

            Space()

            let name = try self.name

            let interfaceNameString = try interfaceName.string

            name

            if let genericContext = `enum`.genericContext {
                if genericContext.currentParameters.count > 0 {
                    try genericContext.dumpGenericParameters(in: machO)
                }
                if genericContext.currentRequirements.count > 0 {
                    Space()
                    Keyword(.where)
                    Space()
                    try genericContext.dumpGenericRequirements(using: options, in: machO)
                }
            }
            Space()
            Standard("{")
            for (offset, fieldRecord) in try `enum`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
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

                try MemberDeclaration("\(fieldRecord.fieldName(in: machO))")

                let mangledName = try fieldRecord.mangledTypeName(in: machO)

                if !mangledName.isEmpty {
                    let demangledName = try MetadataReader.demangleType(for: mangledName, in: machO).printSemantic(using: options)
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

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, function) in SymbolIndexStore.shared.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try MetadataReader.demangleSymbol(for: function, in: machO)?.printSemantic(using: options)

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
            try _name(using: options)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .interface)
        }
    }

    private func _name(using options: DemangleOptions) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .type(.enum(`enum`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }
}
