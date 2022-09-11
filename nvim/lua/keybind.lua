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
vim.keymap.set('n', 'x', '"_x')
vim.keymap.set('n', '<Leader><Leader>h', '<Cmd>nohlsearch<CR>')

if vim.g.vscode then
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>Write<CR>')
  vim.keymap.set('n', 'H', '<Cmd>Tabprevious<CR>')
  vim.keymap.set('n', 'L', '<Cmd>Tabnext<CR>')
  vim.keymap.set('n', '<Leader><Leader>r', '<Cmd>call VSCodeNotify("workbench.action.openRecent")<CR>')
else
  vim.keymap.set('i', 'jj', '<ESC>')
  vim.keymap.set('i', 'kk', '<ESC>')
  -- vim.keymap.set('n', '<Leader>s', '<Cmd>write<CR>')
  vim.keymap.set('n', 'H', '<Cmd>tabprevious<CR>')
  vim.keymap.set('n', 'L', '<Cmd>tabnext<CR>')
  -- set working directory is current editing file
  vim.keymap.set('n', '<Leader>~', '<Cmd>lcd %:p:h<CR>')
end

-- buffer
-- vim.keymap.set('n', '<Leader>q', '<Cmd>bdelete<CR>')
vim.keymap.set('n', '<Leader>n', '<Cmd>bnext<CR>')
vim.keymap.set('n', '<Leader>p', '<Cmd>bprevious<CR>')

-- split window
-- vim.keymap.set('n', '<Leader>h', '<Cmd>split<CR>')
vim.keymap.set('n', '<Leader>v', '<Cmd>vsplit<CR>')

-- keep selection after indent
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')
vim.keymap.set('v', '=', '=gb')

-- pairs
-- if vim.g.vscode then
-- else
--   vim.keymap.set('i', '{', '{}<LEFT>')
--   vim.keymap.set('i', '[', '[]<LEFT>')
--   vim.keymap.set('i', '(', '()<LEFT>')
--   vim.keymap.set('i', "'", "''<LEFT>")
--   vim.keymap.set('i', '"', '""<LEFT>')
-- end

-- open configs
-- vim.keymap.set('n', '<Leader>`', '<Cmd>luafile $MYVIMRC<CR>')
vim.keymap.set('n', '<Leader><Leader>`', '<Cmd>tabnew ~/.config/nvim/<CR>')

--  Packer
vim.cmd([[
  cabbrev ps PackerSync
  cabbrev pi PackerInstall
  cabbrev pc PackerCompile
  cabbrev pcl PackerClean
]])

-- telescope

-- luasnip
-- use nvim-cmp
-- vim.keymap.set('i', '<Tab>', function()
--   require('luasnip').expand_or_jump()
-- end, {
--   silent = true
-- })
--
-- vim.keymap.set('i', '<S-Tab>', function()
--   require('luasnip').jump(-1)
-- end, {
--   silent = true,
--   noremap = true
-- })
--
-- vim.keymap.set('s', '<Tab>', function()
--   require('luasnip').jump(1)
-- end, {
--   silent = true,
--   noremap = true
-- })
--
-- vim.keymap.set('s', '<S-Tab>', function()
--   require('luasnip').jump(-1)
-- end, {
--   silent = true,
--   noremap = true
-- })

-- nvim-dap
