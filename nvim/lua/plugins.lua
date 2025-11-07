-- Clone 'mini.nvim' manually in a way that it gets managed by 'mini.deps'
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/start/mini.nvim'
if not vim.uv.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  local clone_cmd = {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/nvim-mini/mini.nvim',
    mini_path,
  }
  vim.fn.system(clone_cmd)
  vim.cmd('packadd mini.nvim | helptags ALL')
  vim.cmd('echo "Installed `mini.nvim`" | redraw')
end

-- Set up .deps' (customize to your liking)
require('mini.deps').setup({ path = { package = path_package } })

-- local not_in_vscode = vim.g.vscode == nil

local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

-- install and configure plugins
-- now ----------------------------------------------------------------
now(function()
  require('mini.misc').setup()

  MiniMisc.setup_restore_cursor()
  MiniMisc.setup_auto_root()
end)

now(function()
  require('mini.icons').setup()
  -- require('mini.files').setup({
  --   windows = {
  --     -- Whether to show preview of file/directory under cursor
  --     preview = true,
  --   },
  -- })

  -- vim.api.nvim_create_user_command('Files', function()
  --   MiniFiles.open()
  -- end, { desc = 'Open MiniFiles' })
  --
  -- vim.keymap.set('n', '<Leader>e', function()
  --   MiniFiles.open()
  -- end, { desc = 'Open MiniFiles' })
end)

now(function()
  add({
    source = 'stevearc/oil.nvim',
  })
  require('oil').setup({
    view_options = {
      show_hidden = true,
    },
    keymaps = {
      ['yp'] = {
        desc = 'Copy filepath to system clipboard',
        callback = function()
          require('oil.actions').copy_entry_path.callback()
          vim.fn.setreg('+', vim.fn.getreg(vim.v.register))
        end,
      },
      ['yP'] = {
        desc = 'Copy relative filepath to system clipboard',
        callback = function()
          local entry = require('oil').get_cursor_entry()
          local dir = require('oil').get_current_dir()

          if not entry or not dir then
            return
          end

          local relpath = vim.fn.fnamemodify(dir, ':.')

          vim.fn.setreg('+', relpath .. entry.name)
        end,
      },
    },
  })

  vim.api.nvim_create_user_command('OilFloat', function()
    vim.api.nvim_cmd({
      cmd = 'Oil',
      args = { '--float', vim.fn.expand('%:p:h') },
    }, {})
  end, { desc = 'Open Oil Float' })

  vim.keymap.set('n', '<Leader>e', function()
    vim.cmd('OilFloat')
  end, { desc = 'Open OilFloat' })
end)

-- now(function()
--   add({
--     source = 'rcarriga/nvim-notify',
--   })
--   vim.notify = require('notify')
--
--   vim.api.nvim_create_user_command('NotifyHistory', function()
--     vim.cmd('Telescope notify')
--   end, { desc = 'Show notify history' })
-- end)

now(function()
  require('mini.notify').setup()

  vim.notify = require('mini.notify').make_notify({
    ERROR = { duration = 10000 },
  })

  vim.api.nvim_create_user_command('NotifyHistory', function()
    MiniNotify.show_history()
  end, { desc = 'Show notify history' })
end)

now(function()
  require('mini.sessions').setup()

  local function is_blank(arg)
    return arg == nil or arg == ''
  end
  local function get_sessions(lead)
    -- ref: https://qiita.com/delphinus/items/2c993527df40c9ebaea7
    return vim
      .iter(vim.fs.dir(MiniSessions.config.directory))
      :map(function(v)
        local name = vim.fn.fnamemodify(v, ':t:r')
        return vim.startswith(name, lead) and name or nil
      end)
      :totable()
  end
  vim.api.nvim_create_user_command('SessionWrite', function(arg)
    local session_name = is_blank(arg.args) and vim.v.this_session or arg.args
    if is_blank(session_name) then
      vim.notify('No session name specified', vim.log.levels.WARN)
      return
    end
    vim.cmd('%argdelete')
    MiniSessions.write(session_name)
  end, { desc = 'Write session', nargs = '?', complete = get_sessions })

  vim.api.nvim_create_user_command('SessionDelete', function(arg)
    MiniSessions.select('delete', { force = arg.bang })
  end, { desc = 'Delete session', bang = true })

  vim.api.nvim_create_user_command('SessionLoad', function()
    MiniSessions.select('read', { verbose = true })
  end, { desc = 'Load session' })

  vim.api.nvim_create_user_command('SessionEscape', function()
    vim.v.this_session = ''
  end, { desc = 'Escape session' })

  vim.api.nvim_create_user_command('SessionReveal', function()
    if is_blank(vim.v.this_session) then
      vim.print('No session')
      return
    end
    vim.print(vim.fn.fnamemodify(vim.v.this_session, ':t:r'))
  end, { desc = 'Reveal session' })
end)

now(function()
  require('mini.starter').setup()
end)

-- later ----------------------------------------------------------------
later(function()
  add({
    source = 'vim-denops/denops.vim',
  })
end)

later(function()
  require('mini.pairs').setup({
    modes = { insert = true, command = true, terminal = true },
    -- vim.keymap.set('i', '<CR>', 'v:lua.cr_action()', { expr = true }),
  })
end)

later(function()
  require('mini.surround').setup({
    mappings = {
      add = '<Leader>sa', -- Add surrounding in Normal and Visual modes
      delete = '<Leader>sd', -- Delete surrounding
      find = '<Leader>sf', -- Find surrounding (to the right)
      find_left = '<Leader>sF', -- Find surrounding (to the left)
      highlight = '<Leader>sh', -- Highlight surrounding
      replace = '<Leader>sr', -- Replace surrounding
      update_n_lines = '<Leader>sn', -- Update `n_lines`
      suffix_last = 'l', -- Suffix to search with "prev" method
      suffix_next = 'n', -- Suffix to search with "next" method
    },
    n_lines = 100,
  })
end)

later(function()
  local gen_ai_spec = require('mini.extra').gen_ai_spec
  require('mini.ai').setup({
    custom_textobjects = {
      B = gen_ai_spec.buffer(),
      D = gen_ai_spec.diagnostic(),
      I = gen_ai_spec.indent(),
      L = gen_ai_spec.line(),
      N = gen_ai_spec.number(),
      J = { { '()%d%d%d%d%-%d%d%-%d%d()', '()%d%d%d%d%/%d%d%/%d%d()' } },
    },
  })
end)

-- later(function()
--   require('mini.jump').setup({
--     mappings = {
--       forward = 'f',
--       backward = 'F',
--       forward_till = 't',
--       backward_till = 'T',
--       repeat_jump = ':',
--     },
--   })
-- end)

-- later(function()
--   require('mini.jump2d').setup({
--     mappings = {
--       start_jumping = 's',
--     },
--   })
-- end)

