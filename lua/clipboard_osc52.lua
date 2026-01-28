local M = {}

local osc52 = require("vim.ui.clipboard.osc52")

-- OSC52 시퀀스를 생성하여 터미널로 전송
function M.copy_to_clipboard(text)
  if not text or text == "" then
    return
  end

  -- 텍스트를 base64로 인코딩
  osc52.copy("+")(text)
  osc52.copy("*")(text)
end

-- Visual 모드에서 선택된 텍스트 가져오기
function M.get_visual_selection()
  -- Visual 모드 종료
  vim.cmd('noautocmd normal! "vy')

  -- 레지스터 'v'에서 텍스트 가져오기
  local lines = vim.fn.getreg('v', 1, true)

  return lines
end

-- Visual 모드에서 Ctrl+C 핸들러
function M.visual_copy()
  local text = M.get_visual_selection()
  M.copy_to_clipboard(text)
end
--[[
--vim.o.clipboard = "unnamedplus"
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    -- vim.highlight.on_yank()
    local copy_to_unnamedplus = require("vim.ui.clipboard.osc52").copy("+")
    copy_to_unnamedplus(vim.v.event.regcontents)
    local copy_to_unnamed = require("vim.ui.clipboard.osc52").copy("*")
    copy_to_unnamed(vim.v.event.regcontents)
  end,
})
--]]

return M

