import Testing
@testable import GhostTypeLib

// MARK: - isWebBasedApp: newly added apps

@Test func slackIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.tinyspeck.slackmacgap"))
}

@Test func discordIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.hnc.Discord"))
}

@Test func teamsIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.microsoft.teams"))
    #expect(PromptPanelView.isWebBasedApp("com.microsoft.teams2"))
}

@Test func notionIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("notion.id"))
}

@Test func figmaIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.figma.Desktop"))
}

@Test func linearIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.linear"))
}

// MARK: - isWebBasedApp: previously supported apps still work

@Test func chromeIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.google.Chrome"))
    #expect(PromptPanelView.isWebBasedApp("com.google.Chrome.canary"))
}

@Test func vscodeIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.microsoft.VSCode"))
}

@Test func braveIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.brave.Browser"))
}

@Test func operaIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.operasoftware.Opera"))
}

@Test func genericElectronAppIsDetectedAsWebBasedApp() {
    #expect(PromptPanelView.isWebBasedApp("com.example.electron.myapp"))
}

// MARK: - isWebBasedApp: native apps are NOT detected

@Test func nativeAppsAreNotWebBased() {
    #expect(!PromptPanelView.isWebBasedApp("com.apple.TextEdit"))
    #expect(!PromptPanelView.isWebBasedApp("com.apple.Notes"))
    #expect(!PromptPanelView.isWebBasedApp("com.apple.dt.Xcode"))
    #expect(!PromptPanelView.isWebBasedApp("com.apple.Safari"))
    #expect(!PromptPanelView.isWebBasedApp("com.apple.Terminal"))
}
