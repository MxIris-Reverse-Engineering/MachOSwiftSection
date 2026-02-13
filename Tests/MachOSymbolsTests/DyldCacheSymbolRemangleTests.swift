import Foundation
import Testing
import PowerAssert
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

@MainActor
protocol DemangleAndRemangleTests {
    func allSymbols() async throws -> [MachOSwiftSymbol]
    func mainTest() async throws
}

extension DemangleAndRemangleTests {
    func mainTest() async throws {
        let allSwiftSymbols = try await allSymbols()

        // Counters
        var totalCount = 0
        var successCount = 0
        var knownIssueCount = 0
        var demangleFailCount = 0
        var nodeTreeMismatchCount = 0
        var nodePrintMismatchCount = 0
        var remangleMismatchCount = 0

        // Sample collection (limit per category)
        let maxSamples = 10
        var demangleFailSamples: [String] = []
        var nodeTreeMismatchSamples: [String] = []
        var nodePrintMismatchSamples: [String] = []
        var remangleMismatchSamples: [String] = []

        for symbol in allSwiftSymbols {
            totalCount += 1
            let mangledName = symbol.stringValue
            let stdlibName = stdlib_demangleName(mangledName)
            let stdlibTree = MachOTestingSupport.stdlib_demangleNodeTree(mangledName)

            do {
                let node = try demangleAsNodeInterned(mangledName)
                var allPassed = true

                // 1. Node tree check
                if let stdlibTree {
                    let ourTree = node.description + "\n"
                    if stdlibTree != ourTree {
                        if isOpaqueReturnTypeParentDifference(stdlibTree, ourTree) {
                            knownIssueCount += 1
                        } else {
                            allPassed = false
                            nodeTreeMismatchCount += 1
                            if nodeTreeMismatchSamples.count < maxSamples {
                                nodeTreeMismatchSamples.append(mangledName)
                            }
                            Issue.record("Node tree mismatch: \(mangledName)")
                        }
                    }
                }

                // 2. Node print check
                let printed = node.print()
                if stdlibName != printed {
                    allPassed = false
                    nodePrintMismatchCount += 1
                    if nodePrintMismatchSamples.count < maxSamples {
                        nodePrintMismatchSamples.append("  \(mangledName)\n    expected: \(stdlibName)\n    got:      \(printed)")
                    }
                    Issue.record("Node print mismatch: \(mangledName)")
                }

                // 3. Remangle check
                let remangled = try Demangling.mangleAsString(node)
                if remangled != mangledName {
                    // Known issue: Md vs MD (Apple-internal lowercase 'd')
                    if mangledName.hasSuffix("Md") && remangled.hasSuffix("MD")
                        && mangledName.dropLast(2) == remangled.dropLast(2) {
                        knownIssueCount += 1
                    } else {
                        allPassed = false
                        remangleMismatchCount += 1
                        if remangleMismatchSamples.count < maxSamples {
                            remangleMismatchSamples.append("  \(mangledName)\n    remangled: \(remangled)")
                        }
                        Issue.record("Remangle mismatch: \(mangledName)")
                    }
                }

                if allPassed { successCount += 1 }
            } catch {
                if mangledName != stdlibName {
                    demangleFailCount += 1
                    if demangleFailSamples.count < maxSamples {
                        demangleFailSamples.append("  \(mangledName) — \(error)")
                    }
                    Issue.record("Demangle failed: \(mangledName): \(error)")
                } else {
                    successCount += 1 // both failed = consistent
                }
            }
        }

        // Print summary
        print("""

        ═══ Demangling Alignment Report ═══
        Total symbols:         \(totalCount)
        Passed:                \(successCount)
        Known issues (skip):   \(knownIssueCount)
        Demangle failures:     \(demangleFailCount)
        Node tree mismatches:  \(nodeTreeMismatchCount)
        Node print mismatches: \(nodePrintMismatchCount)
        Remangle mismatches:   \(remangleMismatchCount)
        """)

        if !demangleFailSamples.isEmpty {
            print("--- Demangle Failures (first \(demangleFailSamples.count)) ---")
            for sample in demangleFailSamples { print(sample) }
        }
        if !nodeTreeMismatchSamples.isEmpty {
            print("--- Node Tree Mismatches (first \(nodeTreeMismatchSamples.count)) ---")
            for sample in nodeTreeMismatchSamples { print(sample) }
        }
        if !nodePrintMismatchSamples.isEmpty {
            print("--- Node Print Mismatches (first \(nodePrintMismatchSamples.count)) ---")
            for sample in nodePrintMismatchSamples { print(sample) }
        }
        if !remangleMismatchSamples.isEmpty {
            print("--- Remangle Mismatches (first \(remangleMismatchSamples.count)) ---")
            for sample in remangleMismatchSamples { print(sample) }
        }
    }

    /// Check if the difference between two tree strings is only in OpaqueReturnTypeParent lines.
    private func isOpaqueReturnTypeParentDifference(_ lhs: String, _ rhs: String) -> Bool {
        let filteredLhs = lhs.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("OpaqueReturnTypeParent") }
        let filteredRhs = rhs.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("OpaqueReturnTypeParent") }
        return filteredLhs == filteredRhs
    }
}

@Suite
final class DyldCacheSymbolRemangleTests: DyldCacheSymbolTests, DemangleAndRemangleTests {
    @Test func main() async throws {
        try await mainTest()
    }

    @Test func demangle() async throws {
        let node = try Demangling.demangleAsNode("_$sSis15WritableKeyPathCy17RealityFoundation23PhysicallyBasedMaterialVAE9BaseColorVGTHTm")
//        try Demangling.mangleAsString(node).print()
        node.description.print()
    }

    @Test func stdlib_demangleNodeTree() async throws {
        let mangledName = "_$s7SwiftUI11DisplayListV10PropertiesVs9OptionSetAAsAFP8rawValuex03RawI0Qz_tcfCTW"
        let demangleNodeTree = MachOTestingSupport.stdlib_demangleNodeTree(mangledName)
        let stdlibNodeDescription = try #require(demangleNodeTree)
        let swiftSectionNodeDescription = try demangleAsNode(mangledName).description + "\n"
        #expect(stdlibNodeDescription == swiftSectionNodeDescription)
    }
}
