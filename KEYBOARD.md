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

## Tmux

Custom controls from `modules/home/tmux.nix`; everything below is
prefix-then-key. Prefix: `^Space` - tap and **release** space before the
command key (space still held acts as shift). A `*` after the `[session]`
tab in the status bar means the prefix is armed.

| Key | Result |
|---|---|
| `v` / `s` | split below / right, inheriting the pane's directory |
| `V` / `S` | same splits, from the session's start directory |
| `c` / `C` | new window right after this one (pane dir) / at the first free slot (start dir) |
| `b` | last window |
| `N` / `P` | next / previous window **with activity** (plain `n`/`p` = any window) |
| `T` | swap current window with slot 0 |
| `B` | last session |
| `Q` | flash pane numbers |
| `q` | toggle the status bar |
| `h j k l` | move between panes |
| `H J K L` | resize by one cell (repeats; flashes the new size) |
| `[` | copy mode - `v` select, `y` yank (stays in copy mode; yank lands on the macOS clipboard) |
| `g` | render clipboard markdown in an 80-column glow split (`q` closes it) |
| `y` | copy the pane's whole scrollback to the macOS clipboard |
