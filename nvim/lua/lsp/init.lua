local add, now, later = MiniDeps.add, MiniDeps.now, MiniDeps.later

later(function()
  add({
    source = 'williamboman/mason-lspconfig.nvim',
    depends = { 'williamboman/mason.nvim' },
  })
  add({
    source = 'hrsh7th/cmp-nvim-lsp',
  })

  -- lsp common setting
  vim.lsp.config('*', {
    -- root_markers = { '.git' },
    capabilities = require('cmp_nvim_lsp').default_capabilities(),
  })

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

  local group = vim.api.nvim_create_augroup('lsp_attach', {})
  -- create keybind when attach
  vim.api.nvim_create_autocmd({ 'LspAttach' }, {
    group = group,
    callback = function(args)
      local bufnr = args.buf
      local client = assert(vim.lsp.get_client_by_id(args.data.client_id))

      if client:supports_method('textDocument/definition') then
        -- 定義ジャンプの設定（省略）
      end

      if client:supports_method('textDocument/formatting') then
        -- フォーマットの設定（省略）
      end

      -- code definitions, references
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {
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
      vim.keymap.set('n', 'gri', vim.lsp.buf.implementation, {
        buffer = bufnr,
        desc = 'vim.lsp.buf.implementation',
      })
      vim.keymap.set('n', 'gk', vim.lsp.buf.signature_help, {
        buffer = bufnr,
        desc = 'vim.lsp signature_help',
      })
      vim.keymap.set('n', 'grr', vim.lsp.buf.references, {
        buffer = bufnr,
        desc = 'vim.lsp.buf.references',
      })
      vim.keymap.set('n', 'grt', vim.lsp.buf.type_definition, {
        buffer = bufnr,
        desc = 'vim.lsp.buf.type_definition',
      })

      -- workspace
      vim.keymap.set('n', 'grwa', vim.lsp.buf.add_workspace_folder, {
        buffer = bufnr,
        desc = 'vim.lsp add_workspace_folder',
      })
      vim.keymap.set('n', 'grwr', vim.lsp.buf.remove_workspace_folder, {
        buffer = bufnr,
        desc = 'vim.lsp remove_workspace_folder',
      })
      vim.keymap.set('n', 'grwl', function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
      end, {
        buffer = bufnr,
        desc = 'vim.lsp list_workspace_folders',
      })

      -- code actions
      vim.keymap.set({ 'n', 'v' }, 'grn', vim.lsp.buf.rename, {
        buffer = bufnr,
        desc = 'vim.lsp rename',
      })
      vim.keymap.set({ 'n', 'v' }, '<F2>', vim.lsp.buf.rename, {
        buffer = bufnr,
        desc = 'vim.lsp rename',
      })
      vim.keymap.set({ 'n', 'v' }, 'gra', vim.lsp.buf.code_action, {
        buffer = bufnr,
        desc = 'vim.lsp code_action',
      })
      vim.keymap.set({ 'n', 'v' }, '<F7>', vim.lsp.buf.code_action, {
        buffer = bufnr,
        desc = 'vim.lsp code_action',
      })

      -- format
      vim.keymap.set('n', 'gq', vim.lsp.buf.format, {
        buffer = bufnr,
        desc = 'vim.lsp format',
      })
      vim.keymap.set('n', '<F8>', vim.lsp.buf.format, {
        buffer = bufnr,
        desc = 'vim.lsp format',
      })

      -- symbols through by treesitter
      vim.keymap.set('n', 'gW', vim.lsp.buf.workspace_symbol, {
        buffer = bufnr,
        desc = 'vim.lsp lsp_dynamic_workspace_symbols',
      })
      vim.keymap.set('n', 'gO', vim.lsp.buf.document_symbol, {
        buffer = bufnr,
        desc = 'vim.lsp lsp_document_symbols',
      })

      -- diagnostic
      vim.keymap.set('n', '<Leader>d', vim.diagnostic.open_float, {
        buffer = bufnr,
        desc = 'open diagnostic',
      })
      vim.keymap.set('n', '[d', function()
        vim.diagnostic.jump({ count = -1 })
      end, {
        buffer = bufnr,
        desc = 'goto prev diagnostic',
      })
      vim.keymap.set('n', ']d', function()
        vim.diagnostic.jump({ count = 1 })
      end, {
        buffer = bufnr,
        desc = 'goto next diagnostic ',
      })
      -- vim.keymap.set('n', '<Leader>E', function()
      --   require('telescope.builtin').diagnostics()
      -- end, {
      --   buffer = bufnr,
      --   desc = 'telescope diagnostics',
      -- })
      vim.keymap.set('n', 'grq', vim.diagnostic.setloclist, { desc = 'diagnose set_loclist' })
    end,
  })

  -- load lsp setting automatically
  local dirname = vim.fn.stdpath('config') .. '/lua/lsp'
  local lsp_names = {}

  for file, ftype in vim.fs.dir(dirname) do
    if ftype == 'file' and vim.endswith(file, '.lua') and file ~= 'init.lua' then
      local lsp_name = file:sub(1, -5) -- fname without '.lua'
      local ok, result = pcall(require, 'lsp.' .. lsp_name)
      if ok then
        vim.lsp.config(lsp_name, result)
        table.insert(lsp_names, lsp_name)
      else
        vim.notify('Error loading LSP: ' .. lsp_name .. '\n' .. result, vim.log.levels.WARN)
      end
    end
  end

  vim.lsp.enable(lsp_names)
  -- for lsp without settings
  -- vim.lsp.enable(require('mason-lspconfig').get_installed_servers())
end)
