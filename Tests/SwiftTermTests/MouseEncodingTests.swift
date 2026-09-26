import Testing
@testable import SwiftTerm

/// Any-event hover (`?1003h`) carries Cb 3 ("no button") + 32 ("motion") = 35.
/// Under SGR that must stay a motion report with final `M`; reading it as a
/// release (`CSI <32;x;y m`, "left button released") made TUIs click whatever
/// the pointer passed over.
final class MouseEncodingTests {
    private let esc = "\u{1b}"

    private func sent(_ modes: String, _ body: (Terminal) -> Void) -> String {
        let (terminal, delegate) = TerminalTestHarness.makeTerminal()
        terminal.feed(text: modes)
        body(terminal)
        return String(decoding: delegate.sentData.flatMap { $0 }, as: UTF8.self)
    }

    private func hover(_ terminal: Terminal) {
        let flags = terminal.encodeButton(button: 0, release: true, shift: false, meta: false, control: false)
        terminal.sendMotion(buttonFlags: flags, x: 4, y: 2, pixelX: 40, pixelY: 30)
    }

    @Test func testSgrHoverIsNoButtonMotion() {
        #expect(sent("\(esc)[?1003h\(esc)[?1006h", hover) == "\(esc)[<35;5;3M")
    }

    @Test func testSgrPixelHoverIsNoButtonMotion() {
        #expect(sent("\(esc)[?1003h\(esc)[?1016h", hover) == "\(esc)[<35;40;30M")
    }

    @Test func testSgrReleaseStillEndsInLowercaseM() {
        let out = sent("\(esc)[?1003h\(esc)[?1006h") { terminal in
            let press = terminal.encodeButton(button: 0, release: false, shift: false, meta: false, control: false)
            let release = terminal.encodeButton(button: 0, release: true, shift: false, meta: false, control: false)
            terminal.sendEvent(buttonFlags: press, x: 4, y: 2)
            terminal.sendEvent(buttonFlags: release, x: 4, y: 2)
        }
        #expect(out == "\(esc)[<0;5;3M\(esc)[<0;5;3m")
    }

    @Test func testSgrDragWithLeftButtonIsMotion() {
        let out = sent("\(esc)[?1003h\(esc)[?1006h") { terminal in
            let flags = terminal.encodeButton(button: 0, release: false, shift: false, meta: false, control: false)
            terminal.sendMotion(buttonFlags: flags, x: 4, y: 2, pixelX: 40, pixelY: 30)
        }
        #expect(out == "\(esc)[<32;5;3M")
    }

    @Test func testReleaseRule() {
        #expect(Terminal.isSgrRelease(3))
        #expect(Terminal.isSgrRelease(3 | 4 | 8 | 16))
        #expect(!Terminal.isSgrRelease(3 + 32))
        #expect(!Terminal.isSgrRelease(3 + 64))
        #expect(!Terminal.isSgrRelease(0))
        #expect(!Terminal.isSgrRelease(32))
    }
}
