local context_mod = require("plugins.codecompanion.tools.human_tool.context")
local render_mod = require("plugins.codecompanion.tools.human_tool.render")
local window_mod = require("plugins.codecompanion.tools.human_tool.window")
local log = require("codecompanion.utils.log")

local M = {}

-- Define highlight group for human tool input background
local function setup_highlight()
  -- Use a subtle background tint based on Normal bg
  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  local bg = normal.bg or 0x1e1e2e
  -- Lighten/darken slightly for contrast
  local r = math.min(255, math.floor(bg / 65536) + 12)
  local g = math.min(255, math.floor((bg % 65536) / 256) + 8)
  local b = math.min(255, (bg % 256) + 18)
  local new_bg = string.format("#%02x%02x%02x", r, g, b)
  vim.api.nvim_set_hl(0, "HumanToolInputBg", { bg = new_bg })
end

setup_highlight()

-- Re-apply on colorscheme change
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = setup_highlight,
})

local HEADER_TITLE = "## 💬 Human Tool Input"
local PREMIUM_PREFIX = "### Premium Interactions:"
local active_chat -- the chat object when human_tool is active
local header_start_line -- 0-indexed line where our section starts in the chat buffer
local header_line_count -- number of header + context lines inserted

---@return function|nil
function M.get_pending_cb()
  return pending_output_cb
end

---@param cb function|nil
function M.set_pending_cb(cb)
  pending_output_cb = cb
end

---@return table|nil
function M.get_active_chat()
  return active_chat
end

---@return integer|nil
function M.get_buf()
  if active_chat and active_chat.bufnr and vim.api.nvim_buf_is_valid(active_chat.bufnr) then
    return active_chat.bufnr
  end
  return nil
end

---@return integer|nil header_start 0-indexed
function M.get_header_start()
  return header_start_line
end

---@return integer
function M.get_header_line_count()
  return header_line_count or 0
end

---Submit the user's input from the chat buffer
---@return nil
function M.submit()
  if not pending_output_cb then
    return
  end
  if not active_chat or not active_chat.bufnr or not vim.api.nvim_buf_is_valid(active_chat.bufnr) then
    return
  end

  local chat = active_chat
  local bufnr = chat.bufnr

  -- Parse lines: separate header/context/premium from user input
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, header_start_line, -1, false)
  local header_trim = vim.trim(context_mod.header)
  local user_lines = {}
  local context_end = 0 -- track last header-related line for context sync

  for i, line in ipairs(all_lines) do
    local trimmed = vim.trim(line)
    if trimmed == HEADER_TITLE
      or trimmed == ""
      or trimmed == header_trim
      or line:sub(1, 2) == "> "
      or trimmed:sub(1, #PREMIUM_PREFIX) == PREMIUM_PREFIX
    then
      context_end = i
    else
      table.insert(user_lines, line)
    end
  end

  -- Sync context from header section
  context_mod.sync(chat, bufnr, { start = header_start_line, finish = header_start_line + context_end })

  local user_input = vim.trim(table.concat(user_lines, "\n"))
  if user_input == "" then
    user_input = "(User submitted an empty response)"
  end

  -- Clean up extmarks
  local ns = vim.api.nvim_create_namespace("HumanToolInput")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Clean up: remove our header/context/input lines from chat buffer
  local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  end
  vim.api.nvim_buf_set_lines(bufnr, header_start_line, -1, false, {})
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  end

  local cb = pending_output_cb
  pending_output_cb = nil
  active_chat = nil
  header_start_line = nil
  header_line_count = nil

  vim.schedule(function()
    cb({ status = "success", data = user_input })
  end)
end

---Open the input section in the chat buffer (no separate window)
---@param chat table
---@param _prompt string
---@param output_cb function
function M.open(chat, _prompt, output_cb)
  pending_output_cb = output_cb
  active_chat = chat

  local bufnr = chat.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Build header and context lines (these are the "header" we skip on submit)
  local header_lines = { "", "## 💬 Human Tool Input", "" }
  local context_lines = context_mod.render(chat)
  local premium_lines = render_mod.build_header_lines()

  local all_insert_lines = {}
  vim.list_extend(all_insert_lines, header_lines)
  vim.list_extend(all_insert_lines, context_lines)
  vim.list_extend(all_insert_lines, premium_lines)

  -- Record header info BEFORE adding the empty user-input line
  -- Append to the end of chat buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  header_start_line = line_count -- 0-indexed for set_lines
  header_line_count = #all_insert_lines

  -- Add an empty line as the start of the user input area (NOT part of header)
  table.insert(all_insert_lines, "")

  local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  end
  vim.api.nvim_buf_set_lines(bufnr, line_count, -1, false, all_insert_lines)

  -- Apply background highlight to the human tool input section
  local ns = vim.api.nvim_create_namespace("HumanToolInput")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local total_inserted = #all_insert_lines
  for i = 0, total_inserted - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, ns, header_start_line + i, 0, {
      line_hl_group = "HumanToolInputBg",
      priority = 50,
    })
  end

  -- Focus the chat window and position cursor at the end
  local chat_win = window_mod.find_chat_win(chat)
  if chat_win then
    vim.api.nvim_set_current_win(chat_win)
    local new_line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(chat_win, { new_line_count, 0 })
    vim.cmd("startinsert")
  end
end

return M
