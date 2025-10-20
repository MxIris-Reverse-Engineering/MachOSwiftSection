import MachOKit

public protocol LayoutProtocol: Sendable, Equatable {}

public protocol LocatableLayoutWrapper: LayoutWrapper, Sendable, Equatable where Layout: LayoutProtocol {
    var offset: Int { get }

    init(layout: Layout, offset: Int)
}

extension LocatableLayoutWrapper {
    package func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }
    
    package func pointer(in machO: MachOImage) -> UnsafeRawPointer {
        return machO.ptr + UnsafeRawPointer.Stride(offset)
    }
}
