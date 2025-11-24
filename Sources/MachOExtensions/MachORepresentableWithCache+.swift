import Foundation
import MachOKit

extension MachORepresentableWithCache {
    /// Bitmask to get a valid range of vmaddr from raw vmaddr
    ///
    /// | Arch | `MACH_VM_MAX_ADDRESS` | mask |
    /// |---------|------------------|----------|
    /// | **arm** | `0x80000000` | `0x7FFFFFFF` |
    /// | **arm64 (mac or driver)** | `0x00007FFFFE000000` | `0x00007FFFFFFFFFFF` |
    /// | **arm64 (other)** | `0x0000000FC0000000` | `0x0000000FFFFFFFFF` |
    /// | **i386** | `0x00007FFFFFE00000` | `0x00007FFFFFFFFFFF` |
    ///
    /// [xnu implementation](https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/osfmk/mach/arm/vm_param.h#L126)
    package var vmaddrMask: UInt64? {
        switch header.cpuType {
        case .x86:
            return 0xFFFFFFFF
        case .i386:
            return 0xFFFFFFFF
        case .x86_64:
            return 0x00007FFFFFFFFFFF
        case .arm:
            return 0x7FFFFFFF
        case .arm64:
            if let platform = loadCommands.info(of: LoadCommand.buildVersion)?.platform {
                if [
                    .macOS,
                    .driverKit
                ].contains(platform) || isMacOS == true {
                    return 0x00007FFFFFFFFFFF
                } else {
                    return 0x0000000FFFFFFFFF
                }
            }
            return 0x0000000FFFFFFFFF // FIXME: fallback

        case .arm64_32:
            return 0x7FFFFFFF
        default:
            return nil
        }
    }
    
    /// Strips pointer authentication codes (PAC) and Objective-C tagged pointer bits from a raw virtual memory address.
    ///
    /// This method applies the appropriate architecture-specific bitmask to remove extra bits
    /// used for pointer authentication or tagged pointers, returning the "clean" virtual memory address.
    ///
    /// - Parameter rawVMAddr: The raw virtual memory address, potentially containing PAC or tagged pointer bits.
    /// - Returns: The virtual memory address with PAC and tagged pointer bits removed.
    package func stripPointerTags(of rawVMAddr: UInt64) -> UInt64 {
        var vmaddr = rawVMAddr
        if let vmaddrMask {
            vmaddr &= vmaddrMask // PAC & objc tagged pointer
        }
        // vmaddr &= ~3 // objc pointer union
        return vmaddr
    }

    package func stripPointerTags(of ptr: UnsafeRawPointer) -> UnsafeRawPointer {
        let address: UInt64 = .init(ptr.uint)
        let strippedPtr: UInt64 = stripPointerTags(of: address)
        return UnsafeRawPointer(bitPattern: UInt(strippedPtr))!
    }
}

extension MachORepresentableWithCache {
    private var isMacOS: Bool? {
        let loadCommands = loadCommands
        if let platform = loadCommands.info(of: LoadCommand.buildVersion)?.platform  {
            return [
                .macOS,
                .macOSExclaveKit,
                .macOSExclaveCore,
                .macCatalyst
            ].contains(
                platform
            )
        }
        if loadCommands.info(of: LoadCommand.versionMinMacosx) != nil {
            return true
        }

        if loadCommands.info(of: LoadCommand.versionMinIphoneos) != nil ||
            loadCommands.info(of: LoadCommand.versionMinWatchos) != nil ||
            loadCommands.info(of: LoadCommand.versionMinTvos) != nil {
            return false
        }

        if header.isInDyldCache,
           let cache = self.cache {
            return cache.header.platform == .macOS
        }

        return nil
    }
}
