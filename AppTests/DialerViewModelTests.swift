import XCTest
@testable import VoIPCall

@MainActor
final class DialerViewModelTests: XCTestCase {

    func testTypingDigits() {
        let viewModel = DialerViewModel()
        XCTAssertFalse(viewModel.canCall)

        for key in ["5", "5", "5", "*", "#"] {
            viewModel.press(key)
        }
        XCTAssertEqual(viewModel.number, "555*#")
        XCTAssertTrue(viewModel.canCall)
    }

    func testRejectsInvalidCharacters() {
        let viewModel = DialerViewModel()
        viewModel.press("a")
        viewModel.press("")
        viewModel.press(" ")
        XCTAssertEqual(viewModel.number, "")
    }

    func testPlusOnlyAllowedAsPrefix() {
        let viewModel = DialerViewModel()
        viewModel.press("+")
        viewModel.press("1")
        viewModel.press("+")
        XCTAssertEqual(viewModel.number, "+1")
    }

    func testLongPressZero() {
        let viewModel = DialerViewModel()
        viewModel.longPressZero()
        XCTAssertEqual(viewModel.number, "+")
        viewModel.longPressZero()
        XCTAssertEqual(viewModel.number, "+0")
    }

    func testSymbolsOnlyCannotBeCalled() {
        let viewModel = DialerViewModel()
        viewModel.press("*")
        viewModel.press("#")
        XCTAssertFalse(viewModel.canCall)
    }

    func testMaxLength() {
        let viewModel = DialerViewModel()
        for _ in 0..<(DialerViewModel.maxLength + 5) {
            viewModel.press("9")
        }
        XCTAssertEqual(viewModel.number.count, DialerViewModel.maxLength)
    }

    func testDeleteAndClear() {
        let viewModel = DialerViewModel()
        viewModel.paste("123")
        viewModel.deleteLast()
        XCTAssertEqual(viewModel.number, "12")
        viewModel.clear()
        XCTAssertEqual(viewModel.number, "")
        viewModel.deleteLast()
        XCTAssertEqual(viewModel.number, "")
    }

    func testPasteStripsFormatting() {
        let viewModel = DialerViewModel()
        viewModel.paste("+1 (555) 010-0101")
        XCTAssertEqual(viewModel.number, "+15550100101")

        viewModel.paste("call 555+0100 now")
        XCTAssertEqual(viewModel.number, "5550100")
    }
}
