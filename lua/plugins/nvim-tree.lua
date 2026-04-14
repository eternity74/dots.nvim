local MIN_WIDTH = 32

local function my_on_attach(bufnr)
  local api = require("nvim-tree.api")
  local view = require("nvim-tree.view")

  local function opts(desc)
    return {
      desc = "nvim-tree: " .. desc,
      buffer = bufnr,
      noremap = true,
      silent = true,
      nowait = true,
    }
  end

  local function get_alt_bufnr()
    return vim.fn.bufnr("#", true)
  end

  local function find_alt_file()
    local alt_bufnr = get_alt_bufnr()
    local filename = vim.api.nvim_buf_get_name(alt_bufnr)
    if filename ~= "" then
      api.tree.find_file({ buf = alt_bufnr, open = true, focus = true })
    end
  end

  local function toggle_width()
    view.adaptive_size = not view.adaptive_size
    if view.adaptive_size then
      view.grow_from_content()
    else
      view.resize(MIN_WIDTH)
    end
  end

  local function change_nvim_tree_root()
    local alt_bufnr = get_alt_bufnr()
    api.tree.find_file({
      buf = alt_bufnr,
      open = true,
      focus = true,
      update_root = true,
    })
  end

  api.config.mappings.default_on_attach(bufnr)

  vim.keymap.set("n", "w", toggle_width, opts("Expand width"))
  vim.keymap.set("n", "<Space>", find_alt_file, opts("Find file"))

  -- window does not capture <C-Space>, so map both
  for _, lhs in ipairs({ "<C-Space>", "<leader><Space>" }) do
    vim.keymap.set("n", lhs, change_nvim_tree_root, opts("Change nvim-tree root"))
  end
end

local nvim_tree = {
  "nvim-tree/nvim-tree.lua",
  version = "*",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    vim.opt.termguicolors = true

    require("nvim-tree").setup({
      on_attach = my_on_attach,
      sort_by = "case_sensitive",
      hijack_cursor = true,
      system_open = {
        cmd = "xdg-open",
      },
      view = {
        width = { min = MIN_WIDTH },
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
      git = {
        enable = false,
      },
      actions = {
        open_file = {
          window_picker = { enable = false },
        },
      },
      filters = {
        enable = false,
      },
    })

    require("nvim-tree.view").adaptive_size = false
  end,
  keys = {
    { "<C-n>", ":NvimTreeToggle<CR>", desc = "NvimTreeToggle" },
  },
}

return nvim_tree
