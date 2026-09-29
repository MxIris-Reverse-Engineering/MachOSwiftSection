// Throwing counterparts of the standard library's failable `init(bitPattern:)`.
//
// They used to be public in MachOKitExtensions. Swift makes an imported
// module's extension members visible in every file of the importing module, so
// there they shadowed the failable initializer in every module that imported
// the package — MachOObjCSection's core target among them. This package is the
// only one that calls them, and `package` keeps them inside it.

extension UnsafeRawPointer {
    package enum Error: Swift.Error {
        case initFailed
    }

    package init(bitPattern: UInt) throws {
        guard let pointer = Self(bitPattern: bitPattern) else {
            throw Error.initFailed
        }
        self = pointer
    }

    package init(bitPattern: Int) throws {
        guard let pointer = Self(bitPattern: bitPattern) else {
            throw Error.initFailed
        }
        self = pointer
    }
}

extension UnsafePointer {
    package enum Error: Swift.Error {
        case initFailed
    }

    package init(bitPattern: UInt) throws {
        guard let pointer = Self(bitPattern: bitPattern) else {
            throw Error.initFailed
        }
        self = pointer
    }

    package init(bitPattern: Int) throws {
        guard let pointer = Self(bitPattern: bitPattern) else {
            throw Error.initFailed
        }
        self = pointer
    }
}