-- later(function()
--   add({
--     source = 's-show/ft-mapper.nvim',
--   })
--
--   require('ft-mapper').setup({
--     mappings = {
--       -- This configuration is designed for Japanese editing
--       { ',', '、', '，' },
--       { '.', '。', '．' },
--       { ':', '：' },
--       { ';', '；' },
--       { '!', '！' },
--       { '?', '？' },
--       { '(', '（' },
--       { ')', '）' },
--       { '[', '「', '『', '【', '［' },
--       { ']', '」', '』', '】', '］' },
--       { "'", "'", "'" },
--       { '"', '"', '"', '゛' },
--       { '<', '＜', '«' },
--       { '>', '＞', '»' },
--       { '-', 'ー', '―', '—', '–' },
--       { ' ', '　' }, -- half-width and full-width spaces
--     },
--     -- Search within 10 lines above and below cursor line (optional)
--     line_limit = 30,
--     -- Don't assign to default key mappings (optional)
--     no_default_mappings = true,
--     -- Enable debug output (optional)
--     debug = false,
--   })
--
--   -- Assign extended functionality to <leader>f/t/F/T
--   vim.keymap.set({ 'n', 'v', 'o' }, 'f', '<Plug>(f_motion)')
--   vim.keymap.set({ 'n', 'v', 'o' }, 't', '<Plug>(t_motion)')
--   vim.keymap.set({ 'n', 'v', 'o' }, 'F', '<Plug>(F_motion)')
--   vim.keymap.set({ 'n', 'v', 'o' }, 'T', '<Plug>(T_motion)')
--   -- Assign forward repeat search (;) to ">"
--   vim.keymap.set({ 'n', 'v', 'o' }, '.', '<Plug>(forward_repeat)')
--   -- Assign backward repeat search (,) to "<"
--   vim.keymap.set({ 'n', 'v', 'o' }, ',', '<Plug>(backward_repeat)')
-- end)

later(function()
  add({
    source = 'folke/flash.nvim',
  })

  ---@diagnostic disable-next-line missing-fields
  require('flash').setup({
    -- modes = {
    --   char = {
    --     enabled = false,
    --   },
    -- },
  })

  vim.keymap.set({ 'n', 'x', 'o' }, 's', function()
    require('flash').jump()
  end, { desc = 'Flash Jump' })

  vim.keymap.set({ 'n', 'x', 'o' }, 'S', function()
    require('flash').treesitter()
  end, { desc = 'Flash Treesitter' })

  vim.keymap.set('o', 'r', function()
    require('flash').remote()
  end, { desc = 'Flash Remote' })

  vim.keymap.set({ 'o', 'x' }, 'R', function()
    require('flash').treesitter_search()
  end, { desc = 'Flash Treesitter Search' })

  vim.keymap.set({ 'c' }, '<c-s>', function()
    require('flash').toggle()
  end, { desc = 'Toggle Flash Search' })
end)

later(function()
  add({
    source = 'lambdalisue/kensaku.vim',
    depends = {
      'vim-denops/denops.vim',
    },
  })
end)

later(function()
  add({
    source = 'lambdalisue/vim-kensaku-search',
    depends = {
      'lambdalisue/kensaku.vim',
    },
  })

  vim.keymap.set('c', '<CR>', [[<Plug>(kensaku-search-replace)<CR>]])
end)

later(function()
  add({
    source = 'lambdalisue/vim-kensaku-command',
    depends = {
      'lambdalisue/kensaku.vim',
    },
    -- みげも
    -- 検索
  })

  vim.api.nvim_create_user_command('K', function(opts)
    vim.cmd('Kensaku ' .. opts.args)
  end, { nargs = '*' })
end)

later(function()
  require('mini.operators').setup({
    replace = {
      prefix = 'gR',
      reindent_linewise = true,
    },
    exchange = {
      prefix = 'g/',
      reindent_linewise = true,
    },
  })

  vim.keymap.set('n', 'RR', 'R', { desc = 'Replace mode' })
end)

later(function()
  require('mini.splitjoin').setup({
    mappings = {
      toggle = 'gS',
      split = '',
      join = '',
    },
  })
end)

later(function()
  require('mini.align').setup()
  -- start with ga, gA (interative)
end)

later(function()
  require('mini.trailspace').setup()

  vim.api.nvim_create_user_command('Trim', function()
    MiniTrailspace.trim()
    MiniTrailspace.trim_last_lines()
  end, { desc = 'Trim trailing space and last blank lines' })
end)

later(function()
  add({
    source = 'nvim-treesitter/nvim-treesitter',
    checkout = 'master',
    -- 時期がきたらmainにきりかえる
    -- checkout = 'main',
    monitor = 'main',
    hooks = {
      -- post_install = function()
      --   vim.cmd('TSInstall all')
      -- end,
      -- Perform action after every checkout
      post_checkout = function()
        vim.cmd('TSUpdate')
      end,
    },
  })

  require('nvim-treesitter').setup()

  -- autoinstall代替
  -- vim.api.nvim_create_autocmd({ 'Filetype' }, {
  --   callback = function(event)
  --     local ok, nvim_treesitter = pcall(require, 'nvim-treesitter')
  --     if not ok then
  --       return
  --     end
  --     local ft = vim.bo[event.buf].ft
  --     local lang = vim.treesitter.language.get_lang(ft)
  --     nvim_treesitter.install({ lang }):await(function(err)
  --       if err then
  --         vim.notify('Treesitter install error for ft: ' .. ft .. ' err: ' .. err)
  --         return
  --       end
  --       pcall(vim.treesitter.start, event.buf)
  --       vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  --       vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
  --     end)
  --   end,
  -- })

  -- これはたしかkawarimiさんが紹介していたエラーを抑止するための方法
  vim.treesitter.start = (function(wrapped)
    return function(bufnr, lang)
      lang = lang or vim.fn.getbufvar(bufnr or '', '&filetype')
      pcall(wrapped, bufnr, lang)
    end
  end)(vim.treesitter.start)

  -- vim.api.nvim_create_autocmd('FileType', {
  --   group = vim.api.nvim_create_augroup('vim-treesitter-start', {}),
  --   callback = function(_ctx)
  --     -- 必要に応じて`ctx.match`に入っているファイルタイプの値に応じて挙動を制御
  --     -- `pcall`でエラーを無視することでパーサーやクエリがあるか気にしなくてすむ
  --     pcall(vim.treesitter.start)
  --   end,
  -- })

  -- nvim-treesitter main以降後はconfigがない
  require('nvim-treesitter.configs').setup({
    modules = {},
    -- A list of parser names, or "all" (the listed parsers MUST always be installed)
    ensure_installed = {},
    -- Install parsers synchronously (only applied to `ensure_installed`)
    sync_install = false,
    -- List of parsers to ignore installing (or "all")
    ignore_install = {},

    auto_install = true,
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = true,
    },
  })
