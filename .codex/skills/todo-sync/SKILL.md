---
name: todo-sync
description: 코드베이스 내의 TODO, FIXME 주석을 스캔하여 GitHub Issues와 동기화합니다. 새로운 항목은 이슈로 등록하고, 사라진 항목은 해결 여부를 판단하여 이슈를 닫습니다.
metadata:
  version: "1.0"
  author: User
allowed-tools: grep gh git
---

# TODO 리스트 동기화 (TODO Sync)

이 스킬은 프로젝트 내의 주석(`TODO`, `FIXME`, `XXX`)을 분석하여 GitHub Issue 트래커와 동기화하는 작업을 수행합니다.

## 전제 조건
- 실행 환경에 `gh` (GitHub CLI)가 설치되어 있고 인증되어 있어야 합니다.

## 작업 절차

### 1. TODO 스캔 및 분석
먼저 코드베이스 전체에서 다음 정규식 패턴에 해당하는 주석을 재귀적으로 검색하십시오:
`/(TODO|FIXME|XXX)/i`

- 검색에는 당신이 가지고 있는 file search tool이나, `grep -Ri`를 사용하십시오.

검색된 각 항목에 대해 다음 정보를 분석해야 합니다 (line number와 file path 포함):
- **Path**: 파일 경로
- **Line**: 라인 번호
- **Context**: 주석의 내용과 주변 코드를 바탕으로 한 작업의 맥락

**⚠️ 무시 조건 (Ignore Rules):**
검색 결과에서 프로젝트 소스 코드와 직접 관련이 없는 디렉토리의 내용은 반드시 무시하도록 하십시오.
- **필수 제외:** `.git`, `dependencies`
- **일반적 제외 권장:** `build`, `dist` 등 시스템이나 빌드 아티팩트 폴더.

### 2. 이슈 작성 규칙 (Strict Rule)
- 발견된 TODO 내용을 바탕으로 이슈 제목(`issue_name`)과 상세 내용(`description`)을 구성하십시오.
- **필수:** 이슈 제목과 본문은 반드시 **한국어**로 작성해야 합니다.

### 3. 사용자 확인 (Human in the loop)
동기화를 시작하기 전에, 발견된 TODO 목록을 마크다운 표 또는 리스트 형태로 사용자에게 깔끔하게(Pretty Print) 출력하십시오.
- 출력 예시: `[이슈 제목] (파일경로:라인번호) - 설명`

그 후, **"이 TODO들을 GitHub과 동기화할까요?"** 라고 묻고 사용자의 승인을 기다리십시오. 승인되지 않으면 작업을 즉시 종료하십시오.

### 4. 동기화 로직 (Sync Logic)

사용자가 승인하면 다음 로직을 순차적으로 수행하십시오.

#### A. 기존 이슈 가져오기
`gh issues list` 명령어를 사용하여 다음 조건에 맞는 이슈 목록을 가져오십시오:
- Label: `codex:todosync`
- State: `open`

#### B. 해결된 이슈 처리 (Close Resolved Issues)
가져온 GitHub 이슈 목록에는 있지만, 현재 코드베이스의 TODO 검색 결과에는 없는 항목들을 확인하십시오.
- 해당 이슈가 실제로 해결되었는지 코드를 통해 추론하십시오.
- 해결된 것으로 판단되면:
  1. `gh issue comment`를 사용하여 "이 문제는 해결된 것으로 보입니다: [관련 코드/근거]" 코멘트를 남기십시오.
  2. `gh issue close`를 사용하여 이슈를 닫으십시오.

#### C. 새로운 이슈 등록 (Create New Issues)
코드베이스에서 발견된 TODO 중, GitHub 이슈 목록에 없는 항목들을 처리하십시오.
- `gh issue create`를 사용하여 이슈를 생성하십시오.
- **Label**: 반드시 `codex:todosync` 라벨을 붙여야 합니다.
- 이슈 본문에 원본 파일의 경로와 라인 번호를 명시하십시오.

## 예외 처리
- `gh` 명령어가 실패하거나 권한 오류가 발생하면 즉시 작업을 중단하고 사용자에게 알리십시오.
