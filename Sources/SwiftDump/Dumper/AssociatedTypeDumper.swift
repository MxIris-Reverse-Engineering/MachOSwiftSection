import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities

package struct AssociatedTypeDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    private let associatedType: AssociatedType
    
    private let configuration: DumperConfiguration
    
    private let machO: MachO

    package init(_ dumped: AssociatedType, using configuration: DumperConfiguration, in machO: MachO) {
        self.associatedType = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var options: DemangleOptions {
        configuration.demangleOptions
    }
    
    package var declaration: SemanticString {
        get throws {
            Keyword(.extension)

            Space()

            try typeName

            Standard(":")

            Space()

            try protocolName
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration
            
            Space()

            Standard("{")

            for (offset, record) in associatedType.records.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                Keyword(.typealias)

                Space()

                try TypeDeclaration(kind: .other, record.name(in: machO))

                Space()

                Standard("=")

                Space()

                try MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machO), in: machO).printSemantic(using: options)

                if offset.isEnd {
                    BreakLine()
                }
            }

            Standard("}")
        }
    }

    package var typeName: SemanticString {
        get throws {
            try MetadataReader.demangleSymbol(for: associatedType.conformingTypeName, in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    package var protocolName: SemanticString {
        get throws {
            try MetadataReader.demangleSymbol(for: associatedType.protocolTypeName, in: machO).printSemantic(using: options)
        }
    }
}
