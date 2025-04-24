import Foundation

public protocol _SwiftProtocolConformanceLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var protocolDescriptor: Int32 { get }
    var nominalTypeDescriptor: Int32 { get }
    var protocolWitnessTable: Int32 { get }
    var conformanceFlags: UInt32 { get }
}

public enum SwiftProtocolConformanceLayoutField {
    case protocolDescriptor
    case nominalTypeDescriptor
    case protocolWitnessTable
    case conformanceFlags
}
