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
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

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
  use({ 'wbthomason/packer.nvim' })

  use({
    'akinsho/bufferline.nvim',
    tag = 'v2.*',
    disable = true,
    requires = { { 'kyazdani42/nvim-web-devicons' } },
    config = function()
      vim.opt.termguicolors = true
      require('bufferline').setup({})
    end,
  })

  use({
    'tzachar/cmp-tabnine',
    disable = vscode,
    requires = { { 'hrsh7th/nvim-cmp' } },
    run = './install.sh',
    config = function()
      require('cmp_tabnine.config').setup({})
    end,
  })

  use({
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup({})
      local ft = require('Comment.ft')
      ft.set('sh', '#%s')
    end,
  })

  use({
    'sindrets/diffview.nvim',
    requires = { { 'nvim-lua/plenary.nvim' } },
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
          map('n', ']c', function()
            if vim.wo.diff then
              return ']c'
            end
            vim.schedule(function()
              gs.next_hunk()
            end)
            return '<Ignore>'
          end, {
            expr = true,
            desc = 'gitsign next_hunk',
          })

          map('n', '[c', function()
            if vim.wo.diff then
              return '[c'
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
          -- map({'n', 'v'}, '<leader>hs', ':Gitsigns stage_hunk<CR>')
          -- map({'n', 'v'}, '<leader>hr', ':Gitsigns reset_hunk<CR>')
          -- map('n', '<leader>hS', gs.stage_buffer)
          -- map('n', '<leader>hu', gs.undo_stage_hunk)
          -- map('n', '<leader>hR', gs.reset_buffer)
          -- map('n', '<leader>hp', gs.preview_hunk)
          -- map('n', '<leader>hb', function()
          --   gs.blame_line {
          --     full = true
          --   }
          -- end)
          -- map('n', '<leader>tb', gs.toggle_current_line_blame)
          -- map('n', '<leader>hd', gs.diffthis)
          -- map('n', '<leader>hD', function()
          --   gs.diffthis('~')
          -- end)
          -- map('n', '<leader>td', gs.toggle_deleted)

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
      vim.g.gruvbox_material_background = 'medium'
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
      vim.keymap.set('', '<Leader>w', '<Cmd>HopWord<CR>')
      vim.keymap.set('', '<Leader>f', '<Cmd>HopChar1<CR>')
      -- vim.keymap.set('', '<Leader>l', '<Cmd>HopLine<CR>')
      -- vim.keymap.set('', '<Leader>c', '<Cmd>HopChar1CurrentLine<CR>')
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
      -- vim.opt.listchars:append('eol:↴')

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
          lualine_a = { {
            'filename',
            path = 3,
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
    'L3MON4D3/LuaSnip',
    tag = 'v1.*',
    disable = vscode,
    requires = { { 'rafamadriz/friendly-snippets' } },
    config = function()
      require('luasnip.loaders.from_vscode').lazy_load()
      require('luasnip').filetype_extend('ruby', { 'rails' })
      require('luasnip').filetype_extend('javascriptreact', { 'html' })
      require('luasnip').filetype_extend('typescriptreact', { 'html' })

      -- vim.keymap.set('i', '<Tab>', function()
      --   require('luasnip').expand_or_jump()
      -- end, {
      --   silent = true
      -- })
      --
      -- vim.keymap.set('i', '<S-Tab>', function()
      --   require('luasnip').jump(-1)
      -- end, {
      --   silent = true,
      --   noremap = true
      -- })
      --
      -- vim.keymap.set('s', '<Tab>', function()
      --   require('luasnip').jump(1)
      -- end, {
      --   silent = true,
      --   noremap = true
      -- })
      --
      -- vim.keymap.set('s', '<S-Tab>', function()
      --   require('luasnip').jump(-1)
      -- end, {
      --   silent = true,
      --   noremap = true
      -- })
    end,
  })
  use({
    'williamboman/mason-lspconfig.nvim',
    disable = vscode,
    requires = { { 'williamboman/mason.nvim' } },
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = {},
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
          null_ls.builtins.code_actions.gitsigns,
          null_ls.builtins.code_actions.refactoring,
          -- null_ls.builtins.code_actions.xo,
          -- completion
          null_ls.builtins.completion.spell,
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
          null_ls.builtins.diagnostics.zsh,
          -- formatting
          null_ls.builtins.formatting.beautysh,
          -- null_ls.builtins.formatting.deno_fmt,
          null_ls.builtins.formatting.erb_lint,
          -- null_ls.builtins.formatting.eslint,
          -- null_ls.builtins.formatting.eslint_d,
          null_ls.builtins.formatting.fish_indent,
          -- null_ls.builtins.formatting.prettier,
          null_ls.builtins.formatting.prettierd,
          null_ls.builtins.formatting.prismaFmt,
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
      { 'onsails/lspkind-nvim' },
      { 'saadparwaiz1/cmp_luasnip' },
      { 'williamboman/mason-lspconfig.nvim' },
    },
    config = function()
      local cmp = require('cmp')
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
          ['<Tab>'] = function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end,
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
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
          { name = 'nvim_lsp' },
          { name = 'nvim_lsp_signature_help' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'cmp_tabnine' },
        }),
        -- stylua: ignore end
        -- LuaFormatter on
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
      -- Mappings.
      -- See `:help vim.diagnostic.*` for documentation on any of the below functions
      -- local diagnostic_opts = {
      -- 	noremap = true,
      -- 	silent = true,
      -- }
      vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float, {
        noremap = true,
        silent = true,
        desc = 'diagnose open_float',
      })
      vim.keymap.set('n', '<Leader>[', vim.diagnostic.goto_prev, {
        noremap = true,
        silent = true,
        desc = 'diagnose goto_prev',
      })
      vim.keymap.set('n', '<Leader>]', vim.diagnostic.goto_next, {
        noremap = true,
        silent = true,
        desc = 'diagnose goto_next',
      })
      -- vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, { noremap = true, silent = true, desc = 'diagnose set_loclist'})

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
        -- 	noremap = true,
        -- 	silent = true,
        -- 	buffer = bufnr,
        -- }
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp delaration',
        })
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp definition',
        })
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp hover',
        })
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp implementation',
        })
        vim.keymap.set('n', '<C-k>k', vim.lsp.buf.signature_help, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp signature_help',
        })
        vim.keymap.set(
          'n',
          '<Leader>wa',
          vim.lsp.buf.add_workspace_folder,
          { noremap = true, silent = true, buffer = bufnr, desc = 'vim.lsp add_workspace_folder' }
        )
        vim.keymap.set(
          'n',
          '<Leader>wr',
          vim.lsp.buf.remove_workspace_folder,
          { noremap = true, silent = true, buffer = bufnr, desc = 'vim.lsp remove_workspace_folder' }
        )
        vim.keymap.set('n', '<Leader>wl', function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, { noremap = true, silent = true, buffer = bufnr, desc = 'vim.lsp list_workspace_folders' })
        vim.keymap.set('n', '<Leader>D', vim.lsp.buf.type_definition, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp type_definition',
        })
        vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp rename',
        })
        vim.keymap.set('n', '<F2>', vim.lsp.buf.rename, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp rename',
        })
        vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp code_action',
        })
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, {
          noremap = true,
          silent = true,
          buffer = bufnr,
          desc = 'vim.lsp references',
        })
        vim.keymap.set(
          'n',
          '<C-k>f',
          -- 0.7
          -- vim.lsp.buf.formatting,
          -- 0.8
          vim.lsp.buf.format,
          {
            noremap = true,
            silent = true,
            buffer = bufnr,
            desc = 'vim.lsp format',
          }
        )
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
      vim.keymap.set('n', '<Leader>dbb', function()
        require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))
      end, {
        desc = 'nvim-dap set_breakpoint with condition',
      })
      vim.keymap.set('n', '<Leader>dlp', function()
        require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
      end, {
        desc = 'nvim-dap set_breakpoint with log point message',
      })
      vim.keymap.set('n', '<Leader>ddr', function()
        require('dap').repl_open()
      end, {
        desc = 'nvim-dap repl_open()',
      })
      vim.keymap.set('n', '<Leader>ddl', function()
        require('dap').run_last()
      end, {
        desc = 'nvim-dap run_last{}',
      })
    end,
  })

  use({
    'rcarriga/nvim-dap-ui',
    requires = { 'mfussenegger/nvim-dap' },
  })

  use({
    'https://codeberg.org/esensar/nvim-dev-container',
    disable = vscode,
    requires = { 'nvim-treesitter/nvim-treesitter' },
  })

  use({
    'neovim/nvim-lspconfig',
    disable = vscode,
    requires = { { 'williamboman/mason-lspconfig.nvim' } },
  })

  use({
    'kylechui/nvim-surround',
    tag = '*', -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require('nvim-surround').setup({})
    end,
  })

  use({
    'kyazdani42/nvim-tree.lua',
    requires = { 'kyazdani42/nvim-web-devicons' },
    config = function()
      require('nvim-tree').setup({
        -- sync_root_with_cwd = true,
        respect_buf_cwd = true,
        update_focused_file = {
          enable = true,
          update_root = true,
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
      vim.keymap.set('n', '<A-q>', function()
        -- toggle `(find_file?: bool, no_focus?: bool, path?: string)`
        require('nvim-tree').find_file()
      end, {
        desc = 'find_file in nvim-tree',
      })
      -- local augroup = vim.api.nvim_create_augroup('nvim-tree', {})
      -- vim.api.nvim_create_autocmd({'BufEnter'}, {
      --   group = augroup,
      --   buffer = bufnr,
      --   callback = function()
      --     local view = require "nvim-tree.view"
      --     if view.is_visible() then
      --       require('nvim-tree').find_file(vim.api.nvim_buf_get_name(0))
      --     end
      --   end
      -- })
    end,
  })

  use({
    'nvim-treesitter/nvim-treesitter',
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
            node_decremental = '<BS>',
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
        patterns = { '.git', '_darcs', '.hg', '.bzr', '.svn', 'Makefile', 'package.json', 'Rakefile', 'selene.toml' },
        exclude_dirs = { '~/.config/nvim', '~/dev/src/github.com/shishi/dotfiles/nvim' },
        silent_chdir = false,
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
    'nvim-telescope/telescope-file-browser.nvim',
    disasble = vscode,
  })

  use({
    'nvim-telescope/telescope-fzf-native.nvim',
    disable = vscode,
    run = 'make',
  })
  use({
    'nvim-telescope/telescope-ui-select.nvim',
    disable = vscode,
  })

  use({
    'nvim-telescope/telescope.nvim',
    disable = vscode,
    tag = '0.1.0',
    -- or branch = '0.1.x',
    requires = {
      { 'ahmedkhalf/project.nvim' },
      { 'kyazdani42/nvim-web-devicons' },
      { 'nvim-lua/plenary.nvim' },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-treesitter/nvim-treesitter' },
    },
    config = function()
      require('telescope').setup({
        -- extensions = {
        --   file_browser = {
        --     hijack_netrw = true
        --   }
        -- }
      })
      require('telescope').load_extension('fzf')
      require('telescope').load_extension('file_browser')
      require('telescope').load_extension('ui-select')
      require('telescope').load_extension('projects')

      -- builtin
      vim.keymap.set('n', '<C-p>', function()
        require('telescope.builtin').find_files()
      end, {
        desc = 'telescope find files',
      })
      vim.keymap.set('n', '<C-k>g', function()
        require('telescope.builtin').live_grep()
      end, {
        desc = 'telescope live grep',
      })
      -- vim.keymap.set('n', '<Leader>tb', function()
      --   require('telescope.builtin').buffers()
      -- end)
      vim.keymap.set('n', '<C-k>b', function()
        require('telescope.builtin').buffers()
      end, {
        desc = 'telescope buffers',
      })
      vim.keymap.set('n', '<C-k>r', function()
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
      vim.keymap.set('n', '<Leader>tb', function()
        require('telescope.builtin').git_branches()
      end, {
        desc = 'telescope git branches',
      })
      vim.keymap.set('n', '<Leader>ts', function()
        require('telescope.builtin').git_status()
      end, {
        desc = 'telescope git status',
      })
      vim.keymap.set('n', '<Leader>tq', function()
        require('telescope.builtin').quickfix()
      end, {
        desc = 'telescope quickfix',
      })
      vim.keymap.set('n', '<Leader>tt', function()
        require('telescope.builtin').treesitter()
      end, {
        desc = 'telescope treesitter',
      })
      vim.keymap.set('n', '<Leader>tk', function()
        require('telescope.builtin').keymaps()
      end, {
        desc = 'telescope keymaps',
      })

      -- extensions
      vim.keymap.set('n', '<Leader>tf', function()
        require('telescope').extensions.file_browser.file_browser()
      end, {
        desc = 'telescope file browser',
      })
      vim.keymap.set('n', '<Leader>tp', function()
        require('telescope').extensions.projects.projects()
      end, {
        desc = 'telescop projects',
      })
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
      vim.keymap.set({ 'n', 't' }, '<C-k>t', '<Cmd>exe v:count1 . "ToggleTerm"<CR>', {
        silent = true,
      })
      vim.keymap.set({ 'n', 't' }, '<C-k>at', '<Cmd>ToggleTermToggleAll<CR>', {
        silent = true,
      })
      vim.keymap.set({ 'n', 't' }, '<C-k>pt', '<Cmd>10ToggleTerm direction=float<CR>', {
        silent = true,
      })

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
        noremap = true,
        silent = true,
        desc = 'lazygit',
      })
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

      vim.keymap.set('n', '<Leader>xx', '<Cmd>TroubleToggle<CR>', {
        silent = true,
        noremap = true,
      })
      vim.keymap.set('n', '<Leader>xw', '<Cmd>TroubleToggle workspace_diagnostics<CR>', {
        silent = true,
        noremap = true,
      })
      vim.keymap.set('n', '<Leader>xd', '<Cmd>TroubleToggle document_diagnostics<CR>', {
        silent = true,
        noremap = true,
      })
      vim.keymap.set('n', '<Leader>xl', '<Cmd>TroubleToggle loclist<CR>', {
        silent = true,
        noremap = true,
      })
      vim.keymap.set('n', '<Leader>xq', '<Cmd>TroubleToggle quickfix<CR>', {
        silent = true,
        noremap = true,
      })
      vim.keymap.set('n', 'gR', '<Cmd>TroubleToggle lsp_references<CR>', {
        silent = true,
        noremap = true,
      })
    end,
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
