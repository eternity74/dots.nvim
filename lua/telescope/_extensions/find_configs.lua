local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions_state = require("telescope.actions.state")
local builtin = require("telescope.builtin")

return require("telescope").register_extension({
  exports = {
    find_configs = function(opts)
      opts = opts or {}
      local config_dir = vim.fn.stdpath("config")
      local cmd = "where /r " .. config_dir .. " *"
      local out = {}
      for l in vim.fn.system(cmd):gmatch("[^\r\n]+") do
        table.insert(out, { l:sub(config_dir:len() + 2), l })
      end

      pickers
        .new(opts, {
          prompt_title = "ConfigFiles",
          finder = finders.new_table({
            results = out,
            entry_maker = function(entry)
              return {
                value = entry[2],
                filename = entry[2],
                display = entry[1],
                ordinal = entry[1],
              }
            end,
          }),
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(prompt_bufnr, map)
            map("i", "<C-j>", "move_selection_next")
            map("i", "<C-k>", "move_selection_previous")
            return true
          end,
        })
        :find()
    end,
    find_prj = function(opts)
      local curr = io.popen("cd"):read("*l")
      print(curr)
      opts = opts or {}
      local fn = "cscope.files"
      local file = io.open(fn, "rb")
      if not file then
        builtin.find_files()
        return nul
      end

      local out = {}
      for line in io.lines(fn) do
        table.insert(out, { line:sub(curr:len() + 2), line })
      end

      pickers
        .new(opts, {
          prompt_title = "PrjFiles",
          finder = finders.new_table({
            results = out,
            entry_maker = function(entry)
              return {
                value = entry[2],
                filename = entry[2],
                display = entry[1],
                ordinal = entry[1],
              }
            end,
          }),
          sorter = conf.generic_sorter(opts),
          attach_mappings = function(prompt_bufnr, map)
            map("i", "<C-j>", "move_selection_next")
            map("i", "<C-k>", "move_selection_previous")
            return true
          end,
        })
        :find()
    end,
  },
})
