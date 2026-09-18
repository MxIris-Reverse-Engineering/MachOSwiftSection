import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct RelativeObjCProtocolPrefix: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let isa: RelativeDirectRawPointer
        public let mangledName: RelativeDirectPointer<MangledName>
    }
}

extension RelativeObjCProtocolPrefix {
    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        return try layout.mangledName.resolve(from: offset(of: \.mangledName), in: machO)
    }

    public func mangledName() throws -> MangledName {
        return try layout.mangledName.resolve(from: pointer(of: \.mangledName))
    }
}

// MARK: - ReadingContext Support

extension RelativeObjCProtocolPrefix {
    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.mangledName))
        return try layout.mangledName.resolve(at: baseAddress, in: context)
    }
}
