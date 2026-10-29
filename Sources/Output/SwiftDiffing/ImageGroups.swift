import OrderedCollections

/// One image of a version made up of a group of images (evolution proposal
/// `image-group-evolution`): the name the image goes by on the axis and its
/// ABI frozen into a snapshot.
///
/// A module Apple split across images — SwiftUI and SwiftUICore from macOS 15
/// on — keeps one API surface, and a declaration moved between the images
/// keeps its mangled name. Compared one image per version, such a declaration
/// reads as removed from one image and added to the other; compared as a
/// group, it stays put and its move is recorded instead.
public struct ABIImageSnapshot: Sendable, Codable, Equatable {
    /// The image's name on the axis (`SwiftUICore`) — what a report names
    /// where a declaration moved.
    public var imageName: String
    public var snapshot: ABISnapshot

    public init(imageName: String, snapshot: ABISnapshot) {
        self.imageName = imageName
        self.snapshot = snapshot
    }
}

/// A declaration observed on both sides of a transition, in different images
/// of the versions' groups — what an evolution over groups of images reports
/// as moved (evolution proposal `image-group-evolution`).
///
/// A move is reported, never judged: whether code bound to the old image
/// still finds the declaration depends on the old image re-exporting the new
/// one, which a snapshot does not record. A move therefore never makes a
/// transition breaking.
public struct ImageMove: Sendable, Codable, Equatable {
    /// The version the declaration was first observed in its new images —
    /// like a ``LineageEvent``'s, always ≥ 1.
    public let versionIndex: Int
    /// The images holding the declaration before the move, in the group's
    /// order.
    public let oldImageNames: [String]
    /// The images holding the declaration after the move, in the group's
    /// order.
    public let newImageNames: [String]
    /// For a move across versions that could not show the declaration
    /// (evolution proposal `evolution-unobservable-presence`): the first of
    /// them — the move happened at some version from there through
    /// `versionIndex`. `nil` for a move placed exactly.
    public let earliestVersionIndex: Int?

    public init(versionIndex: Int, oldImageNames: [String], newImageNames: [String], earliestVersionIndex: Int? = nil) {
        self.versionIndex = versionIndex
        self.oldImageNames = oldImageNames
        self.newImageNames = newImageNames
        self.earliestVersionIndex = earliestVersionIndex
    }

    /// Where the move is placed, phrased against the axis as an event's is:
    /// `in 15.0`, or `between 12.7 and 15.0` across versions that could not
    /// show the declaration.
    public func placement(on versions: [ABIVersionDescriptor]) -> String {
        versions.placement(ofChangeAt: versionIndex, earliestVersionIndex: earliestVersionIndex)
    }

    /// The move as the lineage report and the evolution interface phrase it:
    /// `moved in 15.0: SwiftUI → SwiftUICore`, the images of one side joined
    /// by ` + `.
    public func phrase(on versions: [ABIVersionDescriptor]) -> String {
        "moved \(placement(on: versions)): \(oldImageNames.joined(separator: " + ")) → \(newImageNames.joined(separator: " + "))"
    }
}

/// One image of an evolution over groups of images and the versions holding
/// it (evolution proposal `image-group-evolution`) — a line of the image
/// group's legend in the lineage report and the evolution interface.
public struct ImagePresence: Sendable, Equatable {
    public let imageName: String
    /// Per version on the axis, whether its group holds the image.
    public let presence: [Bool]

    public init(imageName: String, presence: [Bool]) {
        self.imageName = imageName
        self.presence = presence
    }
}

extension ABIEvolution {
    /// For an evolution over groups of images: every image, in the order it
    /// first appears on the axis (an older version first, the group's order
    /// within one), with the versions holding it. `nil` when every version is
    /// one image.
    public var imagePresences: [ImagePresence]? {
        guard versions.contains(where: { $0.imageNames != nil }) else { return nil }
        var orderedImageNames: [String] = []
        for version in versions {
            for imageName in version.imageNames ?? [] where !orderedImageNames.contains(imageName) {
                orderedImageNames.append(imageName)
            }
        }
        return orderedImageNames.map { imageName in
            ImagePresence(imageName: imageName, presence: versions.map { $0.imageNames?.contains(imageName) ?? false })
        }
    }
}

// MARK: - Merging a group

/// Which images hold the containers of one bucket, and their members, in one
/// version of an evolution over groups of images.
struct BucketImageAttribution {
    /// Container key → the images holding a container with that key, in the
    /// group's order. A type is held by the image defining it; the plain
    /// extensions folded into it do not count.
    var containerImageNames: [ABIKey: [String]] = [:]
    /// Container key → member identity → the images holding that member in
    /// the container a comparison keeps (the first with the key).
    var memberImageNames: [ABIKey: [ABIKey: [String]]] = [:]
}

