import Foundation
import FoundationToolbox
import MachOKit
import MachOKitExtensions
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// The public face of the ObjC-ancestor override recovery (evolution proposal
/// `objc-ancestor-override-recovery`): per class, the members whose selector
/// an ancestor also implements. The hierarchy comes from the host's registered
/// `ObjCClassHierarchyProviding` when there is one, else from the library's
/// own reader; the join to Swift symbols is the same either way, in two tiers
/// of evidence — the `To` thunk symbol at the IMP, or (stripped) the Swift
/// implementation the IMP's code references, guarded by the selector being
/// the importer's spelling of the member's name — plus an optional third,
/// name-only tier that is off by default.
///
/// Lives in `SwiftThunkAnalysis` rather than next to the hierarchy in
/// `SwiftInspection` because the second tier decodes the thunk, and the
/// decoder sits here, above `SwiftInspection`.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-thunk-analysis", category: "ObjCAncestorOverrides")
public enum ObjCAncestorOverrides {
    /// Whether an overriding ObjC method whose IMP ties to no Swift symbol at
    /// all (an inlined body) is attributed to the one member of the class
    /// whose name is the importer's spelling of its selector. Off by default:
    /// the recovery joins, it does not guess — turn it on to also mark the
    /// overrides an OS framework's optimizer inlined away.
    public static var infersOverridesFromSelectorNames: Bool {
        get {
            inferenceSwitchLock.lock()
            defer { inferenceSwitchLock.unlock() }
            return inferenceSwitchValue
        }
        set {
            inferenceSwitchLock.lock()
            defer { inferenceSwitchLock.unlock() }
            inferenceSwitchValue = newValue
        }
    }

    // `NSLock`, not `OSAllocatedUnfairLock`: the package deploys to macOS 10.15.
    private static let inferenceSwitchLock = NSLock()
    nonisolated(unsafe) private static var inferenceSwitchValue = false

    /// The table for the class the image defines under ObjC runtime name
    /// `runtimeName` — a bare name for an ObjC-declared class such as an
    /// `@objc @implementation` one. `nil` when the image defines no such class
    /// object or it has no ObjC methods of its own.
    public static func table(forObjCClassNamed runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCAncestorOverrideTable? {
        guard let hierarchy = hierarchy(forClassNamed: runtimeName, in: machO) else { return nil }
        return table(for: hierarchy, ownerQualifiedName: "\(objcModule).\(runtimeName)", in: machO)
    }

    /// The table for the Swift class whose qualified name is `qualifiedName`
    /// (`SwiftUI.SliderMarkLabels.CustomMarkedSliderCell` — the same key the
    /// static layout engine uses). `nil` when the image has no static class
    /// object for it (a generic class), or when several same-named private
    /// classes make the name ambiguous.
    public static func table(forSwiftClassQualifiedName qualifiedName: String, in machO: some MachORepresentableWithCache) -> ObjCAncestorOverrideTable? {
        let runtimeNames = ObjCClassMethodIndex.shared.runtimeNames(forSwiftClassQualifiedName: qualifiedName, in: machO)
        guard let runtimeName = runtimeNames.first else { return nil }
        guard runtimeNames.count == 1 else {
            #log(.info, "\(runtimeNames.count) class objects print as \(qualifiedName, privacy: .public); not attributing ObjC overrides to any of them")
            return nil
        }
        guard let hierarchy = hierarchy(forClassNamed: runtimeName, in: machO) else { return nil }
        return table(for: hierarchy, ownerQualifiedName: qualifiedName, in: machO)
    }

    private static func hierarchy(forClassNamed runtimeName: String, in machO: some MachORepresentableWithCache) -> ObjCClassHierarchy? {
        if let provider = ObjCClassHierarchyProviderStore.shared.provider(for: machO), let hierarchy = provider.objcClassHierarchy(forClassNamed: runtimeName) {
            return hierarchy
        }
        return ObjCClassMethodIndex.shared.hierarchy(forRuntimeName: runtimeName, in: machO)
    }

    private static func table(for hierarchy: ObjCClassHierarchy, ownerQualifiedName: String, in machO: some MachORepresentableWithCache) -> ObjCAncestorOverrideTable {
        var overrides: [String: ObjCAncestorOverride] = [:]
        var unattributed: [ObjCAncestorOverrideTable.UnattributedMethod] = []
        for method in hierarchy.methods {
            guard let ancestor = hierarchy.ancestorDeclaring(selector: method.selector, isClassMethod: method.isClassMethod) else { continue }
            let offset: Int? = switch method.implementation {
            case .offset(let offset): offset
            case .address(let address): machO.resolveOffset(at: address)
            case nil: nil
            }
            var isAttributed = false
            if let offset {
                // Tier 1: the member's own `To` thunk sits at the IMP.
                // `symbols(offset:)` already filters to Swift symbols.
                if let symbols = machO.symbols(offset: offset), !symbols.isEmpty {
                    let override = ObjCAncestorOverride(selector: method.selector, isClassMethod: method.isClassMethod, ancestorClassName: ancestor.className, evidence: .thunkSymbol)
                    for symbol in symbols {
                        overrides[symbol.name] = override
                    }
                    isAttributed = true
                } else {
                    // Tier 2: the anonymous thunk's code references the
                    // implementation. Guarded twice — the symbol must be a
                    // member of THIS class and its name the importer's
                    // spelling of the selector — because an inlined body
                    // references whatever it calls.
                    for symbolName in ObjCMethodThunkReferences.referencedSwiftSymbolNames(atImplementationOffset: offset, in: machO) {
                        guard let root = try? demangleAsNodeTransient(symbolName),
                              let shape = ObjCMemberShape(demangledSymbol: root),
                              shape.ownerQualifiedName == ownerQualifiedName,
                              shape.isConsistent(withSelector: method.selector, isClassMethod: method.isClassMethod)
                        else { continue }
                        overrides[symbolName] = ObjCAncestorOverride(selector: method.selector, isClassMethod: method.isClassMethod, ancestorClassName: ancestor.className, evidence: .thunkReference)
                        isAttributed = true
                    }
                }
            }
            if !isAttributed {
                unattributed.append(.init(selector: method.selector, isClassMethod: method.isClassMethod, ancestorClassName: ancestor.className))
            }
        }
        return ObjCAncestorOverrideTable(hierarchy: hierarchy, overridesByImplementationSymbolName: overrides, unattributedOverriddenMethods: unattributed)
    }
}
