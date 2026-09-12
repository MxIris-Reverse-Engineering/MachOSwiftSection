import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
@_spi(Internals) import SwiftInspection
import Demangling
import OrderedCollections
import SwiftDeclarationRendering

package struct AssociatedTypeDumper<MachO: FieldLayoutRenderable>: ConformedDumper {
    package let dumped: AssociatedType

    package let configuration: DumperConfiguration

    package let machO: MachO

    package init(_ dumped: AssociatedType, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
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

            let typeName = try await typeName

            typeName

            Standard(":")

            Space()

            try await protocolName
        }
    }

    @SemanticStringBuilder
    package var records: SemanticString {
        get async throws {
            for (offset, record) in dumped.records.offsetEnumerated() {
                let recordName = try record.name(in: machO)
                let witnessMangledName = try record.substitutedTypeName(in: machO)
                let resolution = try SymbolicDemangler.demangleType(for: witnessMangledName, in: machO)
                    .resolveOpaqueTypeCollectingConditionalCandidates(witnessMangledName: witnessMangledName, conformingTypeName: dumped.conformingTypeName, in: machO)

                // Every branch of an availability-conditional witness, above
                // the `typealias` that shows the newest platform's one.
                for line in try await resolution.conditionalWitnessCommentLines(associatedTypeName: recordName, resolvedBy: demangleResolver) {
                    BreakLine()

                    Indent(level: 1)

                    Comment(line)
                }

                BreakLine()

                Indent(level: 1)

                Keyword(.typealias)

                Space()

                TypeDeclaration(kind: .other, recordName)

                Space()

                Standard("=")

                Space()

                try await demangleResolver.resolve(for: resolution.node)

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
            try await demangleResolver.resolve(for: SymbolicDemangler.demangleType(for: dumped.conformingTypeName, in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    package var protocolName: SemanticString {
        get async throws {
            try await demangleResolver.resolve(for: SymbolicDemangler.demangleType(for: dumped.protocolTypeName, in: machO))
        }
    }
}
