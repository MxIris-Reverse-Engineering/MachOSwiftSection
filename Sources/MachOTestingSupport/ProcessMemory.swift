import Foundation

public enum ProcessMemory {
    public enum Metric {
        case physicalFootprint

        case residentSize

        case compressed

        case virtualSize

        var displayName: String {
            switch self {
            case .physicalFootprint: return "Physical Footprint"
            case .residentSize: return "Resident Size (RSS)"
            case .compressed: return "Compressed Memory"
            case .virtualSize: return "Virtual Size"
            }
        }
    }

    private nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        formatter.includesUnit = true
        return formatter
    }()

    public static func value(of metric: Metric) -> UInt64 {
        guard let info = getTaskVMInfo() else { return 0 }

        switch metric {
        case .physicalFootprint: return UInt64(info.phys_footprint)
        case .residentSize: return UInt64(info.resident_size)
        case .compressed: return UInt64(info.compressed)
        case .virtualSize: return UInt64(info.virtual_size)
        }
    }

    public static func formatted(of metric: Metric) -> String {
        let bytes = value(of: metric)
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }

    public static func report() {
        guard let info = getTaskVMInfo() else {
            print("❌ [ProcessMemory] Failed to retrieve task info.")
            return
        }

        print("====== 🧠 Process Memory Report ======")
        printItem(name: Metric.physicalFootprint.displayName, bytes: UInt64(info.phys_footprint))
        printItem(name: Metric.residentSize.displayName, bytes: UInt64(info.resident_size))
        printItem(name: Metric.compressed.displayName, bytes: UInt64(info.compressed))
        print("--------------------------------------")
    }

    // MARK: - Private Helpers

    private static func printItem(name: String, bytes: UInt64) {
        let str = byteFormatter.string(fromByteCount: Int64(bytes))
        print(String(format: "%-20@ : %@", name, str))
    }

    private static func getTaskVMInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }
}
