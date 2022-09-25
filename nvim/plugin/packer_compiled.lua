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
    config = { "\27LJ\2\2�\2\0\0\3\0\15\0(6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0005\1\4\0B\0\2\0016\0\0\0'\1\5\0B\0\2\0029\0\6\0B\0\1\0016\0\0\0'\1\5\0B\0\2\0029\0\6\0'\1\a\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\t\0005\2\n\0B\0\3\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\v\0005\2\f\0B\0\3\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\r\0005\2\14\0B\0\3\1K\0\1\0\1\2\0\0\thtml\20typescriptreact\1\2\0\0\thtml\20javascriptreact\1\2\0\0\nrails\truby\20filetype_extend\15./snippets\14lazy_load luasnip.loaders.from_vscode\1\0\1\fhistory\1\nsetup\vconfig\fluasnip\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/LuaSnip",
    url = "https://github.com/L3MON4D3/LuaSnip"
  },
  ["SmoothCursor.nvim"] = {
    config = { "\27LJ\2\2>\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\17smoothcursor\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/SmoothCursor.nvim",
    url = "https://github.com/gen740/SmoothCursor.nvim"
  },
  ["auto-session"] = {
    config = { "\27LJ\2\2�\3\0\0\4\0\15\0\0206\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0'\1\t\0=\1\b\0006\0\6\0009\0\n\0009\0\v\0'\1\f\0'\2\r\0'\3\14\0B\0\4\1K\0\1\0\29<Cmd>RestoreSession<<CR>\14<Leader>r\6n\bset\vkeymapEblank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal\19sessionoptions\6o\bvim\18pre_save_cmds\1\3\0\0'lua require('nvim-tree').setup({})\24tabdo NvimTreeClose\1\0\4\22auto_save_enabled\2 auto_session_create_enabled\2\25auto_restore_enabled\1\25auto_session_enabled\2\nsetup\17auto-session\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/auto-session",
    url = "https://github.com/rmagatti/auto-session"
  },
  ["bufferline.nvim"] = {
    config = { "\27LJ\2\2W\0\4\b\0\5\0\14\18\5\1\0009\4\0\1'\6\1\0B\4\3\2\15\0\4\0X\5\2�'\4\2\0X\5\1�'\4\3\0'\5\4\0\18\6\4\0\18\a\0\0&\5\a\5L\5\2\0\6 \t \t \nerror\nmatch�\1\1\0\4\0\v\0\0156\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\3\0'\1\4\0B\0\2\0029\0\5\0005\1\t\0005\2\6\0003\3\a\0=\3\b\2=\2\n\1B\0\2\1K\0\1\0\foptions\1\0\0\26diagnostics_indicator\0\1\0\2\16diagnostics\rnvim_lsp\tmode\fbuffers\nsetup\15bufferline\frequire\18termguicolors\bopt\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/bufferline.nvim",
    url = "https://github.com/akinsho/bufferline.nvim"
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
  ["cmp-spell"] = {
    config = { "\27LJ\2\2Q\0\0\2\0\5\0\t6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0005\1\4\0=\1\3\0K\0\1\0\1\3\0\0\nen_us\bcjk\14spelllang\nspell\bopt\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp-spell",
    url = "https://github.com/f3fora/cmp-spell"
  },
  cmp_luasnip = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/cmp_luasnip",
    url = "https://github.com/saadparwaiz1/cmp_luasnip"
  },
  ["copilot-cmp"] = {
    config = { "\27LJ\2\2=\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\16copilot_cmp\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/copilot-cmp",
    url = "https://github.com/zbirenbaum/copilot-cmp"
  },
  ["copilot.lua"] = {
    config = { "\27LJ\2\0029\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\fcopilot\frequire-\1\0\3\0\3\0\0066\0\0\0009\0\1\0003\1\2\0)\2d\0B\0\3\1K\0\1\0\0\rdefer_fn\bvim\0" },
    loaded = false,
    needs_bufread = false,
    only_cond = false,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/opt/copilot.lua",
    url = "https://github.com/zbirenbaum/copilot.lua"
  },
  ["crates.nvim"] = {
    config = { "\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\vcrates\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/crates.nvim",
    url = "https://github.com/saecki/crates.nvim"
  },
  ["diffview.nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/diffview.nvim",
    url = "https://github.com/sindrets/diffview.nvim"
  },
  ["fidget.nvim"] = {
    config = { "\27LJ\2\0028\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\vfidget\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/fidget.nvim",
    url = "https://github.com/j-hui/fidget.nvim"
  },
  ["friendly-snippets"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/friendly-snippets",
    url = "https://github.com/rafamadriz/friendly-snippets"
  },
  ["gitsigns.nvim"] = {
    config = { "\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1�4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0�\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2�'\0\3\0002\0\a�6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0�L\0\2\0L\0\2\0\1�\r<Ignore>\0\rschedule\a]g\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2�'\0\3\0002\0\a�6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0�L\0\2\0L\0\2\0\1�\r<Ignore>\0\rschedule\a[g\tdiff\awo\bvim1\0\0\2\1\2\0\5-\0\0\0009\0\0\0005\1\1\0B\0\2\1K\0\1\0\1�\1\0\1\tfull\2\15blame_line(\0\0\2\1\2\0\5-\0\0\0009\0\0\0'\1\1\0B\0\2\1K\0\1\0\1�\6~\rdiffthis�\t\1\1\b\0002\0]6\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\1\18\3\2\0005\4\14\0'\5\15\0'\6\16\0B\3\4\1\18\3\2\0'\4\4\0'\5\17\0009\6\18\0015\a\19\0B\3\5\1\18\3\2\0'\4\4\0'\5\20\0009\6\21\0015\a\22\0B\3\5\1\18\3\2\0'\4\4\0'\5\23\0009\6\24\0015\a\25\0B\3\5\1\18\3\2\0'\4\4\0'\5\26\0009\6\27\0015\a\28\0B\3\5\1\18\3\2\0'\4\4\0'\5\29\0003\6\30\0005\a\31\0B\3\5\1\18\3\2\0'\4\4\0'\5 \0009\6!\0015\a\"\0B\3\5\1\18\3\2\0'\4\4\0'\5#\0009\6$\0015\a%\0B\3\5\1\18\3\2\0'\4\4\0'\5&\0003\6'\0005\a(\0B\3\5\1\18\3\2\0'\4\4\0'\5)\0009\6*\0015\a+\0B\3\5\1\18\3\2\0'\4\4\0'\5,\0009\6-\0015\a.\0B\3\5\1\18\3\2\0005\4/\0'\0050\0'\0061\0B\3\4\0012\0\0�K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\1\tdesc\24gitsigns setloclist\15setloclist\15<leader>hl\1\0\1\tdesc\28gitsigns toggle_deleted\19toggle_deleted\15<leader>ht\1\0\1\tdesc\25gitsigns diffthis(~)\0\15<leader>hD\1\0\1\tdesc\22gitsigns diffthis\rdiffthis\15<leader>hd\1\0\1\tdesc'gitsigns toggle_current_line_blame\30toggle_current_line_blame\15<leader>hb\1\0\1\tdesc\"gitsigns blame_line full=true\0\15<leader>hf\1\0\1\tdesc\26gitsigns preview_hunk\17preview_hunk\15<leader>hp\1\0\1\tdesc\26gitsigns reset_buffer\17reset_buffer\15<leader>hR\1\0\1\tdesc#gitsigns undo_stage_stage_hunk\20undo_stage_hunk\15<leader>hu\1\0\1\tdesc\26gitsigns stage_buffer\17stage_buffer\15<leader>hS\29:Gitsigns reset_hunk<CR>\15<leader>hr\1\3\0\0\6n\6v\29:Gitsigns stage_hunk<CR>\15<leader>hs\1\3\0\0\6n\6v\1\0\2\texpr\2\tdesc\22gitsign prev_hunk\0\a[g\1\0\2\texpr\2\tdesc\22gitsign next_hunk\0\a]g\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/gitsigns.nvim",
    url = "https://github.com/lewis6991/gitsigns.nvim"
  },
  ["gruvbox-material"] = {
    config = { "\27LJ\2\2�\a\0\0\3\0\18\0'6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0'\1\4\0=\1\3\0006\0\0\0009\0\5\0'\1\a\0=\1\6\0006\0\0\0009\0\5\0)\1\1\0=\1\b\0006\0\0\0009\0\t\0009\0\n\0'\1\v\0+\2\1\0B\0\3\0016\0\0\0009\0\5\0)\1\1\0=\1\f\0006\0\0\0009\0\5\0)\1\1\0=\1\r\0006\0\0\0009\0\5\0'\1\15\0=\1\14\0006\0\0\0009\0\16\0'\1\17\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\fcolored-gruvbox_material_diagnostic_virtual_text/gruvbox_material_diagnostic_line_highlight/gruvbox_material_diagnostic_text_highlight�\4        augroup nord-theme-overrides\n          autocmd!\n          autocmd ColorScheme gruvbox-material highlight Folded ctermfg=LightGray guifg=#918d88\n          autocmd ColorScheme gruvbox-material highlight Folded ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight Folded cterm=italic gui=italic\n          autocmd ColorScheme gruvbox-material highlight SignColumn ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight DiagnosticSign ctermbg=235 guibg=#282828\n        augroup END\n      \14nvim_exec\bapi(gruvbox_material_better_performance\thard gruvbox_material_background\6g\tdark\15background\18termguicolors\bopt\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/gruvbox-material",
    url = "https://github.com/sainnhe/gruvbox-material"
  },
  ["hop.nvim"] = {
    config = { "\27LJ\2\2�\a\0\0\5\0\22\00056\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0B\0\4\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0B\0\4\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\14\0'\3\15\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\18\0'\3\19\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\20\0'\3\21\0004\4\0\0B\0\5\1K\0\1\0�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })<CR>\6T�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })<CR>\6t�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true })<CR>\6F�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true })<CR>\6f\20nvim_set_keymap\bapi\22<Cmd>HopChar1<CR>\14<Leader>f\21<Cmd>HopWord<CR>\14<Leader>w\5\bset\vkeymap\bvim\1\0\1\tkeys\28etovxqpdygfblzhckisuran\nsetup\bhop\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/hop.nvim",
    url = "https://github.com/phaazon/hop.nvim"
  },
  ["indent-blankline.nvim"] = {
    config = { "\27LJ\2\2�\2\0\0\3\0\f\0\0296\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0+\1\2\0=\1\3\0006\0\0\0009\0\1\0009\0\4\0\18\1\0\0009\0\5\0'\2\6\0B\0\3\0016\0\0\0009\0\1\0009\0\4\0\18\1\0\0009\0\5\0'\2\a\0B\0\3\0016\0\b\0'\1\t\0B\0\2\0029\0\n\0005\1\v\0B\0\2\1K\0\1\0\1\0\3\25show_current_context\2\25space_char_blankline\6 \31show_current_context_start\2\nsetup\21indent_blankline\frequire\feol:↴\14space:⋅\vappend\14listchars\tlist\18termguicolors\bopt\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/indent-blankline.nvim",
    url = "https://github.com/lukas-reineke/indent-blankline.nvim"
  },
  ["lspkind-nvim"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/lspkind-nvim",
    url = "https://github.com/onsails/lspkind-nvim"
  },
  ["lspsaga.nvim"] = {
    config = { "\27LJ\2\2y\0\0\4\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\4\0005\3\3\0=\3\5\2B\1\2\1K\0\1\0\26code_action_lightbulb\1\0\0\1\0\2\tsign\2\17virtual_text\1\18init_lsp_saga\flspsaga\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/lspsaga.nvim",
    url = "https://github.com/glepnir/lspsaga.nvim"
  },
  ["lualine.nvim"] = {
    config = { "\27LJ\2\2�\1\0\0\5\0\f\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0004\3\3\0005\4\3\0>\4\1\3=\3\5\2=\2\a\0015\2\b\0=\2\t\0015\2\n\0=\2\v\1B\0\2\1K\0\1\0\15extensions\1\4\0\0\14nvim-tree\rquickfix\15toggleterm\foptions\1\0\1\ntheme\21gruvbox-material\rsections\1\0\0\14lualine_a\1\0\0\1\2\1\0\rfilename\tpath\3\3\nsetup\flualine\frequire\0" },
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
    config = { "\27LJ\2\2I\0\0\3\1\6\0\t6\0\0\0009\0\1\0009\0\2\0009\0\3\0005\1\4\0-\2\0\0=\2\5\1B\0\2\1K\0\1\0\1�\nbufnr\1\0\0\vformat\bbuf\blsp\bvim�\1\1\2\6\1\r\0\0269\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19�6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\2'\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0012\0\0�K\0\1\0\0�\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_method�\a\1\0\b\0+\0�\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0004\2\0\0B\0\3\0026\1\4\0'\2\5\0B\1\2\0029\2\6\0015\3'\0004\4\28\0009\5\a\0019\5\b\0059\5\t\5>\5\1\0049\5\a\0019\5\b\0059\5\n\5>\5\2\0049\5\a\0019\5\v\0059\5\f\5>\5\3\0049\5\a\0019\5\v\0059\5\r\5>\5\4\0049\5\a\0019\5\v\0059\5\t\5>\5\5\0049\5\a\0019\5\v\0059\5\14\5>\5\6\0049\5\a\0019\5\v\0059\5\15\5>\5\a\0049\5\a\0019\5\v\0059\5\16\5>\5\b\0049\5\a\0019\5\v\0059\5\17\5>\5\t\0049\5\a\0019\5\v\0059\5\18\0059\5\19\0055\6\21\0005\a\20\0=\a\22\6B\5\2\2>\5\n\0049\5\a\0019\5\v\0059\5\23\5>\5\v\0049\5\a\0019\5\v\0059\5\24\5>\5\f\0049\5\a\0019\5\v\0059\5\25\5>\5\r\0049\5\a\0019\5\v\0059\5\26\5>\5\14\0049\5\a\0019\5\v\0059\5\27\5>\5\15\0049\5\a\0019\5\28\0059\5\29\5>\5\16\0049\5\a\0019\5\28\0059\5\r\5>\5\17\0049\5\a\0019\5\28\0059\5\30\5>\5\18\0049\5\a\0019\5\28\0059\5\31\5>\5\19\0049\5\a\0019\5\28\0059\5\16\5>\5\20\0049\5\a\0019\5\28\0059\5 \5>\5\21\0049\5\a\0019\5\28\0059\5\18\0059\5\19\0055\6\"\0005\a!\0=\a\22\6B\5\2\2>\5\22\0049\5\a\0019\5\28\0059\5\24\5>\5\23\0049\5\a\0019\5\28\0059\5#\5>\5\24\0049\5\a\0019\5\28\0059\5$\5>\5\25\0049\5\a\0019\5\28\0059\5\23\5>\5\26\0049\5\a\0019\5%\0059\5&\5>\5\27\4=\4(\0033\4)\0=\4*\3B\2\2\0012\0\0�K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prettierd\16fish_indent\rbeautysh\15formatting\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\18LspFormatting\24nvim_create_augroup\bapi\bvim\0" },
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
  ["nvim-bqf"] = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-bqf",
    url = "https://github.com/kevinhwang91/nvim-bqf"
  },
  ["nvim-cmp"] = {
    config = { "\27LJ\2\2�\1\0\0\a\0\b\2!6\0\0\0006\1\1\0009\1\2\0019\1\3\1)\2\0\0B\1\2\0A\0\0\3\b\1\0\0X\2\20�6\2\1\0009\2\2\0029\2\4\2)\3\0\0\23\4\1\0\18\5\0\0+\6\2\0B\2\5\2:\2\1\2\18\3\2\0009\2\5\2\18\4\1\0\18\5\1\0B\2\4\2\18\3\2\0009\2\6\2'\4\a\0B\2\3\2\n\2\0\0X\2\2�+\2\1\0X\3\1�+\2\2\0L\2\2\0\a%s\nmatch\bsub\23nvim_buf_get_lines\24nvim_win_get_cursor\bapi\bvim\vunpack\0\2�\1\0\1\4\2\a\0!6\1\0\0'\2\1\0B\1\2\2-\2\0\0009\2\2\2B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\3\2B\2\1\1X\2\20�9\2\4\1B\2\1\2\15\0\2\0X\3\6�6\2\0\0'\3\1\0B\2\2\0029\2\5\2B\2\1\1X\2\n�-\2\1\0B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\6\2B\2\1\1X\2\2�\18\2\0\0B\2\1\1K\0\1\0\0�\2�\rcomplete\19expand_or_jump\31expand_or_locally_jumpable\21select_next_item\fvisible\fluasnip\frequire�\1\0\1\4\1\6\0\0266\1\0\0'\2\1\0B\1\2\2-\2\0\0009\2\2\2B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\3\2B\2\1\1X\2\r�9\2\4\1)\3��B\2\2\2\15\0\2\0X\3\6�6\2\0\0'\3\1\0B\2\2\0029\2\5\2B\2\1\1X\2\2�\18\2\0\0B\2\1\1K\0\1\0\0�\14jump_prev\21locally_jumpable\21select_prev_item\fvisible\fluasnip\frequireC\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5�-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2�\18\1\0\0B\1\1\1K\0\1\0\0�\1\0\1\vselect\2\fconfirm\fvisible0\0\1\2\0\2\0\a9\1\0\0\6\1\1\0X\1\2�+\1\1\0X\2\1�+\1\2\0L\1\2\0\fnull-ls\tnameS\1\1\4\0\b\0\n6\1\0\0009\1\1\0019\1\2\0019\1\3\0015\2\5\0003\3\4\0=\3\6\2=\0\a\2B\1\2\1K\0\1\0\nbufnr\vfilter\1\0\0\0\vformat\bbuf\blsp\bvim\27\0\0\2\2\0\0\4-\0\0\0-\1\1\0B\0\2\1K\0\1\0\1\0\1�I\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20lsp_definitions\22telescope.builtin\frequireM\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\24lsp_implementations\22telescope.builtin\frequired\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintN\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\25lsp_type_definitions\22telescope.builtin\frequireH\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\19lsp_references\22telescope.builtin\frequireW\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\"lsp_dynamic_workspace_symbols\22telescope.builtin\frequireN\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\25lsp_document_symbols\22telescope.builtin\frequireE\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\16diagnostics\22telescope.builtin\frequire�\17\1\2\a\2S\0�\0019\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19�6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\0025\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0016\2\2\0009\2\3\0029\2\r\2\18\3\1\0'\4\14\0'\5\15\0B\2\4\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\19\0006\5\2\0009\5\20\0059\5\21\0059\5\22\0055\6\23\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\24\0003\5\25\0005\6\26\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\27\0006\5\2\0009\5\20\0059\5\21\0059\5\28\0055\6\29\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\30\0003\5\31\0005\6 \0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4!\0006\5\2\0009\5\20\0059\5\21\0059\5\"\0055\6#\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4$\0006\5\2\0009\5\20\0059\5\21\0059\5%\0055\6&\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4'\0006\5\2\0009\5\20\0059\5\21\0059\5(\0055\6)\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4*\0003\5+\0005\6,\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4-\0003\5.\0005\6/\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0040\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0062\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0043\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0064\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0045\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0067\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0048\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0069\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4:\0003\5;\0005\6<\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4=\0006\5\2\0009\5\20\0059\5\21\0059\5>\0055\6?\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4@\0003\5A\0005\6B\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4C\0003\5D\0005\6E\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4F\0006\5\2\0009\5G\0059\5H\0055\6I\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4J\0006\5\2\0009\5G\0059\5K\0055\6L\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4M\0006\5\2\0009\5G\0059\5N\0055\6O\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4P\0003\5Q\0005\6R\0B\2\5\0012\0\0�K\0\1\0\a�\6�\1\0\1\tdesc\26telescope diagnostics\0\14<Leader>E\1\0\1\tdesc\25diagnostic goto_next\14goto_next\a]e\1\0\1\tdesc\25diagnostic goto_prev\14goto_prev\a[e\1\0\1\tdesc\26diagnostic open_float\15open_float\15diagnostic\14<Leader>e\1\0\1\tdesc!vim.lsp lsp_document_symbols\0\22<Leader><Leader>s\1\0\1\tdesc*vim.lsp lsp_dynamic_workspace_symbols\0\14<Leader>s\1\0\1\tdesc\19vim.lsp format\vformat\t<F8>\1\0\1\tdesc\27vim.lsp.buf.references\0\agr\1\0\1\tdesc\24vim.lsp code_action\t<F7>\1\0\1\tdesc\24vim.lsp code_action\16code_action\15<Leader>ca\1\0\1\tdesc\19vim.lsp rename\t<F2>\1\0\1\tdesc\19vim.lsp rename\vrename\15<Leader>rn\1\0\1\tdesc vim.lsp.buf.type_definition\0\14<Leader>D\1\0\1\tdesc#vim.lsp list_workspace_folders\0\23<Leader><Leader>wl\1\0\1\tdesc$vim.lsp remove_workspace_folder\28remove_workspace_folder\23<Leader><Leader>wr\1\0\1\tdesc!vim.lsp add_workspace_folder\25add_workspace_folder\23<Leader><Leader>wa\1\0\1\tdesc\27vim.lsp signature_help\19signature_help\agk\1\0\1\tdesc\31vim.lsp.buf.implementation\0\agi\1\0\1\tdesc\18vim.lsp hover\nhover\6K\1\0\1\tdesc\27vim.lsp.buf.definition\0\agd\1\0\1\tdesc\23vim.lsp delaration\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\rcallback\0\1\0\0\1\2\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodV\0\1\4\3\4\0\n-\1\0\0008\1\0\0019\1\0\0015\2\1\0-\3\1\0=\3\2\2-\3\2\0=\3\3\2B\1\2\1K\0\1\0\t�\5�\b�\14on_attach\18capabilitiies\1\0\0\nsetup�\1\0\0\6\3\r\0\18-\0\0\0009\0\0\0009\0\1\0005\1\2\0-\2\1\0=\2\3\1-\2\2\0=\2\4\0015\2\n\0005\3\b\0005\4\6\0005\5\5\0=\5\a\4=\4\t\3=\3\v\2=\2\f\1B\0\2\1K\0\1\0\t�\5�\b�\rsettings\bLua\1\0\0\16diagnostics\1\0\0\fglobals\1\0\0\1\2\0\0\bvim\14on_attach\18capabilitiies\1\0\0\nsetup\16sumneko_lua�\n\1\0\r\0L\0�\0016\0\0\0'\1\1\0B\0\2\0026\1\0\0'\2\2\0B\1\2\0023\2\3\0003\3\4\0003\4\5\0009\5\6\0005\6\n\0005\a\b\0003\b\a\0=\b\t\a=\a\v\0064\a\0\0=\a\f\0069\a\r\0009\a\14\a9\a\15\a5\b\17\0009\t\r\0009\t\16\t)\n��B\t\2\2=\t\18\b9\t\r\0009\t\16\t)\n\4\0B\t\2\2=\t\19\b9\t\r\0\18\n\3\0B\t\2\2=\t\20\b9\t\r\0\18\n\4\0B\t\2\2=\t\21\b9\t\r\0009\t\22\tB\t\1\2=\t\23\b9\t\r\0009\t\24\tB\t\1\2=\t\25\b9\t\r\0009\t\24\tB\t\1\2=\t\26\b3\t\27\0=\t\28\bB\a\2\2=\a\r\0069\a\29\0009\a\30\a4\b\b\0005\t\31\0>\t\1\b5\t \0>\t\2\b5\t!\0>\t\3\b5\t\"\0>\t\4\b5\t#\0>\t\5\b5\t$\0>\t\6\b4\t\3\0005\n%\0>\n\1\t>\t\a\bB\a\2\2=\a\30\0065\a*\0009\b&\0015\t'\0005\n(\0=\n)\tB\b\2\2=\b+\a=\a,\6B\5\2\0019\5\6\0009\5-\5'\6.\0005\a1\0009\b\29\0009\b\30\b4\t\3\0005\n/\0>\n\1\t5\n0\0>\n\2\tB\b\2\2=\b\30\aB\5\3\0019\5\6\0009\0052\5'\0063\0005\a4\0009\b\r\0009\b\14\b9\b2\bB\b\1\2=\b\r\a4\b\3\0005\t5\0>\t\1\b=\b\30\aB\5\3\0019\5\6\0009\0052\5'\0066\0005\a7\0009\b\r\0009\b\14\b9\b2\bB\b\1\2=\b\r\a9\b\29\0009\b\30\b4\t\3\0005\n8\0>\n\1\t5\n9\0>\n\2\tB\b\2\2=\b\30\aB\5\3\0016\5\0\0'\6:\0B\5\2\0029\5;\0056\6<\0009\6=\0069\6>\0069\6?\6B\6\1\0A\5\0\0023\6@\0006\a<\0009\aA\a9\aB\a'\bC\0004\t\0\0B\a\3\0023\bD\0006\t\0\0'\nE\0B\t\2\0026\n\0\0'\vF\0B\n\2\0029\nG\n5\vJ\0003\fH\0>\f\1\v3\fI\0=\fK\vB\n\2\0012\0\0�K\0\1\0\16sumneko_lua\1\0\0\0\0\19setup_handlers\20mason-lspconfig\14lspconfig\0\18LspFormatting\24nvim_create_augroup\bapi\0\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\15formatting\vformat\1\0\0\15symbol_map\1\0\1\fCopilot\b\1\0\2\tmode\vsymbol\14max_width\0032\15cmp_format\1\0\1\tname\vbuffer\1\0\1\tname\vcrates\1\0\1\tname\nspell\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\1\0\1\tname\fcopilot\fsources\vconfig\t<CR>\0\n<Esc>\n<C-e>\nabort\14<C-Space>\rcomplete\f<S-Tab>\n<Tab>\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\0\0\0\flspkind\bcmp\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-cmp",
    url = "https://github.com/hrsh7th/nvim-cmp"
  },
  ["nvim-colorizer.lua"] = {
    config = { "\27LJ\2\0027\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\14colorizer\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-colorizer.lua",
    url = "https://github.com/NvChad/nvim-colorizer.lua"
  },
  ["nvim-dap"] = {
    config = { "\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequire�\5\1\0\5\0 \0Q6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0005\4\6\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\b\0005\4\t\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\n\0005\4\v\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\15\0005\4\16\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\17\0003\3\18\0005\4\19\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0005\4\22\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\23\0003\3\24\0005\4\25\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\26\0003\3\27\0005\4\28\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\29\0003\3\30\0005\4\31\0B\0\5\1K\0\1\0\1\0\1\tdesc\24nvim-dap run_last()\0\15<Leader>dr\1\0\1\tdesc\25nvim-dap repl_open()\0\15<Leader>do\1\0\1\tdesc3nvim-dap set_breakpoint with log point message\0\16<Leader>dbm\1\0\1\tdesc+nvim-dap set_breakpoint with condition\0\16<Leader>dbc\1\0\1\tdesc\31nvim-dap toggle_breakpoint\0\15<Leader>db\1\0\1\tdesc\24nvim-dap step_out()\0\1\0\1\tdesc\24nvim-dap step_out()\0\n<F12>\1\0\1\tdesc\25nvim-dap step_into()\0\1\0\1\tdesc\25nvim-dap step_over()\0\n<F10>\1\0\1\tdesc\22nvim-dap continue\0\t<F5>\6n\bset\vkeymap\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-dap",
    url = "https://github.com/mfussenegger/nvim-dap"
  },
  ["nvim-dap-ui"] = {
    config = { "\27LJ\2\2\30\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\topen\31\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\nclose\31\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\nclose�\1\1\0\4\0\14\0\0296\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0026\1\0\0'\2\1\0B\1\2\0029\2\4\0009\2\5\0029\2\6\0023\3\b\0=\3\a\0029\2\4\0009\2\t\0029\2\n\0023\3\v\0=\3\a\0029\2\4\0009\2\t\0029\2\f\0023\3\r\0=\3\a\0022\0\0�K\0\1\0\0\17event_exited\0\21event_terminated\vbefore\0\17dapui_config\22event_initialized\nafter\14listeners\bdap\nsetup\ndapui\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-dap-ui",
    url = "https://github.com/rcarriga/nvim-dap-ui"
  },
  ["nvim-lspconfig"] = {
    config = { "\27LJ\2\2�\2\0\0\n\0\18\0\"5\0\0\0006\1\1\0\18\2\0\0B\1\2\4H\4\r�'\6\2\0\18\a\4\0&\6\a\0066\a\3\0009\a\4\a9\a\5\a\18\b\6\0005\t\6\0=\5\a\t=\5\b\t=\6\t\t=\6\n\tB\a\3\1F\4\3\3R\4�\1276\1\3\0009\1\v\0019\1\f\0016\2\3\0009\2\v\0029\2\14\0026\3\3\0009\3\v\0039\3\15\0039\3\16\0035\4\17\0B\2\3\2=\2\r\1K\0\1\0\1\0\1\21update_in_insert\2\27on_publish_diagnostics\15diagnostic\twith$textDocument/publishDiagnostics\rhandlers\blsp\nnumhl\vtexthl\ttext\ticon\1\0\0\16sign_define\afn\bvim\19DiagnosticSign\npairs\1\0\4\tInfo\t \tHint\t \nError\t \tWarn\t \0" },
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
    config = { "\27LJ\2\2@\0\0\3\0\3\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0+\1\2\0+\2\1\0B\0\3\1K\0\1\0\vtoggle\14nvim-tree\frequire�\1\1\0\5\0\r\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\n\0003\3\v\0005\4\f\0B\0\5\1K\0\1\0\1\0\1\tdesc\21toggle nvim-tree\0\n<C-q>\6n\bset\vkeymap\bvim\24update_focused_file\1\0\2\16update_root\2\venable\2\1\0\2\20respect_buf_cwd\2\23sync_root_with_cwd\2\nsetup\14nvim-tree\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/nvim-tree.lua",
    url = "https://github.com/kyazdani42/nvim-tree.lua"
  },
  ["nvim-treesitter"] = {
    config = { "\27LJ\2\2�\3\0\0\4\0\20\0\0236\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\0015\2\14\0=\2\15\0015\2\16\0=\2\17\0015\2\18\0=\2\19\1B\0\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\fendwise\1\0\1\venable\2\fmatchup\1\0\1\venable\2\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\17<Leader><CR>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0" },
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
    config = { "\27LJ\2\2M\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\rprojects\15extensions\14telescope\frequire�\3\1\0\5\0\18\0\0256\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\0015\2\6\0=\2\a\1B\0\2\0016\0\0\0'\1\b\0B\0\2\0029\0\t\0'\1\n\0B\0\2\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\15\0003\3\16\0005\4\17\0B\0\5\1K\0\1\0\1\0\1\tdesc\23telescope projects\0\v<C-k>p\6n\bset\vkeymap\bvim\rprojects\19load_extension\14telescope\rpatterns\1\n\0\0\t.git\v_darcs\b.hg\t.bzr\t.svn\rMakefile\rRakefile\17package.json\16selene.toml\22detection_methods\1\0\3\17silent_chdir\1\16show_hidden\1\16scope_chdir\vglobal\1\3\0\0\fpattern\blsp\nsetup\17project_nvim\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/project.nvim",
    url = "https://github.com/ahmedkhalf/project.nvim"
  },
  ["rust-tools.nvim"] = {
    config = { "\27LJ\2\2p\0\2\a\1\b\0\f6\2\0\0009\2\1\0029\2\2\2'\3\3\0'\4\4\0-\5\0\0009\5\5\0059\5\5\0055\6\6\0=\1\a\6B\2\5\1K\0\1\0\0�\vbuffer\1\0\0\22code_action_group\14<Leader>a\6n\bset\vkeymap\bvim|\1\0\5\0\b\0\f6\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\3\0005\3\5\0003\4\4\0=\4\6\3=\3\a\2B\1\2\0012\0\0�K\0\1\0\vserver\14on_attach\1\0\0\0\1\0\1\23hover_with_actions\2\nsetup\15rust-tools\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/rust-tools.nvim",
    url = "https://github.com/simrat39/rust-tools.nvim"
  },
  ["telescope-file-browser.nvim"] = {
    config = { "\27LJ\2\2Q\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequire�\1\1\0\5\0\v\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0003\3\t\0005\4\n\0B\0\5\1K\0\1\0\1\0\1\tdesc\27telescope file browser\0\v<C-k>z\6n\bset\vkeymap\bvim\17file_browser\19load_extension\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-file-browser.nvim",
    url = "https://github.com/nvim-telescope/telescope-file-browser.nvim"
  },
  ["telescope-fzf-native.nvim"] = {
    config = { "\27LJ\2\2H\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\bfzf\19load_extension\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-fzf-native.nvim",
    url = "https://github.com/nvim-telescope/telescope-fzf-native.nvim"
  },
  ["telescope-ghq.nvim"] = {
    config = { "\27LJ\2\2�\1\0\0\5\0\v\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0005\4\n\0B\0\5\1K\0\1\0\1\0\1\tdesc\18telescope ghq <Cmd>Telescope ghq list<CR>\v<C-k>g\6n\bset\vkeymap\bvim\bghq\19load_extension\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-ghq.nvim",
    url = "https://github.com/nvim-telescope/telescope-ghq.nvim"
  },
  ["telescope-live-grep-args.nvim"] = {
    config = { "\27LJ\2\2S\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\19live_grep_args\19load_extension\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-live-grep-args.nvim",
    url = "https://github.com/nvim-telescope/telescope-live-grep-args.nvim"
  },
  ["telescope-ui-select.nvim"] = {
    config = { "\27LJ\2\2N\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\14ui-select\19load_extension\14telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope-ui-select.nvim",
    url = "https://github.com/nvim-telescope/telescope-ui-select.nvim"
  },
  ["telescope.nvim"] = {
    config = { "\27LJ\2\2C\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14help_tags\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireS\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\19live_grep_args\15extensions\14telescope\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\roldfiles\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15git_status\22telescope.builtin\frequire?\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nmarks\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20quickfixhistory\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\floclist\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rjumplist\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fkeymaps\22telescope.builtin\frequire�\v\1\0\t\0J\0�\0016\0\0\0'\1\1\0B\0\2\0026\1\0\0'\2\2\0B\1\2\0026\2\0\0'\3\3\0B\2\2\0029\2\4\0025\3\14\0005\4\f\0005\5\b\0005\6\6\0009\a\5\0=\a\a\6=\6\t\0055\6\n\0009\a\5\0=\a\a\6=\6\v\5=\5\r\4=\4\15\0035\4\17\0005\5\16\0=\5\18\0045\5\19\0005\6\23\0005\a\21\0009\b\20\1B\b\1\2=\b\22\a=\a\t\6=\6\r\5=\5\24\4=\4\25\3B\2\2\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4\29\0003\5\30\0005\6\31\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4 \0003\5!\0005\6\"\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4#\0003\5$\0005\6%\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4&\0003\5'\0005\6(\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4)\0003\5*\0005\6+\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4,\0003\5-\0005\6.\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4/\0003\0050\0005\0061\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0042\0003\0053\0005\0064\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0045\0003\0056\0005\0067\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0048\0003\0059\0005\6:\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4;\0003\5<\0005\6=\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4>\0003\5?\0005\6@\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4A\0003\5B\0005\6C\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4D\0003\5E\0005\6F\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4G\0003\5H\0005\6I\0B\2\5\1K\0\1\0\1\0\1\tdesc\22telescope keymaps\0\v<C-k>m\1\0\1\tdesc\23telescope jumplist\0\v<C-k>j\1\0\1\tdesc\22telescope loclist\0\v<C-k>l\1\0\1\tdesc\31telescope quickfix history\0\v<C-k>w\1\0\1\tdesc\23telescope quickfix\0\v<C-k>q\1\0\1\tdesc\20telescope marks\0\v<C-k>r\1\0\1\tdesc\25telescope git status\0\v<C-k>s\1\0\1\tdesc\27telescope git branches\0\16<C-k><C-k>b\1\0\1\tdesc\23telescope commands\0\v<C-k>c\1\0\1\tdesc\30telescope command history\0\v<C-k>h\1\0\1\tdesc\24telescope old files\0\v<C-k>o\1\0\1\tdesc\22telescope buffers\0\6q\1\0\1\tdesc\24telescope live grep\0\n<C-g>\1\0\1\tdesc\25telescope find files\0\n<C-p>\1\0\1\tdesc\24telescope help_tags\0\t<F1>\bset\vkeymap\bvim\15extensions\19live_grep_args\1\0\0\n<C-k>\1\0\0\17quote_prompt\1\0\1\17auto_quoting\2\bfzf\1\0\0\1\0\4\28override_generic_sorter\2\14case_mode\15smart_case\25override_file_sorter\2\nfuzzy\2\rdefaults\1\0\0\rmappings\1\0\0\6n\1\0\0\6i\1\0\0\n<c-t>\1\0\0\22open_with_trouble\nsetup\14telescope%telescope-live-grep-args.actions trouble.providers.telescope\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/telescope.nvim",
    url = "https://github.com/nvim-telescope/telescope.nvim"
  },
  ["toggle-lsp-diagnostics.nvim"] = {
    config = { "\27LJ\2\2T\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\1K\0\1\0\1\0\1\rstart_on\2\tinit\27toggle_lsp_diagnostics\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/toggle-lsp-diagnostics.nvim",
    url = "https://github.com/WhoIsSethDaniel/toggle-lsp-diagnostics.nvim"
  },
  ["toggleterm.nvim"] = {
    config = { "\27LJ\2\2y\0\1\2\0\6\1\0159\1\0\0\a\1\1\0X\1\3�)\1\20\0L\1\2\0X\1\b�9\1\0\0\a\1\2\0X\1\5�6\1\3\0009\1\4\0019\1\5\1\24\1\0\1L\1\2\0K\0\1\0\fcolumns\6o\bvim\rvertical\15horizontal\14direction��̙\19����\3$\0\0\2\1\1\0\5-\0\0\0\18\1\0\0009\0\0\0B\0\2\1K\0\1\0\1�\vtoggle�\4\1\0\a\0\30\0<6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0003\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0005\1\t\0'\2\n\0'\3\v\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\f\0'\2\r\0'\3\14\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\15\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\18\0'\2\19\0'\3\17\0004\4\0\0B\0\5\0016\0\0\0'\1\20\0B\0\2\0029\0\21\0\18\2\0\0009\1\22\0005\3\23\0B\1\3\0023\2\24\0007\2\25\0006\2\6\0009\2\a\0029\2\b\2'\3\26\0'\4\27\0'\5\28\0005\6\29\0B\2\5\0012\0\0�K\0\1\0\1\0\1\tdesc\flazygit#<Cmd>lua _lazygit_toggle()<CR>\n<A-g>\6n\20_lazygit_toggle\0\1\0\4\vhidden\2\bcmd\flazygit\14direction\nfloat\ncount\3d\bnew\rTerminal\24toggleterm.terminal\t<F6>\1\3\0\0\6n\6t*<Cmd>10ToggleTerm direction=float<CR>\14<Leader>y\1\2\0\0\6n!<Cmd>ToggleTermToggleAll<CR>\15<Leader>at\1\2\0\0\6n)<Cmd>exe v:count1 . \"ToggleTerm\"<CR>\14<Leader>t\1\2\0\0\6n\bset\vkeymap\bvim\tsize\0\1\0\1\14direction\15horizontal\nsetup\15toggleterm\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/toggleterm.nvim",
    url = "https://github.com/akinsho/toggleterm.nvim"
  },
  ["trouble.nvim"] = {
    config = { "\27LJ\2\2�\4\0\0\5\0\20\00036\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\f\0'\3\r\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\14\0'\3\15\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\4\0009\0\18\0'\1\19\0B\0\2\1K\0\1\0<        cnoreabbrev copen TroubleToggle quickfix\n      \bcmd$<Cmd>TroubleToggle quickfix<CR>\15<Leader>xq#<Cmd>TroubleToggle loclist<CR>\15<Leader>xl0<Cmd>TroubleToggle document_diagnostics<CR>\15<Leader>xd1<Cmd>TroubleToggle workspace_diagnostics<CR>\15<Leader>xw\27<Cmd>TroubleToggle<CR>\15<Leader>xx\6n\bset\vkeymap\bvim\1\0\1\nicons\2\nsetup\ftrouble\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/trouble.nvim",
    url = "https://github.com/folke/trouble.nvim"
  },
  undotree = {
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/undotree",
    url = "https://github.com/mbbill/undotree"
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
  ["vim-ripgrep"] = {
    config = { "\27LJ\2\2^\0\1\4\0\5\0\t'\1\0\0009\2\1\0&\1\2\0016\2\2\0009\2\3\0029\2\4\2\18\3\1\0B\2\2\1K\0\1\0\19ripgrep#search\afn\bvim\targs\28--vimgrep --smart-case m\0\1\4\0\5\0\t'\1\0\0009\2\1\0&\1\2\0016\2\2\0009\2\3\0029\2\4\2\18\3\1\0B\2\2\1K\0\1\0\19ripgrep#search\afn\bvim\targs+--vimgrep --smart-case --no-ignore-vcs�\1\1\0\4\0\t\0\0156\0\0\0009\0\1\0009\0\2\0'\1\3\0003\2\4\0005\3\5\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\6\0003\2\a\0005\3\b\0B\0\4\1K\0\1\0\1\0\2\rcomplete\tfile\nnargs\6+\0\aGi\1\0\2\rcomplete\tfile\nnargs\6+\0\6G\29nvim_create_user_command\bapi\bvim\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/vim-ripgrep",
    url = "https://github.com/kyoh86/vim-ripgrep"
  },
  ["which-key.nvim"] = {
    config = { "\27LJ\2\2n\0\0\4\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\1K\0\1\0\fplugins\1\0\0\rspelling\1\0\0\1\0\1\fenabled\2\nsetup\14which-key\frequire\0" },
    loaded = true,
    path = "/home/shishi/.local/share/nvim/site/pack/packer/start/which-key.nvim",
    url = "https://github.com/folke/which-key.nvim"
  }
}

time([[Defining packer_plugins]], false)
-- Config for: nvim-treesitter
time([[Config for nvim-treesitter]], true)
try_loadstring("\27LJ\2\2�\3\0\0\4\0\20\0\0236\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\0015\2\6\0005\3\a\0=\3\b\2=\2\t\0015\2\n\0=\2\v\0015\2\f\0=\2\r\0015\2\14\0=\2\15\0015\2\16\0=\2\17\0015\2\18\0=\2\19\1B\0\2\1K\0\1\0\26context_commentstring\1\0\1\venable\2\fendwise\1\0\1\venable\2\fmatchup\1\0\1\venable\2\frainbow\1\0\2\18extended_mode\2\venable\2\vindent\1\0\1\venable\2\26incremental_selection\fkeymaps\1\0\4\19init_selection\t<CR>\21node_incremental\t<CR>\22scope_incremental\n<TAB>\21node_decremental\17<Leader><CR>\1\0\1\venable\2\14highlight\1\0\2&additional_vim_regex_highlighting\1\venable\2\1\0\1\17auto_install\2\nsetup\28nvim-treesitter.configs\frequire\0", "config", "nvim-treesitter")
time([[Config for nvim-treesitter]], false)
-- Config for: indent-blankline.nvim
time([[Config for indent-blankline.nvim]], true)
try_loadstring("\27LJ\2\2�\2\0\0\3\0\f\0\0296\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0+\1\2\0=\1\3\0006\0\0\0009\0\1\0009\0\4\0\18\1\0\0009\0\5\0'\2\6\0B\0\3\0016\0\0\0009\0\1\0009\0\4\0\18\1\0\0009\0\5\0'\2\a\0B\0\3\0016\0\b\0'\1\t\0B\0\2\0029\0\n\0005\1\v\0B\0\2\1K\0\1\0\1\0\3\25show_current_context\2\25space_char_blankline\6 \31show_current_context_start\2\nsetup\21indent_blankline\frequire\feol:↴\14space:⋅\vappend\14listchars\tlist\18termguicolors\bopt\bvim\0", "config", "indent-blankline.nvim")
time([[Config for indent-blankline.nvim]], false)
-- Config for: SmoothCursor.nvim
time([[Config for SmoothCursor.nvim]], true)
try_loadstring("\27LJ\2\2>\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\17smoothcursor\frequire\0", "config", "SmoothCursor.nvim")
time([[Config for SmoothCursor.nvim]], false)
-- Config for: telescope-ui-select.nvim
time([[Config for telescope-ui-select.nvim]], true)
try_loadstring("\27LJ\2\2N\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\14ui-select\19load_extension\14telescope\frequire\0", "config", "telescope-ui-select.nvim")
time([[Config for telescope-ui-select.nvim]], false)
-- Config for: nvim-dap
time([[Config for nvim-dap]], true)
try_loadstring("\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcontinue\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_over\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14step_into\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rstep_out\bdap\frequire=\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\22toggle_breakpoint\bdap\frequirer\0\0\3\0\a\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0006\1\3\0009\1\4\0019\1\5\1'\2\6\0B\1\2\0A\0\0\1K\0\1\0\27Breakpoint condition: \ninput\afn\bvim\19set_breakpoint\bdap\frequires\0\0\5\0\a\0\f6\0\0\0'\1\1\0B\0\2\0029\0\2\0,\1\2\0006\3\3\0009\3\4\0039\3\5\3'\4\6\0B\3\2\0A\0\2\1K\0\1\0\24Log point message: \ninput\afn\bvim\19set_breakpoint\bdap\frequire5\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14repl_open\bdap\frequire4\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rrun_last\bdap\frequire�\5\1\0\5\0 \0Q6\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\4\0003\3\5\0005\4\6\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\b\0005\4\t\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\a\0003\3\n\0005\4\v\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\r\0005\4\14\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\f\0003\3\15\0005\4\16\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\17\0003\3\18\0005\4\19\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\20\0003\3\21\0005\4\22\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\23\0003\3\24\0005\4\25\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\26\0003\3\27\0005\4\28\0B\0\5\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0'\2\29\0003\3\30\0005\4\31\0B\0\5\1K\0\1\0\1\0\1\tdesc\24nvim-dap run_last()\0\15<Leader>dr\1\0\1\tdesc\25nvim-dap repl_open()\0\15<Leader>do\1\0\1\tdesc3nvim-dap set_breakpoint with log point message\0\16<Leader>dbm\1\0\1\tdesc+nvim-dap set_breakpoint with condition\0\16<Leader>dbc\1\0\1\tdesc\31nvim-dap toggle_breakpoint\0\15<Leader>db\1\0\1\tdesc\24nvim-dap step_out()\0\1\0\1\tdesc\24nvim-dap step_out()\0\n<F12>\1\0\1\tdesc\25nvim-dap step_into()\0\1\0\1\tdesc\25nvim-dap step_over()\0\n<F10>\1\0\1\tdesc\22nvim-dap continue\0\t<F5>\6n\bset\vkeymap\bvim\0", "config", "nvim-dap")
time([[Config for nvim-dap]], false)
-- Config for: rust-tools.nvim
time([[Config for rust-tools.nvim]], true)
try_loadstring("\27LJ\2\2p\0\2\a\1\b\0\f6\2\0\0009\2\1\0029\2\2\2'\3\3\0'\4\4\0-\5\0\0009\5\5\0059\5\5\0055\6\6\0=\1\a\6B\2\5\1K\0\1\0\0�\vbuffer\1\0\0\22code_action_group\14<Leader>a\6n\bset\vkeymap\bvim|\1\0\5\0\b\0\f6\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\3\0005\3\5\0003\4\4\0=\4\6\3=\3\a\2B\1\2\0012\0\0�K\0\1\0\vserver\14on_attach\1\0\0\0\1\0\1\23hover_with_actions\2\nsetup\15rust-tools\frequire\0", "config", "rust-tools.nvim")
time([[Config for rust-tools.nvim]], false)
-- Config for: copilot-cmp
time([[Config for copilot-cmp]], true)
try_loadstring("\27LJ\2\2=\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\16copilot_cmp\frequire\0", "config", "copilot-cmp")
time([[Config for copilot-cmp]], false)
-- Config for: nvim-tree.lua
time([[Config for nvim-tree.lua]], true)
try_loadstring("\27LJ\2\2@\0\0\3\0\3\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0+\1\2\0+\2\1\0B\0\3\1K\0\1\0\vtoggle\14nvim-tree\frequire�\1\1\0\5\0\r\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0'\1\t\0'\2\n\0003\3\v\0005\4\f\0B\0\5\1K\0\1\0\1\0\1\tdesc\21toggle nvim-tree\0\n<C-q>\6n\bset\vkeymap\bvim\24update_focused_file\1\0\2\16update_root\2\venable\2\1\0\2\20respect_buf_cwd\2\23sync_root_with_cwd\2\nsetup\14nvim-tree\frequire\0", "config", "nvim-tree.lua")
time([[Config for nvim-tree.lua]], false)
-- Config for: toggleterm.nvim
time([[Config for toggleterm.nvim]], true)
try_loadstring("\27LJ\2\2y\0\1\2\0\6\1\0159\1\0\0\a\1\1\0X\1\3�)\1\20\0L\1\2\0X\1\b�9\1\0\0\a\1\2\0X\1\5�6\1\3\0009\1\4\0019\1\5\1\24\1\0\1L\1\2\0K\0\1\0\fcolumns\6o\bvim\rvertical\15horizontal\14direction��̙\19����\3$\0\0\2\1\1\0\5-\0\0\0\18\1\0\0009\0\0\0B\0\2\1K\0\1\0\1�\vtoggle�\4\1\0\a\0\30\0<6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0003\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0009\0\b\0005\1\t\0'\2\n\0'\3\v\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\f\0'\2\r\0'\3\14\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\15\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\6\0009\0\a\0009\0\b\0005\1\18\0'\2\19\0'\3\17\0004\4\0\0B\0\5\0016\0\0\0'\1\20\0B\0\2\0029\0\21\0\18\2\0\0009\1\22\0005\3\23\0B\1\3\0023\2\24\0007\2\25\0006\2\6\0009\2\a\0029\2\b\2'\3\26\0'\4\27\0'\5\28\0005\6\29\0B\2\5\0012\0\0�K\0\1\0\1\0\1\tdesc\flazygit#<Cmd>lua _lazygit_toggle()<CR>\n<A-g>\6n\20_lazygit_toggle\0\1\0\4\vhidden\2\bcmd\flazygit\14direction\nfloat\ncount\3d\bnew\rTerminal\24toggleterm.terminal\t<F6>\1\3\0\0\6n\6t*<Cmd>10ToggleTerm direction=float<CR>\14<Leader>y\1\2\0\0\6n!<Cmd>ToggleTermToggleAll<CR>\15<Leader>at\1\2\0\0\6n)<Cmd>exe v:count1 . \"ToggleTerm\"<CR>\14<Leader>t\1\2\0\0\6n\bset\vkeymap\bvim\tsize\0\1\0\1\14direction\15horizontal\nsetup\15toggleterm\frequire\0", "config", "toggleterm.nvim")
time([[Config for toggleterm.nvim]], false)
-- Config for: vim-illuminate
time([[Config for vim-illuminate]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\14configure\15illuminate\frequire\0", "config", "vim-illuminate")
time([[Config for vim-illuminate]], false)
-- Config for: gitsigns.nvim
time([[Config for gitsigns.nvim]], true)
try_loadstring("\27LJ\2\2W\0\4\t\1\4\0\14\14\0\3\0X\4\1�4\3\0\0-\4\0\0=\4\0\0036\4\1\0009\4\2\0049\4\3\4\18\5\0\0\18\6\1\0\18\a\2\0\18\b\3\0B\4\5\1K\0\1\0\0�\bset\vkeymap\bvim\vbuffer#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14next_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2�'\0\3\0002\0\a�6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0�L\0\2\0L\0\2\0\1�\r<Ignore>\0\rschedule\a]g\tdiff\awo\bvim#\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\0\0\14prev_hunkg\1\0\2\1\a\0\0156\0\0\0009\0\1\0009\0\2\0\15\0\0\0X\1\2�'\0\3\0002\0\a�6\0\0\0009\0\4\0003\1\5\0B\0\2\1'\0\6\0002\0\0�L\0\2\0L\0\2\0\1�\r<Ignore>\0\rschedule\a[g\tdiff\awo\bvim1\0\0\2\1\2\0\5-\0\0\0009\0\0\0005\1\1\0B\0\2\1K\0\1\0\1�\1\0\1\tfull\2\15blame_line(\0\0\2\1\2\0\5-\0\0\0009\0\0\0'\1\1\0B\0\2\1K\0\1\0\1�\6~\rdiffthis�\t\1\1\b\0002\0]6\1\0\0009\1\1\0019\1\2\0013\2\3\0\18\3\2\0'\4\4\0'\5\5\0003\6\6\0005\a\a\0B\3\5\1\18\3\2\0'\4\4\0'\5\b\0003\6\t\0005\a\n\0B\3\5\1\18\3\2\0005\4\v\0'\5\f\0'\6\r\0B\3\4\1\18\3\2\0005\4\14\0'\5\15\0'\6\16\0B\3\4\1\18\3\2\0'\4\4\0'\5\17\0009\6\18\0015\a\19\0B\3\5\1\18\3\2\0'\4\4\0'\5\20\0009\6\21\0015\a\22\0B\3\5\1\18\3\2\0'\4\4\0'\5\23\0009\6\24\0015\a\25\0B\3\5\1\18\3\2\0'\4\4\0'\5\26\0009\6\27\0015\a\28\0B\3\5\1\18\3\2\0'\4\4\0'\5\29\0003\6\30\0005\a\31\0B\3\5\1\18\3\2\0'\4\4\0'\5 \0009\6!\0015\a\"\0B\3\5\1\18\3\2\0'\4\4\0'\5#\0009\6$\0015\a%\0B\3\5\1\18\3\2\0'\4\4\0'\5&\0003\6'\0005\a(\0B\3\5\1\18\3\2\0'\4\4\0'\5)\0009\6*\0015\a+\0B\3\5\1\18\3\2\0'\4\4\0'\5,\0009\6-\0015\a.\0B\3\5\1\18\3\2\0005\4/\0'\0050\0'\0061\0B\3\4\0012\0\0�K\0\1\0#:<C-U>Gitsigns select_hunk<CR>\aih\1\3\0\0\6o\6x\1\0\1\tdesc\24gitsigns setloclist\15setloclist\15<leader>hl\1\0\1\tdesc\28gitsigns toggle_deleted\19toggle_deleted\15<leader>ht\1\0\1\tdesc\25gitsigns diffthis(~)\0\15<leader>hD\1\0\1\tdesc\22gitsigns diffthis\rdiffthis\15<leader>hd\1\0\1\tdesc'gitsigns toggle_current_line_blame\30toggle_current_line_blame\15<leader>hb\1\0\1\tdesc\"gitsigns blame_line full=true\0\15<leader>hf\1\0\1\tdesc\26gitsigns preview_hunk\17preview_hunk\15<leader>hp\1\0\1\tdesc\26gitsigns reset_buffer\17reset_buffer\15<leader>hR\1\0\1\tdesc#gitsigns undo_stage_stage_hunk\20undo_stage_hunk\15<leader>hu\1\0\1\tdesc\26gitsigns stage_buffer\17stage_buffer\15<leader>hS\29:Gitsigns reset_hunk<CR>\15<leader>hr\1\3\0\0\6n\6v\29:Gitsigns stage_hunk<CR>\15<leader>hs\1\3\0\0\6n\6v\1\0\2\texpr\2\tdesc\22gitsign prev_hunk\0\a[g\1\0\2\texpr\2\tdesc\22gitsign next_hunk\0\a]g\6n\0\rgitsigns\vloaded\fpackageP\1\0\3\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0003\2\3\0=\2\5\1B\0\2\1K\0\1\0\14on_attach\1\0\0\0\nsetup\rgitsigns\frequire\0", "config", "gitsigns.nvim")
time([[Config for gitsigns.nvim]], false)
-- Config for: bufferline.nvim
time([[Config for bufferline.nvim]], true)
try_loadstring("\27LJ\2\2W\0\4\b\0\5\0\14\18\5\1\0009\4\0\1'\6\1\0B\4\3\2\15\0\4\0X\5\2�'\4\2\0X\5\1�'\4\3\0'\5\4\0\18\6\4\0\18\a\0\0&\5\a\5L\5\2\0\6 \t \t \nerror\nmatch�\1\1\0\4\0\v\0\0156\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\3\0'\1\4\0B\0\2\0029\0\5\0005\1\t\0005\2\6\0003\3\a\0=\3\b\2=\2\n\1B\0\2\1K\0\1\0\foptions\1\0\0\26diagnostics_indicator\0\1\0\2\16diagnostics\rnvim_lsp\tmode\fbuffers\nsetup\15bufferline\frequire\18termguicolors\bopt\bvim\0", "config", "bufferline.nvim")
time([[Config for bufferline.nvim]], false)
-- Config for: vim-ripgrep
time([[Config for vim-ripgrep]], true)
try_loadstring("\27LJ\2\2^\0\1\4\0\5\0\t'\1\0\0009\2\1\0&\1\2\0016\2\2\0009\2\3\0029\2\4\2\18\3\1\0B\2\2\1K\0\1\0\19ripgrep#search\afn\bvim\targs\28--vimgrep --smart-case m\0\1\4\0\5\0\t'\1\0\0009\2\1\0&\1\2\0016\2\2\0009\2\3\0029\2\4\2\18\3\1\0B\2\2\1K\0\1\0\19ripgrep#search\afn\bvim\targs+--vimgrep --smart-case --no-ignore-vcs�\1\1\0\4\0\t\0\0156\0\0\0009\0\1\0009\0\2\0'\1\3\0003\2\4\0005\3\5\0B\0\4\0016\0\0\0009\0\1\0009\0\2\0'\1\6\0003\2\a\0005\3\b\0B\0\4\1K\0\1\0\1\0\2\rcomplete\tfile\nnargs\6+\0\aGi\1\0\2\rcomplete\tfile\nnargs\6+\0\6G\29nvim_create_user_command\bapi\bvim\0", "config", "vim-ripgrep")
time([[Config for vim-ripgrep]], false)
-- Config for: telescope-live-grep-args.nvim
time([[Config for telescope-live-grep-args.nvim]], true)
try_loadstring("\27LJ\2\2S\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\19live_grep_args\19load_extension\14telescope\frequire\0", "config", "telescope-live-grep-args.nvim")
time([[Config for telescope-live-grep-args.nvim]], false)
-- Config for: LuaSnip
time([[Config for LuaSnip]], true)
try_loadstring("\27LJ\2\2�\2\0\0\3\0\15\0(6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0005\1\4\0B\0\2\0016\0\0\0'\1\5\0B\0\2\0029\0\6\0B\0\1\0016\0\0\0'\1\5\0B\0\2\0029\0\6\0'\1\a\0B\0\2\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\t\0005\2\n\0B\0\3\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\v\0005\2\f\0B\0\3\0016\0\0\0'\1\1\0B\0\2\0029\0\b\0'\1\r\0005\2\14\0B\0\3\1K\0\1\0\1\2\0\0\thtml\20typescriptreact\1\2\0\0\thtml\20javascriptreact\1\2\0\0\nrails\truby\20filetype_extend\15./snippets\14lazy_load luasnip.loaders.from_vscode\1\0\1\fhistory\1\nsetup\vconfig\fluasnip\frequire\0", "config", "LuaSnip")
time([[Config for LuaSnip]], false)
-- Config for: nvim-cmp
time([[Config for nvim-cmp]], true)
try_loadstring("\27LJ\2\2�\1\0\0\a\0\b\2!6\0\0\0006\1\1\0009\1\2\0019\1\3\1)\2\0\0B\1\2\0A\0\0\3\b\1\0\0X\2\20�6\2\1\0009\2\2\0029\2\4\2)\3\0\0\23\4\1\0\18\5\0\0+\6\2\0B\2\5\2:\2\1\2\18\3\2\0009\2\5\2\18\4\1\0\18\5\1\0B\2\4\2\18\3\2\0009\2\6\2'\4\a\0B\2\3\2\n\2\0\0X\2\2�+\2\1\0X\3\1�+\2\2\0L\2\2\0\a%s\nmatch\bsub\23nvim_buf_get_lines\24nvim_win_get_cursor\bapi\bvim\vunpack\0\2�\1\0\1\4\2\a\0!6\1\0\0'\2\1\0B\1\2\2-\2\0\0009\2\2\2B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\3\2B\2\1\1X\2\20�9\2\4\1B\2\1\2\15\0\2\0X\3\6�6\2\0\0'\3\1\0B\2\2\0029\2\5\2B\2\1\1X\2\n�-\2\1\0B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\6\2B\2\1\1X\2\2�\18\2\0\0B\2\1\1K\0\1\0\0�\2�\rcomplete\19expand_or_jump\31expand_or_locally_jumpable\21select_next_item\fvisible\fluasnip\frequire�\1\0\1\4\1\6\0\0266\1\0\0'\2\1\0B\1\2\2-\2\0\0009\2\2\2B\2\1\2\15\0\2\0X\3\4�-\2\0\0009\2\3\2B\2\1\1X\2\r�9\2\4\1)\3��B\2\2\2\15\0\2\0X\3\6�6\2\0\0'\3\1\0B\2\2\0029\2\5\2B\2\1\1X\2\2�\18\2\0\0B\2\1\1K\0\1\0\0�\14jump_prev\21locally_jumpable\21select_prev_item\fvisible\fluasnip\frequireC\0\1\3\0\4\0\a6\1\0\0'\2\1\0B\1\2\0029\1\2\0019\2\3\0B\1\2\1K\0\1\0\tbody\15lsp_expand\fluasnip\frequireX\0\1\3\1\3\0\r-\1\0\0009\1\0\1B\1\1\2\15\0\1\0X\2\5�-\1\0\0009\1\1\0015\2\2\0B\1\2\1X\1\2�\18\1\0\0B\1\1\1K\0\1\0\0�\1\0\1\vselect\2\fconfirm\fvisible0\0\1\2\0\2\0\a9\1\0\0\6\1\1\0X\1\2�+\1\1\0X\2\1�+\1\2\0L\1\2\0\fnull-ls\tnameS\1\1\4\0\b\0\n6\1\0\0009\1\1\0019\1\2\0019\1\3\0015\2\5\0003\3\4\0=\3\6\2=\0\a\2B\1\2\1K\0\1\0\nbufnr\vfilter\1\0\0\0\vformat\bbuf\blsp\bvim\27\0\0\2\2\0\0\4-\0\0\0-\1\1\0B\0\2\1K\0\1\0\1\0\1�I\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20lsp_definitions\22telescope.builtin\frequireM\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\24lsp_implementations\22telescope.builtin\frequired\0\0\3\0\6\0\v6\0\0\0006\1\1\0009\1\2\0016\2\1\0009\2\3\0029\2\4\0029\2\5\2B\2\1\0A\1\0\0A\0\0\1K\0\1\0\27list_workspace_folders\bbuf\blsp\finspect\bvim\nprintN\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\25lsp_type_definitions\22telescope.builtin\frequireH\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\19lsp_references\22telescope.builtin\frequireW\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\"lsp_dynamic_workspace_symbols\22telescope.builtin\frequireN\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\25lsp_document_symbols\22telescope.builtin\frequireE\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\16diagnostics\22telescope.builtin\frequire�\17\1\2\a\2S\0�\0019\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19�6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\0025\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0016\2\2\0009\2\3\0029\2\r\2\18\3\1\0'\4\14\0'\5\15\0B\2\4\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\19\0006\5\2\0009\5\20\0059\5\21\0059\5\22\0055\6\23\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\24\0003\5\25\0005\6\26\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\27\0006\5\2\0009\5\20\0059\5\21\0059\5\28\0055\6\29\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4\30\0003\5\31\0005\6 \0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4!\0006\5\2\0009\5\20\0059\5\21\0059\5\"\0055\6#\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4$\0006\5\2\0009\5\20\0059\5\21\0059\5%\0055\6&\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4'\0006\5\2\0009\5\20\0059\5\21\0059\5(\0055\6)\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4*\0003\5+\0005\6,\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4-\0003\5.\0005\6/\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0040\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0062\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0043\0006\5\2\0009\5\20\0059\5\21\0059\0051\0055\0064\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0045\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0067\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\0048\0006\5\2\0009\5\20\0059\5\21\0059\0056\0055\0069\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4:\0003\5;\0005\6<\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4=\0006\5\2\0009\5\20\0059\5\21\0059\5>\0055\6?\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4@\0003\5A\0005\6B\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4C\0003\5D\0005\6E\0=\1\a\6B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4F\0006\5\2\0009\5G\0059\5H\0055\6I\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4J\0006\5\2\0009\5G\0059\5K\0055\6L\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4M\0006\5\2\0009\5G\0059\5N\0055\6O\0B\2\5\0016\2\2\0009\2\16\0029\2\17\2'\3\18\0'\4P\0003\5Q\0005\6R\0B\2\5\0012\0\0�K\0\1\0\a�\6�\1\0\1\tdesc\26telescope diagnostics\0\14<Leader>E\1\0\1\tdesc\25diagnostic goto_next\14goto_next\a]e\1\0\1\tdesc\25diagnostic goto_prev\14goto_prev\a[e\1\0\1\tdesc\26diagnostic open_float\15open_float\15diagnostic\14<Leader>e\1\0\1\tdesc!vim.lsp lsp_document_symbols\0\22<Leader><Leader>s\1\0\1\tdesc*vim.lsp lsp_dynamic_workspace_symbols\0\14<Leader>s\1\0\1\tdesc\19vim.lsp format\vformat\t<F8>\1\0\1\tdesc\27vim.lsp.buf.references\0\agr\1\0\1\tdesc\24vim.lsp code_action\t<F7>\1\0\1\tdesc\24vim.lsp code_action\16code_action\15<Leader>ca\1\0\1\tdesc\19vim.lsp rename\t<F2>\1\0\1\tdesc\19vim.lsp rename\vrename\15<Leader>rn\1\0\1\tdesc vim.lsp.buf.type_definition\0\14<Leader>D\1\0\1\tdesc#vim.lsp list_workspace_folders\0\23<Leader><Leader>wl\1\0\1\tdesc$vim.lsp remove_workspace_folder\28remove_workspace_folder\23<Leader><Leader>wr\1\0\1\tdesc!vim.lsp add_workspace_folder\25add_workspace_folder\23<Leader><Leader>wa\1\0\1\tdesc\27vim.lsp signature_help\19signature_help\agk\1\0\1\tdesc\31vim.lsp.buf.implementation\0\agi\1\0\1\tdesc\18vim.lsp hover\nhover\6K\1\0\1\tdesc\27vim.lsp.buf.definition\0\agd\1\0\1\tdesc\23vim.lsp delaration\16declaration\bbuf\blsp\agD\6n\bset\vkeymap\27v:lua.vim.lsp.omnifunc\romnifunc\24nvim_buf_set_option\rcallback\0\1\0\0\1\2\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_methodV\0\1\4\3\4\0\n-\1\0\0008\1\0\0019\1\0\0015\2\1\0-\3\1\0=\3\2\2-\3\2\0=\3\3\2B\1\2\1K\0\1\0\t�\5�\b�\14on_attach\18capabilitiies\1\0\0\nsetup�\1\0\0\6\3\r\0\18-\0\0\0009\0\0\0009\0\1\0005\1\2\0-\2\1\0=\2\3\1-\2\2\0=\2\4\0015\2\n\0005\3\b\0005\4\6\0005\5\5\0=\5\a\4=\4\t\3=\3\v\2=\2\f\1B\0\2\1K\0\1\0\t�\5�\b�\rsettings\bLua\1\0\0\16diagnostics\1\0\0\fglobals\1\0\0\1\2\0\0\bvim\14on_attach\18capabilitiies\1\0\0\nsetup\16sumneko_lua�\n\1\0\r\0L\0�\0016\0\0\0'\1\1\0B\0\2\0026\1\0\0'\2\2\0B\1\2\0023\2\3\0003\3\4\0003\4\5\0009\5\6\0005\6\n\0005\a\b\0003\b\a\0=\b\t\a=\a\v\0064\a\0\0=\a\f\0069\a\r\0009\a\14\a9\a\15\a5\b\17\0009\t\r\0009\t\16\t)\n��B\t\2\2=\t\18\b9\t\r\0009\t\16\t)\n\4\0B\t\2\2=\t\19\b9\t\r\0\18\n\3\0B\t\2\2=\t\20\b9\t\r\0\18\n\4\0B\t\2\2=\t\21\b9\t\r\0009\t\22\tB\t\1\2=\t\23\b9\t\r\0009\t\24\tB\t\1\2=\t\25\b9\t\r\0009\t\24\tB\t\1\2=\t\26\b3\t\27\0=\t\28\bB\a\2\2=\a\r\0069\a\29\0009\a\30\a4\b\b\0005\t\31\0>\t\1\b5\t \0>\t\2\b5\t!\0>\t\3\b5\t\"\0>\t\4\b5\t#\0>\t\5\b5\t$\0>\t\6\b4\t\3\0005\n%\0>\n\1\t>\t\a\bB\a\2\2=\a\30\0065\a*\0009\b&\0015\t'\0005\n(\0=\n)\tB\b\2\2=\b+\a=\a,\6B\5\2\0019\5\6\0009\5-\5'\6.\0005\a1\0009\b\29\0009\b\30\b4\t\3\0005\n/\0>\n\1\t5\n0\0>\n\2\tB\b\2\2=\b\30\aB\5\3\0019\5\6\0009\0052\5'\0063\0005\a4\0009\b\r\0009\b\14\b9\b2\bB\b\1\2=\b\r\a4\b\3\0005\t5\0>\t\1\b=\b\30\aB\5\3\0019\5\6\0009\0052\5'\0066\0005\a7\0009\b\r\0009\b\14\b9\b2\bB\b\1\2=\b\r\a9\b\29\0009\b\30\b4\t\3\0005\n8\0>\n\1\t5\n9\0>\n\2\tB\b\2\2=\b\30\aB\5\3\0016\5\0\0'\6:\0B\5\2\0029\5;\0056\6<\0009\6=\0069\6>\0069\6?\6B\6\1\0A\5\0\0023\6@\0006\a<\0009\aA\a9\aB\a'\bC\0004\t\0\0B\a\3\0023\bD\0006\t\0\0'\nE\0B\t\2\0026\n\0\0'\vF\0B\n\2\0029\nG\n5\vJ\0003\fH\0>\f\1\v3\fI\0=\fK\vB\n\2\0012\0\0�K\0\1\0\16sumneko_lua\1\0\0\0\0\19setup_handlers\20mason-lspconfig\14lspconfig\0\18LspFormatting\24nvim_create_augroup\bapi\0\29make_client_capabilities\rprotocol\blsp\bvim\24update_capabilities\17cmp_nvim_lsp\1\0\1\tname\tpath\1\0\1\tname\fcmdline\1\0\0\6:\1\0\1\tname\vbuffer\1\0\0\6/\fcmdline\1\0\0\1\0\1\tname\vbuffer\1\0\1\tname\fcmp_git\14gitcommit\rfiletype\15formatting\vformat\1\0\0\15symbol_map\1\0\1\fCopilot\b\1\0\2\tmode\vsymbol\14max_width\0032\15cmp_format\1\0\1\tname\vbuffer\1\0\1\tname\vcrates\1\0\1\tname\nspell\1\0\1\tname\fluasnip\1\0\1\tname\28nvim_lsp_signature_help\1\0\1\tname\rnvim_lsp\1\0\1\tname\fcopilot\fsources\vconfig\t<CR>\0\n<Esc>\n<C-e>\nabort\14<C-Space>\rcomplete\f<S-Tab>\n<Tab>\n<C-f>\n<C-b>\1\0\0\16scroll_docs\vinsert\vpreset\fmapping\vwindow\fsnippet\1\0\0\vexpand\1\0\0\0\nsetup\0\0\0\flspkind\bcmp\frequire\0", "config", "nvim-cmp")
time([[Config for nvim-cmp]], false)
-- Config for: which-key.nvim
time([[Config for which-key.nvim]], true)
try_loadstring("\27LJ\2\2n\0\0\4\0\b\0\v6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0005\3\3\0=\3\5\2=\2\a\1B\0\2\1K\0\1\0\fplugins\1\0\0\rspelling\1\0\0\1\0\1\fenabled\2\nsetup\14which-key\frequire\0", "config", "which-key.nvim")
time([[Config for which-key.nvim]], false)
-- Config for: mason-lspconfig.nvim
time([[Config for mason-lspconfig.nvim]], true)
try_loadstring("\27LJ\2\2u\0\0\3\0\5\0\t6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0004\2\0\0=\2\4\1B\0\2\1K\0\1\0\21ensure_installed\1\0\1\27automatic_installation\2\nsetup\20mason-lspconfig\frequire\0", "config", "mason-lspconfig.nvim")
time([[Config for mason-lspconfig.nvim]], false)
-- Config for: toggle-lsp-diagnostics.nvim
time([[Config for toggle-lsp-diagnostics.nvim]], true)
try_loadstring("\27LJ\2\2T\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\1K\0\1\0\1\0\1\rstart_on\2\tinit\27toggle_lsp_diagnostics\frequire\0", "config", "toggle-lsp-diagnostics.nvim")
time([[Config for toggle-lsp-diagnostics.nvim]], false)
-- Config for: trouble.nvim
time([[Config for trouble.nvim]], true)
try_loadstring("\27LJ\2\2�\4\0\0\5\0\20\00036\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\f\0'\3\r\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\14\0'\3\15\0004\4\0\0B\0\5\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\4\0009\0\18\0'\1\19\0B\0\2\1K\0\1\0<        cnoreabbrev copen TroubleToggle quickfix\n      \bcmd$<Cmd>TroubleToggle quickfix<CR>\15<Leader>xq#<Cmd>TroubleToggle loclist<CR>\15<Leader>xl0<Cmd>TroubleToggle document_diagnostics<CR>\15<Leader>xd1<Cmd>TroubleToggle workspace_diagnostics<CR>\15<Leader>xw\27<Cmd>TroubleToggle<CR>\15<Leader>xx\6n\bset\vkeymap\bvim\1\0\1\nicons\2\nsetup\ftrouble\frequire\0", "config", "trouble.nvim")
time([[Config for trouble.nvim]], false)
-- Config for: lualine.nvim
time([[Config for lualine.nvim]], true)
try_loadstring("\27LJ\2\2�\1\0\0\5\0\f\0\0176\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\6\0005\2\4\0004\3\3\0005\4\3\0>\4\1\3=\3\5\2=\2\a\0015\2\b\0=\2\t\0015\2\n\0=\2\v\1B\0\2\1K\0\1\0\15extensions\1\4\0\0\14nvim-tree\rquickfix\15toggleterm\foptions\1\0\1\ntheme\21gruvbox-material\rsections\1\0\0\14lualine_a\1\0\0\1\2\1\0\rfilename\tpath\3\3\nsetup\flualine\frequire\0", "config", "lualine.nvim")
time([[Config for lualine.nvim]], false)
-- Config for: fidget.nvim
time([[Config for fidget.nvim]], true)
try_loadstring("\27LJ\2\0028\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\vfidget\frequire\0", "config", "fidget.nvim")
time([[Config for fidget.nvim]], false)
-- Config for: Comment.nvim
time([[Config for Comment.nvim]], true)
try_loadstring("\27LJ\2\2k\0\0\4\0\a\0\0146\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0029\1\4\0'\2\5\0'\3\6\0B\1\3\1K\0\1\0\b#%s\ash\bset\15Comment.ft\nsetup\fComment\frequire\0", "config", "Comment.nvim")
time([[Config for Comment.nvim]], false)
-- Config for: telescope-fzf-native.nvim
time([[Config for telescope-fzf-native.nvim]], true)
try_loadstring("\27LJ\2\2H\0\0\2\0\4\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\1K\0\1\0\bfzf\19load_extension\14telescope\frequire\0", "config", "telescope-fzf-native.nvim")
time([[Config for telescope-fzf-native.nvim]], false)
-- Config for: nvim-lspconfig
time([[Config for nvim-lspconfig]], true)
try_loadstring("\27LJ\2\2�\2\0\0\n\0\18\0\"5\0\0\0006\1\1\0\18\2\0\0B\1\2\4H\4\r�'\6\2\0\18\a\4\0&\6\a\0066\a\3\0009\a\4\a9\a\5\a\18\b\6\0005\t\6\0=\5\a\t=\5\b\t=\6\t\t=\6\n\tB\a\3\1F\4\3\3R\4�\1276\1\3\0009\1\v\0019\1\f\0016\2\3\0009\2\v\0029\2\14\0026\3\3\0009\3\v\0039\3\15\0039\3\16\0035\4\17\0B\2\3\2=\2\r\1K\0\1\0\1\0\1\21update_in_insert\2\27on_publish_diagnostics\15diagnostic\twith$textDocument/publishDiagnostics\rhandlers\blsp\nnumhl\vtexthl\ttext\ticon\1\0\0\16sign_define\afn\bvim\19DiagnosticSign\npairs\1\0\4\tInfo\t \tHint\t \nError\t \tWarn\t \0", "config", "nvim-lspconfig")
time([[Config for nvim-lspconfig]], false)
-- Config for: project.nvim
time([[Config for project.nvim]], true)
try_loadstring("\27LJ\2\2M\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\rprojects\15extensions\14telescope\frequire�\3\1\0\5\0\18\0\0256\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\4\0005\2\3\0=\2\5\0015\2\6\0=\2\a\1B\0\2\0016\0\0\0'\1\b\0B\0\2\0029\0\t\0'\1\n\0B\0\2\0016\0\v\0009\0\f\0009\0\r\0'\1\14\0'\2\15\0003\3\16\0005\4\17\0B\0\5\1K\0\1\0\1\0\1\tdesc\23telescope projects\0\v<C-k>p\6n\bset\vkeymap\bvim\rprojects\19load_extension\14telescope\rpatterns\1\n\0\0\t.git\v_darcs\b.hg\t.bzr\t.svn\rMakefile\rRakefile\17package.json\16selene.toml\22detection_methods\1\0\3\17silent_chdir\1\16show_hidden\1\16scope_chdir\vglobal\1\3\0\0\fpattern\blsp\nsetup\17project_nvim\frequire\0", "config", "project.nvim")
time([[Config for project.nvim]], false)
-- Config for: nvim-ts-autotag
time([[Config for nvim-ts-autotag]], true)
try_loadstring("\27LJ\2\2A\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\20nvim-ts-autotag\frequire\0", "config", "nvim-ts-autotag")
time([[Config for nvim-ts-autotag]], false)
-- Config for: telescope.nvim
time([[Config for telescope.nvim]], true)
try_loadstring("\27LJ\2\2C\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\14help_tags\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15find_files\22telescope.builtin\frequireS\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\19live_grep_args\15extensions\14telescope\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fbuffers\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\roldfiles\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20command_history\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rcommands\22telescope.builtin\frequireF\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\17git_branches\22telescope.builtin\frequireD\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\15git_status\22telescope.builtin\frequire?\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nmarks\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rquickfix\22telescope.builtin\frequireI\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\20quickfixhistory\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\floclist\22telescope.builtin\frequireB\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\rjumplist\22telescope.builtin\frequireA\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\fkeymaps\22telescope.builtin\frequire�\v\1\0\t\0J\0�\0016\0\0\0'\1\1\0B\0\2\0026\1\0\0'\2\2\0B\1\2\0026\2\0\0'\3\3\0B\2\2\0029\2\4\0025\3\14\0005\4\f\0005\5\b\0005\6\6\0009\a\5\0=\a\a\6=\6\t\0055\6\n\0009\a\5\0=\a\a\6=\6\v\5=\5\r\4=\4\15\0035\4\17\0005\5\16\0=\5\18\0045\5\19\0005\6\23\0005\a\21\0009\b\20\1B\b\1\2=\b\22\a=\a\t\6=\6\r\5=\5\24\4=\4\25\3B\2\2\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4\29\0003\5\30\0005\6\31\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4 \0003\5!\0005\6\"\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4#\0003\5$\0005\6%\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4&\0003\5'\0005\6(\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4)\0003\5*\0005\6+\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4,\0003\5-\0005\6.\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4/\0003\0050\0005\0061\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0042\0003\0053\0005\0064\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0045\0003\0056\0005\0067\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\0048\0003\0059\0005\6:\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4;\0003\5<\0005\6=\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4>\0003\5?\0005\6@\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4A\0003\5B\0005\6C\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4D\0003\5E\0005\6F\0B\2\5\0016\2\26\0009\2\27\0029\2\28\2'\3\v\0'\4G\0003\5H\0005\6I\0B\2\5\1K\0\1\0\1\0\1\tdesc\22telescope keymaps\0\v<C-k>m\1\0\1\tdesc\23telescope jumplist\0\v<C-k>j\1\0\1\tdesc\22telescope loclist\0\v<C-k>l\1\0\1\tdesc\31telescope quickfix history\0\v<C-k>w\1\0\1\tdesc\23telescope quickfix\0\v<C-k>q\1\0\1\tdesc\20telescope marks\0\v<C-k>r\1\0\1\tdesc\25telescope git status\0\v<C-k>s\1\0\1\tdesc\27telescope git branches\0\16<C-k><C-k>b\1\0\1\tdesc\23telescope commands\0\v<C-k>c\1\0\1\tdesc\30telescope command history\0\v<C-k>h\1\0\1\tdesc\24telescope old files\0\v<C-k>o\1\0\1\tdesc\22telescope buffers\0\6q\1\0\1\tdesc\24telescope live grep\0\n<C-g>\1\0\1\tdesc\25telescope find files\0\n<C-p>\1\0\1\tdesc\24telescope help_tags\0\t<F1>\bset\vkeymap\bvim\15extensions\19live_grep_args\1\0\0\n<C-k>\1\0\0\17quote_prompt\1\0\1\17auto_quoting\2\bfzf\1\0\0\1\0\4\28override_generic_sorter\2\14case_mode\15smart_case\25override_file_sorter\2\nfuzzy\2\rdefaults\1\0\0\rmappings\1\0\0\6n\1\0\0\6i\1\0\0\n<c-t>\1\0\0\22open_with_trouble\nsetup\14telescope%telescope-live-grep-args.actions trouble.providers.telescope\frequire\0", "config", "telescope.nvim")
time([[Config for telescope.nvim]], false)
-- Config for: mason.nvim
time([[Config for mason.nvim]], true)
try_loadstring("\27LJ\2\0023\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\nmason\frequire\0", "config", "mason.nvim")
time([[Config for mason.nvim]], false)
-- Config for: nvim-colorizer.lua
time([[Config for nvim-colorizer.lua]], true)
try_loadstring("\27LJ\2\0027\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\14colorizer\frequire\0", "config", "nvim-colorizer.lua")
time([[Config for nvim-colorizer.lua]], false)
-- Config for: telescope-file-browser.nvim
time([[Config for telescope-file-browser.nvim]], true)
try_loadstring("\27LJ\2\2Q\0\0\2\0\4\0\b6\0\0\0'\1\1\0B\0\2\0029\0\2\0009\0\3\0009\0\3\0B\0\1\1K\0\1\0\17file_browser\15extensions\14telescope\frequire�\1\1\0\5\0\v\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0003\3\t\0005\4\n\0B\0\5\1K\0\1\0\1\0\1\tdesc\27telescope file browser\0\v<C-k>z\6n\bset\vkeymap\bvim\17file_browser\19load_extension\14telescope\frequire\0", "config", "telescope-file-browser.nvim")
time([[Config for telescope-file-browser.nvim]], false)
-- Config for: nvim-surround
time([[Config for nvim-surround]], true)
try_loadstring("\27LJ\2\2?\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\18nvim-surround\frequire\0", "config", "nvim-surround")
time([[Config for nvim-surround]], false)
-- Config for: lspsaga.nvim
time([[Config for lspsaga.nvim]], true)
try_loadstring("\27LJ\2\2y\0\0\4\0\6\0\t6\0\0\0'\1\1\0B\0\2\0029\1\2\0005\2\4\0005\3\3\0=\3\5\2B\1\2\1K\0\1\0\26code_action_lightbulb\1\0\0\1\0\2\tsign\2\17virtual_text\1\18init_lsp_saga\flspsaga\frequire\0", "config", "lspsaga.nvim")
time([[Config for lspsaga.nvim]], false)
-- Config for: nvim-dap-ui
time([[Config for nvim-dap-ui]], true)
try_loadstring("\27LJ\2\2\30\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\topen\31\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\nclose\31\0\0\1\1\1\0\4-\0\0\0009\0\0\0B\0\1\1K\0\1\0\1�\nclose�\1\1\0\4\0\14\0\0296\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\0016\0\0\0'\1\3\0B\0\2\0026\1\0\0'\2\1\0B\1\2\0029\2\4\0009\2\5\0029\2\6\0023\3\b\0=\3\a\0029\2\4\0009\2\t\0029\2\n\0023\3\v\0=\3\a\0029\2\4\0009\2\t\0029\2\f\0023\3\r\0=\3\a\0022\0\0�K\0\1\0\0\17event_exited\0\21event_terminated\vbefore\0\17dapui_config\22event_initialized\nafter\14listeners\bdap\nsetup\ndapui\frequire\0", "config", "nvim-dap-ui")
time([[Config for nvim-dap-ui]], false)
-- Config for: nvim-autopairs
time([[Config for nvim-autopairs]], true)
try_loadstring("\27LJ\2\2@\0\0\2\0\3\0\a6\0\0\0'\1\1\0B\0\2\0029\0\2\0004\1\0\0B\0\2\1K\0\1\0\nsetup\19nvim-autopairs\frequire\0", "config", "nvim-autopairs")
time([[Config for nvim-autopairs]], false)
-- Config for: cmp-spell
time([[Config for cmp-spell]], true)
try_loadstring("\27LJ\2\2Q\0\0\2\0\5\0\t6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0005\1\4\0=\1\3\0K\0\1\0\1\3\0\0\nen_us\bcjk\14spelllang\nspell\bopt\bvim\0", "config", "cmp-spell")
time([[Config for cmp-spell]], false)
-- Config for: telescope-ghq.nvim
time([[Config for telescope-ghq.nvim]], true)
try_loadstring("\27LJ\2\2�\1\0\0\5\0\v\0\0156\0\0\0'\1\1\0B\0\2\0029\0\2\0'\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0005\4\n\0B\0\5\1K\0\1\0\1\0\1\tdesc\18telescope ghq <Cmd>Telescope ghq list<CR>\v<C-k>g\6n\bset\vkeymap\bvim\bghq\19load_extension\14telescope\frequire\0", "config", "telescope-ghq.nvim")
time([[Config for telescope-ghq.nvim]], false)
-- Config for: crates.nvim
time([[Config for crates.nvim]], true)
try_loadstring("\27LJ\2\0024\0\0\2\0\3\0\0066\0\0\0'\1\1\0B\0\2\0029\0\2\0B\0\1\1K\0\1\0\nsetup\vcrates\frequire\0", "config", "crates.nvim")
time([[Config for crates.nvim]], false)
-- Config for: hop.nvim
time([[Config for hop.nvim]], true)
try_loadstring("\27LJ\2\2�\a\0\0\5\0\22\00056\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0B\0\2\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\b\0'\3\t\0B\0\4\0016\0\4\0009\0\5\0009\0\6\0'\1\a\0'\2\n\0'\3\v\0B\0\4\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\14\0'\3\15\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\16\0'\3\17\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\18\0'\3\19\0004\4\0\0B\0\5\0016\0\4\0009\0\f\0009\0\r\0'\1\a\0'\2\20\0'\3\21\0004\4\0\0B\0\5\1K\0\1\0�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })<CR>\6T�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })<CR>\6t�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.BEFORE_CURSOR, current_line_only = true })<CR>\6F�\1<Cmd>lua require'hop'.hint_char1({ direction = require'hop.hint'.HintDirection.AFTER_CURSOR, current_line_only = true })<CR>\6f\20nvim_set_keymap\bapi\22<Cmd>HopChar1<CR>\14<Leader>f\21<Cmd>HopWord<CR>\14<Leader>w\5\bset\vkeymap\bvim\1\0\1\tkeys\28etovxqpdygfblzhckisuran\nsetup\bhop\frequire\0", "config", "hop.nvim")
time([[Config for hop.nvim]], false)
-- Config for: gruvbox-material
time([[Config for gruvbox-material]], true)
try_loadstring("\27LJ\2\2�\a\0\0\3\0\18\0'6\0\0\0009\0\1\0+\1\2\0=\1\2\0006\0\0\0009\0\1\0'\1\4\0=\1\3\0006\0\0\0009\0\5\0'\1\a\0=\1\6\0006\0\0\0009\0\5\0)\1\1\0=\1\b\0006\0\0\0009\0\t\0009\0\n\0'\1\v\0+\2\1\0B\0\3\0016\0\0\0009\0\5\0)\1\1\0=\1\f\0006\0\0\0009\0\5\0)\1\1\0=\1\r\0006\0\0\0009\0\5\0'\1\15\0=\1\14\0006\0\0\0009\0\16\0'\1\17\0B\0\2\1K\0\1\0!colorscheme gruvbox-material\bcmd\fcolored-gruvbox_material_diagnostic_virtual_text/gruvbox_material_diagnostic_line_highlight/gruvbox_material_diagnostic_text_highlight�\4        augroup nord-theme-overrides\n          autocmd!\n          autocmd ColorScheme gruvbox-material highlight Folded ctermfg=LightGray guifg=#918d88\n          autocmd ColorScheme gruvbox-material highlight Folded ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight Folded cterm=italic gui=italic\n          autocmd ColorScheme gruvbox-material highlight SignColumn ctermbg=235 guibg=#282828\n          autocmd ColorScheme gruvbox-material highlight DiagnosticSign ctermbg=235 guibg=#282828\n        augroup END\n      \14nvim_exec\bapi(gruvbox_material_better_performance\thard gruvbox_material_background\6g\tdark\15background\18termguicolors\bopt\bvim\0", "config", "gruvbox-material")
time([[Config for gruvbox-material]], false)
-- Config for: null-ls.nvim
time([[Config for null-ls.nvim]], true)
try_loadstring("\27LJ\2\2I\0\0\3\1\6\0\t6\0\0\0009\0\1\0009\0\2\0009\0\3\0005\1\4\0-\2\0\0=\2\5\1B\0\2\1K\0\1\0\1�\nbufnr\1\0\0\vformat\bbuf\blsp\bvim�\1\1\2\6\1\r\0\0269\2\0\0'\3\1\0B\2\2\2\15\0\2\0X\3\19�6\2\2\0009\2\3\0029\2\4\0025\3\5\0-\4\0\0=\4\6\3=\1\a\3B\2\2\0016\2\2\0009\2\3\0029\2\b\2'\3\t\0005\4\n\0-\5\0\0=\5\6\4=\1\a\0043\5\v\0=\5\f\4B\2\3\0012\0\0�K\0\1\0\0�\rcallback\0\1\0\0\16BufWritePre\24nvim_create_autocmd\vbuffer\ngroup\1\0\0\24nvim_clear_autocmds\bapi\bvim\28textDocument/formatting\20supports_method�\a\1\0\b\0+\0�\0016\0\0\0009\0\1\0009\0\2\0'\1\3\0004\2\0\0B\0\3\0026\1\4\0'\2\5\0B\1\2\0029\2\6\0015\3'\0004\4\28\0009\5\a\0019\5\b\0059\5\t\5>\5\1\0049\5\a\0019\5\b\0059\5\n\5>\5\2\0049\5\a\0019\5\v\0059\5\f\5>\5\3\0049\5\a\0019\5\v\0059\5\r\5>\5\4\0049\5\a\0019\5\v\0059\5\t\5>\5\5\0049\5\a\0019\5\v\0059\5\14\5>\5\6\0049\5\a\0019\5\v\0059\5\15\5>\5\a\0049\5\a\0019\5\v\0059\5\16\5>\5\b\0049\5\a\0019\5\v\0059\5\17\5>\5\t\0049\5\a\0019\5\v\0059\5\18\0059\5\19\0055\6\21\0005\a\20\0=\a\22\6B\5\2\2>\5\n\0049\5\a\0019\5\v\0059\5\23\5>\5\v\0049\5\a\0019\5\v\0059\5\24\5>\5\f\0049\5\a\0019\5\v\0059\5\25\5>\5\r\0049\5\a\0019\5\v\0059\5\26\5>\5\14\0049\5\a\0019\5\v\0059\5\27\5>\5\15\0049\5\a\0019\5\28\0059\5\29\5>\5\16\0049\5\a\0019\5\28\0059\5\r\5>\5\17\0049\5\a\0019\5\28\0059\5\30\5>\5\18\0049\5\a\0019\5\28\0059\5\31\5>\5\19\0049\5\a\0019\5\28\0059\5\16\5>\5\20\0049\5\a\0019\5\28\0059\5 \5>\5\21\0049\5\a\0019\5\28\0059\5\18\0059\5\19\0055\6\"\0005\a!\0=\a\22\6B\5\2\2>\5\22\0049\5\a\0019\5\28\0059\5\24\5>\5\23\0049\5\a\0019\5\28\0059\5#\5>\5\24\0049\5\a\0019\5\28\0059\5$\5>\5\25\0049\5\a\0019\5\28\0059\5\23\5>\5\26\0049\5\a\0019\5%\0059\5&\5>\5\27\4=\4(\0033\4)\0=\4*\3B\2\2\0012\0\0�K\0\1\0\14on_attach\0\fsources\1\0\0\rprintenv\nhover\ntaplo\vstylua\1\0\0\1\3\0\0\14--dialect\rpostgres\frustfmt\14prettierd\16fish_indent\rbeautysh\15formatting\ryamllint\16trail_space\18todo_comments\14stylelint\ttidy\15extra_args\1\0\0\1\3\0\0\14--dialect\rpostgres\twith\rsqlfluff\vselene\frubocop\bmdl\tfish\rerb_lint\15actionlint\16diagnostics\14gitrebase\reslint_d\17code_actions\rbuiltins\nsetup\fnull-ls\frequire\18LspFormatting\24nvim_create_augroup\bapi\bvim\0", "config", "null-ls.nvim")
time([[Config for null-ls.nvim]], false)
-- Config for: auto-session
time([[Config for auto-session]], true)
try_loadstring("\27LJ\2\2�\3\0\0\4\0\15\0\0206\0\0\0'\1\1\0B\0\2\0029\0\2\0005\1\3\0005\2\4\0=\2\5\1B\0\2\0016\0\6\0009\0\a\0'\1\t\0=\1\b\0006\0\6\0009\0\n\0009\0\v\0'\1\f\0'\2\r\0'\3\14\0B\0\4\1K\0\1\0\29<Cmd>RestoreSession<<CR>\14<Leader>r\6n\bset\vkeymapEblank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal\19sessionoptions\6o\bvim\18pre_save_cmds\1\3\0\0'lua require('nvim-tree').setup({})\24tabdo NvimTreeClose\1\0\4\22auto_save_enabled\2 auto_session_create_enabled\2\25auto_restore_enabled\1\25auto_session_enabled\2\nsetup\17auto-session\frequire\0", "config", "auto-session")
time([[Config for auto-session]], false)
vim.cmd [[augroup packer_load_aucmds]]
vim.cmd [[au!]]
  -- Event lazy-loads
time([[Defining lazy-load event autocommands]], true)
vim.cmd [[au VimEnter * ++once lua require("packer.load")({'copilot.lua'}, { event = "VimEnter *" }, _G.packer_plugins)]]
time([[Defining lazy-load event autocommands]], false)
vim.cmd("augroup END")

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
