-- Run from the repository root:
-- SKKELUA_RUNTIME=/path/to/skkelua CMP_RUNTIME=/path/to/nvim-cmp \
--   nvim --headless -u NONE -n -i NONE -c 'luafile tests/nvim-cmp-skkelua.lua' -c 'qa!'
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root .. '/nvim')
for _, name in ipairs({ 'SKKELUA_RUNTIME', 'CMP_RUNTIME' }) do
  if not vim.env[name] then
    print(name .. ' must point to an existing plugin checkout')
    vim.cmd.cquit(1)
  end
  vim.opt.runtimepath:append(vim.env[name])
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local dictionary = directory .. '/SKK-JISYO'
vim.fn.writefile({
  ';; okuri-ari entries.',
  ';; okuri-nasi entries.',
  'にほん /日本;国名/二本;本数/',
}, dictionary)

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

local ok, err = pcall(function()
  local source = require('cmp_skkelua').new()
  local skk = require('skkelua')
  skk.config({
    globalDictionaries = { { dictionary, 'utf-8' } },
    userDictionary = directory .. '/user',
    completionRankFile = directory .. '/rank.json',
    sources = { 'skk_dictionary' },
    indicator = { enabled = false },
  })
  vim.cmd.runtime('plugin/skkelua.lua')
  local cmp = require('cmp')
  cmp.register_source('skkelua', source)
  cmp.setup({
    completion = { autocomplete = false },
    sources = { { name = 'skkelua' } },
    preselect = cmp.PreselectMode.None,
  })
  local failure
  local function feed(keys)
    vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), 't')
  end
  local function checked(fn)
    return function()
      local success, message = pcall(fn)
      if not success then
        failure = message
        vim.defer_fn(function()
          feed('<Esc>')
        end, 1)
      end
    end
  end
  vim.keymap.set(
    'i',
    '<F12>',
    checked(function()
      equal('😀▽にほん', vim.api.nvim_get_current_line())
      assert(source:is_available())
      cmp.complete()
      assert(
        vim.wait(2000, function()
          return #cmp.get_entries() == 2
        end),
        'cmp candidates did not arrive'
      )
      local entries = cmp.get_entries()
      equal('日本', entries[1].completion_item.label)
      equal('二本', entries[2].completion_item.label)
      source:resolve(entries[2].completion_item, function(item)
        equal('本数', item.documentation)
      end)
      cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
      cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
      assert(cmp.confirm({ select = false }))
      vim.defer_fn(function()
        feed('<F11>')
      end, 100)
    end)
  )
  vim.keymap.set(
    'i',
    '<F11>',
    checked(function()
      equal('😀二本', vim.api.nvim_get_current_line())
      assert(#skk.get_ranks() > 0, 'candidate was not learned')
      equal(#'😀二本', vim.api.nvim_win_get_cursor(0)[2])
      vim.defer_fn(function()
        feed('go<Esc>')
      end, 1)
    end)
  )
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '😀' })
  skk.handle('enable')
  -- cmp queues work on InsertEnter; send typed keys after that work is processed.
  vim.defer_fn(function()
    feed('Nihonn<F12>')
  end, 50)
  vim.fn.feedkeys('A', 'tx!')
  assert(not failure, failure)
  equal('😀二本ご', vim.api.nvim_get_current_line())
  -- The same reading must now put the confirmed candidate first.
  vim.keymap.set(
    'i',
    '<F10>',
    checked(function()
      local response
      source:complete({ context = require('cmp.context').new() }, function(result)
        response = result
      end)
      equal('二本', response.items[1].label)
      equal('二本;本数', response.items[1].data.word)
      equal(true, response.isIncomplete)
      vim.defer_fn(function()
        feed('<Esc>')
      end, 1)
    end)
  )
  skk.handle('enable')
  vim.defer_fn(function()
    feed('Nihonn<F10>')
  end, 50)
  vim.fn.feedkeys('A', 'tx!')
  assert(not failure, failure)
end)
vim.fn.delete(directory, 'rf')
if not ok then
  print(err)
  vim.cmd.cquit(1)
end
print('ok: skkelua cmp candidates, annotations, UTF-8 replacement, learning and continued input')
