local Curl = require("plenary.curl")

local buf_utils = require("codecompanion.utils.buffers")
local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local token = require("codecompanion.adapters.http.copilot.token")

local input_buf
local input_win
local pending_output_cb
local human_tool_augroup_id

local editor_context = require("codecompanion.interactions.shared.editor_context").new("chat")

local context_header = "> Context:"

local function is_valid_window(window_id)
  return window_id and vim.api.nvim_win_is_valid(window_id)
end

local function close_input_window()
  if is_valid_window(input_win) then
    vim.api.nvim_win_close(input_win, true)
  end
  input_win = nil
end

local function find_chat_win(chat)
  if not chat or not chat.bufnr or not vim.api.nvim_buf_is_valid(chat.bufnr) then
    return nil
  end

  local window_ids = vim.fn.win_findbuf(chat.bufnr)
  for _, window_id in ipairs(window_ids) do
    if vim.api.nvim_win_is_valid(window_id) then
      return window_id
    end
  end

  return nil
end

local function find_chat_win(chat)
  if not chat or not chat.bufnr or not vim.api.nvim_buf_is_valid(chat.bufnr) then
    return nil
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(winid) == chat.bufnr then
      return winid
    end
  end

  return nil
end

local function open_input_window_under_chat(chat, height)
  local chat_win = find_chat_win(chat)
  if not chat_win then
    return nil
  end

  vim.api.nvim_win_call(chat_win, function()
    vim.cmd("belowright " .. height .. "split")
    input_win = vim.api.nvim_get_current_win()
  end)

  return input_win
end

function render_context(chat)
  if vim.tbl_isempty(chat.context_items) then
    return {}
  end
  local start_row = 1

  local lines = {}
  table.insert(lines, context_header)

  for _, context in pairs(chat.context_items) do
    if not context or (context.opts and context.opts.visible == false) then
      goto continue
    end
    if context.opts and context.opts.sync_all then
      table.insert(lines, string.format("> - %s%s", icons.sync_all, context.id))
    elseif context.opts and context.opts.sync_diff then
      table.insert(lines, string.format("> - %s%s", icons.sync_diff, context.id))
    else
      table.insert(lines, string.format("> - %s", context.id))
    end
    ::continue::
  end
  if #lines == 1 then
    -- no context added
    return {}
  end
  table.insert(lines, "")

  return lines
  -- vim.api.nvim_buf_set_lines(chat.bufnr, start_row, start_row, false, lines)
end

local function render_viewport(chat, message)
  local ec_opts = config.interactions.shared.editor_context.opts
  local excluded = ec_opts and ec_opts.excluded
  local buf_lines = buf_utils.get_visible_lines(excluded)

  local count = 0
  local output = {}
  for bufnr, ranges in pairs(buf_lines) do
    for _, range in ipairs(ranges) do
      local content = chat_helpers.format_viewport_range_for_llm(bufnr, range)
      table.insert(output, content)
      count = count + 1
    end
  end

  if count == 0 then
    log:warn("No visible buffers to share")
  end
  return output
end

local function render_user_input(chat, user_input)
  local message = {
    role = config.constants.USER_ROLE,
    content = user_input,
  }
  local instances = editor_context:find(message)
  if instances then
    for _, instance in ipairs(instances) do
      local ctx = instance.ctx
      local ctx_config = chat.editor_context.editor_context[ctx]
      ctx_config["name"] = ctx
      local target = ctx_config.target
      local params = nil

      if ctx_config.opts and ctx_config.opts.has_params then
        params = find_params(message, ctx, target)
      end

      if ctx == "viewport" then
        user_input = user_input .. "\n" .. table.concat(render_viewport(chat, message), "\n")
      end

      ::continue::
    end
  end
  return user_input
end

