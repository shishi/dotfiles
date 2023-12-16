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

--ruby
vim.api.nvim_create_augroup('ft_ruby', { clear = true })
vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = 'ft_ruby',
  pattern = { 'ruby', 'rb', 'rbw', 'gemspec', 'config.ru', 'Gemfile', 'Rakefile', 'Vagrantfile' },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.api.nvim_create_user_command('FormatWithRubocop', function()
      vim.cmd('!rubocop -A -f quiet --stderr %')
    end, {})
    vim.api.nvim_create_user_command('FormatWithRufo', function()
      vim.cmd('!rufo %')
    end, {})
  end,
})

-- json
vim.api.nvim_create_augroup('ft_json', { clear = true })
vim.api.nvim_create_autocmd({ 'FileType' }, {
  group = 'ft_json',
  pattern = { 'json', 'jsonc' },
  callback = function()
    vim.opt_local.expandtab = true
    vim.opt_local.tabstop = 2
    vim.opt_local.filetype = 'jsonc'
  end,
})
