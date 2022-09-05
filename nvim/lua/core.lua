-- vim.o: behaves like :let &{option-name}
-- vim.go: behaves like :let &g:{option-name}
-- vim.bo: behaves like :let &l:{option-name} for buffer-local options
-- vim.wo: behaves like :let &l:{option-name} for window-local options
-- leader key
vim.g.mapleader = ",";

-- encodings
-- vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = "iso-2022-jp,euc-jp,sjis,utf-8"
-- vim.opt.fileformat = "unix"
vim.opt.fileformats = "unix,dos,mac"

-- ui
vim.opt.number = true
-- OR vim.cmd([[colorscheme hogehoge]])
vim.api.nvim_command([[
  colorscheme desert
]])

-- search
vim.opt.hlsearch = true
vim.opt.smartcase = true

-- indent
-- vim.opt.autoindent = true
-- vim.opt.smartindent = true
vim.opt.cindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
-- make sure to follow tabstop number
vim.opt.shiftwidth = 0
vim.opt.softtabstop = -1

-- integratiion
vim.opt.mouse = "a"
vim.opt.shellslash = true
vim.opt.clipboard = "unnamed,unnamedplus"

vim.api.nvim_command([[
  autocmd BufNewFile,BufRead *.json setl ft=jsonc
]])
