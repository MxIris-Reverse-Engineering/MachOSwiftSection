import Foundation
import UtilitiesC

// namespace SpecialPointerAuthDiscriminators {
//  // All of these values are the stable string hash of the corresponding
//  // variable name:
//  //   (computeStableStringHash % 65535 + 1)
//
//  /// HeapMetadataHeader::destroy
//  const uint16_t HeapDestructor = 0xbbbf;
//
//  /// Type descriptor data pointers.
//  const uint16_t TypeDescriptor = 0xae86;
//
//  /// Runtime function variables exported by the runtime.
//  const uint16_t RuntimeFunctionEntry = 0x625b;
//
//  /// Protocol conformance descriptors.
//  const uint16_t ProtocolConformanceDescriptor = 0xc6eb;
//
//  const uint16_t ProtocolDescriptor = 0xe909; // = 59657
//
//  // Type descriptors as arguments.
//  const uint16_t OpaqueTypeDescriptor = 0xbdd1; // = 48593
//  const uint16_t ContextDescriptor = 0xb5e3; // = 46563
//
//  /// Pointer to value witness table stored in type metadata.
//  ///
//  /// Computed with ptrauth_string_discriminator("value_witness_table_t").
//  const uint16_t ValueWitnessTable = 0x2e3f;
//
//  /// Extended existential type shapes.
//  const uint16_t ExtendedExistentialTypeShape = 0x5a3d; // = 23101
//  const uint16_t NonUniqueExtendedExistentialTypeShape = 0xe798; // = 59288
//
//  /// Value witness functions.
//  const uint16_t InitializeBufferWithCopyOfBuffer = 0xda4a;
//  const uint16_t Destroy = 0x04f8;
//  const uint16_t InitializeWithCopy = 0xe3ba;
//  const uint16_t AssignWithCopy = 0x8751;
//  const uint16_t InitializeWithTake = 0x48d8;
//  const uint16_t AssignWithTake = 0xefda;
//  const uint16_t DestroyArray = 0x2398;
//  const uint16_t InitializeArrayWithCopy = 0xa05c;
//  const uint16_t InitializeArrayWithTakeFrontToBack = 0x1c3e;
//  const uint16_t InitializeArrayWithTakeBackToFront = 0x8dd3;
//  const uint16_t StoreExtraInhabitant = 0x79c5;
//  const uint16_t GetExtraInhabitantIndex = 0x2ca8;
//  const uint16_t GetEnumTag = 0xa3b5;
//  const uint16_t DestructiveProjectEnumData = 0x041d;
//  const uint16_t DestructiveInjectEnumTag = 0xb2e4;
//  const uint16_t GetEnumTagSinglePayload = 0x60f0;
//  const uint16_t StoreEnumTagSinglePayload = 0xa0d1;
//
//  /// KeyPath metadata functions.
//  const uint16_t KeyPathDestroy = _SwiftKeyPath_ptrauth_ArgumentDestroy;
//  const uint16_t KeyPathCopy = _SwiftKeyPath_ptrauth_ArgumentCopy;
//  const uint16_t KeyPathEquals = _SwiftKeyPath_ptrauth_ArgumentEquals;
//  const uint16_t KeyPathHash = _SwiftKeyPath_ptrauth_ArgumentHash;
//  const uint16_t KeyPathGetter = _SwiftKeyPath_ptrauth_Getter;
//  const uint16_t KeyPathNonmutatingSetter = _SwiftKeyPath_ptrauth_NonmutatingSetter;
//  const uint16_t KeyPathMutatingSetter = _SwiftKeyPath_ptrauth_MutatingSetter;
//  const uint16_t KeyPathGetLayout = _SwiftKeyPath_ptrauth_ArgumentLayout;
//  const uint16_t KeyPathInitializer = _SwiftKeyPath_ptrauth_ArgumentInit;
//  const uint16_t KeyPathMetadataAccessor = _SwiftKeyPath_ptrauth_MetadataAccessor;
//
//  /// ObjC bridging entry points.
//  const uint16_t ObjectiveCTypeDiscriminator = 0x31c3; // = 12739
//  const uint16_t bridgeToObjectiveCDiscriminator = 0xbca0; // = 48288
//  const uint16_t forceBridgeFromObjectiveCDiscriminator = 0x22fb; // = 8955
//  const uint16_t conditionallyBridgeFromObjectiveCDiscriminator = 0x9a9b; // = 39579
//
//  /// Dynamic replacement pointers.
//  const uint16_t DynamicReplacementScope = 0x48F0; // = 18672
//  const uint16_t DynamicReplacementKey = 0x2C7D; // = 11389
//
//  /// Resume functions for yield-once coroutines that yield a single
//  /// opaque borrowed/inout value.  These aren't actually hard-coded, but
//  /// they're important enough to be worth writing in one place.
//  const uint16_t OpaqueReadResumeFunction = 56769;
//  const uint16_t OpaqueModifyResumeFunction = 3909;
//
//  /// ObjC class pointers.
//  const uint16_t ObjCISA = 0x6AE1;
//  const uint16_t ObjCSuperclass = 0xB5AB;
//
//  /// Resilient class stub initializer callback
//  const uint16_t ResilientClassStubInitCallback = 0xC671;
//
//  /// Jobs, tasks, and continuations.
//  const uint16_t JobInvokeFunction = 0xcc64; // = 52324
//  const uint16_t TaskResumeFunction = 0x2c42; // = 11330
//  const uint16_t TaskResumeContext = 0x753a; // = 30010
//  const uint16_t AsyncRunAndBlockFunction = 0x0f08; // 3848
//  const uint16_t AsyncContextParent = 0xbda2; // = 48546
//  const uint16_t AsyncContextResume = 0xd707; // = 55047
//  const uint16_t AsyncContextYield = 0xe207; // = 57863
//  const uint16_t CancellationNotificationFunction = 0x0f08; // = 3848
//  const uint16_t EscalationNotificationFunction = 0x7861; // = 30817
//  const uint16_t AsyncThinNullaryFunction = 0x0f08; // = 3848
//  const uint16_t AsyncFutureFunction = 0x720f; // = 29199
//
//  /// Swift async context parameter stored in the extended frame info.
//  const uint16_t SwiftAsyncContextExtendedFrameEntry = 0xc31a; // = 49946
//
//  // C type TaskContinuationFunction* descriminator.
//  const uint16_t ClangTypeTaskContinuationFunction = 0x2abe; // = 10942
//
//  /// Dispatch integration.
//  const uint16_t DispatchInvokeFunction = 0xf493; // = 62611
//
//  /// Functions accessible at runtime (i.e. distributed method accessors).
//  const uint16_t AccessibleFunctionRecord = 0x438c; // = 17292
//
//  /// C type GetExtraInhabitantTag function descriminator
//  const uint16_t GetExtraInhabitantTagFunction = 0x392e; // = 14638
//
//  /// C type StoreExtraInhabitantTag function descriminator
//  const uint16_t StoreExtraInhabitantTagFunction = 0x9bf6; // = 39926
//
//  // Relative protocol witness table descriminator
//  const uint16_t RelativeProtocolWitnessTable = 0xb830; // = 47152
//
//  const uint16_t TypeLayoutString = 0x8b65; // = 35685
//
//  /// Isolated deinit body function pointer
//  const uint16_t DeinitWorkFunction = 0x8438; // = 33848
//
//  /// IsCurrentGlobalActor function used between the Swift runtime and
//  /// concurrency runtime.
//  const uint16_t IsCurrentGlobalActorFunction = 0xd1b8; // = 53688
// }

