import Testing
import Cocoa
@testable import GhostTypeLib

@Test @MainActor func floatingPanelHidesStandardWindowButtons() {
    let panel = FloatingPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
        styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    #expect(panel.standardWindowButton(.closeButton)?.isHidden == true)
    #expect(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
    #expect(panel.standardWindowButton(.zoomButton)?.isHidden == true)
}
