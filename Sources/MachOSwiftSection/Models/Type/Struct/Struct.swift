import Foundation
import MachOKit

public struct Struct {
    public let descriptor: StructDescriptor
    
    public init(descriptor: StructDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
    }
}
