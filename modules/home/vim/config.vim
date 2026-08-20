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

# LSP servers — nil pilots; the full roster is a later slice.
# nil has no native formatter: it pipes buffers through nixfmt.
var lspServers = [{
  name: 'nil',
  filetype: 'nix',
  path: g:deps.nil,
  workspaceConfig: {
    nil: {
      formatting: {command: [g:deps.nixfmt]},
    },
  },
}]
autocmd User LspSetup call LspOptionsSet({autoHighlightDiags: true})
autocmd User LspSetup call LspAddServer(lspServers)

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
nmap <leader>f :LspFormat<CR>
xnoremap <leader>f :LspFormat<CR>

g:onedark_color_overrides = {
  foreground: {gui: 'NONE', cterm: 'NONE', cterm16: 'NONE'},
  background: {gui: 'NONE', cterm: 'NONE', cterm16: 'NONE'},
}

# Pack plugins normally load after the vimrc; load them now so
# :colorscheme can see pack-managed schemes.
packloadall
colorscheme onedark
