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

vim.api.nvim_create_autocmd({ 'BufWritePre' }, {
  pattern = '*',
  callback = function(event)
    -- Skip for oil filetype
    if vim.bo[event.buf].filetype == 'oil' then
      return
    end

    local dir = vim.fs.dirname(event.file)
    local force = vim.v.cmdbang == 1
    if
      vim.fn.isdirectory(dir) == 0
      and (force or vim.fn.confirm('"' .. dir .. '" does not exist. Create?', '&Yes\n&No') == 1)
    then
      vim.fn.mkdir(vim.fn.iconv(dir, vim.opt.encoding:get(), vim.opt.termencoding:get()), 'p')
    end
  end,
  desc = 'Auto mkdir to save file',
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
-- local augroup_restore_cursor = vim.api.nvim_create_augroup('augroup_restore_cursor', {
--   clear = true
-- })
-- vim.api.nvim_create_autocmd({ 'BufReadPost' }, {
--   group = augroup_restore_cursor,
--   pattern = { '*' },
--   callback = function()
--     vim.api.nvim_exec('silent! normal! g`"zv', false)
--   end,
-- })

-- relative number in visual mode
local augroup_relativenumber_in_visual_mode = vim.api.nvim_create_augroup('augroup_relativenumber_in_visual_mode', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'ModeChanged' }, {
  group = augroup_relativenumber_in_visual_mode,
  pattern = { '*:[vV\x16]*' },
  callback = function()
    vim.opt.relativenumber = true
  end,
})
vim.api.nvim_create_autocmd({ 'ModeChanged' }, {
  group = augroup_relativenumber_in_visual_mode,
  pattern = { '[vV\x16]*:*' },
  callback = function()
    vim.opt.relativenumber = false
  end,
})

local augroup_nvim_ghost_user_autocommands = vim.api.nvim_create_augroup('augroup_nvim_ghost_user_autocommands', {
  clear = true,
})
vim.api.nvim_create_autocmd({ 'User' }, {
  group = augroup_nvim_ghost_user_autocommands,
  pattern = { 'github.com' },
  callback = function()
    print('hoge')
    vim.opt.filetype = 'markdown'
  end,
})
