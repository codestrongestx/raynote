# RayNote

A native macOS floating Markdown notebook. Keep notes a click away in the menu bar, pin the window above other apps, and store your notes as ordinary Markdown files.

RayNote is an early preview, inspired by Raycast Notes and independently developed. It is not affiliated with Raycast and does not claim exact visual parity.

## Features

- No account, subscription, or application-imposed note count or storage quota. Available disk space and memory remain practical limits.
- Native AppKit text editing with undo/redo, selection, spell checking, and find/replace.
- Live Markdown headings, emphasis, lists, checkboxes, code, quotes, rules, tables, and local image previews, plus source and reading views.
- Markdown import/export with portable local image attachments; paste PNG/TIFF images directly into a note.
- Menu-bar access, right-click actions, a Keep on Top pin, configurable global shortcut, and System/Light/Dark appearance.
- Atomic local saves, recovery drafts for failed writes, preservation of detected outside edits, and recoverable note deletion.

## Build and install

Requires macOS 14 or later and an Xcode or Command Line Tools installation providing Swift 6 or later. There are no external Swift package dependencies.

From the repository directory:

```sh
swift --version
./scripts/build-app.sh
open dist/RayNote.app
```

To install, quit RayNote and copy `dist/RayNote.app` into Applications. The built app runs without the source tree or developer tools. It has a Dock icon and also appears in the menu bar.

The build script generates the app icon and signs the bundle locally with an ad-hoc signature. This is not a Developer ID signed or notarized public binary release.

## Use

Click the menu-bar note icon to show or hide the window. Right-click it, or Control-click, for note actions and Settings. The header pin toggles Keep on Top. Right-click the header or editor for additional actions; the editor retains native Cut/Copy/Paste options.

Change the theme in **Settings → Appearance**: System, Light, or Dark. The window keeps the size you choose across note switches and app restarts. Drag an edge to resize it; **View → Fit Window to Note** fits the current note once when requested. Settings controls the global shortcut. **Actions → Keyboard Shortcuts** shows the current bindings.

| Shortcut | Action |
| --- | --- |
| Control–Option–N | Show or hide the floating window globally |
| Command–N | New note |
| Command–P | Search title and contents / switch note |
| Command–K | Actions |
| Command–/ | Complete keyboard shortcut reference |
| Command–F | Find within the current note |
| Command–G / Command–Shift–G | Next / previous match |
| Command–Option–F | Find and replace |
| Command–B / Command–I | Markdown bold / italic |
| Command–E / Command–L | Inline code / link |
| Command–Option–1 / 2 / 3 | Heading level |
| Command–Option–C | Fenced code block |
| Command–Shift–S / B | Strikethrough / quote |
| Command–Shift–7 / 8 / 9 | Ordered list / bullets / checklist |
| Command–Return | Toggle task completion, or create a task |
| Command–Shift–F | Show / hide formatting bar |
| Command–Shift–M | Switch styled Markdown and raw source |
| Command–Shift–P | Toggle native reading view |
| Tab / Shift–Tab | Indent / outdent selected lines |
| Up / Down / Return | Choose a result in note search |
| Escape | Hide the window |

Markdown delimiters are hidden on inactive lines and shown while editing. The underlying text remains Markdown. Return continues lists; Return on an empty list item exits it. Click a table row or local image preview to edit its source. Escape dismisses the find bar before hiding the window.

## Your data

Notes are UTF-8 `.md` files under:

```text
~/Library/Application Support/RayNote/Notes
```

Images are stored in `Notes/Attachments`. Deleted notes move to `Notes/Recently Deleted` and can be restored from Actions. Recovery drafts, when needed, live in the sibling `Notes.recovery` directory. Back up the entire RayNote directory, including attachments and recovery drafts.

Updating or moving the app does not move the note library. There is no cloud synchronization or application-level encryption. Reading view can load remote HTTP(S) images referenced by a note; those requests go to the image host. Import/export does not download remote images.

## Development

```sh
swift test
./scripts/build-app.sh
```

For UI testing with an isolated library and preferences:

```sh
./scripts/build-qa-app.sh
open .build/RayNoteQA.app
```

The QA app stores notes under `.build/qa-library`. Build output, QA data, and local scan reports are excluded from version control. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and verification guidance.

## Known limitations

- This is a Markdown subset, not complete CommonMark conformance. Multiline inline-code spans are not supported in the live editor.
- Remote images appear as source in the live editor and load in reading view. Inline images render as alternative text in paragraphs.
- Large libraries load into memory; very large notes and libraries may affect responsiveness.
- Detected external changes are preserved before saving, but concurrent writes from other applications are not transactionally coordinated.
- Global shortcuts depend on macOS registration and may conflict with other apps. Choose another binding in Settings when necessary.
- Exact Raycast appearance across macOS versions and desktop backgrounds is not guaranteed.

## License

[MIT](LICENSE). Copyright (c) 2026 codestrongestx.
