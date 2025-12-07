import Foundation
import MachOKit
import MachOFoundation
@_spi(Core) import MachOObjCSection
import MachOSwiftSection
import Demangling

public struct ClassHierarchyDumper {
    public let machO: MachOImage

    public init(machO: MachOImage) {
        self.machO = machO
    }

    public static func dump(for classDescriptor: ClassDescriptor, in machO: MachOImage) throws -> [String] {
        try ClassHierarchyDumper(machO: machO).dump(for: classDescriptor)
    }

    public func dump(for classDescriptor: ClassDescriptor) throws -> [String] {
        var classes: [String] = []
        if let metadataAccessor = try `classDescriptor`.metadataAccessor(in: machO), !`classDescriptor`.flags.isGeneric {
            let metadata = try metadataAccessor.perform(request: .init()).value.resolve(in: machO)
            switch metadata {
            case .class(let classMetadataObjCInterop):
                try perform(classMetadata: classMetadataObjCInterop, classDescriptor: `classDescriptor`, classes: &classes)
            default:
                break
            }
        }
        return classes
    }

    private func perform(objcClass: ObjCClass64, classes: inout [String]) throws {
        if let name = objcClass.info(in: machO)?.name {
            classes.append(name.demangledString)
        }
        if let superclass = objcClass.superClass(in: machO)?.1 {
            try perform(objcClass: superclass, classes: &classes)
        }
    }

    private func perform(classMetadata: ClassMetadataObjCInterop, classDescriptor: ClassDescriptor, classes: inout [String]) throws {
        try classes.append(classDescriptor.name(in: machO))
        if let superclassMetadata = try classMetadata.superclass(in: machO) {
            if superclassMetadata.isPureObjC {
                let objcClass = try ObjCClass64.resolve(from: superclassMetadata.offset, in: machO)
                try perform(objcClass: objcClass, classes: &classes)
            } else if let superclassDescriptor = try superclassMetadata.asFinalClassMetadata(in: machO).descriptor(in: machO) {
                try perform(classMetadata: superclassMetadata.asFinalClassMetadata(in: machO), classDescriptor: superclassDescriptor, classes: &classes)
            }
        }
    }
}

extension ObjCClass64: @retroactive Equatable {
    public static func == (lhs: ObjCClass64, rhs: ObjCClass64) -> Bool {
        lhs.offset == rhs.offset && lhs.layout == rhs.layout
    }
}

extension ObjCClass64: LocatableLayoutWrapper, Resolvable, @unchecked @retroactive Sendable {}

extension ObjCClass64.Layout: @retroactive Equatable {
    public static func == (lhs: ObjCClass64.Layout, rhs: ObjCClass64.Layout) -> Bool {
        lhs.isa == rhs.isa &&
            lhs.superclass == rhs.superclass &&
            lhs.methodCacheBuckets == rhs.methodCacheBuckets &&
            lhs.methodCacheProperties == rhs.methodCacheProperties &&
            lhs.swiftClassFlags == rhs.swiftClassFlags
    }
}

extension ObjCClass64.Layout: LayoutProtocol, @unchecked @retroactive Sendable {}

extension String {
    fileprivate var demangledString: String {
        (try? demangleAsNode(self))?.print(using: .interfaceType) ?? self
    }
}
