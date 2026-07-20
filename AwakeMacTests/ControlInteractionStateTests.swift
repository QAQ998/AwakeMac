import XCTest
@testable import AwakeMac

final class ControlInteractionStateTests: XCTestCase {
    func testCancellingCustomDurationRestoresOriginalValueAndClosesEditor() {
        var editor = CustomDurationEditorState()
        editor.present(currentMinutes: 90)
        editor.draftMinutes = 180

        editor.cancel()

        XCTAssertFalse(editor.isPresented)
        XCTAssertEqual(editor.draftMinutes, 90)
        XCTAssertNil(editor.apply())
    }

    func testApplyingCustomDurationClampsAndCommitsOnlyOnce() {
        var editor = CustomDurationEditorState()
        editor.present(currentMinutes: 60)
        editor.draftMinutes = 2_000

        XCTAssertEqual(editor.apply(), 1_440)
        XCTAssertFalse(editor.isPresented)
        XCTAssertNil(editor.apply())
    }

    func testSecondCustomDurationDisclosureTapCollapsesEditor() {
        var editor = CustomDurationEditorState()

        editor.toggle(currentMinutes: 90)
        XCTAssertTrue(editor.isPresented)
        editor.draftMinutes = 180

        editor.toggle(currentMinutes: 90)

        XCTAssertFalse(editor.isPresented)
        XCTAssertEqual(editor.draftMinutes, 90)
    }

    func testCustomDurationEditorCompletesThirtyCyclesWithoutResidualState() {
        var editor = CustomDurationEditorState()

        for iteration in 1...30 {
            let original = 30 + iteration
            editor.present(currentMinutes: original)
            editor.draftMinutes = original + 10

            if iteration.isMultiple(of: 2) {
                XCTAssertEqual(editor.apply(), original + 10)
                XCTAssertNil(editor.apply())
            } else {
                editor.cancel()
                XCTAssertEqual(editor.draftMinutes, original)
                XCTAssertNil(editor.apply())
            }
            XCTAssertFalse(editor.isPresented)
        }
    }

    func testWakePrerequisiteFeedbackRespectsReduceMotion() {
        var animated = LidPrerequisiteFeedbackState()
        animated.activate(reduceMotion: false)
        XCTAssertTrue(animated.isEmphasized)
        XCTAssertEqual(animated.shakeIteration, 1)

        var reducedMotion = LidPrerequisiteFeedbackState()
        reducedMotion.activate(reduceMotion: true)
        XCTAssertTrue(reducedMotion.isEmphasized)
        XCTAssertEqual(reducedMotion.shakeIteration, 0)

        reducedMotion.reset()
        XCTAssertFalse(reducedMotion.isEmphasized)
    }

    func testLidActivationPolicyExplainsUnavailableStates() {
        XCTAssertEqual(
            LidInteractionPolicy.activation(hasClamshell: false, isAwake: false),
            .unavailable
        )
        XCTAssertEqual(
            LidInteractionPolicy.activation(hasClamshell: true, isAwake: false),
            .showWakePrerequisite
        )
        XCTAssertEqual(
            LidInteractionPolicy.activation(hasClamshell: true, isAwake: true),
            .requestConfirmation
        )
    }
}
