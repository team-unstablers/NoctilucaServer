---
name: todo-sync
description: 코드베이스 내의 TODO, FIXME 주석을 스캔하여 GitHub Issues와 동기화합니다. 새로운 항목은 이슈로 등록하고, 사라진 항목은 해결 여부를 판단하여 이슈를 닫습니다.
metadata:
  version: "1.0"
  author: User
allowed-tools: rg grep gh git
---

# TODO 리스트 동기화 (TODO Sync)

이 스킬은 프로젝트 내의 주석(`TODO`, `FIXME`, `XXX`)을 분석하여 GitHub Issue 트래커와 동기화하는 작업을 수행합니다.

## 전제 조건
- 실행 환경에 `gh` (GitHub CLI)가 설치되어 있고 인증되어 있어야 합니다.

## 작업 절차

### 1. TODO 스캔 및 분석
먼저 코드베이스 전체에서 다음 정규식 패턴에 해당하는 주석이나, `#warning()` 매크로, 로깅 코드등을 재귀적으로 검색하십시오:
`/(TODO|FIXME|XXX)/i`

- 검색에는 `rg -n`을 우선 사용하고, 없으면 `grep -Rni`를 사용하십시오.

검색된 각 항목에 대해 다음 정보를 분석해야 합니다 (line number와 file path 포함):
- **Path**: 파일 경로
- **Line**: 라인 번호
- **Context**: 주석의 내용과 주변 코드를 바탕으로 한 작업의 맥락
- **Comment**: TODO/FIXME/XXX 주석의 원문 (없으면 "주석 원문 없음")

**⚠️ 무시 조건 (Ignore Rules):**
검색 결과에서 프로젝트 소스 코드와 직접 관련이 없는 디렉토리의 내용은 반드시 무시하도록 하십시오.
- **필수 제외:** `.git`, `dependencies`
- **일반적 제외 권장:** `build`, `dist` 등 시스템이나 빌드 아티팩트 폴더.

### 2. 이슈 작성 규칙 (Strict Rule)
- 발견된 TODO 내용을 바탕으로 이슈 제목(`issue_name`)과 상세 내용(`description`)을 구성하십시오.
- **필수:** 이슈 제목과 본문은 반드시 **한국어**로 작성해야 합니다.

#### 2-1. 이슈 제목 포맷 (필수)
```
${subrepo}/${scope}: ${brief} (${filename}:${lineno}${extra_refs})
```

- `subrepo`: 최상위 디렉터리를 아래와 같은 규칙으로 축약
  - `NoctilucaClient` -> `client`
  - `NoctilucaServer` -> `server`
  - `SiriusKit` -> `siriuskit`
  - `NoctilucaPluginKit` -> `pluginkit`
  - `libbcrypt` -> `libbcrypt`
- `scope`: 경로 기반으로 짧고 명확하게
  - 매번 일관되지 않아도 좋으니 디렉토리 구조를 기반으로 최대한 간단하고 명확한 스코프를 선택할 것
  - 예: `NoctilucaClient/auth/pam/PAMAuthenticator.swift` -> `client/auth/pam`
  - 예: `NoctilucaServer/feature/projection/.../ProjectionSession.swift` -> `server/projection`
  - 예: `SiriusKit/SiriusKit/msgdef/v1/channels/hidio/HIDEvent.swift` -> `siriuskit/msgdef/hidio`
  - 예: `SiriusKit/SiriusKit/transport/server/quic/ServerRoleQUICRootTransport.swift` -> `siriuskit/transport/quic`
- `brief`: TODO 주석과 컨텍스트를 요약한 짧은 한 문장
- `filename`: **파일명만** 표기 (경로 제외)
- `extra_refs`: 같은 이슈로 병합된 refinfo가 2개 이상일 때만 `" [외 N건]"`을 붙임

#### 2-2. 이슈 본문 포맷 (필수)
```
# 개요

- $(Codex가 파악한 이슈에 대한 대략적인 개요)

# 제안하는 해결 방안

- $(Codex가 제안하는 해결 방안)

# 기타 사항 (필요한 경우)

- $(기타 알리고자 하는 사항)

# CONTEXT REFERENCES
<!-- Codex 참고용 컨텍스트 정보 -->
<agent-context>
<refinfo filename="${filename}" lineno="${lineno}">
${context}
</refinfo>
<!-- refinfo는 여러개일 수 있다, 중복된 내용을 가리키는 레퍼런스는 한 이슈에 합쳐서 적는다 -->
</agent-context>
```

- `context`: TODO 라인 주변의 코드 스니펫(짧게, 3~7줄)
- 동일하거나 중복된 내용(같은 brief + scope로 판단 가능)은 **한 이슈로 병합**하고 `refinfo`를 여러 개 추가

### 3. 사용자 확인 (Human in the loop)
동기화를 시작하기 전에, 발견된 TODO 목록을 마크다운 리스트 형태로 출력하십시오.
- 출력 예시: `[${subrepo}/${scope}: ${brief} (${filename}:${lineno})] - 요약`

그 후, **"이 TODO들을 GitHub과 동기화할까요?"** 라고 묻고 사용자의 승인을 기다리십시오. 승인되지 않으면 작업을 즉시 종료하십시오.

### 4. 동기화 로직 (Sync Logic)

사용자가 승인하면 다음 로직을 순차적으로 수행하십시오.

#### A. 기존 이슈 가져오기
`gh issue list` 명령어를 사용하여 다음 조건에 맞는 이슈 목록을 가져오십시오:
- Label: `codex:todosync`
- State: `open`

각 이슈 본문에서 `<refinfo filename="..." lineno="...">`를 추출해 레퍼런스 키로 사용하십시오.

#### B. 해결된 이슈 처리 (Close Resolved Issues)
가져온 GitHub 이슈 목록에는 있지만, 현재 코드베이스의 TODO 검색 결과에는 없는 항목들을 확인하십시오.
- 해당 이슈가 실제로 해결되었는지 코드를 통해 추론하십시오.
- 해결된 것으로 판단되면:
  1. `gh issue comment`를 사용하여 "이 문제는 해결된 것으로 보입니다: [관련 코드/근거]" 코멘트를 남기십시오.
  2. `gh issue close`를 사용하여 이슈를 닫으십시오.

#### C. 새로운 이슈 등록 (Create New Issues)
코드베이스에서 발견된 TODO 중, GitHub 이슈 목록에 없는 항목들을 처리하십시오.
- `gh issue create`를 사용하여 이슈를 생성하십시오.
- **Label**: 반드시 `codex:todosync` 와 `component:$subrepo` (`component:client`, `component:server`, `component:siriuskit` ...)라벨을 붙여야 합니다.
- 이슈 본문은 반드시 **2-2 포맷**을 따르십시오.

## 예외 처리
- `gh` 명령어가 실패하거나 권한 오류가 발생하면 즉시 작업을 중단하고 사용자에게 알리십시오.
