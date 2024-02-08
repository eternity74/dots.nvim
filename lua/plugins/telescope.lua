local M = {
  "nvim-telescope/telescope.nvim",
  tag = "0.1.5",
  branch = "0.1.x",
  dependencies = {
    { "nvim-lua/plenary.nvim" },
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
    },
  },
  cmd = { "Telescope", "Tel" },
  keys = { "<leader>f" },
}

function M.config()
  local telescope = require("telescope")
  local builtin = require("telescope.builtin")

  local pickers = {
    builtin.oldfiles,
    builtin.find_files,
    index = 1,
  }

  local old_picker

  pickers.cycle = function(prompt_bufnr)
    local current_picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
    print(current_picker.finder)
    print("builtin.oldfiles = " .. tostring(builtin.oldfiles))
    print("Is oldfiles =" .. tostring(current_picker == builtin.oldfiles))
    if pickers.index >= #pickers then
      pickers.index = 1
    else
      pickers.index = pickers.index + 1
    end
    if current_picker.prompt_title == "Oldfiles" then
      old_picker:find({ default_text = require("telescope.actions.state").get_current_line() })
    else
      old_picker = current_picker
      builtin.oldfiles({ default_text = require("telescope.actions.state").get_current_line() })
    end
    --pickers[pickers.index]({ default_text = require("telescope.actions.state").get_current_line() })
  end

  telescope.setup({
    defaults = {
      mappings = {
        i = {
          ["<C-f>"] = pickers.cycle,
          ["<C-j>"] = "move_selection_next",
          ["<C-k>"] = "move_selection_previous",
        },
        n = {
          ["<C-f>"] = pickers.cycle,
        },
      },
    },
    extensions = {
      fzf = {
        fuzzy = true,
        override_generic_sorter = true,
        override_file_sorter = true,
        case_mode = "smart_case",
      },
    },
  })

  telescope.load_extension("fzf")
  telescope.load_extension("find_configs")
end

M.keys = {
  { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "find files" },
  { "<leader>fc", "<cmd>Telescope find_configs<cr>", desc = "configs" },
  {
    "<C-p>",
    ":lua require'telescope'.extensions.find_configs.find_prj{}<CR>",
    desc = "find in prj",
  },
}

return M
