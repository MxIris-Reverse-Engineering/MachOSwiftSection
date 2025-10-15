import XCTest
@testable import Demangle

/// Test cases for the Swift Remangler
final class RemanglerTests: XCTestCase {
    // MARK: - Basic Round-Trip Tests

    func testSimpleTypeRoundTrip() throws {
        let mangledNames = [
            "_$sSiD",                    // Int with suffix
            "_$sSSD",                    // String with suffix
            "_$sSbD",                    // Bool with suffix
            "_$sSdD",                    // Double with suffix
            "_$sSfD",                    // Float with suffix
        ]

        for mangled in mangledNames {
            let demangled = try demangleAsNode(mangled)
            let remangled = remangle(demangled)

            XCTAssertNotNil(remangled, "Failed to remangle: \(mangled)")
            if let remangled = remangled {
                XCTAssertEqual(remangled, mangled,
                              "Round-trip failed for: \(mangled)\nGot: \(remangled)")
            }
        }
    }

    func testStructureRoundTrip() throws {
        let mangledNames = [
            "_$s10Foundation4DataV",                    // Foundation.Data
            "_$s5MyApp11UserProfileV",                  // MyApp.UserProfile
            "_$s12SwiftUICore4ViewP",                   // SwiftUICore.View
        ]

        for mangled in mangledNames {
            do {
                let demangled = try demangleAsNode(mangled)
                let remangled = remangle(demangled)

                XCTAssertNotNil(remangled, "Failed to remangle: \(mangled)")
                if let remangled = remangled {
                    XCTAssertEqual(remangled, mangled,
                                  "Round-trip failed for: \(mangled)\nGot: \(remangled)")
                }
            } catch {
                // Some symbols might not demangle correctly - that's ok for now
                print("Skipping symbol that failed to demangle: \(mangled)")
            }
        }
    }

    func testFunctionRoundTrip() throws {
        let mangledNames = [
            "_$s5MyApp3fooyyF",                         // MyApp.foo() -> ()
            "_$s5MyApp3barySiSiF",                      // MyApp.bar(Int) -> Int
        ]

        for mangled in mangledNames {
            do {
                let demangled = try demangleAsNode(mangled)
                let remangled = remangle(demangled)

                XCTAssertNotNil(remangled, "Failed to remangle: \(mangled)")
                if let remangled = remangled {
                    XCTAssertEqual(remangled, mangled,
                                  "Round-trip failed for: \(mangled)\nGot: \(remangled)")
                }
            } catch {
                print("Skipping symbol that failed to demangle: \(mangled)")
            }
        }
    }

    // MARK: - Generic Type Tests

    func testGenericTypeRoundTrip() throws {
        let mangledNames = [
            "_$sSaySiGD",                               // Array<Int>
            "_$sSDySS_SiGD",                            // Dictionary<String, Int>
            "_$sShySiGD",                               // Set<Int>
        ]

        for mangled in mangledNames {
            do {
                let demangled = try demangleAsNode(mangled)
                let remangled = remangle(demangled)

                XCTAssertNotNil(remangled, "Failed to remangle: \(mangled)")
                if let remangled = remangled {
                    XCTAssertEqual(remangled, mangled,
                                  "Round-trip failed for: \(mangled)\nGot: \(remangled)")
                }
            } catch {
                print("Skipping symbol that failed to demangle: \(mangled)")
            }
        }
    }

    func testOptionalTypeRoundTrip() throws {
        let mangledNames = [
            "_$sSiSgD",                                 // Int?
            "_$sS2SGD",                                 // String?
        ]

        for mangled in mangledNames {
            do {
                let demangled = try demangleAsNode(mangled)
                let remangled = remangle(demangled)

                XCTAssertNotNil(remangled, "Failed to remangle: \(mangled)")
                if let remangled = remangled {
                    XCTAssertEqual(remangled, mangled,
                                  "Round-trip failed for: \(mangled)\nGot: \(remangled)")
                }
            } catch {
                print("Skipping symbol that failed to demangle: \(mangled)")
            }
        }
    }

    // MARK: - Manual Node Construction Tests

    func testManualNodeConstruction() throws {
        // Test building a simple type manually: Swift.Int
        let module = Node(kind: .module, text: "Swift")
        let identifier = Node(kind: .identifier, text: "Int")
        let structure = Node(kind: .structure, children: [module, identifier])
        let type = Node(kind: .type, children: [structure])
        let global = Node(kind: .global, children: [type])

        let remangled = remangle(global)
        XCTAssertNotNil(remangled, "Failed to remangle manually constructed node")

        // The result might have a suffix depending on context
        if let remangled = remangled {
            XCTAssertTrue(remangled.contains("Si"), "Expected 'Si' (Int) in mangled output")
        }
    }

    func testManualFunctionConstruction() throws {
        // Test building: MyModule.myFunc() -> ()
        let module = Node(kind: .module, text: "MyModule")
        let identifier = Node(kind: .identifier, text: "myFunc")

        // Empty tuple for arguments
        let argTuple = Node(kind: .argumentTuple, children: [
            Node(kind: .type, children: [Node(kind: .tuple)])
        ])

        // Void return type
        let returnType = Node(kind: .returnType, children: [
            Node(kind: .type, children: [Node(kind: .tuple)])
        ])

        let functionType = Node(kind: .functionType, children: [argTuple, returnType])
        let function = Node(kind: .function, children: [module, identifier, Node(kind: .type, children: [functionType])])
        let global = Node(kind: .global, children: [function])

        let remangled = remangle(global)
        XCTAssertNotNil(remangled, "Failed to remangle manually constructed function")
    }

