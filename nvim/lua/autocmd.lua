-- reload init.lua and requires
local augroup_reload_inits = vim.api.nvim_create_augroup('augroup_reload_inits', {
  clear = true
})
vim.api.nvim_create_autocmd({'BufWritePost'}, {
  group = augroup_reload_inits,
  pattern = {'core.lua', 'keybind.lua', 'autocmd.lua', 'plugins.lua'},
  callback = function(table)
    -- print(vim.inspect(table))

    package.loaded['core'] = nil
    package.loaded['keybind'] = nil
    package.loaded['autocmd'] = nil
    package.loaded['plugins'] = nil
    require('core')
    require('keybind')
    require('autocmd')
    require('plugins')
    vim.api.nvim_command('PackerCompile')
  end
})

-- formatoptions
-- because using autocmmd many plugins overwrite
local augroup_formatoptions = vim.api.nvim_create_augroup('augroup_formatoptions', {
  clear = true
})
vim.api.nvim_create_autocmd({'Filetype'}, {
  group = augroup_formatoptions,
  pattern = {'*'},
  callback = function()
    vim.opt_local.formatoptions = 'tqj'
  end
})

-- -- ruby
-- vim.api.nvim_create_augroup('ruby_autocmds', {
--   clear = true
-- })
-- vim.api.nvim_create_autocmd({'BufNewFile', 'BufRead'}, {
--   group = 'ruby_autocmds',
--   pattern = {'*.rb', '*.rbw', '*.gemspec', 'Gemfile*', 'config.ru', 'Rakefile', 'Vagrantfile'},
--   callback = function()
--     vim.opt_local.filetype = 'ruby'
--     vim.opt_local.tapstop = 2
--   end
-- })

-- json
local augroup_json = vim.api.nvim_create_augroup('augroup_json', {
  clear = true
})
vim.api.nvim_create_autocmd({'BufNewFile', 'BufRead'}, {
  group = augroup_json,
  pattern = "*.json",
  callback = function()
    vim.opt_local.filetype = 'jsonc'
  end
})

local augroup_restore_cursor = vim.api.nvim_create_augroup('augroup_restore_cursor', {})
-- Restore cursor position
vim.api.nvim_create_autocmd({ "BufReadPost" }, {
  group = augroup_restore_cursor,
    pattern = { "*" },
    callback = function()
        vim.api.nvim_exec('silent! normal! g`"zv', false)
    end,
})
