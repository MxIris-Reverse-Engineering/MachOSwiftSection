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
        /// A `weak` property: `T?`, as `weak` requires an optional.
        case weakStorage
    }

    /// How an Objective-C type maps to a Swift one.
    private enum Mapping {
        /// As the importer imports a declaration: Foundation's bridged
        /// classes become their Swift value types and `id` is `Any`.
        case imported
        /// As the Swift type behind an `@objc @implementation` ivar's complete
        /// encoding, which the compiler only writes for a type Objective-C
        /// represents as it is (evolution proposal `objc-ivar-type-recovery`):
        /// no class is bridged and `id` is `AnyObject`.
        case triviallyRepresented
    }

    /// The image the names are resolved in: a Swift class or protocol is
    /// found under the name the Objective-C runtime knows it by.
    package let machO: MachO

    package init(machO: MachO) {
        self.machO = machO
    }

    /// A `Type` node for `type` in `position`.
    package func typeNode(_ type: ObjCEncodedType, position: Position) -> Node {
        typeNode(type, position: position, mapping: .imported)
    }

    /// The Swift type of an `@objc @implementation` stored property whose
    /// ivar carries the complete encoding `type` (evolution proposal
    /// `objc-ivar-type-recovery`): the compiler writes one only for a type
    /// Objective-C represents as it is, so `NSString` stays `NSString` and
    /// `id` is `AnyObject`. `nil` for a type the encoding does not
    /// determine: a block, whose signature no ivar encoding carries, a
    /// pointer to a structure (a CF type reads the same), a bit field, an
    /// unnamed structure, an array the importer cannot represent, or one the
    /// reader does not know.
    package func triviallyRepresentedTypeNode(_ type: ObjCEncodedType, position: Position) -> Node? {
        guard Self.determinesStoredPropertyType(type) else { return nil }
        return typeNode(type, position: position, mapping: .triviallyRepresented)
    }

    /// The Swift type of an `@objc @implementation` stored property whose
    /// ivar the compiler marked `?` — a type bridged to a separate
    /// Objective-C one — read off the `T` attribute of the Objective-C
    /// property synthesized on it (evolution proposal
    /// `objc-ivar-type-recovery`): the type the importer gives that
    /// Objective-C type, `NSString` as `String`, `NSArray` as `[Any]` (the
    /// attribute names no element type), `id` as `Any`. The `?` proves the
    /// Swift type is no class Objective-C has, so only a class the importer
    /// bridges and a bare `id` qualify; anything else — a class imported as
    /// itself, which an `unowned` property's storage also marks `?`, a
    /// Foundation class bridged to a value type the table does not list —
    /// returns `nil`.
    package func bridgedTypeNode(_ type: ObjCEncodedType, position: Position) -> Node? {
        guard case .object(let className, let protocolNames) = type, protocolNames.isEmpty else { return nil }
        if let className, !ObjCBridgedStructures.importsAsNonClassType(className) { return nil }
        return typeNode(type, position: position, mapping: .imported)
    }

    private func typeNode(_ type: ObjCEncodedType, position: Position, mapping: Mapping) -> Node {
        let base = Self.type(bareTypeNode(type, mapping: mapping))
        guard Self.isNullable(type) else { return base }
        switch position {
        case .topLevel: return Self.implicitlyUnwrapped(base)
        case .closureComponent, .weakStorage: return Self.optional(base)
        case .nonOptional: return base
        }
    }

    /// Whether `type` names one Swift type a stored property can have. A
    /// pointer does only to `void` or a scalar: the importer gives a pointer
    /// to an object, a pointer or a structure a type of its own
    /// (`AutoreleasingUnsafeMutablePointer`, an optional pointee, a CF class).
    private static func determinesStoredPropertyType(_ type: ObjCEncodedType) -> Bool {
        switch type {
        case .void, .block, .bitField, .unknown: false
        case .structure(let name), .union(let name): name != nil
        case .array(_, let element): flattenedElementCount(of: type) != nil && determinesStoredPropertyType(element)
        case .pointer(let pointee, _): pointee == .void || isScalar(pointee)
        default: true
        }
    }

    private static func isScalar(_ type: ObjCEncodedType) -> Bool {
        switch type {
        case .bool, .character, .unsignedCharacter, .short, .unsignedShort, .int, .unsignedInt, .long, .unsignedLong, .longLong, .unsignedLongLong, .float, .double, .longDouble: true
        default: false
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
    private func bareTypeNode(_ type: ObjCEncodedType, mapping: Mapping = .imported) -> Node {
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
        case .characterString(let isConst): return Self.boundGenericStructure(Self.swiftStructure(isConst ? "UnsafePointer" : "UnsafeMutablePointer"), arguments: [Self.swiftStructure("Int8")])
        case .selector: return Self.structure(module: "ObjectiveC", name: "Selector")
        case .objectClass: return Node.createTransient(kind: .typeAlias, children: [Self.module("Swift"), Node.createTransient(kind: .identifier, text: "AnyClass")])
        case .object(let className, let protocolNames): return objectNode(className: className, protocolNames: protocolNames, mapping: mapping)
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
            // ClangImporter imports a pointer to what it cannot represent as
            // `OpaquePointer`.
            case .array where Self.flattenedElementCount(of: pointee) == nil: return Self.swiftStructure("OpaquePointer")
            default: return Self.boundGenericStructure(Self.swiftStructure(isConst ? "UnsafePointer" : "UnsafeMutablePointer"), arguments: [bareTypeNode(pointee, mapping: mapping)])
            }
        case .structure(let name), .union(let name):
            guard let name else { return Self.swiftStructure("OpaquePointer") }
            return Self.structure(module: objcModule, name: name)
        case .array(let count, let element):
            // A C array imports as a tuple of its elements, a single element
            // as the element itself; one it cannot represent, as nothing.
            guard Self.flattenedElementCount(of: type) != nil else { return Self.anyNode }
            if count == 1 { return bareTypeNode(element, mapping: mapping) }
            return Node.createTransient(kind: .tuple, children: (0 ..< count).map { _ in
                Node.createTransient(kind: .tupleElement, child: Self.type(bareTypeNode(element, mapping: mapping)))
            })
        case .bitField, .unknown:
            return Self.anyNode
        }
    }

    /// ClangImporter imports a C array of at most this many elements, as a
    /// tuple, and no longer one (`VisitConstantArrayType`).
    static var maximumImportedArrayCount: Int { 4096 }

    /// The most elements nested arrays may flatten to. Each level within
    /// ClangImporter's limit still multiplies, and a tuple of tuples past
    /// this would take for ever to build and print — what an encoding
    /// crafted to do so asks for — so past it the type reads as one the
    /// importer cannot represent.
    static var maximumFlattenedArrayElementCount: Int { 65_536 }

    /// How many elements `type` flattens to — 1 for anything but an array —
    /// or `nil` for an array ClangImporter cannot represent, or one past
    /// `maximumFlattenedArrayElementCount`.
    static func flattenedElementCount(of type: ObjCEncodedType) -> Int? {
        guard case .array(let count, let element) = type else { return 1 }
        guard count >= 0, count <= maximumImportedArrayCount, let elementCount = flattenedElementCount(of: element) else { return nil }
        let (flattenedCount, overflowed) = count.multipliedReportingOverflow(by: elementCount)
        guard !overflowed, flattenedCount <= maximumFlattenedArrayElementCount else { return nil }
        return flattenedCount
    }

    private func objectNode(className: String?, protocolNames: [String], mapping: Mapping) -> Node {
        let protocols = protocolNames.map { Self.type(ObjCRuntimeNames.protocolNode(forRuntimeName: $0, in: machO)) }
        guard let className else {
            // A bare `id` a Swift type represents as it is is `AnyObject`;
            // the importer gives `Any`.
            if mapping == .triviallyRepresented, protocols.isEmpty {
                return Node.createTransient(kind: .protocolListWithAnyObject, child: Node.createTransient(kind: .protocolList, child: Node.createTransient(kind: .typeList)))
            }
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
        // A class a Swift type represents as it is is that class.
        if mapping == .triviallyRepresented {
            return ObjCRuntimeNames.classNode(forRuntimeName: className, in: machO)
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
