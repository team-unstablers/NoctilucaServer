# Noctiluca Server 0.9.10 — TODO

> 이 문서는 0.9.10 릴리즈를 위한 작업 목록을 수집/정리하는 살아있는 문서입니다.
> 사장님의 브레인 덤프를 유실 없이 받아두고, 가능한 것부터 카테고리로 분류합니다.
>
> - **작성 시작**: 2026-04-23
> - **담당**: 치즈군
> - **상태**: 수집 중 (collecting)

---

## 🎯 릴리즈 테마 (Discord 공지 기준)

- **메인 테마**: 안정성 향상 (Stability) — Swift 6 이행 + data race 근절
- **코덱 정책 변화**: 타일링 이미지 코덱 (MJPG / ZRLE / WebP) **제거**, 대체로 VP8 도입 (대역폭 효율)
- **신규 기능**: VP8 코덱, 디스플레이 레이아웃/해상도 변경, 가상 디스플레이, iPad에서 보조 디스플레이 별도 창 분리 (실험적)
- **Qt 클라이언트**: 사용성 개선

---

## ✅ 이미 완료된 것 (Done)

- [x] **Swift 6 이행** (Noctiluca + SiriusKit)
- [x] **MsQuic Unbuffered 설정**
- [x] **서버 사이드 HIDIO 데이터 레이스 해결** (MsQuic Unbuffered 전환 덕분으로 추정)
- [x] **VP8 인코더** (서버, libvpx 기반)
- [x] **VP8 디코더** (NoctilucaClient)
- [x] **VP8 디코더** (NoctilucaClientQt)
- [x] **디스플레이 레이아웃 설정 가능** (서버)
- [x] **디스플레이 해상도 설정 가능** (서버)
- [x] **메인 디스플레이 설정 가능** (서버)

---

## 🧠 Raw Brain Dump (분류 전)

> 떠오르는 대로 여기에 찍어둡니다. 문법/순서/중복 신경 쓰지 않음.

### 2026-04-23 — Turn 1 (Discord 공지 + chain of thought)

**Discord 공지 요약**:
- Swift 6 이행 중 (業報 드립)
- 0.9.10 포커스: 안정성 (data race 근절)
- Qt 클라이언트 사용성 개선
- 타일링 이미지 코덱 (MJPG/ZRLE/WebP) 제거 예정 → VP8로 대체
- VP8 추가 (특히 macOS on VM — UTM 등에 유용)
- 디스플레이 레이아웃/해상도 변경 가능
- 가상 디스플레이 생성 가능 (세션 종료 시 자동 정리)
- iPad에서 개별 디스플레이 스폰/디태치 제한 실험적으로 해제

**Chain of thought 덤프 (원문)**:
- Swift 6 이행? 했어.
- MsQuic Unbuffered 설정? 했어.
  - 이로 인한 서버 사이드 HIDIO쪽 데이터 레이스? 해결한 것 같아.
- VP8 인코더? 했어.
- VP8 디코더? 했어.
- VP8 디코더 (NoctilucaClientQt)? 했어.
- 디스플레이 레이아웃? 설정 가능해.
- 디스플레이 해상도? 설정 가능해.
- 메인 디스플레이로 설정? 가능해.
- 가상 디스플레이? 가능하긴 하지만 가드 로직이 완전하지 않아.
- 가상 디스플레이의 UI가 완전하지 않아 (macOS)
- NoctilucaClientQt: 디스플레이 레이아웃 / 해상도 등 설정이 불가능해, 왜냐하면 UI가 부재해.
- NoctilucaClientQt: 가상 디스플레이 생성이 불가능해. UI가 완전하지 않아.
- 맞아, Swift 6 이행하면서 CJK 플러그인을 비활성화 했는데, 다시 활성화 해야만 해.
- NoctilucaClientQt: 코덱 폴백 로직이 너무 부실해.
- NoctilucaClient / NoctilucaClientQt: 디스플레이를 프로젝션 중 해당 디스플레이 연결이 끊기면 다른 디스플레이로 자동 전환해야 하는데 그렇지 않고 있어.
- 클립보드를 통한 파일 전송 채널에 패스 트래버설 등의 다수 취약점을 Claude로부터 보고받았어.

### 2026-04-23 — Turn 2 (미정 해소 + 신규)

