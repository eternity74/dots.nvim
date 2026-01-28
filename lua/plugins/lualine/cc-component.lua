local M = require("lualine.component"):extend()

M.processing = false
M.spinner_index = 1
M.name = ""

local spinner_symbols = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}
local spinner_symbols_len = 10

-- Initializer
function M:init(options)
  M.super.init(self, options)

  local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionRequest*",
    group = group,
    callback = function(request)
      if request.match == "CodeCompanionRequestStarted" then
        self.processing = true
      elseif request.match == "CodeCompanionRequestFinished" then
        self.title = ""
        self.processing = false
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionChatModel",
    group = group,
    callback = function(request)
      self.name = "N/A"
      if request.data.adapter ~= nil then
        if request.data.adapter.model ~= nil then
          self.name = request.data.adapter.model.name
        else
          self.name = request.data.adapter.name
        end
      end
    end
  })
end

-- Function that runs every time statusline is updated
function M:update_status()
  if self.processing then
    self.spinner_index = (self.spinner_index % spinner_symbols_len) + 1
    return self.name .. spinner_symbols[self.spinner_index]
  else
    return self.name
  end
end

return M
