vim9script
# Sourced by the generated store vimrc (default.nix), which provides g:deps (nix store paths).

# Nothing manually dropped into ~/.vim can leak in here.
set packpath-=~/.vim
set packpath-=~/.vim/after
set runtimepath-=~/.vim
set runtimepath-=~/.vim/after

g:mapleader = ','

set scrolloff=7
set wildignore=*.o,*~,*.pyc,*/.git/*,*/.hg/*,*/.svn/*,*/.DS_Store
set whichwrap+=<,>,h,l
set hlsearch
set showmatch
set matchtime=2
set belloff=all
set nobackup
set nowritebackup
set noswapfile
set autoindent
set smartindent
set virtualedit=block
set switchbuf=useopen,usetab,newtab
set updatetime=300
set signcolumn=number
set termguicolors

# No status line: the ruler rides the command line (vim-sensible would
# otherwise set laststatus=2).
set laststatus=0

# Claim the buffer before vim's own detection does: our autocmds register
# here, vim's filetypedetect only at packloadall below, and same-event
# autocmds run in registration order. Retagging later (on FileType yaml)
# does set ft=helm, but the yaml syntax load that follows in the same
# event chain overwrites the helm one — ft right, highlighting wrong.
# ++nested lets setfiletype fire FileType, which loads the syntax.
augroup helmdetect
  autocmd!
  autocmd BufNewFile,BufRead *.yaml,*.yml,*.tpl ++nested {
    if expand('%:p') =~ '/templates/'
          && findfile('Chart.yaml', expand('%:p:h') .. ';') != ''
      setfiletype helm
    endif
  }
augroup END

# tmux focus-events feed FocusGained, so autoread actually fires.
autocmd FocusGained,BufEnter * silent! checktime

# Reopen files at the last edit position.
autocmd BufReadPost * {
  if line("'\"") > 1 && line("'\"") <= line("$")
    exe "normal! g'\""
  endif
}

# Search for the visual selection with * and #.
xnoremap <silent> * y/\V<C-R>=escape(@",'/\')<CR><CR>
xnoremap <silent> # y?\V<C-R>=escape(@",'?\')<CR><CR>

nmap <leader>w :w<cr>
map <silent> <leader><cr> :noh<cr>
nmap gb :bnext<cr>
nmap gB :bprevious<cr>
nnoremap <leader>sp <ScriptCmd>g:HarperEnable()<CR>:setlocal spell!<CR>

# Autoclose pairs.
noremap! "" ""<left>
noremap! '' ''<left>
noremap! (( ()<left>
noremap! [[ []<left>
noremap! {{ {}<left>
# Doubled closer = one trailing space, cursor against the opener: (| ),
noremap! )) ( )<left><left>
noremap! ]] [ ]<left><left>
noremap! }} { }<left><left>
noremap! <> <><left>
inoremap ``` ```<CR>```<ESC>kA

# Jump past the next closer on this line.
def EscapePair(): string
  var line = getline('.')
  var start = col('.') - 1
  var idx = match(line, '[]"''`)}>]', start)
  if idx < 0
    return ''
  endif
  return repeat("\<Right>", strchars(strpart(line, start, idx - start + 1)))
enddef
inoremap <silent><expr> <C-l> EscapePair()

