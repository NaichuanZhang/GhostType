import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - determineMode Tests

@Test func determineModeFixForGrammarPrompt() {
    #expect(ModeDetector.detect(prompt: "Fix the grammar", hasContext: true) == "fix")
    #expect(ModeDetector.detect(prompt: "fix spelling errors", hasContext: false) == "fix")
    #expect(ModeDetector.detect(prompt: "Check my grammar", hasContext: true) == "fix")
}

@Test func determineModeTranslatePrompt() {
    #expect(ModeDetector.detect(prompt: "Translate to Spanish", hasContext: true) == "translate")
    #expect(ModeDetector.detect(prompt: "Please translate this to French", hasContext: false) == "translate")
}

@Test func determineModeRewriteWithContext() {
    #expect(ModeDetector.detect(prompt: "Rewrite this", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Make it shorter", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Expand on this", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Make it professional", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Make it friendly", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Change the tone", hasContext: true) == "rewrite")
    #expect(ModeDetector.detect(prompt: "Make it concise", hasContext: true) == "rewrite")
}

@Test func determineModeRewriteWithoutContextIsGenerate() {
    // Without context, rewrite-like prompts default to generate
    #expect(ModeDetector.detect(prompt: "Rewrite this text", hasContext: false) == "generate")
    #expect(ModeDetector.detect(prompt: "Make it shorter", hasContext: false) == "generate")
}

@Test func determineModeDefaultsToGenerate() {
    #expect(ModeDetector.detect(prompt: "Write me a poem", hasContext: false) == "generate")
    #expect(ModeDetector.detect(prompt: "What is Swift?", hasContext: true) == "generate")
    #expect(ModeDetector.detect(prompt: "Hello", hasContext: false) == "generate")
}

@Test func determineModeFixTakesPriorityOverRewrite() {
    // "fix" keyword should trigger fix mode even with context
    #expect(ModeDetector.detect(prompt: "Fix and rewrite this", hasContext: true) == "fix")
}

@Test func determineModeTranslateTakesPriorityOverRewrite() {
    #expect(ModeDetector.detect(prompt: "Translate and rephrase", hasContext: true) == "translate")
}
