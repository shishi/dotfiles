-- Load the configuration with isolated XDG data/state, installed plugins, and
-- prettier available before running this integration check.
local function check()
  assert(
    vim.wait(3000, function()
      return vim.fn.exists(':Format') == 2
    end),
    'configuration did not finish loading'
  )
  assert(package.loaded.skkelua, 'skkelua must replace skkeleton')
  for _, plugin in ipairs(MiniDeps.get_session()) do
    local retired = { 'denops.vim', 'skkeleton', 'cmp-skkeleton', 'skkeleton_indicator.nvim', 'vim-gin' }
    assert(not vim.tbl_contains(retired, plugin.name), plugin.name .. ' is still enabled')
  end

  vim.cmd.enew()
  -- Deliver typed input after InsertEnter mappings have been installed.
  vim.defer_fn(function()
    vim.fn.feedkeys(vim.keycode('<C-j>ka<Esc>'), 't')
  end, 50)
  vim.fn.feedkeys('i', 'tx!')
  assert(vim.api.nvim_get_current_line() == 'か', 'Ctrl-J must enable kana input')
  vim.bo.modified = false

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'start', '日本語', 'end' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.fn.maparg('s', 'n', false, true).callback()
  local jab = require('jab')
  jab.jab(vim.tbl_extend('force', jab.cache.opts_general, { str = 'nihongo', label = 'q' }))
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'jab must find 日本語 with the shared Migemo dictionary')
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('K nihongo')
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, ':K must find 日本語')
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.api.nvim_feedkeys(vim.keycode('?nihongo<CR>'), 'xt', false)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, '? + Enter must use Migemo')
  vim.bo.modified = false

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ '日本語 alpha', '日本語 beta', 'English' }, dir .. '/sample.txt')
  require('telescope').extensions.migemo.migemo({ cwd = dir, default_text = 'nihongo' })
  local picker = require('telescope.actions.state').get_current_picker(vim.api.nvim_get_current_buf())
  local completed = false
  picker:register_completion_callback(function()
    completed = true
  end)
  assert(
    vim.wait(3000, function()
      return completed and picker.manager and picker.manager:num_results() == 2
    end),
    'Telescope must return both Japanese lines'
  )
  local prompt = picker.prompt_bufnr
  local refine = vim.fn.maparg('<C-Space>', 'i', false, true).callback
  assert(refine, 'Telescope fuzzy refine mapping is missing')
  refine()
  picker:set_prompt('日本語 beta')
  local refined = vim.wait(3000, function()
    return picker.manager and picker.manager:num_results() == 1
  end)
  assert(refined, 'fuzzy refinement failed: ' .. vim.inspect({
    prompt = picker:_get_prompt(),
    filtered = picker:_get_next_filtered_prompt(),
    results = picker.manager:num_results(),
    attached = picker._finder_attached,
    processed = require('telescope.actions.state').get_current_line(),
    mode = vim.fn.mode(),
  }))
  require('telescope.actions').close(prompt)

  local samples = {
    json = '{"x":1}',
    jsonc = '{"x":1}',
    yaml = 'x:    [1,2]',
    js = 'const x={a:1}',
    jsx = 'const X=()=> <div/>',
    ts = 'const x:number=1',
    tsx = 'const X=()=> <div/>',
    vue = '<template><div   class="x">hi</div></template>',
    css = 'a{color:red}',
    scss = '$x:red;a{color:$x}',
    less = '@x:red;a{color:@x}',
    html = '<div   class="x"><p>hi</p></div>',
    md = '-  item',
  }
  for extension, input in pairs(samples) do
    local path = dir .. '/format.' .. extension
    vim.cmd.edit(path)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { input })
    vim.cmd.write()
    assert(table.concat(vim.fn.readfile(path), '\n') ~= input, extension .. ' was not formatted on save')
    assert(require('conform').list_formatters(0)[1].name == 'prettier', extension .. ' must use prettier')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { input })
    vim.cmd('write!')
    assert(vim.fn.readfile(path)[1] == input, ':w! must skip formatting')
  end
  vim.cmd.edit(dir .. '/sample.lock')
  vim.bo.filetype = 'json'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '{"x":1}' })
  vim.cmd.write()
  assert(vim.fn.readfile(dir .. '/sample.lock')[1] == '{"x":1}', 'lock file must not be formatted')
  vim.fn.delete(dir, 'rf')
  print('Neovim Deno migration: PASS')
end

local ok, err = xpcall(check, debug.traceback)
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd.cquit()
end
vim.cmd('qa!')
