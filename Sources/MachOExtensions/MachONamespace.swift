import Foundation

public struct MachONamespace<Base> {
    public let base: Base

    public init(_ base: Base) {
        self.base = base
    }
}

public protocol MachONamespacing {}

extension MachONamespacing {
    public var machO: MachONamespace<Self> {
        set {}
        get { MachONamespace(self) }
    }

    public static var machO: MachONamespace<Self>.Type {
        set {}
        get { MachONamespace.self }
    }
}
