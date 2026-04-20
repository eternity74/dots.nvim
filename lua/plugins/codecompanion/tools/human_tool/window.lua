local M = {}

local input_win
local suppress_next_chat_leave_close = false

---@param window_id integer
---@return boolean
function M.is_valid(window_id)
  return window_id ~= nil and vim.api.nvim_win_is_valid(window_id)
end

---@param bufnr integer
---@return boolean
function M.is_valid_buffer(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

---@return integer|nil
function M.get()
  return input_win
end

---@param winid integer|nil
function M.set(winid)
  input_win = winid
end

---@param value boolean
function M.set_suppress(value)
  suppress_next_chat_leave_close = value
end

---@param opts? { force?: boolean }
function M.close(opts)
  opts = opts or {}
  if suppress_next_chat_leave_close and not opts.force then
    suppress_next_chat_leave_close = false
    return
  end
  if M.is_valid(input_win) then
    vim.api.nvim_win_close(input_win, true)
  end
  input_win = nil
end

---@param chat table
---@return integer|nil
function M.find_chat_win(chat)
  if not chat or not M.is_valid_buffer(chat.bufnr) then
    return nil
  end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(winid) == chat.bufnr then
      return winid
    end
  end
  return nil
end

---@param chat table
---@param height integer
---@return integer|nil
function M.open_under_chat(chat, height)
  local chat_win = M.find_chat_win(chat)
  if not chat_win then
    return nil
  end
  vim.api.nvim_win_call(chat_win, function()
    vim.cmd("belowright " .. height .. "split")
    input_win = vim.api.nvim_get_current_win()
  end)
  return input_win
end

---@param chat table
---@param win_height integer
---@return boolean
function M.ensure(chat, win_height)
  if M.is_valid(input_win) then
    vim.api.nvim_set_current_win(input_win)
    return true
  end
  local winid = M.open_under_chat(chat, win_height)
  if winid then
    vim.api.nvim_set_current_win(winid)
  end
  return winid ~= nil
end

return M
