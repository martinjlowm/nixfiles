# WezTerm terminal configuration (migrated from tmux)
{pkgs, ...}: {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      local wezterm = require 'wezterm'
      local act = wezterm.action
      local config = wezterm.config_builder()

      -- Theme (OneDark like tmux)
      config.color_scheme = 'OneDark (base16)'

      -- Font (from kitty config)
      config.font = wezterm.font 'Hack Nerd Font Mono'
      config.font_size = 14.0

      -- Cursor
      config.default_cursor_style = 'SteadyBlock'

      -- Shell
      config.default_prog = { '/bin/zsh' }

      -- Tab bar (PowerLine style)
      config.use_fancy_tab_bar = false
      config.tab_bar_at_bottom = true
      config.tab_max_width = 32
      config.show_new_tab_button_in_tab_bar = false

      -- Scrollable tab bar styling
      config.tab_bar_style = {
        new_tab = wezterm.format {
          { Text = '''' },
        },
        new_tab_hover = wezterm.format {
          { Text = '''' },
        },
      }

      -- OneDark colors
      local onedark = {
        bg = '#282c34',
        bg_dark = '#21252b',
        bg_highlight = '#2c313a',
        fg = '#abb2bf',
        red = '#e06c75',
        green = '#98c379',
        yellow = '#e5c07b',
        blue = '#61afef',
        magenta = '#c678dd',
        cyan = '#56b6c2',
        gutter_grey = '#4b5263',
        comment_grey = '#5c6370',
      }

      config.colors = {
        tab_bar = {
          background = onedark.bg_dark,
          active_tab = {
            bg_color = onedark.green,
            fg_color = onedark.bg,
            intensity = 'Bold',
          },
          inactive_tab = {
            bg_color = onedark.bg_highlight,
            fg_color = onedark.fg,
          },
          inactive_tab_hover = {
            bg_color = onedark.gutter_grey,
            fg_color = onedark.fg,
          },
          new_tab = {
            bg_color = onedark.bg_dark,
            fg_color = onedark.fg,
          },
          new_tab_hover = {
            bg_color = onedark.gutter_grey,
            fg_color = onedark.fg,
          },
        },
      }

      local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider
      local SOLID_LEFT_INVERSE_ARROW = wezterm.nerdfonts.ple_right_hard_divider_inverse
      local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider
      local SOLID_RIGHT_INVERSE_ARROW = wezterm.nerdfonts.ple_left_hard_divider_inverse

      -- Right status: hostname, date, time
      wezterm.on('update-status', function(window, pane)
        local hostname = wezterm.hostname()
        local date = wezterm.strftime '%Y-%m-%d'
        local time = wezterm.strftime '%H:%M'

        window:set_right_status(wezterm.format {
          { Background = { Color = onedark.bg_dark } },
          { Foreground = { Color = onedark.blue } },
          { Text = SOLID_LEFT_ARROW },
          { Background = { Color = onedark.blue } },
          { Foreground = { Color = onedark.bg } },
          { Text = ' ' .. time .. ' ' },
          { Background = { Color = onedark.blue } },
          { Foreground = { Color = onedark.yellow } },
          { Text = SOLID_LEFT_ARROW },
          { Background = { Color = onedark.yellow } },
          { Foreground = { Color = onedark.bg } },
          { Text = ' ' .. date .. ' ' },
          { Background = { Color = onedark.yellow } },
          { Foreground = { Color = onedark.green } },
          { Text = SOLID_LEFT_ARROW },
          { Background = { Color = onedark.green } },
          { Foreground = { Color = onedark.bg } },
          { Attribute = { Intensity = 'Bold' } },
          { Text = ' ' .. hostname .. ' ' },
        })
      end)

      wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
        local background = onedark.bg
        local foreground = onedark.fg


        if tab.is_active then
          background = onedark.green
          foreground = onedark.bg
        elseif hover then
          background = onedark.gutter_grey
          foreground = onedark.fg
        end

        -- Use custom title if set, otherwise use pane title
        local title = tab.tab_title
        if not title or #title == 0 then
          title = tab.active_pane.title
        end
        if #title > max_width - 4 then
          title = wezterm.truncate_right(title, max_width - 4)
        end

        return {
          { Background = { Color = background } },
          { Foreground = { Color = tab.tab_index > 0 and #tabs > 1 and onedark.bg or background } },
          { Text = SOLID_RIGHT_ARROW },
          { Background = { Color = background } },
          { Foreground = { Color = foreground } },
          { Text = ' ' .. tab.tab_index .. ' ' .. title .. ' ' },
          { Background = { Color = tab.tab_index == #tabs - 1 and onedark.bg_dark or onedark.bg } },
          { Foreground = { Color = background } },
          { Text = SOLID_RIGHT_ARROW },
        }
      end)

      -- Mouse support (like tmux mouse = true)
      config.mouse_bindings = {
        {
          event = { Up = { streak = 1, button = 'Left' } },
          mods = 'NONE',
          action = act.CompleteSelection 'ClipboardAndPrimarySelection',
        },
      }

      -- macOS option as alt (from kitty)
      config.send_composed_key_when_left_alt_is_pressed = false
      config.send_composed_key_when_right_alt_is_pressed = false

      -- Leader key: C-z (like tmux shortcut = "z")
      config.leader = { key = 'z', mods = 'CTRL', timeout_milliseconds = 1000 }

      config.keys = {
        -- Copy mode: M-v or Leader+[ (like tmux)
        {
          key = 'v',
          mods = 'ALT',
          action = act.ActivateCopyMode,
        },
        {
          key = '[',
          mods = 'LEADER',
          action = act.ActivateCopyMode,
        },

        -- Pane splitting (like tmux defaults with leader)
        {
          key = '%',
          mods = 'LEADER|SHIFT',
          action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
        },
        {
          key = '"',
          mods = 'LEADER|SHIFT',
          action = act.SplitVertical { domain = 'CurrentPaneDomain' },
        },

        -- Pane navigation (arrow keys)
        {
          key = 'LeftArrow',
          mods = 'LEADER',
          action = act.ActivatePaneDirection 'Left',
        },
        {
          key = 'DownArrow',
          mods = 'LEADER',
          action = act.ActivatePaneDirection 'Down',
        },
        {
          key = 'UpArrow',
          mods = 'LEADER',
          action = act.ActivatePaneDirection 'Up',
        },
        {
          key = 'RightArrow',
          mods = 'LEADER',
          action = act.ActivatePaneDirection 'Right',
        },

        -- Cycle to next pane (like tmux 'o')
        {
          key = 'o',
          mods = 'LEADER',
          action = act.ActivatePaneDirection 'Next',
        },

        -- New tab (like tmux new-window)
        {
          key = 'c',
          mods = 'LEADER',
          action = act.SpawnTab 'CurrentPaneDomain',
        },

        -- Tab navigation
        {
          key = 'n',
          mods = 'LEADER',
          action = act.ActivateTabRelative(1),
        },
        {
          key = 'p',
          mods = 'LEADER',
          action = act.ActivateTabRelative(-1),
        },

        -- Jump to tab by number (Leader+0-9)
        { key = '0', mods = 'LEADER', action = act.ActivateTab(0) },
        { key = '1', mods = 'LEADER', action = act.ActivateTab(1) },
        { key = '2', mods = 'LEADER', action = act.ActivateTab(2) },
        { key = '3', mods = 'LEADER', action = act.ActivateTab(3) },
        { key = '4', mods = 'LEADER', action = act.ActivateTab(4) },
        { key = '5', mods = 'LEADER', action = act.ActivateTab(5) },
        { key = '6', mods = 'LEADER', action = act.ActivateTab(6) },
        { key = '7', mods = 'LEADER', action = act.ActivateTab(7) },
        { key = '8', mods = 'LEADER', action = act.ActivateTab(8) },
        { key = '9', mods = 'LEADER', action = act.ActivateTab(9) },

        -- Close pane
        {
          key = 'x',
          mods = 'LEADER',
          action = act.CloseCurrentPane { confirm = true },
        },

        -- Reload config (like tmux bind-key r source-file)
        {
          key = 'r',
          mods = 'LEADER',
          action = act.ReloadConfiguration,
        },

        -- Search/switch tabs
        {
          key = 'w',
          mods = 'LEADER',
          action = act.ShowTabNavigator,
        },

        -- Rename tab
        {
          key = ',',
          mods = 'LEADER',
          action = act.PromptInputLine {
            description = wezterm.format {
              { Text = 'Enter new tab name: ' },
            },
            action = wezterm.action_callback(function(window, pane, line)
              if line then
                window:active_tab():set_title(line)
              end
            end),
          },
        },

        -- Send C-z to application (since it's our leader)
        {
          key = 'z',
          mods = 'LEADER|CTRL',
          action = act.SendKey { key = 'z', mods = 'CTRL' },
        },
      }

      -- Copy mode key bindings (emacs-style like tmux keyMode = "emacs")
      config.key_tables = {
        copy_mode = {
          -- Exit copy mode
          { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
          { key = 'q', mods = 'NONE', action = act.CopyMode 'Close' },

          -- Copy: M-w (like tmux bind -n -T copy-mode M-w send-keys -X copy-pipe-and-cancel "pbcopy")
          {
            key = 'w',
            mods = 'ALT',
            action = act.Multiple {
              { CopyTo = 'ClipboardAndPrimarySelection' },
              { CopyMode = 'Close' },
            },
          },

          -- Emacs-style navigation
          { key = 'f', mods = 'CTRL', action = act.CopyMode 'MoveRight' },
          { key = 'b', mods = 'CTRL', action = act.CopyMode 'MoveLeft' },
          { key = 'n', mods = 'CTRL', action = act.CopyMode 'MoveDown' },
          { key = 'p', mods = 'CTRL', action = act.CopyMode 'MoveUp' },
          { key = 'a', mods = 'CTRL', action = act.CopyMode 'MoveToStartOfLineContent' },
          { key = 'e', mods = 'CTRL', action = act.CopyMode 'MoveToEndOfLineContent' },
          { key = 'f', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
          { key = 'b', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
          { key = 'v', mods = 'CTRL', action = act.CopyMode 'PageDown' },
          { key = 'v', mods = 'ALT', action = act.CopyMode 'PageUp' },

          -- Selection
          { key = 'Space', mods = 'CTRL', action = act.CopyMode { SetSelectionMode = 'Cell' } },

          -- Arrow keys
          { key = 'LeftArrow', mods = 'NONE', action = act.CopyMode 'MoveLeft' },
          { key = 'RightArrow', mods = 'NONE', action = act.CopyMode 'MoveRight' },
          { key = 'UpArrow', mods = 'NONE', action = act.CopyMode 'MoveUp' },
          { key = 'DownArrow', mods = 'NONE', action = act.CopyMode 'MoveDown' },
        },
      }

      return config
    '';
  };
}
