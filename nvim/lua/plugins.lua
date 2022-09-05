local fn = vim.fn

-- Automatically install packer
local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
if fn.empty(fn.glob(install_path)) > 0 then
  PACKER_BOOTSTRAP = fn.system({"git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim",
                                install_path})
  print("Installing packer close and reopen Neovim...")
  vim.cmd([[packadd packer.nvim]])
end

-- Autocommand that reloads neovim whenever you save the plugins.lua file
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
  return
end

if vim.g.vscode then
else
  -- Have packer use a popup window
  packer.init({
    display = {
      open_fn = function()
        return require("packer.util").float({})
      end
    }
  })
end

-- Install your plugins here
return packer.startup(function(use)
  -- My plugins here
  use({"wbthomason/packer.nvim"})
  use({
    "kylechui/nvim-surround",
    tag = "*", -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require("nvim-surround").setup({})
    end
  })
  use {
    'phaazon/hop.nvim',
    branch = 'v2', -- optional but strongly recommended
    config = function()
      -- you can configure Hop the way you like here; see :h hop-config
      require('hop').setup({
        keys = 'etovxqpdygfblzhckisuran'
      })
    end
  }
  use {
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup({})
    end
  }
end)