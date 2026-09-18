import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
@_spi(Internals) import SwiftInspection
import Demangling
import OrderedCollections
import SwiftDeclarationRendering

package struct AssociatedTypeDumper<MachO: MachOFieldLayoutRenderable>: ConformedDumper {
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
                // The dump's spelling of a reference that could not be
                // expanded names the owner declaration in a trailing comment;
                // the interface's, the indexer's default, does not.
                let resolution = try SymbolicDemangler.demangleType(for: witnessMangledName, in: machO)
                    .resolveOpaqueTypeCollectingConditionalCandidates(witnessMangledName: witnessMangledName, conformingTypeName: dumped.conformingTypeName, in: machO, spelling: .annotated)

                // Every branch of an availability-conditional witness, above
                // the `typealias` that shows the newest platform's one — and
                // every hop of a projected member, above the answer.
                let commentLines = try await resolution.conditionalWitnessCommentLines(associatedTypeName: recordName, resolvedBy: demangleResolver)
                    + resolution.projectedMemberCommentLines(associatedTypeName: recordName, resolvedBy: demangleResolver)
                for line in commentLines {
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
