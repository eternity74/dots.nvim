# human_tool

LLM과 사용자 간의 양방향 대화 브릿지 역할을 하는 CodeCompanion 커스텀 도구입니다.
LLM이 매 응답을 이 도구를 통해 사용자에게 전달하고, 사용자의 입력을 다시 LLM으로 넘깁니다.

## 파일 구조

```
human_tool/
├── init.lua     — 도구 정의 (cmds, schema, system_prompt, handlers, output)
├── window.lua   — 입력 창 상태 관리 (open / close / ensure / find)
├── context.lua  — 컨텍스트 파싱 · 동기화 · 렌더링
├── render.lua   — 헤더 · 뷰포트 · 사용자 입력 렌더링 + Copilot 통계
└── input.lua    — 입력 버퍼 생성 및 submit 흐름
```

## 모듈별 역할

### `init.lua`
- 도구의 진입점. `M` 테이블을 반환하며 CodeCompanion 도구 인터페이스를 구현합니다.
- `cmds`: LLM 호출 시 실행 — LLM 응답을 채팅 버퍼에 추가하고 입력 창을 엽니다.
- `handlers.setup`: 채팅 창의 `BufWinLeave` / `BufWinEnter` 자동 명령으로 입력 창 생명주기를 관리합니다.
- `handlers.on_exit`: 도구 종료 시 입력 창을 강제로 닫고 augroup을 정리합니다.
- `output.success`: 사용자 입력을 채팅 메시지로 추가하고 LLM에게 도구 결과로 반환합니다.

### `window.lua`
- **상태**: `input_win` (현재 입력 창 ID), `suppress_next_chat_leave_close` (submit 중 창 닫힘 방지 플래그)
- 주요 함수: `open_under_chat`, `close`, `ensure`, `find_chat_win`
- 채팅 창 바로 아래에 `belowright split`으로 입력 창을 생성합니다.

### `context.lua`
- **역할**: Treesitter로 입력 버퍼에서 `> Context:` 항목을 파싱하고, 채팅 상태(`context_items`, `messages`, `tool_registry`)와 동기화합니다.
- `get_from_buffer(bufnr)` → 버퍼의 컨텍스트 항목 목록 반환
- `sync(chat, bufnr)` → 삭제된 항목을 채팅 상태에서 제거
- `render(chat)` → 현재 컨텍스트를 마크다운 블록 라인으로 변환

### `render.lua`
- **역할**: 입력 창 상단 헤더 생성 및 에디터 컨텍스트 렌더링
- `build_header_lines()` → Copilot 프리미엄 사용량 + 안내 문구 반환
- `render_user_input(chat, user_input)` → `@viewport` 등 에디터 컨텍스트 참조 확장

### `input.lua`
- **상태**: `input_buf` (재사용 스크래치 버퍼), `pending_output_cb` (제출 대기 콜백)
- `open(chat, prompt, output_cb)`: 버퍼 초기화 → 헤더/컨텍스트 렌더링 → 창 열기 → `Ctrl-S` 키맵 등록
- submit 시 헤더와 `> Context:` 블록을 제외한 텍스트를 수집하여 `output_cb`로 반환합니다.

## 전체 흐름

```
LLM → human_tool(cmds) 호출
  → input_mod.open() → 입력 창 열림
    → 사용자가 Ctrl-S 입력
      → context_mod.sync() → output_cb({ status="success", data=user_input })
        → output.success() → chat:add_tool_output()
          → LLM에게 전달
```

## 키맵

| 모드 | 키 | 동작 |
|------|----|------|
| Normal / Insert / Visual | `Ctrl-S` | 입력 제출 |

## 의존성

| 모듈 | 외부 의존성 |
|------|-------------|
| `render.lua` | `plenary.curl`, `copilot.token`, `codecompanion.utils.buffers`, `codecompanion.interactions.chat.helpers` |
| `context.lua` | `vim.treesitter` (`cc_context` 쿼리) |
| `input.lua` | `window`, `context`, `render` |
| `init.lua` | `input`, `window`, `render` |
