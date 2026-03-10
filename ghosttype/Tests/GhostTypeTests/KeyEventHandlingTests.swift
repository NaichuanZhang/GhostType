import Testing
@testable import GhostTypeLib
import Cocoa

// MARK: - Key event routing tests

@Test func shiftEnterInsertsNewline() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: .shift,
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .insertNewline)
}

@Test func plainEnterWithResponseHandlesEnter() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: [],
        hasResponse: true,
        isGenerating: false
    )
    #expect(action == .handleEnter)
}

@Test func plainEnterWithoutResponsePassesThrough() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: [],
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .passThrough)
}

@Test func escapeKeyDismisses() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 53,
        modifierFlags: [],
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .dismiss)
}

@Test func shiftEnterDuringGenerationStillInsertsNewline() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: .shift,
        hasResponse: false,
        isGenerating: true
    )
    #expect(action == .insertNewline)
}

@Test func otherKeysPassThrough() {
    // keyCode 0 = 'A' key
    let action = PanelManager.routeKeyEvent(
        keyCode: 0,
        modifierFlags: [],
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .passThrough)
}

@Test func cmdEnterSubmits() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: .command,
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .submit)
}

@Test func cmdEnterSubmitsDuringGeneration() {
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: .command,
        hasResponse: true,
        isGenerating: true
    )
    #expect(action == .submit)
}

@Test func cmdShiftEnterInsertsNewline() {
    // Cmd+Shift+Enter falls through to the shift check — no accidental submit
    let action = PanelManager.routeKeyEvent(
        keyCode: 36,
        modifierFlags: [.command, .shift],
        hasResponse: false,
        isGenerating: false
    )
    #expect(action == .insertNewline)
}
