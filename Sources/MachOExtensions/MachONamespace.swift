import Foundation

package struct MachONamespace<Base> {
    package let base: Base

    package init(_ base: Base) {
        self.base = base
    }
}

package protocol MachONamespacing {}

extension MachONamespacing {
    package var machO: MachONamespace<Self> {
        set {}
        get { MachONamespace(self) }
    }

    package static var machO: MachONamespace<Self>.Type {
        set {}
        get { MachONamespace.self }
    }
}
