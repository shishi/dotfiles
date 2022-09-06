-- ruby
vim.cmd([[
  augroup ruby_setting
    autocmd!
    autocmd BufNewFile,BufRead *.rb,*.rbw,*.gemspec Rakefile Vagrantfile setlocal filetype=ruby
    autocmd Filetype ruby setlocal ts=2
  augroup end
]])
