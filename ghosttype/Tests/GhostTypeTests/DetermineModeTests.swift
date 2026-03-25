import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - determineMode Tests

@Test func determineModeFixForGrammarPrompt() {
    #expect(PromptPanelView.determineMode(prompt: "Fix the grammar", hasContext: true) == "fix")
    #expect(PromptPanelView.determineMode(prompt: "fix spelling errors", hasContext: false) == "fix")
    #expect(PromptPanelView.determineMode(prompt: "Check my grammar", hasContext: true) == "fix")
}

@Test func determineModeTranslatePrompt() {
    #expect(PromptPanelView.determineMode(prompt: "Translate to Spanish", hasContext: true) == "translate")
    #expect(PromptPanelView.determineMode(prompt: "Please translate this to French", hasContext: false) == "translate")
}

@Test func determineModeRewriteWithContext() {
    #expect(PromptPanelView.determineMode(prompt: "Rewrite this", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Make it shorter", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Expand on this", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Make it professional", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Make it friendly", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Change the tone", hasContext: true) == "rewrite")
    #expect(PromptPanelView.determineMode(prompt: "Make it concise", hasContext: true) == "rewrite")
}

@Test func determineModeRewriteWithoutContextIsGenerate() {
    // Without context, rewrite-like prompts default to generate
    #expect(PromptPanelView.determineMode(prompt: "Rewrite this text", hasContext: false) == "generate")
    #expect(PromptPanelView.determineMode(prompt: "Make it shorter", hasContext: false) == "generate")
}

@Test func determineModeDefaultsToGenerate() {
    #expect(PromptPanelView.determineMode(prompt: "Write me a poem", hasContext: false) == "generate")
    #expect(PromptPanelView.determineMode(prompt: "What is Swift?", hasContext: true) == "generate")
    #expect(PromptPanelView.determineMode(prompt: "Hello", hasContext: false) == "generate")
}

@Test func determineModeFixTakesPriorityOverRewrite() {
    // "fix" keyword should trigger fix mode even with context
    #expect(PromptPanelView.determineMode(prompt: "Fix and rewrite this", hasContext: true) == "fix")
}

@Test func determineModeTranslateTakesPriorityOverRewrite() {
    #expect(PromptPanelView.determineMode(prompt: "Translate and rephrase", hasContext: true) == "translate")
}