inoremap (<CR> (<CR>)<ESC>O
inoremap {<CR> {<CR>}<ESC>O
inoremap [<CR> [<CR>]<ESC>O

g:NERDTreeShowHidden = 1
g:NERDTreeMinimalUI = 1
nnoremap <C-t> :NERDTreeToggle<cr>

g:gitgutter_preview_win_floating = 1

# fzf (binary and ripgrep from home.packages).
nnoremap <silent> <C-p> :Files<CR>
nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>/ :Rg<CR>

# LSP servers. Registration is lazy — a server only launches when a buffer
# of its filetype opens, so a long roster costs nothing at startup.
# Paths come from g:deps (nix store), never from PATH.
var lspServers = [
  # nil has no native formatter: it pipes buffers through nixfmt.
  {
    name: 'nil',
    filetype: 'nix',
    path: g:deps.nil,
    workspaceConfig: {nil: {formatting: {command: [g:deps.nixfmt]}}},
  },
  # Vim detects *.tf as 'tf', not 'terraform' — register both.
  # Point it at tofu (terraform itself is unfree). Hover/definition on
  # variables and attributes still need provider schemas, i.e. a `tofu init`
  # in the workspace — without one only schema-free tokens resolve.
  {
    name: 'terraform',
    filetype: ['tf', 'terraform'],
    path: g:deps.terraform,
    args: ['serve'],
    initializationOptions: {terraform: {path: g:deps.tofu}},
  },
  # TypeScript is split by project: vtsls (VS Code's own TypeScript service)
  # wherever a package.json is found above the file, deno everywhere else.
  # runIfSearch and runUnlessSearch take the same marker, so exactly one of
  # the two ever attaches to a buffer.
  {
    name: 'vtsls',
    filetype: ['typescript', 'typescriptreact', 'javascript', 'javascriptreact'],
    path: g:deps.vtsls,
    args: ['--stdio'],
    runIfSearch: ['package.json'],
    rootSearch: ['tsconfig.json', 'package.json', '.git/'],
    # Use the TypeScript pinned in the repo's node_modules rather than the
    # one vtsls bundles, so diagnostics match what the repo's own tsc reports.
    initializationOptions: {vtsls: {autoUseWorkspaceTsdk: true}},
    workspaceConfig: {vtsls: {autoUseWorkspaceTsdk: true}},
  },
  # deno lsp stays silent unless initializationOptions enables it. Brings
  # its own TypeScript, plus deno fmt/lint — no node anywhere.
  {
    name: 'deno',
    filetype: ['typescript', 'typescriptreact', 'javascript', 'javascriptreact'],
    path: g:deps.deno,
    args: ['lsp'],
    runUnlessSearch: ['package.json'],
    # Both are needed: the plugin answers deno's workspace/configuration
    # request from workspaceConfig, and an absent one reads as disabled —
    # the server then advertises hover/definition but replies null to both
    # (formatting still works, which makes it look half-broken).
    initializationOptions: {enable: true, lint: true},
    workspaceConfig: {deno: {enable: true, lint: true}},
  },
  # Charts are ft=helm (vim-helm), so they never reach this one.
  {
    name: 'yaml',
    filetype: 'yaml',
    path: g:deps.yaml,
    args: ['--stdio'],
    workspaceConfig: {yaml: {validate: true, format: {enable: true}}},
  },
  # helm-ls drives yaml-language-server itself for the non-template parts.
  {
    name: 'helm',
    filetype: 'helm',
    path: g:deps.helm,
    args: ['serve'],
    workspaceConfig: {'helm-ls': {yamlls: {enabled: true, path: g:deps.yaml}}},
  },
  # shellcheck rides along in the server's wrapper; shfmt is ours to point at.
  {
    name: 'bash',
    filetype: ['sh', 'bash'],
    path: g:deps.bash,
    args: ['start'],
    workspaceConfig: {bashIde: {shfmt: {path: g:deps.shfmt}}},
  },
  {
    name: 'toml',
    filetype: 'toml',
    path: g:deps.toml,
    args: ['lsp', 'stdio'],
  },
  # The vscode-* trio needs provideFormatter to offer :LspFormat.
  {
    name: 'json',
    filetype: ['json', 'jsonc'],
    path: g:deps.json,
    args: ['--stdio'],
    initializationOptions: {provideFormatter: true},
  },
  {
    name: 'css',
    filetype: ['css', 'scss', 'less'],
    path: g:deps.css,
    args: ['--stdio'],
    initializationOptions: {provideFormatter: true},
  },
  {
    name: 'html',
    filetype: 'html',
    path: g:deps.html,
    args: ['--stdio'],
    initializationOptions: {provideFormatter: true},
  },
  {
    name: 'docker',
    filetype: 'dockerfile',
    path: g:deps.docker,
    args: ['--stdio'],
  },
  # Obsidian-shaped markdown: wikilinks, backlink code lens, daily notes
  # from natural-language dates, code action to create a missing note.
  # Roots on an Obsidian vault or a repo. Formats nothing — ,f uses
  # formatprg below.
  {
    name: 'markdown',
    filetype: 'markdown',
    path: g:deps.markdown,
    rootSearch: ['.obsidian/', '.moxide.toml', '.git/'],
  },
  # Grammar/style, local and offline. Defaults to TCP, hence --stdio.
]
# autoComplete (on by default) pops the menu up as you type; omniComplete
# adds <C-x><C-o> as the manual trigger, which autoComplete otherwise
# disables. Accept/cancel/navigate stay vim's own <C-y>/<C-e>/<C-n>/<C-p>.
var lspOpts = {
  autoHighlightDiags: true,
  autoComplete: true,
  omniComplete: true,
}
autocmd User LspSetup call LspOptionsSet(lspOpts)
autocmd User LspSetup call LspAddServer(lspServers)

# harper-ls is registered on demand rather than at startup: its prose lints
# are noisy enough in markdown to want silence by default. LspAddServer sends
# buffers that are already open to the new server, so enabling is immediate.
# The plugin has no per-server stop, so this only turns harper on — the
# off state is a vim that has not been asked for it.
var harperServer = {
  name: 'harper',
  filetype: ['markdown', 'text', 'gitcommit'],
  path: g:deps.harper,
  args: ['--stdio'],
}
var harperOn = false
def g:HarperEnable()
  if harperOn
    echo 'harper: already on'
    return
  endif
  g:LspAddServer([harperServer])
  harperOn = true
  echo 'harper: on'
enddef
command! Harper call g:HarperEnable()

# No SQL language server until the postgres slice; until then gq pipes
# through sqlfluff (dialect is a guess — revisit with postgres).
# TS/JS in a node project formats through the repo's own prettier: the version
# it pins, its .prettierrc, and safe on .prettierignore'd paths (prettier
# echoes stdin back unchanged there). With no prettier installed, formatprg
# stays empty and FormatBuffer falls through to the language server — for
# stray TS that is deno fmt, a reflowing printer in its own right.
autocmd FileType typescript,typescriptreact,javascript,javascriptreact {
  var prettier = findfile('node_modules/.bin/prettier', expand('%:p:h') .. ';')
  if prettier != ''
    var arg = ' --stdin-filepath ' .. shellescape(expand('%:p'))
    &l:formatprg = fnamemodify(prettier, ':p') .. arg
  endif
}
autocmd FileType sql &l:formatprg = g:deps.sqlfluff .. ' format --dialect postgres -'

# Markdown: no LSP formatter anywhere, so gq pipes through deno fmt (already
# here for TS; it handles md, json and jsonc too).
autocmd FileType markdown &l:formatprg = g:deps.deno .. ' fmt --ext md -'

# Same map surface the CoC config used.
nnoremap <silent> gd :LspGotoDefinition<CR>
nnoremap <silent> gy :LspGotoTypeDef<CR>
nnoremap <silent> gi :LspGotoImpl<CR>
nnoremap <silent> gr :LspShowReferences<CR>
nnoremap <silent> K :LspHover<CR>
nmap <leader>rn :LspRename<CR>
nmap <silent> <leader>n :LspDiag next<CR>
nmap <silent> <leader>p :LspDiag prev<CR>
nnoremap <silent> <leader>ld :LspDiag show<CR>
# Code actions and friends, on the keys the CoC config used.
nnoremap <silent> <leader>a :LspCodeAction<CR>
xnoremap <silent> <leader>a :LspCodeAction<CR>
nnoremap <silent> <leader>qf :LspAutoFix<CR>
nnoremap <silent> <leader>i :LspOrganizeImports<CR>
nnoremap <silent> <leader>cl :LspCodeLens<CR>
nnoremap <silent> <leader>lo :LspDocumentSymbol<CR>
nnoremap <silent> <leader>ls :LspSymbolSearch<CR>
# ,f means the same everywhere: the language server where it formats,
# formatprg (markdown, sql) where none does.
# Runs formatprg in-process rather than through gq. gq filters by appending
# the program's output below the original lines and deleting them afterwards,
# and vim serves its event loop while the program runs — so the language
# server can receive a didChange for the doubled buffer and keep it, which
# tsserver reports as duplicate identifiers on every symbol. Replacing the
# lines here mutates the buffer with no yield in between. It also means a
# failing formatprg (prettier on any mid-edit syntax error) leaves the buffer
# untouched, and an already-formatted buffer is not marked modified.
def FormatBuffer()
  if empty(&l:formatprg)
    execute 'LspFormat'
    return
  endif
  var pos = getcurpos()
  var src = getline(1, '$')
  var out = systemlist(&l:formatprg, src)
  if v:shell_error != 0
    echohl ErrorMsg
    echomsg 'formatprg: ' .. get(out, 0, 'failed')
    echohl None
    return
  endif
  if out == src
    return
  endif
  setline(1, out)
  if len(src) > len(out)
    deletebufline('%', len(out) + 1, len(src))
  endif
  # Deliver the change now: the plugin pushes didChange and queues its
  # diagnostics pull from a change listener, and without a flush the pull can
  # race the replacement and leave diagnostics describing a half-updated file.
  listener_flush()
  cursor(min([pos[1], line('$')]), pos[2])
enddef
nnoremap <silent> <leader>f <ScriptCmd>FormatBuffer()<CR>
xnoremap <silent> <leader>f :LspFormat<CR>
autocmd FileType markdown,sql xnoremap <buffer> <leader>f gq

# LspAutoFix only applies a fix when the diagnostic has exactly one candidate
# (or one marked preferred); harper offers a list of spellings, so it declines
# silently. In prose ,qf offers that list instead, filtered to quickfix
# actions so the menu holds candidate spellings and not markdown-oxide's
# source actions.
autocmd FileType markdown,text,gitcommit
      \ nnoremap <buffer> <leader>qf <Cmd>LspCodeAction only:quickfix<CR>

# Dracula, the same theme glow renders with (modules/home/glow.nix).
# colorterm=0 leaves Normal's background unset instead of painting
# dracula's grey, so alacritty's near-black shows through.
g:dracula_colorterm = 0

# Pack plugins normally load after the vimrc; load them now so
# :colorscheme can see pack-managed schemes.
packloadall
colorscheme dracula
