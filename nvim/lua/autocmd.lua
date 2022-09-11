-- reload init.lua and requires
vim.api.nvim_create_augroup('reload_lua_files', {
  clear = true
})
-- vim.api.nvim_clear_autocmds({
--   group = 'reload_lua_files'
-- })
vim.api.nvim_create_autocmd({'BufWritePost'}, {
  group = 'reload_lua_files',
  pattern = {'core.lua', 'keybind.lua', 'autocmd.lua', 'plugins.lua'},
  callback = function(table)
    -- print(vim.inspect(table))

    package.loaded['core'] = nil
    package.loaded['keybind'] = nil
    package.loaded['autocmd'] = nil
    package.loaded['plugins'] = nil
    require('core')
    require('keybind')
    require('autocmd')
    require('plugins')
    vim.api.nvim_command('PackerCompile')
  end
})

-- formatoptions
-- because using autocmmd many plugins overwrite
vim.api.nvim_create_augroup('formatoptions', {
  clear = true
})
vim.api.nvim_create_autocmd('Filetype', {
  group = 'formatoptions',
  pattern = {'*'},
  callback = function()
    vim.opt_local.formatoptions = 'tqj'
  end
})

-- -- ruby
-- vim.api.nvim_create_augroup('ruby_autocmds', {
--   clear = true
-- })
-- vim.api.nvim_create_autocmd({'BufNewFile', 'BufRead'}, {
--   group = 'ruby_autocmds',
--   pattern = {'*.rb', '*.rbw', '*.gemspec', 'Gemfile*', 'config.ru', 'Rakefile', 'Vagrantfile'},
--   callback = function()
--     vim.opt_local.filetype = 'ruby'
--     vim.opt_local.tapstop = 2
--   end
-- })

-- json
vim.api.nvim_create_augroup('json_autocmds', {
  clear = true
})
vim.api.nvim_create_autocmd({'BufNewFile', 'BufRead'}, {
  group = 'json_autocmds',
  pattern = "*.json",
  callback = function()
    vim.opt_local.filetype = 'jsonc'
  end
})

-- -- lsp
-- local augroup = vim.api.nvim_create_augroup("LspDocumentHighlight", {
--   clear = false
-- })
-- vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
--   group = augroup,
--   buffer = bufnr,
--   callback = function()
--     vim.lsp.buf.clear_references()
--     vim.lsp.buf.document_highlight()
--   end
-- })
--
