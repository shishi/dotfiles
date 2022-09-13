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
  ["diffview.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/diffview.nvim",
    url = "https://github.com/sindrets/diffview.nvim"
  },
  ["friendly-snippets"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/friendly-snippets",
    url = "https://github.com/rafamadriz/friendly-snippets"
  },
  ["gitsigns.nvim"] = {
    config = { "\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1€4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0À\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a]c\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a[c\tdiff\awo\bvimð\1\1\1\b\0\14\0\0236\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\0012\0\0€K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\2\texpr\2\tdesc\22gitsign prev_hunk\0\a[c\1\0\2\texpr\2\tdesc\22gitsign next_hunk\0\a]c\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/gitsigns.nvim",
    url = "https://github.com/lewis6991/gitsigns.nvim"
  },
  ["gruvbox-material"] = {
    config = { "\27LJ\2\2î\a\0\0\3\0\18\0'6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0'\1\4\0=\1\3\0006\0\0\0009\0\5\0'\1\a\0=\1\6\0006\0\0\0009\0\5\0)\1\1\0=\1\b\0006\0\0\0009\0\t\0009\0\n\0'\1\v\0+\2\1\0B\0\3\0016\0\0\0009\0\5\0)\1\1\0=\1\f\0006\0\0\0009\0\5\0)\1\1\0=\1\r\0006\0\0\0009\0\5\0'\1\15\0=\1\14\0006\0\0\0009\0\16\0'\1\17\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\fcolored-gruvbox_material_diagnostic_virtual_text/gruvbox_material_diagnostic_line_highlight/gruvbox_material_diagnostic_text_highlight©\4        augroup nord-theme-overrides\n          autocmd!\n          autocmd ColorScheme gruvbox-material highlight Folded ctermfg=LightGray guifg=#918d88\n          autocmd ColorScheme gruvbox-material highlight Folded ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight Folded cterm=italic gui=italic\n          autocmd ColorScheme gruvbox-material highlight SignColumn ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight DiagnosticSign ctermbg=235 guibg=#282828\n        augroup END\n      \14nvim_exec\bapi(gruvbox_material_better_performance\vmedium gruvbox_material_background\6g\tdark\15background\18termguicolors\bopt\bvim\0" },
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
  ["indent-blankline.nvim"] = {
    config = { "\27LJ\2\2á\3\0\0\2\0\b\0\0256\0\0\0009\0\1\0'\1\2\0B\0\2\0016\0\0\0009\0\1\0'\1\3\0B\0\2\0016\0\0\0009\0\1\0'\1\4\0B\0\2\0016\0\0\0009\0\1\0'\1\5\0B\0\2\0016\0\0\0009\0\1\0'\1\6\0B\0\2\0016\0\0\0009\0\1\0'\1\a\0B\0\2\1K\0\1\0Ahighlight IndentBlanklineIndent6 guibg=#C678DD gui=nocombineAhighlight IndentBlanklineIndent5 guibg=#61AFEF gui=nocombineAhighlight IndentBlanklineIndent4 guibg=#56B6C2 gui=nocombineAhighlight IndentBlanklineIndent3 guibg=#98C379 gui=nocombineAhighlight IndentBlanklineIndent2 guibg=#E5C07B gui=nocombineAhighlight IndentBlanklineIndent1 guibg=#E06C75 gui=nocombine\bcmd\bvimÉ\4\1\0\5\0\26\00006\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\3\0009\0\4\0'\1\5\0005\2\6\0B\0\3\0026\1\0\0009\1\3\0019\1\a\0015\2\b\0005\3\t\0=\0\n\0035\4\v\0=\4\f\0033\4\r\0=\4\14\3B\1\3\0016\1\0\0009\1\1\1+\2\2\0=\2\15\0016\1\0\0009\1\1\0019\1\16\1\18\2\1\0009\1\17\1'\3\18\0B\1\3\0016\1\0\0009\1\1\0019\1\16\1\18\2\1\0009\1\17\1'\3\19\0B\1\3\0016\1\20\0'\2\21\0B\1\2\0029\1\22\0015\2\24\0005\3\23\0=\3\25\2B\1\2\1K\0\1\0\24char_highlight_list\1\0\0\1\a\0\0\27IndentBlanklineIndent1\27IndentBlanklineIndent2\27IndentBlanklineIndent3\27IndentBlanklineIndent4\27IndentBlanklineIndent5\27IndentBlanklineIndent6\nsetup\21indent_blankline\frequire\feol:â†´\14space:â‹…\vappend\14listchars\tlist\rcallback\0\fpattern\1\2\0\0\6*\ngroup\1\0\0\1\2\0\0\16ColorScheme\24nvim_create_autocmd\1\0\1\nclear\2\29augroup_indent-blankline\24nvim_create_augroup\bapi\18termguicolors\bopt\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/indent-blankline.nvim",
    url = "https://github.com/lukas-reineke/indent-blankline.nvim"
  },
  ["lspkind-nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/lspkind-nvim",
    url = "https://github.com/onsails/lspkind-nvim"
  },
  ["lualine.nvim"] = {
    config = { "\27LJ\2\2¨\1\0\0\5\0\n\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0004\3\3\0005\4\3\0>\4\1\3=\3\5\2=\2\a\0015\2\b\0=\2\t\1B\0\2\1K\0\1\0\foptions\1\0\1\ntheme\21gruvbox-material\rsections\1\0\0\14lualine_a\1\0\0\1\2\1\0\rfilename\tpath\3\3\nsetup\flualine\frequire\0" },
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
    config = { "\27LJ\2\2I\0\0\3\1\6\0\t6\0\0\0009\0\1\0009\0\2\0009\0\3\0005\1\4\0-\2\0\0=\2\5\1B\0\2\1K\0\1\0\1À\nbufnr\1\0\0\vformat\bbuf\blsp\bvimò\1\1\2\6\1\r\0\0269\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\2'\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0012\0\0€K\0\1\0\0À\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_method°\b\1\0\b\0001\0œ\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0004\2\0\0B\0\3\0026\1\4\0'\2\5\0B\1\2\0029\2\6\0015\3-\0004\4!\0009\5\a\0019\5\b\0059\5\t\5>\5\1\0049\5\a\0019\5\b\0059\5\n\5>\5\2\0049\5\a\0019\5\b\0059\5\v\5>\5\3\0049\5\a\0019\5\b\0059\5\f\5>\5\4\0049\5\a\0019\5\r\0059\5\14\5>\5\5\0049\5\a\0019\5\15\0059\5\16\5>\5\6\0049\5\a\0019\5\15\0059\5\17\5>\5\a\0049\5\a\0019\5\15\0059\5\t\5>\5\b\0049\5\a\0019\5\15\0059\5\18\5>\5\t\0049\5\a\0019\5\15\0059\5\19\5>\5\n\0049\5\a\0019\5\15\0059\5\20\5>\5\v\0049\5\a\0019\5\15\0059\5\21\5>\5\f\0049\5\a\0019\5\15\0059\5\22\0059\5\23\0055\6\25\0005\a\24\0=\a\26\6B\5\2\2>\5\r\0049\5\a\0019\5\15\0059\5\27\5>\5\14\0049\5\a\0019\5\15\0059\5\28\5>\5\15\0049\5\a\0019\5\15\0059\5\29\5>\5\16\0049\5\a\0019\5\15\0059\5\30\5>\5\17\0049\5\a\0019\5\15\0059\5\31\5>\5\18\0049\5\a\0019\5\15\0059\5 \5>\5\19\0049\5\a\0019\5!\0059\5\"\5>\5\20\0049\5\a\0019\5!\0059\5\17\5>\5\21\0049\5\a\0019\5!\0059\5#\5>\5\22\0049\5\a\0019\5!\0059\5$\5>\5\23\0049\5\a\0019\5!\0059\5%\5>\5\24\0049\5\a\0019\5!\0059\5\20\5>\5\25\0049\5\a\0019\5!\0059\5&\5>\5\26\0049\5\a\0019\5!\0059\5\22\0059\5\23\0055\6(\0005\a'\0=\a\26\6B\5\2\2>\5\27\0049\5\a\0019\5!\0059\5\28\5>\5\28\0049\5\a\0019\5!\0059\5)\5>\5\29\0049\5\a\0019\5!\0059\5*\5>\5\30\0049\5\a\0019\5!\0059\5\27\5>\5\31\0049\5\a\0019\5+\0059\5,\5>\5 \4=\4.\0033\4/\0=\0040\3B\2\2\0012\0\0€K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prismaFmt\14prettierd\16fish_indent\rbeautysh\15formatting\bzsh\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\nspell\15completion\16refactoring\rgitsigns\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\18LspFormatting\24nvim_create_augroup\bapi\bvim\0" },
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
    config = { "\27LJ\2\2C\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\2\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4€-\1\0\0009\1\1\1B\1\1\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\21select_next_item\fvisibleX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5€-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\1\0\1\vselect\2\fconfirm\fvisible0\0\1\2\0\2\0\a9\1\0\0\6\1\1\0X\1\2€+\1\1\0X\2\1€+\1\2\0L\1\2\0\fnull-ls\tnameS\1\1\4\0\b\0\n6\1\0\0009\1\1\0019\1\2\0019\1\3\0015\2\5\0003\3\4\0=\3\6\2=\0\a\2B\1\2\1K\0\1\0\nbufnr\vfilter\1\0\0\0\vformat\bbuf\blsp\bvim\27\0\0\2\2\0\0\4-\0\0\0-\1\1\0B\0\2\1K\0\1\0\1\0\1Àd\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintú\14\1\2\a\2>\0Æ\0019\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\0025\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0016\2\2\0009\2\3\0029\2\r\2\18\3\1\0'\4\14\0'\5\15\0B\2\4\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\19\0006\5\2\0009\5\20\0059\5\21\0059\5\22\0055\6\23\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\24\0006\5\2\0009\5\20\0059\5\21\0059\5\25\0055\6\26\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\27\0006\5\2\0009\5\20\0059\5\21\0059\5\28\0055\6\29\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\30\0006\5\2\0009\5\20\0059\5\21\0059\5\31\0055\6 \0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4!\0006\5\2\0009\5\20\0059\5\21\0059\5\"\0055\6#\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4$\0006\5\2\0009\5\20\0059\5\21\0059\5%\0055\6&\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4'\0006\5\2\0009\5\20\0059\5\21\0059\5(\0055\6)\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4*\0003\5+\0005\6,\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4-\0006\5\2\0009\5\20\0059\5\21\0059\5.\0055\6/\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0040\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0062\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0043\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0064\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0045\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0067\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0048\0006\5\2\0009\5\20\0059\5\21\0059\0059\0055\6:\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4;\0006\5\2\0009\5\20\0059\5\21\0059\5<\0055\6=\0=\1\a\6B\2\5\0012\0\0€K\0\1\0\3À\2À\1\0\3\vsilent\2\tdesc\19vim.lsp format\fnoremap\2\vformat\v<C-k>f\1\0\3\vsilent\2\tdesc\23vim.lsp references\fnoremap\2\15references\agr\1\0\3\vsilent\2\tdesc\24vim.lsp code_action\fnoremap\2\16code_action\15<Leader>ca\1\0\3\vsilent\2\tdesc\19vim.lsp rename\fnoremap\2\t<F2>\1\0\3\vsilent\2\tdesc\19vim.lsp rename\fnoremap\2\vrename\15<Leader>rn\1\0\3\vsilent\2\tdesc\28vim.lsp type_definition\fnoremap\2\20type_definition\14<Leader>D\1\0\3\vsilent\2\tdesc#vim.lsp list_workspace_folders\fnoremap\2\0\15<Leader>wl\1\0\3\vsilent\2\tdesc$vim.lsp remove_workspace_folder\fnoremap\2\28remove_workspace_folder\15<Leader>wr\1\0\3\vsilent\2\tdesc!vim.lsp add_workspace_folder\fnoremap\2\25add_workspace_folder\15<Leader>wa\1\0\3\vsilent\2\tdesc\27vim.lsp signature_help\fnoremap\2\19signature_help\v<C-k>k\1\0\3\vsilent\2\tdesc\27vim.lsp implementation\fnoremap\2\19implementation\agi\1\0\3\vsilent\2\tdesc\18vim.lsp hover\fnoremap\2\nhover\6K\1\0\3\vsilent\2\tdesc\23vim.lsp definition\fnoremap\2\15definition\agd\1\0\3\vsilent\2\tdesc\23vim.lsp delaration\fnoremap\2\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\rcallback\0\1\0\0\1\2\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodV\0\1\4\3\4\0\n-\1\0\0008\1\0\0019\1\0\0015\2\1\0-\3\1\0=\3\2\2-\3\2\0=\3\3\2B\1\2\1K\0\1\0\5À\1À\4À\14on_attach\18capabilitiies\1\0\0\nsetupˆ\1\0\0\6\1\v\0\14-\0\0\0009\0\0\0009\0\1\0005\1\t\0005\2\a\0005\3\5\0005\4\3\0005\5\2\0=\5\4\4=\4\6\3=\3\b\2=\2\n\1B\0\2\1K\0\1\0\5À\rsettings\1\0\0\bLua\1\0\0\16diagnostics\1\0\0\fglobals\1\0\0\1\2\0\0\bvim\nsetup\16sumneko_luaù\n\1\0\t\0J\0£\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\6\0005\3\4\0003\4\3\0=\4\5\3=\3\a\0024\3\0\0=\3\b\0029\3\t\0009\3\n\0039\3\v\0035\4\r\0009\5\t\0009\5\f\5)\6üÿB\5\2\2=\5\14\0049\5\t\0009\5\f\5)\6\4\0B\5\2\2=\5\15\0043\5\16\0=\5\17\0049\5\t\0009\5\18\5B\5\1\2=\5\19\0049\5\t\0009\5\20\5B\5\1\2=\5\21\0043\5\22\0=\5\23\4B\3\2\2=\3\t\0029\3\24\0009\3\25\0034\4\5\0005\5\26\0>\5\1\0045\5\27\0>\5\2\0045\5\28\0>\5\3\0045\5\29\0>\5\4\4B\3\2\2=\3\25\2B\1\2\0019\1\2\0009\1\30\1'\2\31\0005\3\"\0009\4\24\0009\4\25\0044\5\3\0005\6 \0>\6\1\0055\6!\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2$\0005\3%\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0034\4\3\0005\5&\0>\5\1\4=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2'\0005\3(\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0039\4\24\0009\4\25\0044\5\3\0005\6)\0>\6\1\0055\6*\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0016\1\0\0'\2+\0B\1\2\0029\1,\0016\2-\0009\2.\0029\2/\0029\0020\2B\2\1\0A\1\0\0026\2-\0009\0021\0029\0022\2'\0033\0'\0044\0006\5-\0009\0055\0059\0056\0055\0067\0B\2\5\0016\2-\0009\0021\0029\0022\2'\0033\0'\0048\0006\5-\0009\0055\0059\0059\0055\6:\0B\2\5\0016\2-\0009\0021\0029\0022\2'\0033\0'\4;\0006\5-\0009\0055\0059\5<\0055\6=\0B\2\5\0013\2>\0006\3-\0009\3?\0039\3@\3'\4A\0004\5\0\0B\3\3\0023\4B\0006\5\0\0'\6C\0B\5\2\0026\6\0\0'\aD\0B\6\2\0029\6E\0065\aH\0003\bF\0>\b\1\a3\bG\0=\bI\aB\6\2\0012\0\0€K\0\1\0\16sumneko_lua\1\0\0\0\0\19setup_handlers\20mason-lspconfig\14lspconfig\0\18LspFormatting\24nvim_create_augroup\bapi\0\1\0\3\vsilent\2\tdesc\23diagnose goto_next\fnoremap\2\14goto_next\14<Leader>]\1\0\3\vsilent\2\tdesc\23diagnose goto_prev\fnoremap\2\14goto_prev\14<Leader>[\1\0\3\vsilent\2\tdesc\24diagnose open_float\fnoremap\2\15open_float\15diagnostic\14<Leader>e\6n\bset\vkeymap\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\fsources\vconfig\t<CR>\0\n<C-e>\nabort\14<C-Space>\rcomplete\n<Tab>\0\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\bcmp\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-cmp",
    url = "https://github.com/hrsh7th/nvim-cmp"
  },
  ["nvim-dap"] = {
    config = { "\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequire€\6\1\0\5\0 \0Q6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0005\4\6\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\b\0005\4\t\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\n\0005\4\v\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\15\0005\4\16\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\17\0003\3\18\0005\4\19\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0005\4\22\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\23\0003\3\24\0005\4\25\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\26\0003\3\27\0005\4\28\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\29\0003\3\30\0005\4\31\0B\0\5\1K\0\1\0\1\0\1\tdesc\24nvim-dap run_last{}\0\16<Leader>ddl\1\0\1\tdesc\25nvim-dap repl_open()\0\16<Leader>ddr\1\0\1\tdesc3nvim-dap set_breakpoint with log point message\0\16<Leader>dlp\1\0\1\tdesc+nvim-dap set_breakpoint with condition\0\16<Leader>dbb\1\0\1\tdesc\31nvim-dap toggle_breakpoint\0\15<Leader>db\1\0\1\tdesc\24nvim-dap step_out()\0\1\0\1\tdesc\24nvim-dap step_out()\0\n<F12>\1\0\1\tdesc\25nvim-dap step_into()\0\1\0\1\tdesc\25nvim-dap step_over()\0\n<F10>\1\0\1\tdesc\22nvim-dap continue\0\t<F5>\6n\bset\vkeymap\bvim\0" },
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
  ["nvim-tree.lua"] = {
    config = { "\27LJ\2\2@\0\0\3\0\3\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0+\1\2\0+\2\1\0B\0\3\1K\0\1\0\vtoggle\14nvim-tree\frequire;\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14find_file\14nvim-tree\frequireš\2\1\0\5\0\16\0\0256\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\n\0003\3\v\0005\4\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\r\0003\3\14\0005\4\15\0B\0\5\1K\0\1\0\1\0\1\tdesc\27find_file in nvim-tree\0\n<A-q>\1\0\1\tdesc\21toggle nvim-tree\0\n<C-q>\6n\bset\vkeymap\bvim\24update_focused_file\1\0\2\16update_root\2\venable\2\1\0\1\20respect_buf_cwd\2\nsetup\14nvim-tree\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-tree.lua",
    url = "https://github.com/kyazdani42/nvim-tree.lua"
  },
  ["nvim-treesitter"] = {
    config = { "\27LJ\2\2Ñ\3\0\0\4\0\20\0\0236\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\0015\2\14\0=\2\15\0015\2\16\0=\2\17\0015\2\18\0=\2\19\1B\0\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\fendwise\1\0\1\venable\2\fmatchup\1\0\1\venable\2\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\t<BS>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter"
  },
  ["nvim-treesitter-endwise"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-treesitter-endwise",
    url = "https://github.com/RRethy/nvim-treesitter-endwise"
  },
  ["nvim-ts-autotag"] = {
    config = { "\27LJ\2\2A\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\20nvim-ts-autotag\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-ts-autotag",
    url = "https://github.com/windwp/nvim-ts-autotag"
  },
  ["nvim-ts-context-commentstring"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-ts-context-commentstring",
    url = "https://github.com/JoosepAlviste/nvim-ts-context-commentstring"
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
  ["project.nvim"] = {
    config = { "\27LJ\2\2û\1\0\0\3\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\0015\2\6\0=\2\a\1B\0\2\1K\0\1\0\17exclude_dirs\1\3\0\0\19~/.config/nvim.~/dev/src/github.com/shishi/dotfiles/nvim\rpatterns\1\0\1\17silent_chdir\1\1\n\0\0\t.git\v_darcs\b.hg\t.bzr\t.svn\rMakefile\17package.json\rRakefile\16selene.toml\nsetup\17project_nvim\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/project.nvim",
    url = "https://github.com/ahmedkhalf/project.nvim"
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
    config = { "\27LJ\2\2D\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireC\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14live_grep\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\roldfiles\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15git_status\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15treesitter\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fkeymaps\22telescope.builtin\frequireQ\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequireM\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\rprojects\15extensions\14telescope\frequireö\b\1\0\5\0003\0‡\0016\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\4\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\5\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\6\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\a\0B\0\2\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\15\0003\3\16\0005\4\17\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\18\0003\3\19\0005\4\20\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\21\0003\3\22\0005\4\23\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\24\0003\3\25\0005\4\26\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\27\0003\3\28\0005\4\29\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\30\0003\3\31\0005\4 \0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2!\0003\3\"\0005\4#\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2$\0003\3%\0005\4&\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2'\0003\3(\0005\4)\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2*\0003\3+\0005\4,\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2-\0003\3.\0005\4/\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\0020\0003\0031\0005\0042\0B\0\5\1K\0\1\0\1\0\1\tdesc\22telescop projects\0\15<Leader>tp\1\0\1\tdesc\27telescope file browser\0\15<Leader>tf\1\0\1\tdesc\22telescope keymaps\0\15<Leader>tk\1\0\1\tdesc\25telescope treesitter\0\15<Leader>tt\1\0\1\tdesc\23telescope quickfix\0\15<Leader>tq\1\0\1\tdesc\25telescope git status\0\15<Leader>ts\1\0\1\tdesc\27telescope git branches\0\15<Leader>tb\1\0\1\tdesc\23telescope commands\0\v<C-k>c\1\0\1\tdesc\30telescope command history\0\v<C-k>h\1\0\1\tdesc\24telescope old files\0\v<C-k>r\1\0\1\tdesc\22telescope buffers\0\v<C-k>b\1\0\1\tdesc\24telescope live grep\0\v<C-k>g\1\0\1\tdesc\25telescope find files\0\n<C-p>\6n\bset\vkeymap\bvim\rprojects\14ui-select\17file_browser\bfzf\19load_extension\nsetup\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope.nvim",
    url = "https://github.com/nvim-telescope/telescope.nvim"
  },
  ["toggleterm.nvim"] = {
    config = { "\27LJ\2\2y\0\1\2\0\6\1\0159\1\0\0\a\1\1\0X\1\3€)\1\20\0L\1\2\0X\1\b€9\1\0\0\a\1\2\0X\1\5€6\1\3\0009\1\4\0019\1\5\1\24\1\0\1L\1\2\0K\0\1\0\fcolumns\6o\bvim\rvertical\15horizontal\14directionµæÌ™\19™³æþ\3$\0\0\2\1\1\0\5-\0\0\0\18\1\0\0009\0\0\0B\0\2\1K\0\1\0\1À\vtoggleþ\4\1\0\a\0\31\00046\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0003\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0005\1\t\0'\2\n\0'\3\v\0005\4\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\r\0'\2\14\0'\3\15\0005\4\16\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\17\0'\2\18\0'\3\19\0005\4\20\0B\0\5\0016\0\0\0'\1\21\0B\0\2\0029\0\22\0\18\2\0\0009\1\23\0005\3\24\0B\1\3\0023\2\25\0007\2\26\0006\2\6\0009\2\a\0029\2\b\2'\3\27\0'\4\28\0'\5\29\0005\6\30\0B\2\5\0012\0\0€K\0\1\0\1\0\3\vsilent\2\tdesc\flazygit\fnoremap\2#<Cmd>lua _lazygit_toggle()<CR>\n<A-g>\6n\20_lazygit_toggle\0\1\0\4\vhidden\2\bcmd\flazygit\14direction\nfloat\ncount\3d\bnew\rTerminal\24toggleterm.terminal\1\0\1\vsilent\2*<Cmd>10ToggleTerm direction=float<CR>\f<C-k>pt\1\3\0\0\6n\6t\1\0\1\vsilent\2!<Cmd>ToggleTermToggleAll<CR>\f<C-k>at\1\3\0\0\6n\6t\1\0\1\vsilent\2)<Cmd>exe v:count1 . \"ToggleTerm\"<CR>\v<C-k>t\1\3\0\0\6n\6t\bset\vkeymap\bvim\tsize\0\1\0\1\14direction\15horizontal\nsetup\15toggleterm\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/toggleterm.nvim",
    url = "https://github.com/akinsho/toggleterm.nvim"
  },
  ["trouble.nvim"] = {
    config = { "\27LJ\2\2›\5\0\0\5\0\26\00076\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0005\4\n\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\v\0'\3\f\0005\4\r\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\14\0'\3\15\0005\4\16\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\17\0'\3\18\0005\4\19\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\20\0'\3\21\0005\4\22\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\23\0'\3\24\0005\4\25\0B\0\5\1K\0\1\0\1\0\2\fnoremap\2\vsilent\2*<Cmd>TroubleToggle lsp_references<CR>\agR\1\0\2\fnoremap\2\vsilent\2$<Cmd>TroubleToggle quickfix<CR>\15<Leader>xq\1\0\2\fnoremap\2\vsilent\2#<Cmd>TroubleToggle loclist<CR>\15<Leader>xl\1\0\2\fnoremap\2\vsilent\0020<Cmd>TroubleToggle document_diagnostics<CR>\15<Leader>xd\1\0\2\fnoremap\2\vsilent\0021<Cmd>TroubleToggle workspace_diagnostics<CR>\15<Leader>xw\1\0\2\fnoremap\2\vsilent\2\27<Cmd>TroubleToggle<CR>\15<Leader>xx\6n\bset\vkeymap\bvim\1\0\1\nicons\2\nsetup\ftrouble\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/trouble.nvim",
    url = "https://github.com/folke/trouble.nvim"
  },
  ["vim-illuminate"] = {
    config = { "\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\14configure\15illuminate\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/vim-illuminate",
    url = "https://github.com/RRethy/vim-illuminate"
  },
  ["vim-matchup"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/vim-matchup",
    url = "https://github.com/andymass/vim-matchup"
  },
  ["which-key.nvim"] = {
    config = { "\27LJ\2\2n\0\0\4\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\1K\0\1\0\fplugins\1\0\0\rspelling\1\0\0\1\0\1\fenabled\2\nsetup\14which-key\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/which-key.nvim",
    url = "https://github.com/folke/which-key.nvim"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: hop.nvim
time([[Config for hop.nvim]], true)
try_loadstring("\27LJ\2\2Ô\1\0\0\4\0\f\0\0216\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0B\0\4\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0B\0\4\1K\0\1\0\22<Cmd>HopChar1<CR>\14<Leader>f\21<Cmd>HopWord<CR>\14<Leader>w\5\bset\vkeymap\bvim\1\0\1\tkeys\28etovxqpdygfblzhckisuran\nsetup\bhop\frequire\0", "config", "hop.nvim")
time([[Config for hop.nvim]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\2Ñ\3\0\0\4\0\20\0\0236\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\0015\2\14\0=\2\15\0015\2\16\0=\2\17\0015\2\18\0=\2\19\1B\0\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\fendwise\1\0\1\venable\2\fmatchup\1\0\1\venable\2\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\t<BS>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)
-- Config for: nvim-cmp
time([[Config for nvim-cmp]], true)
try_loadstring("\27LJ\2\2C\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireR\0\1\2\1\2\0\f-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\4€-\1\0\0009\1\1\1B\1\1\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\21select_next_item\fvisibleX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5€-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2€\18\1\0\0B\1\1\1K\0\1\0\0À\1\0\1\vselect\2\fconfirm\fvisible0\0\1\2\0\2\0\a9\1\0\0\6\1\1\0X\1\2€+\1\1\0X\2\1€+\1\2\0L\1\2\0\fnull-ls\tnameS\1\1\4\0\b\0\n6\1\0\0009\1\1\0019\1\2\0019\1\3\0015\2\5\0003\3\4\0=\3\6\2=\0\a\2B\1\2\1K\0\1\0\nbufnr\vfilter\1\0\0\0\vformat\bbuf\blsp\bvim\27\0\0\2\2\0\0\4-\0\0\0-\1\1\0B\0\2\1K\0\1\0\1\0\1Àd\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintú\14\1\2\a\2>\0Æ\0019\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\0025\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0016\2\2\0009\2\3\0029\2\r\2\18\3\1\0'\4\14\0'\5\15\0B\2\4\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\19\0006\5\2\0009\5\20\0059\5\21\0059\5\22\0055\6\23\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\24\0006\5\2\0009\5\20\0059\5\21\0059\5\25\0055\6\26\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\27\0006\5\2\0009\5\20\0059\5\21\0059\5\28\0055\6\29\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\30\0006\5\2\0009\5\20\0059\5\21\0059\5\31\0055\6 \0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4!\0006\5\2\0009\5\20\0059\5\21\0059\5\"\0055\6#\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4$\0006\5\2\0009\5\20\0059\5\21\0059\5%\0055\6&\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4'\0006\5\2\0009\5\20\0059\5\21\0059\5(\0055\6)\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4*\0003\5+\0005\6,\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4-\0006\5\2\0009\5\20\0059\5\21\0059\5.\0055\6/\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0040\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0062\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0043\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0064\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0045\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0067\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0048\0006\5\2\0009\5\20\0059\5\21\0059\0059\0055\6:\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4;\0006\5\2\0009\5\20\0059\5\21\0059\5<\0055\6=\0=\1\a\6B\2\5\0012\0\0€K\0\1\0\3À\2À\1\0\3\vsilent\2\tdesc\19vim.lsp format\fnoremap\2\vformat\v<C-k>f\1\0\3\vsilent\2\tdesc\23vim.lsp references\fnoremap\2\15references\agr\1\0\3\vsilent\2\tdesc\24vim.lsp code_action\fnoremap\2\16code_action\15<Leader>ca\1\0\3\vsilent\2\tdesc\19vim.lsp rename\fnoremap\2\t<F2>\1\0\3\vsilent\2\tdesc\19vim.lsp rename\fnoremap\2\vrename\15<Leader>rn\1\0\3\vsilent\2\tdesc\28vim.lsp type_definition\fnoremap\2\20type_definition\14<Leader>D\1\0\3\vsilent\2\tdesc#vim.lsp list_workspace_folders\fnoremap\2\0\15<Leader>wl\1\0\3\vsilent\2\tdesc$vim.lsp remove_workspace_folder\fnoremap\2\28remove_workspace_folder\15<Leader>wr\1\0\3\vsilent\2\tdesc!vim.lsp add_workspace_folder\fnoremap\2\25add_workspace_folder\15<Leader>wa\1\0\3\vsilent\2\tdesc\27vim.lsp signature_help\fnoremap\2\19signature_help\v<C-k>k\1\0\3\vsilent\2\tdesc\27vim.lsp implementation\fnoremap\2\19implementation\agi\1\0\3\vsilent\2\tdesc\18vim.lsp hover\fnoremap\2\nhover\6K\1\0\3\vsilent\2\tdesc\23vim.lsp definition\fnoremap\2\15definition\agd\1\0\3\vsilent\2\tdesc\23vim.lsp delaration\fnoremap\2\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\rcallback\0\1\0\0\1\2\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodV\0\1\4\3\4\0\n-\1\0\0008\1\0\0019\1\0\0015\2\1\0-\3\1\0=\3\2\2-\3\2\0=\3\3\2B\1\2\1K\0\1\0\5À\1À\4À\14on_attach\18capabilitiies\1\0\0\nsetupˆ\1\0\0\6\1\v\0\14-\0\0\0009\0\0\0009\0\1\0005\1\t\0005\2\a\0005\3\5\0005\4\3\0005\5\2\0=\5\4\4=\4\6\3=\3\b\2=\2\n\1B\0\2\1K\0\1\0\5À\rsettings\1\0\0\bLua\1\0\0\16diagnostics\1\0\0\fglobals\1\0\0\1\2\0\0\bvim\nsetup\16sumneko_luaù\n\1\0\t\0J\0£\0016\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\6\0005\3\4\0003\4\3\0=\4\5\3=\3\a\0024\3\0\0=\3\b\0029\3\t\0009\3\n\0039\3\v\0035\4\r\0009\5\t\0009\5\f\5)\6üÿB\5\2\2=\5\14\0049\5\t\0009\5\f\5)\6\4\0B\5\2\2=\5\15\0043\5\16\0=\5\17\0049\5\t\0009\5\18\5B\5\1\2=\5\19\0049\5\t\0009\5\20\5B\5\1\2=\5\21\0043\5\22\0=\5\23\4B\3\2\2=\3\t\0029\3\24\0009\3\25\0034\4\5\0005\5\26\0>\5\1\0045\5\27\0>\5\2\0045\5\28\0>\5\3\0045\5\29\0>\5\4\4B\3\2\2=\3\25\2B\1\2\0019\1\2\0009\1\30\1'\2\31\0005\3\"\0009\4\24\0009\4\25\0044\5\3\0005\6 \0>\6\1\0055\6!\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2$\0005\3%\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0034\4\3\0005\5&\0>\5\1\4=\4\25\3B\1\3\0019\1\2\0009\1#\1'\2'\0005\3(\0009\4\t\0009\4\n\0049\4#\4B\4\1\2=\4\t\0039\4\24\0009\4\25\0044\5\3\0005\6)\0>\6\1\0055\6*\0>\6\2\5B\4\2\2=\4\25\3B\1\3\0016\1\0\0'\2+\0B\1\2\0029\1,\0016\2-\0009\2.\0029\2/\0029\0020\2B\2\1\0A\1\0\0026\2-\0009\0021\0029\0022\2'\0033\0'\0044\0006\5-\0009\0055\0059\0056\0055\0067\0B\2\5\0016\2-\0009\0021\0029\0022\2'\0033\0'\0048\0006\5-\0009\0055\0059\0059\0055\6:\0B\2\5\0016\2-\0009\0021\0029\0022\2'\0033\0'\4;\0006\5-\0009\0055\0059\5<\0055\6=\0B\2\5\0013\2>\0006\3-\0009\3?\0039\3@\3'\4A\0004\5\0\0B\3\3\0023\4B\0006\5\0\0'\6C\0B\5\2\0026\6\0\0'\aD\0B\6\2\0029\6E\0065\aH\0003\bF\0>\b\1\a3\bG\0=\bI\aB\6\2\0012\0\0€K\0\1\0\16sumneko_lua\1\0\0\0\0\19setup_handlers\20mason-lspconfig\14lspconfig\0\18LspFormatting\24nvim_create_augroup\bapi\0\1\0\3\vsilent\2\tdesc\23diagnose goto_next\fnoremap\2\14goto_next\14<Leader>]\1\0\3\vsilent\2\tdesc\23diagnose goto_prev\fnoremap\2\14goto_prev\14<Leader>[\1\0\3\vsilent\2\tdesc\24diagnose open_float\fnoremap\2\15open_float\15diagnostic\14<Leader>e\6n\bset\vkeymap\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\1\0\1\tname\vbuffer\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\fsources\vconfig\t<CR>\0\n<C-e>\nabort\14<C-Space>\rcomplete\n<Tab>\0\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\bcmp\frequire\0", "config", "nvim-cmp")
time([[Config for nvim-cmp]], false)
-- Config for: which-key.nvim
time([[Config for which-key.nvim]], true)
try_loadstring("\27LJ\2\2n\0\0\4\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\1K\0\1\0\fplugins\1\0\0\rspelling\1\0\0\1\0\1\fenabled\2\nsetup\14which-key\frequire\0", "config", "which-key.nvim")
time([[Config for which-key.nvim]], false)
-- Config for: indent-blankline.nvim
time([[Config for indent-blankline.nvim]], true)
try_loadstring("\27LJ\2\2á\3\0\0\2\0\b\0\0256\0\0\0009\0\1\0'\1\2\0B\0\2\0016\0\0\0009\0\1\0'\1\3\0B\0\2\0016\0\0\0009\0\1\0'\1\4\0B\0\2\0016\0\0\0009\0\1\0'\1\5\0B\0\2\0016\0\0\0009\0\1\0'\1\6\0B\0\2\0016\0\0\0009\0\1\0'\1\a\0B\0\2\1K\0\1\0Ahighlight IndentBlanklineIndent6 guibg=#C678DD gui=nocombineAhighlight IndentBlanklineIndent5 guibg=#61AFEF gui=nocombineAhighlight IndentBlanklineIndent4 guibg=#56B6C2 gui=nocombineAhighlight IndentBlanklineIndent3 guibg=#98C379 gui=nocombineAhighlight IndentBlanklineIndent2 guibg=#E5C07B gui=nocombineAhighlight IndentBlanklineIndent1 guibg=#E06C75 gui=nocombine\bcmd\bvimÉ\4\1\0\5\0\26\00006\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\3\0009\0\4\0'\1\5\0005\2\6\0B\0\3\0026\1\0\0009\1\3\0019\1\a\0015\2\b\0005\3\t\0=\0\n\0035\4\v\0=\4\f\0033\4\r\0=\4\14\3B\1\3\0016\1\0\0009\1\1\1+\2\2\0=\2\15\0016\1\0\0009\1\1\0019\1\16\1\18\2\1\0009\1\17\1'\3\18\0B\1\3\0016\1\0\0009\1\1\0019\1\16\1\18\2\1\0009\1\17\1'\3\19\0B\1\3\0016\1\20\0'\2\21\0B\1\2\0029\1\22\0015\2\24\0005\3\23\0=\3\25\2B\1\2\1K\0\1\0\24char_highlight_list\1\0\0\1\a\0\0\27IndentBlanklineIndent1\27IndentBlanklineIndent2\27IndentBlanklineIndent3\27IndentBlanklineIndent4\27IndentBlanklineIndent5\27IndentBlanklineIndent6\nsetup\21indent_blankline\frequire\feol:â†´\14space:â‹…\vappend\14listchars\tlist\rcallback\0\fpattern\1\2\0\0\6*\ngroup\1\0\0\1\2\0\0\16ColorScheme\24nvim_create_autocmd\1\0\1\nclear\2\29augroup_indent-blankline\24nvim_create_augroup\bapi\18termguicolors\bopt\bvim\0", "config", "indent-blankline.nvim")
time([[Config for indent-blankline.nvim]], false)
-- Config for: trouble.nvim
time([[Config for trouble.nvim]], true)
try_loadstring("\27LJ\2\2›\5\0\0\5\0\26\00076\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0005\4\n\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\v\0'\3\f\0005\4\r\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\14\0'\3\15\0005\4\16\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\17\0'\3\18\0005\4\19\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\20\0'\3\21\0005\4\22\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\23\0'\3\24\0005\4\25\0B\0\5\1K\0\1\0\1\0\2\fnoremap\2\vsilent\2*<Cmd>TroubleToggle lsp_references<CR>\agR\1\0\2\fnoremap\2\vsilent\2$<Cmd>TroubleToggle quickfix<CR>\15<Leader>xq\1\0\2\fnoremap\2\vsilent\2#<Cmd>TroubleToggle loclist<CR>\15<Leader>xl\1\0\2\fnoremap\2\vsilent\0020<Cmd>TroubleToggle document_diagnostics<CR>\15<Leader>xd\1\0\2\fnoremap\2\vsilent\0021<Cmd>TroubleToggle workspace_diagnostics<CR>\15<Leader>xw\1\0\2\fnoremap\2\vsilent\2\27<Cmd>TroubleToggle<CR>\15<Leader>xx\6n\bset\vkeymap\bvim\1\0\1\nicons\2\nsetup\ftrouble\frequire\0", "config", "trouble.nvim")
time([[Config for trouble.nvim]], false)
-- Config for: lualine.nvim
time([[Config for lualine.nvim]], true)
try_loadstring("\27LJ\2\2¨\1\0\0\5\0\n\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0004\3\3\0005\4\3\0>\4\1\3=\3\5\2=\2\a\0015\2\b\0=\2\t\1B\0\2\1K\0\1\0\foptions\1\0\1\ntheme\21gruvbox-material\rsections\1\0\0\14lualine_a\1\0\0\1\2\1\0\rfilename\tpath\3\3\nsetup\flualine\frequire\0", "config", "lualine.nvim")
time([[Config for lualine.nvim]], false)
-- Config for: nvim-autopairs
time([[Config for nvim-autopairs]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\19nvim-autopairs\frequire\0", "config", "nvim-autopairs")
time([[Config for nvim-autopairs]], false)
-- Config for: project.nvim
time([[Config for project.nvim]], true)
try_loadstring("\27LJ\2\2û\1\0\0\3\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\0015\2\6\0=\2\a\1B\0\2\1K\0\1\0\17exclude_dirs\1\3\0\0\19~/.config/nvim.~/dev/src/github.com/shishi/dotfiles/nvim\rpatterns\1\0\1\17silent_chdir\1\1\n\0\0\t.git\v_darcs\b.hg\t.bzr\t.svn\rMakefile\17package.json\rRakefile\16selene.toml\nsetup\17project_nvim\frequire\0", "config", "project.nvim")
time([[Config for project.nvim]], false)
-- Config for: nvim-ts-autotag
time([[Config for nvim-ts-autotag]], true)
try_loadstring("\27LJ\2\2A\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\20nvim-ts-autotag\frequire\0", "config", "nvim-ts-autotag")
time([[Config for nvim-ts-autotag]], false)
-- Config for: telescope.nvim
time([[Config for telescope.nvim]], true)
try_loadstring("\27LJ\2\2D\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireC\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14live_grep\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\roldfiles\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15git_status\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15treesitter\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fkeymaps\22telescope.builtin\frequireQ\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequireM\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\rprojects\15extensions\14telescope\frequireö\b\1\0\5\0003\0‡\0016\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\4\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\5\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\6\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\3\0'\1\a\0B\0\2\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\15\0003\3\16\0005\4\17\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\18\0003\3\19\0005\4\20\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\21\0003\3\22\0005\4\23\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\24\0003\3\25\0005\4\26\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\27\0003\3\28\0005\4\29\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2\30\0003\3\31\0005\4 \0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2!\0003\3\"\0005\4#\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2$\0003\3%\0005\4&\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2'\0003\3(\0005\4)\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2*\0003\3+\0005\4,\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\2-\0003\3.\0005\4/\0B\0\5\0016\0\b\0009\0\t\0009\0\n\0'\1\v\0'\0020\0003\0031\0005\0042\0B\0\5\1K\0\1\0\1\0\1\tdesc\22telescop projects\0\15<Leader>tp\1\0\1\tdesc\27telescope file browser\0\15<Leader>tf\1\0\1\tdesc\22telescope keymaps\0\15<Leader>tk\1\0\1\tdesc\25telescope treesitter\0\15<Leader>tt\1\0\1\tdesc\23telescope quickfix\0\15<Leader>tq\1\0\1\tdesc\25telescope git status\0\15<Leader>ts\1\0\1\tdesc\27telescope git branches\0\15<Leader>tb\1\0\1\tdesc\23telescope commands\0\v<C-k>c\1\0\1\tdesc\30telescope command history\0\v<C-k>h\1\0\1\tdesc\24telescope old files\0\v<C-k>r\1\0\1\tdesc\22telescope buffers\0\v<C-k>b\1\0\1\tdesc\24telescope live grep\0\v<C-k>g\1\0\1\tdesc\25telescope find files\0\n<C-p>\6n\bset\vkeymap\bvim\rprojects\14ui-select\17file_browser\bfzf\19load_extension\nsetup\14telescope\frequire\0", "config", "telescope.nvim")
time([[Config for telescope.nvim]], false)
-- Config for: nvim-tree.lua
time([[Config for nvim-tree.lua]], true)
try_loadstring("\27LJ\2\2@\0\0\3\0\3\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0+\1\2\0+\2\1\0B\0\3\1K\0\1\0\vtoggle\14nvim-tree\frequire;\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14find_file\14nvim-tree\frequireš\2\1\0\5\0\16\0\0256\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\n\0003\3\v\0005\4\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\r\0003\3\14\0005\4\15\0B\0\5\1K\0\1\0\1\0\1\tdesc\27find_file in nvim-tree\0\n<A-q>\1\0\1\tdesc\21toggle nvim-tree\0\n<C-q>\6n\bset\vkeymap\bvim\24update_focused_file\1\0\2\16update_root\2\venable\2\1\0\1\20respect_buf_cwd\2\nsetup\14nvim-tree\frequire\0", "config", "nvim-tree.lua")
time([[Config for nvim-tree.lua]], false)
-- Config for: mason-lspconfig.nvim
time([[Config for mason-lspconfig.nvim]], true)
try_loadstring("\27LJ\2\2u\0\0\3\0\5\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0004\2\0\0=\2\4\1B\0\2\1K\0\1\0\21ensure_installed\1\0\1\27automatic_installation\2\nsetup\20mason-lspconfig\frequire\0", "config", "mason-lspconfig.nvim")
time([[Config for mason-lspconfig.nvim]], false)
-- Config for: nvim-surround
time([[Config for nvim-surround]], true)
try_loadstring("\27LJ\2\2?\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\18nvim-surround\frequire\0", "config", "nvim-surround")
time([[Config for nvim-surround]], false)
-- Config for: mason.nvim
time([[Config for mason.nvim]], true)
try_loadstring("\27LJ\2\0023\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\nmason\frequire\0", "config", "mason.nvim")
time([[Config for mason.nvim]], false)
-- Config for: toggleterm.nvim
time([[Config for toggleterm.nvim]], true)
try_loadstring("\27LJ\2\2y\0\1\2\0\6\1\0159\1\0\0\a\1\1\0X\1\3€)\1\20\0L\1\2\0X\1\b€9\1\0\0\a\1\2\0X\1\5€6\1\3\0009\1\4\0019\1\5\1\24\1\0\1L\1\2\0K\0\1\0\fcolumns\6o\bvim\rvertical\15horizontal\14directionµæÌ™\19™³æþ\3$\0\0\2\1\1\0\5-\0\0\0\18\1\0\0009\0\0\0B\0\2\1K\0\1\0\1À\vtoggleþ\4\1\0\a\0\31\00046\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0003\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0005\1\t\0'\2\n\0'\3\v\0005\4\f\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\r\0'\2\14\0'\3\15\0005\4\16\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\17\0'\2\18\0'\3\19\0005\4\20\0B\0\5\0016\0\0\0'\1\21\0B\0\2\0029\0\22\0\18\2\0\0009\1\23\0005\3\24\0B\1\3\0023\2\25\0007\2\26\0006\2\6\0009\2\a\0029\2\b\2'\3\27\0'\4\28\0'\5\29\0005\6\30\0B\2\5\0012\0\0€K\0\1\0\1\0\3\vsilent\2\tdesc\flazygit\fnoremap\2#<Cmd>lua _lazygit_toggle()<CR>\n<A-g>\6n\20_lazygit_toggle\0\1\0\4\vhidden\2\bcmd\flazygit\14direction\nfloat\ncount\3d\bnew\rTerminal\24toggleterm.terminal\1\0\1\vsilent\2*<Cmd>10ToggleTerm direction=float<CR>\f<C-k>pt\1\3\0\0\6n\6t\1\0\1\vsilent\2!<Cmd>ToggleTermToggleAll<CR>\f<C-k>at\1\3\0\0\6n\6t\1\0\1\vsilent\2)<Cmd>exe v:count1 . \"ToggleTerm\"<CR>\v<C-k>t\1\3\0\0\6n\6t\bset\vkeymap\bvim\tsize\0\1\0\1\14direction\15horizontal\nsetup\15toggleterm\frequire\0", "config", "toggleterm.nvim")
time([[Config for toggleterm.nvim]], false)
-- Config for: nvim-dap
time([[Config for nvim-dap]], true)
try_loadstring("\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequire€\6\1\0\5\0 \0Q6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0005\4\6\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\b\0005\4\t\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\n\0005\4\v\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\15\0005\4\16\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\17\0003\3\18\0005\4\19\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0005\4\22\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\23\0003\3\24\0005\4\25\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\26\0003\3\27\0005\4\28\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\29\0003\3\30\0005\4\31\0B\0\5\1K\0\1\0\1\0\1\tdesc\24nvim-dap run_last{}\0\16<Leader>ddl\1\0\1\tdesc\25nvim-dap repl_open()\0\16<Leader>ddr\1\0\1\tdesc3nvim-dap set_breakpoint with log point message\0\16<Leader>dlp\1\0\1\tdesc+nvim-dap set_breakpoint with condition\0\16<Leader>dbb\1\0\1\tdesc\31nvim-dap toggle_breakpoint\0\15<Leader>db\1\0\1\tdesc\24nvim-dap step_out()\0\1\0\1\tdesc\24nvim-dap step_out()\0\n<F12>\1\0\1\tdesc\25nvim-dap step_into()\0\1\0\1\tdesc\25nvim-dap step_over()\0\n<F10>\1\0\1\tdesc\22nvim-dap continue\0\t<F5>\6n\bset\vkeymap\bvim\0", "config", "nvim-dap")
time([[Config for nvim-dap]], false)
-- Config for: vim-illuminate
time([[Config for vim-illuminate]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\14configure\15illuminate\frequire\0", "config", "vim-illuminate")
time([[Config for vim-illuminate]], false)
-- Config for: gitsigns.nvim
time([[Config for gitsigns.nvim]], true)
try_loadstring("\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1€4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0À\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a]c\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2€'\0\3\0002\0\a€6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0€L\0\2\0L\0\2\0\1À\r<Ignore>\0\rschedule\a[c\tdiff\awo\bvimð\1\1\1\b\0\14\0\0236\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\0012\0\0€K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\2\texpr\2\tdesc\22gitsign prev_hunk\0\a[c\1\0\2\texpr\2\tdesc\22gitsign next_hunk\0\a]c\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0", "config", "gitsigns.nvim")
time([[Config for gitsigns.nvim]], false)
-- Config for: gruvbox-material
time([[Config for gruvbox-material]], true)
try_loadstring("\27LJ\2\2î\a\0\0\3\0\18\0'6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0'\1\4\0=\1\3\0006\0\0\0009\0\5\0'\1\a\0=\1\6\0006\0\0\0009\0\5\0)\1\1\0=\1\b\0006\0\0\0009\0\t\0009\0\n\0'\1\v\0+\2\1\0B\0\3\0016\0\0\0009\0\5\0)\1\1\0=\1\f\0006\0\0\0009\0\5\0)\1\1\0=\1\r\0006\0\0\0009\0\5\0'\1\15\0=\1\14\0006\0\0\0009\0\16\0'\1\17\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\fcolored-gruvbox_material_diagnostic_virtual_text/gruvbox_material_diagnostic_line_highlight/gruvbox_material_diagnostic_text_highlight©\4        augroup nord-theme-overrides\n          autocmd!\n          autocmd ColorScheme gruvbox-material highlight Folded ctermfg=LightGray guifg=#918d88\n          autocmd ColorScheme gruvbox-material highlight Folded ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight Folded cterm=italic gui=italic\n          autocmd ColorScheme gruvbox-material highlight SignColumn ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight DiagnosticSign ctermbg=235 guibg=#282828\n        augroup END\n      \14nvim_exec\bapi(gruvbox_material_better_performance\vmedium gruvbox_material_background\6g\tdark\15background\18termguicolors\bopt\bvim\0", "config", "gruvbox-material")
time([[Config for gruvbox-material]], false)
-- Config for: refactoring.nvim
time([[Config for refactoring.nvim]], true)
try_loadstring("\27LJ\2\2=\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\16refactoring\frequire\0", "config", "refactoring.nvim")
time([[Config for refactoring.nvim]], false)
-- Config for: Comment.nvim
time([[Config for Comment.nvim]], true)
try_loadstring("\27LJ\2\2k\0\0\4\0\a\0\0146\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0029\1\4\0'\2\5\0'\3\6\0B\1\3\1K\0\1\0\b#%s\ash\bset\15Comment.ft\nsetup\fComment\frequire\0", "config", "Comment.nvim")
time([[Config for Comment.nvim]], false)
-- Config for: null-ls.nvim
time([[Config for null-ls.nvim]], true)
try_loadstring("\27LJ\2\2I\0\0\3\1\6\0\t6\0\0\0009\0\1\0009\0\2\0009\0\3\0005\1\4\0-\2\0\0=\2\5\1B\0\2\1K\0\1\0\1À\nbufnr\1\0\0\vformat\bbuf\blsp\bvimò\1\1\2\6\1\r\0\0269\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19€6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\2'\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0012\0\0€K\0\1\0\0À\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_method°\b\1\0\b\0001\0œ\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0004\2\0\0B\0\3\0026\1\4\0'\2\5\0B\1\2\0029\2\6\0015\3-\0004\4!\0009\5\a\0019\5\b\0059\5\t\5>\5\1\0049\5\a\0019\5\b\0059\5\n\5>\5\2\0049\5\a\0019\5\b\0059\5\v\5>\5\3\0049\5\a\0019\5\b\0059\5\f\5>\5\4\0049\5\a\0019\5\r\0059\5\14\5>\5\5\0049\5\a\0019\5\15\0059\5\16\5>\5\6\0049\5\a\0019\5\15\0059\5\17\5>\5\a\0049\5\a\0019\5\15\0059\5\t\5>\5\b\0049\5\a\0019\5\15\0059\5\18\5>\5\t\0049\5\a\0019\5\15\0059\5\19\5>\5\n\0049\5\a\0019\5\15\0059\5\20\5>\5\v\0049\5\a\0019\5\15\0059\5\21\5>\5\f\0049\5\a\0019\5\15\0059\5\22\0059\5\23\0055\6\25\0005\a\24\0=\a\26\6B\5\2\2>\5\r\0049\5\a\0019\5\15\0059\5\27\5>\5\14\0049\5\a\0019\5\15\0059\5\28\5>\5\15\0049\5\a\0019\5\15\0059\5\29\5>\5\16\0049\5\a\0019\5\15\0059\5\30\5>\5\17\0049\5\a\0019\5\15\0059\5\31\5>\5\18\0049\5\a\0019\5\15\0059\5 \5>\5\19\0049\5\a\0019\5!\0059\5\"\5>\5\20\0049\5\a\0019\5!\0059\5\17\5>\5\21\0049\5\a\0019\5!\0059\5#\5>\5\22\0049\5\a\0019\5!\0059\5$\5>\5\23\0049\5\a\0019\5!\0059\5%\5>\5\24\0049\5\a\0019\5!\0059\5\20\5>\5\25\0049\5\a\0019\5!\0059\5&\5>\5\26\0049\5\a\0019\5!\0059\5\22\0059\5\23\0055\6(\0005\a'\0=\a\26\6B\5\2\2>\5\27\0049\5\a\0019\5!\0059\5\28\5>\5\28\0049\5\a\0019\5!\0059\5)\5>\5\29\0049\5\a\0019\5!\0059\5*\5>\5\30\0049\5\a\0019\5!\0059\5\27\5>\5\31\0049\5\a\0019\5+\0059\5,\5>\5 \4=\4.\0033\4/\0=\0040\3B\2\2\0012\0\0€K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prismaFmt\14prettierd\16fish_indent\rbeautysh\15formatting\bzsh\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\nspell\15completion\16refactoring\rgitsigns\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\18LspFormatting\24nvim_create_augroup\bapi\bvim\0", "config", "null-ls.nvim")
time([[Config for null-ls.nvim]], false)
-- Config for: LuaSnip
time([[Config for LuaSnip]], true)
try_loadstring("\27LJ\2\2ú\1\0\0\3\0\v\0\0276\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\5\0005\2\6\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\a\0005\2\b\0B\0\3\0016\0\0\0'\1\3\0B\0\2\0029\0\4\0'\1\t\0005\2\n\0B\0\3\1K\0\1\0\1\2\0\0\thtml\20typescriptreact\1\2\0\0\thtml\20javascriptreact\1\2\0\0\nrails\truby\20filetype_extend\fluasnip\14lazy_load luasnip.loaders.from_vscode\frequire\0", "config", "LuaSnip")
time([[Config for LuaSnip]], false)

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
