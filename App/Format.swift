import CleanerKit
import Foundation

extension Int64 {
    /// Decimal units, as Finder shows them.
    var bytes: String { formatted(.byteCount(style: .file)) }
}

/// The home folder the app works with. `--home <path>` swaps in a demo folder for screenshots.
enum AppHome {
    static let path: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--home"), i + 1 < args.count { return args[i + 1] }
        return UserHome.path
    }()
}

extension String {
    /// Path with the home folder shortened to `~`.
    var tilde: String {
        let home = AppHome.path
        return self == home ? "~" : hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }
}
