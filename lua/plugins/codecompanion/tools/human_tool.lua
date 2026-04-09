local config = require("codecompanion.config")

local input_buf
local input_win
local pending_output_cb

--- 입력 버퍼를 생성(또는 재사용)하고 사용자 입력을 받아 콜백으로 응답합니다.
---@param prompt string LLM 응답 내용 (버퍼 상단에 표시)
---@param output_cb fun(result: table) 사용자 입력 완료 시 호출되는 콜백
local function open_input_buffer(prompt, output_cb)
  pending_output_cb = output_cb
  -- 입력 버퍼 재사용(없거나 무효하면 새로 생성)
  if not (input_buf and vim.api.nvim_buf_is_valid(input_buf)) then
    input_buf = vim.api.nvim_create_buf(false, true)

    -- 버퍼 옵션 설정
    vim.bo[input_buf].buftype = "acwrite"
    vim.bo[input_buf].filetype = "markdown"
    vim.bo[input_buf].swapfile = false

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

  -- 프롬프트를 주석으로 표시 (읽기 전용 헤더)
  local header_lines = {}
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
    vim.cmd("belowright " .. win_height .. "split")
    input_win = vim.api.nvim_get_current_win()
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
        open_input_buffer(llm_response, output_cb)
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
    end,
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param meta { tools: CodeCompanion.Tools }
    on_exit = function(self, meta)
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.HumanTool
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local user_input = vim.iter(stdout):flatten():join("\n")
      return chat:add_tool_output(self, user_input)
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

