package enum DyldSharedCachePath: String {
    case current = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e"
    case iOS_18_5 = "/Volumes/Generic/iOS Systems/22F76__iPhone17,5/dyld_shared_cache_arm64e"
    case iOS_26_1 = "/Volumes/Generic/iOS Systems/23B85__iPhone17,5/dyld_shared_cache_arm64e"
    case macOS_15_5 = "/Volumes/DyldSharedCaches/macOS/15.5/dyld_shared_cache_arm64e"
    case macOS_26_5_1 = "/Volumes/DyldSharedCaches/macOS/26.5.1/dyld_shared_cache_arm64e"
    case macOS_26_5_2 = "/Volumes/DyldSharedCaches/macOS/26.5.2/dyld_shared_cache_arm64e"
    case macOS_27_0 = "/Volumes/DyldSharedCaches/macOS/27.0/dyld_shared_cache_arm64e"
    /// From iOS 27 beta 3 on a simulator runtime ships its frameworks in a
    /// cache of its own instead of as files under `RuntimeRoot`.
    case iOS_27_0_Simulator = "/Library/Developer/CoreSimulator/Volumes/iOS_24A434/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64"
}
