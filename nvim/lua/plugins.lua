-- Clone 'mini.nvim' manually in a way that it gets managed by 'mini.deps'
local path_package = vim.fn.stdpath('data') .. '/site/'
local mini_path = path_package .. 'pack/deps/start/mini.nvim'
if not vim.uv.fs_stat(mini_path) then
  vim.cmd('echo "Installing `mini.nvim`" | redraw')
  local clone_cmd = {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/echasnovski/mini.nvim',
    mini_path,
  }
  vim.fn.system(clone_cmd)
  vim.cmd('packadd mini.nvim | helptags ALL')
  vim.cmd('echo "Installed `mini.nvim`" | redraw')
end

-- Set up 'mini.deps' (customize to your liking)
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
  require('mini.files').setup({
    windows = {
      -- Whether to show preview of file/directory under cursor
      preview = true,
    },
  })

  vim.api.nvim_create_user_command('Files', function()
    MiniFiles.open()
  end, { desc = 'Open MiniFiles' })

  vim.keymap.set('n', '<Leader>e', function()
    MiniFiles.open()
  end, { desc = 'Open MiniFiles' })
end)

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
  require('mini.pairs').setup({
    modes = { insert = true, command = true, terminal = true },
    vim.keymap.set('i', '<CR>', 'v:lua.cr_action()', { expr = true }),
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

later(function()
  require('mini.jump').setup({
    mappings = {
      -- forward = 'f',
      -- backward = 'F',
      -- forward_till = 't',
      -- backward_till = 'T',
      repeat_jump = ':',
    },
  })
end)

-- later(function()
--   require('mini.jump2d').setup({
--     mappings = {
--       start_jumping = 's',
--     },
--   })
-- end)

later(function()
  add({
    source = 'ggandor/leap.nvim',
  })
  vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(leap)')
  vim.keymap.set('n', 'S', '<Plug>(leap-from-window)')
end)

later(function()
  require('mini.operators').setup({
    replace = { prefix = 'gR' },
    exchange = { prefix = 'g/' },
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
    -- Use 'master' while monitoring updates in 'main'
    checkout = 'master',
    monitor = 'main',
    -- Perform action after every checkout
    hooks = {
      post_checkout = function()
        vim.cmd('TSUpdate')
      end,
    },
  })

  vim.treesitter.start = (function(wrapped)
    return function(bufnr, lang)
      lang = lang or vim.fn.getbufvar(bufnr or '', '&filetype')
      pcall(wrapped, bufnr, lang)
    end
  end)(vim.treesitter.start)

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
  vim.filetype.get_option = function(filetype, option)
    return option == 'commentstring' and require('ts_context_commentstring.internal').calculate_commentstring()
      or get_option(filetype, option)
  end
end)

later(function()
  require('mini.diff').setup()
end)

later(function()
  require('mini.git').setup()

  vim.keymap.set({ 'n', 'x' }, '<Leader>gs', MiniGit.show_at_cursor, { desc = 'Show at cursor' })
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

later(function()
  add({
    source = 'nvim-lua/plenary.nvim',
  })
  add({
    source = 'sindrets/diffview.nvim',
  })
  add({
    source = 'nvim-telescope/telescope.nvim',
  })
  add({
    source = 'NeogitOrg/neogit',
    dependencies = { 'nvim-lua/plenary.nvim', 'sindrets/diffview.nvim', 'nvim-telescope/telescope.nvim' },
  })

  vim.api.nvim_create_user_command('Neogit', function()
    require('neogit').open()
  end, { desc = 'Open Neogit' })

  vim.keymap.set('n', '<A-g>', function()
    require('neogit').open()
  end, { desc = 'Open Neogit' })
end)

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
end)

later(function()
  local clue = require('mini.clue')
  local function mode_nx(keys)
    return { mode = 'n', keys = keys }, { mode = 'x', keys = keys }
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
      -- mode_nx('s'),

      -- text object
      { mode = 'x', keys = 'i' },
      { mode = 'x', keys = 'a' },
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

-- fuzzy finder ----------------------------------------------------------------
later(function()
  add({
    source = 'nvim-lua/plenary.nvim',
  })
  add({
    source = 'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim', 'folke/trouble.nvim' },
  })
  add({
    source = 'nvim-telescope/telescope-live-grep-args.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim' },
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
        '!.git',
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

-- completion ----------------------------------------------------------------
later(function()
  add({
    source = 'rafamadriz/friendly-snippets',
  })
  require('mini.fuzzy').setup()
  require('mini.completion').setup({
    lsp_completion = {
      process_items = MiniFuzzy.process_lsp_items,
    },
  })

  -- improve fallback completion
  vim.opt.complete = { '.', 'w', 'k', 'b', 'u' }
  vim.opt.completeopt:append('fuzzy')
  -- vim.opt.dictionary:append('/usr/share/dict/words')

  -- define keycodes
  local keys = {
    cn = vim.keycode('<c-n>'),
    cp = vim.keycode('<c-p>'),
    ct = vim.keycode('<c-t>'),
    cd = vim.keycode('<c-d>'),
    cr = vim.keycode('<cr>'),
    cy = vim.keycode('<c-y>'),
  }

  -- select by <tab>/<s-tab>
  vim.keymap.set('i', '<tab>', function()
    -- popup is visible -> next item
    -- popup is NOT visible -> add indent
    return vim.fn.pumvisible() == 1 and keys.cn or keys.ct
  end, { expr = true, desc = 'Select next item if popup is visible' })
  vim.keymap.set('i', '<s-tab>', function()
    -- popup is visible -> previous item
    -- popup is NOT visible -> remove indent
    return vim.fn.pumvisible() == 1 and keys.cp or keys.cd
  end, { expr = true, desc = 'Select previous item if popup is visible' })

  -- complete by <cr>
  vim.keymap.set('i', '<cr>', function()
    if vim.fn.pumvisible() == 0 then
      -- popup is NOT visible -> insert newline
      return require('mini.pairs').cr()
      -- alternative if you want to avoid require
      -- return keys.cr
    end
    local item_selected = vim.fn.complete_info()['selected'] ~= -1
    if item_selected then
      -- popup is visible and item is selected -> complete item
      return keys.cy
    end
    -- popup is visible but item is NOT selected -> hide popup and insert newline
    return keys.cy .. keys.cr
  end, { expr = true, desc = 'Complete current item if item is selected' })

  local gen_loader = require('mini.snippets').gen_loader
  require('mini.snippets').setup({
    snippets = {
      -- Load custom file with global snippets first (adjust for Windows)
      gen_loader.from_file('~/.config/nvim/snippets/global.json'),

      -- Load snippets based on current language by reading files from
      -- "snippets/" subdirectories from 'runtimepath' directories.
      gen_loader.from_lang(),
    },
  })
end)

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
    ensure_installed = {
      -- lsp
      'bashls',
      'eslint',
      'gopls',
      'lua_ls',
      'ruby_lsp',
      'rust_analyzer',
      'taplo',
      'vtsls',
      'volar',
      -- tools
      'rubocop',
    },
    automatic_installation = true,
  })
end)

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

-- formatting ---------------------------------------------------------------
add({
  source = 'stevearc/conform.nvim',
})
later(function()
  require('conform').setup({
    format_on_save = {
      -- These options will be passed to conform.format()
      timeout_ms = 500,
      lsp_format = 'fallback',
    },
    formatters_by_ft = {
      go = { 'gofmt', 'goimports' },
      json = { 'jq' },
      lua = { 'stylua' },
      ruby = { 'rubocop' },
      sh = { 'shfmt' },
      yaml = { 'yamlfmt' },
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
add({
  source = 'mfussenegger/nvim-lint',
})
later(function()
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
