import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// One member of an Objective-C class or category as Swift imports it
/// (evolution proposal `objc-imported-declarations`), shaped like the member
/// symbol the compiler would have demangled to so the member printers print
/// it as they print any other. Its Swift name follows the importer's rules
/// and may not be the one the SDK gives it: the printer pins the selector
/// with `@objc(selector)`.
package struct ObjCImportedMember: Sendable {
    package enum Kind: Sendable, Hashable {
        case method
        case initializer
        /// A class method imported as a convenience initializer.
        case factoryInitializer
        case property
        case `subscript`
    }

    /// How an object property holds its value, from its attributes.
    package enum Ownership: Sendable, Hashable {
        /// `&` (`strong`, `retain`).
        case strong
        /// `C`: `@NSCopying`.
        case copy
        /// `W`: `weak`.
        case weak
        /// None of them on an object: `assign` or `unsafe_unretained`,
        /// `unowned(unsafe)`.
        case unownedUnsafe
    }

    package let kind: Kind
    /// The selector the runtime sends: a method's, a property's or a
    /// subscript's getter.
    package let selector: String
    /// A property's or subscript's setter; `nil` when it is read-only.
    package let setterSelector: String?
    package let isClassMember: Bool
    /// The declaration: `Global > Function`, `Global > Static > Getter >
    /// Variable`, `Global > Allocator`, `Global > Getter > Subscript`.
    package let node: Node
    /// The encoding the declaration was built from: the method list's, an
    /// adopted protocol's extended one, or the property's attributes.
    package let typeEncoding: String
    /// An object property's ownership; `nil` for every other member.
    package let ownership: Ownership?

    package var isSettable: Bool {
        setterSelector != nil
    }
}

