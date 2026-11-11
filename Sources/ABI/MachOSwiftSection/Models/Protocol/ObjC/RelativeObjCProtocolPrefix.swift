import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct RelativeObjCProtocolPrefix {
    public struct Layout: LayoutProtocol {
        public let isa: RelativeDirectRawPointer
        public let mangledName: RelativeDirectPointer<MangledName>
    }
}

// MARK: - ReadingContext Support

extension RelativeObjCProtocolPrefix {
    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.mangledName))
        return try layout.mangledName.resolve(at: baseAddress, in: context)
    }
}
