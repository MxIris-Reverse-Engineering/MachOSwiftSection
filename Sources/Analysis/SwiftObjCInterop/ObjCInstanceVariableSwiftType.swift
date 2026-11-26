import MachOSwiftSection
@_spi(Internals) import Demangling

/// The Swift type of an `@objc @implementation` stored property, read off
/// the Objective-C side once the image no longer carries the property's
/// field-offset symbol (evolution proposal `objc-ivar-type-recovery`).
///
/// The compiler writes a stored property's ivar encoding in one of three
/// ways (`buildIvar` in IRGen's `GenClass.cpp`): empty when the property is
/// not `@objc`; `?` when its type is bridged to a separate Objective-C type;
/// and otherwise the property type's own encoding — which it only writes for
/// a type Objective-C represents as it is (`isTriviallyRepresentableIn`), so
/// that Objective-C type IS the Swift type. A `?` ivar's Swift type is the
/// bridged form of the Objective-C property synthesized on it, whose `T`
/// attribute the same function encodes. Neither says whether an object is
/// optional, so a type that can be `nil` reads `T!`, as ClangImporter spells
/// an unannotated declaration — `T?` for a `weak` property, which must be
/// optional.
package struct ObjCInstanceVariableSwiftType {
    /// Where the type was read.
    package enum Source: Sendable, Hashable {
        /// The ivar's own type encoding.
        case instanceVariableEncoding
        /// The `T` attribute of the Objective-C property synthesized on the
        /// ivar, for an ivar the compiler marked `?`.
        case objcProperty
    }

    /// The property's `Type` node, its unknown nullability spelled.
    package let typeNode: Node
    package let source: Source
    /// The Objective-C type the Swift type was read from, which tells a
    /// printer when the type is a C primitive it may spell otherwise.
    package let encodedType: ObjCEncodedType
    /// The Objective-C property offers no setter.
    package let isReadOnly: Bool
    /// The Objective-C property is `weak`.
    package let isWeak: Bool

    /// The type of `instanceVariable`, given the Objective-C property
    /// synthesized on it (`ObjCImplementationClassFacts.objcProperty(storedIn:swiftPropertyName:)`);
    /// `nil` when the Objective-C side does not say.
    package init?(instanceVariable: ObjCImplementationClassFacts.InstanceVariable, objcProperty: ObjCImplementationClassFacts.Property?, in machO: some MachOSwiftSectionRepresentableWithCache) {
        let importedTypes = ObjCImportedTypes(machO: machO)
        let isWeak = objcProperty?.isWeak ?? false
        let encodedType: ObjCEncodedType
        let typeNode: Node
        // An empty encoding: the property is not `@objc`, and nothing in the
        // binary says what its type is.
        guard instanceVariable.isObjCVisible else { return nil }
        if instanceVariable.typeEncoding == "?" {
            // Bridged: the Objective-C property says to what. A `weak`
            // property's storage is marked `?` whatever its class, and
            // `weak` holds only a class, which no bridging changes.
            guard let objcProperty,
                  let propertyType = ObjCTypeEncodingParser.propertyType(fromAttributes: objcProperty.attributes),
                  let propertyTypeNode = isWeak
                  ? importedTypes.triviallyRepresentedTypeNode(propertyType, position: .weakStorage)
                  : importedTypes.bridgedTypeNode(propertyType, position: .topLevel)
            else { return nil }
            encodedType = propertyType
            typeNode = propertyTypeNode
            self.source = .objcProperty
        } else {
            guard let instanceVariableType = ObjCTypeEncodingParser.type(from: instanceVariable.typeEncoding),
                  let instanceVariableTypeNode = importedTypes.triviallyRepresentedTypeNode(instanceVariableType, position: isWeak ? .weakStorage : .topLevel)
            else { return nil }
            encodedType = instanceVariableType
            typeNode = instanceVariableTypeNode
            self.source = .instanceVariableEncoding
        }
        self.typeNode = typeNode
        self.encodedType = encodedType
        self.isReadOnly = objcProperty?.isReadOnly ?? false
        self.isWeak = isWeak
    }
}
