import Foundation
import LaunchDeckCore

@main
struct LaunchDeckCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        switch args.first {
        case "domains":
            for domain in LaunchDomain.standard() {
                let mode = domain.allowsWrites ? "writable" : "read-only"
                print("\(domain.name)\t\(mode)\t\(domain.url.path)")
            }
        case "version":
            print("\(LaunchDeck.appName) 0.1.0")
        default:
            print("Usage: launchdeck <domains|version>")
        }
    }
}
