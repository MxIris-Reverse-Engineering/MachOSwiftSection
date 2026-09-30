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

// MARK: - ReadingContext Support

extension RelativeObjCProtocolPrefix {
    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.mangledName))
        return try layout.mangledName.resolve(at: baseAddress, in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension RelativeObjCProtocolPrefix {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: machO.context).")
    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: .inProcess).")
    public func mangledName() throws -> MangledName {
        try mangledName(in: InProcessContext.shared)
    }
}
