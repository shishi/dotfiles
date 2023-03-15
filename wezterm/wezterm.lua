local wezterm = require('wezterm')
local act = wezterm.action

local function append_table(table, other)
  for k, v in pairs(other) do
    table[k] = v
  end
end

wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  window:gui_window():set_position(850, 150)
end)

-- common config
local config = {
  -- seems this setting effect only QuitApplication
  window_close_confirmation = 'NeverPrompt',
  skip_close_confirmation_for_processes_named = {
    'bash',
    'sh',
    'zsh',
    'fish',
    'tmux',
    'nu',
    'cmd.exe',
    'pwsh.exe',
    'powershell.exe',
    'wsl.exe',
    'wslhost.exe',
    'conhost.exe',
  },
  -- key
  disable_default_key_bindings = true,
  keys = {
    -- applicaton
    {
      key = 'q',
      mods = 'CTRL|SHIFT|ALT',
      action = act.QuitApplication,
    },
    {
      key = 'l',
      mods = 'CTRL|SHIFT|ALT',
      action = act.ShowLauncher,
    },
    {
      key = 'Backspace',
      mods = 'CTRL|SHIFT|ALT',
      action = act.ActivateCopyMode,
    },
    {
      key = 'f',
      mods = 'CTRL|SHIFT|ALT',
      action = act.Search({ CaseInSensitiveString = '' }),
    },
    {
      key = 'PageUp',
      mods = 'CTRL',
      action = act.ScrollByPage(-1),
    },
    {
      key = 'PageDown',
      mods = 'CTRL',
      action = act.ScrollByPage(1),
    },
    -- tab & pane
    {
      key = 't',
      mods = 'CTRL|SHIFT|ALT',
      action = act.SpawnCommandInNewTab,
    },
    {
      key = 'w',
      mods = 'CTRL|SHIFT|ALT',
      action = act.CloseCurrentPane({
        confirm = false,
      }),
    },
    {
      key = "'",
      mods = 'CTRL|SHIFT|ALT',
      action = wezterm.action.SplitVertical({
        domain = 'CurrentPaneDomain',
      }),
    },
    {
      key = ';',
      mods = 'CTRL|SHIFT|ALT',
      action = wezterm.action.SplitHorizontal({
        domain = 'CurrentPaneDomain',
      }),
    },
    {
      key = 'UpArrow',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivatePaneDirection('Up'),
    },
    {
      key = 'DownArrow',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivatePaneDirection('Down'),
    },
    {
      key = 'RightArrow',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivatePaneDirection('Right'),
    },
    {
      key = 'LeftArrow',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivatePaneDirection('Left'),
    },
    {
      key = 'Tab',
      mods = 'CTRL|ALT',
      action = act.ActivateTabRelative(1),
    },
    {
      key = 'Tab',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTabRelative(-1),
    },
    {
      key = '1',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(0),
    },
    {
      key = '2',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(1),
    },
    {
      key = '3',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(2),
    },
    {
      key = '4',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(3),
    },
    {
      key = '5',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(4),
    },
    {
      key = '6',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(5),
    },
    {
      key = '7',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(6),
    },
    {
      key = '8',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(7),
    },
    {
      key = '9',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ActivateTab(-1),
    },
    -- copy & paste
    {
      key = 'c',
      mods = 'SHIFT|CTRL|ALT',
      action = act.CopyTo('Clipboard'),
    },
    {
      key = 'v',
      mods = 'SHIFT|CTRL|ALT',
      action = act.PasteFrom('Clipboard'),
    },
    -- font size
    {
      key = '0',
      mods = 'SHIFT|CTRL|ALT',
      action = act.ResetFontSize,
    },
    {
      key = '-',
      mods = 'SHIFT|CTRL|ALT',
      action = act.DecreaseFontSize,
    },
    {
      key = '=',
      mods = 'SHIFT|CTRL|ALT',
      action = act.IncreaseFontSize,
    },
  },
  -- mouse
  mouse_bindings = {
    {
      event = {
        Up = {
          streak = 1,
          button = 'Middle',
        },
      },
      mods = 'NONE',
      action = act.Paste,
    },
    {
      event = {
        Up = {
          streak = 1,
          button = 'Right',
        },
      },
      mods = 'NONE',
      action = act.Copy,
    },
  },
  -- GUI
  font = wezterm.font_with_fallback({
    {
      family = 'UDEV Gothic NF',
    },
    {
      family = 'Noto Color Emoji',
    },
  }),
  font_size = 20,
  adjust_window_size_when_changing_font_size = false,
  -- color_scheme = "Gruvbox dark, hard (base16)",
  color_scheme = 'Afterglow',
  window_background_opacity = 0.9,
  initial_cols = 160,
  initial_rows = 42,
  window_padding = {
    left = 0,
    right = 0,
    bottom = 0,
    top = 0,
  },
  -- tab
  hide_tab_bar_if_only_one_tab = false,
  window_frame = {
    -- The font used in the tab bar.
    -- Roboto Bold is the default; this font is bundled
    -- with wezterm.
    -- Whatever font is selected here, it will have the
    -- main font setting appended to it to pick up any
    -- fallback fonts you may have used there.
    font = wezterm.font({
      family = 'Roboto',
      weight = 'Bold',
    }),

    -- The size of the font in the tab bar.
    -- Default to 10. on Windows but 12.0 on other systems
    font_size = 16.0,

    -- The overall background color of the tab bar when
    -- the window is focused
    active_titlebar_bg = '#333333',

    -- The overall background color of the tab bar when
    -- the window is not focused
    inactive_titlebar_bg = '#333333',
  },
  colors = {
    tab_bar = {
      -- The color of the inactive tab bar edge/divider
      inactive_tab_edge = '#575757',
    },
  },
}

-- ssh domains
local ssh_config = {
  ssh_domains = {
    {
      name = 'stafes',
      remote_address = '192.168.10.110',
      username = 'shishi',
      -- connect_automatically = true,
      ssh_option = {
        identityfile = '~/.ssh/id_rsa',
      },
    },
  },
}
append_table(config, ssh_config)

-- per os config
if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  local wsl_domains = wezterm.default_wsl_domains()

  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end

  local windows_config = {
    wsl_domains = wsl_domains,
    front_end = 'WebGpu',
    -- this setting make cmd and powershell can't start
    -- default_domain = 'WSL:Ubuntu',
    default_prog = { 'wsl.exe', '~', '-d', 'Ubuntu', '--user', 'shishi' },
    launch_menu = {
      {
        label = 'Command Prompt',
        args = { 'cmd.exe' },
      },
      {
        label = 'Powershell',
        args = { 'C:/Program Files/PowerShell/7/pwsh.exe' },
      },
    },
  }
  append_table(config, windows_config)
elseif wezterm.target_triple == 'x86_64-unknown-linux-gnu' then
  local linux_config = {
    front_end = 'OpenGL',
  }
  append_table(config, linux_config)
end

return config
