import Foundation

package enum MachOFileName: String {
    case iOS_22E238_Simulator_SwiftUI = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUI.framework"
    case iOS_22E238_Simulator_SwiftUICore = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework"
    case iOS_18_5_Simulator_SwiftUI = "/Library/Developer/CoreSimulator/Volumes/iOS_22F77/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    case iOS_26_2_Simulator_SwiftUI = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.2.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    case iOS_26_2_Simulator_SwiftUICore = "/Library/Developer/CoreSimulator/Volumes/iOS_23C54/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.2.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"

    case SourceEdit = "/Applications/SourceEdit.app"
    case SourceEditorFromSourceEdit = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework"
    case SourceEditorFromXcode = "/Applications/Xcode.app/Contents/SharedFrameworks/SourceEditor.framework"

    case Finder = "/System/Library/CoreServices/Finder.app"
    case Dock = "/System/Library/CoreServices/Dock.app"
    case iPhoneMirroring = "/System/Applications/iPhone Mirroring.app"
    case ScreenContinuityUI = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework"
    case ControlCenter = "/System/Library/CoreServices/ControlCenter.app"
    case Freeform = "/System/Applications/Freeform.app"

    case SymbolTests = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTests.framework/Versions/A/SymbolTests"
    case SymbolTestsCore = "../../Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore"
}
