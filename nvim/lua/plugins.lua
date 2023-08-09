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
    cond = not_in_vscode,
    name = 'barbecue',
    version = '*',
    dependencies = {
      'SmiteshP/nvim-navic',
      'nvim-tree/nvim-web-devicons', -- optional dependency
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
            local icon = level:match('error') and ' ' or ' '
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
    'numToStr/Comment.nvim',
    enalbed = false,
    dependencies = { { 'JoosepAlviste/nvim-ts-context-commentstring' } },
    config = function()
      require('Comment').setup({
        pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),
      })
      local ft = require('Comment.ft')
      ft.set('sh', '#%s')
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
            dismiss = '<C-]>',
          },
        },
        panel = { enabled = false },
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
    'ggandor/flit.nvim',
    cond = not_in_vscode,
    config = function()
      require('flit').setup({})
    end,
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
      vim.api.nvim_exec(
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
        false
      )
      vim.g.gruvbox_material_diagnostic_text_highlight = 1
      vim.g.gruvbox_material_diagnostic_line_highlight = 1
      vim.g.gruvbox_material_diagnostic_virtual_text = 'colored'

      vim.cmd([[colorscheme gruvbox-material]])
    end,
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    cond = not_in_vscode,
    config = function()
      vim.opt.termguicolors = true
      vim.opt.list = true
      -- vim.opt.listchars:append('space:⋅')
      -- vim.opt.listchars:append('eol:↴')

      require('indent_blankline').setup({
        space_char_blankline = ' ',
        show_current_context = true,
        show_current_context_start = true,
      })
    end,
  },
  {
    'ggandor/leap.nvim',
    config = function()
      require('leap').add_default_mappings()
    end,
  },
  {
    'nvim-lualine/lualine.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-tree/nvim-web-devicons', 'SmiteshP/nvim-navic' } },
    config = function()
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
          refresh = {
            statusline = 1000,
            tabline = 1000,
            winbar = 1000,
          },
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
        -- winbar = {
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
    dependencies = { { 'williamboman/mason.nvim' }, { 'hrsh7th/cmp-nvim-lsp' }, { 'nvim-telescope/telescope.nvim' } },
    -- after = 'mason.nvim',
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = {
          'lua_ls',
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
    end,
  },
  {
    'echasnovski/mini.nvim',
    version = false,
    dependencies = { { 'nvim-treesitter/nvim-treesitter' }, { 'JoosepAlviste/nvim-ts-context-commentstring' } },
    config = function()
      require('mini.cursorword').setup()
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
          fixme = { pattern = '%f[%w]()FIXME()%f[%W]', group = 'MiniHipatternsFixme' },
          hack = { pattern = '%f[%w]()HACK()%f[%W]', group = 'MiniHipatternsHack' },
          todo = { pattern = '%f[%w]()TODO()%f[%W]', group = 'MiniHipatternsTodo' },
          note = { pattern = '%f[%w]()NOTE()%f[%W]', group = 'MiniHipatternsNote' },
          -- Highlight hex color strings (`#rrggbb`) using that color
          hex_color = hipatterns.gen_highlighter.hex_color(),
        },
      })

      require('mini.pairs').setup()
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
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-tree/nvim-web-devicons',
      'MunifTanjim/nui.nvim',
    },
    cond = not_in_vscode,
    cmd = 'Neotree',
    -- keys = {
    --   {
    --     '<leader>fe',
    --     function()
    --       require('neo-tree.command').execute({ toggle = true, dir = require('lazyvim.util').get_root() })
    --     end,
    --     desc = 'Explorer NeoTree (root dir)',
    --   },
    --   {
    --     '<leader>fE',
    --     function()
    --       require('neo-tree.command').execute({ toggle = true, dir = vim.loop.cwd() })
    --     end,
    --     desc = 'Explorer NeoTree (cwd)',
    --   },
    --   { '<leader>e', '<leader>fe', desc = 'Explorer NeoTree (root dir)', remap = true },
    --   { '<leader>E', '<leader>fE', desc = 'Explorer NeoTree (cwd)', remap = true },
    -- },
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
          follow_current_file = false,
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
    'folke/noice.nvim',
    dependencies = { { 'MunifTanjim/nui.nvim', 'rcarriga/nvim-notify' } },
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
    'jose-elias-alvarez/null-ls.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' } },
    config = function()
      local augroup = vim.api.nvim_create_augroup('LspFormatting', {})
      local null_ls = require('null-ls')
      null_ls.setup({
        -- LuaFormatter off
        -- stylua: ignore start
        sources = {
          -- code actions
          -- null_ls.builtins.code_actions.eslint,
          null_ls.builtins.code_actions.eslint_d,
          null_ls.builtins.code_actions.gitrebase,
          -- null_ls.builtins.code_actions.gitsigns,
          -- null_ls.builtins.code_actions.refactoring,
          -- null_ls.builtins.code_actions.xo,
          -- completion
          -- null_ls.builtins.completion.spell,
          -- null_ls.builtins.completion.tags,
          -- diagnostics
          null_ls.builtins.diagnostics.actionlint,
          null_ls.builtins.diagnostics.buf,
          null_ls.builtins.diagnostics.erb_lint,
          -- null_ls.builtins.diagnostics.eslint,
          null_ls.builtins.diagnostics.eslint_d,
          null_ls.builtins.diagnostics.fish,
          -- null_ls.builtins.diagnostics.haml_lint,
          null_ls.builtins.diagnostics.mdl,
          null_ls.builtins.diagnostics.rubocop,
          null_ls.builtins.diagnostics.selene,
          null_ls.builtins.diagnostics.sqlfluff.with({
            extra_args = { '--dialect', 'postgres' },
          }),
          null_ls.builtins.diagnostics.tidy,
          null_ls.builtins.diagnostics.stylelint,
          -- null_ls.builtins.diagnostics.todo_comments,
          null_ls.builtins.diagnostics.trail_space,
          -- null_ls.builtins.diagnostics.xo,
          null_ls.builtins.diagnostics.yamllint,
          -- null_ls.builtins.diagnostics.zsh,
          -- formatting
          null_ls.builtins.formatting.beautysh,
          null_ls.builtins.formatting.buf,
          -- null_ls.builtins.formatting.deno_fmt,
          null_ls.builtins.formatting.erb_lint,
          -- null_ls.builtins.formatting.eslint,
          null_ls.builtins.formatting.eslint_d,
          null_ls.builtins.formatting.fish_indent,
          -- null_ls.builtins.formatting.prettier,
          -- null_ls.builtins.formatting.prettierd,
          -- null_ls.builtins.formatting.prismaFmt,
          null_ls.builtins.formatting.rubocop,
          null_ls.builtins.formatting.rustfmt,
          -- null_ls.builtins.formatting.sql_formatter,
          null_ls.builtins.formatting.sqlfluff.with({
            extra_args = { '--dialect', 'postgres' },
          }),
          null_ls.builtins.formatting.stylelint,
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.formatting.taplo,
          null_ls.builtins.formatting.tidy,
          -- null_ls.builtins.formatting.trim_newlines,
          -- null_ls.builtins.formatting.trim_whitespace,
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
                -- on 0.8, you should use vim.lsp.buf.format({ bufnr = bufnr }) instead
                -- vim.lsp.buf.formatting_sync()
                vim.lsp.buf.format({
                  bufnr = bufnr,
                })
              end,
            })
          end
        end,
      })
    end,
  },
  {
    'windwp/nvim-autopairs',
    -- cond = not_in_vscode,
    enabled = false,
    dependencies = { { 'hrsh7th/nvim-cmp' } },
    config = function()
      require('nvim-autopairs').setup({})
    end,
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
      -- { 'windwp/nvim-autopairs' },
    },
    event = 'InsertEnter',
    config = function()
      local cmp = require('cmp')
      local lspkind = require('lspkind')

      -- -- for autopairs

      -- cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())

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
    dependencies = { 'mfussenegger/nvim-dap' },
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
            -- program = '${file}',
            program = 'npm run dev',
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
    'hrsh7th/nvim-linkedit',
    enabled = not_in_vscode,
    config = function()
      require('linkedit').setup({
        sources = {
          { name = 'lsp_linked_editing_range' },
          { name = 'lsp_document_highlight', on = { 'operator' } },
        },
      })
    end,
  },

  {
    'neovim/nvim-lspconfig',
    cond = not_in_vscode,
    dependencies = { { 'williamboman/mason-lspconfig.nvim', 'SmiteshP/nvim-navic', 'nanotee/sqls.nvim' } },
    -- after = 'mason-lspconfig.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      -- lsp diagnostics setting
      vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        underline = true,
        update_in_insert = true,
        severity_sort = true,
      })

      -- lsp diagnostics symbols
      local signs = {
        Error = ' ',
        Warn = ' ',
        Hint = ' ',
        Info = ' ',
      }

      for type, icon in pairs(signs) do
        local hl = 'DiagnosticSign' .. type
        vim.fn.sign_define(hl, {
          icon = icon,
          text = icon,
          texthl = hl,
          numhl = hl,
        })
      end

      -- Set up lspconfig.
      local augroup_lsp_keybind = vim.api.nvim_create_augroup('augroup_lsp_keybind', {})
      vim.api.nvim_create_autocmd({ 'LspAttach' }, {
        group = augroup_lsp_keybind,
        pattern = { '*' },
        callback = function(args)
          local bufnr = args.buf
          -- local client = vim.lsp.get_client_by_id(args.data.client_id)
          vim.api.nvim_buf_set_option(0, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

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

      local lsp_formatting = function(bufnr)
        vim.lsp.buf.format({
          filter = function(client)
            -- apply whatever logic you want (in this example, we'll only use null-ls)
            return client.name == 'null-ls'
          end,
          bufnr = bufnr,
        })
      end

      -- if you want to set up formatting on save, you can use this as a callback
      local augroup = vim.api.nvim_create_augroup('LspFormatting', {})

      -- add to your shared on_attach callback
      local on_attach = function(client, bufnr)
        if client.supports_method('textDocument/formatting') then
          vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
          vim.api.nvim_create_autocmd('BufWritePre', {
            group = augroup,
            buffer = bufnr,
            callback = function()
              lsp_formatting(bufnr)
            end,
          })
        end

        if client.server_capabilities.documentSymbolProvider then
          require('nvim-navic').attach(client, bufnr)
        end
      end

      local lspconfig = require('lspconfig')
      local capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities())
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
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
              hint = {
                enable = true,
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
        -- ['ruby_ls'] = function()
        --   lspconfig.ruby_ls.setup({
        --     capabilitiies = capabilities,
        --     on_attach = on_attach,
        --     cmd = { 'bundle', 'exec', 'ruby-lsp' },
        --   })
        -- end,
        -- ['sqls'] = function()
        --   lspconfig.sqls.setup({
        --     capabilitiies = capabilities,
        --     on_attach = function(client, bufnr)
        --       navic.attach(client, bufnr)
        --       require('sqls').on_attch(client, bufnr)
        --     end,
        --     settings = {
        --       sqls = {
        --         connections = {
        --           -- {
        --           --   driver = 'mysql',
        --           --   dataSourceName = 'root:root@tcp(127.0.0.1:3306)/world',
        --           -- },
        --           {
        --             driver = 'postgresql',
        --             dataSourceName = 'host=localhost port=5432 user=postgres password=password dbname=memie_dev sslmode=disable',
        --           },
        --         },
        --       },
        --     },
        --   })
        -- end,
      })
    end,
  },
  {
    'SmiteshP/nvim-navic',
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
    'rcarriga/nvim-notify',
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
          require('notify').dismiss({ silent = true, pending = true })
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
    'kylechui/nvim-surround',
    version = '*', -- Use for stability; omit to use `main` branch for the latest features
    enabled = false,
    config = function()
      require('nvim-surround').setup({})
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = { { 'JoosepAlviste/nvim-ts-context-commentstring' } },
    build = function()
      require('nvim-treesitter.install').update({
        with_sync = true,
      })
    end,
    config = function()
      require('nvim-treesitter.configs').setup({
        -- ensure_installed = { 'markdown', 'markdown_inline' },
        auto_install = false,
        highlight = {
          enable = true,
          -- disable = { "c", "rust" },
          additional_vim_regex_highlighting = false,
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
        indent = {
          enable = true,
        },
        matchup = {
          enable = true,
          -- disable = { "c", "ruby" },  -- optional, list of language that will be disabled
        },
        endwise = {
          enable = true,
        },
        context_commentstring = {
          enable = true,
          enable_autocmd = false,
        },
      })
    end,
  },
  {
    'MunifTanjim/nui.nvim',
    lazy = true,
  },
  {
    'gen740/SmoothCursor.nvim',
    enabled = false,
    cond = not_in_vscode,
    config = function()
      require('smoothcursor').setup({})
    end,
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
    dependencies = { { 'nvim-treesitter/nvim-treesitter' } },
    config = function() end,
  },
  {
    'nvim-tree/nvim-web-devicons',
    cond = not_in_vscode,
  },
  {
    'folke/persistence.nvim',
    event = 'BufReadPre',
    opts = { options = { 'buffers', 'curdir', 'tabpages', 'winsize', 'help' } },
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
          require('persistence').load({ last = true })
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
        patterns = {
          '.git',
          '_darcs',
          '.hg',
          '.bzr',
          '.svn',
          'Makefile',
          'package.json',
        },
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
    'simrat39/rust-tools.nvim',
    cond = not_in_vscode,
    dependencies = { { 'nvim-lua/plenary.nvim' }, { 'neovim/nvim-lspconfig' }, { 'mfussenegger/nvim-dap' } },
    -- after = 'nvim-lspconfig',
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
    'nvim-telescope/telescope-ui-select.nvim',
    enabled = false,
    cond = not_in_vscode,
    dependencies = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('ui-select')
    end,
  },
  {
    'nvim-telescope/telescope.nvim',
    -- version = '0.1.0',
    branch = '0.1.x',
    cond = not_in_vscode,
    dependencies = {
      { 'nvim-tree/nvim-web-devicons' },
      { 'nvim-lua/plenary.nvim' },
      {
        'nvim-treesitter/nvim-treesitter',
      },
    },
    config = function()
      local trouble = require('trouble.providers.telescope')
      local lga_actions = require('telescope-live-grep-args.actions')
      require('telescope').setup({
        defaults = {
          vimgrep_arguments = { 'rg', '--vimgrep', '--smart-case', '--hidden', '--glob', '!.git' },
          -- layout_strategy = 'vertical',
          -- layout_config = {
          --   prompt_position = 'top',
          -- },
          mappings = {
            i = {
              ['<c-t>'] = trouble.open_with_trouble,
            },
            n = {
              ['<c-t>'] = trouble.open_with_trouble,
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
          --   file_browser = {
          --     hijack_netrw = true
          --   }
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
      -- vim.keymap.set('n', '<Leader>tb', function()
      --   require('telescope.builtin').buffers()
      -- end)
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
      -- vim.keymap.set('n', '<Leader>tc', function()
      --   require('telescope.builtin').commands()
      -- end)
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
            return vim.o.columns * 0.4
          end
        end,
      })
      vim.keymap.set({ 'n' }, '<Leader>t', '<Cmd>exe v:count1 . "ToggleTerm"<CR>', {})
      vim.keymap.set({ 'n' }, '<Leader>at', '<Cmd>ToggleTermToggleAll<CR>', {})
      vim.keymap.set({ 'n' }, '<Leader>y', '<Cmd>10ToggleTerm direction=float<CR>', {})
      vim.keymap.set({ 'n', 't' }, '<F6>', '<Cmd>10ToggleTerm direction=float<CR>', {})

      local Terminal = require('toggleterm.terminal').Terminal
      local lazygit = Terminal:new({
        cmd = 'lazygit',
        direction = 'float',
        hidden = true,
        count = 100,
      })

      ---@diagnostic disable: lowercase-global
      function _lazygit_toggle()
        lazygit:toggle()
      end

      vim.keymap.set('n', '<A-g>', '<Cmd>lua _lazygit_toggle()<CR>', {
        desc = 'lazygit',
      })
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
    cond = not_in_vscode,
    dependencies = { { 'nvim-tree/nvim-web-devicons' } },
    config = function()
      require('trouble').setup({
        icons = true,
      })

      vim.keymap.set('n', '<Leader>xx', '<Cmd>TroubleToggle<CR>', {})
      vim.keymap.set('n', '<Leader>xw', '<Cmd>TroubleToggle workspace_diagnostics<CR>', {})
      vim.keymap.set('n', '<Leader>xd', '<Cmd>TroubleToggle document_diagnostics<CR>', {})
      vim.keymap.set('n', '<Leader>xl', '<Cmd>TroubleToggle loclist<CR>', {})
      vim.keymap.set('n', '<Leader>xq', '<Cmd>TroubleToggle quickfix<CR>', {})
      -- vim.keymap.set('n', 'gR', '<Cmd>TroubleToggle lsp_references<CR>', {})
      --
      vim.cmd([[
        cnoreabbrev copen TroubleToggle quickfix
      ]])
    end,
  },
  {
    'mbbill/undotree',
    cond = not_in_vscode,
  },
  {
    'RRethy/vim-illuminate',
    cond = not_in_vscode,
    enabled = false,
    config = function()
      require('illuminate').configure({})
    end,
  },
  {
    'andymass/vim-matchup',
    -- enabled = false,
    cond = not_in_vscode,
    config = function()
      vim.g.matchup_matchparen_offscreen = { method = 'popup' }
    end,
  },
  {
    'ojroques/nvim-osc52',
    cond = not_in_vscode,
    config = function()
      vim.keymap.set('n', '<leader>c', require('osc52').copy_operator, { expr = true })
      vim.keymap.set('n', '<leader>cc', '<leader>c_', { remap = true })
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
    build = 'npm install --legacy-peer-deps && npm run compile',
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
}

local opts = {}
require('lazy').setup(plugins, opts)
