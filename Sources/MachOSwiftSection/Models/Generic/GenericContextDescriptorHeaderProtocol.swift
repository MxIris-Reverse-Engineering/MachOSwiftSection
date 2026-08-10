import Foundation
import MachOKit
import MachOKitExtensions

public protocol GenericContextDescriptorHeaderProtocol: ResolvableLocatableLayoutWrapper where Layout: GenericContextDescriptorHeaderLayout {}

public protocol GenericContextDescriptorHeaderLayout: LayoutProtocol {
    var numParams: UInt16 { get }
    var numRequirements: UInt16 { get }
    var numKeyArguments: UInt16 { get }
    var flags: GenericContextDescriptorFlags { get }
}
