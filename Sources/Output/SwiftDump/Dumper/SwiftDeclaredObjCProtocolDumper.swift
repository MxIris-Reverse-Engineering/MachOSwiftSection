import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftThunkAnalysis
import SwiftDeclarationRendering

/// Dumps an `@objc` protocol declared in Swift (evolution proposal
/// `swift-declared-objc-protocols`) with what the binary says about it: how
/// it was recognized, its Objective-C record, and each requirement as a
/// Swift declaration followed by its Objective-C facts — the selector,
/// whether it is required, its type encoding, and the class it was taken
/// from when one implements it.
package struct SwiftDeclaredObjCProtocolDumper<MachO: MachOFieldLayoutRenderable>: NamedDumper {
    package typealias Dumped = SwiftDeclaredObjCProtocol

    package let dumped: Dumped

    package let configuration: DumperConfiguration

    package let machO: MachO

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var name: SemanticString {
        get async throws {
            try await dumped.dumpedName(using: demangleResolver, configuration: configuration)
        }
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.atObjc)
            if dumped.hasExplicitObjCName, let record = dumped.record {
                Standard("(\(record.runtimeName))")
            }
            Space()
            Keyword(.protocol)
            Space()
            try await name
            if let record = dumped.record {
                for (offset, runtimeName) in record.inheritedProtocolRuntimeNames.offsetEnumerated() {
                    Standard(offset.isStart ? ":" : ",")
                    Space()
                    try await demangleResolver.resolve(for: Node.createTransient(kind: .type, child: ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO)))
                }
            }
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            BreakLine()
            Indent(level: configuration.indentation)
            switch dumped.evidence {
            case .fieldDescriptor(let offset):
                Comment("Evidence: field descriptor of kind ObjCProtocol at 0x\(String(offset, radix: 16))")
            case .runtimeName:
                Comment("Evidence: the record's runtime name spells this image's module (the image has no reflection metadata)")
            }

            if let record = dumped.record {
                BreakLine()
                Indent(level: configuration.indentation)
                Comment("ObjC protocol \(record.runtimeName), record emitted by \(record.isEmittedBySwift ? "Swift" : "clang") at 0x\(String(record.offset, radix: 16))")
                try await requirements(of: record)
            } else {
                BreakLine()
                Indent(level: configuration.indentation)
                Comment("No Objective-C protocol record pairs with this declaration: the source renamed it with @objc(Name) to a name other than its Swift name.")
            }

            BreakLine()
            Standard("}")
        }
    }

    @SemanticStringBuilder
    private func requirements(of record: ObjCProtocolRecord) async throws -> SemanticString {
        let protocolNode = try dumped.protocolNode()
        let requirements = ObjCProtocolRequirementBuilder.requirements(of: record, protocolNode: protocolNode, in: machO)
        let witnesses = ObjCProtocolWitnesses.witnesses(for: requirements, ofProtocolRuntimeName: record.runtimeName, protocolNode: protocolNode, in: machO)
        if requirements.indices.contains(where: { witnesses[$0] == nil }) {
            BreakLine()
            Indent(level: configuration.indentation)
            Comment("Requirements no class of this image implements are named from their selectors by the ClangImporter's rules; the binary records no Swift names for them.")
        }
        if !requirements.isEmpty {
            BreakLine()
        }
        for (index, requirement) in requirements.enumerated() {
            let witness = witnesses[index]
            BreakLine()
            Indent(level: configuration.indentation)
            Keyword(.atObjc)
            if witness?.hasExplicitSelector ?? true {
                Standard("(\(requirement.selector))")
            }
            Space()
            if requirement.isOptional {
                Keyword(.optional)
                Space()
            }
            try await demangleResolver.resolve(for: witness?.node ?? requirement.node)
            Space()
            let factsComment = try await objcFactsComment(for: requirement, witness: witness)
            Comment(factsComment)
        }
    }

    /// `-teamNameFor:error: required, @"NSString"32@0:8@"NSString"16^@24`,
    /// then the implementing class and what tied its member, for one taken
    /// from a class.
    private func objcFactsComment(for requirement: ObjCProtocolRequirement, witness: ObjCProtocolWitness?) async throws -> String {
        let prefix = requirement.isClassMember ? "+" : "-"
        var selectors = prefix + requirement.selector
        if let setterSelector = requirement.setterSelector {
            selectors += ", " + prefix + setterSelector
        }
        var comment = "\(selectors) \(requirement.isOptional ? "optional" : "required"), \(requirement.typeEncoding)"
        if let witness {
            let className = try await demangleResolver.resolve(for: Node.createTransient(kind: .type, child: witness.classNode)).string
            comment += "; implemented by \(className) (\(witness.evidence.description))"
        }
        return comment
    }
}
