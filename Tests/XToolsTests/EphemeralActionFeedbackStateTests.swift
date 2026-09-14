@testable import XTools
import Testing

struct EphemeralActionFeedbackStateTests {
    @Test func initialStateIsInactiveWithoutAGeneration() {
        let state = IndexEphemeralActionFeedbackState()

        #expect(!state.isPresented)
        #expect(state.generation == 0)
    }

    @Test func retriggerKeepsFeedbackPresentedAndInvalidatesTheOldCompletion() {
        var state = IndexEphemeralActionFeedbackState()

        state.trigger()
        let firstGeneration = state.generation
        #expect(state.isPresented)

        state.trigger()
        let secondGeneration = state.generation
        #expect(state.isPresented)
        #expect(secondGeneration != firstGeneration)

        let staleCompletionAccepted = state.finish(generation: firstGeneration)
        #expect(!staleCompletionAccepted)
        #expect(state.isPresented)
        #expect(state.generation == secondGeneration)
    }

    @Test func onlyTheLatestPresentedGenerationCanFinish() {
        var state = IndexEphemeralActionFeedbackState()

        state.trigger()
        let generation = state.generation

        let matchingCompletionAccepted = state.finish(generation: generation)
        #expect(matchingCompletionAccepted)
        #expect(!state.isPresented)
        #expect(state.generation == generation)

        let repeatedCompletionAccepted = state.finish(generation: generation)
        #expect(!repeatedCompletionAccepted)
    }
}
