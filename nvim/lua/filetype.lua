-- golang
vim.api.nvim_create_augroup('ft_golang', { clear = true })
vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = 'ft_golang',
  pattern = 'go',
  -- callback = function()
  --   vim.opt_local.expandtab = false
  --   vim.opt_local.noexpandtab = true
  --   vim.opt_local.tabstop = 4
  -- end,
  command = 'setlocal noexpandtab tabstop=4',
})
