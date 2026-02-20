import Cocoa

// SPM-compatible entry point — manually bootstraps NSApplication
// (SwiftUI @main App requires Xcode project with app bundle)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
