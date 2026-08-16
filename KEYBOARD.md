# Keyboard chord cheatsheet

Chords provided by the Karabiner rules in
`modules/home/karabiner/karabiner.json`, written as typed under Programmer
Dvorak. Mechanics: `ctrl` is consumed by the mapping; `shift`/`option` pass
through where noted; `cmd` chords exist only where listed - every other
`ctrl+cmd+…` combination passes through raw to macOS.

## Universal

| Chord | Result | Variants |
|---|---|---|
| `^I` | Tab | `shift` → backtab · `^⌘I` → ⌘Tab (app switcher; `+shift` cycles backwards) |
| `^[` | Escape | - |
| `^M` | Return | `shift`/`option` pass through · `^⌘M` → ⌘Return ("send" in most chat/mail apps) |
| `^H` | Backspace | `option` → word-delete · `^⌘H` → ⌘⌫ (delete to line start) · in terminals this posts DEL (0x7f), not raw 0x08 |

## GUI apps only (not in Alacritty)

| Chord | Result | Variants |
|---|---|---|
| `^B` | ← | `shift` = select · `option` = word-back · `^⌘B` → ⌘← (line start; Back in browsers outside text fields) |
| `^F` | → | `shift` = select · `option` = word-forward · `^⌘F` **not captured** - macOS fullscreen toggle |
| `^P` | ↑ | `shift`/`option` pass through · `^⌘P` → ⌘↑ (top of page/document; Finder: parent folder) |
| `^N` | ↓ | `shift`/`option` pass through · `^⌘N` → ⌘↓ (bottom of page/document; Finder: open item) |
| `^W` | ⌥⌫ (delete word back) | - |
| `^U` | ⌘⌫ (delete to line start) | - |

## Spacebar

Space acts as **Shift** while held with another key; pressed and released
alone it posts a space (release within 1 s - a longer lone hold posts
nothing).
