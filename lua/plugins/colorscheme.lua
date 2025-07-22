local tokyonight = {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    require("tokyonight").setup({
      on_colors = function(colors)
        -- colors.fg_dark = "#a9b1d6"
        colors.fg = "#ebebeb"
        colors.fg_dark = "#f2f3f5"
      end
    })
    --vim.cmd([[:highlight DiffText gui=bold guibg=#0e1430]])
    vim.cmd[[:highlight DiffText gui=bold]]
    vim.cmd[[colorscheme tokyonight-moon]]
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

local catppuccin = {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    require("catppuccin").setup{}
    vim.cmd.colorscheme("catppuccin")
  end,
}

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

local onedark = {
  "https://github.com/navarasu/onedark.nvim",
  config = function()
    require('onedark').setup {
      style = 'dark',
    }
    vim.cmd.colorscheme("onedark")
  end
}

local jonedark = {
  "https://github.com/joshdick/onedark.vim",
  config = function()
    vim.cmd.colorscheme("onedark")
  end
}

local vscode = {
  "Mofiqul/vscode.nvim",
  config = function()
    require("vscode").setup{}
    vim.cmd.colorscheme("vscode")
  end,
}

-- return vscode
return tokyonight
--return onedark
-- return jonedark
-- return dracula
-- return catppuccin
-- return gruvbox
