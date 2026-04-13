import Foundation

public enum UnsafePointers {
    public struct UnsafePointerFieldTest {
        public var readPointer: UnsafePointer<Int>
        public var mutablePointer: UnsafeMutablePointer<Int>
        public var rawPointer: UnsafeRawPointer
        public var mutableRawPointer: UnsafeMutableRawPointer
        public var bufferPointer: UnsafeBufferPointer<Int>
        public var mutableBufferPointer: UnsafeMutableBufferPointer<Int>
        public var rawBufferPointer: UnsafeRawBufferPointer
        public var opaquePointer: OpaquePointer

        public init(
            readPointer: UnsafePointer<Int>,
            mutablePointer: UnsafeMutablePointer<Int>,
            rawPointer: UnsafeRawPointer,
            mutableRawPointer: UnsafeMutableRawPointer,
            bufferPointer: UnsafeBufferPointer<Int>,
            mutableBufferPointer: UnsafeMutableBufferPointer<Int>,
            rawBufferPointer: UnsafeRawBufferPointer,
            opaquePointer: OpaquePointer
        ) {
            self.readPointer = readPointer
            self.mutablePointer = mutablePointer
            self.rawPointer = rawPointer
            self.mutableRawPointer = mutableRawPointer
            self.bufferPointer = bufferPointer
            self.mutableBufferPointer = mutableBufferPointer
            self.rawBufferPointer = rawBufferPointer
            self.opaquePointer = opaquePointer
        }
    }

    public struct UnmanagedFieldTest {
        public var unmanagedReference: Unmanaged<AnyObject>

        public init(unmanagedReference: Unmanaged<AnyObject>) {
            self.unmanagedReference = unmanagedReference
        }
    }

    public struct AutoreleasingPointerFieldTest {
        public var autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>

        public init(autoreleasing: AutoreleasingUnsafeMutablePointer<AnyObject?>) {
            self.autoreleasing = autoreleasing
        }
    }
}
