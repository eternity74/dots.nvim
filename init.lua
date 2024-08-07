vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
-- print(lazypath)
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

require("options")
require("lazy").setup("plugins", opts)

if vim.env.TMUX then
  local i = vim.env.TMUX_UNIQUE:find(vim.env.TMUX_PANE, nil, true)
  local session_name = require("b64").enc(string.sub(vim.env.TMUX_UNIQUE, 0, i - 1))
  vim.o.shada = vim.o.shada .. ",n~/.local/state/nvim/shada/tmux-" .. session_name .. ".shada"
  --print(vim.o.shada)
end

vim.cmd([[
highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/
set list listchars=tab:›∙,trail:∙,extends:$,nbsp:= 
]])
