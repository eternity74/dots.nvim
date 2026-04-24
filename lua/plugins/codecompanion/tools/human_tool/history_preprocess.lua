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
---@return table[] Transformed messages
function M.preprocess_messages(messages)
  if not messages or #messages == 0 then
    return messages
  end

  fix_long_tool_call_ids(messages)

  local human_tool_call_ids, responded_call_ids = build_call_id_sets(messages)
  local result = {}

  for i, msg in ipairs(messages) do

    -- LLM message with tool_calls
    if msg.role == "llm" and msg.tools and msg.tools.calls then
      local has_human_tool = false
      local human_tool_input = nil

      for _, call in ipairs(msg.tools.calls) do
        if call["function"] and call["function"].name == "human_tool" then
          has_human_tool = true
          local ok, args = pcall(vim.json.decode, call["function"].arguments or "{}")
          if ok and args and args.input and args.input ~= "" then
            human_tool_input = args.input
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
        -- If already visible or no content, just drop the tool_call message
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
  vim.defer_fn(function()
    -- Patch 1: UI:create_chat - preprocess messages for restore
    local ui_ok, history_ui = pcall(require, "codecompanion._extensions.history.ui")
    if ui_ok and history_ui.create_chat then
      local original_create_chat = history_ui.create_chat
      history_ui.create_chat = function(self, chat_data)
        if chat_data and chat_data.messages then
          chat_data.messages = M.preprocess_messages(chat_data.messages)
        end
        return original_create_chat(self, chat_data)
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

