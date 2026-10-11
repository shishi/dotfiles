local function live_grep(opts)
  local engine = require('luamigemo')
  local dictionary = assert(vim.api.nvim_get_runtime_file('migemo-compact-dict', false)[1])
  local migemo = engine.get(dictionary)
  local refining = false
  opts = vim.tbl_extend('keep', opts or {}, { prompt_title = 'Migemo' })
  opts.on_input_filter_cb = function(prompt)
    if not refining then
      return { prompt = migemo:query(prompt, engine.RXOP_PCRE) }
    end
  end
  local attach_mappings = opts.attach_mappings
  opts.attach_mappings = function(buf, map)
    map('i', '<C-Space>', function()
      refining = true
      require('telescope.actions').to_fuzzy_refine(buf)
    end)
    return not attach_mappings or attach_mappings(buf, map)
  end
  require('telescope.builtin').live_grep(opts)
end

return require('telescope').register_extension({ exports = { migemo = live_grep } })
