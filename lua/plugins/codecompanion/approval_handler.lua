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

      -- Focus the chat buffer window so user can interact with approval keymaps
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
          vim.api.nvim_set_current_win(winid)
          -- Scroll to the bottom where the approval prompt is
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          vim.api.nvim_win_set_cursor(winid, { line_count, 0 })
          break
        end
      end

      -- Exit insert mode if needed
      local mode = vim.api.nvim_get_mode().mode
      if mode:match("^i") then
        local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
        vim.api.nvim_feedkeys(esc, "n", true)
      end
    end,
  })
end

return M
