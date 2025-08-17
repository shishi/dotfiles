-- |     String value     |  Help page  |              Affected modes              | Vimscript equivalent |
-- |:--------------------:|:-----------:|:----------------------------------------:|:--------------------:|
-- | '' (an empty string) | mapmode-nvo | Normal, Visual, Select, Operator-pending | :map                 |
-- | 'n'                  | mapmode-n   | Normal                                   | :nmap                |
-- | 'v'                  | mapmode-v   | Visual and Select                        | :vmap                |
-- | 's'                  | mapmode-s   | Select                                   | :smap                |
-- | 'x'                  | mapmode-x   | Visual                                   | :xmap                |
-- | 'o'                  | mapmode-o   | Operator-pending                         | :omap                |
-- | '!'                  | mapmode-ic  | Insert and Command-line                  | :map!                |
-- | 'i'                  | mapmode-i   | Insert                                   | :imap                |
-- | 'l'                  | mapmode-l   | Insert, Command-line, Lang-Arg           | :lmap                |
-- | 'c'                  | mapmode-c   | Command-line                             | :cmap                |
-- | 't'                  | mapmode-t   | Terminal                                 | :tmap                |
-- core
vim.keymap.set({ 'n', 'v' }, ';', ':')
vim.keymap.set({ 'n', 'v' }, ':', ';')
vim.keymap.set('n', '<Leader><Leader>q', 'q', { desc = 'start recording' })
-- vim.keymap.set('n', 'q', '<Nop>')

vim.keymap.set('n', 'p', 'p`]', { desc = 'Paste and move the end' })
vim.keymap.set('n', 'P', 'P`]', { desc = 'Paste and move the end' })

-- vim.keymap.set({ 'n', 'x' }, 'x', '"_d', { desc = 'Delete into blackhole' })
vim.keymap.set({ 'n', 'x' }, 'x', '"_x', { desc = 'Delete into blackhole' })
vim.keymap.set('n', 'X', '"_D', { desc = 'Delete into blackhole' })
vim.keymap.set('o', 'x', 'd', { desc = 'Delete using x' })

vim.keymap.set('n', '<Enter>', 'o<ESC>')
vim.keymap.set('n', '<A-Enter>', 'O<ESC>')

vim.keymap.set('n', '<Leader><Leader>h', '<Cmd>nohlsearch<CR>', { desc = 'nohlsearch' })

vim.cmd([[
  cabbrev Q qa
  cabbrev Q! qa!
  cabbrev W wa
]])

if vim.g.vscode then
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>Write<CR>')
  vim.keymap.set('n', '<Leader>;', '<Cmd>Tabclose<CR>', { desc = 'close tab' })
  vim.keymap.set('n', '[t', '<Cmd>Tabprevious<CR>', { desc = 'previous tab' })
  vim.keymap.set('n', ']t', '<Cmd>Tabnext<CR>', { desc = 'next tab' })
  vim.keymap.set('n', '<Leader><Leader>r', '<Cmd>call VSCodeNotify("workbench.action.openRecent")<CR>')
else
  vim.keymap.set('i', 'jj', '<ESC>')
  vim.keymap.set('i', 'kk', '<ESC>')
  vim.keymap.set('i', 'jk', '<ESC>')
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>write<CR>')

  -- buffer
  vim.keymap.set('n', '<Leader>;', '<Cmd>bp|bd! #<CR>', { desc = 'close buffer without close window' })
  vim.keymap.set('n', '[b', '<Cmd>bprevious<CR>', { desc = 'previous buffer' })
  vim.keymap.set('n', ']b', '<Cmd>bnext<CR>', { desc = 'next buffer' })
  vim.keymap.set('n', '[t', '<Cmd>tabprevious<CR>', { desc = 'previous tab' })
  vim.keymap.set('n', ']t', '<Cmd>tabnext<CR>', { desc = 'next tab' })

  -- quickfix, grep
  -- batch replace on quickfix list (:cl or :copen)
  -- :cdo s/hoge/huag/gc
  vim.keymap.set('n', '[q', '<Cmd>cprevious<CR>', { desc = 'previous quickfix' })
  vim.keymap.set('n', ']q', '<Cmd>cnext<CR>', { desc = 'next quickfix' })
  vim.keymap.set('n', '<F4>', '<Cmd>cprevious<CR>', { desc = 'previous quickfix' })
  vim.keymap.set('n', '<F3>', '<Cmd>cnext<CR>', { desc = 'next quickfix' })
  vim.keymap.set('n', '<Leader>/', ':Grep ', { desc = 'Grep' })
  vim.keymap.set('n', '<Leader>*', ':Grep <c-r><c-w><CR>', { desc = 'Grep current word' })

  -- set working directory is current editing file
  vim.keymap.set('n', "<Leader>'", '<Cmd>lcd %:p:h<CR>')
end

-- first, last
vim.keymap.set({ 'n', 'v' }, 'H', '^')
vim.keymap.set({ 'n', 'v' }, 'L', '$')

-- Window
vim.keymap.set({ 'n', 't' }, '<A-h>', '<Cmd>wincmd h<CR>')
vim.keymap.set({ 'n', 't' }, '<A-j>', '<Cmd>wincmd j<CR>')
vim.keymap.set({ 'n', 't' }, '<A-k>', '<Cmd>wincmd k<CR>')
vim.keymap.set({ 'n', 't' }, '<A-l>', '<Cmd>wincmd l<CR>')
vim.keymap.set({ 'n', 't' }, '<A-H>', '<C-w><')
vim.keymap.set({ 'n', 't' }, '<A-J>', '<C-w>-')
vim.keymap.set({ 'n', 't' }, '<A-K>', '<C-w>+')
vim.keymap.set({ 'n', 't' }, '<A-L>', '<C-w>>')

-- split window
-- vim.keymap.set('n', '<Leader>h', '<Cmd>split<CR>')
vim.keymap.set('n', '<Leader><Leader>v', '<Cmd>vsplit<CR>', { desc = 'vsplit' })

-- keep selection after indent
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')
vim.keymap.set('v', '=', '=gb')

-- open configs
-- vim.keymap.set('n', '<Leader>`', '<Cmd>luafile $MYVIMRC<CR>')
vim.keymap.set('n', '<Leader><Leader>`', '<Cmd>tabnew ~/.config/nvim/init.lua<CR>', { desc = 'open init.lua' })

-- terminal
-- vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]])
-- vim.keymap.set('t', 'jj', [[<C-\><C-n>]])
vim.keymap.set('t', 'fj', [[<C-\><C-n>]], { desc = 'esc in terminal' })

-- input process for cant input area correctly with skkleton like claude code
vim.keymap.set({ 'n', 't', 'i' }, '<Leader>i', "<Cmd>call feedkeys(input(''), 'n')<CR>")
