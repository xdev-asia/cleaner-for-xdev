import Foundation

extension Int64 {
    /// Decimal units, as Finder shows them.
    var bytes: String { formatted(.byteCount(style: .file)) }
}

extension String {
    /// Path with the home folder shortened to `~`.
    var tilde: String {
        let home = NSHomeDirectory()
        return self == home ? "~" : hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }
}