end)

later(function()
  add({
    source = 'JoosepAlviste/nvim-ts-context-commentstring',
    depends = { 'nvim-treesitter/nvim-treesitter' },
  })

  require('ts_context_commentstring').setup({
    enable_autocmd = false,
  })

  local get_option = vim.filetype.get_option
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.filetype.get_option = function(filetype, option)
    return option == 'commentstring' and require('ts_context_commentstring.internal').calculate_commentstring()
      or get_option(filetype, option)
  end
end)

later(function()
  require('mini.git').setup()

  vim.keymap.set({ 'n', 'x' }, '<Leader>gs', MiniGit.show_at_cursor, { desc = 'Show at cursor' })
end)

later(function()
  add({
    source = 'NeogitOrg/neogit',
    depends = {
      'nvim-lua/plenary.nvim',
      'sindrets/diffview.nvim',
      'nvim-telescope/telescope.nvim',
    },
  })

  vim.api.nvim_create_user_command('Neogit', function()
    require('neogit').open()
  end, { desc = 'Open Neogit' })

  vim.keymap.set('n', '<A-g>', function()
    require('neogit').open()
  end, { desc = 'Open Neogit' })
end)

later(function()
  add({
    source = 'lambdalisue/vim-gin',
    depends = { 'vim-denops/denops.vim' },
  })

  -- vim.api.nvim_create_user_command('Gs', function()
  --   vim.cmd('GinStatus')
  -- end, { desc = 'GinStatus' })
end)

later(function()
  require('mini.diff').setup()
end)

later(function()
  add({
    source = 'sindrets/diffview.nvim',
    depends = { 'nvim-lua/plenary.nvim' },
  })

  require('diffview').setup({
    view = {
      merge_tool = {
        layout = 'diff3_mixed',
        disable_diagnostics = true,
      },
    },
  })
end)

-- later(function()
--   add({
--     source = 'subnut/nvim-ghost.nvim',
--   })
--
--   vim.g.nvim_ghost_server_port = 4001
--
--   -- augroup nvim_ghost_user_autocommands
--   --   au User www.reddit.com,www.stackoverflow.com setfiletype markdown
--   --   au User www.reddit.com,www.github.com setfiletype markdown
--   --   au User *github.com setfiletype markdown
--   -- augroup END
-- end)

-- ui ----------------------------------------------------------------
later(function()
  require('mini.statusline').setup()
  vim.opt.laststatus = 3
  -- vim.opt.cmdheight = 0

  -- vim.api.nvim_create_autocmd({ 'RecordingEnter', 'CmdlineEnter' }, {
  --   pattern = '*',
  --   callback = function()
  --     vim.opt.cmdheight = 1
  --   end,
  -- })
  -- vim.api.nvim_create_autocmd('RecordingLeave', {
  --   pattern = '*',
  --   callback = function()
  --     vim.opt.cmdheight = 0
  --   end,
  -- })
  -- vim.api.nvim_create_autocmd('CmdlineLeave', {
  --   pattern = '*',
  --   callback = function()
  --     if vim.fn.reg_recording() == '' then
  --       vim.opt.cmdheight = 0
  --     end
  --   end,
  -- })
end)

later(function()
  require('mini.tabline').setup()
end)

later(function()
  require('mini.indentscope').setup({
    draw = {
      delay = 0,
      animation = require('mini.indentscope').gen_animation.none(),
    },
  })
  vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    callback = function()
      local ignore_filetypes = {
        '',
        'NvimTree',
        'Trouble',
        'aerial',
        'better_term',
        'help',
        'lazy',
        'lazyterm',
        'mason',
        'notify',
        'toggleterm',
        'trouble',
      }
      if vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
        vim.b.miniindentscope_disable = true
      end
    end,
  })
end)

-- later(function()
--   add({
--     source = 'emmanueltouzery/key-menu.nvim',
--   })
-- end)

later(function()
  local clue = require('mini.clue')
  local function mode_nx(keys)
    return { mode = 'n', keys = keys }, { mode = 'v', keys = keys }
  end

  clue.setup({
    window = {
      -- Delay before showing clue window
      delay = 100,
    },
    triggers = {
      -- Leader triggers
      mode_nx('<leader>'),

      -- Built-in completion
      { mode = 'i', keys = '<c-x>' },

      -- `g` key
      mode_nx('g'),

      -- Marks
      mode_nx("'"),
      mode_nx('`'),

      -- Registers
      mode_nx('"'),
      { mode = 'i', keys = '<c-r>' },
      { mode = 'c', keys = '<c-r>' },

      -- Window commands
      { mode = 'n', keys = '<c-w>' },

      -- bracketed commands
      { mode = 'n', keys = '[' },
      { mode = 'n', keys = ']' },

      -- `z` key
      mode_nx('z'),

      -- surround
      -- mode_nv('s'),

      -- text object
      { mode = 'v', keys = 'i' },
      { mode = 'v', keys = 'a' },
      { mode = 'o', keys = 'i' },
      { mode = 'o', keys = 'a' },

      -- option toggle (mini.basics)
      -- { mode = 'n', keys = 'm' },

      -- telescope
      { mode = 'n', keys = '<C-k>' },

      -- trouble
      { mode = 'n', keys = '<Leader>x' },
    },

    clues = {
      -- Enhance this by adding descriptions for <Leader> mapping groups
      clue.gen_clues.builtin_completion(),
      clue.gen_clues.g(),
      clue.gen_clues.marks(),
      clue.gen_clues.registers({ show_contents = true }),
      clue.gen_clues.windows({ submode_resize = true, submode_move = true }),
      clue.gen_clues.z(),
    },
  })
end)

later(function()
  require('mini.cursorword').setup()
end)

later(function()
  local hipatterns = require('mini.hipatterns')
  local hi_words = require('mini.extra').gen_highlighter.words

  hipatterns.setup({
    highlighters = {
      -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
      fixme = hi_words({ 'FIXME', 'Fixme', 'fixme' }, 'MiniHipatternsFixme'),
      hack = hi_words({ 'HACK', 'Hack', 'hack' }, 'MiniHipatternsHack'),
      todo = hi_words({ 'TODO', 'Todo', 'todo' }, 'MiniHipatternsTodo'),
      note = hi_words({ 'NOTE', 'Note', 'note' }, 'MiniHipatternsNote'),
      -- Highlight hex color strings (`#rrggbb`) using that color
      hex_color = hipatterns.gen_highlighter.hex_color(),
    },
  })
end)

later(function()
  add({
    source = 'kevinhwang91/nvim-bqf',
  })
end)