package struct SpecialPointerAuthDiscriminators: RawRepresentable {
    package let rawValue: UInt64

    package init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    package init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    package static let zero = SpecialPointerAuthDiscriminators(rawValue: 0)
    package static let heapDestructor = SpecialPointerAuthDiscriminators(rawValue: 0xBBBF)
    package static let typeDescriptor = SpecialPointerAuthDiscriminators(rawValue: 0xAE86)
    package static let runtimeFunctionEntry = SpecialPointerAuthDiscriminators(rawValue: 0x625B)
    package static let protocolConformanceDescriptor = SpecialPointerAuthDiscriminators(rawValue: 0xC6EB)
    package static let protocolDescriptor = SpecialPointerAuthDiscriminators(rawValue: 0xE909)
    package static let opaqueTypeDescriptor = SpecialPointerAuthDiscriminators(rawValue: 0xBDD1)
    package static let contextDescriptor = SpecialPointerAuthDiscriminators(rawValue: 0xB5E3)
    package static let valueWitnessTable = SpecialPointerAuthDiscriminators(rawValue: 0x2E3F)
    package static let extendedExistentialTypeShape = SpecialPointerAuthDiscriminators(rawValue: 0x5A3D)
    package static let nonUniqueExtendedExistentialTypeShape = SpecialPointerAuthDiscriminators(rawValue: 0xE798)
    package static let initializeBufferWithCopyOfBuffer = SpecialPointerAuthDiscriminators(rawValue: 0xDA4A)
    package static let destroy = SpecialPointerAuthDiscriminators(rawValue: 0x04F8)
    package static let initializeWithCopy = SpecialPointerAuthDiscriminators(rawValue: 0xE3BA)
    package static let assignWithCopy = SpecialPointerAuthDiscriminators(rawValue: 0x8751)
    package static let initializeWithTake = SpecialPointerAuthDiscriminators(rawValue: 0x48D8)
    package static let assignWithTake = SpecialPointerAuthDiscriminators(rawValue: 0xEFDA)
    package static let destroyArray = SpecialPointerAuthDiscriminators(rawValue: 0x2398)
    package static let initializeArrayWithCopy = SpecialPointerAuthDiscriminators(rawValue: 0xA05C)
    package static let initializeArrayWithTakeFrontToBack = SpecialPointerAuthDiscriminators(rawValue: 0x1C3E)
    package static let initializeArrayWithTakeBackToFront = SpecialPointerAuthDiscriminators(rawValue: 0x8DD3)
    package static let storeExtraInhabitant = SpecialPointerAuthDiscriminators(rawValue: 0x79C5)
    package static let getExtraInhabitantIndex = SpecialPointerAuthDiscriminators(rawValue: 0x2CA8)
    package static let getEnumTag = SpecialPointerAuthDiscriminators(rawValue: 0xA3B5)
    package static let destructiveProjectEnumData = SpecialPointerAuthDiscriminators(rawValue: 0x041D)
    package static let destructiveInjectEnumTag = SpecialPointerAuthDiscriminators(rawValue: 0xB2E4)
    package static let getEnumTagSinglePayload = SpecialPointerAuthDiscriminators(rawValue: 0x60F0)
    package static let storeEnumTagSinglePayload = SpecialPointerAuthDiscriminators(rawValue: 0xA0D1)
    package static let objectiveCTypeDiscriminator = SpecialPointerAuthDiscriminators(rawValue: 0x31C3)
    package static let bridgeToObjectiveCDiscriminator = SpecialPointerAuthDiscriminators(rawValue: 0xBCA0)
    package static let forceBridgeFromObjectiveCDiscriminator = SpecialPointerAuthDiscriminators(rawValue: 0x22FB)
    package static let conditionallyBridgeFromObjectiveCDiscriminator = SpecialPointerAuthDiscriminators(rawValue: 0x9A9B)
    package static let dynamicReplacementScope = SpecialPointerAuthDiscriminators(rawValue: 0x48F0)
    package static let dynamicReplacementKey = SpecialPointerAuthDiscriminators(rawValue: 0x2C7D)
    package static let opaqueReadResumeFunction = SpecialPointerAuthDiscriminators(rawValue: 56769)
    package static let opaqueModifyResumeFunction = SpecialPointerAuthDiscriminators(rawValue: 3909)
    package static let objCISA = SpecialPointerAuthDiscriminators(rawValue: 0x6AE1)
    package static let objCSuperclass = SpecialPointerAuthDiscriminators(rawValue: 0xB5AB)
    package static let resilientClassStubInitCallback = SpecialPointerAuthDiscriminators(rawValue: 0xC671)
    package static let jobInvokeFunction = SpecialPointerAuthDiscriminators(rawValue: 0xCC64)
    package static let taskResumeFunction = SpecialPointerAuthDiscriminators(rawValue: 0x2C42)
    package static let taskResumeContext = SpecialPointerAuthDiscriminators(rawValue: 0x753A)
    package static let asyncRunAndBlockFunction = SpecialPointerAuthDiscriminators(rawValue: 0x0F08)
    package static let asyncContextParent = SpecialPointerAuthDiscriminators(rawValue: 0xBDA2)
    package static let asyncContextResume = SpecialPointerAuthDiscriminators(rawValue: 0xD707)
    package static let asyncContextYield = SpecialPointerAuthDiscriminators(rawValue: 0xE207)
    package static let cancellationNotificationFunction = SpecialPointerAuthDiscriminators(rawValue: 0x0F08)
    package static let escalationNotificationFunction = SpecialPointerAuthDiscriminators(rawValue: 0x7861)
    package static let asyncThinNullaryFunction = SpecialPointerAuthDiscriminators(rawValue: 0x0F08)
    package static let asyncFutureFunction = SpecialPointerAuthDiscriminators(rawValue: 0x720F)
    package static let swiftAsyncContextExtendedFrameEntry = SpecialPointerAuthDiscriminators(rawValue: 0xC31A)
    package static let clangTypeTaskContinuationFunction = SpecialPointerAuthDiscriminators(rawValue: 0x2ABE)
    package static let dispatchInvokeFunction = SpecialPointerAuthDiscriminators(rawValue: 0xF493)
    package static let accessibleFunctionRecord = SpecialPointerAuthDiscriminators(rawValue: 0x438C)
    package static let getExtraInhabitantTagFunction = SpecialPointerAuthDiscriminators(rawValue: 0x392E)
    package static let storeExtraInhabitantTagFunction = SpecialPointerAuthDiscriminators(rawValue: 0x9BF6)
    package static let relativeProtocolWitnessTable = SpecialPointerAuthDiscriminators(rawValue: 0xB830)
    package static let typeLayoutString = SpecialPointerAuthDiscriminators(rawValue: 0x8B65)
    package static let deinitWorkFunction = SpecialPointerAuthDiscriminators(rawValue: 0x8438)
    package static let isCurrentGlobalActorFunction = SpecialPointerAuthDiscriminators(rawValue: 0xD1B8)
}

