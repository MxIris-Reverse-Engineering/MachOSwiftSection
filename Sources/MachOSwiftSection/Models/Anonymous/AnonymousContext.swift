import Foundation
import MachOKit 
import MachOFoundation
import MachOMacro

public struct AnonymousContext {
    public let descriptor: AnonymousContextDescriptor
    public let genericContext: GenericContext?
    public let mangledName: MangledName?
    
    @MachOImageGenerator
    public init(descriptor: AnonymousContextDescriptor, in machOFile: MachOFile) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize
        
        let genericContext = try descriptor.genericContext(in: machOFile)
        
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext
        
        if descriptor.hasMangledName {
            let mangledNamePointer: RelativeDirectPointer<MangledName> = try  machOFile.readElement(offset: currentOffset)
            self.mangledName = try mangledNamePointer.resolve(from: currentOffset, in: machOFile)
            currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
        } else {
            self.mangledName = nil
        }
    }
}
