import Foundation

public let publicGlobalLetConstant = "global let"
public var publicGlobalVarStoredVariable = "global var"
public var publicGlobalVarComputedVariable: String {
    return "global var computed"
}

private let privateGlobalLetConstant = "private global let"
private var privateGlobalVarStoredVariable = "private global var"
private var privateGlobalVarComputedVariable: String {
    return "private global var computed"
}

internal let internalGlobalLetConstant = "internal global let"
internal var internalGlobalVarStoredVariable = "internal global var"
internal var internalGlobalVarComputedVariable: String {
    return "internal global var computed"
}

public struct Struct {
    public init() {}
    public typealias TypeAlias = String
    public static let publicStaticLetStoredProperty = "static let"
    public static var publicStaticVarStoredProperty = "static var"
    public static var publicStaticVarComputedProperty: String {
        return "static var computed"
    }

    private static let privateStaticLetStoredProperty = "private static let"
    private static var privateStaticVarStoredProperty = "private static var"
    private static var privateStaticVarComputedProperty: String {
        return "private static var computed"
    }

    internal static let internalStaticLetStoredProperty = "internal static let"
    internal static var internalStaticVarStoredProperty = "internal static var"
    internal static var internalStaticVarComputedProperty: String {
        return "internal static var computed"
    }

    public static func publicStaticFunction() {
        print(publicStaticLetStoredProperty)
        print(publicStaticVarStoredProperty)
        publicStaticVarStoredProperty = "X"
        print(publicStaticVarComputedProperty)

        print(privateStaticLetStoredProperty)
        print(privateStaticVarStoredProperty)
        privateStaticVarStoredProperty = "X"
        print(privateStaticVarComputedProperty)

        print(internalStaticLetStoredProperty)
        print(internalStaticVarStoredProperty)
        internalStaticVarStoredProperty = "X"
        print(internalStaticVarComputedProperty)
    }
}

public func publicGlobalFunction() {
    print(publicGlobalLetConstant)
    print(publicGlobalVarStoredVariable)
    publicGlobalVarStoredVariable = "X"
    print(publicGlobalVarComputedVariable)

    print(privateGlobalLetConstant)
    print(privateGlobalVarStoredVariable)
    privateGlobalVarStoredVariable = "X"
    print(privateGlobalVarComputedVariable)

    print(internalGlobalLetConstant)
    print(internalGlobalVarStoredVariable)
    internalGlobalVarStoredVariable = "X"
    print(internalGlobalVarComputedVariable)
}

extension Struct {
    public static let publicExtensionStaticLetStoredProperty = "extension static let"
    public static var publicExtensionStaticVarStoredProperty = "extension static var"
    public static var publicExtensionStaticVarComputedProperty: String {
        return "extension static var computed"
    }
}

// extension String.Index {
//    public struct NestedStruct {
//        public init() {}
//        public static let publicNestedStaticLetStoredProperty = "nested static let"
//        public static var publicNestedStaticVarStoredProperty = "nested static var"
//        public static var publicNestedStaticVarComputedProperty: String {
//            return "nested static var computed"
//        }
//    }
// }

import SymbolTestsCore

extension TestsValues {
    public struct NestedStruct {}
}

extension TestsObjects {
    public final class NestedClass {}
}

