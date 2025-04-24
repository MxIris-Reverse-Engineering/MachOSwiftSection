import Foundation

public protocol _SwiftEnumLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var flags: UInt32 { get }
    var parent: Int32 { get }
    var name: Int32 { get }
    var accessFunction: Int32 { get }
    var fieldDescriptor: Int32 { get }
    var numPayloadCasesAndPayloadSizeOffset: UInt32 { get }
    var numEmptyCases: UInt32 { get }
}

public enum SwiftEnumLayoutField {
    case flags
    case parent
    case name
    case accessFunction
    case fieldDescriptor
    case numPayloadCasesAndPayloadSizeOffset
    case numEmptyCases
}
