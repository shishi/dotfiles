vim.loader.enable()

vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1

require('core')
require('keybind')
require('usercmd')
require('autocmd')
require('plugins')
require('filetype')
require('lsp')