local function get_copilot_stats()
  local oauth_token = token.fetch({ force = true }).oauth_token

  local ok, response = pcall(function()
    return Curl.get("https://api.github.com/copilot_internal/user", {
      sync = true,
      headers = {
        Authorization = "Bearer " .. oauth_token,
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
    })
  end)

  if not ok then
    log:error("Copilot Adapter: Could not get stats: %s", response)
    return nil
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Copilot Adapter: Error parsing stats response: %s", response.body)
    return nil
  end

  return json
end

--- 입력 버퍼를 생성(또는 재사용)하고 사용자 입력을 받아 콜백으로 응답합니다.
---@param prompt string LLM 응답 내용 (버퍼 상단에 표시)
---@param output_cb fun(result: table) 사용자 입력 완료 시 호출되는 콜백
local function open_input_buffer(chat, prompt, output_cb)
  pending_output_cb = output_cb
  -- 입력 버퍼 재사용(없거나 무효하면 새로 생성)
  if not (input_buf and vim.api.nvim_buf_is_valid(input_buf)) then
    input_buf = vim.api.nvim_create_buf(false, true)

    -- 버퍼 옵션 설정
    vim.api.nvim_buf_set_option(input_buf, 'buftype', 'nofile')   -- Buffer is not associated with a file
    vim.api.nvim_buf_set_option(input_buf, 'bufhidden', 'hide')  -- Wipe buffer when abandoned
    vim.api.nvim_buf_set_option(input_buf, 'swapfile', false)    -- Disable swapfile
    vim.api.nvim_buf_set_option(input_buf, 'buflisted', false)   -- Do not show in buffer list
    vim.api.nvim_buf_set_option(input_buf, 'modifiable', true)   -- Keep buffer editable
    vim.api.nvim_buf_set_option(input_buf, 'filetype', 'markdown') -- Optional: keep markdown ft

    -- 버퍼가 실제로 삭제되면 상태 정리 및 대기 중 콜백 처리
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = input_buf,
      once = true,
      callback = function()
        if pending_output_cb then
          pending_output_cb({ status = "success", data = "(사용자가 입력 창을 닫았습니다)" })
          pending_output_cb = nil
        end

        input_buf = nil
        input_win = nil
      end,
    })
  end

  local stats = get_copilot_stats()
  local premium = stats.quota_snapshots and stats.quota_snapshots.premium_interactions or nil

  -- 프롬프트를 주석으로 표시 (읽기 전용 헤더)
  local header_lines = {}

  for _, line in ipairs(render_context(chat)) do
    table.insert(header_lines, line)
  end
  table.insert(header_lines, "## Premium Interactions: Used " .. (premium.entitlement - premium.remaining) .. " / " .. premium.entitlement)
  table.insert(header_lines, "Describe what to do...")
  --[[
  for _, line in ipairs(vim.split(prompt, "\n", { plain = true })) do
    table.insert(header_lines, "<!-- " .. line .. " -->")
  end
  table.insert(header_lines, "<!-- " .. string.rep("-", 60) .. " -->")
  table.insert(header_lines, "<!-- 아래에 응답을 입력하고 Ctrl+S 로 전송하세요 -->")
  --]]
  table.insert(header_lines, "")

  -- 헤더 + 입력 영역 초기화
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, header_lines)

  -- 현재 창 높이 기준으로 분할 창 크기 결정
  local win_height = math.max(10, math.floor(vim.o.lines * 0.15))

  -- 창 재사용(무효하면 새로 생성)
  if not (input_win and vim.api.nvim_win_is_valid(input_win)) then
    local winid = open_input_window_under_chat(chat, win_height)
    if not winid then
      -- chat 창이 안 보이는 상태면 생성 보류
      return
    end
  else
    vim.api.nvim_set_current_win(input_win)
  end

  vim.api.nvim_win_set_buf(input_win, input_buf)

  -- 커서를 첫 입력 줄(헤더 마지막 빈 줄)로 이동
  local input_start_line = #header_lines
  vim.api.nvim_win_set_cursor(input_win, { input_start_line, 0 })

  -- Insert 모드로 진입
  vim.cmd("startinsert")

  local submitted = false

  local function reset_buffer()
    if not vim.api.nvim_buf_is_valid(input_buf) then
      return
    end

    -- 다음 입력을 위해 헤더 이후 내용 제거 및 커서 복귀
    local line_count = vim.api.nvim_buf_line_count(input_buf)
    if line_count > #header_lines then
      vim.api.nvim_buf_set_lines(input_buf, #header_lines, -1, false, {})
    end

    if input_win and vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_win_set_cursor(input_win, { #header_lines, 0 })
      vim.api.nvim_set_current_win(input_win)
      vim.cmd("startinsert")
    end
  end

  local function submit()
    if submitted then
      return
    end
    submitted = true

    -- 헤더 이후의 줄 + 첫 입력 줄(헤더 마지막 빈 줄)까지 사용자 입력으로 취급
    local all_lines = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
    local user_lines = {}
    for i = #header_lines, #all_lines do
      table.insert(user_lines, all_lines[i])
    end

    local user_input = vim.trim(table.concat(user_lines, "\n"))
    if user_input == "" then
      user_input = "(사용자가 빈 응답을 전송했습니다)"
    end

    -- 창/버퍼를 닫지 않고 초기화 후 재사용
    reset_buffer()

    -- 콜백으로 결과 전달
    output_cb({ status = "success", data = user_input })
    pending_output_cb = nil
  end

  -- Ctrl+S 키맵: Normal / Insert / Visual 모드 모두 적용
  local keymap_opts = { noremap = true, silent = true, buffer = input_buf }
  vim.keymap.set("n", "<C-s>", submit, keymap_opts)
  vim.keymap.set("i", "<C-s>", submit, keymap_opts)
  vim.keymap.set("v", "<C-s>", submit, keymap_opts)

end

local M = {
  description = "Communicate with LLM in a Human, allowing the LLM to communicate to the user.",
  name = "human_tool",
  cmds = {
    ---@param self CodeCompanion.Tools The Tools object (provides self.chat)
    ---@param args table The arguments from the LLM's tool call
    ---@param opts { input: any, output_cb: fun(result: table) }
    ---@return nil  -- 비동기: output_cb 로 결과를 전달
    function(self, args, opts)
      log:debug("HumanTool called with opts: %s", vim.inspect(opts))
      local llm_response = tostring(args.input or "")
      local output_cb = opts.output_cb

      vim.schedule(function()
        -- 1) Chat buffer에 LLM 응답 추가
        if self.chat then
          self.chat:add_buf_message({
            role = config.constants.LLM_ROLE,
            content = llm_response,
          })
        end

        -- 2) 입력 버퍼 열기 → Ctrl+S 시 output_cb 호출
        open_input_buffer(self.chat, llm_response, output_cb)
      end)
    end,
  },
  system_prompt = [[## HumanTool (`human_tool`)

## CONTEXT
- You have access to a human_tool running within CodeCompanion, in Neovim.
- This tool is the mandatory communication bridge between the human and the LLM.

### OBJECTIVE
- Ensure every assistant response is delivered through `human_tool`.
- This includes:
  1. the first response to the user's initial message,
  2. every follow-up response after messages coming from `human_tool`.

### RESPONSE POLICY
- For every turn, call `human_tool` with the message you want to send to the human.
- Never bypass `human_tool`.
- Use it both to provide information and to ask for clarification.
- When the tool responds `stop`, LLM should stop call human_tool and wait for the next user message to trigger the next response.
]],
  schema = {
    type = "function",
    ["function"] = {
      name = "human_tool",
      description = "A mandatory bridge tool for communicating with the human user. Use it on every turn, including the initial response and all follow-up responses.",
      parameters = {
        type = "object",
        properties = {
          input = {
            type = "string",
            description = "The exact message to send to the human. Every assistant response (initial and follow-up) must be delivered through this field.",
          },
          turn_type = {
            type = "string",
            enum = {
              "initial",
              "followup",
            },
            description = "Classifies whether this is the first response to the user's initial message (`initial`) or a response to subsequent interaction (`followup`).",
          },
        },
        required = {
          "input",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    setup = function(self, meta)
      local chat = meta.tools and meta.tools.chat
      if not chat or not chat.bufnr then
        return
      end

      human_tool_augroup_id = vim.api.nvim_create_augroup("CodeCompanionHumanTool_" .. chat.bufnr, { clear = true })

      vim.api.nvim_create_autocmd("BufWinLeave", {
        group = human_tool_augroup_id,
        buffer = chat.bufnr,
        callback = function()
          close_input_window()
        end,
      })

      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = human_tool_augroup_id,
        buffer = chat.bufnr,
        callback = function()
          if not pending_output_cb then
            return
          end
          if not (input_buf and vim.api.nvim_buf_is_valid(input_buf)) then
            return
          end
          if is_valid_window(input_win) then
            return
          end

          local win_height = math.max(10, math.floor(vim.o.lines * 0.15))
          local window_id = open_input_window_under_chat(chat, win_height)
          if not window_id then
            return
          end

          vim.api.nvim_win_set_buf(input_win, input_buf)
          local line_count = vim.api.nvim_buf_line_count(input_buf)
          vim.api.nvim_win_set_cursor(input_win, { math.max(line_count, 1), 0 })
          vim.cmd("startinsert")
        end,
      })
    end,
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    on_exit = function(self, meta)
      close_input_window()

      if human_tool_augroup_id then
        pcall(vim.api.nvim_del_augroup_by_id, human_tool_augroup_id)
        human_tool_augroup_id = nil
      end
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local user_input = vim.iter(stdout):flatten():join("\n")
      vim.schedule(function()
        -- 1) Chat buffer에 LLM 응답 추가
        if meta.tools.chat then
          meta.tools.chat:add_buf_message({
            role = config.constants.USER_ROLE,
            content = user_input,
          })
        end
      end)
      local message = render_user_input(chat, user_input)
      log:debug("[wanchang] HumanTool success with self.function_call.call_id: %s", self.function_call.call_id)
      return chat:add_tool_output(self, message)
    end,
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stderr table The error output from the command
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      return vim.notify("HumanTool An error occurred", vim.log.levels.ERROR)
    end,
  },
}

return M

