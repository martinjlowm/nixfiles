# Tmux terminal multiplexer configuration
{pkgs, ...}: {
  programs.tmux = {
    enable = true;
    keyMode = "emacs";
    mouse = true;
    newSession = true;
    extraConfig = ''
      set-option -g default-shell /bin/zsh
      bind -n -T copy-mode M-w send-keys -X copy-pipe-and-cancel "pbcopy"
      bind -n M-v copy-mode -u
      bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "~/.tmux.conf reloaded"
    '';
    shortcut = "z";
    plugins = [
      {
        plugin = pkgs.tmuxPlugins.onedark-theme;
        extraConfig = "set -g @plugin 'odedlaz/tmux-onedark-theme'";
      }
      {
        plugin = pkgs.tmuxPlugins.yank;
        extraConfig = "set -g @plugin 'tmux-plugins/tmux-yank'";
      }
    ];
  };
}
