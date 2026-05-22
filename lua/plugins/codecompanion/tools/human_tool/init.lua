local config = require("codecompanion.config")
local input_mod = require("plugins.codecompanion.tools.human_tool.input")
local log = require("codecompanion.utils.log")
local render_mod = require("plugins.codecompanion.tools.human_tool.render")
local context_mod = require("plugins.codecompanion.tools.human_tool.context")

local function normalize_model_name(model)
  if type(model) ~= "string" then
    return ""
  end

  local normalized = model:lower()
  normalized = normalized:gsub("%s+", "-")
  normalized = normalized:gsub("_", "-")
  return normalized
end

local function maybe_auto_switch_model(chat)
  if not chat or not chat.adapter or not chat.adapter.schema or not chat.adapter.schema.model then
    return
  end

  local current_model = chat.adapter.schema.model.default
  local normalized = normalize_model_name(current_model)
  local target_model

  if normalized == "kaiku-4.5" or normalized == "claude-haiku-4.5" or normalized == "claude-haiku-4-5" then
    target_model = "claude-opus-4.6"
  elseif normalized == "gpt-5-mini" then
    target_model = "gpt-5.3-codex"
  end

  if not target_model or target_model == current_model then
    return
  end

  log:info("[human_tool] Auto-switch model: %s -> %s", tostring(current_model), target_model)
  chat:change_model({ model = target_model })
end

local M = {
  description = "Communicate with LLM in a Human, allowing the LLM to communicate to the user.",
  name = "human_tool",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args table
    ---@param opts { input: any, output_cb: fun(result: table) }
    ---@return nil
    function(self, args, opts)
      local llm_response = tostring(args.input or "")
      local output_cb = opts.output_cb

      maybe_auto_switch_model(self.chat)

      vim.schedule(function()
        if self.chat then
          self.chat:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = llm_response,
          })
        end
        input_mod.open(self.chat, llm_response, output_cb)
      end)
    end,
  },
  system_prompt = [[## HumanTool (`human_tool`)

## CONTEXT
- You have access to a human_tool running within CodeCompanion, in Neovim.
- This tool is the mandatory communication bridge between the human and the LLM.

### OBJECTIVE
- Ensure every assistant response is delivered through `human_tool`.
- This includes:
  1. the first response to the user's initial message,
  2. every follow-up response after messages coming from `human_tool`.

### RESPONSE POLICY
- For every turn, call `human_tool` with the message you want to send to the human.
- Never bypass `human_tool`.
- Use it both to provide information and to ask for clarification.
- When the tool responds `stop`, LLM should stop call human_tool and wait for the next user message to trigger the next response.
]],
  schema = {
    type = "function",
    ["function"] = {
      name = "human_tool",
      description = "A mandatory bridge tool for communicating with the human user. Use it on every turn, including the initial response and all follow-up responses.",
      parameters = {
        type = "object",
        properties = {
          input = {
            type = "string",
            description = "The exact message to send to the human. Every assistant response (initial and follow-up) must be delivered through this field.",
          },
          turn_type = {
            type = "string",
            enum = { "initial", "followup" },
            description = "Classifies whether this is the first response to the user's initial message (`initial`) or a response to subsequent interaction (`followup`).",
          },
        },
        required = { "input" },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    setup = function(self, meta)
      -- No separate window management needed; input is in the chat buffer
    end,

    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    on_exit = function(self, meta)
      -- Clean up pending state if needed
      if input_mod.get_pending_cb() then
        input_mod.set_pending_cb(nil)
      end
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local user_input = vim.iter(stdout):flatten():join("\n")

      local replaced_input = render_mod.render_user_input(chat, user_input)

      local lines = vim.split(replaced_input, "\n", { plain = true })
      local out_lines = {}
      local premium_lines = {}
      local header_trim = vim.trim(context_mod.header)
      local i = 1
      while i <= #lines do
        local trimmed = vim.trim(lines[i])
        local is_premium_line = vim.startswith(trimmed, "### Premium Interactions")
          or vim.startswith(trimmed, "### 💎 Premium")
          or vim.startswith(trimmed, "### 🤖 LLM")

        if is_premium_line then
          table.insert(premium_lines, lines[i])
          i = i + 1
        elseif trimmed == header_trim then
          -- skip the header line and all subsequent lines that start with "> "
          i = i + 1
          while i <= #lines and (lines[i]:sub(1, 2) == "> ") do
            i = i + 1
          end
        else
          table.insert(out_lines, lines[i])
          i = i + 1
        end
      end

      -- Keep premium/LLM status lines for chat rendering only.
      -- Only actual user input should be returned to the LLM.
      local output_message = table.concat(out_lines, "\n")
      local premium_info = table.concat(premium_lines, "\n")
      local buffer_message = output_message
      if premium_info ~= "" then
        if buffer_message ~= "" then
          buffer_message = premium_info .. "\n" .. buffer_message
        else
          buffer_message = premium_info
        end
      end

      vim.schedule(function()
        if meta.tools.chat then
          meta.tools.chat:add_buf_message({
            role = config.constants.USER_ROLE,
            content = buffer_message,
          })
        end
      end)

      local user_role = config.interactions.chat.roles and config.interactions.chat.roles.user or "User"
      local display_text = string.format("**💬 Human Tool(%s)**\n\n%s", user_role, buffer_message)
      return chat:add_tool_output(self, output_message, display_text)
    end,

    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta and meta.tools and meta.tools.chat or nil
      local err_text = "HumanTool error occurred"
      if type(stderr) == "table" and #stderr > 0 then
        err_text = err_text .. ":\n" .. table.concat(stderr, "\n")
      end

      if chat then
        vim.schedule(function()
          chat:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = "⚠️ " .. err_text,
          })
        end)
      end
      return nil
    end,
  },
}

return M

