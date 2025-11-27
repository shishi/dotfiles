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

-- auto mkdir when save file
vim.api.nvim_create_autocmd({ 'BufWritePre' }, {
  pattern = '*',
  callback = function(event)
    -- Skip for oil and mininotify
    local bufname = vim.api.nvim_buf_get_name(event.buf)
    if vim.bo[event.buf].filetype == 'oil' or bufname:match('^mini.+://') then
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

-- auto reload file when file changed outside of nvim
vim.api.nvim_create_autocmd({ 'WinEnter', 'FocusGained', 'BufEnter' }, {
  pattern = '*',
  command = 'checktime',
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

-- set cellwidth automatically
-- https://github.com/wancup/dotfiles/blob/ed785d6e283dc04aed456bb7d1b04a5cf38e6a6d/.config/nvim/lua/configs/autocmd.lua?plain=1#L33-L63
local augroup_set_cellwidth = vim.api.nvim_create_augroup('augroup_set_cellwidth', { clear = true })
local apply_cellwidths = function()
  vim.fn.setcellwidths({
    { 0x1F000, 0x1FFFF, 2 }, -- 🀀 ~ 🫸
    { 0x2190, 0x2193, 2 }, -- ← ~ ↓
    { 0x2025, 0x2026, 2 }, -- ‥ ~ …
    { 0x2460, 0x2473, 2 }, -- ① ~ ⑳
    { 0x2600, 0x27FF, 2 }, -- ☀ ~ ⛿
    { 0x2B05, 0x2B07, 2 }, -- ⬅ ~ ⬇
    { 0x25BC, 0x25BD, 2 }, -- ▼ ~ ▽
  })
end
local force_single_width_fts = {
  'yazi',
  'toggleterm',
}
vim.api.nvim_create_autocmd('FileType', {
  group = augroup_set_cellwidth,
  pattern = force_single_width_fts,
  callback = function()
    vim.fn.setcellwidths({})
  end,
})

vim.api.nvim_create_autocmd('WinClosed', {
  group = augroup_set_cellwidth,
  callback = function(event)
    local win_id = tonumber(event.match)
    if not win_id then
      return
    end
    local buf = vim.api.nvim_win_get_buf(win_id)
    if (not buf) or (not vim.api.nvim_buf_is_valid(buf)) then
      return
    end

    local filetype = vim.api.nvim_get_option_value('filetype', { buf = buf })
    if vim.tbl_contains(force_single_width_fts, filetype) then
      apply_cellwidths()
    end
  end,
})
