import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// One requirement of an `@objc` protocol declared in Swift, as a Swift
/// declaration (evolution proposal `swift-declared-objc-protocols`). The
/// binary keeps no Swift symbol for it; the declaration is built from the
/// protocol's Objective-C record, shaped like the member symbol the compiler
/// would have demangled to, so the member printers print it as they print
/// any other.
package struct ObjCProtocolRequirement: Sendable {
    package enum Kind: Sendable, Hashable {
        case method
        case initializer
        case property
        case `subscript`
    }

    /// Where the Swift spelling comes from.
    package enum Source: Sendable, Hashable {
        /// The importer's rules applied to the selector and type encoding:
        /// the Swift name may differ from the source's, so the printer pins
        /// the selector with `@objc(selector)`.
        case selector
        /// The member implementing it in a Swift class of the image that
        /// adopts the protocol, by its Swift name and types.
        case conformer(className: String)
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
    package let source: Source
    /// What the declaration was built from: the method's type encoding
    /// (extended when the record carries one), or the property's attributes.
    package let typeEncoding: String

    package var isSettable: Bool {
        setterSelector != nil
    }

    package init(kind: Kind, selector: String, setterSelector: String?, isClassMember: Bool, isOptional: Bool, node: Node, source: Source, typeEncoding: String) {
        self.kind = kind
        self.selector = selector
        self.setterSelector = setterSelector
        self.isClassMember = isClassMember
        self.isOptional = isOptional
        self.node = node
        self.source = source
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
/// follow the importer too: Foundation's bridged classes import as their
/// Swift value types, `id` as `Any`, a block as a closure, a Swift class or
/// protocol by its Swift name. An object type's nullability is not recorded,
/// so it is `T!` — what the importer makes of an unannotated declaration —
/// and `T?` inside a closure's signature, where `!` cannot be written.
package enum ObjCProtocolRequirementBuilder {
    /// The requirements of `record`, declared on `protocolNode` (a
    /// `Protocol` node, as the protocol's mangled name demangles to).
    package static func requirements(of record: ObjCProtocolRecord, protocolNode: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> [ObjCProtocolRequirement] {
        let builder = Builder(protocolNode: protocolNode, record: record, machO: machO)
        return builder.requirements()
    }

    /// The Foundation classes the importer bridges to Swift value types.
    fileprivate static let bridgedStructures: [String: (module: String, name: String)] = [
        "NSString": ("Swift", "String"),
        "NSURL": ("Foundation", "URL"),
        "NSData": ("Foundation", "Data"),
        "NSDate": ("Foundation", "Date"),
        "NSUUID": ("Foundation", "UUID"),
        "NSIndexSet": ("Foundation", "IndexSet"),
        "NSIndexPath": ("Foundation", "IndexPath"),
        "NSLocale": ("Foundation", "Locale"),
        "NSTimeZone": ("Foundation", "TimeZone"),
        "NSCalendar": ("Foundation", "Calendar"),
        "NSCharacterSet": ("Foundation", "CharacterSet"),
        "NSNotification": ("Foundation", "Notification"),
        "NSDateComponents": ("Foundation", "DateComponents"),
        "NSDateInterval": ("Foundation", "DateInterval"),
        "NSURLComponents": ("Foundation", "URLComponents"),
        "NSURLQueryItem": ("Foundation", "URLQueryItem"),
        "NSURLRequest": ("Foundation", "URLRequest"),
        "NSPersonNameComponents": ("Foundation", "PersonNameComponents"),
    ]

    private struct Builder<MachO: MachOSwiftSectionRepresentableWithCache> {
        let protocolNode: Node
        let record: ObjCProtocolRecord
        let machO: MachO
        let contextTypeName: String
        let propertyNames: Set<String>

        init(protocolNode: Node, record: ObjCProtocolRecord, machO: MachO) {
            self.protocolNode = protocolNode
            self.record = record
            self.machO = machO
            self.contextTypeName = protocolNode.children.at(1)?.text ?? record.runtimeName
            self.propertyNames = Set((record.instanceProperties + record.classProperties).map(\.name))
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
            let variable = Node.createTransient(kind: .variable, children: [
                protocolNode,
                Node.createTransient(kind: .identifier, text: accessors.property.name),
                typeNode(type, position: .topLevel),
            ])
            let getter = Node.createTransient(kind: .getter, child: variable)
            return ObjCProtocolRequirement(
                kind: .property,
                selector: accessors.getterSelector,
                setterSelector: accessors.setterSelector,
                isClassMember: isClassMember,
                isOptional: isOptional,
                node: global(getter, isStatic: isClassMember),
                source: .selector,
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
                guard let indexType = methodType.parameterTypes.first else { return nil }
                let setterSelector = method.selector == "objectAtIndexedSubscript:" ? "setObject:atIndexedSubscript:" : "setObject:forKeyedSubscript:"
                let functionType = Node.createTransient(kind: .functionType, children: [
                    Node.createTransient(kind: .argumentTuple, child: typeNode(indexType, position: .topLevel)),
                    Node.createTransient(kind: .returnType, child: typeNode(methodType.returnType, position: .topLevel)),
                ])
                let subscriptNode = Node.createTransient(kind: .subscript, children: [
                    protocolNode,
                    Node.createTransient(kind: .labelList),
                    Node.createTransient(kind: .type, child: functionType),
                ])
                return ObjCProtocolRequirement(
                    kind: .subscript,
                    selector: method.selector,
                    setterSelector: methodsBySelector[setterSelector] != nil ? setterSelector : nil,
                    isClassMember: isClassMethod,
                    isOptional: isOptional,
                    node: global(Node.createTransient(kind: .getter, child: subscriptNode), isStatic: isClassMethod),
                    source: .selector,
                    typeEncoding: encoding
                )
            case .initializer, .method:
                let parameterTypes = name.parameterIndices.map { methodType.parameterTypes[$0] }
                let resultType: Node
                if name.kind == .initializer {
                    // `instancetype`, of unknown nullability: `init!`.
                    resultType = Self.implicitlyUnwrapped(Self.type(Node.createTransient(kind: .dependentGenericParamType, children: [
                        Node.createTransient(kind: .index, index: 0),
                        Node.createTransient(kind: .index, index: 0),
                    ])))
                } else {
                    switch name.errorConvention {
                    case .booleanResult: resultType = typeNode(.void, position: .topLevel)
                    case .nonNilResult: resultType = typeNode(methodType.returnType, position: .nonOptional)
                    case nil: resultType = typeNode(methodType.returnType, position: .topLevel)
                    }
                }
                var functionTypeChildren: [Node] = []
                if name.errorConvention != nil {
                    functionTypeChildren.append(Node.createTransient(kind: .throwsAnnotation))
                }
                functionTypeChildren.append(Node.createTransient(kind: .argumentTuple, child: Self.type(Node.createTransient(kind: .tuple, children: parameterTypes.map {
                    Node.createTransient(kind: .tupleElement, child: typeNode($0, position: .topLevel))
                }))))
                functionTypeChildren.append(Node.createTransient(kind: .returnType, child: resultType))
                var declarationChildren: [Node] = [protocolNode]
                if name.kind == .method {
                    declarationChildren.append(Node.createTransient(kind: .identifier, text: name.baseName))
                }
                if !name.argumentLabels.isEmpty {
                    declarationChildren.append(Node.createTransient(kind: .labelList, children: name.argumentLabels.map {
                        $0.isEmpty ? Node.createTransient(kind: .firstElementMarker) : Node.createTransient(kind: .identifier, text: $0)
                    }))
                }
                declarationChildren.append(Node.createTransient(kind: .type, child: Node.createTransient(kind: .functionType, children: functionTypeChildren)))
                let declaration = Node.createTransient(kind: name.kind == .initializer ? .allocator : .function, children: declarationChildren)
                return ObjCProtocolRequirement(
                    kind: name.kind == .initializer ? .initializer : .method,
                    selector: method.selector,
                    setterSelector: nil,
                    isClassMember: isClassMethod && name.kind == .method,
                    isOptional: isOptional,
                    node: global(declaration, isStatic: isClassMethod && name.kind == .method),
                    source: .selector,
                    typeEncoding: encoding
                )
            }
        }

        private func global(_ declaration: Node, isStatic: Bool) -> Node {
            Node.createTransient(kind: .global, child: isStatic ? Node.createTransient(kind: .static, child: declaration) : declaration)
        }

        // MARK: Types

        enum Position {
            /// A parameter, a result or a property: an object's nullability
            /// is unknown, `T!`.
            case topLevel
            /// A closure's parameter or result: `T?`, as `!` cannot nest.
            case closureComponent
            /// A result the error convention proves non-nil.
            case nonOptional
        }

        /// A `Type` node for `type` in `position`.
        func typeNode(_ type: ObjCEncodedType, position: Position) -> Node {
            let base = Self.type(bareTypeNode(type))
            guard Self.isNullable(type) else { return base }
            switch position {
            case .topLevel: return Self.implicitlyUnwrapped(base)
            case .closureComponent: return Self.optional(base)
            case .nonOptional: return base
            }
        }

        private static func isNullable(_ type: ObjCEncodedType) -> Bool {
            switch type {
            case .object, .block, .objectClass, .characterString: true
            case .pointer: true
            default: false
            }
        }

        /// The type itself, unwrapped: what a `Type` node holds.
        private func bareTypeNode(_ type: ObjCEncodedType) -> Node {
            switch type {
            case .void: return Node.createTransient(kind: .tuple)
            case .bool: return Self.swiftStructure("Bool")
            case .character: return Self.swiftStructure("Int8")
            case .unsignedCharacter: return Self.swiftStructure("UInt8")
            case .short: return Self.swiftStructure("Int16")
            case .unsignedShort: return Self.swiftStructure("UInt16")
            case .int, .long: return Self.swiftStructure("Int32")
            case .unsignedInt, .unsignedLong: return Self.swiftStructure("UInt32")
            case .longLong: return Self.swiftStructure("Int")
            case .unsignedLongLong: return Self.swiftStructure("UInt")
            case .float: return Self.swiftStructure("Float")
            case .double, .longDouble: return Self.swiftStructure("Double")
            case .characterString: return Self.boundGenericStructure(Self.swiftStructure("UnsafeMutablePointer"), arguments: [Self.swiftStructure("Int8")])
            case .selector: return Self.structure(module: "ObjectiveC", name: "Selector")
            case .objectClass: return Node.createTransient(kind: .typeAlias, children: [Self.module("Swift"), Node.createTransient(kind: .identifier, text: "AnyClass")])
            case .object(let className, let protocolNames): return objectNode(className: className, protocolNames: protocolNames)
            case .block(let signature):
                guard let signature else { return Self.anyNode }
                return Node.createTransient(kind: .functionType, children: [
                    Node.createTransient(kind: .argumentTuple, child: Self.type(Node.createTransient(kind: .tuple, children: signature.parameterTypes.map {
                        Node.createTransient(kind: .tupleElement, child: typeNode($0, position: .closureComponent))
                    }))),
                    Node.createTransient(kind: .returnType, child: typeNode(signature.returnType, position: .closureComponent)),
                ])
            case .pointer(let pointee, let isConst):
                switch pointee {
                case .void: return Self.swiftStructure(isConst ? "UnsafeRawPointer" : "UnsafeMutableRawPointer")
                case .unknown, .object, .block, .objectClass, .bitField: return Self.swiftStructure("OpaquePointer")
                default: return Self.boundGenericStructure(Self.swiftStructure(isConst ? "UnsafePointer" : "UnsafeMutablePointer"), arguments: [bareTypeNode(pointee)])
                }
            case .structure(let name), .union(let name):
                guard let name else { return Self.swiftStructure("OpaquePointer") }
                return Self.structure(module: objcModule, name: name)
            case .array(let count, let element):
                // A C array imports as a tuple of its elements.
                return Node.createTransient(kind: .tuple, children: (0 ..< max(count, 0)).map { _ in
                    Node.createTransient(kind: .tupleElement, child: Self.type(bareTypeNode(element)))
                })
            case .bitField, .unknown:
                return Self.anyNode
            }
        }

        private func objectNode(className: String?, protocolNames: [String]) -> Node {
            let protocols = protocolNames.map { Self.type(protocolNode(forRuntimeName: $0)) }
            guard let className else {
                // `id`, `id<P>`, `id<P, Q>`.
                return Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList, children: protocols))
            }
            if !protocols.isEmpty {
                // `NSObject<P> *` imports as `NSObject & P`.
                return Node.createTransient(kind: .protocolListWithClass, children: [
                    Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList, children: protocols)),
                    Self.type(classNode(forRuntimeName: className)),
                ])
            }
            if let bridged = ObjCProtocolRequirementBuilder.bridgedStructures[className] {
                return Self.structure(module: bridged.module, name: bridged.name)
            }
            switch className {
            case "NSArray":
                return Self.boundGenericStructure(Self.swiftStructure("Array"), arguments: [Self.anyNode])
            case "NSDictionary":
                return Self.boundGenericStructure(Self.swiftStructure("Dictionary"), arguments: [Self.swiftStructure("AnyHashable"), Self.anyNode])
            case "NSSet":
                return Self.boundGenericStructure(Self.swiftStructure("Set"), arguments: [Self.swiftStructure("AnyHashable")])
            case "NSError":
                return Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList, child: Self.type(Node.createTransient(kind: .protocol, children: [Self.module("Swift"), Node.createTransient(kind: .identifier, text: "Error")]))))
            default:
                return classNode(forRuntimeName: className)
            }
        }

        private func protocolNode(forRuntimeName runtimeName: String) -> Node {
            ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO)
        }

        private func classNode(forRuntimeName runtimeName: String) -> Node {
            ObjCRuntimeNames.classNode(forRuntimeName: runtimeName, in: machO)
        }

        // MARK: Node shapes

        private static var anyNode: Node {
            Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList))
        }

        private static func type(_ node: Node) -> Node {
            node.kind == .type ? node : Node.createTransient(kind: .type, child: node)
        }

        private static func module(_ name: String) -> Node {
            Node.createTransient(kind: .module, text: name)
        }

        private static func structure(module moduleName: String, name: String) -> Node {
            Node.createTransient(kind: .structure, children: [module(moduleName), Node.createTransient(kind: .identifier, text: name)])
        }

        private static func swiftStructure(_ name: String) -> Node {
            structure(module: "Swift", name: name)
        }

        private static func boundGenericStructure(_ structure: Node, arguments: [Node]) -> Node {
            Node.createTransient(kind: .boundGenericStructure, children: [
                type(structure),
                Node.createTransient(kind: .typeList, children: arguments.map(type)),
            ])
        }

        private static func optional(_ wrapped: Node, enumName: String = "Optional") -> Node {
            type(Node.createTransient(kind: .boundGenericEnum, children: [
                type(Node.createTransient(kind: .enum, children: [module("Swift"), Node.createTransient(kind: .identifier, text: enumName)])),
                Node.createTransient(kind: .typeList, child: type(wrapped)),
            ]))
        }

        private static func implicitlyUnwrapped(_ wrapped: Node) -> Node {
            optional(wrapped, enumName: "ImplicitlyUnwrappedOptional")
        }
    }
}
