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

-- Encodes a string to base64
local function encode_base64(input)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((input:gsub('.', function(x)
      local r,bits='',x:byte()
      for i=8,1,-1 do r=r..(bits%2^i-bits%2^(i-1)>0 and '1' or '0') end
      return r
    end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
      if #x < 6 then return '' end
      local c=0
      for i=1,6 do c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0) end
      return b:sub(c+1,c+1)
    end)..({ '', '==', '=' })[#input%3+1])
end



require("options")
require("lazy").setup("plugins", opts)

if vim.env.TMUX then
  local i = vim.env.TMUX_UNIQUE:find(vim.env.TMUX_PANE, nil, true)
  --local session_name = require("b64").enc(string.sub(vim.env.TMUX_UNIQUE, 0, i - 1))
  local session_name = encode_base64(string.sub(vim.env.TMUX_UNIQUE, 0, i - 1))
  vim.o.shada = vim.o.shada .. ",n~/.local/state/nvim/shada/tmux-" .. session_name .. ".shada"
  --print(vim.o.shada)
end

vim.cmd([[
highlight ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/
set list listchars=tab:›∙,trail:∙,extends:$,nbsp:= 
]])

vim.lsp.set_log_level("debug")
