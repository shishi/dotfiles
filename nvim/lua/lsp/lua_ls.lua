return {
  -- cmd = { 'lua-language-server' },
  -- filetypes = { 'lua' },
  -- capabilitiies = capabilities,
  -- on_attach = on_attach,
  on_init = function(client)
    if client.workspace_folders then
      local path = client.workspace_folders[1].name
      if
        path ~= vim.fn.stdpath('config')
        and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc'))
      then
        return
      end
    end

    client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
      runtime = { version = 'LuaJIT' },
      workspace = {
        checkThirdParty = false,
        -- library = {
        --   -- Load luvit types when the `vim.uv` word is found
        --   { path = 'luvit-meta/library', words = { 'vim%.uv' } },
        --   { path = 'wezterm-types', mods = { 'wezterm' } },
        -- },
        library = vim.list_extend(vim.api.nvim_get_runtime_file('lua', true), {
          '${3rd}/luv/library',
          '${3rd}/busted/library',
        }),
      },
    })
  end,

  settings = {
    Lua = {
      diagnostics = {
        unusedLocalExclude = { '_*' },
      },
    },
  },
}
