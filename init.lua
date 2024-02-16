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

require("lazy").setup("plugins", opts)
require("options")

vim.o.tabstop = 2
vim.o.expandtab = true
vim.o.softtabstop = 2
vim.o.shiftwidth = 2

if vim.env.TMUX then
  local i = vim.env.TMUX_UNIQUE:find(vim.env.TMUX_PANE, nil, true)
  local session_name = require("b64").enc(string.sub(vim.env.TMUX_UNIQUE, 0, i - 1))
  vim.o.shada = vim.o.shada .. ",n~/.local/state/nvim/shada/tmux-" .. session_name .. ".shada"
  --print(vim.o.shada)
end

vim.api.nvim_create_autocmd({ "BufRead" }, {
  pattern = { "COMMIT_EDITMSG" },
  command = "set tw=72 colorcolumn=51,+1",
})

-- clang-format conf
vim.g.clang_format_path = "/home/wanchang.ryu/bin/clang-format"
vim.keymap.set(
  { "n", "v" },
  "<F5>",
  ":py3f /home/wanchang.ryu/wtools/bin/clang-format.py<CR>",
  { noremap = true }
)
