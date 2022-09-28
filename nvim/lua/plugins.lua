local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd([[packadd packer.nvim]])
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

-- Autocommand that reloads neovim whenever you save the plugins.lua file
-- vim.cmd([[
--   augroup packer_user_config
--     autocmd!
--     autocmd BufWritePost plugins.lua source <afile> | PackerSync
--   augroup end
-- ]])

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, 'packer')
if not status_ok then
  return
end

if vim.g.vscode then
  packer.init({
    ensure_dependencies = true,
    display = {
      noninteractive = true,
    },
  })
else
  packer.init({
    ensure_dependencies = true,
    display = {
      noninteractive = false,
      open_fn = function()
        return require('packer.util').float({})
      end,
    },
  })
end

local vscode = vim.g.vscode == 1
return packer.startup(function(use)
  use({
    'wbthomason/packer.nvim',
  })

  use({
    'rmagatti/auto-session',
    disable = vscode,
    config = function()
      require('auto-session').setup({
        -- log_level = 'error',
        auto_session_enabled = true,
        auto_session_create_enabled = true,
        auto_save_enabled = true,
        auto_restore_enabled = false,
        -- auto_session_suppress_dirs = { "~/", "~/Projects", "~/Downloads", "/"},
        -- auto_session_allowed_dirs = { '~/*', '/mnt/*' },
        -- auto_session_use_git_branch = true,
        -- nvim-tree
        pre_save_cmds = { "lua require('nvim-tree').setup({})", 'tabdo NvimTreeClose' },
        -- for neo-tree cmds
        -- https://github.com/nvim-neo-tree/neo-tree.nvim/issues/128
        -- cwd_change_handling = {
        --   restore_upcoming_session = true, -- already the default, no need to specify like this, only here as an example
        --   pre_cwd_changed_hook = function()
        --     -- vim.api.nvim_feedkeys('<C-c>', 'n', true)
        --   end,
        --   post_cwd_changed_hook = function() -- example refreshing the lualine status line _after_ the cwd changes
        --     -- require('lualine').refresh() -- refresh lualine so the new session name is displayed in the status bar
        --   end,
        -- },
      })

      vim.o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal'

      vim.keymap.set('n', '<Leader>r', '<Cmd>RestoreSession<<CR>')
    end,
  })

  use({
    'akinsho/bufferline.nvim',
    tag = 'v2.*',
    disable = vscode,
    requires = { { 'kyazdani42/nvim-web-devicons' } },
    config = function()
      vim.opt.termguicolors = true
      require('bufferline').setup({
        options = {
          mode = 'buffers',
          diagnostics = 'nvim_lsp',
          diagnostics_indicator = function(count, level, _diagnostics_dict, _context)
            local icon = level:match('error') and ' ' or ' '
            return ' ' .. icon .. count
          end,
        },
      })
    end,
  })

  use({
    'uga-rosa/ccc.nvim',
    disable = vscode,
    cofnig = function()
      require('ccc').setup({
        highlighter = {
          auto_enable = true,
          lsp = true,
        },
      })
    end,
  })

  use({
    'f3fora/cmp-spell',
    disable = vscode,
    requires = { { 'hrsh7th/nvim-cmp' } },
    config = function()
      vim.opt.spell = true
      vim.opt.spelllang = { 'en_us', 'cjk' }
    end,
  })

  use({
    'numToStr/Comment.nvim',
    disable = vscode,
    config = function()
      require('Comment').setup({})
      local ft = require('Comment.ft')
      ft.set('sh', '#%s')
    end,
  })

  use({
    'zbirenbaum/copilot.lua',
    disable = vscode,
    event = { 'VimEnter' },
    config = function()
      vim.defer_fn(function()
        require('copilot').setup({})
      end, 100)
    end,
  })

  -- use({
  --   'github/copilot.vim',
  --   disable = vscode,
  -- })

  use({
    'zbirenbaum/copilot-cmp',
    disable = vscode,
    requires = { { 'copilot.lua' }, { 'hrsh7th/nvim-cmp' } },
    config = function()
      require('copilot_cmp').setup({})
    end,
  })

  use({
    'saecki/crates.nvim',
    disable = vscode,
    tag = 'v0.2.1',
    requires = { { 'nvim-lua/plenary.nvim' } },
    config = function()
      require('crates').setup()
    end,
  })

  use({
    'sindrets/diffview.nvim',
    diable = vscode,
    requires = { { 'nvim-lua/plenary.nvim' } },
  })

  use({
    'j-hui/fidget.nvim',
    disable = true,
    config = function()
      require('fidget').setup({})
    end,
  })

  use({
    'rafamadriz/friendly-snippets',
    disable = vscode,
  })

  use({
    'lewis6991/gitsigns.nvim',
    disable = vscode,
    config = function()
      require('gitsigns').setup({
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map('n', ']g', function()
            if vim.wo.diff then
              return ']g'
            end
            vim.schedule(function()
              gs.next_hunk()
            end)
            return '<Ignore>'
          end, {
            expr = true,
            desc = 'gitsign next_hunk',
          })

          map('n', '[g', function()
            if vim.wo.diff then
              return '[g'
            end
            vim.schedule(function()
              gs.prev_hunk()
            end)
            return '<Ignore>'
          end, {
            expr = true,
            desc = 'gitsign prev_hunk',
          })

          -- -- Actions
          map({ 'n', 'v' }, '<leader>hs', ':Gitsigns stage_hunk<CR>')
          map({ 'n', 'v' }, '<leader>hr', ':Gitsigns reset_hunk<CR>')
          map('n', '<leader>hS', gs.stage_buffer, { desc = 'gitsigns stage_buffer' })
          map('n', '<leader>hu', gs.undo_stage_hunk, { desc = 'gitsigns undo_stage_stage_hunk' })
          map('n', '<leader>hR', gs.reset_buffer, { desc = 'gitsigns reset_buffer' })
          map('n', '<leader>hp', gs.preview_hunk, { desc = 'gitsigns preview_hunk' })
          map('n', '<leader>hf', function()
            gs.blame_line({
              full = true,
            })
          end, { desc = 'gitsigns blame_line full=true' })
          map('n', '<leader>hb', gs.toggle_current_line_blame, { desc = 'gitsigns toggle_current_line_blame' })
          map('n', '<leader>hd', gs.diffthis, { desc = 'gitsigns diffthis' })
          map('n', '<leader>hD', function()
            gs.diffthis('~')
          end, { desc = 'gitsigns diffthis(~)' })
          map('n', '<leader>ht', gs.toggle_deleted, { desc = 'gitsigns toggle_deleted' })
          map('n', '<leader>hl', gs.setloclist, { desc = 'gitsigns setloclist' })

          -- Text object
          map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end,
      })
    end,
  })

  use({
    'sainnhe/gruvbox-material',
    disable = vscode,
    requires = {
      'nvim-treesitter/nvim-treesitter',
      opt = true,
    },
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
        augroup nord-theme-overrides
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
  })

  use({
    'phaazon/hop.nvim',
    branch = 'v2', -- optional but strongly recommended
    config = function()
      -- you can configure Hop the way you like here; see :h hop-config
      require('hop').setup({
        keys = 'etovxqpdygfblzhckisuran',
      })
      vim.keymap.set({ 'n', 'v' }, '<Leader>w', '<Cmd>HopWord<CR>')
      -- vim.keymap.set({ 'n', 'v' }, '<Leader>b', '<Cmd>HopWordBC<CR>')
      vim.keymap.set({ 'n', 'v' }, '<Leader>l', '<Cmd>HopLineStart<CR>')
      -- vim.keymap.set({ 'n', 'v' }, '<Leader>k', '<Cmd>HopLineStartAC<CR>')
      vim.keymap.set({ 'n', 'v' }, '<Leader>f', '<Cmd>HopChar1<CR>')
      -- vim.keymap.set('', '<Leader>l', '<Cmd>HopLine<CR>')
      -- vim.keymap.set('', '<Leader>c', '<Cmd>HopChar1CurrentLine<CR>')
      vim.keymap.set({ 'n', 'v' }, '<Leader>o', '<Cmd>HopChar2<CR>')

      vim.api.nvim_set_keymap(
        '',
        'f',
        "<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true })<CR>",
        { desc = 'hop f' }
      )
      vim.api.nvim_set_keymap(
        '',
        'F',
        "<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true })<CR>",
        { desc = 'hop F' }
      )
      vim.api.nvim_set_keymap(
        '',
        't',
        "<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })<CR>",
        { desc = 'hop t' }
      )
      vim.api.nvim_set_keymap(
        '',
        'T',
        "<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })<CR>",
        { desc = 'hop T' }
      )
    end,
  })

  use({
    'lukas-reineke/indent-blankline.nvim',
    disable = vscode,
    config = function()
      vim.opt.termguicolors = true

      -- local augroup = vim.api.nvim_create_augroup('augroup_indent-blankline', {
      --   clear = true,
      -- })
      -- vim.api.nvim_create_autocmd({ 'ColorScheme' }, {
      --   group = augroup,
      --   pattern = { '*' },
      --   callback = function()
      --     vim.cmd([[highlight IndentBlanklineIndent1 guibg=#E06C75 gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent2 guibg=#E5C07B gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent3 guibg=#98C379 gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent4 guibg=#56B6C2 gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent5 guibg=#61AFEF gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent6 guibg=#C678DD gui=nocombine]])
      --   end,
      -- })
      -- vim.api.nvim_create_autocmd({ 'ColorScheme' }, {
      --   group = augroup,
      --   pattern = { '*' },
      --   callback = function()
      --     vim.cmd([[highlight IndentBlanklineIndent1 guibg=#4d4d4d guifg=#4d4d4d gui=nocombine]])
      --     vim.cmd([[highlight IndentBlanklineIndent2 guibg=none guifg=none gui=nocombine]])
      --   end,
      -- })

      vim.opt.list = true
      vim.opt.listchars:append('space:⋅')
      vim.opt.listchars:append('eol:↴')

      require('indent_blankline').setup({
        -- char = '',
        space_char_blankline = ' ',
        show_current_context = true,
        show_current_context_start = true,

        -- char_highlight_list = { 'IndentBlanklineIndent1', 'IndentBlanklineIndent2' },
        -- space_char_highlight_list = { 'IndentBlanklineIndent1', 'IndentBlanklineIndent2' },

        -- char_highlight_list = {
        --   'IndentBlanklineIndent1',
        --   'IndentBlanklineIndent2',
        --   'IndentBlanklineIndent3',
        --   'IndentBlanklineIndent4',
        --   'IndentBlanklineIndent5',
        --   'IndentBlanklineIndent6',
        -- },
        -- space_char_highlight_list = {'IndentBlanklineIndent1', 'IndentBlanklineIndent2', 'IndentBlanklineIndent3',
        --                              'IndentBlanklineIndent4', 'IndentBlanklineIndent5', 'IndentBlanklineIndent6'}
      })
    end,
  })

  use({
    'nvim-lualine/lualine.nvim',
    disable = vscode,
    requires = { { 'kyazdani42/nvim-web-devicons' } },
    config = function()
      require('lualine').setup({
        sections = {
          lualine_c = { {
            'lsp_progress',
          } },
        },
        options = {
          theme = 'gruvbox-material',
        },
        extensions = {
          'nvim-tree',
          'quickfix',
          'toggleterm',
        },
      })
    end,
  })

  use({
    'arkav/lualine-lsp-progress',
    disable = vscode,
    requires = { { 'nvim-lualine/lualine.nvim' } },
  })

  use({
    'L3MON4D3/LuaSnip',
    tag = 'v1.*',
    disable = vscode,
    requires = { { 'rafamadriz/friendly-snippets' } },
    config = function()
      require('luasnip').config.setup({
        history = false,
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
  })

  use({
    'glepnir/lspsaga.nvim',
    disable = vscode,
    branch = 'main',
    requires = { { 'neovim/nvim-lspconfig' } },
    config = function()
      local saga = require('lspsaga')

      saga.init_lsp_saga({
        code_action_lightbulb = {
          -- enable = true,
          -- enable_in_insert = true,
          -- cache_code_action = true,
          sign = true,
          -- update_time = 150,
          -- sign_priority = 20,
          virtual_text = false,
        },
      })
    end,
  })

  use({
    'williamboman/mason-lspconfig.nvim',
    disable = vscode,
    requires = { { 'williamboman/mason.nvim' } },
    config = function()
      require('mason-lspconfig').setup({
        -- ensure_installed = {
        --   "sumneko_lua", "rust_analyzer"
        -- },
        automatic_installation = true,
      })
    end,
  })

  use({
    'williamboman/mason.nvim',
    disable = vscode,
    config = function()
      require('mason').setup()
    end,
  })

  use({
    'jose-elias-alvarez/null-ls.nvim',
    disable = vscode,
    requires = { { 'nvim-lua/plenary.nvim' } },
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
          null_ls.builtins.diagnostics.todo_comments,
          null_ls.builtins.diagnostics.trail_space,
          -- null_ls.builtins.diagnostics.xo,
          null_ls.builtins.diagnostics.yamllint,
          -- null_ls.builtins.diagnostics.zsh,
          -- formatting
          null_ls.builtins.formatting.beautysh,
          -- null_ls.builtins.formatting.deno_fmt,
          null_ls.builtins.formatting.erb_lint,
          -- null_ls.builtins.formatting.eslint,
          -- null_ls.builtins.formatting.eslint_d,
          null_ls.builtins.formatting.fish_indent,
          -- null_ls.builtins.formatting.prettier,
          null_ls.builtins.formatting.prettierd,
          -- null_ls.builtins.formatting.prismaFmt,
          null_ls.builtins.formatting.rubocop,
          null_ls.builtins.formatting.rustfmt,
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
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd('BufWritePre', {
              group = augroup,
              buffer = bufnr,
              callback = function()
                -- on 0.8, you should use vim.lsp.buf.format({ bufnr = bufnr }) instead
                -- vim.lsp.buf.formatting_sync()
                vim.lsp.buf.format({ bufnr = bufnr })
              end,
            })
          end
        end,
      })
    end,
  })

  use({
    'windwp/nvim-autopairs',
    disable = vscode,
    requires = { { 'hrsh7th/nvim-cmp' } },
    config = function()
      require('nvim-autopairs').setup({})
    end,
  })

  use({
    'hrsh7th/nvim-cmp',
    disable = vscode,
    requires = {
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
      { 'windwp/nvim-autopairs' },
    },
    config = function()
      local cmp = require('cmp')
      local lspkind = require('lspkind')

      -- for autopairs
      local cmp_autopairs = require('nvim-autopairs.completion.cmp')
      cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())

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
          { name = 'luasnip' },
          { name = 'nvim_lsp_signature_help' },
          { name = 'nvim_lsp' },
          { name = 'crates' },
          { name = 'spell' },
          {
            { name = 'buffer' },
          },
        }),
        -- stylua: ignore end
        -- LuaFormatter on
        formatting = {
          format = lspkind.cmp_format({
            mode = 'symbol',
            max_width = 50,
            symbol_map = { Copilot = '' },
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

      -- Set up lspconfig.
      local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())

      -- https://github.com/jose-elias-alvarez/null-ls.nvim/wiki/Avoiding-LSP-formatting-conflicts
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

      -- Use an on_attach function to only map the following keys
      -- after the language server attaches to the current buffer
      local on_attach = function(client, bufnr)
        -- augroup == LspFormatting
        -- from above `local augroup = vim.api.nvim_create_augroup("LspFormatting", {})`
        if client.supports_method('textDocument/formatting') then
          vim.api.nvim_clear_autocmds({
            group = augroup,
            buffer = bufnr,
          })
          vim.api.nvim_create_autocmd({ 'BufWritePre' }, {
            group = augroup,
            buffer = bufnr,
            callback = function()
              lsp_formatting(bufnr)
            end,
          })
        end
        -- Enable completion triggered by <c-x><c-o>
        vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

        -- Mappings.
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        -- local lsp_bufopts = {
        -- 	buffer = bufnr,
        -- }
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, {
          buffer = bufnr,
          desc = 'vim.lsp delaration',
        })
        vim.keymap.set('n', 'gd', function()
          require('telescope.builtin').lsp_definitions()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp.buf.definition',
        })
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
          buffer = bufnr,
          desc = 'vim.lsp hover',
        })
        vim.keymap.set('n', 'gi', function()
          require('telescope.builtin').lsp_implementations()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp.buf.implementation',
        })
        vim.keymap.set('n', 'gk', vim.lsp.buf.signature_help, {
          buffer = bufnr,
          desc = 'vim.lsp signature_help',
        })
        vim.keymap.set(
          'n',
          '<Leader><Leader>wa',
          vim.lsp.buf.add_workspace_folder,
          { buffer = bufnr, desc = 'vim.lsp add_workspace_folder' }
        )
        vim.keymap.set(
          'n',
          '<Leader><Leader>wr',
          vim.lsp.buf.remove_workspace_folder,
          { buffer = bufnr, desc = 'vim.lsp remove_workspace_folder' }
        )
        vim.keymap.set('n', '<Leader><Leader>wl', function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, { buffer = bufnr, desc = 'vim.lsp list_workspace_folders' })
        vim.keymap.set('n', '<Leader>D', function()
          require('telescope.builtin').lsp_type_definitions()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp.buf.type_definition',
        })
        vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, {
          buffer = bufnr,
          desc = 'vim.lsp rename',
        })
        vim.keymap.set('n', '<F2>', vim.lsp.buf.rename, {
          buffer = bufnr,
          desc = 'vim.lsp rename',
        })
        vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action, {
          buffer = bufnr,
          desc = 'vim.lsp code_action',
        })
        vim.keymap.set('n', '<F7>', vim.lsp.buf.code_action, {
          buffer = bufnr,
          desc = 'vim.lsp code_action',
        })
        vim.keymap.set('n', 'gr', function()
          require('telescope.builtin').lsp_references()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp.buf.references',
        })
        vim.keymap.set(
          'n',
          '<F8>',
          -- 0.7
          -- vim.lsp.buf.formatting,
          -- 0.8
          vim.lsp.buf.format,
          {
            buffer = bufnr,
            desc = 'vim.lsp format',
          }
        )
        vim.keymap.set('n', '<Leader>s', function()
          require('telescope.builtin').lsp_dynamic_workspace_symbols()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp lsp_dynamic_workspace_symbols',
        })
        vim.keymap.set('n', '<Leader><Leader>s', function()
          require('telescope.builtin').lsp_document_symbols()
        end, {
          buffer = bufnr,
          desc = 'vim.lsp lsp_document_symbols',
        })
        -- See `:help vim.diagnostic.*` for documentation on any of the below functions
        -- local diagnostic_opts = {
        -- }
        vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float, {
          desc = 'diagnostic open_float',
        })
        vim.keymap.set('n', '[e', vim.diagnostic.goto_prev, {
          desc = 'diagnostic goto_prev',
        })
        vim.keymap.set('n', ']e', vim.diagnostic.goto_next, {
          desc = 'diagnostic goto_next',
        })
        vim.keymap.set('n', '<Leader>E', function()
          require('telescope.builtin').diagnostics()
        end, {
          desc = 'telescope diagnostics',
        })
        -- vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, { desc = 'diagnose set_loclist'})
      end

      local lspconfig = require('lspconfig')
      require('mason-lspconfig').setup_handlers({ --
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
        ['sumneko_lua'] = function()
          lspconfig.sumneko_lua.setup({
            capabilitiies = capabilities,
            on_attach = on_attach,
            settings = {
              Lua = {
                diagnostics = {
                  globals = { 'vim' },
                },
              },
            },
          })
        end,
      })
    end,
  })

  use({
    'mfussenegger/nvim-dap',
    disable = vscode,
    config = function()
      vim.keymap.set('n', '<F5>', function()
        require('dap').continue()
      end, {
        desc = 'nvim-dap continue',
      })
      vim.keymap.set('n', '<F10>', function()
        require('dap').step_over()
      end, {
        desc = 'nvim-dap step_over()',
      })
      vim.keymap.set('n', '<F10>', function()
        require('dap').step_into()
      end, {
        desc = 'nvim-dap step_into()',
      })
      vim.keymap.set('n', '<F12>', function()
        require('dap').step_out()
      end, {
        desc = 'nvim-dap step_out()',
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
  })

  use({
    'rcarriga/nvim-dap-ui',
    disable = vscode,
    requires = { 'mfussenegger/nvim-dap' },
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
  })

  use({
    'mxsdev/nvim-dap-vscode-js',
    requires = { { 'mfussenegger/nvim-dap' } },
    config = function()
      require('dap-vscode-js').setup({
        -- node_path = "node", -- Path of node executable. Defaults to $NODE_PATH, and then "node"
        -- debugger_path = "(runtimedir)/site/pack/packer/opt/vscode-js-debug", -- Path to vscode-js-debug installation.
        -- debugger_cmd = { "js-debug-adapter" }, -- Command to use to launch the debug server. Takes precedence over `node_path` and `debugger_path`.
        adapters = { 'pwa-node', 'pwa-chrome', 'pwa-msedge', 'node-terminal', 'pwa-extensionHost' }, -- which adapters to register in nvim-dap
      })
      for _, language in ipairs({ 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }) do
        require('dap').configurations[language] = {
          -- https://github.com/mxsdev/nvim-dap-vscode-js
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
          },
          -- https://nextjs.org/docs/advanced-features/debugging
          {
            name = 'Next.js: debug client-side',
            type = 'pwa-chrome',
            request = 'launch',
            url = 'http://localhost:3000',
          },
        }
      end
    end,
  })

  use({
    'https://codeberg.org/esensar/nvim-dev-container',
    disable = true,
    requires = { 'nvim-treesitter/nvim-treesitter' },
  })

  use({
    'neovim/nvim-lspconfig',
    disable = vscode,
    requires = { { 'williamboman/mason-lspconfig.nvim' } },
    config = function()
      -- lsp symbols
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

      -- lsp
      vim.lsp.handlers['textDocument/publishDiagnostics'] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
        -- -- Enable underline, use default values
        -- -- underline = true,
        -- -- Enable virtual text, override spacing to 4
        -- virtual_text = {
        --   prefix = '◯'
        --   -- spacing = 4
        -- },
        -- -- Use a function to dynamically turn signs off
        -- -- and on, using buffer local variables
        -- signs = function(namespace, bufnr)
        --   return vim.b[bufnr].show_signs == true
        -- end,
        update_in_insert = true,
      })
    end,
  })

  -- use({
  --   'rcarriga/nvim-notify',
  --   disable = vscode,
  --   config = function()
  --     require('notify').setup({})
  --   end,
  -- })

  use({
    'kylechui/nvim-surround',
    tag = '*', -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require('nvim-surround').setup({})
    end,
  })

  use({
    'kyazdani42/nvim-tree.lua',
    disable = vscode,
    requires = { 'kyazdani42/nvim-web-devicons' },
    config = function()
      require('nvim-tree').setup({
        open_on_setup = true,
        open_on_setup_file = false,
        sync_root_with_cwd = true,
        respect_buf_cwd = true,
        update_focused_file = {
          enable = true,
          update_root = true,
        },
        renderer = {
          highlight_git = true,
          highlight_opened_files = 'all',
          indent_markers = {
            enable = false,
            inline_arrows = true,
            icons = {
              corner = '└',
              edge = '│',
              item = '│',
              bottom = '─',
              none = ' ',
            },
          },
        },
        -- reload_on_bufenter = true
        -- view = {
        --   mappings = {
        --     list = {{
        --       key = "u",
        --       action = "dir_up"
        --     }}
        --   }
        -- }
      })
      vim.keymap.set('n', '<C-q>', function()
        -- toggle `(find_file?: bool, no_focus?: bool, path?: string)`
        require('nvim-tree').toggle(true, false)
      end, {
        desc = 'toggle nvim-tree',
      })
      -- vim.keymap.set('n', '<A-q>', function()
      --   -- toggle `(find_file?: bool, no_focus?: bool, path?: string)`
      --   require('nvim-tree').find_file()
      -- end, {
      --   desc = 'find_file in nvim-tree',
      -- })
    end,
  })

  use({
    'nvim-treesitter/nvim-treesitter',
    disable = vscode,
    requires = { { 'p00f/nvim-ts-rainbow' }, { 'andymass/vim-matchup' }, { 'RRethy/nvim-treesitter-endwise' } },
    run = function()
      require('nvim-treesitter.install').update({
        with_sync = true,
      })
    end,
    config = function()
      require('nvim-treesitter.configs').setup({
        auto_install = true,
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
        rainbow = {
          enable = true,
          -- disable = { "jsx", "cpp" }, list of languages you want to disable the plugin for
          extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
          max_file_lines = nil, -- Do not enable for files with more than n lines, int
          -- colors = {}, -- table of hex strings
          -- termcolors = {} -- table of colour name strings
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
        },
      })
    end,
  })

  use({
    'gen740/SmoothCursor.nvim',
    disable = true,
    config = function()
      require('smoothcursor').setup({})
    end,
  })

  use({
    'kevinhwang91/nvim-bqf',
    disable = vscode,
    requires = { { 'nvim-treesitter/nvim-treesitter' } },
  })

  use({
    'RRethy/nvim-treesitter-endwise',
    diasable = vscode,
  })

  use({
    'windwp/nvim-ts-autotag',
    disable = vscode,
    requires = { { 'nvim-treesitter/nvim-treesitter' } },
    config = function()
      require('nvim-ts-autotag').setup({})
    end,
  })

  use({
    'JoosepAlviste/nvim-ts-context-commentstring',
    disable = vscode,
    requires = { { 'numToStr/Comment.nvim', 'nvim-treesitter/nvim-treesitter' } },
    config = function()
      require('nvim-treesitter.configs').setup({
        context_commentstring = {
          enable = true,
          enable_autocmd = false,
        },
        require('Comment').setup({
          pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),
        }),
      })
    end,
  })

  use({
    'kyazdani42/nvim-web-devicons',
    disable = vscode,
  })

  use({ 'nvim-lua/plenary.nvim' })

  use({
    'ahmedkhalf/project.nvim',
    disable = vscode,
    config = function()
      require('project_nvim').setup({
        detection_methods = { 'pattern', 'lsp' },
        patterns = { '.git', '_darcs', '.hg', '.bzr', '.svn', 'Makefile', 'Rakefile', 'package.json', 'selene.toml' },
        -- exclude_dirs = { '~/.config/nvim', '~/dev/src/github.com/shishi/dotfiles/nvim' },
        show_hidden = false,
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
  })

  use({
    'ThePrimeagen/refactoring.nvim',
    disable = true,
    requires = { { 'nvim-lua/plenary.nvim' }, { 'nvim-treesitter/nvim-treesitter' } },
    config = function()
      require('refactoring').setup({})
    end,
  })

  use({
    'simrat39/rust-tools.nvim',
    diaable = vscode,
    requires = { { 'nvim-lua/plenary.nvim' }, { 'neovim/nvim-lspconfig' }, { 'mfussenegger/nvim-dap' } },
    config = function()
      local rt = require('rust-tools')

      rt.setup({
        hover_with_actions = true,
        server = {
          on_attach = function(_, bufnr)
            -- Hover actions
            -- vim.keymap.set('n', '<C-space>', rt.hover_actions.hover_actions, { buffer = bufnr })
            -- Code action groups
            vim.keymap.set('n', '<Leader>a', rt.code_action_group.code_action_group, { buffer = bufnr })
          end,
        },
      })
      -- rt.inlay_hints.enable()
    end,
  })

  use({
    'nvim-telescope/telescope-file-browser.nvim',
    disasble = vscode,
    require = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('file_browser')

      vim.keymap.set('n', '<C-k>z', function()
        require('telescope').extensions.file_browser.file_browser()
      end, {
        desc = 'telescope file browser',
      })
    end,
  })

  use({
    'nvim-telescope/telescope-fzf-native.nvim',
    disable = vscode,
    require = { { 'nvim-telescope/telescope.nvim' } },
    run = 'make',
    config = function()
      require('telescope').load_extension('fzf')
    end,
  })

  use({
    'nvim-telescope/telescope-ghq.nvim',
    disable = vscode,
    require = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('ghq')

      vim.keymap.set('n', '<C-k>g', '<Cmd>Telescope ghq list<CR>', {
        desc = 'telescope ghq',
      })
    end,
  })

  use({
    'nvim-telescope/telescope-live-grep-args.nvim',
    disable = vscode,
    require = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('live_grep_args')
    end,
  })

  use({
    'nvim-telescope/telescope-ui-select.nvim',
    disable = vscode,
    require = { { 'nvim-telescope/telescope.nvim' } },
    config = function()
      require('telescope').load_extension('ui-select')
    end,
  })

  use({
    'nvim-telescope/telescope.nvim',
    disable = vscode,
    -- tag = '0.1.0',
    branch = '0.1.x',
    requires = {
      { 'kyazdani42/nvim-web-devicons' },
      { 'nvim-lua/plenary.nvim' },
      { 'nvim-treesitter/nvim-treesitter' },
    },
    config = function()
      local trouble = require('trouble.providers.telescope')
      local lga_actions = require('telescope-live-grep-args.actions')
      require('telescope').setup({
        defaults = {
          --   layout_strategies = { 'horizontal' },
          --   layout_config = {
          --     prompt_position = 'top',
          --   },
          mappings = {
            i = { ['<c-t>'] = trouble.open_with_trouble },
            n = { ['<c-t>'] = trouble.open_with_trouble },
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
            mappings = { -- extend mappings
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
      vim.keymap.set('n', 's', function()
        -- require('telescope.builtin').live_grep()
        require('telescope.builtin').current_buffer_fuzzy_find()
      end, {
        desc = 'telescope current_buffer_fuzzy_find',
      })
      -- vim.keymap.set('n', '<Leader>tb', function()
      --   require('telescope.builtin').buffers()
      -- end)
      vim.keymap.set('n', 'S', function()
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
      -- vim.keymap.set('n', '<Leader>tc', function()
      --   require('telescope.builtin').commands()
      -- end)
      vim.keymap.set('n', '<C-k>c', function()
        require('telescope.builtin').commands()
      end, {
        desc = 'telescope commands',
      })
      vim.keymap.set('n', '<C-k><C-k>b', function()
        require('telescope.builtin').git_branches()
      end, {
        desc = 'telescope git branches',
      })
      vim.keymap.set('n', '<C-k>s', function()
        require('telescope.builtin').git_status()
      end, {
        desc = 'telescope git status',
      })
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

      -- extensions
    end,
  })

  use({
    'akinsho/toggleterm.nvim',
    disable = vscode,
    tag = '*',
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
  })

  use({
    'WhoIsSethDaniel/toggle-lsp-diagnostics.nvim',
    diable = vscode,
    config = function()
      require('toggle_lsp_diagnostics').init({ start_on = true })
    end,
  })

  use({
    'folke/trouble.nvim',
    disable = vscode,
    requires = { { 'kyazdani42/nvim-web-devicons' } },
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
  })

  use({
    'mbbill/undotree',
    disable = vscode,
  })

  use({
    'RRethy/vim-illuminate',
    disable = vscode,
    config = function()
      require('illuminate').configure({})
    end,
  })

  use({
    'andymass/vim-matchup',
    disable = vscode,
  })

  use({
    'kyoh86/vim-ripgrep',
    disable = vscode,
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
        local args = '--vimgrep --smart-case ' .. opt.args
        -- local args = split(args_s, ' ')

        vim.fn['ripgrep#search'](args)
      end, {
        nargs = '+',
        complete = 'file',
      })
      vim.api.nvim_create_user_command('Gi', function(opt)
        local args = '--vimgrep --smart-case --no-ignore-vcs' .. opt.args
        -- local args = split(args_s, ' ')

        vim.fn['ripgrep#search'](args)
      end, {
        nargs = '+',
        complete = 'file',
      })
    end,
  })

  use({
    'microsoft/vscode-js-debug',
    disable = vscode,
    opt = true,
    run = 'npm install --legacy-peer-deps && npm run compile',
  })

  use({
    'folke/which-key.nvim',
    disable = vscode,
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
  })

  use({
    'glepnir/zephyr-nvim',
    disable = true,
    requires = {
      'nvim-treesitter/nvim-treesitter',
      opt = true,
    },
  })

  -- packages except on github

  if packer_bootstrap then
    require('packer').sync()
  end
end)
