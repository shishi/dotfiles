-- vim.o: behaves like :let &{option-name}
-- vim.go: behaves like :let &g:{option-name}
-- vim.bo: behaves like :let &l:{option-name} for buffer-local options
-- vim.wo: behaves like :let &l:{option-name} for window-local options
-- leader key
vim.g.mapleader = ',';

-- encodings
-- vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = 'iso-2022-jp,euc-jp,sjis,utf-8'
-- vim.opt.fileformat = "unix"
vim.opt.fileformats = 'unix,dos,mac'

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
vim.opt.cindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
-- make sure to follow tabstop number
vim.opt.shiftwidth = 0
vim.opt.softtabstop = -1

-- integratiion
vim.opt.mouse = 'a'
vim.opt.mousemodel = 'popup'
vim.opt.shellslash = true
vim.opt.clipboard = 'unnamed,unnamedplus'
vim.g.clipboard = {
  name = 'win32yank',
  copy = {
    ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i',
    ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i'
  },
  paste = {
    ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o',
    ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o'
  },
  cache_enable = 0
}
vim.opt.modeline = true
vim.opt.modelines = 10

-- screen
vim.opt.scrolloff = 999
vim.opt.sidescroll = 1
vim.opt.sidescrolloff = 3
vim.opt.title = true

-- gui
vim.opt.guifont = 'UDEV Gothic NF:h12'

