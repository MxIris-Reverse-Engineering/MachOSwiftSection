import Foundation
import MachOKit
import MachOKitExtensions
@_spi(Internals) import MachOCaches

/// What the ObjC side knows about one class that the member recovery needs
/// (evolution proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`): the class's own method table —
/// selector, instance/class, where the IMP is — and, for every ancestor up
/// the superclass chain, the selectors that ancestor implements, plus the
/// selectors of the `@objc` protocols the class adopts. A selector of the
/// class's own table that an ancestor also implements is an override; one
/// a protocol declares is a witness whose selector is the requirement's;
/// nothing else about the ancestors or protocols matters here.
///
/// The value is deliberately reader-agnostic: a host that already indexed the
/// image's ObjC metadata (RuntimeViewer, or the library's own
/// `ObjCIndexing.ObjCInterfaceIndexer`) builds it from what it has through
/// ``ObjCClassHierarchyProviding``; otherwise ``ObjCClassMethodIndex`` reads
/// it from the Mach-O directly.
public struct ObjCClassHierarchy: Sendable {
    /// Where a method's implementation lives, in whichever coordinate the
    /// source had at hand. Both resolve to the same symbol lookup.
    public enum ImplementationLocation: Sendable, Hashable {
        /// An offset into the image (a file's header-relative offset, or a
        /// cache image's main-cache offset — whatever `symbols(offset:)` keys on).
        case offset(Int)
        /// An address, as an in-process ObjC reader hands back; resolved to an
        /// offset against the image at lookup time.
        case address(UInt64)
    }

    public struct Method: Sendable, Hashable {
        public let selector: String
        public let isClassMethod: Bool
        public let implementation: ImplementationLocation?

        public init(selector: String, isClassMethod: Bool, implementation: ImplementationLocation?) {
            self.selector = selector
            self.isClassMethod = isClassMethod
            self.implementation = implementation
        }
    }

    /// One ancestor and the selectors it implements — its own class object's
    /// method lists, categories the linker or dyld attached to it included —
    /// plus the selectors of the protocols it adopts: a conformance is
    /// inherited, so a subclass member satisfying an ancestor's protocol
    /// requirement takes the requirement's selector just as a direct
    /// witness does (`NSTableView`'s `NSDraggingSource` for a subclass's
    /// `draggingSession(_:movedTo:)`).
    public struct Ancestor: Sendable {
        public let className: String
        public let instanceSelectors: Set<String>
        public let classSelectors: Set<String>
        public let adoptedProtocolSelectors: AdoptedProtocolSelectors?

        public init(className: String, instanceSelectors: Set<String>, classSelectors: Set<String>, adoptedProtocolSelectors: AdoptedProtocolSelectors? = nil) {
            self.className = className
            self.instanceSelectors = instanceSelectors
            self.classSelectors = classSelectors
            self.adoptedProtocolSelectors = adoptedProtocolSelectors
        }

        public func implements(selector: String, isClassMethod: Bool) -> Bool {
            isClassMethod ? classSelectors.contains(selector) : instanceSelectors.contains(selector)
        }
    }

    /// The selectors of the `@objc` protocols the class adopts — its own
    /// `class_ro_t.baseProtocols` and its categories', the protocols those
    /// inherit included, required and optional requirements alike. A member
    /// answering to one of them is a witness, and its selector is the
    /// requirement's, never derived from the Swift name.
    public struct AdoptedProtocolSelectors: Sendable, Hashable {
        public let instanceSelectors: Set<String>
        public let classSelectors: Set<String>
        /// `false` when a protocol could not be read — a standalone file's
        /// protocol from another image is a bind with nothing behind it — so
        /// a selector absent from the sets is UNKNOWN, not absent.
        public let isComplete: Bool

        public init(instanceSelectors: Set<String>, classSelectors: Set<String>, isComplete: Bool) {
            self.instanceSelectors = instanceSelectors
            self.classSelectors = classSelectors
            self.isComplete = isComplete
        }

        public func declares(selector: String, isClassMethod: Bool) -> Bool {
            isClassMethod ? classSelectors.contains(selector) : instanceSelectors.contains(selector)
        }
    }

    /// The class's ObjC runtime name: the bare name for an ObjC-declared class
    /// (`NSGlassEffectView`), the mangled runtime name for a Swift class
    /// (`_TtC7SwiftUI21CustomMarkedSliderCell`).
    public let className: String

    /// The class's own methods, instance and class alike — its class object's
    /// method lists plus the categories of the same image that target it (a
    /// Swift `extension` with `@objc` members compiles to one).
    public let methods: [Method]

    /// The superclass chain, nearest ancestor first.
    public let ancestors: [Ancestor]

    /// `false` when the chain stopped before its root class because a
    /// superclass could not be followed — a standalone file's superclass in
    /// another binary is a bind with nothing behind it offline. Verdicts from
    /// the ancestors that WERE reached still stand; only "not an override"
    /// becomes "not provably an override".
    public let isAncestorChainComplete: Bool

    /// The name of the superclass the chain could not follow, when known.
    public let unresolvedAncestorName: String?

