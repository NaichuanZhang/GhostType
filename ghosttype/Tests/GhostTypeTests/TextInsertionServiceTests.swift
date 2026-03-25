import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - Web App Detection Tests

@Test func textInsertionServiceDetectsChromeAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.google.Chrome") == true)
    #expect(TextInsertionService.isWebBasedApp("com.google.Chrome.canary") == true)
}

@Test func textInsertionServiceDetectsVSCodeAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.microsoft.VSCode") == true)
    #expect(TextInsertionService.isWebBasedApp("com.microsoft.VSCode.insiders") == true)
}

@Test func textInsertionServiceDetectsBraveAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.brave.Browser") == true)
}

@Test func textInsertionServiceDetectsElectronApps() {
    #expect(TextInsertionService.isWebBasedApp("com.example.electron.app") == true)
}

@Test func textInsertionServiceDetectsSlackAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.tinyspeck.slackmacgap") == true)
}

@Test func textInsertionServiceDetectsDiscordAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.hnc.Discord") == true)
}

@Test func textInsertionServiceDetectsNotionAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("notion.id") == true)
}

@Test func textInsertionServiceDetectsFigmaAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.figma.Desktop") == true)
}

@Test func textInsertionServiceDetectsLinearAsWebApp() {
    #expect(TextInsertionService.isWebBasedApp("com.linear") == true)
}

@Test func textInsertionServiceNativeAppsAreNotWebBased() {
    #expect(TextInsertionService.isWebBasedApp("com.apple.TextEdit") == false)
    #expect(TextInsertionService.isWebBasedApp("com.apple.Notes") == false)
    #expect(TextInsertionService.isWebBasedApp("com.apple.dt.Xcode") == false)
    #expect(TextInsertionService.isWebBasedApp("com.apple.Terminal") == false)
}

// MARK: - Delegation consistency

@Test func promptPanelViewIsWebBasedAppDelegatesToService() {
    // Verify the static method on PromptPanelView delegates to TextInsertionService
    #expect(PromptPanelView.isWebBasedApp("com.google.Chrome") == TextInsertionService.isWebBasedApp("com.google.Chrome"))
    #expect(PromptPanelView.isWebBasedApp("com.apple.TextEdit") == TextInsertionService.isWebBasedApp("com.apple.TextEdit"))
}
