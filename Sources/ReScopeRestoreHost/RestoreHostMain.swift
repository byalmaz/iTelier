import Foundation
import ReScopeCore
import Darwin

@main struct ReScopeRestoreHostMain {
    static func main() async {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--backup" {
            exit(await BackupHost.runWorker(sessionPath: CommandLine.arguments[2]))
        }
        guard CommandLine.arguments.count == 2 else { exit(2) }
        exit(await RestoreHost.runWorker(sessionPath: CommandLine.arguments[1]))
    }
}
