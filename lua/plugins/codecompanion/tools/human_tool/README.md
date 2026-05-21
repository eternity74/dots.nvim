# human_tool

LLM과 사용자 간의 양방향 대화 브릿지 역할을 하는 CodeCompanion 커스텀 도구입니다.
LLM이 매 응답을 이 도구를 통해 사용자에게 전달하고, 사용자의 입력을 다시 LLM으로 넘깁니다.

## 현재 동작 방식 요약

- 별도 입력 창을 띄우지 않고 **채팅 버퍼 하단에 인라인 입력 섹션**을 추가합니다.
- LLM 메시지는 `human_tool` 호출 시 즉시 채팅 버퍼에 표시됩니다.
- 사용자가 인라인 섹션에 입력한 텍스트를 제출하면 tool output으로 LLM에 전달됩니다.

## 파일 구조

```
human_tool/
├── init.lua     — 도구 정의 (cmds, schema, system_prompt, output)
├── input.lua    — 채팅 버퍼 인라인 입력 섹션 생성/제출
├── context.lua  — 컨텍스트 파싱 · 동기화 · 렌더링
├── render.lua   — 상단 상태 헤더(프리미엄/모델) 및 사용자 입력 렌더링
└── window.lua   — chat window 탐색 등 창 유틸리티
```

## 모듈별 역할

### `init.lua`
- 도구 진입점.
- `cmds`에서 LLM 응답 텍스트를 채팅 버퍼에 추가한 뒤 `input.open()`을 호출합니다.
- 필요 시 모델 자동 전환(`maybe_auto_switch_model`)을 수행합니다.
- `output.success`에서 사용자 입력을 채팅 버퍼에 표시하고 tool output으로 반환합니다.

### `input.lua`
- 채팅 버퍼 끝에 아래 순서로 섹션을 삽입합니다.
  1) `## 💬 Human Tool Input`
  2) `> Context:` 블록
  3) 프리미엄/LLM 상태 라인
  4) 사용자 입력 시작 빈 줄
- `submit()` 시 헤더/컨텍스트 영역을 제외한 사용자 입력만 수집해 callback으로 전달합니다.

### `context.lua`
- `> Context:` 항목을 파싱하고 현재 chat 상태와 동기화합니다.
- 삭제된 컨텍스트는 `messages`, `context_items`, `tool_registry`에서 정리합니다.

### `render.lua`
- Copilot premium 사용량/현재 모델 라인을 생성합니다.
- 사용자 입력 본문에 포함된 참조를 `chat:replace_user_inputs`로 확장합니다.

### `window.lua`
- 채팅 버퍼가 열린 창 탐색 등 유틸리티를 제공합니다.
- 현재 인라인 입력 방식에서는 `find_chat_win` 중심으로 사용됩니다.

## 전체 흐름

```
LLM → human_tool(cmds) 호출
  → chat buffer에 LLM 응답 출력
  → input.open()으로 인라인 입력 섹션 생성
    → 사용자 입력 제출
      → context.sync()
      → output.success()
      → chat:add_tool_output()로 LLM에 전달
```

## 참고

- 과거 문서의 "별도 split 입력창 / Ctrl-S 제출" 설명은 현재 구현과 다릅니다.
- 현재 구현 기준의 제출 트리거/입력 UX는 `input.lua` 실제 코드가 기준입니다.
