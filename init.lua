local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local opts = {
  --  defaults = { lazy = true },
  performance = {
    rtp = {
      disabled_plugins = {
        "conform",
        "mason",
      },
    },
  },
}

require("lazy").setup("plugins", opts)
--local tele_plug = require("plugins.telescope")
--require("lazy").setup(tele_plug)
require("options")
--[[
require("conform").setup({
	formatters_by_ft = {
		lua = { "stylua" },
		-- Conform will run multiple formatters sequentially
		python = { "isort", "black" },
		-- Use a sub-list to run only the first available formatter
		javascript = { { "prettierd", "prettier" } },
	},
})
--]]

vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.softtabstop = 2
vim.o.shiftwidth = 2

local neogit = require("neogit")
neogit.setup({})
