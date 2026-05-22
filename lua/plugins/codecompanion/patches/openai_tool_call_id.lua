--- Monkey-patch: openai adapter's output_response to use call_id or id
--- This fixes tool response matching when call_id differs from id (e.g., Copilot adapter).
local log = require("codecompanion.utils.log")

local M = {}

local did_setup = false

function M.setup()
  if did_setup then
    return
  end
  did_setup = true

  vim.defer_fn(function()
    local ok, openai = pcall(require, "codecompanion.adapters.http.openai")
    if not ok or not openai then
      log:warn("[cc_patch][openai_tool_call_id] openai adapter not available; patch skipped")
      return
    end

    -- The openai adapter is a table (not an instance), patch the handler
    if openai.handlers and openai.handlers.tools and openai.handlers.tools.output_response then
      log:info("[cc_patch][openai_tool_call_id] patched openai.handlers.tools.output_response")
      openai.handlers.tools.output_response = function(self, tool_call, output)
        return {
          role = self.roles.tool or "tool",
          tools = {
            call_id = tool_call.call_id or tool_call.id,
            name = tool_call["function"].name,
          },
          content = output,
          opts = { visible = false },
        }
      end
    else
      log:warn("[cc_patch][openai_tool_call_id] output_response handler not found; patch skipped")
    end
  end, 50)
end

return M
