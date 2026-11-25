import Foundation
import Testing
@testable import ZapretMacKit

@Test func shortcutShowsLettersInMacNotation() {
    #expect(GlobalShortcut(keyCode: 11, modifiers: [.control, .option]).displayString == "⌃⌥B")
    #expect(GlobalShortcut(keyCode: 0, modifiers: [.command, .shift]).displayString == "⇧⌘A")
    // Modifiers always come in menu order, whatever order they were given in.
    #expect(GlobalShortcut(keyCode: 35, modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘P")
}

@Test func shortcutShowsDigits() {
    #expect(GlobalShortcut(keyCode: 18, modifiers: .command).displayString == "⌘1")
    #expect(GlobalShortcut(keyCode: 29, modifiers: .option).displayString == "⌥0")
    #expect(GlobalShortcut(keyCode: 23, modifiers: .control).displayString == "⌃5")
}

@Test func shortcutShowsFunctionKeys() {
    #expect(GlobalShortcut(keyCode: 122, modifiers: .command).displayString == "⌘F1")
    #expect(GlobalShortcut(keyCode: 111, modifiers: [.control, .option, .shift]).displayString == "⌃⌥⇧F12")
    #expect(GlobalShortcut(keyCode: 90, modifiers: .option).displayString == "⌥F20")
}

@Test func shortcutShowsArrowsAndSpecialKeys() {
    #expect(GlobalShortcut(keyCode: 123, modifiers: .control).displayString == "⌃←")
    #expect(GlobalShortcut(keyCode: 124, modifiers: .control).displayString == "⌃→")
    #expect(GlobalShortcut(keyCode: 125, modifiers: .option).displayString == "⌥↓")
    #expect(GlobalShortcut(keyCode: 126, modifiers: .command).displayString == "⌘↑")
    #expect(GlobalShortcut(keyCode: 36, modifiers: .command).displayString == "⌘↩")
    #expect(GlobalShortcut(keyCode: 51, modifiers: .option).displayString == "⌥⌫")
}

@Test func shortcutNeedsCommandOptionOrControl() {
    #expect(GlobalShortcut(keyCode: 11, modifiers: .command).isValid)
    #expect(GlobalShortcut(keyCode: 11, modifiers: .option).isValid)
    #expect(GlobalShortcut(keyCode: 11, modifiers: .control).isValid)
    #expect(GlobalShortcut(keyCode: 11, modifiers: [.shift, .control]).isValid)
    #expect(!GlobalShortcut(keyCode: 11, modifiers: .shift).isValid)
    #expect(!GlobalShortcut(keyCode: 11, modifiers: []).isValid)
    #expect(!GlobalShortcut(keyCode: 111, modifiers: .shift).isValid)
}

@Test func shortcutCarbonModifiers() {
    // cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000
    #expect(GlobalShortcut(keyCode: 11, modifiers: [.control, .option]).carbonModifiers == 0x1800)
    #expect(GlobalShortcut(keyCode: 11, modifiers: [.command, .shift]).carbonModifiers == 0x300)
}

@Test func shortcutCodableRoundTrip() throws {
    let shortcut = GlobalShortcut(keyCode: 111, modifiers: [.control, .option, .shift])
    let data = try JSONEncoder().encode(shortcut)
    let back = try JSONDecoder().decode(GlobalShortcut.self, from: data)
    #expect(back == shortcut)
    #expect(back.displayString == "⌃⌥⇧F12")
}
