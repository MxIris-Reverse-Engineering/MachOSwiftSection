import Foundation
import MachOKit

public protocol GenericContextDescriptorHeaderProtocol: ResolvableLocatableLayoutWrapper where Layout: GenericContextDescriptorHeaderLayout {}

public protocol GenericContextDescriptorHeaderLayout {
    var numParams: UInt16 { get }
    var numRequirements: UInt16 { get }
    var numKeyArguments: UInt16 { get }
    var flags: GenericContextDescriptorFlags { get }
}
