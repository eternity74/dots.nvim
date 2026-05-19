# CodeCompanion `human_tool` 저장/복원 동작 분석 문서 (소스 기반)

작성일: 2026-05-19  
대상 경로: `/home/wanchang.ryu/.config/nvim/lua/plugins/codecompanion`

---

## 1) 결론 요약

질문: "복원을 했을 때 실제 CodeCompanion에서 tool call이 호출되고 있는가?"

### 결론
- 현재 코드 기준으로 history 복원 시 `human_tool`은 **기본 렌더링 변환 + pending call replay**가 함께 동작함.
- `history_preprocess.lua`에서 메시지를 **렌더링용 일반 메시지로 변환**함.
- 동시에, **응답이 없는 pending `human_tool` call만 실제로 재실행**함.
- 즉, 복원은 snapshot 성격을 유지하면서 pending human_tool 상태는 런타임으로 되살리는 형태임.

---

## 2) 소스에서 확인한 핵심 근거

### A. `human_tool` 실행 경로
파일: `tools/human_tool/init.lua`

- tool 호출 시:
  - `cmds[1]`에서 LLM 응답(`args.input`)을 버퍼에 LLM 메시지로 추가
  - `input_mod.open(...)`으로 사용자 입력 섹션을 채팅 버퍼에 열어 입력 대기
- 사용자 입력 제출 시:
  - `output.success`에서 사용자 입력을 가공 후
  - `chat:add_tool_output(self, output_message, display_text)`로 **tool output**을 대화에 추가

즉, 실시간 대화에서는 `human_tool`이 정상적인 tool-call 흐름으로 동작.

### B. 복원(history) 시 전처리 동작
파일: `tools/human_tool/history_preprocess.lua`

주요 동작:
- `human_tool` tool_call 메시지 → plain `llm` 메시지로 변환
- `human_tool` tool 응답 → plain `user` 메시지로 변환
- orphan tool_call은 dummy tool response 삽입
- 저장 JSON 자체는 수정하지 않고, 복원 렌더링 단계에서만 변환
- **추가 구현:** pending `human_tool` call 추출 후 `create_chat` 완료 시점에 `chat.tools:execute(...)`로 replay

핵심:
- 복원 시 과거 기록은 표시용으로 변환하면서,
- **미응답(pending) `human_tool` 호출은 실제 재실행**하여 입력 대기 상태를 런타임에서 복구함.

### C. 초기 리스크 및 현재 상태
- `history_preprocess.lua`에는 `M.setup()`이 있고,
- 현재는 `tools/human_tool/init.lua`에서 `history_preprocess.setup()`을 호출하도록 **연결 완료**.

의미:
- 복원 전처리 로직이 실제 런타임에서 활성화될 경로가 확보됨.

---

## 3) 설정에서 확인한 사항

파일: `extensions_config.lua`

- history 관련 keymap 존재:
  - `keymap = "gh"`
  - `save_chat_keymap = "sc"`
- 자동 저장 설정은 현재 `auto_save = true`로 **수정 완료**.

영향:
- 저장/복원 keymap 방향성은 이미 일부 잡혀 있음.
- 자동 저장 옵션명 오타 가능성(`auto_sve`)을 제거해 설정 적용 가능성을 높임.

---

## 4) “완벽 복원” 가능성 평가

### 현재 구현 기준
- **화면/대화 맥락 복원:** 가능
- **pending `human_tool` 실행 상태 복원:** 가능 (replay 적용)
- **이미 완료된 tool call 재실행:** 수행하지 않음
- **모든 tool side effect까지 동일 재현:** 불가 (의도적으로 제한)

따라서 현재의 “완벽 복원”은:
1. 텍스트/역할 순서 복원
2. pending `human_tool` 런타임 재개
3. 전체 tool side effect 동일성은 범위 밖

---

## 5) 진행 계획 (구체)

1. **복원 전처리 활성화 여부 확정**
   - `history_preprocess.setup()` 호출 지점 추가/확인
   - 검증: history에서 복원 시 human_tool call이 plain llm/user로 변환되는지

2. **저장 설정 정확성 점검**
   - `auto_sve` → 실제 옵션명 검증 후 수정
   - 검증: 채팅 후 파일 자동 저장 여부

3. **복원 정책 명시**
   - 기본: snapshot 복원(현재 방향)
   - 선택: replay 모드(향후 확장)
   - 검증: 문서/코드 주석으로 정책 일치

4. **관측성(로그) 추가**
   - 복원 시점에 "재실행 없음/변환만 수행" 로그 출력
   - 검증: 로그만 보고 복원 모드 판별 가능

5. **검증 시나리오 3개 고정**
   - 시나리오 A: human_tool 1턴
   - 시나리오 B: multi-turn + pending
   - 시나리오 C: 일반 tool + human_tool 혼합

---

## 6) 바로 작업 가능한 액션 아이템

- [x] `history_preprocess.setup()` 초기화 연결
- [x] `extensions_config.lua`의 `auto_sve` 옵션명 검증/수정 (`auto_save`로 반영)
- [x] history 복원 시 pending `human_tool` call replay 연결
- [ ] 복원 모드 동작 로그 1~2줄 추가
- [ ] 테스트 절차 문서화

---

## 7) 최종 답변 (질문에 대한 직접 응답)

- "복원 시 실제 tool call이 호출되냐?" → **pending `human_tool` call에 한해 호출되도록 반영됨.**
- "완벽 복원이 가능하냐?" → **대화 맥락 + pending human_tool 재개 수준으로는 가능하지만, 완료된 모든 tool side effect까지 동일 재현하는 의미의 완전 복원은 아님.**
---

## 8) 이번에 실제 적용된 패치 요약

1. `tools/human_tool/init.lua`
   - `history_preprocess` require 추가
   - `history_preprocess.setup()` 호출 추가
   - 누락 방지를 위해 `context_mod` require 유지/복구

2. `extensions_config.lua`
   - `auto_sve = true` → `auto_save = true` 수정

3. `tools/human_tool/history_preprocess.lua`
   - `collect_pending_human_tool_calls(messages)` 추가
   - history `create_chat` 패치에서 pending `human_tool` call 수집
   - chat 생성 직후 `chat.tools:execute(chat, pending_calls)`로 replay 수행

### 권장 검증 순서
1. Neovim 재시작
2. CodeCompanion chat에서 `human_tool` 호출 직후 응답하지 않고 대기 상태 만들기
3. `sc`로 저장
4. `gh`로 history 진입 후 방금 대화 복원
5. 복원 직후 Human Tool 입력 섹션이 다시 열리는지 확인(실행 replay)
6. 로그에서 replay 메시지(`Replaying ... pending human_tool call(s)`) 확인
