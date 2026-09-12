# Storage and Markdown

## Your data

Notes are UTF-8 `.md` files under:

```text
~/Library/Application Support/RayNote/Notes
```

Images are stored in `Notes/Attachments`. Deleted notes move to `Notes/Recently Deleted` and can be restored from Actions. Recovery drafts, when needed, live in the sibling `Notes.recovery` directory. Back up the entire RayNote directory, including attachments and recovery drafts.

Updating or moving the app does not move the note library. There is no cloud synchronization or application-level encryption. Reading view can load remote HTTP(S) images referenced by a note; those requests go to the image host. Import/export does not download remote images.

## Known limitations

- This is a Markdown subset, not complete CommonMark conformance. Multiline inline-code spans are not supported in the live editor.
- Remote images appear as source in the live editor and load in reading view. Inline images render as alternative text in paragraphs.
- Large libraries load into memory; very large notes and libraries may affect responsiveness.
- Detected external changes are preserved before saving, but concurrent writes from other applications are not transactionally coordinated.
- Global shortcuts depend on macOS registration and may conflict with other apps. Choose another binding in Settings when necessary.
- Exact Raycast appearance across macOS versions and desktop backgrounds is not guaranteed.