**가드 로직 (가상 디스플레이)**:
- 오류 가드 로직 없음
- 최소/최대 해상도 제한 없음 (현 macOS에서는 3840x2160까지가 한계)
- 1x1, 262144x2 같은 이상한 해상도도 생성 가능 (막아야 함)

**iPad 보조 디스플레이 분리**:
- iPad Pro에서 테스트가 안 됨 (남자친구 아이패드 빌려야 함)

**클립보드 파일 전송 취약점**:
- 0.9.10에 같이 shipping 할 예정
- see `docs/clipboard-transfer-security-report.md`

**신규**:
- App Store 상점 페이지의 기본 언어를 영문으로 — 현재 비-미국 사용자에게 한국어 설명문이 표시됨

### 2026-04-23 — Turn 3 (보고받은 버그)

- NoctilucaServer: 체험판 → 정식 라이선스로 전환할 때 struggle이 있음

---

## 📋 분류된 작업

### 🆕 기능 (Features)

- [x] VP8 인코더 (서버)
- [x] VP8 디코더 (Client / ClientQt)
- [x] 디스플레이 레이아웃 / 해상도 / 메인 디스플레이 설정 (서버)
- [ ] **가상 디스플레이 — 가드 로직 완성** (현재 불완전)
  - [ ] 오류 가드 로직 추가 (실패 케이스 처리)
  - [ ] 최소/최대 해상도 제한 (macOS 현재 한계: 3840×2160)
  - [ ] 이상 해상도 거부 (예: 1×1, 262144×2 등 생성 가능 → 차단)
- [ ] **가상 디스플레이 UI 완성 (macOS)** — Noctiluca Server 앱
- [ ] **iPad: 보조 디스플레이 별도 창 분리** (실험적, 공지에 포함)
  - [ ] **iPad Pro 실기 테스트** — 남자친구 iPad 빌려서 검증 필요

### 🐛 버그 픽스 (Bug Fixes)

- [x] 서버 사이드 HIDIO 데이터 레이스 (MsQuic Unbuffered)
- [ ] **프로젝션 중 디스플레이 연결 끊김 시 자동 전환** (Client / ClientQt 둘 다) — 현재 미동작
- [ ] **CJK 플러그인 재활성화** — Swift 6 이행 중 비활성화됨, 복구 필요
- [ ] **NoctilucaServer: 체험판 → 정식 라이선스 전환 시 struggle** (보고받음)

### 🔒 보안 (Security) — 0.9.10에 Shipping

> **근거 문서**: [`docs/clipboard-transfer-security-report.md`](./clipboard-transfer-security-report.md) (2026-04-10 감사 리포트)
> **결정**: 0.9.10에 함께 shipping (핫픽스 분리 X).
> **적용 범위**: Server (Swift) / Client (Swift) / ClientQt (C++) 공통 — 세 타겟 모두에 반영 필요.

#### 🔴 CRITICAL (즉시)

- [ ] **[2.1] `FileTransferSnapshot.validatePath` Path Traversal 수정**
  - 현: `String.hasPrefix` 기반, 정규화 없음 → `../` 로 호스트 임의 파일 탈취 가능
  - 조치: `URL.standardizedFileURL.resolvingSymlinksInPath()` / `realpath(3)` 기반 정규화 포함관계 판정으로 전면 재작성
  - Qt: `std::filesystem::weakly_canonical` 로 심볼릭 링크까지 정규화 강화
  - 검증된 경로를 그대로 `writeFromFile` / `FileHandle`에 전달 (TOCTOU 회피)
- [ ] **[2.2] protobuf 메시지에 크기/개수 상한 도입**
  - 현: `ClipboardData.data`, `TransferDataChunk.data`, `ClipboardEvent.items` 모두 상한 없음 → 메모리/디스크 DoS
  - 조치:
    - SiriusKit 레벨 프레임 최대 길이 상수 (예: 16 MiB), `SiriusFrameStreamDecoder`에서 초과 프레임 드랍
    - `TransferChannel`에 `maxInFlightBytes` / `maxTotalBytes` 상한 추가, `totalSize` 초과 수신 시 즉시 close
    - `ClipboardEvent.items`, `ClipboardItem.representations` 개수 상한 (예: 16/16)
    - `ClipboardData.data` 본문 상한 + 초과 시 반드시 `omitted` + TransferChannel 경유 강제
    - `resolveOmittedData` 누적 버퍼 상한
