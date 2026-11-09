import Foundation

extension Rules {
    /// Rules usable inside the App Sandbox: only those that move files to the Trash. Tools cannot be run from a
    /// sandboxed app, and emptying the Trash is left out so the Mac App Store edition never deletes permanently.
    public static let sandboxed: [Rule] = standard.filter { $0.action == .trashItem || $0.action == .trashContents }
}

public enum UserHome {
    /// The account's home folder. Inside the App Sandbox `NSHomeDirectory()` returns the app's container instead.
    public static let path: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()
}