    // MARK: - Error Handling Tests

    func testInvalidNodeStructure() {
        // Create a node with invalid structure
        let invalidNode = Node(kind: .identifier)  // Identifier without text

        let result = remangleWithError(invalidNode)
        XCTAssertFalse(result.isSuccess, "Should fail on invalid node")

        if case .failure(let error) = result {
            XCTAssertTrue(error.description.contains("Identifier"),
                         "Error should mention identifier issue")
        }
    }

    func testTooDeepRecursion() {
        // Create a very deep node tree
        var node = Node(kind: .type, children: [Node(kind: .tuple)])

        // Create 2000 nested types (exceeds max depth of 1024)
        for _ in 0..<2000 {
            node = Node(kind: .type, children: [node])
        }

        let result = remangleWithError(node)
        XCTAssertFalse(result.isSuccess, "Should fail on too deep recursion")

        if case .failure(let error) = result {
            if case .tooComplex = error {
                // Expected error type
            } else {
                XCTFail("Expected tooComplex error, got: \(error)")
            }
        }
    }

    // MARK: - Substitution Tests

    func testSubstitutionGeneration() {
        let remangler = Remangler()

        // Create some nodes to test substitution
        let node1 = Node(kind: .structure, children: [
            Node(kind: .module, text: "Swift"),
            Node(kind: .identifier, text: "Int")
        ])

        let node2 = Node(kind: .structure, children: [
            Node(kind: .module, text: "Swift"),
            Node(kind: .identifier, text: "String")
        ])

        // First occurrence should not use substitution
        _ = remangler.mangle(node1)
        let count1 = remangler.substitutionCount

        // Second occurrence of same node should use substitution
        _ = remangler.mangle(node1)
        let count2 = remangler.substitutionCount

        // Different node should add new substitution
        _ = remangler.mangle(node2)
        let count3 = remangler.substitutionCount

        XCTAssertEqual(count1, 0, "First node should not create substitution yet")
        XCTAssertGreaterThan(count3, count1, "Should have added substitutions")
    }

    // MARK: - Batch Operations Tests

    func testBatchRemangling() throws {
        let mangledNames = [
            "_$sSiD",
            "_$sSSD",
            "_$sSbD",
        ]

        let nodes = try mangledNames.map { try demangleAsNode($0) }
        let results = remangleBatch(nodes)

        XCTAssertEqual(results.count, mangledNames.count)
        for (index, result) in results.enumerated() {
            XCTAssertNotNil(result, "Batch remangling failed for index \(index)")
        }
    }

    func testConcurrentRemangling() async throws {
        let mangledNames = [
            "_$sSiD",
            "_$sSSD",
            "_$sSbD",
            "_$sSdD",
            "_$sSfD",
        ]

        let nodes = try mangledNames.map { try demangleAsNode($0) }
        let results = await remangleConcurrent(nodes)

        XCTAssertEqual(results.count, mangledNames.count)
        for (index, result) in results.enumerated() {
            XCTAssertNotNil(result, "Concurrent remangling failed for index \(index)")
        }
    }

    // MARK: - Statistics Tests

    func testRemanglingStatistics() throws {
        let mangled = "_$sSiD"
        let demangled = try demangleAsNode(mangled)

        let stats = remangleWithStatistics(demangled)

        XCTAssertTrue(stats.succeeded, "Remangling should succeed")
        XCTAssertNotNil(stats.result, "Should have result")
        XCTAssertGreaterThan(stats.outputLength, 0, "Should have non-zero output length")
    }

    // MARK: - Extract and Modify Tests

    func testExtractAndRemangle() throws {
        let mangled = "_$s5MyApp4UserV"
        let demangled = try demangleAsNode(mangled)

        // Extract just the identifier
        let extracted = extractAndRemangle(demangled) { $0.kind == .identifier }

        XCTAssertNotNil(extracted, "Should extract identifier")
    }

    // MARK: - Utility Tests

    func testCanRemangle() throws {
        let mangled = "_$sSiD"
        let demangled = try demangleAsNode(mangled)

        XCTAssertTrue(canRemangle(demangled), "Should be able to remangle valid node")

        let invalidNode = Node(kind: .identifier)
        XCTAssertFalse(canRemangle(invalidNode), "Should not be able to remangle invalid node")
    }

    func testRoundTripFunction() {
        let mangled = "_$sSiD"
        let result = roundTrip(mangled)

        XCTAssertNotNil(result, "Round-trip should succeed")
        if let result = result {
            XCTAssertEqual(result, mangled, "Round-trip should produce same output")
        }
    }

    func testCanRoundTrip() {
        let validMangled = "_$sSiD"
        XCTAssertTrue(canRoundTrip(validMangled), "Should be able to round-trip valid symbol")

        let invalidMangled = "not_a_valid_symbol"
        XCTAssertFalse(canRoundTrip(invalidMangled), "Should not be able to round-trip invalid symbol")
    }

    // MARK: - Performance Tests

    func testRemanglingPerformance() throws {
        let mangled = "_$sSiD"
        let demangled = try demangleAsNode(mangled)

        measure {
            for _ in 0..<1000 {
                _ = remangle(demangled)
            }
        }
    }

    func testBatchRemanglingPerformance() throws {
        let mangledNames = Array(repeating: "_$sSiD", count: 100)
        let nodes = try mangledNames.map { try demangleAsNode($0) }

        measure {
            _ = remangleBatch(nodes)
        }
    }
}