later(function()
  add({
    source = 'stevearc/quicker.nvim',
    -- source = 'thinca/vim-qfreplace'
  })

  require('quicker').setup({
    keys = {
      {
        '>',
        function()
          require('quicker').expand({ before = 2, after = 2, add_to_existing = true })
        end,
        desc = 'Expand quickfix context',
      },
      {
        '<',
        function()
          require('quicker').collapse()
        end,
        desc = 'Collapse quickfix context',
      },
    },
  })

  vim.keymap.set('n', '<leader>q', function()
    require('quicker').toggle()
    require('quicker').refresh()
  end, {
    desc = 'Toggle quickfix',
  })
  vim.keymap.set('n', '<leader>l', function()
    require('quicker').toggle({ loclist = true })
    require('quicker').refresh()
  end, {
    desc = 'Toggle loclist',
  })
end)

later(function()
  add({
    source = 'folke/trouble.nvim',
  })
  require('trouble').setup()

  vim.api.nvim_set_keymap('n', '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>', { desc = 'Diagnostics (Trouble)' })
  vim.api.nvim_set_keymap(
    'n',
    '<leader>xX',
    '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
    { desc = 'Buffer Diagnostics (Trouble)' }
  )
  vim.api.nvim_set_keymap(
    'n',
    '<leader>xs',
    '<cmd>Trouble symbols toggle focus=false<cr>',
    { desc = 'Symbols (Trouble)' }
  )
  vim.api.nvim_set_keymap(
    'n',
    '<leader>xl',
    '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
    { desc = 'LSP Definitions / references / ... (Trouble)' }
  )
  vim.api.nvim_set_keymap('n', '<leader>xL', '<cmd>Trouble loclist toggle<cr>', { desc = 'Location List (Trouble)' })
  vim.api.nvim_set_keymap('n', '<leader>xQ', '<cmd>Trouble qflist toggle<cr>', { desc = 'Quickfix List (Trouble)' })

  -- vim.api.nvim_create_user_command(
  --   'Trouble',
  --   function()
  --   end,
  --   { desc = '' }
  -- )
end)

-- later(function()
--   add({
--     source = 'folke/noice.nvim',
--     depends = {
--       'MunifTanjim/nui.nvim',
--       'rcarriga/nvim-notify',
--       'hr7sh7th/nvim-cmp',
--     },
--   })
--
--   require('noice').setup({
--     lsp = {
--       -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
--       override = {
--         ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
--         ['vim.lsp.util.stylize_markdown'] = true,
--         ['cmp.entry.get_documentation'] = true, -- requires hrsh7th/nvim-cmp
--       },
--     },
--     -- you can enable a preset for easier configuration
--     presets = {
--       bottom_search = true, -- use a classic bottom cmdline for search
--       command_palette = true, -- position the cmdline and popupmenu together
--       long_message_to_split = true, -- long messages will be sent to a split
--       inc_rename = false, -- enables an input dialog for inc-rename.nvim
--       lsp_doc_border = false, -- add a border to hover docs and signature help
--     },
--   })
-- end)

-- fuzzy finder ----------------------------------------------------------------
later(function()
  add({
    source = 'nvim-telescope/telescope.nvim',
    depends = {
      'nvim-lua/plenary.nvim',
      'folke/trouble.nvim',
      'rcarriga/nvim-notify',
    },
  })
  add({
    source = 'nvim-telescope/telescope-live-grep-args.nvim',
    depends = { 'nvim-telescope/telescope.nvim' },
  })

  local open_with_trouble = require('trouble.sources.telescope').open
  --- @diagnostic disable-next-line: unused-local
  local add_to_trouble = require('trouble.sources.telescope').add
  local lga_actions = require('telescope-live-grep-args.actions')

  require('telescope').setup({
    defaults = {
      generic_sorter = require('mini.fuzzy').get_telescope_sorter,
      path_display = {
        'filename_first',
      },
      vimgrep_arguments = {
        'rg',
        '--vimgrep',
        '--smart-case',
        '--hidden',
        '--glob',
        '!.git/',
        -- --no-ignore
        -- '--glob',
        -- '!*.lock',
        -- '--glob',
        -- '!*.lock.json'
      },
      -- layout_strategy = 'vertical',
      -- layout_config = {
      --   prompt_position = 'top',
      -- },
      mappings = {
        i = {
          ['<C-t>'] = open_with_trouble,
        },
        n = {
          ['<C-t>'] = open_with_trouble,
        },
      },
    },
    pickers = {
      find_files = {
        find_command = {
          'fd',
          '--color',
          'never',
          '--type',
          'file',
          '--hidden',
          '--no-ignore',
          '--exclude',
          '.git',
          '--strip-cwd-prefix',
        },
      },
    },
    extensions = {
      live_grep_args = {
        auto_quoting = true, -- enable/disable auto-quoting
        mappings = {
          -- extend mappings
          i = {
            ['<C-k>'] = lga_actions.quote_prompt(),
            -- ["<C-Space>"] = lga_actions.quote_prompt({ postfix = " --t " }),
          },
        },
      },
    },
  })

  -- require('telescope').load_extension('notify')
  require('telescope').load_extension('live_grep_args')

  -- builtin
  vim.keymap.set('n', '<F1>', function()
    require('telescope.builtin').help_tags()
  end, {
    desc = 'telescope help_tags',
  })
  vim.keymap.set('n', '<C-p>', function()
    require('telescope.builtin').find_files()
  end, {
    desc = 'telescope find files',
  })
  vim.keymap.set('n', '<C-g>', function()
    -- require('telescope.builtin').live_grep()
    require('telescope').extensions.live_grep_args.live_grep_args()
  end, {
    desc = 'telescope live grep',
  })
  vim.keymap.set('n', 'q', function()
    require('telescope.builtin').current_buffer_fuzzy_find()
  end, {
    desc = 'telescope current_buffer_fuzzy_find',
  })
  vim.keymap.set('n', 'Q', function()
    require('telescope.builtin').buffers()
  end, {
    desc = 'telescope buffers',
  })
  vim.keymap.set('n', '<C-k>g', function()
    require('telescope.builtin').git_files()
  end, {
    desc = 'telescope git files',
  })
  vim.keymap.set('n', '<C-k>*', function()
    require('telescope.builtin').grep_string()
  end, {
    desc = 'telescope grep string under your cursor',
  })
  vim.keymap.set('n', '<C-k>o', function()
    require('telescope.builtin').oldfiles()
  end, {
    desc = 'telescope old files',
  })
  vim.keymap.set('n', '<C-k>h', function()
    require('telescope.builtin').command_history()
  end, {
    desc = 'telescope command history',
  })
  vim.keymap.set('n', '<C-k>/', function()
    require('telescope.builtin').search_history()
  end, {
    desc = 'telescope search history',
  })
  vim.keymap.set('n', '<C-k>c', function()
    require('telescope.builtin').commands()
  end, {
    desc = 'telescope commands',
  })
  -- vim.keymap.set('n', '<C-k>b', function()
  --   require('telescope.builtin').git_branches()
  -- end, {
  --   desc = 'telescope git branches',
  -- })
  -- vim.keymap.set('n', '<C-k>s', function()
  --   require('telescope.builtin').git_status()
  -- end, {
  --   desc = 'telescope git status',
  -- })
  vim.keymap.set('n', '<C-k>m', function()
    require('telescope.builtin').marks()
  end, {
    desc = 'telescope marks',
  })
  vim.keymap.set('n', '<C-k>q', function()
    require('telescope.builtin').quickfix()
  end, {
    desc = 'telescope quickfix',
  })
  vim.keymap.set('n', '<C-k>w', function()
    require('telescope.builtin').quickfixhistory()
  end, {
    desc = 'telescope quickfix history',
  })
  vim.keymap.set('n', '<C-k>l', function()
    require('telescope.builtin').loclist()
  end, {
    desc = 'telescope loclist',
  })
  vim.keymap.set('n', '<C-k>j', function()
    require('telescope.builtin').jumplist()
  end, {
    desc = 'telescope jumplist',
  })
  -- vim.keymap.set('n', '<Leader>tt', function()
  --   require('telescope.builtin').treesitter()
  -- end, {
  --   desc = 'telescope treesitter',
  -- })
  vim.keymap.set('n', '<C-k>k', function()
    require('telescope.builtin').keymaps()
  end, {
    desc = 'telescope keymaps',
  })
  vim.keymap.set('n', '<C-k>;', function()
    require('telescope.builtin').resume()
  end, {
    desc = 'telescope resume',
  })
end)

