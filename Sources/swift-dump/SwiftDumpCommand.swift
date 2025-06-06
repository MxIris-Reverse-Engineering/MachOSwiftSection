import Foundation
import SwiftDump
import ArgumentParser

@main
struct SwiftDumpCommand: ParsableCommand {
    
    @Argument(help: "The path to the Mach-O file to dump.")
    var filePath: String
    
    
    func run() throws {
        
    }
}