- [ ] **[3.3] `FileTransferMetadata.path` 절대 경로 노출 제거 → opaque token 방식**
  - 현: `/Users/alice/Desktop/...` 같은 호스트 절대 경로가 클라이언트에 노출
  - 조치: 서버가 내부 테이블에 `token → real path` 매핑 보관, 와이어에는 `token`, `displayName`, `size`, `contentType` 만 송신
  - 부가 효과: 2.1 (Path Traversal) 도 동시에 완화

#### 🟠 HIGH (단기)

- [ ] **[3.1] `TransferDataChunk.crc32 == 0` 이면 검증 스킵 문제**
  - 조치 A: `crc32`를 required로 격상 (빈 데이터일 때만 0 허용)
  - 조치 B: CRC32가 불필요하다 판단되면 메시지에서 제거 + "QUIC이 무결성 보장" 문서화
- [ ] **[3.2] `TransferStartNotification.totalSize` 미강제**
  - 현: 불일치 시 로그만 남기고 채널 유지 → 디스크 고갈/기만 가능
  - 조치: `receivedTotalBytes > totalSize` 즉시 에러 종료, `isEOF && receivedTotalBytes != totalSize` 시 결과 파일 폐기
  - `totalSize == 0` 의 의미 ("알 수 없음" vs "0바이트") spec 명확화, 별도 상한 적용

#### 🟡 MEDIUM (단기~중기)

- [ ] **[4.1] `DirectoryEntry.name` 검증 추가**
  - `name.contains("/") || name.contains("..") || name.isEmpty` 거부
  - Qt: `std::filesystem::path(name).has_parent_path()` 검증
- [ ] **[4.2] 자동 맞구독 시 사용자 동의 UX**
  - 서버가 `syncDirection == bidirectional / remoteToLocal` 일 때 자동 `SubscribeClipboardRequest` 송신 중
  - 조치: 명시적 사용자 설정 또는 세션 수락 시 확인 UI, Qt 클라이언트도 동일 정책
  - `requestId` monotonic 카운터로 발급 (현재는 `1` 고정)
- [ ] **[4.3] `serveTransferData` 세션/토큰 기반 격리**
  - 인증된 상대방이 `lastSentSnapshot`의 임의 (item, repr) 인덱스 접근 가능
  - 조치: 세션·채널 단위로 스냅샷 격리 + opaque token 사용 (3.3과 동일 해법)
- [ ] **[4.4] `PendingFileTransfer.createPlaceholder`에 `O_NOFOLLOW` 추가**
  - `open(url.path, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)` 로 수정
  - 안전 강화: `openat(dirfd, name, O_WRONLY | O_NOFOLLOW | O_CREAT | O_EXCL)` + name sanitize
  - `metadata.name` path separator / `..` 엄격 금지
- [ ] **[4.5] Qt Windows `ClipboardFileDataObject` relative path 검증**
  - `std::filesystem::path(name).filename() == name` 확인, 아니면 drop
  - Explorer drop 총 파일 수/크기 상한 도입

#### 🟢 LOW / 방어-in-depth (중기)

- [ ] **[5.1] MIME 허용 목록 + pasteboard slot 주입 방지**
  - `application/x-...` wrap의 허용 목록 기반 매핑으로 좁힘
  - macOS 수신 측 `setWithFileTransfer`에 `allowFile` 정책 적용
- [ ] **[5.2] `GetClipboardRequest` rate limit + 스냅샷 관리**
  - 예: 500ms당 1회 제한
  - `ClipboardEvent` 송신과 동일하게 `lastSentSnapshot` 업데이트
- [ ] **[5.4] `TransferChannel` 동시 open 상한** (`AppSettings.Transfer.maxActiveTransfers`)
- [ ] **[5.5] Linux FUSE bridge mount permission 확인** (`user_only` 기본)
- [ ] **[6.5] `ChannelAccepts` 단계에서 정책 게이트** — `TransferSettings.allow*` / `ClipboardSettings.allowFile` 를 `createIfAccepts`에서 먼저 체크

#### 📝 문서화

- [ ] **AGENTS.md / SPEC에 불변식 명문화**
  - `TransferDataChunk.crc32` 의미
  - `totalSize` 의미 및 "알 수 없음" 케이스
  - 최대 크기, 동시 채널 수 상한
  - 모든 타겟(Swift/Qt)이 동일하게 강제할 수 있도록

