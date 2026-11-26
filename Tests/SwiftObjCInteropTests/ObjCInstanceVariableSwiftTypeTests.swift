import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftSectionFixtureSupport
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@_spi(Internals) @testable import SwiftInspection
@_spi(Internals) @testable import SwiftObjCInterop

/// The Swift type behind an `@objc @implementation` ivar's encoding
/// (evolution proposal `objc-ivar-type-recovery`), checked encoding by
/// encoding against AppKit loaded into the test process, which only serves as
/// the image class names are looked up in.
@Suite
struct ObjCInstanceVariableSwiftTypeTests {
    private static func appKit() throws -> MachOImage {
        _ = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
        return try #require(MachOImage(named: .AppKit))
    }

    private static func instanceVariable(encoding: String) -> ObjCImplementationClassFacts.InstanceVariable {
        ObjCImplementationClassFacts.InstanceVariable(name: "storage", offset: 8, size: 8, alignment: 8, typeEncoding: encoding, swiftFieldOffsetSymbolName: nil, swiftPropertyName: nil, swiftTypeNode: nil)
    }

    /// The printed type recovered from an ivar with `encoding`, or `nil`.
    private static func recoveredType(encoding: String, propertyAttributes: String? = nil) throws -> String? {
        let objcProperty = propertyAttributes.map { ObjCImplementationClassFacts.Property(name: "storage", attributes: $0) }
        return ObjCInstanceVariableSwiftType(instanceVariable: instanceVariable(encoding: encoding), objcProperty: objcProperty, in: try appKit())
            .map { $0.typeNode.print(using: .interface) }
    }

    @Test func completeEncodingOfABridgeableClassKeepsTheClass() throws {
        // A Swift `NSString` property: the compiler writes `@"NSString"` only
        // because the type is the class itself, never for a `String`.
        #expect(try Self.recoveredType(encoding: "@\"NSString\"") == "__C.NSString!")
        #expect(try Self.recoveredType(encoding: "@\"NSArray\"") == "__C.NSArray!")
    }

    @Test func completeEncodingOfABareIdIsAnyObject() throws {
        #expect(try Self.recoveredType(encoding: "@") == "Swift.AnyObject!")
    }

    @Test func completeEncodingOfAProtocolIsTheExistential() throws {
        #expect(try Self.recoveredType(encoding: "@\"<NSCopying>\"") == "(any __C.NSCopying)!")
    }

    @Test func scalarEncodingsNameTheirSwiftTypes() throws {
        #expect(try Self.recoveredType(encoding: "B") == "Swift.Bool")
        #expect(try Self.recoveredType(encoding: "d") == "Swift.Double")
        #expect(try Self.recoveredType(encoding: "q") == "Swift.Int")
        #expect(try Self.recoveredType(encoding: "^d") == "Swift.UnsafeMutablePointer<Swift.Double>!")
    }

    @Test func encodingsThatDoNotDetermineATypeRecoverNothing() throws {
        // A block's signature is in no ivar encoding.
        #expect(try Self.recoveredType(encoding: "@?") == nil)
        // A CF type and a pointer to a structure encode alike.
        #expect(try Self.recoveredType(encoding: "^{CGColor=}") == nil)
        #expect(try Self.recoveredType(encoding: "{?=ii}") == nil)
        #expect(try Self.recoveredType(encoding: "b3") == nil)
        #expect(try Self.recoveredType(encoding: "") == nil)
    }

    @Test func weakPropertyIsOptional() throws {
        #expect(try Self.recoveredType(encoding: "@\"NSObject\"", propertyAttributes: "T@\"NSObject\",W,N,Vstorage") == "__C.NSObject?")
    }

    @Test func readOnlyAndWeakAreReadOffTheObjCProperty() throws {
        let appKit = try Self.appKit()
        let readOnly = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "q"), objcProperty: .init(name: "storage", attributes: "Tq,R,N,Vstorage"), in: appKit))
        #expect(readOnly.isReadOnly)
        #expect(!readOnly.isWeak)
        #expect(readOnly.source == .instanceVariableEncoding)
        let settable = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "q"), objcProperty: nil, in: appKit))
        #expect(!settable.isReadOnly)
    }
}
