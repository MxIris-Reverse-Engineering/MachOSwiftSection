import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// One requirement of an `@objc` protocol declared in Swift, as a Swift
/// declaration (evolution proposal `swift-declared-objc-protocols`). The
/// binary keeps no Swift symbol for it; the declaration is built from the
/// protocol's Objective-C record by the importer's rules, shaped like the
/// member symbol the compiler would have demangled to, so the member
/// printers print it as they print any other. Its Swift name may differ
/// from the source's: the printer pins the selector with `@objc(selector)`.
package struct ObjCProtocolRequirement: Sendable {
    package enum Kind: Sendable, Hashable {
        case method
        case initializer
        case property
        case `subscript`
    }

    package let kind: Kind
    /// The selector the runtime sends: a method's, a property's or a
    /// subscript's getter.
    package let selector: String
    /// A property's or subscript's setter; `nil` when it is read-only.
    package let setterSelector: String?
    package let isClassMember: Bool
    package let isOptional: Bool
    /// The declaration, shaped like a demangled member symbol: `Global >
    /// Function`, `Global > Static > Getter > Variable`, `Global > Allocator`,
    /// `Global > Getter > Subscript`.
    package let node: Node
    /// What the declaration was built from: the method's type encoding
    /// (extended when the record carries one), or the property's attributes.
    package let typeEncoding: String

    package var isSettable: Bool {
        setterSelector != nil
    }

    package init(kind: Kind, selector: String, setterSelector: String?, isClassMember: Bool, isOptional: Bool, node: Node, typeEncoding: String) {
        self.kind = kind
        self.selector = selector
        self.setterSelector = setterSelector
        self.isClassMember = isClassMember
        self.isOptional = isOptional
        self.node = node
        self.typeEncoding = typeEncoding
    }
}

