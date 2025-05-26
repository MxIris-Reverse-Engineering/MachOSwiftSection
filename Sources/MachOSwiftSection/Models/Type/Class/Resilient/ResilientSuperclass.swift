import Foundation
import MachOKit
import MachOSwiftSectionMacro

public struct ResilientSuperclass: LocatableLayoutWrapper {
    public struct Layout {
        public let superclass: RelativeDirectRawPointer
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension ResilientSuperclass {
    //@MachOImageGenerator
    public func superclass(for kind: TypeReferenceKind, in machOFile: MachOFile) throws -> String? {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        let resolvedTypeReference = try typeReference.resolve(at: offset(of: \.superclass), in: machOFile)
        switch resolvedTypeReference {
        case .directTypeDescriptor(let contextDescriptorWrapper):
            return try contextDescriptorWrapper?.namedContextDescriptor?.fullname(in: machOFile)
        case .indirectTypeDescriptor(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machOFile)
            case .element(let element):
                return try element.namedContextDescriptor?.fullname(in: machOFile)
            case nil:
                return nil
            }
        case .directObjCClassName(let string):
            return string
        case .indirectObjCClass(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machOFile)
            case .element(let element):
                return try element.description.resolve(in: machOFile).fullname(in: machOFile)
            case nil:
                return nil
            }
        }
    }
}
