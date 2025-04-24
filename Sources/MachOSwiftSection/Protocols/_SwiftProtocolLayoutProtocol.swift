import Foundation

public protocol _SwiftProtocolLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var flags: UInt32 { get }
    var parent: Int32 { get }
    var name: Int32 { get }
    var numRequirementsInSignature: UInt32 { get }
    var numRequirements: UInt32 { get }
    var associatedTypes: Int32 { get }
}

public enum SwiftProtocolLayoutField {
    case flags
    case parent
    case name
    case numRequirementsInSignature
    case numRequirements
    case associatedTypes
}