/// One version's group of images merged into the single snapshot an
/// evolution compares, remembering which images each container and member
/// came from.
///
/// - Types, protocols and globals are concatenated in the group's order: a
///   key two images both carry is a real duplicate, compared first-wins and
///   surfaced as a key collision naming the dropped record's image.
/// - The containers of the four extension buckets merge by key, their
///   members concatenated in the group's order: two images extending one
///   type contribute to one extension.
/// - A plain extension — no conformance, no `where` clause, not retroactive —
///   of a type some image of the group defines folds into that type. Within
///   one image those members are the type's own (their mangling names no
///   extension); split across images, they would otherwise read as removed
///   from the type and added to an extension in the version the type moved.
/// - The version hides non-exported members when any of its images lacks
///   local Swift symbols (evolution proposal
///   `evolution-unobservable-presence`): an absence there may be hiding in
///   that image.
struct MergedImageGroup {
    /// The images of the group, in its order, each named once.
    let imageNames: [String]
    let snapshot: ABISnapshot
    let types: BucketImageAttribution
    let protocols: BucketImageAttribution
    let typeExtensions: BucketImageAttribution
    let protocolExtensions: BucketImageAttribution
    let typeAliasExtensions: BucketImageAttribution
    let conformanceExtensions: BucketImageAttribution
    /// Global identity → the images holding it.
    let globalVariableImageNames: [ABIKey: [String]]
    let globalFunctionImageNames: [ABIKey: [String]]
    /// The merged snapshot's key collisions, each dropped record named with
    /// its image.
    let keyCollisions: [ABIKeyCollision]

    /// A container gathered from the images of a group, with where each part
    /// came from.
    private struct AttributedContainer {
        var container: ContainerSnapshot
        /// The images holding the container, in the group's order.
        var imageNames: [String]
        /// Parallel to `container.members`: the image each member came from.
        var memberImageNames: [String]
    }

    init(_ images: [ABIImageSnapshot]) {
        var imageNames: [String] = []
        for image in images where !imageNames.contains(image.imageName) {
            imageNames.append(image.imageName)
        }
        self.imageNames = imageNames

        func concatenated(_ bucket: KeyPath<ABISnapshot, [ContainerSnapshot]>) -> [AttributedContainer] {
            images.flatMap { image in
                image.snapshot[keyPath: bucket].map { container in
                    AttributedContainer(
                        container: container,
                        imageNames: [image.imageName],
                        memberImageNames: Array(repeating: image.imageName, count: container.members.count)
                    )
                }
            }
        }

        func mergedByKey(_ bucket: KeyPath<ABISnapshot, [ContainerSnapshot]>) -> OrderedDictionary<ABIKey, AttributedContainer> {
            var merged: OrderedDictionary<ABIKey, AttributedContainer> = [:]
            for image in images {
                for container in image.snapshot[keyPath: bucket] {
                    let memberImageNames = Array(repeating: image.imageName, count: container.members.count)
                    if var existing = merged[container.key] {
                        existing.container.members += container.members
                        existing.memberImageNames += memberImageNames
                        if !existing.imageNames.contains(image.imageName) {
                            existing.imageNames.append(image.imageName)
                        }
                        merged[container.key] = existing
                    } else {
                        merged[container.key] = AttributedContainer(container: container, imageNames: [image.imageName], memberImageNames: memberImageNames)
                    }
                }
            }
            return merged
        }

        var types = concatenated(\.types)
        let protocols = concatenated(\.protocols)
        var typeExtensions = mergedByKey(\.typeExtensions)
        let protocolExtensions = Array(mergedByKey(\.protocolExtensions).values)
        let typeAliasExtensions = Array(mergedByKey(\.typeAliasExtensions).values)
        let conformanceExtensions = Array(mergedByKey(\.conformanceExtensions).values)

        // Fold every plain extension of a type the group defines into the
        // type a comparison keeps (the first with its key).
        var foldedTypeKeys: Set<ABIKey> = []
        for typeIndex in types.indices {
            guard foldedTypeKeys.insert(types[typeIndex].container.key).inserted else { continue }
            let typeSortKey = types[typeIndex].container.key.sortKey
            for kindToken in ["struct", "class", "enum"] {
                let plainExtensionKey = ABIDiffer.extensionContainerKey(
                    kindToken: kindToken,
                    targetSortKey: typeSortKey,
                    protocolSortKey: nil,
                    whereSortKey: nil,
                    isRetroactive: false
                )
                guard let plainExtension = typeExtensions.removeValue(forKey: plainExtensionKey) else { continue }
                types[typeIndex].container.members += plainExtension.container.members
                types[typeIndex].memberImageNames += plainExtension.memberImageNames
            }
        }

        let mergedTypeExtensions = Array(typeExtensions.values)
        let globalVariables = images.flatMap { image in image.snapshot.globalVariables.map { (record: $0, imageName: image.imageName) } }
        let globalFunctions = images.flatMap { image in image.snapshot.globalFunctions.map { (record: $0, imageName: image.imageName) } }

        let snapshot = ABISnapshot(
            types: types.map(\.container),
            protocols: protocols.map(\.container),
            typeExtensions: mergedTypeExtensions.map(\.container),
            protocolExtensions: protocolExtensions.map(\.container),
            typeAliasExtensions: typeAliasExtensions.map(\.container),
            conformanceExtensions: conformanceExtensions.map(\.container),
            globalVariables: globalVariables.map { $0.record },
            globalFunctions: globalFunctions.map { $0.record },
            hasLocalSwiftSymbols: images.allSatisfy(\.snapshot.hasLocalSwiftSymbols)
        )
        self.snapshot = snapshot
        self.types = Self.attribution(of: types)
        self.protocols = Self.attribution(of: protocols)
        self.typeExtensions = Self.attribution(of: mergedTypeExtensions)
        self.protocolExtensions = Self.attribution(of: protocolExtensions)
        self.typeAliasExtensions = Self.attribution(of: typeAliasExtensions)
        self.conformanceExtensions = Self.attribution(of: conformanceExtensions)
        self.globalVariableImageNames = Self.imageNamesByIdentity(of: globalVariables)
        self.globalFunctionImageNames = Self.imageNamesByIdentity(of: globalFunctions)
        // Parallel to the snapshot's arrays, in the order `keyCollisions`
        // walks them.
        let buckets = [types, protocols, mergedTypeExtensions, protocolExtensions, typeAliasExtensions, conformanceExtensions]
        self.keyCollisions = snapshot.keyCollisions(imageNames: SnapshotRecordImageNames(
            containerImageNames: buckets.map { bucket in bucket.map { $0.imageNames.first ?? "" } },
            memberImageNames: buckets.map { bucket in bucket.map(\.memberImageNames) },
            globalVariableImageNames: globalVariables.map { $0.imageName },
            globalFunctionImageNames: globalFunctions.map { $0.imageName }
        ))
    }

