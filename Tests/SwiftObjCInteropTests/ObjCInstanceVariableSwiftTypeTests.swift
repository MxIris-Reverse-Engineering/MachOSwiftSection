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

    /// How the fixed print preset spells the class named `runtimeName`, which
    /// is how a class the recovery keeps prints, whatever the spelling of
    /// imported names.
    private static func printedClass(_ runtimeName: String) throws -> String {
        ObjCRuntimeNames.classNode(forRuntimeName: runtimeName, in: try appKit()).print(using: .interface)
    }

    /// The importer's type for an Objective-C type, as a declaration imports it.
    private static func importedType(_ encoding: String) throws -> String {
        let type = try #require(ObjCTypeEncodingParser.type(from: encoding))
        return ObjCImportedTypes(machO: try appKit()).typeNode(type, position: .topLevel).print(using: .interface)
    }

    @Test func completeEncodingOfABridgeableClassKeepsTheClass() throws {
        // A Swift `NSString` property: the compiler writes `@"NSString"` only
        // because the type is the class itself, never for a `String`.
        let string = try Self.recoveredType(encoding: "@\"NSString\"")
        #expect(string == (try Self.printedClass("NSString")) + "!")
        #expect(string != (try Self.importedType("@\"NSString\"")))
        let array = try Self.recoveredType(encoding: "@\"NSArray\"")
        #expect(array == (try Self.printedClass("NSArray")) + "!")
    }

    @Test func completeEncodingOfABareIdIsAnyObject() throws {
        #expect(try Self.recoveredType(encoding: "@") == "Swift.AnyObject!")
    }

    @Test func completeEncodingOfAProtocolIsTheExistential() throws {
        // As the importer gives it: no bridging touches a protocol.
        let existential = try Self.recoveredType(encoding: "@\"<NSCopying>\"")
        #expect(existential == (try Self.importedType("@\"<NSCopying>\"")))
        #expect(existential?.hasSuffix("!") == true)
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

    @Test func bridgedEncodingTakesTheImportedTypeOfTheObjCProperty() throws {
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"NSString\",C,N,Vstorage") == "Swift.String!")
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"NSArray\",C,N,Vstorage") == (try Self.importedType("@\"NSArray\"")))
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@,&,N,Vstorage") == (try Self.importedType("@")))
        let appKit = try Self.appKit()
        let bridged = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "?"), objcProperty: .init(name: "storage", attributes: "T@\"NSString\",C,N,Vstorage"), in: appKit))
        #expect(bridged.source == .objcProperty)
    }

    @Test func bridgedEncodingWithoutATypedObjCPropertyRecoversNothing() throws {
        #expect(try Self.recoveredType(encoding: "?") == nil)
        // The `?` proves the type is no Objective-C class: a class imported as
        // itself is an `unowned` property's storage or a bridging the table
        // does not know, and says nothing reliable.
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"NSObject\",&,N,Vstorage") == nil)
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"<NSCopying>\",&,N,Vstorage") == nil)
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "Tq,N,Vstorage") == nil)
        // A Swift closure bridges to a block, whose attribute has no signature.
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@?,C,N,Vstorage") == nil)
    }

    @Test func weakStorageReadsItsClassUnbridged() throws {
        // `weak` makes the compiler write `?` for any class, and holds no
        // value type: `NSString` stays a class.
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"NSObject\",W,N,Vstorage") == (try Self.printedClass("NSObject")) + "?")
        #expect(try Self.recoveredType(encoding: "?", propertyAttributes: "T@\"NSString\",W,N,Vstorage") == (try Self.printedClass("NSString")) + "?")
    }

    @Test func readOnlyAndWeakAreReadOffTheObjCProperty() throws {
        let appKit = try Self.appKit()
        let readOnly = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "q"), objcProperty: .init(name: "storage", attributes: "Tq,R,N,Vstorage"), in: appKit))
        #expect(readOnly.isReadOnly)
        #expect(!readOnly.isWeak)
        #expect(readOnly.source == .instanceVariableEncoding)
        let settable = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "q"), objcProperty: nil, in: appKit))
        #expect(!settable.isReadOnly)
        let weak = try #require(ObjCInstanceVariableSwiftType(instanceVariable: Self.instanceVariable(encoding: "?"), objcProperty: .init(name: "storage", attributes: "T@\"NSObject\",W,N,Vstorage"), in: appKit))
        #expect(weak.isWeak)
        #expect(!weak.isReadOnly)
    }
}