-- later(function()
--   require('mini.pick').setup()
--
--   vim.ui.select = MiniPick.ui_select
--
--   vim.keymap.set('n', '<C-p>f', function()
--     MiniPick.builtin.files({ tool = 'git' })
--   end, { desc = 'mini.pick.files' })
-- end)
--
-- inputs ----------------------------------------------------------------
later(function()
  add({
    source = 'vim-skk/skkeleton',
    depends = {
      'vim-denops/denops.vim',
    },
  })

  vim.fn['skkeleton#config']({
    globalDictionaries = {
      vim.fn.stdpath('config') .. '/skk/SKK-JISYO.L',
      vim.fn.stdpath('config') .. '/skk/SKK-JISYO.emoji.utf8',
      vim.fn.stdpath('config') .. '/skk/skk-x-emoji.txt',
    },
    sources = { 'skk_dictionary', 'google_japanese_input' },
    -- sources = { 'skk_server' },
    eggLikeNewline = true,
    showCandidatesCount = 1,
  })

  vim.keymap.set({ 'i', 'c', 't' }, [[<C-j>]], [[<Plug>(skkeleton-enable)]], { noremap = false })
end)

-- completion ----------------------------------------------------------------
later(function()
  local build = function(args)
    local obj = vim.system({ 'make', '-C', args.path, 'install_jsregexp' }, { text = true }):wait()
    vim.print(vim.inspect(obj))
  end

  add({
    source = 'L3MON4D3/LuaSnip',
    hooks = {
      post_install = function(args)
        later(function()
          build(args)
        end)
      end,
    },
  })

  local luasnip = require('luasnip')
  require('luasnip.loaders.from_vscode').lazy_load()
  -- load snippets from path/of/your/nvim/config/my-cool-snippets
  -- require('luasnip.loaders.from_vscode').lazy_load({ paths = { './my-cool-snippets' } })

  -- vim.keymap.set({ 'i' }, '<C-y>', function()
  --   ---@diagnostic disable-next-line: missing-parameter
  --   luasnip.expand()
  -- end, { silent = true })
  -- vim.keymap.set({ 'i', 's' }, '<C-l>', function()
  --   luasnip.jump(1)
  -- end, { silent = true })
  -- vim.keymap.set({ 'i', 's' }, '<C-k>', function()
  --   luasnip.jump(-1)
  -- end, { silent = true })
  -- vim.keymap.set({ 'i', 's' }, '<C-,>', function()
  --   if luasnip.choice_active() then
  --     luasnip.change_choice(1)
  --   end
  -- end, { silent = true })

  add({
    source = 'hrsh7th/nvim-cmp',
    depends = {
      'neovim/nvim-lspconfig',
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
      'rafamadriz/friendly-snippets',
    },
  })
  add({
    source = 'onsails/lspkind.nvim',
  })

  local cmp = require('cmp')
  local lspkind = require('lspkind')
  cmp.setup({
    snippet = {
      -- REQUIRED - you must specify a snippet engine
      expand = function(args)
        -- vim.fn['vsnip#anonymous'](args.body) -- For `vsnip` users.
        require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
        -- require('snippy').expand_snippet(args.body) -- For `snippy` users.
        -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
        -- vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)

        -- For `mini.snippets` users:
        -- local insert = MiniSnippets.config.expand.insert or MiniSnippets.default_insert
        -- insert({ body = args.body }) -- Insert at cursor
        -- cmp.resubscribe({ "TextChangedI", "TextChangedP" })
        -- require("cmp.config").set_onetime({ sources = {} })
      end,
    },
    window = {
      -- completion = cmp.config.window.bordered(),
      -- documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-u>'] = cmp.mapping.scroll_docs(-4),
      ['<C-d>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      -- ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
      -- super tab
      -- https://github.com/hrsh7th/nvim-cmp/wiki/Example-mappings#luasnip
      ['<CR>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          if luasnip.expandable() then
            --- @diagnostic disable-next-line: missing-parameter
            luasnip.expand()
          else
            cmp.confirm({
              select = true,
            })
          end
        else
          fallback()
        end
      end),

      ['<Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.locally_jumpable(1) then
          luasnip.jump(1)
        else
          fallback()
        end
      end, { 'i', 's' }),

      ['<S-Tab>'] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.locally_jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { 'i', 's' }),
    }),
    -- {
    --   -- default keymaps start
    --   ['<Down>'] = {
    --     i = cmp.mapping.select_next_item({ behavior = cmp.types.cmp.SelectBehavior.Select }),
    --   },
    --   ['<Up>'] = {
    --     i = cmp.mapping.select_prev_item({ behavior = cmp.types.cmp.SelectBehavior.Select }),
    --   },
    --   ['<C-n>'] = {
    --     i = function()
    --       if cmp.visible() then
    --         cmp.select_next_item({ behavior = cmp.types.cmp.SelectBehavior.Insert })
    --       else
    --         cmp.complete()
    --       end
    --     end,
    --   },
    --   ['<C-p>'] = {
    --     i = function()
    --       if cmp.visible() then
    --         cmp.select_prev_item({ behavior = cmp.types.cmp.SelectBehavior.Insert })
    --       else
    --         cmp.complete()
    --       end
    --     end,
    --   },
    --   ['<C-y>'] = {
    --     i = cmp.mapping.confirm({ select = false }),
    --   },
    --   ['<C-e>'] = {
    --     i = cmp.mapping.abort(),
    --   },
    --   -- default keymapse end
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      -- { name = 'vsnip' }, -- For vsnip users.
      { name = 'luasnip' }, -- For luasnip users.
      -- { name = 'ultisnips' }, -- For ultisnips users.
      -- { name = 'snippy' }, -- For snippy users.
    }, {
      { name = 'buffer' },
      { name = 'path' },
    }),
    formatting = {
      format = lspkind.cmp_format({
        mode = 'symbol_text', -- show only symbol annotations
        maxwidth = {
          -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
          -- can also be a function to dynamically calculate max width such as
          -- menu = function() return math.floor(0.45 * vim.o.columns) end,
          menu = 50, -- leading text (labelDetails)
          abbr = 50, -- actual suggestion item
        },
        ellipsis_char = '...', -- when popup menu exceed maxwidth, the truncated part would show ellipsis_char instead (must define maxwidth first)
        show_labelDetails = true, -- show labelDetails in menu. Disabled by default

        -- The function below will be called before any actual modifications from lspkind
        -- so that you can provide more controls on popup customization. (See [#30](https://github.com/onsails/lspkind-nvim/pull/30))
        before = function(entry, vim_item)
          -- ...
          return vim_item
        end,
      }),
    },
  })
  -- To use git you need to install the plugin petertriho/cmp-git and uncomment lines below
  -- Set configuration for specific filetype.
  -- cmp.setup.filetype('gitcommit', {
  --   sources = cmp.config.sources({
  --     { name = 'git' },
  --   }, {
  --     { name = 'buffer' },
  --   }),
  -- })
  -- require('cmp_git').setup()

  -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline({ '/', '?' }, {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
      { name = 'buffer' },
    },
  })

  -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = 'path' },
    }, {
      { name = 'cmdline' },
    }),
    matching = { disallow_symbol_nonprefix_matching = false },
  })
