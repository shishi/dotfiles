local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local not_in_vscode = vim.g.vscode == nil

local plugins = {
  {
    'aznhe21/actions-preview.nvim',
    cond = not_in_vscode,
    config = function()
      vim.keymap.set({ 'v', 'n' }, 'gf', require('actions-preview').code_actions)
    end,
  },
  {
    'utilyre/barbecue.nvim',
    enabled = false,
    cond = not_in_vscode,
    name = 'barbecue',
    version = '*',
    dependencies = {
      { 'SmiteshP/nvim-navic' },
      { 'nvim-tree/nvim-web-devicons' }, -- optional dependency
    },
    opts = {
      -- configurations go here
    },
  },
  {
    'akinsho/bufferline.nvim',
    version = '*',
    enabled = false,
    cond = not_in_vscode,
    dependencies = { { 'nvim-tree/nvim-web-devicons' }, { 'nvim-lua/plenary.nvim' } },
    config = function()
      vim.opt.termguicolors = true
      require('bufferline').setup({
        options = {
          mode = 'buffers',
          close_command = 'bp|bd #', -- can be a string | function, see "Mouse actions"
          right_mouse_command = 'bp|bd #', -- can be a string | function, see "Mouse actions"
          left_mouse_command = 'buffer %d', -- can be a string | function, see "Mouse actions"
          middle_mouse_command = 'bp|bd #', -- can be a string | function, see "Mouse actions"
          show_tab_indicators = true,
          indicator = {
            style = 'underline',
            -- icon = '📝',
          },
          name_formatter = function(buf)
            local Path = require('plenary.path')
            local filename = Path:new(buf.path):make_relative(vim.fn.getcwd())
            -- local filepath = vim.fn.system({ 'realpath', '--relative-base', vim.fn.getcwd(), buf.path })
            -- local filepath_trim = vim.fn.trim(filepath)
            return filename
          end,
          max_name_length = 30,
          diagnostics = 'nvim_lsp',
          diagnostics_indicator = function(count, level, _diagnostics_dict, _context)
            local icon = level:match('error') and '' or ''
            return ' ' .. icon .. count
          end,
        },
        -- highlights = {
        --   buffer_selected = {
        --     -- fg = 'red',
        --     -- bg = 'red',
        --     bold = true,
        --     -- italic = true,
        --     special = '#FF0000',
        --     sp = '#FF0000',
        --   },
        --   indicator_selected = {
        --     -- fg = 'red',
        --     -- bg = 'red',
        --     bold = true,
        --     special = '#FF0000',
        --     sp = '#FF0000',
        --   },
        -- },
      })
    end,
  },
  {
    'f3fora/cmp-spell',
    cond = not_in_vscode,
    enabled = false,
    dependencies = { { 'hrsh7th/nvim-cmp' } },
    config = function()
      vim.opt.spell = true
      vim.opt.spelllang = { 'en_us', 'cjk' }
    end,
  },
  {
    'zbirenbaum/copilot-cmp',
    dependencies = { 'zbirenbaum/copilot.lua' },
    cond = not_in_vscode,
    event = { 'VimEnter' },
    config = function()
      require('copilot-cmp').setup({})
    end,
  },
  {
    'zbirenbaum/copilot.lua',
    cond = not_in_vscode,
    cmd = 'Copilot',
    event = 'InsertEnter',
    config = function()
      require('copilot').setup({
        suggestion = {
          enabled = true,
          auto_trigger = true,
          keymap = {
            accept = '<M-l>',
            accept_word = false,
            accept_line = false,
            next = '<M-]>',
            prev = '<M-[>',
            dismiss = '<C-M-]>',
          },
        },
        panel = {
          enabled = false,
        },
      })
    end,
  },
  {
    'github/copilot.vim',
    cond = not_in_vscode,
    enabled = false,
  },
  {
    'zbirenbaum/copilot-cmp',
    cond = not_in_vscode,
    dependencies = { { 'copilot.lua' }, { 'hrsh7th/nvim-cmp' } },
    config = function()
      require('copilot_cmp').setup({})
    end,
  },
  {
    'saecki/crates.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' }, { 'hrsh7th/nvim-cmp' } },
    event = 'BufRead Cargo.toml',
    config = function()
      require('crates').setup()
    end,
  },
  {
    'sindrets/diffview.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' } },
  },
  {
    'stevearc/dressing.nvim',
    cond = not_in_vscode,
    opts = {},
    config = function()
      require('dressing').setup({})
    end,
  },
  {
    'creativenull/efmls-configs-nvim',
    -- version = 'v1.x.x', -- version is optional, but recommended
    dependencies = { 'neovim/nvim-lspconfig' },
    enabled = false,
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    --- @type Flash.Config
    opts = {
      jump = {
        autojump = true,
      },
      modes = {
        search = {
          enabled = true,
        },
      },
    },
    keys = {
      {
        's',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').jump()
        end,
        desc = 'Flash',
      },
      {
        'S',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').treesitter()
        end,
        desc = 'Flash Treesitter',
      },
      {
        'r',
        mode = 'o',
        function()
          require('flash').remote()
        end,
        desc = 'Remote Flash',
      },
      {
        'R',
        mode = { 'o', 'x' },
        function()
          require('flash').treesitter_search()
        end,
        desc = 'Treesitter Search',
      },
      {
        '<M-s>',
        mode = { 'c' },
        function()
          require('flash').toggle()
        end,
        desc = 'Toggle Flash Search',
      },
    },
  },
  {
    'rafamadriz/friendly-snippets',
    cond = not_in_vscode,
  },
  {
    'lewis6991/gitsigns.nvim',
    cond = not_in_vscode,
    config = function()
      require('gitsigns').setup({
        on_attach = function(bufnr)
          local function map(mode, lhs, rhs, opts)
            opts = vim.tbl_extend('force', {
              noremap = true,
              silent = true,
            }, opts or {})
            vim.api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
          end

          -- Navigation
          map('n', ']g', "&diff ? ']g' : '<cmd>Gitsigns next_hunk<CR>'", {
            expr = true,
          })
          map('n', '[g', "&diff ? '[g' : '<cmd>Gitsigns prev_hunk<CR>'", {
            expr = true,
          })

          -- Actions
          map('n', '<leader>hs', ':Gitsigns stage_hunk<CR>')
          map('v', '<leader>hs', ':Gitsigns stage_hunk<CR>')
          map('n', '<leader>hr', ':Gitsigns reset_hunk<CR>')
          map('v', '<leader>hr', ':Gitsigns reset_hunk<CR>')
          map('n', '<leader>hS', '<Cmd>Gitsigns stage_buffer<CR>')
          map('n', '<leader>hu', '<Cmd>Gitsigns undo_stage_hunk<CR>')
          map('n', '<leader>hR', '<Cmd>Gitsigns reset_buffer<CR>')
          map('n', '<leader>hp', '<Cmd>Gitsigns preview_hunk<CR>')
          map('n', '<leader>hf', '<Cmd>lua require"gitsigns".blame_line{full=true}<CR>', {
            desc = 'Gitsigns blame_line full=true',
          })
          map('n', '<leader>hb', '<Cmd>Gitsigns toggle_current_line_blame<CR>')
          map('n', '<leader>hd', '<Cmd>Gitsigns diffthis<CR>')
          map('n', '<leader>hD', '<Cmd>lua require"gitsigns".diffthis("~")<CR>', {
            desc = 'Gitsigns diffthis(~)',
          })
          map('n', '<leader>ht', '<Cmd>Gitsigns toggle_deleted<CR>')
          map('n', '<leader>hl', '<Cmd>Gitsitngs setloclist<CR>')

          -- Text object
          map('o', 'ih', ':<C-U>Gitsigns select_hunk<CR>')
          map('x', 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end,
      })
    end,
  },
  {
    'dnlhc/glance.nvim',
    cond = not_in_vscode,
    config = function()
      require('glance').setup({})
      -- vim.keymap.set('n', 'gd', '<CMD>Glance definitions<CR>')
      -- vim.keymap.set('n', 'gr', '<CMD>Glance references<CR>')
      -- vim.keymap.set('n', '<Leader>gt', '<CMD>Glance type_definitions<CR>')
      -- vim.keymap.set('n', 'gI', '<CMD>Glance implementations<CR>')
    end,
  },
  {
    'sainnhe/gruvbox-material',
    -- cond = not_in_vscode,
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
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
    end,
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    cond = not_in_vscode,
    config = function()
      require('ibl').setup({})
      -- local highlight = {
      --   'RainbowRed',
      --   'RainbowYellow',
      --   'RainbowBlue',
      --   'RainbowOrange',
      --   'RainbowGreen',
      --   'RainbowViolet',
      --   'RainbowCyan',
      -- }
      -- local hooks = require('ibl.hooks')
      -- -- create the highlight groups in the highlight setup hook, so they are reset
      -- -- every time the colorscheme changes
      -- hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      --   vim.api.nvim_set_hl(0, 'RainbowRed', { fg = '#E06C75' })
      --   vim.api.nvim_set_hl(0, 'RainbowYellow', { fg = '#E5C07B' })
      --   vim.api.nvim_set_hl(0, 'RainbowBlue', { fg = '#61AFEF' })
      --   vim.api.nvim_set_hl(0, 'RainbowOrange', { fg = '#D19A66' })
      --   vim.api.nvim_set_hl(0, 'RainbowGreen', { fg = '#98C379' })
      --   vim.api.nvim_set_hl(0, 'RainbowViolet', { fg = '#C678DD' })
      --   vim.api.nvim_set_hl(0, 'RainbowCyan', { fg = '#56B6C2' })
      -- end)
      --
      -- require('ibl').setup({ scope = { highlight = highlight } })
      --
      -- hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
    end,
  },
  {
    'lukas-reineke/lsp-format.nvim',
    cond = not_in_vscode,
    config = function()
      require('lsp-format').setup({
        -- go = {
        --   sync = true,
        --   order = { 'null-ls' },
        -- },
        javascript = {
          sync = true,
          exclude = { 'eslint' },
          order = { 'null-ls' },
        },
        javascriptreact = {
          sync = true,
          exclude = { 'eslint' },
          order = { 'null-ls' },
        },
        lua = {
          sync = true,
          exclude = { 'lua-ls' },
          order = { 'null-ls' },
        },
        -- ruby = {
        --   order = { 'null-ls' },
        -- },
        typescript = {
          sync = true,
          exclude = { 'eslint' },
          order = { 'null-ls' },
        },
        typescriptreact = {
          sync = true,
          exclude = { 'eslint' },
          order = { 'null-ls' },
        },
      })
    end,
  },
  {
    'ray-x/lsp_signature.nvim',
    enabled = false,
    event = 'VeryLazy',
    opts = {},
    config = function(_, opts)
      require('lsp_signature').setup(opts)
    end,
  },
  {
    'nvim-lualine/lualine.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-tree/nvim-web-devicons', 'SmiteshP/nvim-navic' } },
    config = function()
      -- local navic = require('nvim-navic')
      require('lualine').setup({
        options = {
          icons_enabled = true,
          theme = 'gruvbox-material',
          component_separators = {
            left = '',
            right = '',
          },
          section_separators = {
            left = '',
            right = '',
          },
          disabled_filetypes = {
            statusline = {},
            winbar = {},
          },
          ignore_focus = {},
          always_divide_middle = true,
          globalstatus = true,
          -- refresh = {
          --   statusline = 1000,
          --   tabline = 1000,
          --   winbar = 1000,
          -- },
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'branch', 'diff', 'diagnostics' },
          lualine_c = { {
            'filename',
            path = 1,
          } },
          lualine_x = { 'encoding', 'fileformat', 'filetype' },
          lualine_y = { 'progress' },
          lualine_z = { 'location' },
        },
        inactive_sections = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = { {
            'filename',
            path = 1,
          } },
          lualine_x = { 'location' },
          lualine_y = {},
          lualine_z = {},
        },
        tabline = {},
        winbar = {
          lualine_a = {},
          lualine_b = {},
          lualine_c = {
            -- {
            --   "navic",
            --   color_correction = nil,
            --   navic_opts = nil
            -- }
          },
          lualine_x = {},
          lualine_y = {},
          lualine_z = {},
        },
        -- inactive_winbar = {
        --     lualine_a = {},
        --     lualine_b = { {
        --         'filename',
        --         path = 1,
        --     } },
        --     lualine_c = {
        --         {
        --             function()
        --               return navic.get_location()
        --             end,
        --             cond = function()
        --               return navic.is_available()
        --             end,
        --         },
        --     },
        --     lualine_x = {},
        --     lualine_y = {},
        --     lualine_z = {},
        -- },
        extensions = { 'nvim-dap-ui', 'nvim-tree', 'quickfix', 'toggleterm' },
      })
    end,
  },
  {
    'L3MON4D3/LuaSnip',
    version = 'v1.*',
    cond = not_in_vscode,
    dependencies = { { 'rafamadriz/friendly-snippets' } },
    config = function()
      require('luasnip').config.setup({
        history = true,
      })
      require('luasnip.loaders.from_vscode').lazy_load()
      require('luasnip.loaders.from_vscode').lazy_load('./snippets')

      require('luasnip').filetype_extend('ruby', { 'rails' })
      require('luasnip').filetype_extend('javascriptreact', { 'html' })
      require('luasnip').filetype_extend('typescriptreact', { 'html' })

      -- vim.keymap.set('i', '<Tab>', function()
      --   require('luasnip').expand_or_jump()
      -- end, {
      -- })
      --
      -- vim.keymap.set('i', '<S-Tab>', function()
      --   require('luasnip').jump(-1)
      -- end, {
      -- })
      --
      -- vim.keymap.set('s', '<Tab>', function()
      --   require('luasnip').jump(1)
      -- end, {
      -- })
      --
      -- vim.keymap.set('s', '<S-Tab>', function()
      --   require('luasnip').jump(-1)
      -- end, {
      -- })
    end,
  },
  {
    'williamboman/mason-lspconfig.nvim',
    cond = not_in_vscode,
    dependencies = { { 'williamboman/mason.nvim' } },
    config = function()
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
          -- rubocop
        },
        automatic_installation = true,
      })
    end,
  },
  {
    'williamboman/mason.nvim',
    cond = not_in_vscode,
    config = function()
      require('mason').setup()
      -- nvim --headless -c "MasonInstall actionlint buf eslint-lsp sqlfluff stylelint yamllint shfmt goimports" -c qall
    end,
  },
  {
    'echasnovski/mini.nvim',
    version = false,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' }, { 'JoosepAlviste/nvim-ts-context-commentstring' } },
    config = function()
      require('mini.cursorword').setup({})

      require('mini.comment').setup({
        options = {
          custom_commentstring = function()
            return require('ts_context_commentstring.internal').calculate_commentstring() or vim.bo.commentstring
          end,
        },
      })

      local hipatterns = require('mini.hipatterns')
      hipatterns.setup({
        highlighters = {
          -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
          fixme = {
            pattern = '%f[%w]()FIXME()%f[%W]',
            group = 'MiniHipatternsFixme',
          },
          hack = {
            pattern = '%f[%w]()HACK()%f[%W]',
            group = 'MiniHipatternsHack',
          },
          todo = {
            pattern = '%f[%w]()TODO()%f[%W]',
            group = 'MiniHipatternsTodo',
          },
          note = {
            pattern = '%f[%w]()NOTE()%f[%W]',
            group = 'MiniHipatternsNote',
          },
          -- Highlight hex color strings (`#rrggbb`) using that color
          hex_color = hipatterns.gen_highlighter.hex_color(),
        },
      })

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
      })
    end,
  },
  {
    'nvim-neo-tree/neo-tree.nvim',
    branch = 'v3.x',
    dependencies = { 'nvim-lua/plenary.nvim', 'nvim-tree/nvim-web-devicons', 'MunifTanjim/nui.nvim' },
    cond = not_in_vscode,
    cmd = 'Neotree',
    deactivate = function()
      vim.cmd([[Neotree close]])
    end,
    init = function()
      vim.g.neo_tree_remove_legacy_commands = 1
      if vim.fn.argc() == 1 then
        local stat = vim.loop.fs_stat(vim.fn.argv(0))
        if stat and stat.type == 'directory' then
          require('neo-tree')
        end
      end
    end,
    keys = {
      {
        '<Leader>fc',
        function()
          vim.cmd([[Neotree close]])
        end,
        desc = 'NeoTree close',
        remap = true,
      },
      {
        '<Leader>fe',
        function()
          vim.cmd([[Neotree filesystem]])
        end,
        desc = 'NeoTree filesystem',
        remap = true,
      },
      {
        '<Leader>fb',
        function()
          vim.cmd([[Neotree buffers]])
        end,
        desc = 'NeoTree buffers',
        remap = true,
      },
      {
        '<Leader>fg',
        function()
          vim.cmd([[Neotree git_status]])
        end,
        desc = 'NeoTree gitS',
        remap = true,
      },
    },
    config = function()
      require('neo-tree').setup({
        source_selector = {
          winbar = true,
          statusline = false,
        },
        filesystem = {
          bind_to_cwd = false,
          follow_current_file = {
            enabled = true,
            leave_dirs_open = true,
          },
          filtered_items = {
            visible = true,
            -- hide_dotfiles = false,
            -- hide_gitignored = false,
            -- hide_hidden = false,
          },
        },
        buffers = {},
        git_status = {},
        -- window = {
        --   mappings = {
        --     ['<space>'] = 'none',
        --   },
        -- },
      })
    end,
  },
  {
    'NeogitOrg/neogit',
    dependencies = {
      { 'nvim-lua/plenary.nvim' },
      { 'nvim-telescope/telescope.nvim' },
      { 'sindrets/diffview.nvim' }, -- {'ibhagwan/fzf-lua'},
    },
    config = true,
    keys = { {
      '<M-g>',
      '<cmd>Neogit<cr>',
      desc = 'neogit',
      mode = 'n',
    } },
  },
  {
    'folke/noice.nvim',
    cond = not_in_vscode,
    dependencies = { { 'MunifTanjim/nui.nvim' }, { 'rcarriga/nvim-notify' } },
    event = 'VeryLazy',
    opts = {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      presets = {
        bottom_search = false,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = false, -- add a border to hover docs and signature help
      },
    },
  },
  {
    'hrsh7th/nvim-cmp',
    cond = not_in_vscode,
    dependencies = {
      { 'hrsh7th/cmp-buffer' },
      { 'hrsh7th/cmp-path' },
      { 'hrsh7th/cmp-cmdline' },
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'hrsh7th/cmp-nvim-lua' },
      { 'hrsh7th/cmp-nvim-lsp-signature-help' },
      { 'neovim/nvim-lspconfig' },
      { 'nvim-telescope/telescope.nvim' },
      { 'onsails/lspkind-nvim' },
      { 'saadparwaiz1/cmp_luasnip' },
      { 'williamboman/mason-lspconfig.nvim' },
    },
    event = 'InsertEnter',
    config = function()
      local cmp = require('cmp')
      local lspkind = require('lspkind')

      -- for integrate luasnip
      local has_words_before = function()
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match('%s') == nil
      end

      local function tab(fallback)
        local luasnip = require('luasnip')
        if cmp.visible() then
          cmp.select_next_item()
          -- fn.feedkeys(t('<C-n>'), 'n')
        elseif luasnip.expand_or_locally_jumpable() then
          require('luasnip').expand_or_jump()
        elseif has_words_before() then
          cmp.complete()
        else
          fallback()
        end
      end

      local function shift_tab(fallback)
        local luasnip = require('luasnip')
        if cmp.visible() then
          cmp.select_prev_item()
          -- fn.feedkeys(t('<C-p>'), 'n')
        elseif luasnip.locally_jumpable(-1) then
          require('luasnip').jump_prev()
        else
          fallback()
        end
      end

      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        window = {
          -- completion = cmp.config.window.bordered(),
          -- documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<Tab>'] = cmp.mapping(tab),
          ['<S-Tab>'] = cmp.mapping(shift_tab),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<Esc>'] = cmp.mapping.abort(),
          ['<CR>'] = function(fallback)
            if cmp.visible() then
              cmp.confirm({
                select = true, -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
              })
            else
              fallback() -- If you use vim-endwise, this fallback will behave the same as vim-endwise.
            end
          end,
        }),
        -- LuaFormatter off
        -- stylua: ignore start
        sources = cmp.config.sources({
          { name = 'copilot' },
          -- { name = 'cmp_tabnine' },
          { name = 'crates' },
          { name = 'luasnip' },
          { name = 'nvim_lsp_signature_help' },
          { name = 'nvim_lsp' },
          -- { name = 'spell' },
          {
            { name = 'buffer' },
          },
        }),
        -- stylua: ignore end
        -- LuaFormatter on
        formatting = {
          format = lspkind.cmp_format({
            mode = 'symbol_text',
            max_width = 50,
            symbol_map = {
              Copilot = '',
            },
          }),
          -- format = function(entry, vim_item)
          --   -- if you have lspkind installed, you can use it like
          --   -- in the following line:
          --   vim_item.kind = lspkind.symbolic(vim_item.kind, { mode = 'symbol' })
          --   vim_item.menu = source_mapping[entry.source.name]
          --   if entry.source.name == 'cmp_tabnine' then
          --     local detail = (entry.completion_item.data or {}).detail
          --     vim_item.kind = ''
          --     if detail and detail:find('.*%%.*') then
          --       vim_item.kind = vim_item.kind .. ' ' .. detail
          --     end
          --
          --     if (entry.completion_item.data or {}).multiline then
          --       vim_item.kind = vim_item.kind .. ' ' .. '[ML]'
          --     end
          --   end
          --   local maxwidth = 80
          --   vim_item.abbr = string.sub(vim_item.abbr, 1, maxwidth)
          --   return vim_item
          -- end,
        },
      })

      -- Set configuration for specific filetype.
      cmp.setup.filetype('gitcommit', {
        -- LuaFormatter off
        -- stylua: ignore start
        sources = cmp.config.sources({
          { name = 'cmp_git' },
          { name = 'buffer' },
        }),
        -- stylua: ignore end
        -- LuaFormatter on
      })

      -- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline('/', {
        mapping = cmp.mapping.preset.cmdline(),
        -- LuaFormatter off
        -- stylua: ignore start
        sources = {
          { name = 'buffer' },
        },
        -- stylua: ignore end
        -- LuaFormatter on
      })

      -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline(),
        -- LuaFormatter off
        -- stylua: ignore start
        sources = cmp.config.sources({
          { name = 'cmdline' },
          { name = 'path' },
        }),
        -- stylua: ignore end
        -- LuaFormatter on
      })
    end,
  },
  {
    'mfussenegger/nvim-dap',
    cond = not_in_vscode,
    lazy = true,
    config = function()
      vim.keymap.set('n', '<F5>', function()
        require('dap').continue()
      end, {
        desc = 'nvim-dap continue',
      })
      vim.keymap.set('n', '<F9>', function()
        require('dap').terminate()
      end, {
        desc = 'nvim-dap terminate',
      })
      vim.keymap.set('n', '<F10>', function()
        require('dap').step_over()
      end, {
        desc = 'nvim-dap step_over()',
      })
      vim.keymap.set('n', '<F11>', function()
        require('dap').step_into()
      end, {
        desc = 'nvim-dap step_into()',
      })
      vim.keymap.set('n', '<F12>', function()
        require('dap').step_out()
      end, {
        desc = 'nvim-dap step_out()',
      })
      vim.keymap.set('n', '<Leader>db', function()
        require('dap').toggle_breakpoint()
      end, {
        desc = 'nvim-dap toggle_breakpoint',
      })
      vim.keymap.set('n', '<Leader>dbc', function()
        require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))
      end, {
        desc = 'nvim-dap set_breakpoint with condition',
      })
      vim.keymap.set('n', '<Leader>dbm', function()
        require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
      end, {
        desc = 'nvim-dap set_breakpoint with log point message',
      })
      vim.keymap.set('n', '<Leader>do', function()
        require('dap').repl_open()
      end, {
        desc = 'nvim-dap repl_open()',
      })
      vim.keymap.set('n', '<Leader>dr', function()
        require('dap').run_last()
      end, {
        desc = 'nvim-dap run_last()',
      })
    end,
  },
  {
    'rcarriga/nvim-dap-ui',
    cond = not_in_vscode,
    dependencies = { 'mfussenegger/nvim-dap', 'nvim-neotest/nvim-nio' },
    lazy = true,
    config = function()
      require('dapui').setup({})
      local dap, dapui = require('dap'), require('dapui')
      dap.listeners.after.event_initialized['dapui_config'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_config'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_config'] = function()
        dapui.close()
      end
    end,
  },
  {
    'theHamsta/nvim-dap-virtual-text',
    cond = not_in_vscode,
    dependencies = { 'mfussenegger/nvim-dap' },
    lazy = true,
    config = function()
      require('nvim-dap-virtual-text').setup({})
    end,
  },
  {
    'mxsdev/nvim-dap-vscode-js',
    cond = not_in_vscode,
    dependencies = { { 'mfussenegger/nvim-dap' } },
    config = function()
      require('dap-vscode-js').setup({
        -- node_path = "node", -- Path of node executable. Defaults to $NODE_PATH, and then "node"
        -- debugger_path = "(runtimedir)/site/pack/packer/opt/vscode-js-debug", -- Path to vscode-js-debug installation.
        -- debugger_cmd = { "js-debug-adapter" }, -- Command to use to launch the debug server. Takes precedence over `node_path` and `debugger_path`.
        adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' }, -- which adapters to register in nvim-dap
      })
      for _, language in ipairs({ 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }) do
        require('dap').configurations[language] = { -- https://github.com/mxsdev/nvim-dap-vscode-js
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Launch',
            program = '${file}',
            -- program = 'npm run dev',
            cwd = '${workspaceFolder}',
          },
          {
            type = 'pwa-node',
            request = 'attach',
            name = 'Attach',
            processId = require('dap.utils').pick_process,
            cwd = '${workspaceFolder}',
          }, -- https://nextjs.org/docs/advanced-features/debugging
          {
            name = 'Next.js: debug client-side',
            type = 'pwa-chrome',
            request = 'launch',
            url = 'http://localhost:3000',
          },
          {
            type = 'pwa-node',
            request = 'launch',
            name = 'Debug Jest Tests',
            -- trace = true, -- include debugger info
            runtimeExecutable = 'node',
            runtimeArgs = {
              './node_modules/jest/bin/jest.js',
              '--runInBand',
            },
            rootPath = '${workspaceFolder}',
            cwd = '${workspaceFolder}',
            console = 'integratedTerminal',
            internalConsoleOptions = 'neverOpen',
          },
        }
      end
    end,
  },
  {
    'esensar/nvim-dev-container',
    url = 'https://codeberg.org/esensar/nvim-dev-container',
    enabled = false,
    cond = not_in_vscode,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' } },
  },
  {
    'hrsh7th/nvim-insx',
    config = function()
      require('insx.preset.standard').setup()
    end,
  },
  {
    'hrsh7th/nvim-linkedit',
    config = function()
      require('linkedit').setup({
        sources = {
          {
            name = 'lsp_linked_editing_range',
          },
          {
            name = 'lsp_document_highlight',
            on = { 'operator' },
          },
        },
      })
    end,
  },
  {
    'neovim/nvim-lspconfig',
    cond = not_in_vscode,
    dependencies = { { 'williamboman/mason-lspconfig.nvim', 'SmiteshP/nvim-navic', 'lukas-reineke/lsp-format.nvim' } },
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      -- lsp diagnostics setting
      vim.diagnostic.config({
        virtual_text = true,
        signs = {
          text = {
            [vim.diagnostic.severity.HINT] = '⍟',
            [vim.diagnostic.severity.ERROR] = '⊗',
            [vim.diagnostic.severity.INFO] = 'ⓘ',
            [vim.diagnostic.severity.WARN] = '⊘',
          },
        },
        underline = true,
        update_in_insert = true,
        severity_sort = true,
      })

      -- lsp diagnostics symbols
      -- local signs = {
      --   Error = '',
      --   Warn = '',
      --   Hint = '',
      --   Info = '',
      -- }
      --
      -- for type, icon in pairs(signs) do
      --   local hl = 'DiagnosticSign' .. type
      --   vim.fn.sign_define(hl, {
      --     icon = icon,
      --     text = icon,
      --     texthl = hl,
      --     numhl = hl,
      --   })
      -- end

      -- Set up lspconfig.
      local augroup_lsp_keybind = vim.api.nvim_create_augroup('augroup_lsp_keybind', {})
      vim.api.nvim_create_autocmd({ 'LspAttach' }, {
        group = augroup_lsp_keybind,
        pattern = { '*' },
        callback = function(args)
          local bufnr = args.buf
          -- local client = vim.lsp.get_client_by_id(args.data.client_id)
          -- vim.api.nvim_set_option_value(0, 'omnifunc', 'v:lua.vim.lsp.omnifunc')plug

          -- code definitions, references
          vim.keymap.set('n', 'gd', function()
            require('telescope.builtin').lsp_definitions()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp.buf.definition',
          })
          vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, {
            buffer = bufnr,
            desc = 'vim.lsp declaration',
          })
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
            buffer = bufnr,
            desc = 'vim.lsp hover',
          })
          vim.keymap.set('n', 'gI', function()
            require('telescope.builtin').lsp_implementations()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp.buf.implementation',
          })
          vim.keymap.set('n', 'gk', vim.lsp.buf.signature_help, {
            buffer = bufnr,
            desc = 'vim.lsp signature_help',
          })
          vim.keymap.set('n', 'gr', function()
            require('telescope.builtin').lsp_references()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp.buf.references',
          })
          vim.keymap.set('n', '<Leader>gt', function()
            require('telescope.builtin').lsp_type_definitions()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp.buf.type_definition',
          })

          -- workspace
          vim.keymap.set('n', '<Leader><Leader>wa', vim.lsp.buf.add_workspace_folder, {
            buffer = bufnr,
            desc = 'vim.lsp add_workspace_folder',
          })
          vim.keymap.set('n', '<Leader><Leader>wr', vim.lsp.buf.remove_workspace_folder, {
            buffer = bufnr,
            desc = 'vim.lsp remove_workspace_folder',
          })
          vim.keymap.set('n', '<Leader><Leader>wl', function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, {
            buffer = bufnr,
            desc = 'vim.lsp list_workspace_folders',
          })

          -- code actions
          vim.keymap.set({ 'n', 'v' }, '<Leader>rn', vim.lsp.buf.rename, {
            buffer = bufnr,
            desc = 'vim.lsp rename',
          })
          vim.keymap.set({ 'n', 'v' }, '<F2>', vim.lsp.buf.rename, {
            buffer = bufnr,
            desc = 'vim.lsp rename',
          })
          vim.keymap.set({ 'n', 'v' }, '<Leader>ca', vim.lsp.buf.code_action, {
            buffer = bufnr,
            desc = 'vim.lsp code_action',
          })
          vim.keymap.set({ 'n', 'v' }, '<F7>', vim.lsp.buf.code_action, {
            buffer = bufnr,
            desc = 'vim.lsp code_action',
          })

          -- format
          vim.keymap.set(
            'n',
            '<F8>', -- 0.7
            -- vim.lsp.buf.formatting,
            -- 0.8
            vim.lsp.buf.format,
            {
              buffer = bufnr,
              desc = 'vim.lsp format',
            }
          )

          -- symbols through by treesitter
          vim.keymap.set('n', 'gs', function()
            require('telescope.builtin').lsp_dynamic_workspace_symbols()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp lsp_dynamic_workspace_symbols',
          })
          vim.keymap.set('n', 'gS', function()
            require('telescope.builtin').lsp_document_symbols()
          end, {
            buffer = bufnr,
            desc = 'vim.lsp lsp_document_symbols',
          })

          -- diagnostic
          vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float, {
            buffer = bufnr,
            desc = 'diagnostic open_float',
          })
          vim.keymap.set('n', '[e', vim.diagnostic.goto_prev, {
            buffer = bufnr,
            desc = 'diagnostic goto_prev',
          })
          vim.keymap.set('n', ']e', vim.diagnostic.goto_next, {
            buffer = bufnr,
            desc = 'diagnostic goto_next',
          })
          vim.keymap.set('n', '<Leader>E', function()
            require('telescope.builtin').diagnostics()
          end, {
            buffer = bufnr,
            desc = 'telescope diagnostics',
          })
          -- vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, { desc = 'diagnose set_loclist'})
        end,
      })

      -- add to your shared on_attach callback
      local on_attach = function(client, bufnr)
        require('lsp-format').on_attach(client, bufnr)
        -- if client.server_capabilities.documentSymbolProvider then
        --   require('nvim-navic').attach(client, bufnr)
        -- end
      end

      local lspconfig = require('lspconfig')
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      require('mason-lspconfig').setup_handlers({
        --
        -- The first entry (without a key) will be the default handler
        -- and will be called for each installed server that doesn't have
        -- a dedicated handler.
        function(server_name) -- default handler (optional)
          lspconfig[server_name].setup({
            capabilitiies = capabilities,
            on_attach = on_attach,
          })
        end, --
        -- Next, you can provide targeted overrides for specific servers.
        -- ['rust_analyzer'] = function()
        --   require('rust-tools').setup {}
        -- end
        -- ['efm'] = function()
        --   local actionlint = require('efmls-configs.linters.actionlint')
        --   local beautysh = require('efmls-configs.formatters.beautysh')
        --   local buf_f = require('efmls-configs.formatters.buf')
        --   local buf_l = require('efmls-configs.linters.buf')
        --   local eslint = require('efmls-configs.linters.eslint')
        --   local goimports = require('efmls-configs.formatters.goimports')
        --   local prettier = require('efmls-configs.formatters.prettier')
        --   -- local selene = require('efmls-configs.linters.selene')
        --   local sqlfluff = {
        --     prefix = 'sqlfluff',
        --     lintCommand =
        --     'sqlfluff lint --dialect ansi --format github-annotation-native --annotation-level warning --nocolor --disable-progress-bar ${INPUT}',
        --     lintIgnoreExitCode = true,
        --     lintStdin = false,
        --     lintFormats = {
        --       '::%totice title=SQLFluff,file=%f,line=%l,col=%c::%m',
        --       '::%tarning title=SQLFluff,file=%f,line=%l,col=%c::%m',
        --       '::%trror title=SQLFluff,file=%f,line=%l,col=%c::%m',
        --     },
        --   }
        --   local sql_formatter = require('efmls-configs.formatters.sql-formatter')
        --   local stylelint = require('efmls-configs.linters.stylelint')
        --   local stylua = require('efmls-configs.formatters.stylua')
        --   local taplo = require('efmls-configs.formatters.taplo')
        --
        --   -- native efm way
        --   -- languages = {
        --   --   lua = {
        --   --     { formatCommand = 'lua-format -i', formatStdin = true },
        --   --     { lintCommand = 'luacheck', lintFormats = { '%f:%l:%c: %m' } },
        --   --   },
        --   -- }
        --
        --   local languages = {
        --     css = { stylelint, prettier },
        --     go = { goimports },
        --     html = { prettier },
        --     javascript = { eslint, prettier },
        --     javascriptreact = { eslint, prettier },
        --     json = { prettier },
        --     jsonc = { prettier },
        --     lua = { stylua },
        --     markdown = { prettier },
        --     proto = { buf_l, buf_f },
        --     -- ruby = { rufo },
        --     scss = { stylelint, prettier },
        --     sh = { beautysh },
        --     sql = { sqlfluff, sql_formatter },
        --     toml = { taplo },
        --     typescript = { eslint, prettier },
        --     typescriptreact = { eslint, prettier },
        --     yml = { actionlint, prettier },
        --   }
        --   local efmls_config = {
        --     filetypes = vim.tbl_keys(languages),
        --     init_options = {
        --       documentFormatting = true,
        --       documentRangeFormatting = true,
        --     },
        --     settings = {
        --       rootMarkers = { '.git/' },
        --       languages = languages,
        --     },
        --   }
        --   lspconfig.efm.setup(vim.tbl_extend('force', efmls_config, {
        --     -- Pass your custom lsp config below like on_attach and capabilities
        --     --
        --     -- on_attach = on_attach,
        --     -- capabilities = capabilities,
        --   }))
        -- end,
        ['lua_ls'] = function()
          lspconfig.lua_ls.setup({
            capabilitiies = capabilities,
            on_attach = on_attach,
            settings = {
              Lua = {
                diagnostics = {
                  globals = { 'vim' },
                },
                runtime = {
                  version = 'LuaJIT',
                  path = vim.split(package.path, ';'),
                },
                workspace = {
                  library = {
                    [vim.fn.expand('$VIMRUNTIME/lua')] = true,
                    [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true,
                  },
                },
                hint = {
                  enable = true,
                },
              },
            },
          })
        end,
        ['vtsls'] = function()
          lspconfig.vtsls.setup({
            filetypes = {
              'typescript',
              'javascript',
              'javascriptreact',
              'typescriptreact',
              'javascript.jsx',
              'typescript.tsx',
              'vue',
            },
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
              hint = {
                enable = true,
              },
              -- -- -- https://github.com/yioneko/vtsls/issues/148#issuecomment-2119744901
              -- -- -- https://github.com/williamboman/mason-lspconfig.nvim/issues/371#issuecomment-2188015156
              vtsls = {
                tsserver = {
                  globalPlugins = {
                    {
                      name = '@vue/typescript-plugin',
                      location = require('mason-registry').get_package('vue-language-server'):get_install_path()
                        .. '/node_modules/@vue/language-server',
                      languages = { 'vue' },
                      -- configNamespace = 'typescript',
                      -- enableForWorkspaceTypeScriptVersions = true,
                    },
                  },
                },
              },
              typescript = {
                preferences = {
                  importModuleSpecifier = 'relative',
                },
                -- format = {
                --     enable = false,
                -- },
                -- suggest = {
                --     completeFunctionCalls = true,
                -- },
              },
              javascript = {
                preferences = {
                  importModuleSpecifier = 'relative',
                },
                -- format = {
                --     enable = false,
                -- },
                -- suggest = {
                --     completeFunctionCalls = true,
                -- },
              },
            },
          })
        end,
      })

      -- setting lsp which not under mason
      lspconfig.gopls.setup({
        capabilitiies = capabilities,
        on_attach = on_attach,
      })
      lspconfig.ruby_lsp.setup({
        capabilitiies = capabilities,
        on_attach = on_attach,
      })
    end,
  },
  {
    'SmiteshP/nvim-navic',
    enable = false,
    cond = not_in_vscode,
    dependencies = { 'neovim/nvim-lspconfig' },
    config = function()
      require('nvim-navic').setup({
        highlight = true,
      })
      -- vim.api.nvim_set_hl(0, 'NavicIconsFile', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsModule', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsNamespace', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsPackage', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsClass', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsMethod', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsProperty', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsField', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsConstructor', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsEnum', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsInterface', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsFunction', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsVariable', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsConstant', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsString', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsNumber', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsBoolean', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsArray', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsObject', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsKey', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsNull', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsEnumMember', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsStruct', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsEvent', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsOperator', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicIconsTypeParameter', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicText', { default = true, bg = '#000000', fg = '#ffffff' })
      -- vim.api.nvim_set_hl(0, 'NavicSeparator', { default = true, bg = '#000000', fg = '#ffffff' })
    end,
  },
  {
    'nvim-neotest/nvim-nio',
    cond = not_in_vscode,
  },
  {
    'rcarriga/nvim-notify',
    cond = not_in_vscode,
    config = function()
      require('notify').setup({
        background_colour = '#000000',
        timeout = 3000,
        max_height = function()
          return math.floor(vim.o.lines * 0.75)
        end,
        max_width = function()
          return math.floor(vim.o.columns * 0.75)
        end,
      })
    end,
    keys = {
      {
        '<leader>un',
        function()
          require('notify').dismiss({
            silent = true,
            pending = true,
          })
        end,
        desc = 'Delete all Notifications',
      },
    },
  },
  {
    'windwp/nvim-spectre',
    cond = not_in_vscode,
    keys = {
      {
        '<Plug>(spectre-open)',
        function()
          require('spectre').open()
        end,
        desc = 'Replace in files (Spectre)',
      },
    },
  },
  {
    'nvim-treesitter/nvim-treesitter',
    -- enabled = false,
    build = function()
      require('nvim-treesitter.install').update({
        with_sync = true,
      })
    end,
    config = function()
      require('nvim-treesitter.configs').setup({
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = true,
          disable = function()
            return not not_in_vscode
          end,
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<CR>',
            scope_incremental = '<TAB>',
            node_incremental = '<CR>',
            node_decremental = '<Leader><CR>',
          },
        },
        matchup = {
          enable = true,
        },
        endwise = {
          enable = true,
        },
      })
    end,
  },
  {
    'MunifTanjim/nui.nvim',
    lazy = true,
  },
  {
    'kevinhwang91/nvim-bqf',
    cond = not_in_vscode,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' } },
  },
  {
    'RRethy/nvim-treesitter-endwise',
    cond = not_in_vscode,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' } },
  },
  {
    'windwp/nvim-ts-autotag',
    cond = not_in_vscode,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' } },
    config = function()
      require('nvim-ts-autotag').setup({})
    end,
  },
  {
    'JoosepAlviste/nvim-ts-context-commentstring',
    config = function()
      require('ts_context_commentstring').setup({
        enable_autocmd = false,
      })
    end,
  },
  {
    'nvim-tree/nvim-web-devicons',
    cond = not_in_vscode,
  },
  {
    'nvimtools/none-ls.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' } },
    config = function()
      local lsp_formatting = function(bufnr)
        vim.lsp.buf.format({
          -- filter = function(client)
          -- see lsp-format in my config
          -- apply whatever logic you want (in this example, we'll only use null-ls)
          -- return client.name == "null-ls"
          -- end,
          bufnr = bufnr,
        })
      end
      local augroup = vim.api.nvim_create_augroup('LspFormatting', {})
      local null_ls = require('null-ls')

      null_ls.setup({
        -- LuaFormatter off
        -- stylua: ignore start
        sources = {
          -- code actions
          -- null_ls.builtins.code_actions.gitrebase,
          -- null_ls.builtins.code_actions.gitsigns,
          -- diagnostics
          null_ls.builtins.diagnostics.actionlint,
          null_ls.builtins.diagnostics.buf,
          null_ls.builtins.diagnostics.erb_lint,
          null_ls.builtins.diagnostics.fish,
          -- null_ls.builtins.diagnostics.haml_lint,
          null_ls.builtins.diagnostics.markdownlint,
          null_ls.builtins.diagnostics.markuplint,
          -- null_ls.builtins.diagnostics.mdl,
          null_ls.builtins.diagnostics.rubocop,
          null_ls.builtins.diagnostics.selene,
          null_ls.builtins.diagnostics.sqlfluff.with({
            extra_args = { '--dialect', 'postgres' },
          }),
          -- null_ls.builtins.diagnostics.tidy,
          null_ls.builtins.diagnostics.stylelint,
          null_ls.builtins.diagnostics.todo_comments,
          null_ls.builtins.diagnostics.trail_space,
          null_ls.builtins.diagnostics.yamllint,
          null_ls.builtins.diagnostics.zsh,
          -- formatting
          null_ls.builtins.formatting.buf,
          null_ls.builtins.formatting.erb_lint,
          null_ls.builtins.formatting.fish_indent,
          null_ls.builtins.formatting.gofmt,
          null_ls.builtins.formatting.goimports,
          null_ls.builtins.formatting.prettier,
          -- null_ls.builtins.formatting.prismaFmt,
          null_ls.builtins.formatting.rubocop,
          -- null_ls.builtins.formatting.sql_formatter,
          null_ls.builtins.formatting.sqlfluff.with({
            extra_args = { '--dialect', 'postgres' },
          }),
          null_ls.builtins.formatting.stylelint,
          null_ls.builtins.formatting.stylua,
          -- null_ls.builtins.formatting.tidy,
          -- hover
          null_ls.builtins.hover.printenv,
        },
        -- stylua: ignore end
        -- LuaFormatter on
        -- you can reuse a shared lspconfig on_attach callback here
        on_attach = function(client, bufnr)
          if client.supports_method('textDocument/formatting') then
            vim.api.nvim_clear_autocmds({
              group = augroup,
              buffer = bufnr,
            })
            vim.api.nvim_create_autocmd('BufWritePre', {
              group = augroup,
              buffer = bufnr,
              callback = function()
                lsp_formatting(bufnr)
              end,
            })
          end
        end,
      })
    end,
  },
  {
    'stevearc/oil.nvim',
    opts = {},
    -- Optional dependencies
    dependencies = { 'nvim-tree/nvim-web-devicons' },
  },
  {
    'folke/persistence.nvim',
    event = 'BufReadPre',
    opts = {
      options = { 'buffers', 'curdir', 'tabpages', 'winsize', 'help' },
    },
    keys = {
      {
        '<Leader>ps',
        function()
          require('persistence').load()
        end,
        desc = 'Restore Session',
      },
      {
        '<Leader>pl',
        function()
          require('persistence').load({
            last = true,
          })
        end,
        desc = 'Restore Last Session',
      },
      {
        '<Leader>pd',
        function()
          require('persistence').stop()
        end,
        desc = "Don't Save Current Session",
      },
    },
  },
  { 'nvim-lua/plenary.nvim' },
  {
    'ahmedkhalf/project.nvim',
    cond = not_in_vscode,
    config = function()
      require('project_nvim').setup({
        detection_methods = { 'pattern', 'lsp' },
        patterns = { '.git', '_darcs', '.hg', '.bzr', '.svn', 'Makefile', 'package.json' },
        exclude_dirs = { '~/', '/mnt/c/Users/shishi/scoop/*' },
        show_hidden = true,
        silent_chdir = false,
        scope_chdir = 'global',
      })

      require('telescope').load_extension('projects')

      vim.keymap.set('n', '<C-k>p', function()
        require('telescope').extensions.projects.projects()
      end, {
        desc = 'telescope projects',
      })
    end,
  },
  {
    'HiPhish/rainbow-delimiters.nvim',
    url = 'https://gitlab.com/HiPhish/rainbow-delimiters.nvim',
    enabled = false,
    cond = not_in_vscode,
    config = function()
      local rainbow_delimiters = require('rainbow-delimiters')

      vim.g.rainbow_delimiters = {
        strategy = {
          [''] = rainbow_delimiters.strategy['global'],
          vim = rainbow_delimiters.strategy['local'],
        },
        query = {
          [''] = 'rainbow-delimiters',
          lua = 'rainbow-blocks',
        },
        highlight = {
          'RainbowDelimiterRed',
          'RainbowDelimiterYellow',
          'RainbowDelimiterBlue',
          'RainbowDelimiterOrange',
          'RainbowDelimiterGreen',
          'RainbowDelimiterViolet',
          'RainbowDelimiterCyan',
        },
      }
    end,
  },
  {
    'simrat39/rust-tools.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' }, { 'neovim/nvim-lspconfig' }, { 'mfussenegger/nvim-dap' } },
    config = function()
      local rt = require('rust-tools')

      rt.setup({
        hover_with_actions = true,
        server = {
          on_attach = function(_, bufnr)
            -- Hover actions
            -- vim.keymap.set('n', '<C-space>', rt.hover_actions.hover_actions, { buffer = bufnr })
            -- Code action groups
            vim.keymap.set('n', '<Leader>a', rt.code_action_group.code_action_group, {
              buffer = bufnr,
            })
          end,
        },
      })
      -- rt.inlay_hints.enable()
    end,
  },
  {
    'nvim-telescope/telescope-file-browser.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('file_browser')

      vim.keymap.set('n', '<C-k>z', function()
        require('telescope').extensions.file_browser.file_browser()
      end, {
        desc = 'telescope file browser',
      })
    end,
  },
  {
    'nvim-telescope/telescope-fzf-native.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-telescope/telescope.nvim' } },
    build = 'make',
    config = function()
      require('telescope').load_extension('fzf')
    end,
  },
  {
    'nvim-telescope/telescope-ghq.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('ghq')

      vim.keymap.set('n', '<C-k>g', '<Cmd>Telescope ghq list<CR>', {
        desc = 'telescope ghq',
      })
    end,
  },
  {
    'nvim-telescope/telescope-live-grep-args.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('live_grep_args')
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    -- version = '0.1.0',
    branch = 'master',
    cond = not_in_vscode,
    dependencies = {
      { 'nvim-tree/nvim-web-devicons' },
      { 'nvim-lua/plenary.nvim' },
      { 'nvim-treesitter/nvim-treesitter' },
      { 'folke/trouble.nvim' },
    },
    config = function()
      local open_with_trouble = require('trouble.sources.telescope').open
      -- local add_to_trouble = require('trouble.sources.telescope').add
      local lga_actions = require('telescope-live-grep-args.actions')

      require('telescope').setup({
        defaults = {
          path_display = {
            'filename_first',
          },
          vimgrep_arguments = { 'rg', '--vimgrep', '--smart-case', '--hidden', '--glob', '!.git' },
          -- layout_strategy = 'vertical',
          -- layout_config = {
          --   prompt_position = 'top',
          -- },
          mappings = {
            i = {
              ['<c-t>'] = open_with_trouble,
            },
            n = {
              ['<c-t>'] = open_with_trouble,
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
          fzf = {
            fuzzy = true, -- false will only do exact matching
            override_generic_sorter = true, -- override the generic sorter
            override_file_sorter = true, -- override the file sorter
            case_mode = 'smart_case', -- or "ignore_case" or "respect_case"
            -- the default case_mode is "smart_case"
          },
          live_grep_args = {
            auto_quoting = true, -- enable/disable auto-quoting
            -- override default mappings
            -- default_mappings = {},
            mappings = {
              -- extend mappings
              i = {
                ['<C-k>'] = lga_actions.quote_prompt(),
              },
            },
          },
        },
      })

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
      vim.keymap.set('n', '<C-M-p>', function()
        require('telescope.builtin').git_files()
      end, {
        desc = 'telescope git files',
      })
      vim.keymap.set('n', '<C-g>', function()
        -- require('telescope.builtin').live_grep()
        require('telescope').extensions.live_grep_args.live_grep_args()
      end, {
        desc = 'telescope live grep',
      })
      vim.keymap.set('n', 'q', function()
        -- require('telescope.builtin').live_grep()
        require('telescope.builtin').current_buffer_fuzzy_find()
      end, {
        desc = 'telescope current_buffer_fuzzy_find',
      })
      vim.keymap.set('n', 'Q', function()
        require('telescope.builtin').buffers()
      end, {
        desc = 'telescope buffers',
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
      vim.keymap.set('n', '<C-k>r', function()
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
      vim.keymap.set('n', '<C-k>m', function()
        require('telescope.builtin').keymaps()
      end, {
        desc = 'telescope keymaps',
      })
      vim.keymap.set('n', '<C-k>;', function()
        require('telescope.builtin').resume()
      end, {
        desc = 'telescope resume',
      })

      -- extensions
    end,
  },
  {
    'akinsho/toggleterm.nvim',
    cond = not_in_vscode,
    config = function()
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
      vim.keymap.set({ 'n' }, '<Leader>at', '<Cmd>ToggleTermToggleAll<CR>', {})
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
    end,
  },
  {
    'johmsalas/text-case.nvim',
    config = function()
      require('textcase').setup({})
    end,
  },
  {
    'WhoIsSethDaniel/toggle-lsp-diagnostics.nvim',
    cond = not_in_vscode,
    config = function()
      require('toggle_lsp_diagnostics').init({
        start_on = true,
      })
    end,
  },
  {
    'folke/trouble.nvim',
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
    opts = {}, -- for default options, refer to the configuration section for custom setup.
    cmd = 'Trouble',
    keys = {
      {
        '<leader>xx',
        '<cmd>Trouble diagnostics toggle<cr>',
        desc = 'Diagnostics (Trouble)',
      },
      {
        '<leader>xX',
        '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',
        desc = 'Buffer Diagnostics (Trouble)',
      },
      {
        '<leader>cs',
        '<cmd>Trouble symbols toggle focus=false<cr>',
        desc = 'Symbols (Trouble)',
      },
      {
        '<leader>cl',
        '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
        desc = 'LSP Definitions / references / ... (Trouble)',
      },
      {
        '<leader>xL',
        '<cmd>Trouble loclist toggle<cr>',
        desc = 'Location List (Trouble)',
      },
      {
        '<leader>xQ',
        '<cmd>Trouble qflist toggle<cr>',
        desc = 'Quickfix List (Trouble)',
      },
    },
  },
  {
    'mbbill/undotree',
    cond = not_in_vscode,
  },
  {
    'andymass/vim-matchup',
    -- enabled = false,
    cond = not_in_vscode,
    config = function()
      vim.g.matchup_matchparen_offscreen = {
        method = 'popup',
      }
    end,
  },
  {
    'chaoren/vim-wordmotion',
    enabled = false,
  },
  {
    'ojroques/nvim-osc52',
    cond = not_in_vscode,
    config = function()
      vim.keymap.set('n', '<leader>c', require('osc52').copy_operator, {
        expr = true,
      })
      vim.keymap.set('n', '<leader>cc', '<leader>c_', {
        remap = true,
      })
      vim.keymap.set('v', '<leader>c', require('osc52').copy_visual)
    end,
  },
  {
    'kyoh86/vim-ripgrep',
    cond = not_in_vscode,
    config = function()
      -- print(vim.inspect(opt.args))
      -- function split(inputstr, sep)
      --   if sep == nil then
      --     sep = '%s'
      --   end
      --
      --   local t = {}
      --
      --   for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
      --     table.insert(t, str)
      --   end
      --
      --   return t
      -- end
      --
      vim.api.nvim_create_user_command('G', function(opt)
        local args = '--vimgrep --smart-case --hidden --glob "!.git"' .. opt.args
        -- local args = split(args_s, ' ')

        vim.fn['ripgrep#search'](args)
      end, {
        nargs = '+',
        complete = 'file',
      })
      vim.api.nvim_create_user_command('Gi', function(opt)
        local args = '--vimgrep --smart-case --hidden --glob "!.git" --no-ignore ' .. opt.args
        -- local args = split(args_s, ' ')

        vim.fn['ripgrep#search'](args)
      end, {
        nargs = '+',
        complete = 'file',
      })
    end,
  },
  {
    'microsoft/vscode-js-debug',
    cond = not_in_vscode,
    build = 'npm install --legacy-peer-deps && npx gulp vsDebugServerBundle && mv dist out',
  },
  {
    'folke/which-key.nvim',
    cond = not_in_vscode,
    config = function()
      -- vim.opt.timeoutlen = '500'
      require('which-key').setup({
        plugins = {
          spelling = {
            enabled = true,
          },
        },
      })
    end,
  },
  {
    'piersolenski/wtf.nvim',
    enabled = false,
    dependencies = { 'MunifTanjim/nui.nvim' },
    event = 'VeryLazy',
    opts = {},
    keys = {
      {
        'gw',
        mode = { 'n' },
        function()
          require('wtf').ai()
        end,
        desc = 'Debug diagnostic with AI',
      },
      {
        mode = { 'n' },
        'gW',
        function()
          require('wtf').search()
        end,
        desc = 'Search diagnostic with Google',
      },
    },
  },
}

local opts = {}
require('lazy').setup(plugins, opts)
