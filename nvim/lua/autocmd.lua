-- reload init.lua and requires
-- create user command for reload config
vim.api.nvim_create_user_command('ReloadInits', function()
  package.loaded['core'] = nil
  package.loaded['keybind'] = nil
  package.loaded['autocmd'] = nil
  -- for name, _ in pairs(package.loaded) do
  --   if name:match('^cnull') then
  --     package.loaded[name] = nil
  --   end
  -- end

  dofile(vim.env.MYVIMRC)
end, {})

-- auto reload when edit plugins.lua
-- local augroup_reload_inits = vim.api.nvim_create_augroup('augroup_reload_inits', {
--   clear = true,
-- })
-- vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
--   group = augroup_reload_inits,
--   pattern = { 'plugins.lua' },
--   callback = function(arg)
--     -- require('packer').sync(arg.file)
--     -- vim.api.nvim_command('PackerSync')
--   end,
-- })

-- formatoptions
-- because using autocmmd many plugins overwrite
local augroup_formatoptions = vim.api.nvim_create_augroup('augroup_formatoptions', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'Filetype' }, {
  group = augroup_formatoptions,
  pattern = { '*' },
  callback = function()
    vim.opt_local.formatoptions = 'tcro/qnjM'
  end,
})

-- autosave when lost focus
local augroup_autosave = vim.api.nvim_create_augroup('augroup_autosave', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'FocusLost' }, {
  group = augroup_autosave,
  pattern = { '*' },
  callback = function()
    vim.cmd('silent! wa')
  end,
})

-- Restore cursor position
local augroup_restore_cursor = vim.api.nvim_create_augroup('augroup_restore_cursor', {})
vim.api.nvim_create_autocmd({ 'BufReadPost' }, {
  group = augroup_restore_cursor,
  pattern = { '*' },
  callback = function()
    vim.api.nvim_exec('silent! normal! g`"zv', false)
  end,
})

