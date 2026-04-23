local Curl = require("plenary.curl")
local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local token = require("codecompanion.adapters.http.copilot.token")

local editor_context = require("codecompanion.interactions.shared.editor_context").new("chat")

local M = {}

local function get_copilot_stats()
  local oauth_token = token.fetch({ force = true }).oauth_token
  local ok, response = pcall(function()
    return Curl.get("https://api.github.com/copilot_internal/user", {
      sync = true,
      headers = {
        Authorization = "Bearer " .. oauth_token,
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
    })
  end)

  if not ok then
    log:error("Copilot Adapter: Could not get stats: %s", response)
    return nil
  end

  local ok_json, json = pcall(vim.json.decode, response.body)
  if not ok_json then
    log:error("Copilot Adapter: Error parsing stats response: %s", response.body)
    return nil
  end

  return json
end

---@return string[]
function M.build_header_lines()
  local header_lines = {}
  local stats = get_copilot_stats()
  local premium = stats and stats.quota_snapshots and stats.quota_snapshots.premium_interactions or nil

  if premium and premium.entitlement and premium.remaining then
    table.insert(
      header_lines,
      string.format("### Premium Interactions: Used %d / %d", premium.entitlement - premium.remaining, premium.entitlement)
    )
  else
    table.insert(header_lines, "### Premium Interactions: unavailable")
  end

  table.insert(header_lines, "")
  return header_lines
end

local function render_viewport()
  local ec_opts = config.interactions.shared.editor_context.opts
  local excluded = ec_opts and ec_opts.excluded
  local buf_lines = buf_utils.get_visible_lines(excluded)

  local count = 0
  local output = {}
  for bufnr, ranges in pairs(buf_lines) do
    for _, range in ipairs(ranges) do
      local content = chat_helpers.format_viewport_range_for_llm(bufnr, range)
      table.insert(output, content)
      count = count + 1
    end
  end

  if count == 0 then
    log:warn("No visible buffers to share")
  end
  return output
end

---@param chat table
---@param user_input string
---@return string
function M.render_user_input(chat, user_input)
  local message = {
    role = config.constants.USER_ROLE,
    content = user_input,
  }

  chat:replace_user_inputs(message)
  return message.content
end

return M
