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

local function get_context_window_from_adapter(adapter)
  if not adapter or not adapter.schema or not adapter.schema.model then
    return nil
  end

  local model_name = adapter.schema.model.default
  if type(model_name) == "function" then
    model_name = model_name(adapter)
  end

  local choices = adapter.schema.model.choices
  if type(choices) == "function" then
    choices = choices(adapter, { async = true })
  end

  if model_name and type(choices) == "table" and choices[model_name] then
    local choice = choices[model_name]
    if choice.meta and choice.meta.context_window then
      return choice.meta.context_window
    end
  end

  -- Fallback: adapter가 이미 resolve한 model info를 우선 재사용
  if adapter.model and adapter.model.info and adapter.model.info.meta and adapter.model.info.meta.context_window then
    return adapter.model.info.meta.context_window
  end

  return nil
end

---@param chat table|nil
---@return table|nil
function M.get_context_usage(chat)
  if not chat or not chat.adapter or not chat.messages then
    return nil
  end

  local context_window = get_context_window_from_adapter(chat.adapter)
  if not context_window or context_window <= 0 then
    return nil
  end

  local tokens_mod = require("codecompanion.utils.tokens")
  local used_tokens = tokens_mod.get_tokens(chat.messages)
  local pct = (used_tokens / context_window) * 100
  local pct_display = math.floor((pct * 10) + 0.5) / 10

  return {
    used_tokens = used_tokens,
    context_window = context_window,
    pct = pct,
    pct_display = pct_display,
  }
end

---@param chat table|nil
---@return string[]
function M.build_header_lines(chat)
  local header_lines = {}
  local stats = get_copilot_stats()
  local premium = stats and stats.quota_snapshots and stats.quota_snapshots.premium_interactions or nil

  local model_name = nil
  local adapter_name = nil
  if chat and chat.adapter then
    if chat.adapter.schema and chat.adapter.schema.model then
      model_name = chat.adapter.schema.model.default
    end
    adapter_name = chat.adapter.formatted_name or chat.adapter.name
  end

  local llm_label = nil
  if adapter_name and model_name then
    llm_label = string.format("%s / %s", adapter_name, model_name)
  elseif model_name then
    llm_label = model_name
  elseif adapter_name then
    llm_label = adapter_name
  end

  local function build_usage_bar(used, total, width)
    width = width or 10
    if not total or total <= 0 then
      return string.rep("░", width)
    end

    local ratio = used / total
    local filled = math.floor((ratio * width) + 0.5)
    filled = math.max(0, math.min(width, filled))

    return string.rep("█", filled) .. string.rep("░", width - filled)
  end

  if premium and premium.entitlement and premium.remaining then
    local total = premium.entitlement
    local remaining = premium.remaining
    local used = total - remaining
    local percent = total > 0 and ((used / total) * 100) or 0
    local bar = build_usage_bar(used, total, 10)

    table.insert(
      header_lines,
      string.format("### 💎 Premium [%s] %d/%d used · %d left (%.1f%%)", bar, used, total, remaining, percent)
    )
  else
    table.insert(header_lines, "### 💎 Premium: unavailable")
  end

  if llm_label then
    table.insert(header_lines, string.format("### 🤖 LLM: %s", llm_label:gsub(" / ", " · ")))
  end

  -- Context Window usage
  local usage = M.get_context_usage(chat)
  if usage then
    local bar = build_usage_bar(usage.used_tokens, usage.context_window, 10)
    table.insert(
      header_lines,
      string.format("### 📊 Context [%s] %d/%d (%.1f%%)", bar, usage.used_tokens, usage.context_window, usage.pct_display or usage.pct)
    )
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
