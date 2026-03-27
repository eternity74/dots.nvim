local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("UserCodeCompanionApproval", { clear = false })

  -- Define a sign for pending approvals (define once).
  pcall(vim.fn.sign_define, "CodeCompanionApprovalSign", { text = "●", texthl = "WarningMsg" })

  local function place_sign(bufnr)
    pcall(vim.fn.sign_place, 0, "CodeCompanionApproval", "CodeCompanionApprovalSign", bufnr, { lnum = 1 })
  end

  local function clear_sign(bufnr)
    pcall(vim.fn.sign_unplace, "CodeCompanionApproval", { buffer = bufnr })
  end

  local function ensure_normal_mode(bufnr)
    if vim.api.nvim_get_current_buf() ~= bufnr then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
    if vim.api.nvim_get_current_buf() == bufnr then
      local mode = vim.api.nvim_get_mode().mode
      if mode ~= "n" then
        local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
        vim.api.nvim_feedkeys(esc, "n", true)
      end
    end
  end

  local function find_approval_buf()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local ok, ft = pcall(vim.api.nvim_buf_get_option, bufnr, "filetype")
        if ok and ft == "codecompanion" then
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          for _, l in ipairs(lines) do
            if l:match("[Aa]pproval") then
              return bufnr
            end
          end
        end
      end
    end
    return nil
  end

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ToolApprovalRequested",
    callback = function(ev)
      local bufnr = nil
      if ev and ev.data and type(ev.data) == "table" and ev.data.bufnr then
        bufnr = ev.data.bufnr
      end
      bufnr = bufnr or find_approval_buf()
      if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local visible = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          visible = true
          break
        end
      end

      if visible then
        ensure_normal_mode(bufnr)
      else
        place_sign(bufnr)
        local name = (vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")) or ("buffer " .. bufnr)
        vim.schedule(function()
          vim.notify(("CodeCompanion approval required in %s. Open the chat buffer to respond."):format(name), vim.log.levels.WARN)
        end)

        local au_grp_name = "CodeCompanionApprovalBuf" .. tostring(bufnr)
        vim.api.nvim_create_augroup(au_grp_name, { clear = true })
        vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
          group = au_grp_name,
          buffer = bufnr,
          once = true,
          callback = function()
            ensure_normal_mode(bufnr)
            clear_sign(bufnr)
            vim.api.nvim_del_augroup_by_name(au_grp_name)
          end,
        })
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ToolApprovalFinished",
    callback = function(ev)
      local bufnr = nil
      if ev and ev.data and type(ev.data) == "table" and ev.data.bufnr then
        bufnr = ev.data.bufnr
      end
      bufnr = bufnr or find_approval_buf()
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        clear_sign(bufnr)
      end
    end,
  })
end

return M
