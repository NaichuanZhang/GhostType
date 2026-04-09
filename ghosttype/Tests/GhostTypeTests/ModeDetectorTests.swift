import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - ModeDetector Tests

@Suite("ModeDetector Tests")
struct ModeDetectorTests {
    @Test("fix mode for grammar/fix/spelling prompts")
    func fixMode() {
        #expect(ModeDetector.detect(prompt: "Fix the grammar", hasContext: true) == "fix")
        #expect(ModeDetector.detect(prompt: "fix spelling errors", hasContext: false) == "fix")
        #expect(ModeDetector.detect(prompt: "Check my grammar", hasContext: true) == "fix")
    }

    @Test("translate mode for translate prompts")
    func translateMode() {
        #expect(ModeDetector.detect(prompt: "Translate to Spanish", hasContext: true) == "translate")
        #expect(ModeDetector.detect(prompt: "Please translate this to French", hasContext: false) == "translate")
    }

    @Test("rewrite mode with context")
    func rewriteWithContext() {
        #expect(ModeDetector.detect(prompt: "Rewrite this", hasContext: true) == "rewrite")
        #expect(ModeDetector.detect(prompt: "Make it shorter", hasContext: true) == "rewrite")
        #expect(ModeDetector.detect(prompt: "Make it professional", hasContext: true) == "rewrite")
        #expect(ModeDetector.detect(prompt: "Change the tone", hasContext: true) == "rewrite")
    }

    @Test("rewrite prompts without context default to generate")
    func rewriteWithoutContext() {
        #expect(ModeDetector.detect(prompt: "Rewrite this text", hasContext: false) == "generate")
        #expect(ModeDetector.detect(prompt: "Make it shorter", hasContext: false) == "generate")
    }

    @Test("defaults to generate for unknown prompts")
    func generateDefault() {
        #expect(ModeDetector.detect(prompt: "Write me a poem", hasContext: false) == "generate")
        #expect(ModeDetector.detect(prompt: "What is Swift?", hasContext: true) == "generate")
    }

    @Test("fix takes priority over rewrite")
    func fixPriority() {
        #expect(ModeDetector.detect(prompt: "Fix and rewrite this", hasContext: true) == "fix")
    }

    @Test("translate takes priority over rewrite")
    func translatePriority() {
        #expect(ModeDetector.detect(prompt: "Translate and rephrase", hasContext: true) == "translate")
    }
}
