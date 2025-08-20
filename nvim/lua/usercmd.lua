-- open init.lua
vim.api.nvim_create_user_command('InitLua', function()
  vim.cmd.edit(vim.fn.stdpath('config') .. '/init.lua')
end, { desc = 'Open init.lua' })

-- reload init.lua and requires
-- create user command for reload config
vim.api.nvim_create_user_command('ReloadInits', function()
  package.loaded['core'] = nil
  package.loaded['keybind'] = nil
  package.loaded['usercmd'] = nil
  package.loaded['autocmd'] = nil
  package.loaded['plugins'] = nil
  package.loaded['filetype'] = nil
  package.loaded['lsp'] = nil

  -- for name, _ in pairs(package.loaded) do
  --   if name:match('^cnull') then
  --     package.loaded[name] = nil
  --   end
  -- end

  dofile(vim.env.MYVIMRC)
end, {})

-- Enhanced grep
vim.api.nvim_create_user_command('Grep', function(arg)
  local grep_cmd = 'silent grep! ' .. (arg.bang and '--fixed-strings -- ' or '') .. vim.fn.shellescape(arg.args, true)
  vim.cmd(grep_cmd)
  if vim.fn.getqflist({ size = true }).size > 0 then
    vim.cmd.copen()
  else
    vim.notify('no matches found', vim.log.levels.WARN)
    vim.cmd.cclose()
  end
end, { nargs = '+', bang = true, desc = 'Enhanced grep' })
