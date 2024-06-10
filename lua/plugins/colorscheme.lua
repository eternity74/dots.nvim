local tokyonight = {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("tokyonight").setup({})
    vim.cmd("colorscheme tokyonight-night")
  end,
}

local gruvbox = {
  "ellisonleao/gruvbox.nvim",
  priority = 1000,
  config = function()
    require("gruvbox").setup({
      terminal_colors = true, -- add neovim terminal colors
      undercurl = true,
      underline = true,
      bold = true,
      italic = {
        strings = true,
        emphasis = true,
        comments = true,
        operators = false,
        folds = true,
      },
      strikethrough = true,
      invert_selection = false,
      invert_signs = false,
      invert_tabline = false,
      invert_intend_guides = false,
      inverse = true, -- invert background for search, diffs, statuslines and errors
      contrast = "", -- can be "hard", "soft" or empty string
      palette_overrides = {},
      overrides = {},
      dim_inactive = false,
      transparent_mode = false,
    })
    vim.cmd("colorscheme gruvbox")
  end,
  opts = ...,
}

local catppuccin = { "catppuccin/nvim", name = "catppuccin", priority = 1000 }

local dracula = {
  "binhtran432k/dracula.nvim",
  lazy = false,
  config = function()
    require("dracula").setup({
      overrides = {
        TreesitterContext = { bg = "#44475A"},
        -- TreesitterContext = { bg = "#7C7F8A"},
        },
      })
    vim.cmd.colorscheme("dracula-soft")
  end,
}

--return dracula
return tokyonight
