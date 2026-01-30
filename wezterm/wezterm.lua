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
  -- debug_key_events = true,
  leader = { key = 'w', mods = 'ALT' },
  -- seems this setting effect only QuitApplication
  window_close_confirmation = 'NeverPrompt',
  send_composed_key_when_right_alt_is_pressed = false,
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
      mods = 'LEADER',
      action = act.QuitApplication,
    },
    {
      key = 'l',
      mods = 'LEADER',
      action = act.ShowLauncher,
    },
    {
      key = 'Backspace',
      mods = 'LEADER',
      action = act.ActivateCopyMode,
    },
    {
      key = 'f',
      mods = 'LEADER',
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
      mods = 'LEADER',
      action = act.SpawnCommandInNewTab,
    },
    {
      key = 'w',
      mods = 'LEADER',
      action = act.CloseCurrentPane({
        confirm = false,
      }),
    },
    {
      key = "'",
      mods = 'LEADER',
      action = act.SplitVertical({
        domain = 'CurrentPaneDomain',
      }),
    },
    {
      key = ';',
      mods = 'LEADER',
      action = act.SplitHorizontal({
        domain = 'CurrentPaneDomain',
      }),
    },
    {
      key = 'UpArrow',
      mods = 'LEADER',
      action = act.ActivatePaneDirection('Up'),
    },
    {
      key = 'DownArrow',
      mods = 'LEADER',
      action = act.ActivatePaneDirection('Down'),
    },
    {
      key = 'RightArrow',
      mods = 'LEADER',
      action = act.ActivatePaneDirection('Right'),
    },
    {
      key = 'LeftArrow',
      mods = 'LEADER',
      action = act.ActivatePaneDirection('Left'),
    },
    {
      key = 'Tab',
      mods = 'LEADER',
      action = act.ActivateTabRelative(1),
    },
    {
      key = 'Tab',
      mods = 'LEADER',
      action = act.ActivateTabRelative(-1),
    },
    {
      key = '1',
      mods = 'LEADER',
      action = act.ActivateTab(0),
    },
    {
      key = '2',
      mods = 'LEADER',
      action = act.ActivateTab(1),
    },
    {
      key = '3',
      mods = 'LEADER',
      action = act.ActivateTab(2),
    },
    {
      key = '4',
      mods = 'LEADER',
      action = act.ActivateTab(3),
    },
    {
      key = '5',
      mods = 'LEADER',
      action = act.ActivateTab(4),
    },
    {
      key = '6',
      mods = 'LEADER',
      action = act.ActivateTab(5),
    },
    {
      key = '7',
      mods = 'LEADER',
      action = act.ActivateTab(6),
    },
    {
      key = '8',
      mods = 'LEADER',
      action = act.ActivateTab(7),
    },
    {
      key = '9',
      mods = 'LEADER',
      action = act.ActivateTab(-1),
    },
    -- copy & paste
    {
      key = 'c',
      mods = 'LEADER',
      action = act.CopyTo('Clipboard'),
    },
    {
      key = 'v',
      mods = 'LEADER',
      action = act.PasteFrom('Clipboard'),
    },
    -- font size
    {
      key = '0',
      mods = 'LEADER',
      action = act.ResetFontSize,
    },
    {
      key = '-',
      mods = 'LEADER',
      action = act.DecreaseFontSize,
    },
    {
      key = '=',
      mods = 'LEADER',
      action = act.IncreaseFontSize,
    },
    {
      key = 's',
      mods = 'LEADER',
      action = act.PaneSelect,
    },
    {
      key = 'e',
      mods = 'LEADER',
      action = wezterm.action_callback(function(window, pane)
        local target_pane_id = tostring(pane:pane_id())

        -- Try to resume existing editor pane
        local success, _stdout, _stderr = wezterm.run_child_process({
          'bash',
          '-lc',
          string.format('npx editprompt --resume --mux wezterm --target-pane %s', target_pane_id),
        })

        -- If resume failed, create new editor pane
        if not success then
          window:perform_action(
            act.SplitPane({
              direction = 'Down',
              size = { Cells = 10 },
              command = {
                args = {
                  'bash',
                  '-lc',
                  string.format(
                    'npx editprompt --editor nvim --always-copy --mux wezterm --target-pane %s',
                    target_pane_id
                  ),
                },
              },
            }),
            pane
          )
        end
      end),
    },
  },
  -- mouse
  mouse_bindings = {
    {
      event = {
        Down = {
          streak = 1,
          button = 'Middle',
        },
      },
      mods = 'NONE',
      action = act.PasteFrom('Clipboard'),
    },
    {
      event = {
        Down = {
          streak = 1,
          button = 'Right',
        },
      },
      mods = 'NONE',
      action = act.CopyTo('Clipboard'),
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
  hide_tab_bar_if_only_one_tab = true,
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
    font_size = 18.0,

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

-- claude code notification
wezterm.on('bell', function(window, _pane)
  window:toast_notification('Claude Code', 'Task completed', nil, 4000)
end)

-- ssh domains
-- local ssh_config = {
--   ssh_domains = {
--     {
--       name = 'stafes',
--       remote_address = '192.168.10.110',
--       username = 'shishi',
--       -- connect_automatically = true,
--       ssh_option = {
--         identityfile = '~/.ssh/id_rsa',
--       },
--     },
--   },
-- }
-- append_table(config, ssh_config)

-- per os config
if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  local wsl_domains = wezterm.default_wsl_domains()

  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = '~'
  end

  local windows_config = {
    use_ime = true,
    ime_preedit_rendering = 'System',
    wsl_domains = wsl_domains,
    front_end = 'OpenGL',
    -- this setting make cmd and powershell can't start
    -- default_domain = 'WSL:Ubuntu',
    default_prog = { 'C:/Users/shishi/scoop/shims/nu.exe' },
    launch_menu = {

      {
        label = 'Command Prompt',
        args = { 'cmd.exe' },
      },
      {
        label = 'Powershell',
        args = { 'C:/Users/shishi/scoop/shims/pwsh.exe' },
      },
      {
        label = 'NuShell',
        args = { 'C:/Users/shishi/scoop/shims/nu.exe' },
      },
      {
        label = 'Ubuntu',
        args = { 'wsl.exe', '~', '-d', 'Ubuntu', '--user', 'shishi' },
      },
    },
  }

  append_table(config, windows_config)
elseif wezterm.target_triple == 'x86_64-unknown-linux-gnu' then
  local linux_config = {
    use_ime = true,
    front_end = 'OpenGL',
  }
  append_table(config, linux_config)
elseif wezterm.target_triple == 'aarch64-apple-darwin' then
  local macos_config = {
    use_ime = true,
    front_end = 'OpenGL',
    macos_forward_to_ime_modifier_mask = 'CTRL|SHIFT',
  }
  append_table(config, macos_config)
end

return config
