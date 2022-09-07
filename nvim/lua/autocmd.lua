-- ruby
vim.cmd([[
  augroup ruby_setting
    autocmd!
    autocmd BufNewFile,BufRead *.rb,*.rbw,*.gemspec,Gemfile*,Rakefile,Vagrantfile setlocal filetype=ruby
    autocmd Filetype ruby setlocal tabstop=2
  augroup end
]])

-- json
vim.cmd([[
  augroup json_setting
    autocmd!
    autocmd BufNewFile,BufRead *.json setlocal filetype=jsonc
  augroup end
]])
