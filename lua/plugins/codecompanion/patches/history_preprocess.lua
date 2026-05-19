--- Pre-process history chat messages before rendering.
---
--- This module monkey-patches the history extension's UI:create_chat() to
--- transform messages before they are passed to Chat.new().
---
--- Transformations:
--- 1. human_tool tool_calls → plain LLM messages (content = arguments.input)
--- 2. human_tool tool responses → plain user messages
--- 3. Long tool_call IDs (>64 chars) → shortened with sha256
--- 4. Orphaned tool_calls (no response) → dummy tool response inserted
--- 5. Title generation: _meta.tag messages excluded from context
---
--- This approach:
--- - Does NOT modify chat.messages (no LLM impact)
--- - Does NOT modify saved JSON files
--- - Only affects rendering when restoring from history


local M = {}
local did_setup = false

---@param call table
---@param responded_call_ids table<string, boolean>
---@return boolean
local function is_pending_call(call, responded_call_ids)
  if not call then
    return false
  end
  if call.id and responded_call_ids[call.id] then
    return false
  end
  if call.call_id and responded_call_ids[call.call_id] then
    return false
  end
  return true
end


--- Check if the adapter expects 'fc_' prefixed tool_call IDs (GPT models).
---@param adapter_name string|nil
---@return boolean
local function expects_fc_prefix(adapter_name)
  if not adapter_name then
    return false
  end
  -- OpenAI GPT models use 'fc_' prefix
  local gpt_adapters = { "openai", "copilot" }
  for _, name in ipairs(gpt_adapters) do
    if adapter_name == name then
      return true
    end
  end
  return false
end

--- Normalize tool_call ID prefix for GPT models that expect 'fc_' instead of 'call_'.
---@param messages table[] Array of chat messages
---@param to_fc boolean If true, convert call_ → fc_; if false, do nothing
local function fix_tool_call_id_prefix(messages, to_fc)
  if not to_fc then
    return
  end

  local id_map = {}

  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.calls then
      for _, call in ipairs(msg.tools.calls) do
        if call.id and call.id:sub(1, 5) == "call_" then
          local new_id = "fc_" .. call.id:sub(6)
          id_map[call.id] = new_id
          call.id = new_id
        end
      end
    end
  end

  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.call_id and id_map[msg.tools.call_id] then
      msg.tools.call_id = id_map[msg.tools.call_id]
    end
  end
end

--- Shorten tool_call IDs that exceed the OpenAI API limit (64 chars).
---@param messages table[] Array of chat messages
local function fix_long_tool_call_ids(messages)
  local MAX_ID_LEN = 64
  local id_map = {}

  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.calls then
      for _, call in ipairs(msg.tools.calls) do
        if call.id and #call.id > MAX_ID_LEN then
          if not id_map[call.id] then
            id_map[call.id] = "call_" .. vim.fn.sha256(call.id):sub(1, 24)
          end
          call.id = id_map[call.id]
        end
      end
    end
  end

  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.call_id and id_map[msg.tools.call_id] then
      msg.tools.call_id = id_map[msg.tools.call_id]
    end
  end
end

--- Build lookup tables for human_tool call IDs and responded call IDs.
---@param messages table[]
---@return table<string, boolean> human_tool_call_ids
---@return table<string, boolean> responded_call_ids
local function build_call_id_sets(messages)
  local human_tool_call_ids = {}
  local responded_call_ids = {}

  for _, msg in ipairs(messages) do
    if msg.role == "llm" and msg.tools and msg.tools.calls then
      for _, call in ipairs(msg.tools.calls) do
        if call["function"] and call["function"].name == "human_tool" then
          -- Register both id and call_id (Copilot uses call_id for matching)
          if call.id then
            human_tool_call_ids[call.id] = true
          end
          if call.call_id then
            human_tool_call_ids[call.call_id] = true
          end
        end
      end
    end
    if msg.role == "tool" and msg.tools and msg.tools.call_id then
      responded_call_ids[msg.tools.call_id] = true
    end
  end

  return human_tool_call_ids, responded_call_ids
end


