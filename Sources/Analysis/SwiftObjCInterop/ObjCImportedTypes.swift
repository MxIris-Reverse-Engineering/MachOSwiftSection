import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling

/// The Swift types the importer gives Objective-C types, as `Type` nodes the
/// member printers print (evolution proposals `swift-declared-objc-protocols`
/// and `objc-imported-declarations`): Foundation's bridged classes import as
/// their Swift value types, `id` as `Any`, a block as a closure, a Swift class
/// or protocol by its Swift name. An object type's nullability is not
/// recorded, so it is `T!` — what the importer makes of an unannotated
/// declaration — and `T?` inside a closure's signature, where `!` cannot be
/// written.
package struct ObjCImportedTypes<MachO: MachOSwiftSectionRepresentableWithCache> {
    /// Where a type appears, which decides how its unknown nullability reads.
    package enum Position {
        /// A parameter, a result or a property: `T!`.
        case topLevel
        /// A closure's parameter or result: `T?`, as `!` cannot nest.
        case closureComponent
        /// A result the error convention proves non-nil.
        case nonOptional
    }

    /// The image the names are resolved in: a Swift class or protocol is
    /// found under the name the Objective-C runtime knows it by.
    package let machO: MachO

    package init(machO: MachO) {
        self.machO = machO
    }

    /// A `Type` node for `type` in `position`.
    package func typeNode(_ type: ObjCEncodedType, position: Position) -> Node {
        let base = Self.type(bareTypeNode(type))
        guard Self.isNullable(type) else { return base }
        switch position {
        case .topLevel: return Self.implicitlyUnwrapped(base)
        case .closureComponent: return Self.optional(base)
        case .nonOptional: return base
        }
    }

    /// `instancetype`, of unknown nullability, as an initializer's result:
    /// `Self!`.
    package static var initializerResultTypeNode: Node {
        implicitlyUnwrapped(type(Node.createTransient(kind: .dependentGenericParamType, children: [
            Node.createTransient(kind: .index, index: 0),
            Node.createTransient(kind: .index, index: 0),
        ])))
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
        let protocols = protocolNames.map { Self.type(ObjCRuntimeNames.protocolNode(forRuntimeName: $0, in: machO)) }
        guard let className else {
            // `id`, `id<P>`, `id<P, Q>`.
            return Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList, children: protocols))
        }
        if !protocols.isEmpty {
            // `NSObject<P> *` imports as `NSObject & P`.
            return Node.createTransient(kind: .protocolListWithClass, children: [
                Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList, children: protocols)),
                Self.type(ObjCRuntimeNames.classNode(forRuntimeName: className, in: machO)),
            ])
        }
        if let bridged = ObjCBridgedStructures.structuresByClassName[className] {
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
            return ObjCRuntimeNames.classNode(forRuntimeName: className, in: machO)
        }
    }

    // MARK: Node shapes

    private static var anyNode: Node {
        Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList))
    }

    /// `node` wrapped in a `Type` node, unless it is one.
    package static func type(_ node: Node) -> Node {
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

/// The Foundation classes the importer bridges to Swift value types. Kept out
/// of `ObjCImportedTypes`, which is generic and so cannot hold a static
/// stored property.
package enum ObjCBridgedStructures {
    /// Whether the importer gives the class a type that is no class: a
    /// bridged value type, one of the three collections, or `Error`.
    package static func importsAsNonClassType(_ className: String) -> Bool {
        structuresByClassName[className] != nil || ["NSArray", "NSDictionary", "NSSet", "NSError"].contains(className)
    }

    static let structuresByClassName: [String: (module: String, name: String)] = [
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
}
