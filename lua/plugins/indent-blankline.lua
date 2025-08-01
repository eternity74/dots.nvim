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

return M
