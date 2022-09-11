local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
    vim.cmd [[packadd packer.nvim]]
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
local status_ok, packer = pcall(require, "packer")
if not status_ok then
  return
end

if vim.g.vscode then
  packer.init({
    ensure_dependencies = true,
    opt_default = false,
    display = {
      noninteractive = true
    }
  })
else
  packer.init({
    ensure_dependencies = true,
    display = {
      noninteractive = false,
      open_fn = function()
        return require("packer.util").float({})
      end
    }
  })
end

local vscode = vim.g.vscode == 1
return packer.startup(function(use)
  use({'wbthomason/packer.nvim'})

  use({'kyazdani42/nvim-web-devicons'})
  use({'nvim-lua/plenary.nvim'})
  use({"nvim-telescope/telescope-file-browser.nvim"})
  use({'nvim-telescope/telescope-ui-select.nvim'})
  use({'rafamadriz/friendly-snippets'})

  use({
    'akinsho/bufferline.nvim',
    tag = 'v2.*',
    disable = true,
    requires = {{'kyazdani42/nvim-web-devicons'}},
    config = function()
      vim.opt.termguicolors = true
      require('bufferline').setup({})
    end
  })

  use({
    'glepnir/zephyr-nvim',
    disable = true,
    requires = {
      'nvim-treesitter/nvim-treesitter',
      opt = true
    }
  })

  use({
    'hrsh7th/nvim-cmp',
    disable = vscode,
    requires = {{'hrsh7th/cmp-buffer'}, {'hrsh7th/cmp-path'}, {'hrsh7th/cmp-cmdline'}, {'hrsh7th/cmp-nvim-lsp'},
                {'hrsh7th/cmp-nvim-lua'}, {'hrsh7th/cmp-nvim-lsp-signature-help'}, {'neovim/nvim-lspconfig'},
                {'onsails/lspkind-nvim'}, {'saadparwaiz1/cmp_luasnip'}, {'williamboman/mason-lspconfig.nvim'}},
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end
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
                select = true -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
              })
            else
              fallback() -- If you use vim-endwise, this fallback will behave the same as vim-endwise.
            end
          end
        }),

        -- LuaFormatter off
        -- stylua: ignore start
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'nvim_lsp_signature_help' },
          { name = 'luasnip' },
          { name = 'buffer' }
        })
        -- stylua: ignore end
        -- LuaFormatter on
      })

      -- Set configuration for specific filetype.
      cmp.setup.filetype('gitcommit', {
        -- LuaFormatter off
        -- stylua: ignore start
        sources = cmp.config.sources({
          { name = 'cmp_git' },
          { name = 'buffer' }
        })
        -- stylua: ignore end
        -- LuaFormatter on
      })

      -- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
      cmp.setup.cmdline('/', {
        mapping = cmp.mapping.preset.cmdline(),
        -- LuaFormatter off
        -- stylua: ignore start
        sources = {
          { name = 'buffer' }
        }
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
          { name = 'path' }
        })
        -- stylua: ignore end
        -- LuaFormatter on
      })

      -- Set up lspconfig.
      local capabilities = require('cmp_nvim_lsp').update_capabilities(vim.lsp.protocol.make_client_capabilities())
      -- Mappings.
      -- See `:help vim.diagnostic.*` for documentation on any of the below functions
      local diagnostic_opts = {
        noremap = true,
        silent = true
      }
      vim.keymap.set('n', '<Leader>e', vim.diagnostic.open_float, diagnostic_opts)
      vim.keymap.set('n', '<Leader>[', vim.diagnostic.goto_prev, diagnostic_opts)
      vim.keymap.set('n', '<Leader>]', vim.diagnostic.goto_next, diagnostic_opts)
      vim.keymap.set('n', '<Leader>q', vim.diagnostic.setloclist, diagnostic_opts)

      -- Use an on_attach function to only map the following keys
      -- after the language server attaches to the current buffer
      local on_attach = function(client, bufnr)
        -- Enable completion triggered by <c-x><c-o>
        vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

        -- Mappings.
        -- See `:help vim.lsp.*` for documentation on any of the below functions
        local lsp_bufopts = {
          noremap = true,
          silent = true,
          buffer = bufnr
        }
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, lsp_bufopts)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, lsp_bufopts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, lsp_bufopts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, lsp_bufopts)
        vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, lsp_bufopts)
        vim.keymap.set('n', '<Leader>wa', vim.lsp.buf.add_workspace_folder, lsp_bufopts)
        vim.keymap.set('n', '<Leader>wr', vim.lsp.buf.remove_workspace_folder, lsp_bufopts)
        vim.keymap.set('n', '<Leader>wl', function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, lsp_bufopts)
        vim.keymap.set('n', '<Leader>D', vim.lsp.buf.type_definition, lsp_bufopts)
        vim.keymap.set('n', '<Leader>rn', vim.lsp.buf.rename, lsp_bufopts)
        vim.keymap.set('n', '<Leader>ca', vim.lsp.buf.code_action, lsp_bufopts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, lsp_bufopts)
        vim.keymap.set('n', '<Leader>gf', vim.lsp.buf.formatting, lsp_bufopts)
      end

      require('mason-lspconfig').setup_handlers({ --
      -- The first entry (without a key) will be the default handler
      -- and will be called for each installed server that doesn't have
      -- a dedicated handler.
      function(server_name) -- default handler (optional)
        require('lspconfig')[server_name].setup({
          capabilitiies = capabilities,
          on_attach = on_attach
        })
      end --
      -- Next, you can provide targeted overrides for specific servers.
      -- ['rust_analyzer'] = function()
      --   require('rust-tools').setup {}
      -- end
      -- ['sumneko_lua'] = function()
      --   lspconfig.sumneko_lua.setup {
      --     settings = {
      --       Lua = {
      --         diagnostics = {
      --           globals = {'vim'}
      --         }
      --       }
      --     }
      --   }
      -- end
      })
    end
  })
  use({
    'jose-elias-alvarez/null-ls.nvim',
    disable = vscode,
    requires = {{'nvim-lua/plenary.nvim'}},
    config = function()
      local null_ls = require("null-ls")
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
            extra_args = {"--dialect", "postgres"}
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
            extra_args = { "--dialect", "postgres" }
          }),
          null_ls.builtins.formatting.stylelint,
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.formatting.taplo,
          null_ls.builtins.formatting.tidy,
          -- null_ls.builtins.formatting.trim_newlines,
          -- null_ls.builtins.formatting.trim_whitespace,
          -- hover
          null_ls.builtins.hover.printenv
        },
        -- stylua: ignore end
        -- LuaFormatter on
        on_attach = function(client, bufnr)
          if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({
              group = augroup,
              buffer = bufnr
            })
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = augroup,
              buffer = bufnr,
              callback = function()
                -- on 0.8, you should use vim.lsp.buf.format({ bufnr = bufnr }) instead
                vim.lsp.buf.formatting_sync()
              end
            })
          end
        end
      })
    end
  })

  use({
    'kylechui/nvim-surround',
    tag = "*", -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require('nvim-surround').setup({})
    end
  })

  use({
    "L3MON4D3/LuaSnip",
    tag = "v1.*",
    disable = vscode,
    requires = {{'rafamadriz/friendly-snippets'}},
    config = function()
      require('luasnip.loaders.from_vscode').lazy_load()
      require('luasnip').filetype_extend('ruby', {'rails'})
      require('luasnip').filetype_extend('javascriptreact', {'html'})
      require('luasnip').filetype_extend('typescriptreact', {'html'})

    end
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
            expr = true
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
            expr = true
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
          map({'o', 'x'}, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end
      })
    end
  })

  use({
    'mattn/vim-findroot',
    disable = vscode,
    config = function()
      vim.g.findroot_not_for_subdir = 0
    end
  })

  use({
    'mfussenegger/nvim-dap',
    disable = vscode,
    config = function()
      vim.keymap.set('n', '<F5>', function()
        require('dap').continue()
      end)
      vim.keymap.set('n', '<F10>', function()
        require('dap').step_over()
      end)
      vim.keymap.set('n', '<F10>', function()
        require('dap').step_into()
      end)
      vim.keymap.set('n', '<F12>', function()
        require('dap').step_out()
      end)
      vim.keymap.set('n', '<F12>', function()
        require('dap').step_out()
      end)
      vim.keymap.set('n', '<Leader>db', function()
        require('dap').toggle_breakpoint()
      end)
      vim.keymap.set('n', '<Leader>dbb', function()
        require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))
      end)
      vim.keymap.set('n', '<Leader>dlp', function()
        require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))
      end)
      vim.keymap.set('n', '<Leader>ddr', function()
        require('dap').repl_open()
      end)
      vim.keymap.set('n', '<Leader>ddl', function()
        require('dap').run_last()
      end)
    end
  })

  use({
    'neovim/nvim-lspconfig',
    disable = vscode,
    requires = {{'williamboman/mason-lspconfig.nvim'}}
  })

  use({
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup({})
      local ft = require('Comment.ft')
      ft.set('sh', '#%s')
    end
  })

  use({
    'nvim-lualine/lualine.nvim',
    disable = vscode,
    requires = {{'kyazdani42/nvim-web-devicons'}},
    config = function()
      require('lualine').setup({
        options = {
          theme = 'codedark'
        }
      })
    end
  })

  use({
    'nvim-treesitter/nvim-treesitter',
    requires = {{'p00f/nvim-ts-rainbow'}},
    run = function()
      require('nvim-treesitter.install').update({
        with_sync = true
      })
    end,
    config = function()
      require('nvim-treesitter.configs').setup({
        auto_install = true,
        highlight = {
          enable = true,
          -- disable = { "c", "rust" },
          additional_vim_regex_highlighting = false
        },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<CR>',
            scope_incremental = '<TAB>',
            node_incremental = '<CR>',
            node_decremental = '<BS>'
          }
        },
        indent = {
          enable = true
        },
        rainbow = {
          enable = true,
          -- disable = { "jsx", "cpp" }, list of languages you want to disable the plugin for
          extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
          max_file_lines = nil -- Do not enable for files with more than n lines, int
          -- colors = {}, -- table of hex strings
          -- termcolors = {} -- table of colour name strings
        }
      })

    end

  })

  use({
    'nvim-telescope/telescope-fzf-native.nvim',
    run = 'make'
  })

  use({
    'nvim-telescope/telescope.nvim',
    disable = vscode,
    tag = '0.1.0',
    -- or branch = '0.1.x',
    requires = {{'kyazdani42/nvim-web-devicons'}, {'nvim-lua/plenary.nvim'},
                {'nvim-telescope/telescope-ui-select.nvim'}, {'nvim-treesitter/nvim-treesitter'}},
    config = function()
      require('telescope').setup({
        extensions = {
          file_browser = {
            hijack_netrw = true
          }
        }
      })
      require('telescope').load_extension('fzf')
      require("telescope").load_extension('file_browser')
      require("telescope").load_extension("ui-select")

      vim.keymap.set('n', '<C-p>', function()
        require('telescope.builtin').find_files()
      end)
      vim.keymap.set('n', '<C-g>', function()
        require('telescope.builtin').live_grep()
      end)
      vim.keymap.set('n', '<Leader>tb', function()
        require('telescope.builtin').buffers()
      end)
      vim.keymap.set('n', '<C-A-b>', function()
        require('telescope.builtin').buffers()
      end)
      vim.keymap.set('n', '<Leader>th', function()
        require('telescope.builtin').command_history()
      end)
      vim.keymap.set('n', '<Leader>tc', function()
        require('telescope.builtin').commands()
      end)
      vim.keymap.set('n', '<C-A-P>', function()
        require('telescope.builtin').commands()
      end)
      vim.keymap.set('n', '<Leader>tf', function()
        require('telescope').extensions.file_browser.file_browser()
      end)
      vim.keymap.set('n', '<Leader>tgb', function()
        require('telescope.builtin').git_branches()
      end)
      vim.keymap.set('n', '<Leader>tq', function()
        require('telescope.builtin').quickfix()
      end)
      vim.keymap.set('n', '<Leader>tt', function()
        require('telescope.builtin').treesitter()
      end)

    end
  })

  use({
    'phaazon/hop.nvim',
    branch = 'v2', -- optional but strongly recommended
    config = function()
      -- you can configure Hop the way you like here; see :h hop-config
      require('hop').setup({
        keys = 'etovxqpdygfblzhckisuran'
      })
      vim.keymap.set('', '<Leader>w', '<Cmd>HopWord<CR>')
      vim.keymap.set('', '<Leader>f', '<Cmd>HopChar1<CR>')
      -- vim.keymap.set('', '<Leader>l', '<Cmd>HopLine<CR>')
      -- vim.keymap.set('', '<Leader>c', '<Cmd>HopChar1CurrentLine<CR>')

    end
  })

  use({
    'sainnhe/gruvbox-material',
    disable = vscode,
    requires = {
      'nvim-treesitter/nvim-treesitter',
      opt = true
    },
    config = function()
      vim.cmd([[colorscheme gruvbox-material]])
    end
  })

  use({
    'ThePrimeagen/refactoring.nvim',
    requires = {{'nvim-lua/plenary.nvim'}, {'nvim-treesitter/nvim-treesitter'}},
    config = function()
      require('refactoring').setup({})
    end
  })

  use({
    'williamboman/mason.nvim',
    disable = vscode,
    config = function()
      require('mason').setup()
    end
  })

  use({
    'williamboman/mason-lspconfig.nvim',
    disable = vscode,
    requires = {{'williamboman/mason.nvim'}},
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {},
        automatic_installation = true
      })
    end
  })

  use({
    'windwp/nvim-autopairs',
    disable = vscode,
    config = function()
      require('nvim-autopairs').setup({})
    end
  })

  use({
    'windwp/nvim-ts-autotag',
    disable = vscode,
    requires = {{'nvim-treesitter/nvim-treesitter'}},
    config = function()
      require('nvim-ts-autotag').setup({})
    end
  })

  -- packages except on github
  use({
    'https://codeberg.org/esensar/nvim-dev-container',
    requires = {'nvim-treesitter/nvim-treesitter'}
  })

  -- order by dependency

  if packer_bootstrap then
    require('packer').sync()
  end
end)
