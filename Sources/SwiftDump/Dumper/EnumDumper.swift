import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import MemberwiseInit

@MemberwiseInit(.package)
package struct DumperConfiguration {
    package var demangleOptions: DemangleOptions
    package var indentation: Int = 1
    package var displayParentName: Bool = true
}

package struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `enum`: Enum

    private let configuration: DumperConfiguration

    private let machO: MachO

    package init(_ dumped: Enum, using configuration: DumperConfiguration, in machO: MachO) {
        self.enum = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var options: DemangleOptions {
        configuration.demangleOptions
    }

    package var declaration: SemanticString {
        get throws {
            Keyword(.enum)

            Space()

            try name

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
        }
    }

    package var fields: SemanticString {
        get throws {
            for (offset, fieldRecord) in try `enum`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: configuration.indentation)

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
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration

            Space()

            Standard("{")

            try fields

            let interfaceNameString = try interfaceName.string

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

    @SemanticStringBuilder
    private func _name(using options: DemangleOptions) throws -> SemanticString {
        if configuration.displayParentName {
            try MetadataReader.demangleContext(for: .type(.enum(`enum`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .enum, `enum`.descriptor.name(in: machO))
        }
    }
}
