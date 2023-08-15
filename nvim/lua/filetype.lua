-- golang
vim.api.nvim_create_augroup('ft_golang', { clear = true })
vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = 'ft_golang',
  pattern = { 'go', 'gomod', 'gowork', 'gotmpl' },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    -- vim.cmd('setlocal noexpandtab tabstop=4')
  end,
})
