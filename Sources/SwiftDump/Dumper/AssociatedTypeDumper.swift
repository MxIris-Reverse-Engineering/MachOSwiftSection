import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import SwiftInspection

package struct AssociatedTypeDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    private let associatedType: AssociatedType

    private let configuration: DumperConfiguration

    private let machO: MachO

    package init(_ dumped: AssociatedType, using configuration: DumperConfiguration, in machO: MachO) {
        self.associatedType = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.extension)

            Space()

            try await typeName

            Standard(":")

            Space()

            try await protocolName
        }
    }

    @SemanticStringBuilder
    package var records: SemanticString {
        get async throws {
            for (offset, record) in associatedType.records.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                Keyword(.typealias)

                Space()

                try TypeDeclaration(kind: .other, record.name(in: machO))

                Space()

                Standard("=")

                Space()

                try await demangleResolver.resolve(for: MetadataReader.demangleType(for: record.substitutedTypeName(in: machO), in: machO))

                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await records

            Standard("}")
        }
    }

    package var typeName: SemanticString {
        get async throws {
            try await demangleResolver.resolve(for: MetadataReader.demangleType(for: associatedType.conformingTypeName, in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    package var protocolName: SemanticString {
        get async throws {
            try await demangleResolver.resolve(for: MetadataReader.demangleType(for: associatedType.protocolTypeName, in: machO))
        }
    }
}
