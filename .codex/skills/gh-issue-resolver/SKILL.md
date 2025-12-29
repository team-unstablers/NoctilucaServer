---
name: gh-issue-resolver
description: GitHub CLI(gh)로 이슈 번호를 받아 현재 레포에서 이슈를 분석하고 해결 계획을 수립한 뒤 사용자 승인 후 작업, 브랜치 생성, 단계별 커밋, PR 생성까지 수행하는 스킬. "#123 해결해줘", "이슈 456 처리해줘", "gh issues에서 나온 이슈 해결" 같은 요청에 사용.
---

# gh-issue-resolver

## 개요
현재 레포의 GitHub 이슈를 gh CLI로 조회하고, 해결 계획을 제시해 승인 받은 뒤 구현/커밋/PR 생성까지 일관된 절차로 수행하라.

## 워크플로

### 1) 입력 확인 및 이슈 조회
- 사용자가 준 이슈 번호를 추출하라. (예: "#123 해결해줘" -> 123)
- 현재 레포 기준으로 이슈를 조회하라.
- gh 인증 상태가 불확실하면 먼저 확인하거나 사용자에게 안내하라.

예시 명령:
```bash
# 이슈 기본 정보

gh issue view 123 --json number,title,state,labels,assignees,author,body,url
```

### 2) 이슈 요약 및 범위 파악
- 이슈의 핵심 요구사항, 수락 기준, 관련 파일/모듈을 요약하라.
- 불명확한 부분은 질문하라. (추측 금지)
- 모노레포이므로 주 변경 대상 하위 디렉터리를 가늠하라. (예: `SiriusKit/`, `NoctilucaServer/`)

### 3) 해결 계획 수립 + 사용자 승인
- 해결 계획을 명확히 제시하라. (작업 단위, 영향 범위, 리스크 포함)
- `update_plan` 도구로 한국어 계획을 작성한 뒤, 반드시 다음 문장으로 승인 요청하라.

반드시 물어볼 문장:
"이대로 진행할까요?"

### 4) 승인 후 브랜치 생성
- 승인 받은 뒤에만 작업을 시작하라.
- 브랜치 이름 규칙: `codex-cli/gh-issue-<issue_id>`

예시 명령:
```bash

git checkout -b codex-cli/gh-issue-123
```

### 5) 구현 및 단계별 커밋
- 변경을 진행하되, 큰 변경 단위마다 커밋하라.
- 커밋 메시지는 레포 컨벤션을 따르라: `[scope]: [subject]` (한국어 권장)
- AGENTS.md의 Explicit Plan Mode 트리거(3개 이상 파일 구조 변경 또는 Core Logic 변경)를 만족하면 그 규칙을 우선하라.

커밋 예시:
```bash

git add -A

git commit -m "transport/quic: 재시도 로직 보완"
```

### 6) PR 생성 (한국어)
- 작업 완료 후 gh CLI로 PR을 생성하라.
- 제목 형식: `$subrepo/$scope: $brief`
  - `subrepo`: 주 변경이 발생한 최상위 디렉터리 (예: `SiriusKit`, `NoctilucaServer`, `NoctilucaClient`)
  - `scope`: 커밋 스코프를 요약한 단어
  - `brief`: 간결한 변경 요약
- 본문은 한국어로 상세히 작성하고, 개요에 반드시 `- resolves #<issue_id>`를 포함하라.
- 사용자 요청이 없으면 이슈를 직접 close 하지 말고, PR만 생성하라.

PR 본문 예시 템플릿:
```
개요
- resolves #123

변경사항
- ...
- ...

테스트
- (실행한 테스트 또는 "미실행" 명시)

리스크/메모
- ... (해당 시)
```

예시 명령:
```bash

gh pr create --title "NoctilucaServer/transport: QUIC 재시도 보완" --body "# 개요
- resolves #123

# 변경사항
- ...
"
```

## 체크리스트
- 계획 승인 없이 코드 수정 금지
- 큰 변경 단위마다 커밋
- PR 제목/본문 규칙 준수 (`- resolves #<issue_id>` 포함)
- 한국어 커뮤니케이션 유지