package enum _PtrAuth {
    package struct Key {
        package var _value: Int32

        @_transparent
        package init(_value: Int32) {
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
    @_transparent
    package static func blend(pointer: UnsafeRawPointer, discriminator: UInt64 = 0) -> UInt64 {
        return PtrAuth_blend(UnsafeMutableRawPointer(mutating: pointer), discriminator)
    }

    @_transparent
    package static func blend(pointer: UnsafeRawPointer, discriminator: SpecialPointerAuthDiscriminators) -> UInt64 {
        return blend(pointer: pointer, discriminator: discriminator.rawValue)
    }

    @_transparent
    package static func sign(pointer: UnsafeRawPointer, key: Key, discriminator: UInt64 = 0) -> UnsafeRawPointer {
        let cKey = PtrAuthKey(rawValue: UInt32(key._value))
        let signedRaw = PtrAuth_sign(UnsafeMutableRawPointer(mutating: pointer), cKey, discriminator)
        return UnsafeRawPointer(signedRaw)
    }

    @_transparent
    package static func sign(pointer: UnsafeRawPointer, key: Key, discriminator: SpecialPointerAuthDiscriminators) -> UnsafeRawPointer {
        return sign(pointer: pointer, key: key, discriminator: discriminator.rawValue)
    }

    @_transparent
    package static func strip(pointer: UnsafeRawPointer, key: Key) -> UnsafeRawPointer {
        let cKey = PtrAuthKey(rawValue: UInt32(key._value))
        let stripped = PtrAuth_strip(UnsafeMutableRawPointer(mutating: pointer), cKey)
        return UnsafeRawPointer(stripped)
    }

    #elseif _ptrauth(_none)
    @_transparent
    package static func blend(pointer: UnsafeRawPointer, discriminator: UInt64 = 0) -> UInt64 {
        return 0
    }

    @_transparent
    package static func blend(pointer: UnsafeRawPointer, discriminator: SpecialPointerAuthDiscriminators) -> UInt64 {
        return blend(pointer: pointer, discriminator: discriminator.rawValue)
    }

    @_transparent
    package static func sign(pointer: UnsafeRawPointer, key: Key, discriminator: UInt64 = 0) -> UnsafeRawPointer {
        return unsafe pointer
    }

    @_transparent
    package static func sign(pointer: UnsafeRawPointer, key: Key, discriminator: SpecialPointerAuthDiscriminators) -> UnsafeRawPointer {
        return sign(pointer: pointer, key: key, discriminator: discriminator.rawValue)
    }

    @_transparent
    package static func strip(pointer: UnsafeRawPointer, key: Key) -> UnsafeRawPointer {
        return unsafe pointer
    }
    #else
    #error("unsupported ptrauth scheme")
    #endif
}
