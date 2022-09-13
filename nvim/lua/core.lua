-- vim.o: behaves like :let &{option-name}
-- vim.go: behaves like :let &g:{option-name}
-- vim.bo: behaves like :let &l:{option-name} for buffer-local options
-- vim.wo: behaves like :let &l:{option-name} for window-local options
-- leader key
vim.g.mapleader = ',';

-- encodings
-- vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = 'utf-8,sjis,iso-2022-jp,euc-jp'
-- vim.opt.fileformat = "unix"
vim.opt.fileformats = 'unix,dos,mac'

-- ui
vim.opt.number = true
if vim.g.vscode then
else
  -- vim.api.nvim_command
  -- vim.cmd([[
  --   try
  --     colorscheme desert
  --     set background=dark
  --   catch /^Vim\%((\a\+)\)\=:E185/
  --     colorscheme default
  --     set background=dark
  --   endtry
  -- ]])
end

local signs = {
  Error = " ",
  Warn = " ",
  Hint = " ",
  Info = " "
}

for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, {
    icon = icon,
    text = icon,
    texthl = hl,
    numhl = hl
  })
end

vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
  -- -- Enable underline, use default values
  -- -- underline = true,
  -- -- Enable virtual text, override spacing to 4
  -- virtual_text = {
  --   prefix = '◯'
  --   -- spacing = 4
  -- },
  -- -- Use a function to dynamically turn signs off
  -- -- and on, using buffer local variables
  -- signs = function(namespace, bufnr)
  --   return vim.b[bufnr].show_signs == true
  -- end,
  update_in_insert = true
})

-- search
vim.opt.hlsearch = true
vim.opt.smartcase = true
vim.opt.wildmenu = true
vim.opt.wildmode = 'list:longest,full'
vim.opt.wildignorecase = true
vim.opt.completeopt = 'menu,menuone,preview,noinsert'

-- indent
vim.opt.cindent = true
vim.opt.expandtab = true
vim.opt.tabstop = 2
-- make sure to follow tabstop number
vim.opt.shiftwidth = 0
vim.opt.softtabstop = -1

-- screen
vim.opt.scrolloff = 999
vim.opt.sidescroll = 1
vim.opt.sidescrolloff = 3
vim.opt.title = true
-- '<' meaning left key when normal and visual mode
-- '>' meaning right key when normal and visual mode
-- '[' meaning left key when insert and replace mode
-- ']' meaning right key when insert and replace mode
-- vim.opt.whichwrap = '<,>,[,],b,s'

-- integratiion
vim.opt.mouse = 'a'
vim.opt.mousemodel = 'popup'
vim.opt.shellslash = true
vim.opt.clipboard = 'unnamed,unnamedplus'
vim.g.clipboard = {
  name = 'win32yank_wsl',
  copy = {
    ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i',
    ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i'
  },
  paste = {
    ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o --lf',
    ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o --lf'
  },
  cache_enable = 0
}
vim.opt.modeline = true
vim.opt.modelines = 10

-- gui
vim.opt.guifont = 'UDEV Gothic NF:h12'

