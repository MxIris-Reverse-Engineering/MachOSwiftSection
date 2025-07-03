import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOSymbols
import Utilities

private struct EnumDumper<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>: NamedDumper {
    let `enum`: Enum
    let options: DemangleOptions
    let machO: MachO

    var body: SemanticString {
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

            for kind in SymbolIndexStore.IndexKind.allCases {
                for (offset, function) in SymbolIndexStore.shared.symbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
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
        try MetadataReader.demangleContext(for: .type(.enum(`enum`.descriptor)), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }
}

extension Enum: NamedDumpable {
    public func dumpName<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try EnumDumper(enum: self, options: options, machO: machO).name
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try EnumDumper(enum: self, options: options, machO: machO).body
    }
}
