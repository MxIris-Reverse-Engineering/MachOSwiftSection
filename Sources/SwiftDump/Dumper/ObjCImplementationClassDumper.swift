import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Dependencies
import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftThunkAnalysis
import SwiftDeclarationRendering

/// Dumps an `@objc @implementation` class with everything the binary says
/// about it, ObjC side first: the class object's facts, the ivar list joined
/// with the Swift field-offset symbols, the method lists with their IMPs and
/// the Swift symbols found there, the property list, the protocol list, then
/// the Swift member symbols the way `ClassDumper` lists a class's. Nothing
/// is guessed: an IMP with no symbol prints as an address, an ivar with no
/// field-offset symbol prints its ObjC facts and no Swift type.
package struct ObjCImplementationClassDumper<MachO: MachOFieldLayoutRenderable>: NamedDumper {
    package typealias Dumped = ObjCImplementationClass

    package let dumped: Dumped

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var facts: ObjCImplementationClassFacts { dumped.facts }

    /// The class's overrides of ObjC-inherited members (evolution proposal
    /// `objc-ancestor-override-recovery`), by selector — the ObjC method lines
    /// name the ancestor they override.
    private var objcAncestorOverrideTable: ObjCAncestorOverrideTable? {
        ObjCAncestorOverrides.table(forObjCClassNamed: facts.className, in: machO)
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    /// The symbol index files a `__C` class's extension members under the
    /// module-qualified interface name.
    private var interfaceNameString: String {
        "\(CImportedModuleNames.objectiveC).\(facts.className)"
    }

    package var name: SemanticString {
        get async throws {
            TypeDeclaration(kind: .class, facts.className)
        }
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.atObjc)
            Space()
            Keyword(.atImplementation)
            Space()
            if facts.evidence.isInferred {
                InlineComment(facts.evidence.description)
                Space()
            }
            Keyword(.extension)
            Space()
            try await name
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            Space()

            Standard("{")

            BreakLine()
            Indent(level: 1)
            Comment("ObjC class \(facts.className): \(facts.superclassName ?? "<root>"), class_ro_t flags 0x\(String(facts.readOnlyDataFlags, radix: 16)), instanceStart \(facts.instanceStart), instanceSize \(facts.instanceSize)")
            BreakLine()
            Indent(level: 1)
            Comment("Evidence: \(facts.evidence.description)")
            if let implementingModuleName = facts.implementingModuleName {
                BreakLine()
                Indent(level: 1)
                Comment("Implemented in Swift module \(implementingModuleName)")
            }
            let objcAncestorOverrideTable = objcAncestorOverrideTable
            if let hierarchy = objcAncestorOverrideTable?.hierarchy, !hierarchy.ancestors.isEmpty {
                BreakLine()
                Indent(level: 1)
                Comment(ObjCAncestorOverrideRendering.ancestorChainComment(for: hierarchy))
            }
            BreakLine()

            try await instanceVariables

            methods(facts.instanceMethods, title: "ObjC instance methods", selectorPrefix: "-", isClassMethod: false, overrideTable: objcAncestorOverrideTable)

            methods(facts.classMethods, title: "ObjC class methods", selectorPrefix: "+", isClassMethod: true, overrideTable: objcAncestorOverrideTable)

            properties

            protocols

            try await swiftMembers

            Standard("}")
        }
    }

    @SemanticStringBuilder
    private var instanceVariables: SemanticString {
        get async throws {
        for (offset, instanceVariable) in facts.instanceVariables.offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                Indent(level: 1)
                InlineComment("Stored properties (ObjC ivars)")
            }
            BreakLine()
            if configuration.printFieldOffset {
                configuration.fieldOffsetComment(startOffset: instanceVariable.offset, endOffset: instanceVariable.offset + instanceVariable.size)
            }
            Indent(level: 1)
            if let typeNode = instanceVariable.swiftTypeNode, let propertyName = instanceVariable.swiftPropertyName {
                Keyword(.var)
                Space()
                MemberDeclaration(propertyName)
                Standard(":")
                Space()
                try await demangleResolver.resolve(for: typeNode.materialize())
            } else {
                MemberDeclaration(instanceVariable.name.isEmpty ? "<unnamed ivar>" : instanceVariable.name)
            }
            Space()
            Comment(instanceVariableComment(for: instanceVariable))
            if offset.isEnd {
                BreakLine()
            }
        }
        }
    }

    private func instanceVariableComment(for instanceVariable: ObjCImplementationClassFacts.InstanceVariable) -> String {
        var parts = ["offset 0x\(String(instanceVariable.offset, radix: 16))", "size \(instanceVariable.size)", "alignment \(instanceVariable.alignment)", "encoding \"\(instanceVariable.typeEncoding)\""]
        if !instanceVariable.name.isEmpty, instanceVariable.swiftPropertyName != nil, instanceVariable.name != instanceVariable.swiftPropertyName {
            parts.append("ivar \(instanceVariable.name)")
        }
        if let symbolName = instanceVariable.swiftFieldOffsetSymbolName {
            parts.append(symbolName)
        } else {
            parts.append("Swift type not recoverable")
        }
        if !instanceVariable.isObjCVisible {
            parts.append("not exposed to ObjC")
        }
        return parts.joined(separator: ", ")
    }

    @SemanticStringBuilder
    private func methods(_ methods: [ObjCImplementationClassFacts.Method], title: String, selectorPrefix: String, isClassMethod: Bool, overrideTable: ObjCAncestorOverrideTable?) -> SemanticString {
        for (offset, method) in methods.offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                Indent(level: 1)
                InlineComment(title)
            }
            BreakLine()
            if configuration.printMemberAddress, let implementationOffset = method.implementationOffset {
                configuration.memberAddressComment(offset: implementationOffset, addressString: machO.addressString(forOffset: implementationOffset))
            }
            Indent(level: 1)
            FunctionDeclaration("\(selectorPrefix)[\(facts.className) \(method.selector)]")
            Space()
            Comment(methodComment(for: method, overridden: overrideTable?.hierarchy.ancestorDeclaring(selector: method.selector, isClassMethod: isClassMethod), isUnattributed: overrideTable?.unattributedOverriddenMethods.contains { $0.selector == method.selector && $0.isClassMethod == isClassMethod } ?? false))
            if offset.isEnd {
                BreakLine()
            }
        }
    }

    private func methodComment(for method: ObjCImplementationClassFacts.Method, overridden ancestor: ObjCClassHierarchy.Ancestor?, isUnattributed: Bool) -> String {
        var parts = ["types \"\(method.typeEncoding)\""]
        if let implementationOffset = method.implementationOffset {
            parts.append("imp 0x\(machO.addressString(forOffset: implementationOffset))")
        } else {
            parts.append("no imp")
        }
        if !method.implementationSymbolNames.isEmpty {
            parts.append(method.implementationSymbolNames.joined(separator: " / "))
        }
        if let ancestor {
            let ancestorName = ObjCAncestorOverrideRendering.displayName(forAncestorClassNamed: ancestor.className)
            parts.append(isUnattributed ? "overrides \(ancestorName) (no Swift member tied to this IMP)" : "overrides \(ancestorName)")
        }
        return parts.joined(separator: ", ")
    }

    @SemanticStringBuilder
    private var properties: SemanticString {
        for (offset, property) in facts.properties.offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                Indent(level: 1)
                InlineComment("ObjC properties")
            }
            BreakLine()
            Indent(level: 1)
            MemberDeclaration(property.name)
            Space()
            Comment(property.attributes)
            if offset.isEnd {
                BreakLine()
            }
        }
    }

    @SemanticStringBuilder
    private var protocols: SemanticString {
        if !facts.protocolNames.isEmpty {
            BreakLine()
            Indent(level: 1)
            InlineComment("ObjC protocols")
            BreakLine()
            Indent(level: 1)
            Standard(facts.protocolNames.joined(separator: ", "))
            BreakLine()
        }
    }

    @SemanticStringBuilder
    private var swiftMembers: SemanticString {
        get async throws {
            let objcAncestorOverrideTable = objcAncestorOverrideTable
            for kind in SymbolIndexStore.MemberKind.allCases {
                let memberSymbols = symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO)
                for (offset, symbol) in memberSymbols.offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()
                        Indent(level: 1)
                        InlineComment("Swift " + kind.description)
                    }
                    BreakLine()
                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }
                    if configuration.printExportStatus,
                       !symbolIndexStore.containsSymbol(named: symbol.name + "To", in: machO),
                       symbolIndexStore.isExportedIncludingDerivedSymbols(name: symbol.name, in: machO) == false {
                        configuration.exportStatusComment()
                    }
                    Indent(level: 1)
                    try await demangleResolver.resolve(for: symbol.demangledNode)
                    if let override = objcAncestorOverrideTable?.override(forMemberSymbolNamed: symbol.name) ?? objcAncestorOverrideTable?.override(forAllocatorSymbolNamed: symbol.name) {
                        Space()
                        Comment(ObjCAncestorOverrideRendering.overrideComment(for: override))
                    }
                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }
        }
    }
}
