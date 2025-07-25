return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim", -- required
      "sindrets/diffview.nvim", -- optional - Diff integration

      -- Only one of these is needed, not both.
      "ibhagwan/fzf-lua",
    },
    config = true,
  },
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim", -- optional [for picker="telescope"]
      "ibhagwan/fzf-lua", -- optional [for picker="fzf-lua"]
      "nvim-tree/nvim-web-devicons", -- optional [for devicons in telescope or fzf]
    },
    opts = {
      disable_maps = false,
      skip_input_prompt = true,
      prefix = "<C-Bslash>",
      -- USE EMPTY FOR DEFAULT OPTIONS
      -- DEFAULTS ARE LISTED BELOW
    },
    --[[
    config = function(opts)
      require("cscope_maps").setup(opts)
    end,
    --]]
  },
  {
    "tpope/vim-fugitive",
  },
  { "tpope/vim-unimpaired", lazy = false },
  {
    "alexghergh/nvim-tmux-navigation",
    config = function()
      local nvim_tmux_nav = require("nvim-tmux-navigation")

      nvim_tmux_nav.setup({
        disable_when_zoomed = true, -- defaults to false
      })

      vim.keymap.set("n", "<C-h>", nvim_tmux_nav.NvimTmuxNavigateLeft)
      vim.keymap.set("n", "<C-j>", nvim_tmux_nav.NvimTmuxNavigateDown)
      vim.keymap.set("n", "<C-k>", nvim_tmux_nav.NvimTmuxNavigateUp)
      vim.keymap.set("n", "<C-l>", nvim_tmux_nav.NvimTmuxNavigateRight)
      --vim.keymap.set("n", "<C-\\>", nvim_tmux_nav.NvimTmuxNavigateLastActive)
      --vim.keymap.set("n", "<C-Space>", nvim_tmux_nav.NvimTmuxNavigateNext)
    end,
  },
  --{ "taybart/b64.nvim" },
  {
    "SirVer/ultisnips",
    enabled = false,
    lazy = VeryLazy,
    init = function()
      vim.g.UltiSnipsExpandTrigger = "<c-f>"
    end,
    config = function()
      vim.g.UltiSnipsEditSplit = "vertical"
      vim.g.UltiSnipsSnippetsDir = "~/.snippets/"
      vim.g.UltiSnipsSnippetDirectories = { "/home/wanchang.ryu/.snippets/" }
      vim.g.UltiSnipsExpandTrigger = "<c-f>"
    end,
  },
  {
    "kelly-lin/telescope-ag",
    dependencies = { "nvim-telescope/telescope.nvim" },
  },
  {
    "Mr-LLLLL/interestingwords.nvim",
    opts = { scroll_center = false },
    config = true,
    enabled = false,
  },
  {
    "vim-scripts/Mark--Karkat",
  },
  {
    "modille/groovy.vim"
  },
  -- input popup
  -- { "stevearc/dressing.nvim" },
  -- shortcut key suggestion
  { "folke/which-key.nvim" },
}