end)

-- later(function()
--   add({
--     source = 'rafamadriz/friendly-snippets',
--   })
--   require('mini.fuzzy').setup()
--   require('mini.completion').setup({
--     lsp_completion = {
--       process_items = MiniFuzzy.process_lsp_items,
--     },
--   })
--
--   -- improve fallback completion
--   vim.opt.complete = { '.', 'w', 'k', 'b', 'u' }
--   vim.opt.completeopt:append('fuzzy')
--   -- vim.opt.dictionary:append('/usr/share/dict/words')
--
--   -- define keycodes
--   local keys = {
--     cn = vim.keycode('<c-n>'),
--     cp = vim.keycode('<c-p>'),
--     ct = vim.keycode('<c-t>'),
--     cd = vim.keycode('<c-d>'),
--     cr = vim.keycode('<cr>'),
--     cy = vim.keycode('<c-y>'),
--   }
--
--   -- select by <tab>/<s-tab>
--   vim.keymap.set('i', '<tab>', function()
--     -- popup is visible -> next item
--     -- popup is NOT visible -> add indent
--     return vim.fn.pumvisible() == 1 and keys.cn or keys.ct
--   end, { expr = true, desc = 'Select next item if popup is visible' })
--   vim.keymap.set('i', '<s-tab>', function()
--     -- popup is visible -> previous item
--     -- popup is NOT visible -> remove indent
--     return vim.fn.pumvisible() == 1 and keys.cp or keys.cd
--   end, { expr = true, desc = 'Select previous item if popup is visible' })
--
--   -- complete by <cr>
--   vim.keymap.set('i', '<cr>', function()
--     if vim.fn.pumvisible() == 0 then
--       -- popup is NOT visible -> insert newline
--       return require('mini.pairs').cr()
--       -- alternative if you want to avoid require
--       -- return keys.cr
--     end
--     local item_selected = vim.fn.complete_info()['selected'] ~= -1
--     if item_selected then
--       -- popup is visible and item is selected -> complete item
--       return keys.cy
--     end
--     -- popup is visible but item is NOT selected -> hide popup and insert newline
--     return keys.cy .. keys.cr
--   end, { expr = true, desc = 'Complete current item if item is selected' })
--
--   local gen_loader = require('mini.snippets').gen_loader
--   require('mini.snippets').setup({
--     snippets = {
--       -- Load custom file with global snippets first (adjust for Windows)
--       gen_loader.from_file('~/.config/nvim/snippets/global.json'),
--
--       -- Load snippets based on current language by reading files from
--       -- "snippets/" subdirectories from 'runtimepath' directories.
--       gen_loader.from_lang(),
--     },
--   })
-- end)

-- lsp ----------------------------------------------------------------
later(function()
  add({ source = 'williamboman/mason.nvim' })
  add({
    source = 'williamboman/mason-lspconfig.nvim',
    depends = { 'williamboman/mason.nvim' },
  })
  add({
    source = 'neovim/nvim-lspconfig',
    depends = { 'williamboman/mason.nvim' },
  })

  require('mason').setup()
  -- nvim --headless -c "MasonInstall actionlint buf eslint-lsp selene sqlfluff stylelint stylua yamllint shfmt goimports" -c qall

  require('mason-lspconfig').setup({
    automatic_enable = false,
    automatic_installation = true,
    ensure_installed = {},
    -- ensure_installed = {
    --   -- lsp
    --   'bashls',
    --   'eslint',
    --   'gopls',
    --   'lua_ls',
    --   'ruby_lsp',
    --   'rust_analyzer',
    --   'taplo',
    --   'vtsls',
    --   'vue_ls',
    --   -- tools
    --   'rubocop',
    -- },
  })
end)

-- later(function()
--   add({
--     source = 'j-hui/fidget.nvim',
--   })
--   require('fidget').setup({})
-- end)

-- llm ----------------------------------------------------------------
later(function()
  add({ source = 'zbirenbaum/copilot.lua' })

  ---@diagnostic disable-next-line: undefined-field
  require('copilot').setup({
    suggestion = {
      auto_trigger = true,
      hide_during_completion = false,
    },
    filetypes = {
      markdown = true,
      gitcommit = true,
      ['*'] = function()
        -- disable for files with specific names
        local fname = vim.fs.basename(vim.api.nvim_buf_get_name(0))
        local disable_patterns = { 'env', 'conf', 'local', 'private' }
        return vim.iter(disable_patterns):all(function(pattern)
          return not string.match(fname, pattern)
        end)
      end,
    },
  })

  -- set CopilotSuggestion as underlined comment
  local hl = vim.api.nvim_get_hl(0, { name = 'Comment' })
  vim.api.nvim_set_hl(0, 'CopilotSuggestion', vim.tbl_extend('force', hl, { underline = true }))
end)

