-- reload init.lua and requires
local augroup_reload_inits = vim.api.nvim_create_augroup('augroup_reload_inits', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = augroup_reload_inits,
  pattern = { 'core.lua', 'keybind.lua', 'autocmd.lua', 'plugins.lua' },
  callback = function()
    -- print(vim.inspect(table))

    package.loaded['core'] = nil
    package.loaded['keybind'] = nil
    package.loaded['autocmd'] = nil
    package.loaded['plugins'] = nil
    require('core')
    require('keybind')
    require('autocmd')
    require('plugins')

    vim.api.nvim_command('PackerSync')
  end,
})

-- create user command for reload config
vim.api.nvim_create_user_command('ReloadInits', function()
  for name, _ in pairs(package.loaded) do
    if name:match('^cnull') then
      package.loaded[name] = nil
    end
  end

  dofile(vim.fn.stdpath('config') .. '/init.lua')
end, {
  nargs = 0,
})

-- formatoptions
-- because using autocmmd many plugins overwrite
local augroup_formatoptions = vim.api.nvim_create_augroup('augroup_formatoptions', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'Filetype' }, {
  group = augroup_formatoptions,
  pattern = { '*' },
  callback = function()
    vim.opt_local.formatoptions = 'troqj'
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
local augroup_json = vim.api.nvim_create_augroup('augroup_json', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead' }, {
  group = augroup_json,
  pattern = '*.json',
  callback = function()
    vim.opt_local.filetype = 'jsonc'
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

-- grep quickfix