/// Builds the requirements of an `@objc` protocol declared in Swift from its
/// Objective-C record: every method and property of the four method lists
/// and two property lists, in record order — which is the source's order
/// within each list — with a property or subscript where its getter is.
///
/// Names follow `ObjCImporterNaming`; a property keeps the name its record
/// carries, which is the Swift name unless the source renamed it. Types
/// follow the importer too (`ObjCImportedTypes`), and the declarations take
/// the shapes `ObjCImportedMemberNodes` gives every imported member.
package enum ObjCProtocolRequirementBuilder {
    /// The requirements of `record`, declared on `protocolNode` (a
    /// `Protocol` node, as the protocol's mangled name demangles to).
    package static func requirements(of record: ObjCProtocolRecord, protocolNode: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> [ObjCProtocolRequirement] {
        let builder = Builder(protocolNode: protocolNode, record: record, machO: machO)
        return builder.requirements()
    }

    private struct Builder<MachO: MachOSwiftSectionRepresentableWithCache> {
        let protocolNode: Node
        let record: ObjCProtocolRecord
        let contextTypeName: String
        let propertyNames: Set<String>
        let nodes: ObjCImportedMemberNodes<MachO>

        init(protocolNode: Node, record: ObjCProtocolRecord, machO: MachO) {
            self.protocolNode = protocolNode
            self.record = record
            self.contextTypeName = protocolNode.children.at(1)?.text ?? record.runtimeName
            self.propertyNames = Set((record.instanceProperties + record.classProperties).map(\.name))
            self.nodes = ObjCImportedMemberNodes(machO: machO)
        }

        private struct PropertyAccessors {
            let property: ObjCProtocolRecord.Property
            let getterSelector: String
            let setterSelector: String?
        }

        func requirements() -> [ObjCProtocolRequirement] {
            let instanceProperties = propertyAccessors(of: record.instanceProperties)
            let classProperties = propertyAccessors(of: record.classProperties)
            var requirements: [ObjCProtocolRequirement] = []
            var emittedPropertyNames: (instance: Set<String>, class: Set<String>) = ([], [])
            let lists: [(methods: [ObjCProtocolRecord.Method], isClassMethod: Bool, isOptional: Bool)] = [
                (record.requiredInstanceMethods, false, false),
                (record.requiredClassMethods, true, false),
                (record.optionalInstanceMethods, false, true),
                (record.optionalClassMethods, true, true),
            ]
            for list in lists {
                let properties = list.isClassMethod ? classProperties : instanceProperties
                let methodsBySelector = Dictionary(list.methods.map { ($0.selector, $0) }, uniquingKeysWith: { first, _ in first })
                for method in list.methods {
                    // A property prints where its getter is; its setter, and
                    // a getter seen again, print nothing more.
                    if let accessors = properties.first(where: { $0.getterSelector == method.selector || $0.setterSelector == method.selector }) {
                        let alreadyEmitted = list.isClassMethod ? emittedPropertyNames.class.contains(accessors.property.name) : emittedPropertyNames.instance.contains(accessors.property.name)
                        guard !alreadyEmitted else { continue }
                        if list.isClassMethod {
                            emittedPropertyNames.class.insert(accessors.property.name)
                        } else {
                            emittedPropertyNames.instance.insert(accessors.property.name)
                        }
                        if let requirement = propertyRequirement(accessors, isClassMember: list.isClassMethod, isOptional: list.isOptional) {
                            requirements.append(requirement)
                        }
                        continue
                    }
                    if let requirement = methodRequirement(method, isClassMethod: list.isClassMethod, isOptional: list.isOptional, methodsBySelector: methodsBySelector) {
                        requirements.append(requirement)
                    }
                }
            }
            // A property whose accessors are in no method list (a record of
            // an unusual compiler): still a requirement.
            for (accessors, isClassMember) in instanceProperties.map({ ($0, false) }) + classProperties.map({ ($0, true) }) {
                let emitted = isClassMember ? emittedPropertyNames.class : emittedPropertyNames.instance
                guard !emitted.contains(accessors.property.name), let requirement = propertyRequirement(accessors, isClassMember: isClassMember, isOptional: false) else { continue }
                requirements.append(requirement)
            }
            return requirements
        }

        private func propertyAccessors(of properties: [ObjCProtocolRecord.Property]) -> [PropertyAccessors] {
            properties.map { property in
                let attributes = property.attributes.split(separator: ",").map(String.init)
                let getterSelector = attributes.first { $0.hasPrefix("G") }.map { String($0.dropFirst()) } ?? property.name
                let isReadOnly = attributes.contains("R")
                let setterSelector = isReadOnly ? nil : (attributes.first { $0.hasPrefix("S") }.map { String($0.dropFirst()) } ?? "set" + property.name.prefix(1).uppercased() + property.name.dropFirst() + ":")
                return PropertyAccessors(property: property, getterSelector: getterSelector, setterSelector: setterSelector)
            }
        }

        private func propertyRequirement(_ accessors: PropertyAccessors, isClassMember: Bool, isOptional: Bool) -> ObjCProtocolRequirement? {
            guard let type = ObjCTypeEncodingParser.propertyType(fromAttributes: accessors.property.attributes) else { return nil }
            return ObjCProtocolRequirement(
                kind: .property,
                selector: accessors.getterSelector,
                setterSelector: accessors.setterSelector,
                isClassMember: isClassMember,
                isOptional: isOptional,
                node: nodes.propertyNode(contextNode: protocolNode, name: accessors.property.name, type: type, isClassMember: isClassMember),
                typeEncoding: accessors.property.attributes
            )
        }

        private func methodRequirement(_ method: ObjCProtocolRecord.Method, isClassMethod: Bool, isOptional: Bool, methodsBySelector: [String: ObjCProtocolRecord.Method]) -> ObjCProtocolRequirement? {
            let encoding = method.extendedTypeEncoding ?? method.typeEncoding
            guard let methodType = ObjCTypeEncodingParser.methodType(from: encoding) ?? ObjCTypeEncodingParser.methodType(from: method.typeEncoding) else { return nil }
            let name = ObjCImporterNaming.importedName(selector: method.selector, isClassMethod: isClassMethod, methodType: methodType, contextTypeName: contextTypeName, propertyNames: propertyNames)
            switch name.kind {
            case .subscriptSetter:
                // Folded into the getter's subscript.
                return nil
            case .subscriptGetter:
                guard let node = nodes.subscriptNode(contextNode: protocolNode, methodType: methodType, isClassMember: isClassMethod) else { return nil }
                let setterSelector = method.selector == "objectAtIndexedSubscript:" ? "setObject:atIndexedSubscript:" : "setObject:forKeyedSubscript:"
                return ObjCProtocolRequirement(
                    kind: .subscript,
                    selector: method.selector,
                    setterSelector: methodsBySelector[setterSelector] != nil ? setterSelector : nil,
                    isClassMember: isClassMethod,
                    isOptional: isOptional,
                    node: node,
                    typeEncoding: encoding
                )
            case .initializer, .factoryInitializer, .method:
                // A protocol's method is never a factory initializer: the
                // naming is asked for one only on behalf of a class.
                let isInitializer = name.kind != .method
                return ObjCProtocolRequirement(
                    kind: isInitializer ? .initializer : .method,
                    selector: method.selector,
                    setterSelector: nil,
                    isClassMember: isClassMethod && !isInitializer,
                    isOptional: isOptional,
                    node: nodes.methodNode(contextNode: protocolNode, name: name, methodType: methodType, isClassMember: isClassMethod),
                    typeEncoding: encoding
                )
            }
        }
    }
}
