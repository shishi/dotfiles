local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:is_available()
  return require('skkelua').is_enabled()
end

function source:get_debug_name()
  return 'skkelua'
end

function source:get_keyword_pattern()
  return [=[\V\[ぁ-ゔァ-ヴｦ-ﾟ]]=]
end

function source:get_position_encoding_kind()
  return 'utf-8'
end

function source:complete(params, callback)
  local skk = require('skkelua')
  local candidates = skk.get_completion_result()
  local pre_edit = skk.get_pre_edit()
  local cursor = params.context.cursor
  -- cmp's col is a one-based byte position; skkelua's length API counts characters.
  local range = {
    start = { line = cursor.line, character = cursor.col - 1 - #pre_edit },
    ['end'] = { line = cursor.line, character = cursor.col - 1 },
  }
  local ranks = {}
  for _, rank in ipairs(skk.get_ranks()) do
    ranks[rank[1]] = rank[2]
  end
  local items = {}
  local global_rank = -1
  for _, candidate in ipairs(candidates) do
    for _, word in ipairs(candidate[2]) do
      local label = word:gsub(';.*$', '')
      local rank = ranks[word]
      if rank == nil then
        rank = global_rank
        global_rank = global_rank - 1
      end
      items[#items + 1] = {
        label = label,
        filterText = pre_edit,
        textEdit = { range = range, newText = label },
        data = { kana = candidate[1], word = word, rank = rank },
      }
    end
  end
  table.sort(items, function(a, b)
    return a.data.rank > b.data.rank
  end)
  for index, item in ipairs(items) do
    item.sortText = string.format('%08d', index)
  end
  callback({ items = items, isIncomplete = true })
end

function source:resolve(item, callback)
  item.documentation = item.data.word:match(';%s*(.*)$')
  callback(item)
end

function source:execute(item, callback)
  require('skkelua').complete_callback(item.data.kana, item.data.word)
  callback(item)
end

return source
