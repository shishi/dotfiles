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
vim.keymap.set('n', ';', ':')
if vim.g.vscode then
  vim.keymap.set('', '<Leader>s', '<Cmd>Write<CR>')
  vim.keymap.set('', 'H', '<Cmd>Tabprevious<CR>')
  vim.keymap.set('', 'L', '<Cmd>Tabnext<CR>')
else
  vim.keymap.set('', '<Leader>s', '<Cmd>write<CR>')
  vim.keymap.set('', 'H', '<Cmd>tabprevious<CR>')
  vim.keymap.set('', 'L', '<Cmd>tabnext<CR>')
end
vim.keymap.set('', '<Leader><Leader>h', '<Cmd>nohlsearch<CR>')

-- buffer
vim.keymap.set('', '<Leader>q', '<Cmd>bdelete<CR>')
vim.keymap.set('n', '<Leader>n', '<Cmd>bnext<CR>')
vim.keymap.set('n', '<Leader>p', '<Cmd>bprevious<CR>')

-- split window
vim.keymap.set('n', '<Leader>h', '<Cmd>split<CR>')
vim.keymap.set('n', '<Leader>v', '<Cmd>vsplit<CR>')

-- pairs
if vim.g.vscode then
else
  vim.keymap.set('i', '{', '{}<LEFT>')
  vim.keymap.set('i', '[', '[]<LEFT>')
  vim.keymap.set('i', '(', '()<LEFT>')
  vim.keymap.set('i', "'", "''<LEFT>")
  vim.keymap.set('i', '"', '""<LEFT>')
end

-- set working directory is current editing file
vim.keymap.set('n', '<Leader>.', '<Cmd>lcd %:p:h<CR>')

-- open configs
vim.keymap.set('n', '<Leader>`', '<Cmd>luafile $MYVIMRC<CR>')
vim.keymap.set('n', '<Leader><Leader>`', '<Cmd>tabnew $MYVIMRC<CR>')

-- hop.nvim
vim.keymap.set('', '<Leader>w', '<Cmd>HopWord<CR>')
vim.keymap.set('', '<Leader>f', '<Cmd>HopChar1<CR>')
vim.keymap.set('', '<Leader>l', '<Cmd>HopLine<CR>')
vim.keymap.set('', '<Leader>c', '<Cmd>HopChar1CurrentLine<CR>')