#### ✅ 테스트 (CLAUDE.md Testing Philosophy 준수)

- [ ] ClipboardChannel / TransferChannel **명세 기반 테스트** 작성
  - 경로 검증
  - 크기/개수 한계
  - CRC 처리
  - 재귀 디렉터리

### 🔧 개선 (Improvements) — Qt 클라이언트

> Discord 공지의 "Windows / Linux (Qt) client usability improvements" 실체

- [ ] **ClientQt: 디스플레이 레이아웃 설정 UI** (현재 부재)
- [ ] **ClientQt: 디스플레이 해상도 설정 UI** (현재 부재)
- [ ] **ClientQt: 가상 디스플레이 생성 UI** (현재 불완전)
- [ ] **ClientQt: 코덱 폴백 로직 강화** (현재 부실)

### 🗑️ 제거 (Removals)

- [ ] **타일링 이미지 코덱 제거**: MJPG / ZRLE / WebP
  - 서버 인코더 제거
  - 클라이언트 디코더 제거 (Client / ClientQt)
  - 코덱 협상 로직에서 제외
  - 문서 / 웹사이트 feature table 갱신 필요

### 📄 문서 / 웹사이트 (Docs / Website)

- [ ] `noctiluca-website`: 코덱 표 갱신 (타일링 제거, VP8 추가)
- [ ] `noctiluca-website`: 가상 디스플레이 / 디스플레이 레이아웃 변경 기능 소개 섹션
- [ ] `CLAUDE.md` 제품 정보 섹션 갱신 (코덱 표)
- [ ] 공식 changelog 문서화

### 🌐 스토어 / 배포 (Store & Distribution)

- [ ] **App Store 상점 페이지 기본 언어를 영문으로 변경**
  - 현: 비-미국 사용자에게 한국어 설명문이 표시되는 문제
  - App Store Connect에서 primary localization 영문으로 전환 + 필요 시 한국어를 secondary로
  - ⚠️ **텍스트만 수정하는 게 아님 — 스크린샷도 전부 재제작 필요**
    - 현 스크린샷은 한국어 locale 기준 (UI 텍스트가 한국어)
    - 플랫폼마다 스크린샷 세트가 제각각: Server(macOS), Navigator(macOS / iOS / iPadOS)
    - 각 플랫폼 요구 해상도·aspect ratio 맞게 영문 locale로 재캡처
    - 실제 볼륨은 퀵윈 아님 — 반나절~하루 단위 작업

### 🚀 릴리즈 준비 (Release Prep)

- [ ] Changelog 작성 (`docs/changelogs/server/0.9.10.md`)
- [ ] Changelog 작성 (`docs/changelogs/navigator/0.9.10.md` — 필요 시)
- [ ] 버전 번호 bump
- [ ] 빌드 / 서명 / 배포 파이프라인 확인
- [ ] Discord 릴리즈 공지 (이미 "예고" 공지는 나감)

### ❓ 미정 / 논의 필요 (Undecided)

- [ ] iPad 보조 디스플레이 분리 — 실험 플래그로 출시할지, 기본 on 으로 갈지?
  - (선결 조건: iPad Pro 실기 테스트 — 남자친구 iPad 빌려서)

### ✅ 해소된 미정 사항 (Resolved)

- [x] ~~가상 디스플레이 "가드 로직" 구체 범위~~
  → 오류 가드 + 최소/최대 해상도 제한 (현 macOS 3840×2160) + 이상 해상도 (1×1, 262144×2 등) 거부. 기능 섹션 참조.
- [x] ~~클립보드 파일 전송 — 0.9.10 포함 vs 별도 핫픽스?~~
  → **0.9.10에 함께 shipping**. 보안 섹션 참조.

---

## 📌 참고

- 이전 릴리즈 changelog: `docs/changelogs/server/`
- 관련 진행 중 문서:
  - `docs/TODO_DESKTOPCONTEXTMANAGER_DEBOUNCING.md`
  - `docs/audio-projection-opusenc.md`
  - `docs/clipboard-transfer-security-report.md` ← **0.9.10 보안 작업 근거**
  - `docs/virtual-display-plan.md` ← **가상 디스플레이 설계**
  - `docs/HIDPI_PROJECTION_REPORT.md`
  - `docs/swift6-channel-migration-rules.md`
  - `docs/swift6-siriuskit-tests-buildfix.md`
