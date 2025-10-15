import XCTest
@testable import Demangle

/// Test cases for standard type substitutions
final class StandardTypesTests: XCTestCase {
    
    func testStandardStructures() {
        // Standard structure types
        XCTAssertEqual(Mangle.getStandardTypeSubst("Array"), "a")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Bool"), "b")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Dictionary"), "D")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Double"), "d")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Float"), "f")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Set"), "h")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Int"), "i")
        XCTAssertEqual(Mangle.getStandardTypeSubst("String"), "S")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UInt"), "u")
        
        // Additional structures
        XCTAssertEqual(Mangle.getStandardTypeSubst("Character"), "J")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Range"), "n")
        XCTAssertEqual(Mangle.getStandardTypeSubst("ClosedRange"), "N")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Substring"), "s")
        XCTAssertEqual(Mangle.getStandardTypeSubst("ObjectIdentifier"), "O")
    }
    
    func testStandardProtocols() {
        XCTAssertEqual(Mangle.getStandardTypeSubst("Equatable"), "Q")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Sequence"), "T")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Collection"), "l")
        XCTAssertEqual(Mangle.getStandardTypeSubst("BinaryInteger"), "z")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Hashable"), "H")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Comparable"), "L")
    }
    
    func testPointerTypes() {
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafePointer"), "P")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeMutablePointer"), "p")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeRawPointer"), "V")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeMutableRawPointer"), "v")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeBufferPointer"), "R")
        XCTAssertEqual(Mangle.getStandardTypeSubst("UnsafeMutableBufferPointer"), "r")
    }
    
    func testEnumTypes() {
        XCTAssertEqual(Mangle.getStandardTypeSubst("Optional"), "q")
    }
    
    func testConcurrencyTypes() {
        // Test with concurrency enabled (default)
        XCTAssertEqual(Mangle.getStandardTypeSubst("Actor"), "cA")
        XCTAssertEqual(Mangle.getStandardTypeSubst("MainActor"), "cM")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Task"), "cT")
        XCTAssertEqual(Mangle.getStandardTypeSubst("TaskPriority"), "cP")
        XCTAssertEqual(Mangle.getStandardTypeSubst("Executor"), "cF")
        XCTAssertEqual(Mangle.getStandardTypeSubst("SerialExecutor"), "cf")
        XCTAssertEqual(Mangle.getStandardTypeSubst("TaskGroup"), "cG")
        XCTAssertEqual(Mangle.getStandardTypeSubst("AsyncSequence"), "ci")
        
        // Test with concurrency disabled
        XCTAssertNil(Mangle.getStandardTypeSubst("Actor", allowConcurrencyManglings: false))
        XCTAssertNil(Mangle.getStandardTypeSubst("Task", allowConcurrencyManglings: false))
    }
    
    func testNonStandardType() {
        XCTAssertNil(Mangle.getStandardTypeSubst("MyCustomType"))
        XCTAssertNil(Mangle.getStandardTypeSubst("NotAStandardType"))
    }
}
