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
vim.keymap.set('n', 'x', '"_x')
vim.keymap.set('n', '<Leader><Leader>h', '<Cmd>nohlsearch<CR>')
vim.keymap.set('n', '<Leader>q', 'q')
vim.keymap.set('n', 'q', '<Nop>')

vim.cmd([[
  cabbrev Q qa
  cabbrev Q! qa!
  cabbrev W wa
]])

if vim.g.vscode then
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>Write<CR>')
  vim.keymap.set('n', '<Leader>;', '<Cmd>Tabclose<CR>')
  vim.keymap.set('n', '<Leader>n', '<Cmd>Tabprevious<CR>')
  vim.keymap.set('n', '<Leader>p', '<Cmd>Tabnext<CR>')
  vim.keymap.set('n', '<Leader><Leader>r', '<Cmd>call VSCodeNotify("workbench.action.openRecent")<CR>')
else
  vim.keymap.set('i', 'jj', '<ESC>')
  vim.keymap.set('i', 'kk', '<ESC>')
  vim.keymap.set('i', 'jk', '<ESC>')
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>write<CR>')
  -- buffer
  vim.keymap.set('n', '<Leader>;', '<Cmd>bp|bd #<CR>')
  vim.keymap.set('n', '<Leader>n', '<Cmd>bnext<CR>')
  vim.keymap.set('n', '<Leader>p', '<Cmd>bprevious<CR>')

  -- quickfix, grep
  -- batch replace on quickfix list (:cl or :copen)
  -- :cdo s/hoge/huag/gc
  vim.keymap.set('n', '<F3>', '<Cmd>cnext<CR>')
  vim.keymap.set('n', '<F4>', '<Cmd>cprevious<CR>')

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
vim.keymap.set('n', '<Leader><Leader>v', '<Cmd>vsplit<CR>')

-- keep selection after indent
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')
vim.keymap.set('v', '=', '=gb')

-- open configs
-- vim.keymap.set('n', '<Leader>`', '<Cmd>luafile $MYVIMRC<CR>')
vim.keymap.set('n', '<Leader><Leader>`', '<Cmd>tabnew ~/.config/nvim/<CR>')

-- terminal
-- vim.keymap.set('t', '<Esc><Esc>', [[<C-\><C-n>]])
-- vim.keymap.set('t', 'jj', [[<C-\><C-n>]])
vim.keymap.set('t', 'fj', [[<C-\><C-n>]])
