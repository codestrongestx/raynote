import AppKit
import Carbon
import XCTest
@testable import RayNote

final class GlobalHotKeyTests: XCTestCase {
    private let first = GlobalShortcut(keyCode: UInt32(kVK_F18), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), key: "F18")
    private let second = GlobalShortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), key: "F19")

    @MainActor func testConflictPreservesExistingRegistrationAndReleasesOnDeinit() throws {
        _ = NSApplication.shared
        var owner: GlobalHotKey? = GlobalHotKey(action: {})
        let occupied = GlobalHotKey(action: {})
        XCTAssertEqual(owner?.replace(with: first), noErr)
        XCTAssertEqual(occupied.replace(with: second), noErr)
        XCTAssertEqual(owner?.replace(with: first), noErr, "Keeping the current key is idempotent")
        XCTAssertNotEqual(owner?.replace(with: second), noErr)
        XCTAssertEqual(owner?.current, first)
        let probe = GlobalHotKey(action: {})
        XCTAssertNotEqual(probe.replace(with: first), noErr, "The old binding must remain registered")
        owner = nil
        XCTAssertEqual(probe.replace(with: first), noErr, "Destroying the owner releases the binding")
    }

    @MainActor func testHandlerAcceptsOnlyItsRegisteredIdentifier() throws {
        _ = NSApplication.shared
        var count = 0
        let owner = GlobalHotKey { count += 1 }
        XCTAssertEqual(owner.replace(with: first), noErr)
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event), noErr)
        let value = try XCTUnwrap(event)
        defer { ReleaseEvent(value) }
        XCTAssertEqual(owner.handle(value), OSStatus(eventNotHandledErr))
        var wrong = EventHotKeyID(signature: owner.identifier.signature, id: owner.identifier.id + 1)
        XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &wrong), noErr)
        XCTAssertEqual(owner.handle(value), OSStatus(eventNotHandledErr))
        XCTAssertEqual(count, 0)
        var correct = owner.identifier
        XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &correct), noErr)
        XCTAssertEqual(owner.handle(value), noErr)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(owner.handle(value), noErr)
        XCTAssertEqual(count, 1, "A repeated press event must not toggle the window again")
        var release: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyReleased), 0, 0, &release), noErr)
        let released = try XCTUnwrap(release)
        defer { ReleaseEvent(released) }
        XCTAssertEqual(SetEventParameter(released, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &wrong), noErr)
        XCTAssertEqual(owner.handle(released), OSStatus(eventNotHandledErr))
        XCTAssertEqual(owner.handle(value), noErr)
        XCTAssertEqual(count, 1, "Another hotkey's release must not reset this binding")
        XCTAssertEqual(SetEventParameter(released, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &correct), noErr)
        XCTAssertEqual(owner.handle(released), noErr)
        XCTAssertEqual(owner.handle(value), noErr)
        XCTAssertEqual(count, 2)
    }

    @MainActor func testExclusiveRegistrationDetectsAnotherProcess() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("occupied.c")
        let executable = folder.appendingPathComponent("occupied")
        // The helper only holds a test key. It never creates or sends keyboard events.
        try """
        #include <Carbon/Carbon.h>
        #include <stdio.h>
        int main(void) {
            EventHotKeyRef key = NULL;
            EventHotKeyID id = { 0x54455354, 1 };
            OSStatus result = RegisterEventHotKey(\(first.keyCode), \(first.modifiers), id,
                GetApplicationEventTarget(), kEventHotKeyExclusive, &key);
            printf("%c", result == noErr ? 'Y' : 'N'); fflush(stdout);
            if (result != noErr) return 1;
            getchar();
            UnregisterEventHotKey(key);
            return 0;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = [source.path, "-framework", "Carbon", "-o", executable.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        let helper = Process(), input = Pipe(), output = Pipe()
        helper.executableURL = executable
        helper.standardInput = input; helper.standardOutput = output
        try helper.run()
        defer {
            try? input.fileHandleForWriting.close()
            helper.waitUntilExit()
        }
        XCTAssertEqual(output.fileHandleForReading.readData(ofLength: 1), Data("Y".utf8))
        let owner = GlobalHotKey(action: {})
        XCTAssertEqual(owner.replace(with: second), noErr)
        XCTAssertEqual(owner.replace(with: first), OSStatus(eventHotKeyExistsErr))
        XCTAssertEqual(owner.current, second)
    }
}
