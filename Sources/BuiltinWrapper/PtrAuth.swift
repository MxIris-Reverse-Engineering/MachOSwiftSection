import Swift

/// Pseudo-namespace for pointer authentication primitives.
package enum _PtrAuth {
    package struct Key {
        var _value: Int32

        @_transparent
        init(_value: Int32) {
            self._value = _value
        }

        #if _ptrauth(_arm64e)
        @_transparent
        package static var ASIA: Key { return Key(_value: 0) }
        @_transparent
        package static var ASIB: Key { return Key(_value: 1) }
        @_transparent
        package static var ASDA: Key { return Key(_value: 2) }
        @_transparent
        package static var ASDB: Key { return Key(_value: 3) }

        /// A process-independent key which can be used to sign code pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processIndependentCode: Key { return .ASIA }

        /// A process-specific key which can be used to sign code pointers.
        /// Signing and authenticating with this key is enforced even in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processDependentCode: Key { return .ASIB }

        /// A process-independent key which can be used to sign data pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processIndependentData: Key { return .ASDA }

        /// A process-specific key which can be used to sign data pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processDependentData: Key { return .ASDB }
        #elseif _ptrauth(_none)
        /// A process-independent key which can be used to sign code pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processIndependentCode: Key { return Key(_value: 0) }

        /// A process-specific key which can be used to sign code pointers.
        /// Signing and authenticating with this key is enforced even in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processDependentCode: Key { return Key(_value: 0) }

        /// A process-independent key which can be used to sign data pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processIndependentData: Key { return Key(_value: 0) }

        /// A process-specific key which can be used to sign data pointers.
        /// Signing and authenticating with this key is a no-op in processes
        /// which disable ABI pointer authentication.
        @_transparent
        package static var processDependentData: Key { return Key(_value: 0) }
        #else
        #error("unsupported ptrauth scheme")
        #endif
    }

    #if _ptrauth(_arm64e)
    /// Blend a pointer and a small integer to form a new extra-data
    /// discriminator.  Not all bits of the inputs are guaranteed to
    /// contribute to the result.
    @_transparent
    @_alwaysEmitIntoClient
    package static func blend(
        pointer: UnsafeRawPointer,
        discriminator: UInt64
    ) -> UInt64 {
        return UInt64(Builtin.int_ptrauth_blend(
            UInt64(UInt(bitPattern: pointer))._value,
            discriminator._value
        ))
    }

    /// Sign an unauthenticated pointer.
    @_semantics("no.preserve.debugger") // Relies on inlining this function.
    @_transparent
    @_alwaysEmitIntoClient
    package static func sign(
        pointer: UnsafeRawPointer,
        key: Key,
        discriminator: UInt64
    ) -> UnsafeRawPointer {
        let bitPattern = UInt64(Builtin.int_ptrauth_sign(
            UInt64(UInt(bitPattern: pointer))._value,
            key._value._value,
            discriminator._value
        ))

        return unsafe UnsafeRawPointer(bitPattern:
            UInt(truncatingIfNeeded: bitPattern)).unsafelyUnwrapped
    }

    /// Authenticate a pointer using one scheme and resign it using another.
    @_transparent
    @_semantics("no.preserve.debugger") // Relies on inlining this function.
    @_alwaysEmitIntoClient
    package static func authenticateAndResign(
        pointer: UnsafeRawPointer,
        oldKey: Key,
        oldDiscriminator: UInt64,
        newKey: Key,
        newDiscriminator: UInt64
    ) -> UnsafeRawPointer {
        let bitPattern = UInt64(Builtin.int_ptrauth_resign(
            UInt64(UInt(bitPattern: pointer))._value,
            oldKey._value._value,
            oldDiscriminator._value,
            newKey._value._value,
            newDiscriminator._value
        ))

        return unsafe UnsafeRawPointer(bitPattern:
            UInt(truncatingIfNeeded: bitPattern)).unsafelyUnwrapped
    }

    package static func metadataAccessorDiscriminator() -> UInt64 {
//        typealias MetadataAccessor = (Int) -> UnsafeRawPointer
//        return discriminator(for: MetadataAccessor.self)
        return 0
    }
    
    /// Get the type-specific discriminator for a function type.
//    @_semantics("no.preserve.debugger") // Don't keep the generic version alive
//    @_transparent
//    static func discriminator<T>(for type: T.Type) -> UInt64 {
//        return UInt64(Builtin.typePtrAuthDiscriminator(type))
//    }

    #elseif _ptrauth(_none)
    /// Blend a pointer and a small integer to form a new extra-data
    /// discriminator.  Not all bits of the inputs are guaranteed to
    /// contribute to the result.
    @_transparent
    package static func blend(
        pointer _: UnsafeRawPointer,
        discriminator _: UInt64
    ) -> UInt64 {
        return 0
    }

    /// Sign an unauthenticated pointer.
    @_transparent
    package static func sign(
        pointer: UnsafeRawPointer,
        key: Key,
        discriminator: UInt64
    ) -> UnsafeRawPointer {
        return unsafe pointer
    }

    /// Authenticate a pointer using one scheme and resign it using another.
    @_transparent
    package static func authenticateAndResign(
        pointer: UnsafeRawPointer,
        oldKey: Key,
        oldDiscriminator: UInt64,
        newKey: Key,
        newDiscriminator: UInt64
    ) -> UnsafeRawPointer {
        return unsafe pointer
    }

    /// Get the type-specific discriminator for a function type.
//    @_transparent
//    static func discriminator<T>(for type: T.Type) -> UInt64 {
//        return 0
//    }
    
    package static func metadataAccessorDiscriminator() -> UInt64 {
        return 0
    }
    
    #else
    #error("Unsupported ptrauth scheme")
    #endif
}

