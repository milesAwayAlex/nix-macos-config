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

# vim-helm only claims a template when Chart.yaml sits exactly one level
# above templates/. Widen it: any yaml under a templates/ dir with a
# Chart.yaml anywhere above. (:set ft=helm still works for odd layouts.)
autocmd FileType yaml {
  if expand('%:p') =~ '/templates/'
        && findfile('Chart.yaml', expand('%:p:h') .. ';') != ''
    &l:filetype = 'helm'
  endif
}

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
nmap <leader>sp :setlocal spell!<cr>
nmap <leader>o :tabe<cr>

# Autoclose pairs.
noremap! "" ""<left>
noremap! '' ''<left>
noremap! `` ``<left>
noremap! (( ()<left>
noremap! [[ []<left>
noremap! {{ {}<left>
noremap! <> <><left>
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
  # deno lsp stays silent unless initializationOptions enables it. Brings
  # its own TypeScript, plus deno fmt/lint — no node anywhere.
  {
    name: 'deno',
    filetype: ['typescript', 'typescriptreact', 'javascript', 'javascriptreact'],
    path: g:deps.deno,
    args: ['lsp'],
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
  {
    name: 'harper',
    filetype: ['markdown', 'text', 'gitcommit'],
    path: g:deps.harper,
    args: ['--stdio'],
  },
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

# No SQL language server until the postgres slice; until then gq pipes
# through sqlfluff (dialect is a guess — revisit with postgres).
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
# ,f means the same everywhere: the language server where it formats,
# formatprg (markdown, sql) where none does.
def FormatBuffer()
  if empty(&l:formatprg)
    execute 'LspFormat'
  else
    var pos = getcurpos()
    silent keepjumps normal! gggqG
    setpos('.', pos)
  endif
enddef
nnoremap <silent> <leader>f <ScriptCmd>FormatBuffer()<CR>
xnoremap <silent> <leader>f :LspFormat<CR>
autocmd FileType markdown,sql xnoremap <buffer> <leader>f gq

g:onedark_color_overrides = {
  foreground: {gui: 'NONE', cterm: 'NONE', cterm16: 'NONE'},
  background: {gui: 'NONE', cterm: 'NONE', cterm16: 'NONE'},
}

# Pack plugins normally load after the vimrc; load them now so
# :colorscheme can see pack-managed schemes.
packloadall
colorscheme onedark