--- Transform messages for history restore.
---@param messages table[] Array of chat messages
---@param opts? {adapter_name?: string} Options
---@return table[] Transformed messages
function M.preprocess_messages(messages, opts)
  if not messages or #messages == 0 then
    return messages
  end

  opts = opts or {}
  fix_tool_call_id_prefix(messages, expects_fc_prefix(opts.adapter_name))
  fix_long_tool_call_ids(messages)

  local human_tool_call_ids, responded_call_ids = build_call_id_sets(messages)
  local result = {}

  for i, msg in ipairs(messages) do

    -- LLM message with tool_calls
    if msg.role == "llm" and msg.tools and msg.tools.calls then
      local has_human_tool = false
      local human_tool_input = nil
      local human_tool_call = nil
      local turn_type = nil

      for _, call in ipairs(msg.tools.calls) do
        if call["function"] and call["function"].name == "human_tool" then
          has_human_tool = true
          human_tool_call = call
          local ok, args = pcall(vim.json.decode, call["function"].arguments or "{}")
          if ok and args then
            if args.input and args.input ~= "" then
              human_tool_input = args.input
            end
            if args.turn_type and args.turn_type ~= "" then
              turn_type = tostring(args.turn_type)
            end
          end
          break
        end
      end

      if has_human_tool then
        -- Convert human_tool call to plain LLM message
        local content = human_tool_input or ""

        -- Skip if preceding visible LLM message already has same content
        local already_visible = false
        for j = #result, 1, -1 do
          local prev = result[j]
          if prev.role == "llm" then
            if prev.opts and prev.opts.visible ~= false
              and prev.content and prev.content == content and content ~= "" then
              already_visible = true
            end
            break
          elseif prev.role ~= "llm" then
            break
          end
        end

        if not already_visible and content ~= "" then
          -- Replace with plain LLM message (no tool_calls)
          table.insert(result, {
            role = "llm",
            content = content,
            opts = { visible = true },
            _meta = msg._meta,
          })
        end

        -- pending human_tool 상태 안내 문구는 복원 UI에 표시하지 않음
        -- If already visible or no content, just drop the tool_call message
        -- (pending call도 동일하게 별도 메시지 없이 생략)
      else
        -- Non-human_tool: keep as-is
        table.insert(result, msg)

        -- Insert dummy responses for any orphaned tool_calls
        for _, call in ipairs(msg.tools.calls) do
          if call.id and not responded_call_ids[call.id]
            and not (call.call_id and responded_call_ids[call.call_id]) then
            local fn_name = call["function"] and call["function"].name or "unknown"
            table.insert(result, {
              role = "tool",
              content = string.format("(Tool '%s' did not complete - session ended)", fn_name),
              opts = { visible = false },
              tools = { call_id = call.id },
            })
          end
        end
      end

    -- Tool response
    elseif msg.role == "tool" and msg.tools and msg.tools.call_id then
      if human_tool_call_ids[msg.tools.call_id] then
        -- Convert human_tool response to plain user message
        if msg.content and msg.content ~= "" then
          table.insert(result, {
            role = "user",
            content = msg.content,
            opts = { visible = true },
          })
        end
        -- Drop the original tool response entirely
      else
        -- Non-human_tool tool response: keep as-is
        table.insert(result, msg)
      end

    else
      -- All other messages: pass through
      table.insert(result, msg)
    end
  end

  return result
end

--- Monkey-patch the history extension's UI:create_chat to preprocess messages
--- and TitleGenerator:generate to filter out _meta.tag messages
function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  vim.defer_fn(function()
    -- Patch 1: UI:create_chat - preprocess messages for restore
    local ui_ok, history_ui = pcall(require, "codecompanion._extensions.history.ui")
    if ui_ok and history_ui.create_chat then
      local original_create_chat = history_ui.create_chat
      history_ui.create_chat = function(self, chat_data)
        if chat_data and chat_data.messages then
          local adapter_name = chat_data.adapter and chat_data.adapter.name or nil
          chat_data.messages = M.preprocess_messages(chat_data.messages, { adapter_name = adapter_name })
        end

        local chat = original_create_chat(self, chat_data)

        -- Restore adapter model name from settings so lualine/events reflect the saved model
        if chat and chat.settings and chat.settings.model and chat.adapter then
          local restored_model = tostring(chat.settings.model)
          if restored_model:lower():match("^gpt") then
            restored_model = "gpt-5-mini"
            chat.settings.model = restored_model
          end

          if chat.adapter.schema and chat.adapter.schema.model then
            chat.adapter.schema.model.default = restored_model
          end
          if type(chat.adapter.model) == "table" then
            chat.adapter.model.name = restored_model
          end

          -- Remove settings keys that are disabled for the restored model
          -- (e.g., temperature is not supported by codex/gpt-5 models)
          if chat.adapter.schema then
            for k, v in pairs(chat.adapter.schema) do
              if type(v) == "table" and type(v.enabled) == "function" and not v.enabled(chat.adapter) then
                chat.settings[k] = nil
              end
            end
          end

          -- Re-fire ChatModel event so lualine picks up the correct model
          local utils = require("codecompanion.utils")
          local adapters = require("codecompanion.adapters")
          utils.fire("ChatModel", {
            adapter = adapters.make_safe(chat.adapter),
            bufnr = chat.bufnr,
            id = chat.id,
            model = chat.settings.model,
          })
        end

        return chat
      end
    end

    -- Patch 2: TitleGenerator:generate - exclude _meta.tag messages from title context
    local tg_ok, TitleGenerator = pcall(require, "codecompanion._extensions.history.title_generator")
    if tg_ok and TitleGenerator.generate then
      local original_generate = TitleGenerator.generate
      TitleGenerator.generate = function(self, chat, callback, is_refresh)
        local patched = {}
        for _, msg in ipairs(chat.messages or {}) do
          if msg._meta and msg._meta.tag and not (msg.opts and msg.opts.tag) then
            msg.opts = msg.opts or {}
            msg.opts.tag = msg._meta.tag
            table.insert(patched, msg)
          end
        end
        local r = original_generate(self, chat, callback, is_refresh)
        for _, msg in ipairs(patched) do
          msg.opts.tag = nil
        end
        return r
      end
    end
  end, 100)
end

return M

