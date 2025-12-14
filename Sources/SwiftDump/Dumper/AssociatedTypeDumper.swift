import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import SwiftInspection
import Demangling

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

            let typeName = try await typeName

            typeName

            if typeName.string == "SwiftUI.FeedbackGenerator" {
                print(typeName.string)
            }

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

                try await demangleResolver.resolve(for: MetadataReader.demangleType(for: record.substitutedTypeName(in: machO), in: machO).resolveOpaqueType(in: machO))

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

extension Node {
    private final class OpaqueTypeNodeRewriter<MachO: MachOSwiftSectionRepresentableWithCache>: Node.Rewriter {
        let machO: MachO

        init(machO: MachO) {
            self.machO = machO
        }

        override func visit(_ node: Node) -> Node {
            do {
                if node.isKind(of: .opaqueType), let firstChild = node.firstChild, firstChild.isKind(of: .opaqueTypeDescriptorSymbolicReference), let offset: Int = firstChild.index?.cast() {
                    let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: offset, in: machO)
                    let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
                    let underlyingTypeArgumentNode = try MetadataReader.demangleType(for: opaqueType.underlyingTypeArgumentMangledNames[0], in: machO)
                    if underlyingTypeArgumentNode.kind == .type, let firstChild = underlyingTypeArgumentNode.firstChild {
                        return firstChild
                    }
                }
            } catch {
                Swift.print(error)
            }
            return node
        }
    }

    fileprivate func resolveOpaqueType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        OpaqueTypeNodeRewriter(machO: machO).rewrite(self)
    }
}
