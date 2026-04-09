import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - Action Trigger Tests (replaced NotificationCenter)

@Suite("Action Trigger Tests")
struct ActionTriggerTests {
    @Test("action triggers start at zero")
    func initialValues() {
        let state = AppState()
        #expect(state.enterAction == 0)
        #expect(state.submitAction == 0)
        #expect(state.dismissAction == 0)
    }

    @Test("incrementing enter action wraps around UInt overflow")
    func enterActionIncrement() {
        let state = AppState()
        state.enterAction &+= 1
        #expect(state.enterAction == 1)
        state.enterAction &+= 1
        #expect(state.enterAction == 2)
    }

    @Test("incrementing submit action works")
    func submitActionIncrement() {
        let state = AppState()
        state.submitAction &+= 1
        #expect(state.submitAction == 1)
    }

    @Test("incrementing dismiss action works")
    func dismissActionIncrement() {
        let state = AppState()
        state.dismissAction &+= 1
        #expect(state.dismissAction == 1)
    }

    @Test("UInt overflow wraps to zero")
    func overflowWrap() {
        let state = AppState()
        state.enterAction = UInt.max
        state.enterAction &+= 1
        #expect(state.enterAction == 0)
    }
}
