import MachOKit

public protocol LayoutWrapperWithOffset: LayoutWrapper {
    var offset: Int { get }
    
    init(layout: Layout, offset: Int)
}

extension LayoutWrapperWithOffset {
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }
    
    public func resolvedRelativeOffset(of keyPath: KeyPath<Layout, RelativeOffset>) -> Int {
        return numericCast(offset(of: keyPath) + layout[keyPath: keyPath].cast())
    }
}
