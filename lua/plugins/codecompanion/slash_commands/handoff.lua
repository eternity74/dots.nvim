local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local PROMPT = [[Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.
Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
Redact any sensitive information, such as API keys, passwords, or personally identifiable information.
If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

Prioritization and compression rules (VERY IMPORTANT):
- Keep RESOLVED topics concise. For each resolved topic, use 1-2 bullets with: problem -> fix -> result.
- Expand UNRESOLVED topics in detail. For each unresolved topic, include:
  - current state and why it's unresolved
  - what was tried already
  - exact blocker/failure signal (error/log/symptom)
  - concrete next actions (ordered checklist)
- Expand RECENT context in detail. Cover the latest conversation flow with enough fidelity for immediate continuation:
  - recent user intent changes
  - recent code changes and affected files
  - recent tool calls/outcomes/approvals
  - latest assumptions/decisions/open questions
- If details conflict, prefer the most recent messages.

The document MUST include the following sections:
1. **분석 내용**
   - Keep completed analysis brief
   - Add detailed notes for ongoing investigations and recent findings
2. **사용자 요청 내용**
   - Original request summary
   - Recent request updates/priority shifts (detailed)
3. **처리 완료된 내용**
   - Briefly list completed items and validated outcomes
4. **추가적으로 해야 할 일**
   - Detailed unresolved issues first (highest priority)
   - For each item: context, blocker, and next step checklist

Output requirements:
- Return the result directly as Markdown text in this chat.
- Do NOT create, write, or save any file.
- Do NOT call any tools or run commands.
- Keep resolved history compact; allocate more tokens to unresolved + recent context.
]]

---@class CodeCompanion.SlashCommand.Handoff
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

local function extract_human_tool_input(call)
  if type(call) ~= "table" then
    return nil
  end

  local fn = call["function"] or {}
  local fn_name = fn.name or call.name
  if fn_name ~= "human_tool" then
    return nil
  end

  local raw_args = fn.arguments or call.arguments or "{}"
  if type(raw_args) ~= "string" then
    return nil
  end

  local ok, args = pcall(vim.json.decode, raw_args)
  if ok and args and type(args.input) == "string" and args.input ~= "" then
    return args.input
  end

  return nil
end

local function get_last_assistant_message(messages)

  for i = #messages, 1, -1 do
    local msg = messages[i]
    local is_llm_role = msg and (msg.role == config.constants.LLM_ROLE or msg.role == "assistant")
    if is_llm_role then

      if type(msg.content) == "string" and msg.content ~= "" then
        return msg.content
      end

      local calls = (msg.tools and msg.tools.calls) or msg.tool_calls
      if type(calls) == "table" then
        for _, call in ipairs(calls) do
          local input = extract_human_tool_input(call)
          if input then
            return input
          end
        end
      end
    end
  end

  log:warn("[handoff] no assistant message content found")
  return nil
end


local function get_handoff_args(_chat, context)
  if context and context.handoff_args_override ~= nil then
    return vim.trim(tostring(context.handoff_args_override))
  end

  local bufnr = context and context.bufnr or vim.api.nvim_get_current_buf()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end

  local cursor = context and context.cursor or vim.api.nvim_win_get_cursor(0)
  local row = (cursor and cursor[1]) or vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local trimmed = vim.trim(line)

  if trimmed == "" then
    return ""
  end

  local prefix = "/handoff"
  if vim.startswith(trimmed, prefix) then
    return vim.trim(trimmed:sub(#prefix + 1))
  end

  return trimmed
end

local function submit_through_human_tool(chat, prompt)

  local ok, input_mod = pcall(require, "plugins.codecompanion.tools.human_tool.input")
  if not ok or not input_mod.get_pending_cb() then
    return false
  end

  local active_chat = input_mod.get_active_chat()
  if active_chat ~= chat then
    return false
  end

  if type(input_mod.submit_silent) ~= "function" then
    return false
  end

  local submitted = input_mod.submit_silent(prompt)
  return submitted
end


function SlashCommand:execute()
  local chat = self.Chat
  log:info("[handoff] execute started")

  local handoff_args = get_handoff_args(chat, self.context)

  if chat.bufnr and vim.api.nvim_buf_is_valid(chat.bufnr) and vim.api.nvim_get_current_buf() == chat.bufnr then
    vim.api.nvim_set_current_line("")
  end

  local user_prompt = PROMPT
  if handoff_args ~= "" then
    user_prompt = user_prompt .. "\n\nArguments: " .. handoff_args
  end

  local handled = false

  local function do_handoff(current_chat)

    if handled then
      return
    end

    local handoff_content = get_last_assistant_message(current_chat.messages or {})
    if not handoff_content or handoff_content == "" then
      return
    end

    handled = true
    log:info("[handoff] handoff content captured (length=%d)", #handoff_content)

    local before_messages = #(current_chat.messages or {})
    local before_context_items = #(current_chat.context_items or {})

    -- Keep chat buffer as-is, but reset LLM context messages.
    -- Preserve system-role messages and rules context
    local preserved_msgs = {}
    for _, msg in ipairs(current_chat.messages or {}) do
      local dominated_by_system = (msg.role == config.constants.SYSTEM_ROLE)
      local is_rules = (msg._meta and msg._meta.tag == "rules")
      if dominated_by_system or is_rules then
        table.insert(preserved_msgs, msg)
      end
    end

    current_chat.messages = {}

    -- Re-inject preserved messages (system + rules)
    for _, msg in ipairs(preserved_msgs) do
      table.insert(current_chat.messages, msg)
    end

    -- Add handoff context as system message
    current_chat:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = "Handoff context for next session:\n\n" .. handoff_content,
    }, { visible = false })
    log:info("[handoff] reset messages and injected hidden system handoff context")

    current_chat:add_buf_message({
      role = config.constants.USER_ROLE,
      content = "이전 대화는 화면에 유지하고, LLM 컨텍스트는 handoff 요약 기준으로 리셋했습니다.",
    })

  end

  -- Use autocmd to detect when tools (including human_tool) finish
  local aug = vim.api.nvim_create_augroup("HandoffToolsFinished_" .. chat.id, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = aug,
    pattern = "CodeCompanionToolsFinished",
    callback = function(ev)
      if handled then
        vim.api.nvim_del_augroup_by_id(aug)
        return
      end
      -- Filter: only react to our chat's bufnr
      local data = ev and ev.data or {}
      if data.bufnr and data.bufnr ~= chat.bufnr then
        return
      end
      -- Schedule to let tool output be added to messages first
      vim.schedule(function()
        do_handoff(chat)
        if handled then
          vim.api.nvim_del_augroup_by_id(aug)
        end
      end)
    end,
  })
  -- Also keep on_completed as fallback for non-tool responses
  chat:add_callback("on_completed", function(current_chat)
    do_handoff(current_chat)
    if handled then
      vim.api.nvim_del_augroup_by_id(aug)
    end
  end)

  if submit_through_human_tool(chat, user_prompt) then
    log:info("[handoff] prompt submitted via human_tool path")
    return
  end

  log:info("[handoff] fallback path: add hidden user message + submit directly")
  chat:add_message({
    role = config.constants.USER_ROLE,
    content = user_prompt,
  }, { visible = false })
  chat:submit()
end

return SlashCommand