/// Builds the members of an Objective-C class or category from its method
/// and property lists (evolution proposal `objc-imported-declarations`), in
/// list order — the source's — with a property where its getter is, the
/// instance members before the class members.
///
/// Names follow `ObjCImporterNaming`, a class method restating the class's
/// name imported as an initializer. A method list's encoding names no class;
/// when a protocol the class or category adopts declares the same selector,
/// its extended encoding — classes, protocols, block signatures — gives the
/// types and the names instead. Methods Swift never sees are left out: the
/// compiler's `.cxx_construct` and `.cxx_destruct`, `dealloc`, and the
/// reference counting methods ARC forbids.
package enum ObjCImportedMemberBuilder {
    /// The members of `record`, declared on `contextNode` (the `Class` node
    /// of the class, or of a category's target), whose name for the
    /// importer's rules is `contextTypeName`.
    package static func members(of record: ObjCImportedContainerRecord, contextNode: Node, contextTypeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> [ObjCImportedMember] {
        Builder(record: record, contextNode: contextNode, contextTypeName: contextTypeName, machO: machO).members()
    }

    /// The selectors the importer never imports as members.
    private static let unimportedSelectors: Set<String> = [
        ".cxx_construct", ".cxx_destruct", "dealloc",
        "retain", "release", "autorelease", "retainCount",
    ]

    private struct Builder<MachO: MachOSwiftSectionRepresentableWithCache> {
        let record: ObjCImportedContainerRecord
        let contextNode: Node
        let contextTypeName: String
        let machO: MachO
        let nodes: ObjCImportedMemberNodes<MachO>

        init(record: ObjCImportedContainerRecord, contextNode: Node, contextTypeName: String, machO: MachO) {
            self.record = record
            self.contextNode = contextNode
            self.contextTypeName = contextTypeName
            self.machO = machO
            self.nodes = ObjCImportedMemberNodes(machO: machO)
        }

        private struct PropertyAccessors {
            let property: ObjCImportedContainerRecord.Property
            let getterSelector: String
            let setterSelector: String?
        }

        func members() -> [ObjCImportedMember] {
            var members: [ObjCImportedMember] = []
            for isClassMember in [false, true] {
                let methods = isClassMember ? record.classMethods : record.instanceMethods
                let properties = propertyAccessors(of: isClassMember ? record.classProperties : record.instanceProperties)
                let propertyNames = Self.propertyNames(properties: properties, methods: methods)
                let methodSelectors = Set(methods.map(\.selector))
                var emittedPropertyNames: Set<String> = []
                for method in methods {
                    // A property prints where its getter is; its setter, and
                    // a getter seen again, print nothing more.
                    if let accessors = properties.first(where: { $0.getterSelector == method.selector || $0.setterSelector == method.selector }) {
                        guard emittedPropertyNames.insert(accessors.property.name).inserted else { continue }
                        if let member = propertyMember(accessors, isClassMember: isClassMember, propertyNames: propertyNames) {
                            members.append(member)
                        }
                        continue
                    }
                    guard !ObjCImportedMemberBuilder.unimportedSelectors.contains(method.selector) else { continue }
                    if let member = methodMember(method, isClassMember: isClassMember, propertyNames: propertyNames, methodSelectors: methodSelectors) {
                        members.append(member)
                    }
                }
                // A property whose accessors are in no method list — a
                // `@dynamic` one, or one an ancestor implements.
                for accessors in properties where !emittedPropertyNames.contains(accessors.property.name) {
                    if let member = propertyMember(accessors, isClassMember: isClassMember, propertyNames: propertyNames) {
                        members.append(member)
                    }
                }
            }
            return members
        }

        /// `NameImporter::getAllPropertyNames`, as far as the record goes:
        /// its property names, and the selectors of its argument-less methods
        /// that return something. The importer also takes the superclasses'.
        private static func propertyNames(properties: [PropertyAccessors], methods: [ObjCImportedContainerRecord.Method]) -> Set<String> {
            var names = Set(properties.map(\.property.name))
            for method in methods where !method.selector.contains(":") && !method.typeEncoding.hasPrefix("v") {
                names.insert(method.selector)
            }
            return names
        }

        private func propertyAccessors(of properties: [ObjCImportedContainerRecord.Property]) -> [PropertyAccessors] {
            properties.map { property in
                let attributes = property.attributes.split(separator: ",").map(String.init)
                let getterSelector = attributes.first { $0.hasPrefix("G") }.map { String($0.dropFirst()) } ?? property.name
                let isReadOnly = attributes.contains("R")
                let setterSelector = isReadOnly ? nil : (attributes.first { $0.hasPrefix("S") }.map { String($0.dropFirst()) } ?? "set" + property.name.prefix(1).uppercased() + property.name.dropFirst() + ":")
                return PropertyAccessors(property: property, getterSelector: getterSelector, setterSelector: setterSelector)
            }
        }

        private func propertyMember(_ accessors: PropertyAccessors, isClassMember: Bool, propertyNames: Set<String>) -> ObjCImportedMember? {
            let attributes = accessors.property.attributes
            guard let type = ObjCTypeEncodingParser.propertyType(fromAttributes: attributes) else { return nil }
            let name = ObjCImporterNaming.importedPropertyName(accessors.property.name, attributes: attributes, contextTypeName: contextTypeName, propertyNames: propertyNames)
            return ObjCImportedMember(
                kind: .property,
                selector: accessors.getterSelector,
                setterSelector: accessors.setterSelector,
                isClassMember: isClassMember,
                node: nodes.propertyNode(contextNode: contextNode, name: name, type: type, isClassMember: isClassMember),
                typeEncoding: attributes,
                ownership: Self.ownership(type: type, attributes: attributes)
            )
        }

        private static func ownership(type: ObjCEncodedType, attributes: String) -> ObjCImportedMember.Ownership? {
            guard type.isObjectPointer else { return nil }
            let attributeCodes = Set(attributes.split(separator: ",").map(String.init))
            if attributeCodes.contains("C") { return .copy }
            if attributeCodes.contains("W") { return .weak }
            if attributeCodes.contains("&") { return .strong }
            return .unownedUnsafe
        }

        private func methodMember(_ method: ObjCImportedContainerRecord.Method, isClassMember: Bool, propertyNames: Set<String>, methodSelectors: Set<String>) -> ObjCImportedMember? {
            // An adopted protocol's extended encoding names what the method
            // list's leaves as `@`. Either has to take one argument per
            // colon of the selector, or the names and types would not pair.
            let argumentCount = method.selector.count(where: { $0 == ":" })
            func argumentMatchedMethodType(from encoding: String) -> ObjCMethodTypeEncoding? {
                guard let parsed = ObjCTypeEncodingParser.methodType(from: encoding), parsed.parameterTypes.count == argumentCount else { return nil }
                return parsed
            }
            let encoding: String
            let methodType: ObjCMethodTypeEncoding
            if let extendedEncoding = adoptedProtocolEncoding(of: method.selector, isClassMember: isClassMember),
               let extendedMethodType = argumentMatchedMethodType(from: extendedEncoding) {
                encoding = extendedEncoding
                methodType = extendedMethodType
            } else if let plainMethodType = argumentMatchedMethodType(from: method.typeEncoding) {
                encoding = method.typeEncoding
                methodType = plainMethodType
            } else {
                return nil
            }
            let name = ObjCImporterNaming.importedName(
                selector: method.selector,
                isClassMethod: isClassMember,
                methodType: methodType,
                contextTypeName: contextTypeName,
                propertyNames: propertyNames,
                undoesSwiftInsertedWith: false,
                factoryInitializerClassName: contextTypeName
            )
            switch name.kind {
            case .subscriptSetter:
                // Folded into the getter's subscript.
                return nil
            case .subscriptGetter:
                guard let node = nodes.subscriptNode(contextNode: contextNode, methodType: methodType, isClassMember: isClassMember) else { return nil }
                let setterSelector = method.selector == "objectAtIndexedSubscript:" ? "setObject:atIndexedSubscript:" : "setObject:forKeyedSubscript:"
                return ObjCImportedMember(
                    kind: .subscript,
                    selector: method.selector,
                    setterSelector: methodSelectors.contains(setterSelector) ? setterSelector : nil,
                    isClassMember: isClassMember,
                    node: node,
                    typeEncoding: encoding,
                    ownership: nil
                )
            case .initializer, .factoryInitializer, .method:
                let kind: ObjCImportedMember.Kind = switch name.kind {
                case .initializer: .initializer
                case .factoryInitializer: .factoryInitializer
                default: .method
                }
                return ObjCImportedMember(
                    kind: kind,
                    selector: method.selector,
                    setterSelector: nil,
                    isClassMember: isClassMember && kind == .method,
                    node: nodes.methodNode(contextNode: contextNode, name: name, methodType: methodType, isClassMember: isClassMember),
                    typeEncoding: encoding,
                    ownership: nil
                )
            }
        }

        /// The extended encoding of `selector` in a protocol the record
        /// adopts, or in one those protocols inherit, among the protocol
        /// records of the image.
        private func adoptedProtocolEncoding(of selector: String, isClassMember: Bool) -> String? {
            var visitedRuntimeNames: Set<String> = []
            var pendingRuntimeNames = record.protocolRuntimeNames
            while !pendingRuntimeNames.isEmpty {
                let runtimeName = pendingRuntimeNames.removeFirst()
                guard visitedRuntimeNames.insert(runtimeName).inserted,
                      let protocolRecord = ObjCImportedContainerIndex.shared.protocolRecord(named: runtimeName, in: machO)
                else { continue }
                let methodLists = isClassMember
                    ? [protocolRecord.requiredClassMethods, protocolRecord.optionalClassMethods]
                    : [protocolRecord.requiredInstanceMethods, protocolRecord.optionalInstanceMethods]
                for methods in methodLists {
                    if let method = methods.first(where: { $0.selector == selector }), let extendedTypeEncoding = method.extendedTypeEncoding {
                        return extendedTypeEncoding
                    }
                }
                pendingRuntimeNames.append(contentsOf: protocolRecord.inheritedProtocolRuntimeNames)
            }
            return nil
        }
    }
}
