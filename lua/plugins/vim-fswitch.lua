local M = {
  "derekwyatt/vim-fswitch",
  lazy = false,
}

function M.config()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = { "*.h" },
    callback = function(ev)
      vim.b.fswitchdst = "cc,cpp"
      vim.b.fswitchlocs = ".,reg:|third_party/blink/public/common/|/third_party/blink/common/"
      vim.b.fswitchlocs = vim.b.fswitchlocs .. ",reg:|content/public/browser|content/browser"
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = { "*.cc" },
    callback = function(ev)
      vim.b.fswitchdst = "h"
      vim.b.fswitchlocs = ".,reg:|third_party/blink/common/|/third_party/blink/public/common/"
      vim.b.fswitchlocs = vim.b.fswitchlocs .. ",reg:|content/browser|content/public/browser"
    end,
  })
  vim.api.nvim_create_user_command("A", "FSHere", {})
end

return M
