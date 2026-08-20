# LSP is yegappan/lsp, deliberately out-of-nixpkgs, consumed as the vim9-lsp
# flake input. The consuming flake passes that input's source as the vim9-lsp
# module arg via home-manager's extraSpecialArgs (D11).
#
# home-manager wraps vim with `-u <store vimrc>`, so ~/.vimrc is never read,
# and config.vim drops ~/.vim from plugin discovery. Nothing manually
# dropped into ~/.vim can leak into the declarative vim.
{
  pkgs,
  vim9-lsp,
  ...
}:
let
  lsp = pkgs.vimUtils.buildVimPlugin {
    pname = "vim9-lsp";
    version = vim9-lsp.shortRev or "pinned";
    src = vim9-lsp;
  };
in
{
  programs.vim = {
    enable = true;

    # home-manager force-merges vim-sensible into this list; it covers
    # backspace, incsearch, wildmenu, autoread, ruler, laststatus=2, and
    # filetype/syntax on, so those are not repeated in config.vim.
    plugins = with pkgs.vimPlugins; [
      fzf-vim
      lsp
      nerdtree
      onedark-vim
      vim-fugitive
      vim-gitgutter
      vim-surround
    ];

    settings = {
      background = "dark";
      expandtab = true;
      hidden = true;
      ignorecase = true;
      smartcase = true;
      number = true;
      shiftwidth = 2;
      tabstop = 2;
    };

    # The config proper is config.vim (vim9script — real file, real
    # filetype treatment in the editor). The store paths it needs arrive
    # through g:deps, keeping the external deps gathered here.
    extraConfig = ''
      let g:deps = #{
            \   nil: '${pkgs.nil}/bin/nil',
            \   nixfmt: '${pkgs.nixfmt}/bin/nixfmt',
            \ }
      source ${./config.vim}
    '';
  };
}
