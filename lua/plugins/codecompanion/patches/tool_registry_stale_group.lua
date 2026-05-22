--- Monkey-patch: ToolRegistry.add_group to handle stale group state.
--- When a group is removed via context reconciliation, group metadata can remain
--- while all member tools are already detached from `in_use`.
--- In that case, re-adding the same group is blocked by `add_group`'s early return.
local log = require("codecompanion.utils.log")

local M = {}

function M.setup()
  local ok, ToolRegistry = pcall(require, "codecompanion.interactions.chat.tool_registry")
  if not ok then
    log:warn("[cc_patch][tool_registry_stale_group] ToolRegistry not available; patch skipped")
    return
  end
  if ToolRegistry._patched_add_group_readd then
    return
  end

  local original_add_group = ToolRegistry.add_group
  if type(original_add_group) ~= "function" then
    log:warn("[cc_patch][tool_registry_stale_group] add_group is not a function; patch skipped")
    return
  end

  ToolRegistry.add_group = function(self, group, add_opts)
    -- If the group entry exists but none of its tools are active anymore,
    -- treat it as stale and clear it so the group can be added again.
    local group_tools = self.groups and self.groups[group]
    if type(group_tools) == "table" then
      local has_active_tool = false
      for _, tool_name in ipairs(group_tools) do
        if self.in_use and self.in_use[tool_name] then
          has_active_tool = true
          break
        end
      end

      if not has_active_tool then
        self.groups[group] = nil
      end
    end

    return original_add_group(self, group, add_opts)
  end

  ToolRegistry._patched_add_group_readd = true
  log:info("[cc_patch][tool_registry_stale_group] patched ToolRegistry.add_group")
end

return M
