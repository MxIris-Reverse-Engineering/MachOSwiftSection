import Foundation

public protocol _SwiftClassLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var flags: UInt32 { get }
    var parent: Int32 { get }
    var name: Int32 { get }
    var accessFunction: Int32 { get }
    var fieldDescriptor: Int32 { get }
    var superclassType: Int32 { get }
    var metadataNegativeSizeInWords: UInt32 { get }
    var metadataPositiveSizeInWords: UInt32 { get }
    var numImmediateMembers: UInt32 { get }
    var numFields: UInt32 { get }
}

public enum SwiftClassLayoutField {
    case flags
    case parent
    case name
    case accessFunction
    case fieldDescriptor
    case superclassType
    case metadataNegativeSizeInWords
    case metadataPositiveSizeInWords
    case numImmediateMembers
    case numFields
}

