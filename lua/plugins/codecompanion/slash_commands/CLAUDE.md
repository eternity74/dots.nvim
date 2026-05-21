# Handoff Slash Command 분석

## 전체 흐름

1. **`/handoff` 실행** → `SlashCommand:execute()`
2. **프롬프트 준비**: 핸드오프 문서 작성을 요청하는 시스템 프롬프트 + 사용자 인자
3. **콜백 등록**: `on_ready` + `on_completed`에 콜백 등록
4. **프롬프트 전송**: human_tool 경로 또는 fallback(직접 submit)
5. **콜백 실행 시**:
   - 마지막 assistant 메시지에서 핸드오프 콘텐츠 추출
   - `chat:clear()` 실행
   - context_items, tool_registry 복원
   - 핸드오프 콘텐츠를 system message로 주입
   - 사용자에게 확인 메시지 표시

## 주요 구성 요소

| 함수 | 역할 |
|------|------|
| `extract_human_tool_input()` | tool_calls에서 human_tool의 input 추출 |
| `get_last_assistant_message()` | 메시지 역순 탐색으로 assistant 응답 찾기 |
| `get_handoff_args()` | `/handoff` 뒤의 인자 파싱 |
| `submit_through_human_tool()` | human_tool input 버퍼를 통해 프롬프트 전송 |

## 잠재적 문제점

1. **콜백 타이밍**: `on_ready`와 `on_completed` 둘 다에 같은 콜백을 등록하는데, `on_ready`는 LLM이 응답을 완료하기 전에 호출될 수 있어서 `handoff_content`가 아직 없을 수 있음 → 하지만 `handled` 플래그로 중복 방지는 됨

2. **`get_last_assistant_message()` 로직**: 프롬프트 자체에 "파일 저장하지 말고 마크다운으로 반환"하라고 했는데, LLM이 human_tool을 통해 응답하면 `msg.content`가 비어있고 `tool_calls`에만 내용이 있을 수 있음. 이 경우 `extract_human_tool_input()`으로 추출하려 하지만, tool call 구조가 예상과 다를 수 있음

3. **human_tool 경로 조건**: `submit_through_human_tool()`이 성공하려면 이미 human_tool이 활성화되어 있어야 함 (`pending_cb` 존재 + `active_chat` 일치). 하지만 `/handoff`는 사용자가 직접 입력하는 것이므로, human_tool이 대기 중일 때만 이 경로가 작동함

4. **fallback 경로의 문제**: `chat:add_buf_message()` + `chat:submit()` 시, 이 메시지가 LLM에게 "tool response"가 아닌 일반 user message로 전달됨. Human tool을 사용하는 에이전트에게는 이것이 기대하지 않은 입력일 수 있음

## 디버깅 참고

- 로그 확인: `:CodeCompanionLog` 또는 log 파일에서 `[handoff]` 프리픽스 검색
- `on_ready` vs `on_completed` 콜백 중 어느 것이 실제 트리거되는지 확인 필요
- `get_last_assistant_message()`가 반환하는 값이 실제 핸드오프 문서인지 확인 필요
