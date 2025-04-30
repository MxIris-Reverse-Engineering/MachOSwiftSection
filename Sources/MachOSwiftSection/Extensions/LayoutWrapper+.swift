import Foundation
@_spi(Support) import MachOKit

extension LayoutWrapper {
    public func layoutOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let pKeyPath: PartialKeyPath<Layout> = keyPath
        return layoutOffset(of: pKeyPath)
    }
}

protocol LayoutWrapperWithOffset: LayoutWrapper {
    var offset: Int { get }
}

extension LayoutWrapperWithOffset {
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + layoutOffset(of: keyPath)
    }
}
