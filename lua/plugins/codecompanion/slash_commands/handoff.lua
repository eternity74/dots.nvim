local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local PROMPT = [[Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.
Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.
Redact any sensitive information, such as API keys, passwords, or personally identifiable information.
If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

The document MUST include the following sections:
1. **분석 내용** - What was analyzed or investigated during this session
2. **사용자 요청 내용** - What the user originally requested
3. **처리 완료된 내용** - What was accomplished and completed
4. **추가적으로 해야 할 일** - Remaining tasks or next steps for the follow-up session

Output requirements:
- Return the result directly as Markdown text in this chat.
- Do NOT create, write, or save any file.
- Do NOT call any tools or run commands.
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
  log:debug("[handoff] scanning assistant messages: total=%d", #messages)

  for i = #messages, 1, -1 do
    local msg = messages[i]
    local is_llm_role = msg and (msg.role == config.constants.LLM_ROLE or msg.role == "assistant")
    if is_llm_role then
      log:debug("[handoff] found assistant candidate at index=%d (has_content=%s)", i, tostring(type(msg.content) == "string" and msg.content ~= ""))

      if type(msg.content) == "string" and msg.content ~= "" then
        log:debug("[handoff] using assistant content from index=%d, length=%d", i, #msg.content)
        return msg.content
      end

      local calls = (msg.tools and msg.tools.calls) or msg.tool_calls
      if type(calls) == "table" then
        log:debug("[handoff] assistant message index=%d has tool calls: %d", i, #calls)
        for _, call in ipairs(calls) do
          local input = extract_human_tool_input(call)
          if input then
            log:debug("[handoff] extracted human_tool input from tool call, length=%d", #input)
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
  log:debug("[handoff] trying to submit via human_tool (prompt_length=%d)", #prompt)

  local ok, input_mod = pcall(require, "plugins.codecompanion.tools.human_tool.input")
  if not ok or not input_mod.get_pending_cb() then
    log:debug("[handoff] human_tool input module unavailable or no pending callback")
    return false
  end

  local active_chat = input_mod.get_active_chat()
  if active_chat ~= chat then
    log:debug("[handoff] active chat mismatch, cannot submit through human_tool")
    return false
  end

  local bufnr = input_mod.get_buf()
  local header_start = input_mod.get_header_start()
  local header_count = input_mod.get_header_line_count()

  if not bufnr or not header_start or not header_count then
    log:warn("[handoff] human_tool buffer/header metadata missing: bufnr=%s, header_start=%s, header_count=%s", tostring(bufnr), tostring(header_start), tostring(header_count))
    return false
  end

  local input_start = header_start + header_count
  local lines = vim.split(prompt, "\n", { plain = true })
  log:debug("[handoff] writing prompt into human_tool input area: bufnr=%d, input_start=%d, lines=%d", bufnr, input_start, #lines)

  local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  end

  vim.api.nvim_buf_set_lines(bufnr, input_start, -1, false, lines)

  if not was_modifiable then
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  end

  local submitted = input_mod.submit()
  log:debug("[handoff] input_mod.submit() result=%s", tostring(submitted))
  return submitted
end


function SlashCommand:execute()
  local chat = self.Chat
  log:info("[handoff] execute started")

  local handoff_args = get_handoff_args(chat, self.context)
  log:debug("[handoff] parsed args='%s'", handoff_args)

  if chat.bufnr and vim.api.nvim_buf_is_valid(chat.bufnr) and vim.api.nvim_get_current_buf() == chat.bufnr then
    vim.api.nvim_set_current_line("")
    log:debug("[handoff] cleared current /handoff command line in chat buffer")
  end

  local user_prompt = PROMPT
  if handoff_args ~= "" then
    user_prompt = user_prompt .. "\n\nArguments: " .. handoff_args
  end
  log:debug("[handoff] prepared prompt (length=%d)", #user_prompt)

  local handled = false

  local function do_handoff(current_chat)
    log:debug("[handoff] do_handoff fired (handled=%s, messages=%d)", tostring(handled), #(current_chat.messages or {}))

    if handled then
      log:debug("[handoff] ignored because already handled")
      return
    end

    local handoff_content = get_last_assistant_message(current_chat.messages or {})
    if not handoff_content or handoff_content == "" then
      log:debug("[handoff] no assistant handoff content yet")
      return
    end

    handled = true
    log:info("[handoff] handoff content captured (length=%d)", #handoff_content)

    local before_messages = #(current_chat.messages or {})
    local before_context_items = #(current_chat.context_items or {})
    log:debug("[handoff] pre-clear state: messages=%d, context_items=%d", before_messages, before_context_items)

    local preserved_context_items = vim.deepcopy(current_chat.context_items or {})
    local preserved_tool_registry = {
      flags = vim.deepcopy(current_chat.tool_registry.flags or {}),
      groups = vim.deepcopy(current_chat.tool_registry.groups or {}),
      in_use = vim.deepcopy(current_chat.tool_registry.in_use or {}),
      schemas = vim.deepcopy(current_chat.tool_registry.schemas or {}),
    }

    current_chat:clear()
    log:info("[handoff] chat:clear() executed")

    current_chat.context_items = preserved_context_items
    current_chat.tool_registry.flags = preserved_tool_registry.flags
    current_chat.tool_registry.groups = preserved_tool_registry.groups
    current_chat.tool_registry.in_use = preserved_tool_registry.in_use
    current_chat.tool_registry.schemas = preserved_tool_registry.schemas
    log:debug("[handoff] restored preserved context/tool registry")

    current_chat.context:render()
    log:debug("[handoff] context re-rendered")

    current_chat:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = "Handoff context for next session:\n\n" .. handoff_content,
    }, { visible = true })
    log:info("[handoff] injected system message with handoff context")

    current_chat:add_buf_message({
      role = config.constants.USER_ROLE,
      content = "Handoff context was injected as a system message. Continue from here.",
    })
    log:debug("[handoff] added user-visible confirmation message")

    log:debug("[handoff] post-injection message count=%d", #(current_chat.messages or {}))
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
  log:debug("[handoff] autocmd + on_completed callback registered")

  if submit_through_human_tool(chat, user_prompt) then
    log:info("[handoff] prompt submitted via human_tool path")
    return
  end

  log:info("[handoff] fallback path: add user message + submit directly")
  chat:add_buf_message({
    role = config.constants.USER_ROLE,
    content = user_prompt,
  })
  chat:submit()
end


return SlashCommand
