import Foundation
import Testing
import Demangle
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection

@Suite(.serialized)
struct SymbolDemangleTests {
    let mainCache: DyldCache

    let subCache: DyldCache

    let machOFileInMainCache: MachOFile

    let machOFileInSubCache: MachOFile

    let machOFileInCache: MachOFile

    init() async throws {
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUI))
        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .SwiftUICore))
    }

    private func swiftDemangle(for tasks: [SwiftDemangleTask]) async throws -> [SwiftDemangleTask.Result] {
        let process = Process()

        process.executableURL = .init(fileURLWithPath: "/usr/bin/swift")

        var arguments: [String] = ["demangle", "--compact", "--no-sugar"]

        for task in tasks {
            arguments.append(task.mangledName)
        }

        let pipe = Pipe()

        process.standardOutput = pipe

        try process.run()

        process.waitUntilExit()

        let data = try pipe.fileHandleForReading.readToEnd()!

        var results: [SwiftDemangleTask.Result] = []
        let outputs = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(tasks.count == outputs.count, "Number of tasks does not match number of outputs")
        for (task, result) in zip(tasks, outputs) {
            results.append(.init(index: task.index, demangledName: String(result)))
        }
        return results
    }

    struct SwiftDemangleTask {
        struct Result {
            let index: Int
            let demangledName: String
        }

        let index: Int
        let mangledName: String
    }

    @Test func swiftDemangles() async throws {
        let mangledNames = machOFileInMainCache.symbols.filter { $0.name.starts(with: "_$s") }.map(\.name)

        let swiftDemangleResults = try await withThrowingTaskGroup { group in
            for tasks in mangledNames.enumerated().map({ SwiftDemangleTask(index: $0.offset, mangledName: $0.element) }).splitByBatchSize(10) {
                group.addTask {
                    try await swiftDemangle(for: tasks)
                }
            }

            var results: [SwiftDemangleTask.Result] = []
            for try await result in group {
                results.append(contentsOf: result)
            }
            return results
        }

        let swiftDemangledNames = swiftDemangleResults.sorted { $0.index < $1.index }.map(\.demangledName)
        print(swiftDemangledNames)
    }

    @MainActor
    @Test func symbols() throws {

        for symbol in machOFileInMainCache.symbols where symbol.name.starts(with: "_$s") {
            var demangler = Demangler(scalars: symbol.name.unicodeScalars)
            let node = try demangler.demangleSymbol()
            let swiftSectionDemanlgedName = node.print()
            #expect(symbol.demangledName == swiftSectionDemanlgedName, "\(symbol.name)")
        }

//        for symbol in machOFileInMainCache.symbols where symbol.name.starts(with: "_$s") {
//            do {
//                var demangler = Demangler(scalars: symbol.name.unicodeScalars)
//                let node = try demangler.demangleSymbol()
//                node.print().print()
//            } catch {
//                print("Failed: \(symbol.name)")
//                print(error)
//                print("\n")
//            }
//            print(symbol.name)
//        }
    }
    
    @Test func demangle() async throws {
        var demangler = Demangler(scalars: "_$s7SwiftUI24TableColumnCustomizationV10visibilityAA10VisibilityOSS_tcips12IdentifiableRzlACyxGxTK".unicodeScalars)
        let node = try demangler.demangleSymbol()
        node.print().print()
    }
}

extension Array {
    /// 按指定的每批次元素数量拆分数组
    /// - Parameter batchSize: 每个批次包含的元素数量
    /// - Returns: 拆分后的二维数组
    func splitByBatchSize(_ batchSize: Int) -> [[Element]] {
        guard batchSize > 0 else { return [] }

        return stride(from: 0, to: count, by: batchSize).map {
            Array(self[$0 ..< Swift.min($0 + batchSize, count)])
        }
    }
}
