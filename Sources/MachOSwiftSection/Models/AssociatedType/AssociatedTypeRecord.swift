import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct AssociatedTypeRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: Sendable {
        public let name: RelativeDirectPointer<String>
        public let substitutedTypeName: RelativeDirectPointer<MangledName>
    }

    public var layout: Layout

    public var offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension AssociatedTypeRecord {
    public func name<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> String {
        return try layout.name.resolve(from: offset(of: \.name), in: machO)
    }

    public func substitutedTypeName<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> MangledName {
        return try layout.substitutedTypeName.resolve(from: offset(of: \.substitutedTypeName), in: machO)
    }
}
