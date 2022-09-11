-- Automatically generated packer.nvim plugin loader code

if vim.api.nvim_call_function('has', {'nvim-0.5'}) ~= 1 then
  vim.api.nvim_command('echohl WarningMsg | echom "Invalid Neovim version for packer.nvim! | echohl None"')
  return
end

vim.api.nvim_command('packadd packer.nvim')

local no_errors, error_msg = pcall(function()

_G._packer = _G._packer or {}
_G._packer.inside_compile = true

local time
local profile_info
local should_profile = false
if should_profile then
  local hrtime = vim.loop.hrtime
  profile_info = {}
  time = function(chunk, start)
    if start then
      profile_info[chunk] = hrtime()
    else
      profile_info[chunk] = (hrtime() - profile_info[chunk]) / 1e6
    end
  end
else
  time = function(chunk, start) end
end

local function save_profiles(threshold)
  local sorted_times = {}
  for chunk_name, time_taken in pairs(profile_info) do
    sorted_times[#sorted_times + 1] = {chunk_name, time_taken}
  end
  table.sort(sorted_times, function(a, b) return a[2] > b[2] end)
  local results = {}
  for i, elem in ipairs(sorted_times) do
    if not threshold or threshold and elem[2] > threshold then
      results[i] = elem[1] .. ' took ' .. elem[2] .. 'ms'
    end
  end
  if threshold then
    table.insert(results, '(Only showing plugins that took longer than ' .. threshold .. ' ms ' .. 'to load)')
  end

  _G._packer.profile_output = results
end

time([[Luarocks path setup]], true)
local package_path_str = "/home/shishi/.cache/nvim/packer_hererocks/2.1.0-beta3/share/lua/5.1/?.lua;/home/shishi/.cache/nvim/packer_hererocks/2.1.0-beta3/share/lua/5.1/?/init.lua;/home/shishi/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/luarocks/rocks-5.1/?.lua;/home/shishi/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/luarocks/rocks-5.1/?/init.lua"
local install_cpath_pattern = "/home/shishi/.cache/nvim/packer_hererocks/2.1.0-beta3/lib/lua/5.1/?.so"
if not string.find(package.path, package_path_str, 1, true) then
  package.path = package.path .. ';' .. package_path_str
end

if not string.find(package.cpath, install_cpath_pattern, 1, true) then
  package.cpath = package.cpath .. ';' .. install_cpath_pattern
end

time([[Luarocks path setup]], false)
time([[try_loadstring definition]], true)
local function try_loadstring(s, component, name)
  local success, result = pcall(loadstring(s), name, _G.packer_plugins[name])
  if not success then
    vim.schedule(function()
      vim.api.nvim_notify('packer.nvim: Error running ' .. component .. ' for ' .. name .. ': ' .. result, vim.log.levels.ERROR, {})
    end)
  end
  return result
end

time([[try_loadstring definition]], false)
time([[Defining packer_plugins]], true)
_G.packer_plugins = {
  ["Comment.nvim"] = {
    config = { "\27LJ\2\2k\0\0\4\0\a\0\0146\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0029\1\4\0'\2\5\0'\3\6\0B\1\3\1K\0\1\0\b#%s\ash\bset\15Comment.ft\nsetup\fComment\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/Comment.nvim",
    url = "https://github.com/numToStr/Comment.nvim"
  },
  LuaSnip = {
    config = { "\27LJ\2\2ú\1\0\0\3\0\v\0\0276\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\5\0005\2\6\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\a\0005\2\b\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\t\0005\2\n\0B\0\3\1K\0\1\0\1\2\0\0\thtml\20typescriptreact\1\2\0\0\thtml\20javascriptreact\1\2\0\0\nrails\truby\20filetype_extend\fluasnip\14lazy_load luasnip.loaders.from_vscode\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/LuaSnip",
    url = "https://github.com/L3MON4D3/LuaSnip"
  },
  ["cmp-buffer"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-buffer",
    url = "https://github.com/hrsh7th/cmp-buffer"
  },
  ["cmp-cmdline"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-cmdline",
    url = "https://github.com/hrsh7th/cmp-cmdline"
  },
  ["cmp-nvim-lsp"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-nvim-lsp",
    url = "https://github.com/hrsh7th/cmp-nvim-lsp"
  },
  ["cmp-nvim-lsp-signature-help"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-nvim-lsp-signature-help",
    url = "https://github.com/hrsh7th/cmp-nvim-lsp-signature-help"
  },
  ["cmp-nvim-lua"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-nvim-lua",
    url = "https://github.com/hrsh7th/cmp-nvim-lua"
  },
  ["cmp-path"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-path",
    url = "https://github.com/hrsh7th/cmp-path"
  },
  cmp_luasnip = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp_luasnip",
    url = "https://github.com/saadparwaiz1/cmp_luasnip"
  },
  ["friendly-snippets"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/friendly-snippets",
    url = "https://github.com/rafamadriz/friendly-snippets"
  },
  ["gitsigns.nvim"] = {
    config = { "\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1€4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0À\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a]c\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a[c\tdiff\awo\bvimÂ\1\1\1\b\0\14\0\0236\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\0012\0\0€K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\1\texpr\2\0\a[c\1\0\1\texpr\2\0\a]c\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/gitsigns.nvim",
    url = "https://github.com/lewis6991/gitsigns.nvim"
  },
  ["gruvbox-material"] = {
    config = { "\27LJ\2\2@\0\0\2\0\3\0\0056\0\0\0009\0\1\0'\1\2\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/gruvbox-material",
    url = "https://github.com/sainnhe/gruvbox-material"
  },
  ["hop.nvim"] = {
    config = { "\27LJ\2\2Ô\1\0\0\4\0\f\0\0216\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0B\0\4\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0B\0\4\1K\0\1\0\22<Cmd>HopChar1<CR>\14<Leader>f\21<Cmd>HopWord<CR>\14<Leader>w\5\bset\vkeymap\bvim\1\0\1\tkeys\28etovxqpdygfblzhckisuran\nsetup\bhop\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/hop.nvim",
    url = "https://github.com/phaazon/hop.nvim"
  },
  ["lspkind-nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/lspkind-nvim",
    url = "https://github.com/onsails/lspkind-nvim"
  },
  ["lualine.nvim"] = {
    config = { "\27LJ\2\2^\0\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\1B\0\2\1K\0\1\0\foptions\1\0\0\1\0\1\ntheme\rcodedark\nsetup\flualine\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/lualine.nvim",
    url = "https://github.com/nvim-lualine/lualine.nvim"
  },
  ["mason-lspconfig.nvim"] = {
    config = { "\27LJ\2\2u\0\0\3\0\5\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0004\2\0\0=\2\4\1B\0\2\1K\0\1\0\21ensure_installed\1\0\1\27automatic_installation\2\nsetup\20mason-lspconfig\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/mason-lspconfig.nvim",
    url = "https://github.com/williamboman/mason-lspconfig.nvim"
  },
  ["mason.nvim"] = {
    config = { "\27LJ\2\0023\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\nmason\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/mason.nvim",
    url = "https://github.com/williamboman/mason.nvim"
  },
  ["null-ls.nvim"] = {
    config = { "\27LJ\2\2;\0\0\1\0\4\0\0066\0\0\0009\0\1\0009\0\2\0009\0\3\0B\0\1\1K\0\1\0\20formatting_sync\bbuf\blsp\bvimô\1\1\2\6\0\14\0\0259\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0006\4\6\0=\4\a\3=\1\b\3B\2\2\0016\2\2\0009\2\3\0029\2\t\2'\3\n\0005\4\v\0006\5\6\0=\5\a\4=\1\b\0043\5\f\0=\5\r\4B\2\3\1K\0\1\0\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\faugroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodê\a\1\0\a\0-\0•\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2)\0004\3!\0009\4\3\0009\4\4\0049\4\5\4>\4\1\0039\4\3\0009\4\4\0049\4\6\4>\4\2\0039\4\3\0009\4\4\0049\4\a\4>\4\3\0039\4\3\0009\4\4\0049\4\b\4>\4\4\0039\4\3\0009\4\t\0049\4\n\4>\4\5\0039\4\3\0009\4\v\0049\4\f\4>\4\6\0039\4\3\0009\4\v\0049\4\r\4>\4\a\0039\4\3\0009\4\v\0049\4\5\4>\4\b\0039\4\3\0009\4\v\0049\4\14\4>\4\t\0039\4\3\0009\4\v\0049\4\15\4>\4\n\0039\4\3\0009\4\v\0049\4\16\4>\4\v\0039\4\3\0009\4\v\0049\4\17\4>\4\f\0039\4\3\0009\4\v\0049\4\18\0049\4\19\0045\5\21\0005\6\20\0=\6\22\5B\4\2\2>\4\r\0039\4\3\0009\4\v\0049\4\23\4>\4\14\0039\4\3\0009\4\v\0049\4\24\4>\4\15\0039\4\3\0009\4\v\0049\4\25\4>\4\16\0039\4\3\0009\4\v\0049\4\26\4>\4\17\0039\4\3\0009\4\v\0049\4\27\4>\4\18\0039\4\3\0009\4\v\0049\4\28\4>\4\19\0039\4\3\0009\4\29\0049\4\30\4>\4\20\0039\4\3\0009\4\29\0049\4\r\4>\4\21\0039\4\3\0009\4\29\0049\4\31\4>\4\22\0039\4\3\0009\4\29\0049\4 \4>\4\23\0039\4\3\0009\4\29\0049\4!\4>\4\24\0039\4\3\0009\4\29\0049\4\16\4>\4\25\0039\4\3\0009\4\29\0049\4\"\4>\4\26\0039\4\3\0009\4\29\0049\4\18\0049\4\19\0045\5$\0005\6#\0=\6\22\5B\4\2\2>\4\27\0039\4\3\0009\4\29\0049\4\24\4>\4\28\0039\4\3\0009\4\29\0049\4%\4>\4\29\0039\4\3\0009\4\29\0049\4&\4>\4\30\0039\4\3\0009\4\29\0049\4\23\4>\4\31\0039\4\3\0009\4'\0049\4(\4>\4 \3=\3*\0023\3+\0=\3,\2B\1\2\1K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prismaFmt\14prettierd\16fish_indent\rbeautysh\15formatting\bzsh\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\nspell\15completion\16refactoring\rgitsigns\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/null-ls.nvim",
    url = "https://github.com/jose-elias-alvarez/null-ls.nvim"
  },
  ["nvim-autopairs"] = {
    config = { "\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\19nvim-autopairs\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-autopairs",
    url = "https://github.com/windwp/nvim-autopairs"
  },
  ["nvim-cmp"] = {
    config = { "\27LJ\2\2C\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\2\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4€-\1\0\0009\1\1\1B\1\1\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\21select_next_item\fvisibleX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5€-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\1\0\1\vselect\2\fconfirm\fvisibled\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintÎ\a\1\2\b\0&\0–\0016\2\0\0009\2\1\0029\2\2\2\18\3\1\0'\4\3\0'\5\4\0B\2\4\0015\2\5\0=\1\6\0026\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\n\0006\6\0\0009\6\v\0069\6\f\0069\6\r\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\14\0006\6\0\0009\6\v\0069\6\f\0069\6\15\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\16\0006\6\0\0009\6\v\0069\6\f\0069\6\17\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\18\0006\6\0\0009\6\v\0069\6\f\0069\6\19\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\20\0006\6\0\0009\6\v\0069\6\f\0069\6\21\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\22\0006\6\0\0009\6\v\0069\6\f\0069\6\23\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\24\0006\6\0\0009\6\v\0069\6\f\0069\6\25\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\26\0003\6\27\0\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\28\0006\6\0\0009\6\v\0069\6\f\0069\6\29\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\30\0006\6\0\0009\6\v\0069\6\f\0069\6\31\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5 \0006\6\0\0009\6\v\0069\6\f\0069\6!\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\"\0006\6\0\0009\6\v\0069\6\f\0069\6#\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5$\0006\6\0\0009\6\v\0069\6\f\0069\6%\6\18\a\2\0B\3\5\1K\0\1\0\15formatting\15<Leader>gf\15references\agr\16code_action\15<Leader>ca\vrename\15<Leader>rn\20type_definition\14<Leader>D\0\15<Leader>wl\28remove_workspace_folder\15<Leader>wr\25add_workspace_folder\15<Leader>wa\19signature_help\n<C-k>\19implementation\agi\nhover\6K\15definition\agd\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\vbuffer\1\0\2\vsilent\2\fnoremap\2\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\bapi\bvimn\0\1\4\2\6\0\f6\1\0\0'\2\1\0B\1\2\0028\1\0\0019\1\2\0015\2\3\0-\3\0\0=\3\4\2-\3\1\0=\3\5\2B\1\2\1K\0\1\0\1À\3À\14on_attach\18capabilitiies\1\0\0\nsetup\14lspconfig\frequireØ\t\1\0\b\0B\0¢\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\6\0005\3\4\0003\4\3\0=\4\5\3=\3\a\0024\3\0\0=\3\b\0029\3\t\0009\3\n\0039\3\v\0035\4\r\0009\5\t\0009\5\f\5)\6üÿB\5\2\2=\5\14\0049\5\t\0009\5\f\5)\6\4\0B\5\2\2=\5\15\0043\5\16\0=\5\17\0049\5\t\0009\5\18\5B\5\1\2=\5\19\0049\5\t\0009\5\20\5B\5\1\2=\5\21\0043\5\22\0=\5\23\4B\3\2\2=\3\t\0029\3\24\0009\3\25\0034\4\5\0005\5\26\0>\5\1\0045\5\27\0>\5\2\0045\5\28\0>\5\3\0045\5\29\0>\5\4\4B\3\2\2=\3\25\2B\1\2\0019\1\2\0009\1\30\1'\2\31\0005\3\"\0009\4\24\0009\4\25\0044\5\3\0005\6 \0>\6\1\0055\6!\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2$\0005\3%\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0034\4\3\0005\5&\0>\5\1\4=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2'\0005\3(\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0039\4\24\0009\4\25\0044\5\3\0005\6)\0>\6\1\0055\6*\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0016\1\0\0'\2+\0B\1\2\0029\1,\0016\2-\0009\2.\0029\2/\0029\0020\2B\2\1\0A\1\0\0025\0021\0006\3-\0009\0032\0039\0033\3'\0044\0'\0055\0006\6-\0009\0066\0069\0067\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\0058\0006\6-\0009\0066\0069\0069\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\5:\0006\6-\0009\0066\0069\6;\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\5<\0006\6-\0009\0066\0069\6=\6\18\a\2\0B\3\5\0013\3>\0006\4\0\0'\5?\0B\4\2\0029\4@\0044\5\3\0003\6A\0>\6\1\5B\4\2\0012\0\0€K\0\1\0\0\19setup_handlers\20mason-lspconfig\0\15setloclist\14<Leader>q\14goto_next\14<Leader>]\14goto_prev\14<Leader>[\15open_float\15diagnostic\14<Leader>e\6n\bset\vkeymap\1\0\2\vsilent\2\fnoremap\2\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\fsources\vconfig\t<CR>\0\n<C-e>\nabort\14<C-Space>\rcomplete\n<Tab>\0\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\bcmp\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-cmp",
    url = "https://github.com/hrsh7th/nvim-cmp"
  },
  ["nvim-dap"] = {
    config = { "\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequireŠ\3\1\0\4\0\22\0G6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\6\0003\3\a\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\6\0003\3\b\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\t\0003\3\n\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\t\0003\3\v\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\14\0003\3\15\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\16\0003\3\17\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\18\0003\3\19\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0B\0\4\1K\0\1\0\0\16<Leader>ddl\0\16<Leader>ddr\0\16<Leader>dlp\0\16<Leader>dbb\0\15<Leader>db\0\0\n<F12>\0\0\n<F10>\0\t<F5>\6n\bset\vkeymap\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-dap",
    url = "https://github.com/mfussenegger/nvim-dap"
  },
  ["nvim-dev-container"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-dev-container",
    url = "https://codeberg.org/esensar/nvim-dev-container"
  },
  ["nvim-lspconfig"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-lspconfig",
    url = "https://github.com/neovim/nvim-lspconfig"
  },
  ["nvim-surround"] = {
    config = { "\27LJ\2\2?\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\18nvim-surround\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-surround",
    url = "https://github.com/kylechui/nvim-surround"
  },
  ["nvim-treesitter"] = {
    config = { "\27LJ\2\2ò\2\0\0\4\0\14\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\1B\0\2\1K\0\1\0\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\t<BS>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter"
  },
  ["nvim-ts-autotag"] = {
    config = { "\27LJ\2\2A\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\20nvim-ts-autotag\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-ts-autotag",
    url = "https://github.com/windwp/nvim-ts-autotag"
  },
  ["nvim-ts-rainbow"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-ts-rainbow",
    url = "https://github.com/p00f/nvim-ts-rainbow"
  },
  ["nvim-web-devicons"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-web-devicons",
    url = "https://github.com/kyazdani42/nvim-web-devicons"
  },
  ["packer.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/packer.nvim",
    url = "https://github.com/wbthomason/packer.nvim"
  },
  ["plenary.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim"
  },
  ["refactoring.nvim"] = {
    config = { "\27LJ\2\2=\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\16refactoring\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/refactoring.nvim",
    url = "https://github.com/ThePrimeagen/refactoring.nvim"
  },
  ["telescope-file-browser.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-file-browser.nvim",
    url = "https://github.com/nvim-telescope/telescope-file-browser.nvim"
  },
  ["telescope-fzf-native.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-fzf-native.nvim",
    url = "https://github.com/nvim-telescope/telescope-fzf-native.nvim"
  },
  ["telescope-ui-select.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-ui-select.nvim",
    url = "https://github.com/nvim-telescope/telescope-ui-select.nvim"
  },
  ["telescope.nvim"] = {
    config = { "\27LJ\2\2D\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireC\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14live_grep\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireQ\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15treesitter\22telescope.builtin\frequire™\5\1\0\4\0%\0j6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\t\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\5\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\n\0B\0\2\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\15\0003\3\16\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\17\0003\3\18\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\19\0003\3\20\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\21\0003\3\22\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\23\0003\3\24\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\25\0003\3\26\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\27\0003\3\28\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\29\0003\3\30\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\31\0003\3 \0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2!\0003\3\"\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2#\0003\3$\0B\0\4\1K\0\1\0\0\15<Leader>tt\0\15<Leader>tq\0\16<Leader>tgb\0\15<Leader>tf\0\f<C-A-P>\0\15<Leader>tc\0\15<Leader>th\0\f<C-A-b>\0\15<Leader>tb\0\n<C-g>\0\n<C-p>\6n\bset\vkeymap\bvim\14ui-select\bfzf\19load_extension\15extensions\1\0\0\17file_browser\1\0\0\1\0\1\17hijack_netrw\2\nsetup\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope.nvim",
    url = "https://github.com/nvim-telescope/telescope.nvim"
  },
  ["vim-findroot"] = {
    config = { "\27LJ\2\0029\0\0\2\0\3\0\0056\0\0\0009\0\1\0)\1\0\0=\1\2\0K\0\1\0\28findroot_not_for_subdir\6g\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/vim-findroot",
    url = "https://github.com/mattn/vim-findroot"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: hop.nvim
time([[Config for hop.nvim]], true)
try_loadstring("\27LJ\2\2Ô\1\0\0\4\0\f\0\0216\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0B\0\4\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0B\0\4\1K\0\1\0\22<Cmd>HopChar1<CR>\14<Leader>f\21<Cmd>HopWord<CR>\14<Leader>w\5\bset\vkeymap\bvim\1\0\1\tkeys\28etovxqpdygfblzhckisuran\nsetup\bhop\frequire\0", "config", "hop.nvim")
time([[Config for hop.nvim]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\2ò\2\0\0\4\0\14\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\1B\0\2\1K\0\1\0\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\t<BS>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)
-- Config for: nvim-cmp
time([[Config for nvim-cmp]], true)
try_loadstring("\27LJ\2\2C\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\2\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4€-\1\0\0009\1\1\1B\1\1\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\21select_next_item\fvisibleX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5€-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\1\0\1\vselect\2\fconfirm\fvisibled\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintÎ\a\1\2\b\0&\0–\0016\2\0\0009\2\1\0029\2\2\2\18\3\1\0'\4\3\0'\5\4\0B\2\4\0015\2\5\0=\1\6\0026\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\n\0006\6\0\0009\6\v\0069\6\f\0069\6\r\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\14\0006\6\0\0009\6\v\0069\6\f\0069\6\15\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\16\0006\6\0\0009\6\v\0069\6\f\0069\6\17\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\18\0006\6\0\0009\6\v\0069\6\f\0069\6\19\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\20\0006\6\0\0009\6\v\0069\6\f\0069\6\21\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\22\0006\6\0\0009\6\v\0069\6\f\0069\6\23\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\24\0006\6\0\0009\6\v\0069\6\f\0069\6\25\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\26\0003\6\27\0\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\28\0006\6\0\0009\6\v\0069\6\f\0069\6\29\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\30\0006\6\0\0009\6\v\0069\6\f\0069\6\31\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5 \0006\6\0\0009\6\v\0069\6\f\0069\6!\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5\"\0006\6\0\0009\6\v\0069\6\f\0069\6#\6\18\a\2\0B\3\5\0016\3\0\0009\3\a\0039\3\b\3'\4\t\0'\5$\0006\6\0\0009\6\v\0069\6\f\0069\6%\6\18\a\2\0B\3\5\1K\0\1\0\15formatting\15<Leader>gf\15references\agr\16code_action\15<Leader>ca\vrename\15<Leader>rn\20type_definition\14<Leader>D\0\15<Leader>wl\28remove_workspace_folder\15<Leader>wr\25add_workspace_folder\15<Leader>wa\19signature_help\n<C-k>\19implementation\agi\nhover\6K\15definition\agd\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\vbuffer\1\0\2\vsilent\2\fnoremap\2\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\bapi\bvimn\0\1\4\2\6\0\f6\1\0\0'\2\1\0B\1\2\0028\1\0\0019\1\2\0015\2\3\0-\3\0\0=\3\4\2-\3\1\0=\3\5\2B\1\2\1K\0\1\0\1À\3À\14on_attach\18capabilitiies\1\0\0\nsetup\14lspconfig\frequireØ\t\1\0\b\0B\0¢\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\6\0005\3\4\0003\4\3\0=\4\5\3=\3\a\0024\3\0\0=\3\b\0029\3\t\0009\3\n\0039\3\v\0035\4\r\0009\5\t\0009\5\f\5)\6üÿB\5\2\2=\5\14\0049\5\t\0009\5\f\5)\6\4\0B\5\2\2=\5\15\0043\5\16\0=\5\17\0049\5\t\0009\5\18\5B\5\1\2=\5\19\0049\5\t\0009\5\20\5B\5\1\2=\5\21\0043\5\22\0=\5\23\4B\3\2\2=\3\t\0029\3\24\0009\3\25\0034\4\5\0005\5\26\0>\5\1\0045\5\27\0>\5\2\0045\5\28\0>\5\3\0045\5\29\0>\5\4\4B\3\2\2=\3\25\2B\1\2\0019\1\2\0009\1\30\1'\2\31\0005\3\"\0009\4\24\0009\4\25\0044\5\3\0005\6 \0>\6\1\0055\6!\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2$\0005\3%\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0034\4\3\0005\5&\0>\5\1\4=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2'\0005\3(\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0039\4\24\0009\4\25\0044\5\3\0005\6)\0>\6\1\0055\6*\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0016\1\0\0'\2+\0B\1\2\0029\1,\0016\2-\0009\2.\0029\2/\0029\0020\2B\2\1\0A\1\0\0025\0021\0006\3-\0009\0032\0039\0033\3'\0044\0'\0055\0006\6-\0009\0066\0069\0067\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\0058\0006\6-\0009\0066\0069\0069\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\5:\0006\6-\0009\0066\0069\6;\6\18\a\2\0B\3\5\0016\3-\0009\0032\0039\0033\3'\0044\0'\5<\0006\6-\0009\0066\0069\6=\6\18\a\2\0B\3\5\0013\3>\0006\4\0\0'\5?\0B\4\2\0029\4@\0044\5\3\0003\6A\0>\6\1\5B\4\2\0012\0\0€K\0\1\0\0\19setup_handlers\20mason-lspconfig\0\15setloclist\14<Leader>q\14goto_next\14<Leader>]\14goto_prev\14<Leader>[\15open_float\15diagnostic\14<Leader>e\6n\bset\vkeymap\1\0\2\vsilent\2\fnoremap\2\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\fsources\vconfig\t<CR>\0\n<C-e>\nabort\14<C-Space>\rcomplete\n<Tab>\0\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\bcmp\frequire\0", "config", "nvim-cmp")
time([[Config for nvim-cmp]], false)
-- Config for: nvim-dap
time([[Config for nvim-dap]], true)
try_loadstring("\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequireŠ\3\1\0\4\0\22\0G6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\6\0003\3\a\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\6\0003\3\b\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\t\0003\3\n\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\t\0003\3\v\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\14\0003\3\15\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\16\0003\3\17\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\18\0003\3\19\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0B\0\4\1K\0\1\0\0\16<Leader>ddl\0\16<Leader>ddr\0\16<Leader>dlp\0\16<Leader>dbb\0\15<Leader>db\0\0\n<F12>\0\0\n<F10>\0\t<F5>\6n\bset\vkeymap\bvim\0", "config", "nvim-dap")
time([[Config for nvim-dap]], false)
-- Config for: vim-findroot
time([[Config for vim-findroot]], true)
try_loadstring("\27LJ\2\0029\0\0\2\0\3\0\0056\0\0\0009\0\1\0)\1\0\0=\1\2\0K\0\1\0\28findroot_not_for_subdir\6g\bvim\0", "config", "vim-findroot")
time([[Config for vim-findroot]], false)
-- Config for: nvim-autopairs
time([[Config for nvim-autopairs]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\19nvim-autopairs\frequire\0", "config", "nvim-autopairs")
time([[Config for nvim-autopairs]], false)
-- Config for: nvim-ts-autotag
time([[Config for nvim-ts-autotag]], true)
try_loadstring("\27LJ\2\2A\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\20nvim-ts-autotag\frequire\0", "config", "nvim-ts-autotag")
time([[Config for nvim-ts-autotag]], false)
-- Config for: telescope.nvim
time([[Config for telescope.nvim]], true)
try_loadstring("\27LJ\2\2D\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireC\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14live_grep\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireQ\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15treesitter\22telescope.builtin\frequire™\5\1\0\4\0%\0j6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\t\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\5\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\n\0B\0\2\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\15\0003\3\16\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\17\0003\3\18\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\19\0003\3\20\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\21\0003\3\22\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\23\0003\3\24\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\25\0003\3\26\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\27\0003\3\28\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\29\0003\3\30\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\31\0003\3 \0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2!\0003\3\"\0B\0\4\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2#\0003\3$\0B\0\4\1K\0\1\0\0\15<Leader>tt\0\15<Leader>tq\0\16<Leader>tgb\0\15<Leader>tf\0\f<C-A-P>\0\15<Leader>tc\0\15<Leader>th\0\f<C-A-b>\0\15<Leader>tb\0\n<C-g>\0\n<C-p>\6n\bset\vkeymap\bvim\14ui-select\bfzf\19load_extension\15extensions\1\0\0\17file_browser\1\0\0\1\0\1\17hijack_netrw\2\nsetup\14telescope\frequire\0", "config", "telescope.nvim")
time([[Config for telescope.nvim]], false)
-- Config for: mason-lspconfig.nvim
time([[Config for mason-lspconfig.nvim]], true)
try_loadstring("\27LJ\2\2u\0\0\3\0\5\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0004\2\0\0=\2\4\1B\0\2\1K\0\1\0\21ensure_installed\1\0\1\27automatic_installation\2\nsetup\20mason-lspconfig\frequire\0", "config", "mason-lspconfig.nvim")
time([[Config for mason-lspconfig.nvim]], false)
-- Config for: nvim-surround
time([[Config for nvim-surround]], true)
try_loadstring("\27LJ\2\2?\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\18nvim-surround\frequire\0", "config", "nvim-surround")
time([[Config for nvim-surround]], false)
-- Config for: LuaSnip
time([[Config for LuaSnip]], true)
try_loadstring("\27LJ\2\2ú\1\0\0\3\0\v\0\0276\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\5\0005\2\6\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\a\0005\2\b\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\t\0005\2\n\0B\0\3\1K\0\1\0\1\2\0\0\thtml\20typescriptreact\1\2\0\0\thtml\20javascriptreact\1\2\0\0\nrails\truby\20filetype_extend\fluasnip\14lazy_load luasnip.loaders.from_vscode\frequire\0", "config", "LuaSnip")
time([[Config for LuaSnip]], false)
-- Config for: gruvbox-material
time([[Config for gruvbox-material]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\0056\0\0\0009\0\1\0'\1\2\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\bvim\0", "config", "gruvbox-material")
time([[Config for gruvbox-material]], false)
-- Config for: gitsigns.nvim
time([[Config for gitsigns.nvim]], true)
try_loadstring("\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1€4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0À\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a]c\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a[c\tdiff\awo\bvimÂ\1\1\1\b\0\14\0\0236\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\0012\0\0€K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\1\texpr\2\0\a[c\1\0\1\texpr\2\0\a]c\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0", "config", "gitsigns.nvim")
time([[Config for gitsigns.nvim]], false)
-- Config for: lualine.nvim
time([[Config for lualine.nvim]], true)
try_loadstring("\27LJ\2\2^\0\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\1B\0\2\1K\0\1\0\foptions\1\0\0\1\0\1\ntheme\rcodedark\nsetup\flualine\frequire\0", "config", "lualine.nvim")
time([[Config for lualine.nvim]], false)
-- Config for: Comment.nvim
time([[Config for Comment.nvim]], true)
try_loadstring("\27LJ\2\2k\0\0\4\0\a\0\0146\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0029\1\4\0'\2\5\0'\3\6\0B\1\3\1K\0\1\0\b#%s\ash\bset\15Comment.ft\nsetup\fComment\frequire\0", "config", "Comment.nvim")
time([[Config for Comment.nvim]], false)
-- Config for: refactoring.nvim
time([[Config for refactoring.nvim]], true)
try_loadstring("\27LJ\2\2=\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\16refactoring\frequire\0", "config", "refactoring.nvim")
time([[Config for refactoring.nvim]], false)
-- Config for: null-ls.nvim
time([[Config for null-ls.nvim]], true)
try_loadstring("\27LJ\2\2;\0\0\1\0\4\0\0066\0\0\0009\0\1\0009\0\2\0009\0\3\0B\0\1\1K\0\1\0\20formatting_sync\bbuf\blsp\bvimô\1\1\2\6\0\14\0\0259\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0006\4\6\0=\4\a\3=\1\b\3B\2\2\0016\2\2\0009\2\3\0029\2\t\2'\3\n\0005\4\v\0006\5\6\0=\5\a\4=\1\b\0043\5\f\0=\5\r\4B\2\3\1K\0\1\0\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\faugroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodê\a\1\0\a\0-\0•\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2)\0004\3!\0009\4\3\0009\4\4\0049\4\5\4>\4\1\0039\4\3\0009\4\4\0049\4\6\4>\4\2\0039\4\3\0009\4\4\0049\4\a\4>\4\3\0039\4\3\0009\4\4\0049\4\b\4>\4\4\0039\4\3\0009\4\t\0049\4\n\4>\4\5\0039\4\3\0009\4\v\0049\4\f\4>\4\6\0039\4\3\0009\4\v\0049\4\r\4>\4\a\0039\4\3\0009\4\v\0049\4\5\4>\4\b\0039\4\3\0009\4\v\0049\4\14\4>\4\t\0039\4\3\0009\4\v\0049\4\15\4>\4\n\0039\4\3\0009\4\v\0049\4\16\4>\4\v\0039\4\3\0009\4\v\0049\4\17\4>\4\f\0039\4\3\0009\4\v\0049\4\18\0049\4\19\0045\5\21\0005\6\20\0=\6\22\5B\4\2\2>\4\r\0039\4\3\0009\4\v\0049\4\23\4>\4\14\0039\4\3\0009\4\v\0049\4\24\4>\4\15\0039\4\3\0009\4\v\0049\4\25\4>\4\16\0039\4\3\0009\4\v\0049\4\26\4>\4\17\0039\4\3\0009\4\v\0049\4\27\4>\4\18\0039\4\3\0009\4\v\0049\4\28\4>\4\19\0039\4\3\0009\4\29\0049\4\30\4>\4\20\0039\4\3\0009\4\29\0049\4\r\4>\4\21\0039\4\3\0009\4\29\0049\4\31\4>\4\22\0039\4\3\0009\4\29\0049\4 \4>\4\23\0039\4\3\0009\4\29\0049\4!\4>\4\24\0039\4\3\0009\4\29\0049\4\16\4>\4\25\0039\4\3\0009\4\29\0049\4\"\4>\4\26\0039\4\3\0009\4\29\0049\4\18\0049\4\19\0045\5$\0005\6#\0=\6\22\5B\4\2\2>\4\27\0039\4\3\0009\4\29\0049\4\24\4>\4\28\0039\4\3\0009\4\29\0049\4%\4>\4\29\0039\4\3\0009\4\29\0049\4&\4>\4\30\0039\4\3\0009\4\29\0049\4\23\4>\4\31\0039\4\3\0009\4'\0049\4(\4>\4 \3=\3*\0023\3+\0=\3,\2B\1\2\1K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prismaFmt\14prettierd\16fish_indent\rbeautysh\15formatting\bzsh\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\nspell\15completion\16refactoring\rgitsigns\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\0", "config", "null-ls.nvim")
time([[Config for null-ls.nvim]], false)
-- Config for: mason.nvim
time([[Config for mason.nvim]], true)
try_loadstring("\27LJ\2\0023\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\nmason\frequire\0", "config", "mason.nvim")
time([[Config for mason.nvim]], false)

_G._packer.inside_compile = false
if _G._packer.needs_bufread == true then
  vim.cmd("doautocmd BufRead")
end
_G._packer.needs_bufread = false

if should_profile then save_profiles() end

end)

if not no_errors then
  error_msg = error_msg:gsub('"', '\\"')
  vim.api.nvim_command('echohl ErrorMsg | echom "Error in packer_compiled: '..error_msg..'" | echom "Please check your config for correctness" | echohl None')
end
