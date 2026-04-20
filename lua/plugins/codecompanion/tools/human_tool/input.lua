local context_mod = require("plugins.codecompanion.tools.human_tool.context")
local render_mod = require("plugins.codecompanion.tools.human_tool.render")
local window_mod = require("plugins.codecompanion.tools.human_tool.window")

local M = {}

local input_buf
local pending_output_cb

---@return integer|nil
function M.get_buf()
  return input_buf
end

---@return function|nil
function M.get_pending_cb()
  return pending_output_cb
end

---@param cb function|nil
function M.set_pending_cb(cb)
  pending_output_cb = cb
end

local function create_or_reuse_buffer()
  if window_mod.is_valid_buffer(input_buf) then
    return
  end

  input_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = input_buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = input_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = input_buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = input_buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = input_buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = input_buf })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = input_buf,
    once = true,
    callback = function()
      if pending_output_cb then
        pending_output_cb({ status = "success", data = "(User closed the input window)" })
        pending_output_cb = nil
      end
      input_buf = nil
    end,
  })
end

---@param chat table
---@param _prompt string
---@param output_cb function
function M.open(chat, _prompt, output_cb)
  pending_output_cb = output_cb

  create_or_reuse_buffer()
  if not window_mod.is_valid_buffer(input_buf) then
    return
  end

  local header_lines = render_mod.build_header_lines()
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, header_lines)
  local context_lines = context_mod.render(chat)
  table.insert(context_lines, "")
  vim.api.nvim_buf_set_lines(input_buf, #header_lines, -1, false, context_lines)

  local win_height = math.max(10, math.floor(vim.o.lines * 0.15))
  if not window_mod.ensure(chat, win_height) then
    return
  end

  vim.api.nvim_win_set_buf(window_mod.get(), input_buf)
  vim.api.nvim_win_set_cursor(window_mod.get(), { #header_lines + #context_lines, 0 })
  vim.cmd("startinsert")

  local submitted = false

  local function reset_buffer()
    if not window_mod.is_valid_buffer(input_buf) then
      return
    end
    local line_count = vim.api.nvim_buf_line_count(input_buf)
    if line_count > #header_lines then
      vim.api.nvim_buf_set_lines(input_buf, #header_lines, -1, false, {})
    end
    if window_mod.is_valid(window_mod.get()) then
      vim.api.nvim_win_set_cursor(window_mod.get(), { #header_lines, 0 })
      vim.api.nvim_set_current_win(window_mod.get())
      vim.cmd("startinsert")
    end
  end

  local function submit()
    if submitted then
      return
    end
    submitted = true

    context_mod.sync(chat, input_buf)

    local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_lines = {}

    for i = #header_lines + 1, #all_lines do
      table.insert(user_lines, all_lines[i])
    end

    local user_input = vim.trim(table.concat(user_lines, "\n"))
    if user_input == "" then
      user_input = "(User submitted an empty response)"
    end

    local chat_win = window_mod.find_chat_win(chat)
    if chat_win and vim.api.nvim_get_current_win() == chat_win then
      window_mod.set_suppress(true)
    end
    reset_buffer()

    local cb = output_cb
    pending_output_cb = nil
    if cb then
      vim.schedule(function()
        cb({ status = "success", data = user_input })
      end)
    end

    vim.defer_fn(function()
      if window_mod.is_valid_buffer(input_buf) and not window_mod.is_valid(window_mod.get()) then
        local h = math.max(10, math.floor(vim.o.lines * 0.15))
        local winid = window_mod.open_under_chat(chat, h)
        if winid then
          vim.api.nvim_win_set_buf(winid, input_buf)
          vim.api.nvim_win_set_cursor(winid, { #header_lines, 0 })
          vim.api.nvim_set_current_win(winid)
          vim.cmd("startinsert")
        end
      end
    end, 10)

    submitted = false
  end

  local keymap_opts = { noremap = true, silent = true, buffer = input_buf }
  vim.keymap.set("n", "<C-s>", submit, keymap_opts)
  vim.keymap.set("i", "<C-s>", submit, keymap_opts)
  vim.keymap.set("v", "<C-s>", submit, keymap_opts)
end

return M