    private static func attribution(of containers: [AttributedContainer]) -> BucketImageAttribution {
        var attribution = BucketImageAttribution()
        for attributedContainer in containers {
            let containerKey = attributedContainer.container.key
            var containerImageNames = attribution.containerImageNames[containerKey] ?? []
            for imageName in attributedContainer.imageNames where !containerImageNames.contains(imageName) {
                containerImageNames.append(imageName)
            }
            attribution.containerImageNames[containerKey] = containerImageNames
            // A comparison keeps the first container with the key; its
            // members are the ones a lineage follows.
            guard attribution.memberImageNames[containerKey] == nil else { continue }
            attribution.memberImageNames[containerKey] = imageNamesByIdentity(of: zip(attributedContainer.container.members, attributedContainer.memberImageNames).map { (record: $0, imageName: $1) })
        }
        return attribution
    }

    private static func imageNamesByIdentity(of records: [(record: MemberRecord, imageName: String)]) -> [ABIKey: [String]] {
        var imageNamesByIdentity: [ABIKey: [String]] = [:]
        for (record, imageName) in records {
            var imageNames = imageNamesByIdentity[record.identityKey] ?? []
            if !imageNames.contains(imageName) {
                imageNames.append(imageName)
            }
            imageNamesByIdentity[record.identityKey] = imageNames
        }
        return imageNamesByIdentity
    }
}

// MARK: - Moves

extension ImageMove {
    /// The moves along one lineage, from its per-version observations and the
    /// images holding it where it was observed present (`nil` elsewhere).
    ///
    /// Two observations of the declaration present, with nothing between
    /// them but versions that could not show it, are compared: different
    /// images make a move, placed at the later one and — when versions lie
    /// between — spanning them. An observed absence in between ends the
    /// comparison: what reappears after a removal was added, not moved. The
    /// images compare as sets, so a caller listing a version's images in
    /// another order moves nothing; a move reports them in each version's
    /// group order.
    ///
    /// A member passes its container's images as `containerImageNames`: a
    /// move it made along with its container — the same images on both
    /// sides — is the container's, and recording it again for every member
    /// would bury the members that moved on their own.
    static func moves(
        observations: [PresenceObservation],
        imageNames: [[String]?],
        containerImageNames: [[String]?]? = nil
    ) -> [ImageMove] {
        var moves: [ImageMove] = []
        var lastObservedPresentIndex: Int?
        for versionIndex in observations.indices {
            switch observations[versionIndex] {
            case .present:
                if let previousIndex = lastObservedPresentIndex,
                   let oldImageNames = imageNames[previousIndex],
                   let newImageNames = imageNames[versionIndex],
                   Set(oldImageNames) != Set(newImageNames) {
                    let movedWithItsContainer = containerImageNames.map { containerImageNames in
                        containerImageNames[previousIndex].map { Set($0) } == Set(oldImageNames)
                            && containerImageNames[versionIndex].map { Set($0) } == Set(newImageNames)
                    } ?? false
                    if !movedWithItsContainer {
                        moves.append(ImageMove(
                            versionIndex: versionIndex,
                            oldImageNames: oldImageNames,
                            newImageNames: newImageNames,
                            earliestVersionIndex: versionIndex - previousIndex > 1 ? previousIndex + 1 : nil
                        ))
                    }
                }
                lastObservedPresentIndex = versionIndex
            case .absent:
                lastObservedPresentIndex = nil
            case .hidden:
                break
            }
        }
        return moves
    }
}
