-- vim.o: behaves like :let &{option-name}
-- vim.go: behaves like :let &g:{option-name}
-- vim.bo: behaves like :let &l:{option-name} for buffer-local options
-- vim.wo: behaves like :let &l:{option-name} for window-local options
-- leader key
vim.g.mapleader = ' '
vim.keymap.set('', '<BS>', '<Leader>', {
  remap = true,
  desc = 'second <Leader>',
})

-- encodings
-- vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = 'ucs-bom,utf-8,iso-2022-jp-3,euc-jp,cp932'
-- vim.opt.fileformat = "unix"
vim.opt.fileformats = 'unix,dos,mac'

-- undo
vim.opt.autowrite = true
vim.opt.undofile = true

-- ui
vim.opt.number = true
vim.opt.signcolumn = 'yes'
vim.opt.laststatus = 3
vim.opt.cursorline = true
-- vim.opt.winbar = '%F'
-- vim.opt.winbar = ''
vim.opt.termguicolors = true

-- vim.opt.relativenumber = true
-- if vim.g.vscode then
-- else
--   vim.api.nvim_command
--   vim.cmd([[
--     try
--       colorscheme desert
--       set background=dark
--     catch /^Vim\%((\a\+)\)\=:E185/
--       colorscheme default
--       set background=dark
--     endtry
--   ]])
-- end

-- search
vim.opt.hlsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.wildmenu = true
vim.opt.wildmode = 'list:longest,full'
vim.opt.wildignorecase = true
vim.opt.completeopt = 'menu,menuone,preview,noinsert'

if vim.fn.executable('rg') == 1 then
  vim.opt.grepprg = 'rg --vimgrep  --smart-case --hidden --glob "!.git"'
end

-- ref: `:NewGrep` in `:help grep`
vim.api.nvim_create_user_command('Grep', function(arg)
  local grep_cmd = 'silent grep! ' .. (arg.bang and '--fixed-strings -- ' or '') .. vim.fn.shellescape(arg.args, true)
  vim.cmd(grep_cmd)
  if vim.fn.getqflist({ size = true }).size > 0 then
    vim.cmd.copen()
  else
    vim.notify('no matches found', vim.log.levels.WARN)
    vim.cmd.cclose()
  end
end, { nargs = '+', bang = true, desc = 'Enhounced grep' })

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
vim.opt.clipboard = 'unnamedplus'

local utils = require('utils')

if utils.file_exists('/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe') then
  vim.g.clipboard = {
    name = 'win32yank_wsl',
    copy = {
      ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i',
      ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -i',
    },
    paste = {
      ['+'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o --lf',
      ['*'] = '/mnt/c/Users/shishi/scoop/apps/win32yank/current/win32yank.exe -o --lf',
    },
    cache_enable = 0,
  }
elseif vim.fn.getenv('SSH_TTY') ~= vim.NIL or vim.fn.getenv('USER') == 'app' then
  local function paste()
    return {
      vim.fn.split(vim.fn.getreg(''), '\n'),
      vim.fn.getregtype(''),
    }
  end

  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = paste,
      ['*'] = paste,
    },
  }
end

vim.opt.modeline = true
vim.opt.modelines = 10

-- gui
vim.opt.guifont = 'UDEV Gothic NF:h18'

if vim.g.neovide then
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_underline_automatic_scaling = true
  vim.g.neovide_refresh_rate = 120
  vim.g.neovide_remember_window_size = true
  vim.g.neovide_input_use_logo = true
  vim.g.neovide_cursor_animation_length = 0
end
