vim.cmd([[ hi LspProgressMessageCompleted ctermfg=Green guifg=Green ]])

local progress_option = {
    series_format = function(title, message, percentage, done)
        local builder = {}
        local has_title = false
        local has_message = false
        if title and title ~= "" then
            table.insert(builder, title)
            has_title = true
        end
        if message and message ~= "" then
            table.insert(builder, message)
            has_message = true
        end
        if percentage and (has_title or has_message) then
            table.insert(builder, string.format("(%.0f%%%%)", percentage))
        end
        if done and (has_title or has_message) then
            table.insert(builder, "- done")
        end
        -- return table.concat(builder, " ")
        return { msg = table.concat(builder, " "), done = done }
    end,
    client_format = function(client_name, spinner, series_messages)
        if #series_messages == 0 then
            return nil
        end
        local builder = {}
        local done = true
        for _, series in ipairs(series_messages) do
            if not series.done then
                done = false
            end
            table.insert(builder, series.msg)
        end
        if done then
            -- replace the check mark once done
            spinner = "%#LspProgressMessageCompleted#✓%*"
        end
        return "["
            .. client_name
            .. "] "
            .. spinner
            .. " "
            .. table.concat(builder, ", ")
    end,
}

local function LspIcon()
    local active_clients_count = #vim.lsp.get_clients()
    return active_clients_count > 0 and " LSP" or ""
end

local function LspStatus()
    return require("lsp-progress").progress({
        format = function(messages)
            return #messages > 0 and table.concat(messages, " ") or ""
        end,
    })
end

return {
  "nvim-lualine/lualine.nvim",
  dependencies = {
    {"nvim-web-devicons", opt = true},
  },
  --event = { "BufNewFile", "BufRead" },
  config = function()
    require('lualine').setup {
      sections = {
        lualine_c = {
          {'filename', path = 1},
          LspIcon,
          LspStatus,
        },
        lualine_y = {'location'},
        lualine_z = { { require("plugins/lualine/cc-component") }, },
      },
      inactive_sections = {
        lualine_c = { { "filename", path = 1 } }
      },
    }
  end,
}
