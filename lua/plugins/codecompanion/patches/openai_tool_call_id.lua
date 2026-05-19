--- Monkey-patch: openai adapter's output_response to use call_id or id
--- This fixes tool response matching when call_id differs from id (e.g., Copilot adapter).
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
      return
    end

    -- The openai adapter is a table (not an instance), patch the handler
    if openai.handlers and openai.handlers.tools and openai.handlers.tools.output_response then
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
    end
  end, 50)
end

return M
