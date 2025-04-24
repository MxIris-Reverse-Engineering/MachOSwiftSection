import Foundation

public protocol _SwiftNominalTypeLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var flags: UInt32 { get }
    var parent: Int32 { get }
    var name: Int32 { get }
    var accessFunction: Int32 { get }
    var fieldDescriptor: Int32 { get }
}

public enum SwiftNominalTypeLayoutField {
    case flags
    case parent
    case name
    case accessFunction
    case fieldDescriptor
}

