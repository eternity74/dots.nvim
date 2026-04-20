local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local get_node_text = vim.treesitter.get_node_text --[[@as function]]
local query_get = vim.treesitter.query.get --[[@as function]]

local icons = (config.display and config.display.icons) or { sync_all = "", sync_diff = "" }

local M = {}

M.header = "> Context:"

---@param bufnr integer
---@return string[]
function M.get_from_buffer(bufnr)
  local query = query_get("markdown", "cc_context")
  local ok, chat_parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok then
    return {}
  end
  local tree = chat_parser:parse()[1]
  local root = tree:root()

  local items = {}
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "context_item" then
      local context = get_node_text(node, bufnr)
      context = vim.iter(vim.tbl_values(icons)):fold(select(1, context:gsub("^> %- ", "")), function(acc, icon)
        return select(1, acc:gsub(icon, ""))
      end)
      table.insert(items, vim.trim(context))
    end
  end
  return items
end

---@param chat table
---@param bufnr integer
function M.sync(chat, bufnr)
  local context_in_chat = M.get_from_buffer(bufnr)
  if vim.tbl_isempty(context_in_chat) and vim.tbl_isempty(chat.context_items) then
    return
  end

  local function expand_group_ref(group_name)
    local group_config = chat.tools.tools_config.groups[group_name] or {}
    return vim.tbl_map(function(tool)
      return "<tool>" .. tool .. "</tool>"
    end, group_config.tools or {})
  end

  local context_set = {}
  for _, id in ipairs(context_in_chat) do
    context_set[id] = true
    local group_name = id:match("<group>(.*)</group>")
    if group_name and vim.trim(group_name) ~= "" then
      for _, tool_id in ipairs(expand_group_ref(group_name)) do
        context_set[tool_id] = true
      end
    end
  end

  local remove_set = {}
  for _, ctx in ipairs(chat.context_items) do
    if not context_set[ctx.id] then
      remove_set[ctx.id] = true
    end
  end

  if vim.tbl_isempty(remove_set) then
    return
  end

  for id in pairs(remove_set) do
    local group_name = id:match("<group>(.*)</group>")
    if group_name then
      for _, tool_id in ipairs(expand_group_ref(group_name)) do
        remove_set[tool_id] = true
      end
    end
  end

  chat.messages = vim
    .iter(chat.messages)
    :filter(function(msg)
      return not (msg.context and msg.context.id and remove_set[msg.context.id])
    end)
    :totable()

  chat.context_items = vim
    .iter(chat.context_items)
    :filter(function(ctx)
      return not remove_set[ctx.id]
    end)
    :totable()

  local schemas_to_keep = {}
  local tools_in_use_to_keep = {}
  for id, tool_schema in pairs(chat.tool_registry.schemas) do
    if not remove_set[id] then
      schemas_to_keep[id] = tool_schema
      local tool_name = id:match("<tool>(.*)</tool>")
      if tool_name and chat.tool_registry.in_use[tool_name] then
        tools_in_use_to_keep[tool_name] = true
      end
    else
      log:debug("Removing tool schema and usage flag for ID: %s", id)
    end
  end
  chat.tool_registry.schemas = schemas_to_keep
  chat.tool_registry.in_use = tools_in_use_to_keep
end

---@param chat table
---@return string[]
function M.render(chat)
  if not chat or vim.tbl_isempty(chat.context_items or {}) then
    return {}
  end

  local lines = { M.header }
  for _, context in pairs(chat.context_items) do
    if context and not (context.opts and context.opts.visible == false) then
      if context.opts and context.opts.sync_all then
        table.insert(lines, string.format("> - %s%s", icons.sync_all, context.id))
      elseif context.opts and context.opts.sync_diff then
        table.insert(lines, string.format("> - %s%s", icons.sync_diff, context.id))
      else
        table.insert(lines, string.format("> - %s", context.id))
      end
    end
  end

  if #lines == 1 then
    return {}
  end

  table.insert(lines, "")
  return lines
end

return M
