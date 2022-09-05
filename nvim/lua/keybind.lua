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
if vim.g.vscode then
  vim.keymap.set('', '<Leader>s', '<Cmd>Write<CR>')
  vim.keymap.set('', 'H', '<Cmd>Tabprevious<CR>')
  vim.keymap.set('', 'L', '<Cmd>Tabnext<CR>')
else
  vim.keymap.set('', '<Leader>s', '<Cmd>write<CR>')
  vim.keymap.set('', 'H', '<Cmd>tabprevious<CR>')
  vim.keymap.set('', 'L', '<Cmd>tabnext<CR>')
end
vim.keymap.set('', '<Leader>q', 'ZZ')
vim.keymap.set('', '<Leader><Leader>h', '<Cmd>nohlsearch<CR>')

-- hop.nvim
vim.keymap.set('', '<Leader>w', '<Cmd>HopWord<CR>')
vim.keymap.set('', '<Leader>f', '<Cmd>HopChar1<CR>')
vim.keymap.set('', '<Leader>l', '<Cmd>HopLine<CR>')
vim.keymap.set('', '<Leader>c', '<Cmd>HopChar1CurrentLine<CR>')