later(function()
  add({
    source = 'nvim-lua/plenary.nvim',
  })
  add({
    source = 'CopilotC-Nvim/CopilotChat.nvim',
    depends = {
      'nvim-lua/plenary.nvim',
      'zbirenbaum/copilot.lua',
    },
  })

  local default_prompts = require('CopilotChat.config.prompts')
  local in_japanese = 'なお、説明は日本語でお願いします。'
  require('CopilotChat').setup({
    prompts = vim.tbl_deep_extend('force', default_prompts, {
      -- ビルトインのプロンプトを日本語化
      Explain = { prompt = default_prompts.Explain.prompt .. in_japanese },
      Review = { prompt = default_prompts.Review.prompt .. in_japanese },
      Fix = { prompt = default_prompts.Fix.prompt .. in_japanese },
      Optimize = { prompt = default_prompts.Optimize.prompt .. in_japanese },
      -- 日英翻訳のプロンプトを独自に追加
      TranslateJE = {
        prompt = 'Translate the selected text from English to Japanese if it is in English, or from Japanese to English if it is in Japanese. Please do not include unnecessary line breaks, line numbers, comments, etc. in the result.',
        system_prompt = 'You are an excellent Japanese-English translator. You can translate the original text correctly without losing its meaning. You also have deep knowledge of system engineering and are good at translating technical documents.',
        description = 'Translate text from Japanese to English or vice versa',
      },
    }),
  })

  vim.opt.splitright = true
  vim.keymap.set('ca', 'chat', 'CopilotChat', { desc = 'Ask CopilotChat' })
  vim.keymap.set({ 'n', 'x' }, '<Leader>p', '<cmd>CopilotChatPrompt<cr>', { desc = 'CopilotChat predefined prompts' })
end)

later(function()
  add({
    source = 'greggh/claude-code.nvim',
    depends = {
      'nvim-lua/plenary.nvim',
    },
  })

  require('claude-code').setup({
    window = {
      split_ratio = 0.4, -- Percentage of screen for the terminal window (height for horizontal, width for vertical splits)
      position = 'vertical', -- Position of the window: "botright", "topleft", "vertical", "float", etc.
      enter_insert = true, -- Whether to enter insert mode when opening Claude Code
      hide_numbers = true, -- Hide line numbers in the terminal window
      hide_signcolumn = true, -- Hide the sign column in the terminal window

      -- Floating window configuration (only applies when position = "float")
      float = {
        width = '80%', -- Width: number of columns or percentage string
        height = '80%', -- Height: number of rows or percentage string
        row = 'center', -- Row position: number, "center", or percentage string
        col = 'center', -- Column position: number, "center", or percentage string
        relative = 'editor', -- Relative to: "editor" or "cursor"
        border = 'rounded', -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
      },
    },
    -- command = '~/.local/bin/claude',
    keymaps = {
      toggle = {
        normal = '<Leader>cc', -- Normal mode keymap for toggling Claude Code, false to disable
        terminal = '<Leader>cc', -- Terminal mode keymap for toggling Claude Code, false to disable
        variants = {
          continue = '<Leader>cC', -- Normal mode keymap for Claude Code with continue flag
          verbose = '<Leader>cV', -- Normal mode keymap for Claude Code with verbose flag
        },
      },
      window_navigation = false, -- Enable window navigation keymaps (<C-h/j/k/l>)
      scrolling = false, -- Enable scrolling keymaps (<C-f/b>) for page up/down
    },
  })
  vim.keymap.set('n', '<Leader>cc', '<cmd>ClaudeCode<CR>', { desc = 'Toggle Claude Code' })
end)

later(function()
  add({
    source = 'lambdalisue/nvim-aibo',
  })

  --- @diagnostic disable-next-line: redundant-parameter
  require('aibo').setup({
    -- Prompt buffer configuration
    prompt = {
      no_default_mappings = false, -- Set to true to disable default keymaps
      -- on_attach = function(bufnr, info)
      --   -- Custom setup for prompt buffers
      --   -- Runs AFTER ftplugin files
      --   -- info.type = "prompt"
      --   -- info.tool = tool name (e.g., "claude")
      --   -- info.aibo = aibo instance
      -- end,
    },

    -- Console buffer configuration
    console = {
      no_default_mappings = false,
      -- on_attach = function(bufnr, info)
      --   -- Custom setup for console buffers
      --   -- info.type = "console"
      --   -- info.cmd = command being executed
      --   -- info.args = command arguments
      --   -- info.job_id = terminal job ID
      -- end,
    },

    -- Tool-specific overrides
    tools = {
      claude = {
        no_default_mappings = false,
        -- on_attach = function(bufnr, info)
        --   -- Custom setup for Claude buffers
        --   -- Called after prompt/console on_attach
        -- end,
      },
      codex = {
        -- Codex-specific configuration
      },
    },
  })

  -- vim.keymap.set('n', '<Leader>cc', function()
  --   local width = math.floor(vim.o.columns * 1 / 3)
  --   vim.cmd(string.format('Aibo -opener="%dvsplit" claude', width))
  -- end, { desc = 'Open Claude AI assistant' })
  --
  -- vim.keymap.set('n', '<Leader>cC', function()
  --   local width = math.floor(vim.o.columns * 1 / 3)
  --   vim.cmd(string.format('Aibo -opener="%dvsplit" claude --continue', width))
  -- end, { desc = 'Open Claude AI assistant' })
  --
  -- vim.keymap.set({ 'n', 'x' }, '<Leader>cs', '<cmd>AiboSend<CR>', { desc = 'AiboSend' })
end)

-- formatting ---------------------------------------------------------------
later(function()
  add({
    source = 'stevearc/conform.nvim',
  })
  require('conform').setup({
    default_format_opts = {
      lsp_format = 'fallback',
      timeout_ms = 500,
    },
    format_on_save = function(buf)
      -- `:w!`で保存したときはフォーマットをスキップ
      if vim.v.cmdbang == 1 then
        return nil
      end

      local name = vim.api.nvim_buf_get_name(buf)
      local basename = vim.fs.basename(name)

      -- lockファイルはフォーマットをスキップ
      if basename:match('%.lock$') or basename:match('%plock%p') then
        -- do not format lock files
        return nil
      end

      -- その他のファイルはsetup時の設定でフォーマット
      return {}
    end,
    formatters = {
      yaml = {
        append_args = { '--single-quote' },
      },
    },
    formatters_by_ft = {
      go = { 'gofmt', 'goimports' },
      json = { 'deno_fmt' },
      jsonc = { 'deno_fmt' },
      lua = { 'stylua' },
      ruby = { 'rubocop' },
      sh = { 'shfmt' },
      yaml = { 'deno_fmt' },
    },
  })
  vim.o.formatexpr = "v:lua.require('conform').formatexpr()"

  vim.api.nvim_create_user_command('Format', function()
    require('conform').format()
  end, { desc = 'Format current buffer' })

  vim.keymap.set('n', '<Leader>f', function()
    require('conform').format()
  end, { desc = 'Format current buffer' })
end)

