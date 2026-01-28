local M = {
  "lukas-reineke/indent-blankline.nvim",
  opts = {
    indent = {
      char = "│",
      tab_char = "│",
    },
    scope = { enabled = false },
    exclude = {
      filetypes = {
        "help",
        "alpha",
        "dashboard",
        "neo-tree",
        "Trouble",
        "trouble",
        "lazy",
        "mason",
        "notify",
        "toggleterm",
        "lazyterm",
      },
    },
  },
  main = "ibl",
  keys = {
    { "<Space>tt", "<cmd>IBLToggle<cr><cmd>lua vim.b.miniindentscope_disable=not vim.b.miniindentscope_disable<cr>", desc = "Toggle indent-blankline" },
  },
  lazy = false,
}

function M.toggle_decoration()
  pcall(vim.cmd, "IBLToggle")
  vim.b.miniindentscope_disable = not vim.b.miniindentscope_disable

  if vim.b.miniindentscope_disable then
    pcall(vim.cmd, "highlight clear ExtraWhitespace")
    pcall(function()
      vim.o.list = false
    end)
    pcall(vim.cmd, "match none")
  else
    pcall(vim.cmd, "highlight ExtraWhitespace ctermbg=red guibg=red")
    pcall(vim.cmd, 'match ExtraWhitespace /\\s\\+$/')
    pcall(function()
      vim.o.list = true
      vim.o.listchars = "tab:›∙,trail:∙,extends:$,nbsp:="
    end)
  end

end

M.keys = {
  {
    "<Space>tt",
    function() M.toggle_decoration() end,
    desc = "Toggle indent-blankline",
  },
}

return M
