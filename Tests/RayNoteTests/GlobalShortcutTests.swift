import AppKit
import Carbon
import XCTest
@testable import RayNote

final class GlobalShortcutTests: XCTestCase {
    func testRecordingRequiresUsefulModifier() throws {
        let plain = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: UInt16(kVK_ANSI_N)))
        XCTAssertNil(GlobalShortcut.from(event: plain))
        let shifted = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0, context: nil, characters: "N", charactersIgnoringModifiers: "N", isARepeat: false, keyCode: UInt16(kVK_ANSI_N)))
        XCTAssertNil(GlobalShortcut.from(event: shifted))
    }
    func testRecordingProducesCarbonModifiersAndReadableLabel() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "N", charactersIgnoringModifiers: "N", isARepeat: false, keyCode: UInt16(kVK_ANSI_N)))
        let shortcut = try XCTUnwrap(GlobalShortcut.from(event: event))
        XCTAssertEqual(shortcut.modifiers, UInt32(controlKey | optionKey | shiftKey))
        XCTAssertEqual(shortcut.label, "⌃⌥⇧N")
        XCTAssertEqual(shortcut.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(try JSONDecoder().decode(GlobalShortcut.self, from: JSONEncoder().encode(shortcut)), shortcut)
    }
}
