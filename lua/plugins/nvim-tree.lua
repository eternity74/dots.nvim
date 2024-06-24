local min_width = 32

local function my_on_attach(bufnr)
  local api = require "nvim-tree.api"

  local function opts(desc)
    return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  -- default mappings
  api.config.mappings.default_on_attach(bufnr)

-- custom mappings
  vim.keymap.set('n', 'w', function()
    local view = require'nvim-tree.view'
    print (view.View.adaptive_size)
    view.View.adaptive_size = not view.View.adaptive_size
    if view.View.adaptive_size then
      view.grow_from_content()
    else
      view.resize(min_width)
    end
  end, opts('Expand width'))
end
local nvim_tree = {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("nvim-tree").setup {
      on_attach = my_on_attach,
      sort_by = "case_sensitive",
      hijack_cursor = true,
      system_open = {
        cmd = "open",
      },
      view = {
        width = { min = min_width },
      },
      renderer = {
        group_empty = true,
        icons = {
          show = {
            git = true,
            file = false,
            folder = false,
            folder_arrow = true,
          },
          glyphs = {
            bookmark = "🔖",
            folder = {
              arrow_closed = "⏵",
              arrow_open = "⏷",
            },
            git = {
              unstaged = "✗",
              staged = "✓",
              unmerged = "⌥",
              renamed = "➜",
              untracked = "★",
              deleted = "⊖",
              ignored = "◌",
            },
          },
        },
      },
    }
    require("nvim-tree.view").View.adaptive_size = false
  end,
  keys = {
    { "<C-n>", ":NvimTreeToggle<CR>", desc = "NvimTreeToogle" },
    { "<C-m>", ":NvimTreeFindFileToggle<CR>", desc = "NvimTreeFindFileToggle" },
  },
}
return nvim_tree