-- linting ----------------------------------------------------------------
later(function()
  add({
    source = 'mfussenegger/nvim-lint',
  })

  require('lint').linters_by_ft = {
    fish = { 'fish' },
    -- lua = { 'selene' },
    ruby = { 'rubocop' },
    -- sh = { 'shellcheck' },
  }

  vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'InsertLeave' }, {
    callback = function()
      -- try_lint without arguments runs the linters defined in `linters_by_ft`
      -- for the current filetype
      require('lint').try_lint()

      -- You can call `try_lint` with a linter name or a list of names to always
      -- run specific linters, independent of the `linters_by_ft` configuration
      -- require('lint').try_lint('cspell')
    end,
  })
end)

-- filetype specific  ----------------------------------------------------------------
-- markdown
later(function()
  add({
    source = 'ixru/nvim-markdown',
  })
end)

later(function()
  add({
    source = 'MeanderingProgrammer/render-markdown.nvim',
    depends = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-mini/mini.nvim',
    },
  })
end)

-- terminal ----------------------------------------------------------------
later(function()
  add({
    source = 'akinsho/toggleterm.nvim',
  })

  require('toggleterm').setup({
    direction = 'horizontal',
    size = function(term)
      if term.direction == 'horizontal' then
        return 20
      elseif term.direction == 'vertical' then
        return vim.o.columns * 0.5
      end
    end,
  })
  vim.keymap.set({ 'n' }, '<Leader>t', '<Cmd>exe v:count1 . "ToggleTerm"<CR>', {})
  vim.keymap.set({ 'n' }, '<Leader>ta', '<Cmd>ToggleTermToggleAll<CR>', {})
  vim.keymap.set({ 'n' }, '<Leader>y', '<Cmd>10ToggleTerm direction=float<CR>', {})
  vim.keymap.set({ 'n', 't' }, '<F6>', '<Cmd>10ToggleTerm direction=float<CR>', {})

  -- local Terminal = require('toggleterm.terminal').Terminal
  -- local lazygit = Terminal:new({
  --   cmd = 'lazygit',
  --   direction = 'float',
  --   hidden = true,
  --   count = 100,
  -- })
  --
  -- ---@diagnostic disable: lowercase-global
  -- function _lazygit_toggle()
  --   lazygit:toggle()
  -- end
  --
  -- vim.keymap.set('n', '<A-g>', '<Cmd>lua _lazygit_toggle()<CR>', {
  --   desc = 'lazygit',
  -- })
end)

-- other functions ----------------------------------------------------------------
later(function()
  add({
    source = 'potamides/pantran.nvim',
  })
  require('pantran').setup({
    -- Default engine to use for translation. To list valid engine names run
    -- `:lua =vim.tbl_keys(require("pantran.engines"))`.
    default_engine = 'google',
    -- Configuration for individual engines goes here.
    engines = {
      google = {
        -- Default languages can be defined on a per engine basis. In this case
        -- `:lua require("pantran.async").run(function() vim.pretty_print(require("pantran.engines").yandex:languages()) end)`
        -- can be used to list available language identifiers.
        default_source = 'auto',
        default_target = 'ja',
        fallback = {
          default_source = 'en',
          default_target = 'ja',
        },
      },
    },
    -- controls = {
    --   mappings = {
    --     edit = {
    --       n = {
    --         -- Use this table to add additional mappings for the normal mode in
    --         -- the translation window. Either strings or function references are
    --         -- supported.
    --         ['j'] = 'gj',
    --         ['k'] = 'gk',
    --       },
    --       i = {
    --         -- Similar table but for insert mode. Using 'false' disables
    --         -- existing keybindings.
    --         ['<C-y>'] = false,
    --         ['<C-a>'] = require('pantran.ui.actions').yank_close_translation,
    --       },
    --     },
    --     -- Keybindings here are used in the selection window.
    --     -- select = {
    --     --   n = {
    --     --     -- ...
    --     --   },
    --     -- },
    --   },
    -- },
  })
  local pantran = require('pantran')
  local opts = { noremap = true, silent = true, expr = true, desc = 'pantran translate' }
  vim.keymap.set('n', '<leader>tr', pantran.motion_translate, opts)
  vim.keymap.set('n', '<leader>trr', function()
    return pantran.motion_translate() .. '_'
  end, opts)
  vim.keymap.set('v', '<leader>tr', pantran.motion_translate, opts)
end)

-- colosrsheme ----------------------------------------------------------------
later(function()
  add({
    source = 'sainnhe/gruvbox-material',
  })

  vim.opt.termguicolors = true
  vim.opt.background = 'dark'
  vim.g.gruvbox_material_background = 'hard'
  vim.g.gruvbox_material_better_performance = 1

  -- already defined in core.lua
  -- https://github.com/folke/lsp-colors.nvim/issues/14
  -- vim.fn.sign_define("DiagnosticSignError", {
  --   text = '¤',
  --   texthl = 'red',
  --   linehl = '',
  --   numhl = ''
  -- })
  -- vim.fn.sign_define("DiagnosticSignWarn", {
  --   text = '•',
  --   texthl = 'yellow',
  --   linehl = '',
  --   numhl = ''
  -- })
  -- vim.fn.sign_define("DiagnosticSignHint", {
  --   text = '»',
  --   texthl = 'green',
  --   linehl = '',
  --   numhl = ''
  -- })
  -- vim.fn.sign_define("DiagnosticSignInfo", {
  --   text = 'i',
  --   texthl = 'gray',
  --   linehl = '',
  --   numhl = ''
  -- })
  --
  vim.api.nvim_exec2(
    [[
      augroup gruvbox-material-theme-overrides
        autocmd!
        autocmd ColorScheme gruvbox-material highlight Folded ctermfg=LightGray guifg=#918d88
        autocmd ColorScheme gruvbox-material highlight Folded ctermbg=235 guibg=#282828
        autocmd ColorScheme gruvbox-material highlight Folded cterm=italic gui=italic
        autocmd ColorScheme gruvbox-material highlight SignColumn ctermbg=235 guibg=#282828
        autocmd ColorScheme gruvbox-material highlight DiagnosticSign ctermbg=235 guibg=#282828
      augroup END
    ]],
    {
      output = false,
    }
  )
  vim.g.gruvbox_material_diagnostic_text_highlight = 1
  vim.g.gruvbox_material_diagnostic_line_highlight = 1
  vim.g.gruvbox_material_diagnostic_virtual_text = 'colored'

  vim.cmd([[colorscheme gruvbox-material]])
end)
