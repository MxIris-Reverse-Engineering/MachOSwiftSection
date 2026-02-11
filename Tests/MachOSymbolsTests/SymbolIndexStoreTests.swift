import Foundation
import Testing
import MachO
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport

/// 用于获取和格式化当前进程内存占用的工具类
public enum ProcessMemory {
    /// 内存指标枚举
    public enum Metric {
        /// 物理内存占用 (Physical Footprint)
        /// 苹果推荐指标，对应 Activity Monitor 中的 "App Memory"。
        /// 包含：脏页 + 压缩内存。最能反映应用对系统的实际压力。
        case physicalFootprint

        /// 常驻内存 (Resident Size / RSS)
        /// 当前映射到物理 RAM 中的页面总数。
        /// 注意：在内存紧张时，部分内存可能被压缩（不计入 RSS），因此该值有时会误导。
        case residentSize

        /// 压缩内存 (Compressed)
        /// 被系统压缩器压缩的内存页大小。
        case compressed

        /// 虚拟内存大小 (Virtual Size)
        /// 进程保留的地址空间总量（通常远大于物理内存）。
        case virtualSize

        /// 这里的显示名称，用于日志输出
        var displayName: String {
            switch self {
            case .physicalFootprint: return "Physical Footprint"
            case .residentSize: return "Resident Size (RSS)"
            case .compressed: return "Compressed Memory"
            case .virtualSize: return "Virtual Size"
            }
        }
    }

    // MARK: - Formatter

    /// 共享的 ByteCountFormatter，配置为内存计数风格 (1024进制)
    private nonisolated(unsafe) static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory // 使用 1024 进制 (KiB, MiB, GiB)
        formatter.allowsNonnumericFormatting = false // 避免输出 "Zero KB"
        formatter.includesUnit = true
        return formatter
    }()

    // MARK: - Public API

    /// 获取指定指标的原始字节数 (Bytes)
    /// - Parameter metric: 内存指标类型
    /// - Returns: 字节数 (UInt64)
    public static func value(of metric: Metric) -> UInt64 {
        guard let info = getTaskVMInfo() else { return 0 }

        switch metric {
        case .physicalFootprint: return UInt64(info.phys_footprint)
        case .residentSize: return UInt64(info.resident_size)
        case .compressed: return UInt64(info.compressed)
        case .virtualSize: return UInt64(info.virtual_size)
        }
    }

    /// 获取指定指标的格式化字符串 (例如: "125.4 MB")
    /// - Parameter metric: 内存指标类型
    /// - Returns: 格式化后的字符串
    public static func formatted(of metric: Metric) -> String {
        let bytes = value(of: metric)
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }

    /// 打印当前所有主要内存指标的快照
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
        // 对齐输出，让日志更好看
        print(String(format: "%-20@ : %@", name, str))
    }

    /// 核心私有方法：调用 Mach Kernel API
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

@Suite
final class SymbolIndexStoreTests: MachOImageTests {
    @Test func main() async throws {
        SymbolIndexStore.usesIntern = true
        SymbolIndexStore.shared.prepare(in: machOImage)
        ProcessMemory.report()
    }
}
