/// One identity-key collision the first-wins keying resolved silently: two
/// records in the same keying scope (one container's members, one global
/// bucket, or one container axis) carried the same identity, so only the
/// first was compared and the rest were dropped.
///
/// A dropped record can hide a change — most realistically a removal
/// classified as compatible. The one known-legitimate source is the merged
/// extension bucket: two conditional extensions (`where T: P` vs `where T: Q`)
/// each declaring a member whose mangling does not encode the `where` clause
/// collide once their members are flattened into one bucket (see
/// `Documentations/Internal/ABIDiffDesignAndLimitations.md`).
public struct ABIKeyCollision: Sendable, Codable, Equatable {
    /// The identity that collided.
    public let key: ABIKey
    /// The owning container's reporting name; `nil` for a global bucket or a
    /// container-level collision.
    public let containerName: String?
    /// Human-readable renderings of the records that were dropped (the first
    /// record with the key was kept and compared).
    public let droppedSignatures: [String]

    public init(key: ABIKey, containerName: String?, droppedSignatures: [String]) {
        self.key = key
        self.containerName = containerName
        self.droppedSignatures = droppedSignatures
    }
}

/// The diagnostics side-channel of an `ABIDiff`: everything the comparison
/// had to resolve silently, surfaced so a verdict is never quietly weaker
/// than it looks. `nil` on the diff when there is nothing to report.
public struct ABIDiffDiagnostics: Sendable, Codable, Equatable {
    /// Collisions found while keying the old side's snapshot.
    public let oldSideKeyCollisions: [ABIKeyCollision]
    /// Collisions found while keying the new side's snapshot.
    public let newSideKeyCollisions: [ABIKeyCollision]

    public init(oldSideKeyCollisions: [ABIKeyCollision], newSideKeyCollisions: [ABIKeyCollision]) {
        self.oldSideKeyCollisions = oldSideKeyCollisions
        self.newSideKeyCollisions = newSideKeyCollisions
    }

    public var isEmpty: Bool {
        oldSideKeyCollisions.isEmpty && newSideKeyCollisions.isEmpty
    }
}

extension ABISnapshot {
    /// Every identity-key collision the first-wins keying would silently
    /// resolve when this snapshot is diffed: duplicate container keys within
    /// one axis, and duplicate member identities within one container or
    /// global bucket. Deterministically ordered (container name, then key).
    public func keyCollisions() -> [ABIKeyCollision] {
        var collisions: [ABIKeyCollision] = []
        for axis in [types, protocols, typeExtensions, protocolExtensions, typeAliasExtensions, conformanceExtensions] {
            collectContainerKeyCollisions(axis, into: &collisions)
            for container in axis {
                collectMemberKeyCollisions(container.members, containerName: container.name, into: &collisions)
            }
        }
        collectMemberKeyCollisions(globalVariables, containerName: nil, into: &collisions)
        collectMemberKeyCollisions(globalFunctions, containerName: nil, into: &collisions)
        return collisions.sorted {
            ($0.containerName ?? "", $0.key.sortKey) < ($1.containerName ?? "", $1.key.sortKey)
        }
    }

    /// Two containers with the same key on one axis (dropped ones surface by
    /// name — a container has no signature).
    private func collectContainerKeyCollisions(_ containers: [ContainerSnapshot], into collisions: inout [ABIKeyCollision]) {
        var firstSeen: Set<ABIKey> = []
        var droppedNamesByKey: [ABIKey: [String]] = [:]
        for container in containers {
            if firstSeen.contains(container.key) {
                droppedNamesByKey[container.key, default: []].append(container.name)
            } else {
                firstSeen.insert(container.key)
            }
        }
        for (key, droppedNames) in droppedNamesByKey {
            collisions.append(ABIKeyCollision(key: key, containerName: nil, droppedSignatures: droppedNames))
        }
    }

    private func collectMemberKeyCollisions(_ members: [MemberRecord], containerName: String?, into collisions: inout [ABIKeyCollision]) {
        var firstSeen: Set<ABIKey> = []
        var droppedSignaturesByKey: [ABIKey: [String]] = [:]
        for member in members {
            if firstSeen.contains(member.identityKey) {
                droppedSignaturesByKey[member.identityKey, default: []].append(member.signature)
            } else {
                firstSeen.insert(member.identityKey)
            }
        }
        for (key, droppedSignatures) in droppedSignaturesByKey {
            collisions.append(ABIKeyCollision(key: key, containerName: containerName, droppedSignatures: droppedSignatures))
        }
    }
}
