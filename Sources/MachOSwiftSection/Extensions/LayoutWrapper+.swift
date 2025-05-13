import Foundation
import MachOKit

extension LayoutWrapper {
    func layoutOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let pKeyPath: PartialKeyPath<Layout> = keyPath
        return layoutOffset(of: pKeyPath)
    }
}

extension LayoutWrapper {
//    @_spi(Support)
    static var layoutSize: Int {
        MemoryLayout<Layout>.size
    }

//    @_spi(Support)
    var layoutSize: Int {
        MemoryLayout<Layout>.size
    }
}

extension LayoutWrapper {
//    @_spi(Support)
    static func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }

//    @_spi(Support)
    func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }
}


