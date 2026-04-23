local config = require("codecompanion.config")
local input_mod = require("plugins.codecompanion.tools.human_tool.input")
local log = require("codecompanion.utils.log")
local render_mod = require("plugins.codecompanion.tools.human_tool.render")
local context_mod = require("plugins.codecompanion.tools.human_tool.context")

local M = {
  description = "Communicate with LLM in a Human, allowing the LLM to communicate to the user.",
  name = "human_tool",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args table
    ---@param opts { input: any, output_cb: fun(result: table) }
    ---@return nil
    function(self, args, opts)
      log:debug("HumanTool called with opts: %s", vim.inspect(opts))
      local llm_response = tostring(args.input or "")
      local output_cb = opts.output_cb

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
      local header_trim = vim.trim(context_mod.header)
      local i = 1
      while i <= #lines do
        if vim.trim(lines[i]) == header_trim then
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

      local output_message = table.concat(out_lines, "\n")

      vim.schedule(function()
        if meta.tools.chat then
          meta.tools.chat:add_buf_message({
            role = config.constants.USER_ROLE,
            content = output_message,
          })
        end
      end)

      log:debug("[wanchang] HumanTool success with self.function_call.call_id: %s", self.function_call.call_id)
      log:debug("[wanchang] output_message: %s", output_message)
      local user_role = config.interactions.chat.roles and config.interactions.chat.roles.user or "User"
      local display_text = string.format("**💬 Human Tool(%s)**\n\n%s", user_role, output_message)
      log:debug("[wanchang] display_text: %s", display_text)
      return chat:add_tool_output(self, output_message, display_text)
    end,

    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      return vim.notify("HumanTool An error occurred", vim.log.levels.ERROR)
    end,
  },
}

return M

