import Testing
@testable import GhostTypeLib

// MARK: - Avatar properties removed from AppState

@Test func appStateHasNoAvatarProperties() {
    let state = AppState()
    // After avatar removal, these properties should not exist.
    // Verify the settings that remain are avatar-free by checking saveSettings
    // doesn't crash and panelWidth is the static constant (no avatar panel offset).
    #expect(state.panelWidth == 480)
    state.saveSettings()
}

// MARK: - PanelManager panel width is always the static prompt width

@Test func panelWidthIsAlwaysPromptWidth() {
    // panelWidth is a let constant on AppState — no avatar conditional logic.
    let state = AppState()
    #expect(state.panelWidth == 480)
}