// Helpers for working with authenticated function pointers.

//extension UnsafeRawPointer {
//    /// Load a function pointer from memory that has been authenticated
//    /// specifically for its given address.
//    @_semantics("no.preserve.debugger") // Don't keep the generic version alive
//    @_transparent
//    package func _loadAddressDiscriminatedFunctionPointer<T>(
//        fromByteOffset offset: Int = 0,
//        as type: T.Type,
//        discriminator: UInt64
//    ) -> T {
//        let src = unsafe self + offset
//
//        let srcDiscriminator = unsafe _PtrAuth.blend(
//            pointer: src,
//            discriminator: discriminator
//        )
//        let ptr = unsafe src.load(as: UnsafeRawPointer.self)
//        let resigned = unsafe _PtrAuth.authenticateAndResign(
//            pointer: ptr,
//            oldKey: .processIndependentCode,
//            oldDiscriminator: srcDiscriminator,
//            newKey: .processIndependentCode,
//            newDiscriminator: _PtrAuth.discriminator(for: type)
//        )
//
//        return unsafe unsafeBitCast(resigned, to: type)
//    }
//
//    @_semantics("no.preserve.debugger") // Don't keep the generic version alive
//    @_transparent
//    package func _loadAddressDiscriminatedFunctionPointer<T>(
//        fromByteOffset offset: Int = 0,
//        as type: T?.Type,
//        discriminator: UInt64
//    ) -> T? {
//        let src = unsafe self + offset
//
//        let srcDiscriminator = unsafe _PtrAuth.blend(
//            pointer: src,
//            discriminator: discriminator
//        )
//        guard let ptr = unsafe src.load(as: UnsafeRawPointer?.self) else {
//            return nil
//        }
//        let resigned = unsafe _PtrAuth.authenticateAndResign(
//            pointer: ptr,
//            oldKey: .processIndependentCode,
//            oldDiscriminator: srcDiscriminator,
//            newKey: .processIndependentCode,
//            newDiscriminator: _PtrAuth.discriminator(for: T.self)
//        )
//
//        return unsafe T?.some(unsafeBitCast(resigned, to: T.self))
//    }
//    
//    package static func metadataAccessorDiscriminator() -> UInt64 {
//        return 0
//    }
//}
//
//extension UnsafeMutableRawPointer {
//    /// Copy a function pointer from memory that has been authenticated
//    /// specifically for its given address.
//    package func _copyAddressDiscriminatedFunctionPointer(
//        from src: UnsafeRawPointer,
//        discriminator: UInt64
//    ) {
//        if unsafe src == UnsafeRawPointer(self) { return }
//
//        let srcDiscriminator = unsafe _PtrAuth.blend(
//            pointer: src,
//            discriminator: discriminator
//        )
//        let destDiscriminator = unsafe _PtrAuth.blend(
//            pointer: self,
//            discriminator: discriminator
//        )
//
//        let ptr = unsafe src.load(as: UnsafeRawPointer.self)
//        let resigned = unsafe _PtrAuth.authenticateAndResign(
//            pointer: ptr,
//            oldKey: .processIndependentCode,
//            oldDiscriminator: srcDiscriminator,
//            newKey: .processIndependentCode,
//            newDiscriminator: destDiscriminator
//        )
//
//        unsafe storeBytes(of: resigned, as: UnsafeRawPointer.self)
//    }
//
//    @_transparent
//    package func _storeFunctionPointerWithAddressDiscrimination(
//        _ unsignedPointer: UnsafeRawPointer,
//        discriminator: UInt64
//    ) {
//        let destDiscriminator = unsafe _PtrAuth.blend(
//            pointer: self,
//            discriminator: discriminator
//        )
//        let signed = unsafe _PtrAuth.sign(
//            pointer: unsignedPointer,
//            key: .processIndependentCode,
//            discriminator: destDiscriminator
//        )
//        unsafe storeBytes(of: signed, as: UnsafeRawPointer.self)
//    }
//}
