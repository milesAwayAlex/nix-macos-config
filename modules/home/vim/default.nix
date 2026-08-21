# LSP is yegappan/lsp, deliberately out-of-nixpkgs, consumed as the vim9-lsp
# flake input. The consuming flake passes that input's source as the vim9-lsp
# module arg via home-manager's extraSpecialArgs (D11).
#
# home-manager wraps vim with `-u <store vimrc>`, so ~/.vimrc is never read,
# and config.vim drops ~/.vim from plugin discovery. Nothing manually
# dropped into ~/.vim can leak into the declarative vim.
{
  config,
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
  # $EDITOR by store path, not by name: a bare `vim` takes whatever PATH
  # offers, which need not be the vim configured here. Declared from this
  # module so a consumer of homeModules.bash alone does not pull vim into
  # their closure, and in initExtra because home-manager sources
  # hm-session-vars.sh only from .profile — non-login shells never see it.
  programs.bash.initExtra = "export EDITOR=${config.programs.vim.package}/bin/vim";

  programs.vim = {
    enable = true;

    # nixpkgs builds vim with --disable-darwin by default, which leaves
    # +clipboard meaning *X11* — useless on macOS, so "*y and "+y silently
    # did nothing. --enable-darwin wires the real pasteboard. Costs a local
    # source build (no cache hit for a non-default override).
    packageConfigurable = pkgs.vim-full.override {
      darwinSupport = true;
      guiSupport = false; # terminal only; the default would pull GTK
    };

    # home-manager force-merges vim-sensible into this list; it covers
    # backspace, incsearch, wildmenu, autoread, ruler, laststatus=2, and
    # filetype/syntax on, so those are not repeated in config.vim.
    plugins = with pkgs.vimPlugins; [
      fzf-vim
      lsp
      vim-helm # ft=helm detection for charts; helm-ls needs it
      nerdtree
      dracula-vim
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
            \   terraform: '${pkgs.terraform-ls}/bin/terraform-ls',
            \   deno: '${pkgs.deno}/bin/deno',
            \   vtsls: '${pkgs.vtsls}/bin/vtsls',
            \   yaml: '${pkgs.yaml-language-server}/bin/yaml-language-server',
            \   helm: '${pkgs.helm-ls}/bin/helm_ls',
            \   bash: '${pkgs.bash-language-server}/bin/bash-language-server',
            \   shfmt: '${pkgs.shfmt}/bin/shfmt',
            \   toml: '${pkgs.taplo}/bin/taplo',
            \   json: '${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server',
            \   css: '${pkgs.vscode-langservers-extracted}/bin/vscode-css-language-server',
            \   html: '${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server',
            \   docker: '${pkgs.dockerfile-language-server}/bin/docker-langserver',
            \   sqlfluff: '${pkgs.sqlfluff}/bin/sqlfluff',
            \   markdown: '${pkgs.markdown-oxide}/bin/markdown-oxide',
            \   harper: '${pkgs.harper}/bin/harper-ls',
            \   tofu: '${pkgs.opentofu}/bin/tofu',
            \ }
      source ${./config.vim}
    '';
  };
}
