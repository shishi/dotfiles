-- Run with: nvim --headless -u NONE -l tests/nvim-clipboard.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. '/nvim')
vim.env.SSH_CONNECTION = 'clipboard-test'
local writes = {}
vim.api.nvim_ui_send = function(data)
  writes[#writes + 1] = data
end
vim.tty.request = function()
  error('paste must not query the terminal clipboard')
end
require('core')

vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'コピー', 'target' })
vim.cmd('normal! yyjp')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'コピー', 'target', 'コピー' }))
assert(writes[1] == '\27]52;c;' .. vim.base64.encode('コピー\n') .. '\27\\', 'copy must use OSC 52')
vim.cmd('normal! P')
assert(vim.api.nvim_buf_line_count(0) == 4, 'P must also paste without a terminal query')

vim.fn.setreg('+', { 'かな' }, 'v')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! "+p')
assert(vim.api.nvim_get_current_line() == 'xかな', 'explicit + paste must retain characterwise text')

vim.fn.setreg('+', { 'ab', 'cd' }, '\22' .. '2')
assert(vim.fn.getregtype('+') == '\22' .. '2', 'block width must survive the clipboard provider')
assert(vim.deep_equal(vim.fn.getreg('+', 1, true), { 'ab', 'cd' }))
print('Neovim clipboard: PASS')
