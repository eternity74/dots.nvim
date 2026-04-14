local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("UserCodeCompanionApproval", { clear = false })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeCompanionToolApprovalRequested",
    callback = function(ev)
      local bufnr = ev and ev.data and type(ev.data) == "table" and ev.data.bufnr
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if vim.api.nvim_get_current_buf() == bufnr then
        local mode = vim.api.nvim_get_mode().mode
        if mode:match("^i") then
          local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
          vim.api.nvim_feedkeys(esc, "n", true)
        end
      end
    end,
  })
end

return M

