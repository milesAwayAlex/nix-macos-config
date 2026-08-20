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

## Vim

Every custom key from `modules/home/vim/config.vim`; leader is `,`.

| Key | Result |
|---|---|
| `,w` | save |
| `,<CR>` | clear search highlight |
| `gb` / `gB` | next / previous buffer |
| `,sp` | toggle spell check |
| `*` / `#` (visual) | search down / up for the selection |
| `^T` | NERDTree toggle |
| `^P` | fzf file picker (`:Files`) |
| `,b` | fzf buffer picker (`:Buffers`) |
| `,/` | ripgrep the project (`:Rg`) |

### LSP

Served by yegappan/lsp. Anything a given language server does not implement
reports itself as unsupported rather than failing silently.

| Key | Command | Result |
|---|---|---|
| `gd` / `gy` / `gi` | `:LspGotoDefinition` / `GotoTypeDef` / `GotoImpl` | jump to definition / type definition / implementation |
| `gr` | `:LspShowReferences` | references (backlinks, in markdown) |
| `K` | `:LspHover` | hover popup |
| `,rn` | `:LspRename` | rename symbol across the workspace |
| `,f` | — | format (server, else `formatprg`) |
| `,a` | `:LspCodeAction` | code actions at the cursor, or over a visual range |
| `,qf` | `:LspAutoFix` | apply the first fix for the problem on this line |
| `,i` | `:LspOrganizeImports` | organize imports |
| `,cl` | `:LspCodeLens` | run the code lens on this line |
| `,lo` | `:LspDocumentSymbol` | outline of this file |
| `,ls` | `:LspSymbolSearch` | search symbols across the workspace |
| `,n` / `,p` | `:LspDiag next` / `prev` | next / previous diagnostic |
| `,ld` | `:LspDiag show` | all diagnostics for the buffer |

Useful commands with no key: `:LspFixAll`, `:LspPeekReferences`,
`:LspIncomingCalls` / `:LspOutgoingCalls`, `:LspShowSignature`,
`:LspSelectionExpand` / `:LspSelectionShrink`, `:LspHighlight` (and
`:LspHighlightClear`), `:LspFold`. For debugging a server:
`:LspServer show status`, `:LspServer show capabilities`,
`:LspServer restart`, `:LspServer debug on`.

Insert/command mode: doubling `"` `'` `(` `[` `{` `<` closes the pair and
lands the cursor inside; doubling the *closer* (`))` `]]` `}}`) gives the
padded form `{ | }`; ` ``` ` opens a fenced code block; `(<CR>` `[<CR>`
`{<CR>` open an indented block.

`,f` formats through the language server where it offers formatting, and
through `formatprg` where it does not (markdown → deno fmt, SQL →
sqlfluff); `gq` always uses `formatprg`.

Completion needs no key: the menu appears as you type. `<C-x><C-o>`
triggers it manually. Accept with `<C-y>`, dismiss with `<C-e>`, move with
`<C-n>` / `<C-p>` — vim's own insert-completion keys.

Recovery: `/usr/bin/vim` runs the old CoC setup untouched — the full path
is the escape hatch, since plain `vi` also resolves to the nix vim.
