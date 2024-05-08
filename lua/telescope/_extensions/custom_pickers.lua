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
      local cmd = (vim.fn.has("unix") == 1)
          and string.format('find %s -not -path "%s/.git/*" -type f', config_dir, config_dir)
        or string.format("where /r %s *", config_dir)
      local out = {}
      print(cmd)
      for l in vim.fn.system(cmd):gmatch("[^\r\n]+") do
        local name = l:sub(config_dir:len() + 2)
        if not name:match "^.git" then
          table.insert(out, { name, l })
        end
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
      --local curr = io.popen("cd"):read("*l")
      local curr = vim.loop.cwd()
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
        local display = line
        local filepath = line
        if string.sub(display, 1, string.len(curr)) == curr then
          display = display:sub(curr:len() + 2)
        else
          filepath = string.format("%s/%s", curr, filepath)
        end
        table.insert(out, { display, filepath })
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