    /// The adopted protocols' selectors, `nil` when the source knows nothing
    /// about them (a provider that does not track protocols).
    public let adoptedProtocolSelectors: AdoptedProtocolSelectors?

    public init(className: String, methods: [Method], ancestors: [Ancestor], isAncestorChainComplete: Bool, unresolvedAncestorName: String? = nil, adoptedProtocolSelectors: AdoptedProtocolSelectors? = nil) {
        self.className = className
        self.methods = methods
        self.ancestors = ancestors
        self.isAncestorChainComplete = isAncestorChainComplete
        self.unresolvedAncestorName = unresolvedAncestorName
        self.adoptedProtocolSelectors = adoptedProtocolSelectors
    }

    /// The nearest ancestor implementing `selector`, or `nil` when none does —
    /// which, if the chain is complete, means the member is not an override.
    public func ancestorDeclaring(selector: String, isClassMethod: Bool) -> Ancestor? {
        ancestors.first { $0.implements(selector: selector, isClassMethod: isClassMethod) }
    }

    /// Whether an `@objc` protocol the class or an ancestor adopts, as far
    /// as the source could read them, declares `selector` — `false` also
    /// when nothing is known, so a caller that wants "provably a witness"
    /// gets exactly that.
    public func adoptedProtocolDeclares(selector: String, isClassMethod: Bool) -> Bool {
        if adoptedProtocolSelectors?.declares(selector: selector, isClassMethod: isClassMethod) == true { return true }
        return ancestors.contains { $0.adoptedProtocolSelectors?.declares(selector: selector, isClassMethod: isClassMethod) == true }
    }

    /// Whether every protocol the class and its ancestors adopt was read in
    /// full — the precondition for ruling a selector NOT inherited from a
    /// requirement.
    public var isAdoptedProtocolSetComplete: Bool {
        guard adoptedProtocolSelectors?.isComplete == true else { return false }
        return ancestors.allSatisfy { $0.adoptedProtocolSelectors?.isComplete == true }
    }
}

/// The seam through which a host hands the library an ObjC class hierarchy it
/// already holds, instead of having the library read the image's ObjC
/// metadata a second time. Registered per image in
/// ``ObjCClassHierarchyProviderStore``; the library's own reader is the
/// fallback for an image nobody registered a provider for, and for a class the
/// provider answers `nil` about.
///
/// Class-constrained so the store can hold providers weakly: a provider is
/// typically the host's own indexer object, and the store must not be what
/// keeps it alive after the host dropped the image.
public protocol ObjCClassHierarchyProviding: AnyObject, Sendable {
    /// The hierarchy of the class named `runtimeName` (the `class_ro_t` name —
    /// bare for an ObjC-declared class, mangled for a Swift one), or `nil` when
    /// the provider does not know the class.
    func objcClassHierarchy(forClassNamed runtimeName: String) -> ObjCClassHierarchy?
}

/// Per-image registry of ``ObjCClassHierarchyProviding`` providers. Same
/// pattern as `PropertyWrapperTypeCatalogStore`: the class-indexing code that
/// consumes the provider (`TypeDefinition.index(in:)`) has no view of the
/// indexer's configuration, so the host installs the provider against the
/// image and the consumer looks it up by the image's identifier.
///
/// Providers are held **weakly**; an entry whose provider deinitialized reads
/// as absent.
public final class ObjCClassHierarchyProviderStore: @unchecked Sendable {
    public static let shared = ObjCClassHierarchyProviderStore()

    private struct WeakProvider {
        weak var provider: (any ObjCClassHierarchyProviding)?
    }

    private let lock = NSLock()
    private var providersByImageIdentifier: [AnyHashable: WeakProvider] = [:]

    private init() {}

    /// Installs `provider` for `machO`, replacing any earlier registration.
    public func register(_ provider: any ObjCClassHierarchyProviding, for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        providersByImageIdentifier[AnyHashable(machO.identifier)] = WeakProvider(provider: provider)
    }

    /// The live provider registered for `machO`, if any.
    public func provider(for machO: some MachORepresentableWithCache) -> (any ObjCClassHierarchyProviding)? {
        lock.lock()
        defer { lock.unlock() }
        let key = AnyHashable(machO.identifier)
        guard let entry = providersByImageIdentifier[key] else { return nil }
        guard let provider = entry.provider else {
            providersByImageIdentifier[key] = nil
            return nil
        }
        return provider
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        providersByImageIdentifier[AnyHashable(machO.identifier)] = nil
    }
}

/// Per-image eviction of the hierarchy-side state: the reader index, the
/// host's provider registration, the ancestor resolver (which holds the
/// file's dependency images once it has resolved them) and the recovery
/// options. The declaration indexer calls this alongside the other per-image
/// cache evictions.
public enum ObjCClassHierarchies {
    public static func removeCache(for machO: some MachORepresentableWithCache) {
        ObjCClassMethodIndex.shared.remove(for: machO)
        ObjCClassHierarchyProviderStore.shared.remove(for: machO)
        ObjCAncestorResolverStore.shared.remove(for: machO)
        ObjCMemberRecoveryOptionsStore.shared.remove(for: machO)
    }
}
