# Plugin Host XPC 안전성 감사 보고서

| 항목 | 내용 |
| --- | --- |
| 작성일 | 2026-05-18 |
| 대상 타겟 | NoctilucaServer (Swift / macOS), NoctilucaPluginKitHost (Swift / macOS XPC service), Shotoku (외부 의존, `../Shotoku`) |
| 대상 컴포넌트 | `NoctilucaPluginKitHost.xpc` 와 그 IPC 경계 (Shotoku `RPCListener` / `RPCClient` over XPC) |
| 검토 기준 | `appstream-swift6` 브랜치 작업 트리 |

본 문서는 NoctilucaServer 플러그인 번들 로딩 모델 (`docs/plugin-process-isolation.md`)
의 신뢰 경계 — 즉 **서버 본체 ↔ `NoctilucaPluginKitHost.xpc` 인스턴스** 사이의
XPC 경계 — 가 현재 코드에서 어떻게 방어되고 있는지를 검토한 결과입니다.

특히, 플러그인 번들 자체에 대한 코드 서명 검증과는 별개로, **XPC 연결 양 끝의
peer 가 정말로 서로가 기대하는 코드 (서명된 Noctiluca 본체 / 본체에 내장된 XPC
service) 인지** 를 확인하는 메커니즘이 적용되어 있는지를 다룹니다.

각 항목은 **① 위치 → ② 시나리오 → ③ 영향 → ④ 권장 조치** 형식으로 정리합니다.

---

## 0. TL;DR

> **Update (2026-05-18)**: §3.1 / §3.2 / §3.3 — Resolved. Shotoku 가
> `RPCXPCEndpointOptions.peerCodeSigningRequirement` 를 제공하면서 §3.7
> prerequisite 가 해결되었고, NoctilucaServer 측에서 양방향 게이트와 audit
> token 기반 보강 검증 (`XPCPeerIdentity.verify(...)`) 을 적용했습니다.
> 본 TL;DR 의 HIGH 3건 (§3.1 / §3.2 / §3.3) 은 이제 historical record 로
> 남깁니다. 나머지 MEDIUM / LOW 항목은 미해결.

- **HIGH (Resolved 2026-05-18)**: ~~`NoctilucaPluginKitHost.xpc` 측 `RPCListener` 에 `authorize:`
  클로저가 전달되지 않아, **연결해 온 peer (server 본체) 의 코드 서명을 일절
  검증하지 않습니다**~~. `NoctilucaPluginKitHost/main.swift` 가
  `authorize:` 클로저를 전달하여 `XPCPeerIdentity.verify(...)` 로 peer audit
  token 을 평가하고, listener endpoint 에는
  `peerCodeSigningRequirement: XPCPeerIdentity.serverPeerRequirement` 를
  설정하여 libxpc OS-레벨 가드도 함께 적용 (이중 가드).
- **HIGH (Resolved 2026-05-18)**: ~~Shotoku 의 `XPCBridge` 가 `xpc_connection_get_audit_token` /
  `xpc_dictionary_get_audit_token` 으로 audit token 을 추출해
  `RPCPeerProcess.auditToken` 까지 채워서 넘기지만, **NoctilucaServer /
  NoctilucaPluginKitHost 어느 쪽에서도 이 audit token 으로 코드 서명 동일성을
  검증하는 호출이 존재하지 않습니다**~~. `NoctilucaPluginKitHostCore/security/
  XPCPeerIdentity.swift` 가 `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`
  + `SecCodeCheckValidity` 흐름을 캡슐화하여 host 의 `authorize:` 클로저가
  매 connection / 매 message dispatch 마다 audit token 을 평가하도록 함.
- **HIGH (Resolved 2026-05-18)**: ~~server 본체 → host XPC 방향에서도 발신 측 검증이 없습니다~~.
  `XPCLoader` 가 `RPCXPCEndpointOptions(peerCodeSigningRequirement:
  XPCPeerIdentity.hostPeerRequirement)` 를 endpoint 에 부착하여, libxpc 가
  connect 시점에 host XPC service 의 DR 매칭을 native 로 수행하도록 변경
  (`xpc_connection_set_peer_code_signing_requirement` 가 Shotoku 내부에서
  설정됨).
- **MEDIUM**: `SecStaticCodeCheckValidity` 호출 시 `requirement` 파라미터가
  `nil` 입니다 (`PluginBundleCodeSigningVerifier.swift:42-46`). 즉 명시적인
  Designated Requirement 문자열 (`anchor apple generic and certificate
  leaf[subject.OU] = "XHA76UVA95"`) 매칭을 수행하지 않고, info dictionary 에서
  꺼낸 Team ID 를 Swift 코드 레벨에서 문자열 비교하고 있습니다. CSSM 가 native
  로 평가하는 DR 매칭에 비해 **(a) 인증서 체인의 Apple anchor 검증이 누락되고,
  (b) "anchor apple generic" 같은 추가 조건을 강제하지 못합니다.**
- **MEDIUM**: `SecStaticCodeCheckValidity` 의 flags 가
  `kSecCSCheckAllArchitectures` 단독이며, `kSecCSStrictValidate` /
  `kSecCSEnforceRevocationChecks` / `kSecCSCheckNestedCode` 를 사용하지
  않습니다. 폐기된 인증서로 서명된 번들이 차단되지 않고, nested code (예: 번들
  내부의 helper framework / 임의의 추가 dylib) 의 서명 무결성이 검증되지
  않습니다.
- **MEDIUM**: 번들 로드 시 `bundle.bundleIdentifier` 와 `manifest.id`
  (NoctilucaPluginKit manifest.json 의 `id` 필드) 의 교차 검증이 없습니다.
  매니페스트만 위조하여 다른 번들을 사칭하는 시나리오에 대한 추가 레이어가
  부재합니다.
- **LOW**: 운영자 / 사용자 관찰성 (telemetry / OSLog) 측면에서, XPC peer 의
  Team ID / pid / audit token 요약을 명시적으로 기록하는 시점이 없습니다. 이상
  연결을 사후 분석할 수 있는 단서가 부족합니다.

전체 패턴을 한 줄로 요약하면:

> **플러그인 번들 자체의 서명은 검증하지만, "XPC 양 끝의 peer 가 그 번들을 들고
> 있는 서명된 Noctiluca 본체 / 본체에 정상 내장된 host service 가 맞는지" 는
> 검증하지 않는다.**

플러그인 번들 검증이 `XPCLoader` 시작 *전* 에 server 본체 측에서 수행되기
때문에, 정상 시나리오에서는 host 가 dlopen 하는 dylib 의 정체성은 보장됩니다.
하지만 본 문서는 **XPC 경계 자체** 의 신뢰 모델을 다루며, 이 경계에서는 위의
가드가 빠져 있습니다.

---

## 1. 검토 대상과 위협 모델

### 1.1 컴포넌트 범위

| 컴포넌트 | 역할 | 비고 |
| --- | --- | --- |
| NoctilucaServer (main process) | XPC client. `XPCLoader` 가 host service 로 connect | `NoctilucaServer/plugins/bundle-system/loader/XPCLoader.swift` |
| `NoctilucaPluginKitHost.xpc` | XPC service. `RPCListener` 가 server 본체의 connection 을 수락 | `NoctilucaPluginKitHost/main.swift` |
| NoctilucaPluginKitHostCore | host service 의 core 로직 (코드 서명 verifier 포함) | `NoctilucaPluginKitHostCore/security/PluginBundleCodeSigningVerifier.swift` |
| Shotoku | RPC framework (외부, `../Shotoku`) | `Sources/Shotoku/Public/Listener.swift`, `Public/Context.swift`, `Transport/XPC/XPCBridge.swift`, `Transport/XPC/XPCTransport.swift` |

### 1.2 신뢰 모델

`docs/plugin-process-isolation.md` 의 격리 모델에서, XPC 경계의 양쪽은 모두
**같은 vendor (team unstablers) 가 서명한 동일 번들의 일부** 라는 전제로
구성되어 있습니다 (`NoctilucaPluginKitHost.xpc` 는 server bundle 의
`Contents/XPCServices/` 에 내장).

이 전제가 깨지는 시나리오는 다음과 같습니다.

1. **악성 클라이언트의 XPC 직접 접속**: launchd 가 spawn 한
   `NoctilucaPluginKitHost.xpc` 에 server 본체가 아닌 다른 프로세스 (예:
   sandbox escape 한 다른 앱, 디버거에 attach 한 임의 프로세스) 가
   `xpc_connection_create_mach_service` 류로 직접 연결을 시도하는 경우.
2. **호스트 service 위장**: server 본체가 connect 할 때, 동일한 서비스 이름
   (`app.noctiluca.server.NoctilucaPluginKitHost`) 으로 등록된 다른 launchd
   plist 가 우선 순위에서 이긴 경우 (이론적 시나리오. 일반적으로 server
   bundle 내장 service 가 사용되지만 환경 변수 / 사용자별 LaunchAgent 조작
   가능성).
3. **로컬 사용자 권한 상승 후의 측면 공격**: 로컬 사용자가 이미 host service
   binary 를 임의 dylib 으로 swizzle 한 후 server 본체와의 IPC 를 가로채는
   경우.

이 중 (1) 과 (2) 는 XPC peer 검증 (양방향) 으로 차단할 수 있는 부류이며, 본
보고서가 다루는 범위입니다. (3) 은 SIP / sandbox / Hardened Runtime 영역으로
별도 작업입니다.

---

## 2. 잘 되어 있는 부분 (현재 구현 요약)

검토 결과, 다음 영역은 정상적으로 구현되어 있습니다.

### 2.1 번들 코드 서명 검증

- `PluginBundleCodeSigningVerifier.verify(bundleURL:)` 가 `SecStaticCodeCreateWithPath`
  + `SecStaticCodeCheckValidity` + `SecCodeCopySigningInformation` 으로
  서명을 검증하고 Team ID 를 추출합니다. (`PluginBundleCodeSigningVerifier.swift:33-79`)
- 호출 위치: `PluginBundleRegistry.loadBundle(from:)` 가 `bundle.load()` *이전* 에
  명시적으로 검증을 수행합니다. (CLAUDE.md `PLUGIN SYSTEM` 섹션 및
  `PluginBundleRegistry.swift:222-238` 참조)
- 격리 정책 교차 검증: `manifest.isolationPolicy == .noIsolate` 인 번들은 Team ID
  가 `XHA76UVA95` 인지 추가로 확인합니다 (`PluginBundleRegistry.swift:241-275`,
  `allowNonisolatedThirdPartyPluginBundle` 으로 사용자 opt-in 가능).

### 2.2 정책 표현

- `PluginBundleSecurityPolicy` 가 `disallowAll` / `allowTeamUnstablers` /
  `allowSigned` / `allowAll` 4단계로 구분되어 있으며, 기본값은
  `allowTeamUnstablers` 입니다 (`PluginBundleRegistry.swift:138`).

### 2.3 Shotoku 측의 hook 인프라

- `RPCListener` 가 `authorize:` 클로저와 `RPCAuthorizationPolicy` (`.connection`,
  `.message`) 를 제공합니다. 기본 정책은 `[.connection, .message]` 로 connection
  설립 직후 + 각 메시지 dispatch 직전 두 번 검증할 수 있는 구조입니다
  (`Shotoku/Sources/Shotoku/Public/Listener.swift:28-44`,
  `Shotoku/Sources/Shotoku/Public/Context.swift:55-83`).
- `RPCPeerProcess` 가 `pid` / `euid` / `egid` / 원시 `auditToken: Data` 를
  전달하며, 주석에서 audit token 이 `SecCodeCopyGuestWithAttributes` 에 그대로
  쓸 수 있는 형태임을 명시하고 있습니다 (`Shotoku/Sources/Shotoku/Public/Context.swift:40-53`).
- 메시지 단위로는 `xpc_dictionary_get_audit_token` 을 호출하여 connection-level
  token 이 아닌 send-time token 을 쓰도록 구현되어 있습니다
  (`Shotoku/Sources/Shotoku/Transport/XPC/XPCTransport.swift:355-368`,
  `Shotoku/Sources/Shotoku/Transport/XPC/XPCBridge.swift:36-64`).

즉, **검증을 위한 재료는 Shotoku 가 이미 모두 손에 쥐여 주고 있는데, 호출 측에서
재료를 받아 쓰지 않고 있는 상태** 입니다.

---

## 3. 누락된 검증 항목 (본 보고서의 본문)

### 3.1 [HIGH] `RPCListener` `authorize:` 클로저 미전달

- **위치**: `NoctilucaPluginKitHost/main.swift:27-33`
  ```swift
  let listener = RPCListener<HostControlInterfaceImpl>(
      service,
      endpoint: .xpc("app.noctiluca.server.NoctilucaPluginKitHost"),
      logger: self.logger
  )
  ```
- **시나리오**: host service 의 `RPCListener` 가 `authorize:` 파라미터를
  생략하고 초기화됩니다. Shotoku 의 `State.start()` 에서는 다음과 같이 가드를
  걸지만 (`Shotoku/.../Public/Listener.swift:120-134`),

  ```swift
  authorize: { peer in
      guard policy.contains(.connection) else { return true }
      guard let authorize else { return true }   // ← 여기서 전부 통과
      ...
  }
  ```

  `authorize` 가 `nil` 인 한 connection-level 검증도, message-level 검증도
  사실상 작동하지 않습니다 (`RPCAuthorizationPolicy` 의 기본값 `[.connection,
  .message]` 자체는 set 되어 있지만, 클로저가 없어 항상 `true`).
- **영향**: launchd 가 spawn 한 `NoctilucaPluginKitHost.xpc` 인스턴스에 대해
  **누가 connect 하든 host control interface (loadBundle / unloadBundle /
  keyboardHack_* / bundle_*) 가 노출됩니다.** loadBundle 호출 한 번이면 임의
  경로의 dylib 을 host process 안에서 `dlopen` 시킬 수 있고, 그 host process 는
  server 본체의 entitlement 일부 (XPC service 본인 한정) 를 갖고 있는
  프로세스입니다. 격리의 목적이 "server 본체를 보호" 였다는 점에서 정반대
  방향의 위협이지만, "**host process 가 임의 코드 실행 환경으로 전락**" 자체가
  유의미한 공격 표면입니다.
- **권장 조치**: `RPCListener` 초기화 시 `authorize:` 를 전달.
  - 최소: `RPCPeerProcess.auditToken` 으로 `SecCodeCopyGuestWithAttributes` 호출
    → `SecCodeCheckValidity(_:_:requirement)` 에서 designated requirement
    문자열 (`identifier "app.noctiluca.server" and anchor apple generic and
    certificate leaf[subject.OU] = "XHA76UVA95"`) 매칭.
  - 권장: 위에 더해 macOS 12+ 의 `xpc_connection_set_peer_code_signing_requirement`
    를 underlying `xpc_connection_t` 에 set 하여 OS 레벨에서도 같은 가드를
    얻기 (이중 가드). 다만 이는 Shotoku 의 `XPCTransport` 가 underlying
    connection 을 노출해야 하므로 §3.7 참조.

### 3.2 [HIGH] audit token 이 채워지지만 코드 서명 검증에 사용되지 않음

- **위치**: 검증이 일어나야 하지만 일어나지 않는 곳들 — 호출 자체가 존재하지
  않음을 grep 으로 확인.
  ```
  $ grep -rn -E 'peer_code_signing|SecCodeCopyGuest|xpc_connection_set_peer' \
        NoctilucaServer
  (0 hit)
  ```
- **시나리오**: Shotoku 가 `RPCPeerProcess.auditToken` 까지 친절하게 채워서
  넘기지만, 이를 받아 `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`
  + `SecCodeCheckValidity(_:_:requirement)` 로 평가하는 호출이 server / host
  양쪽 어디에도 없습니다. `RPCPeerProcess.pid` / `euid` 도 마찬가지로
  authorization 결정에 활용되지 않습니다.
- **영향**: §3.1 의 게이트가 비어 있음을 보강하는 fallback 도 없음을 의미.
  심지어 **token 의 존재 자체가 코드의 의도를 오해하게 만드는 false sense of
  security** 로 작용할 수 있습니다 (코드를 읽는 사람이 "audit token 이 있으니
  뭔가 검증이 되고 있겠지" 라고 가정).
- **권장 조치**: §3.1 의 `authorize:` 클로저 구현 시, 다음 헬퍼를 새로
  도입합니다.
  ```swift
  // 예시 — NoctilucaPluginKitHostCore/security/ 에 별도 파일로
  enum XPCPeerCodeSigningVerifier {
      static func verify(
          auditToken: Data,
          designatedRequirement: String
      ) -> Result<Void, Error> {
          // 1) SecCodeCopyGuestWithAttributes(nil,
          //    [kSecGuestAttributeAudit: auditTokenCFData], [], &peerCode)
          // 2) SecRequirementCreateWithString(drString, [], &req)
          // 3) SecCodeCheckValidity(peerCode, [.strict, .enforceRevocationChecks], req)
      }
  }
  ```
  - `auditToken` 은 Shotoku 가 8 워드 (`audit_token_t`) 원본을 그대로 `Data`
    로 wrapping 한 것이므로 (`Shotoku/.../XPCBridge.swift:55-63`), CFData 로
    캐스팅하면 `SecCodeCopyGuestWithAttributes` 에 그대로 전달 가능합니다.
  - server 본체의 DR 문자열은 `codesign -d -r- /path/to/NoctilucaServer.app`
    로 추출한 것을 기준으로 작성. 빌드 타깃 (개발 빌드 / Release / App Store)
    별로 anchor 가 다르므로, 빌드 컨피그 별 DR 문자열 (또는 anchor 만 다른
    union DR) 을 두는 패턴이 일반적입니다.

### 3.3 [HIGH] server → host 방향의 peer code signing requirement 미설정

- **위치**: `NoctilucaServer/plugins/bundle-system/loader/XPCLoader.swift` 가
  사용하는 Shotoku `RPCClient<HostControlInterface>` 생성 경로. `XPCLoader.swift`
  는 endpoint 이름 (`app.noctiluca.server.NoctilucaPluginKitHost`) 만 지정하고
  underlying XPC connection 에 peer code signing requirement 를 set 하지
  않습니다.
- **시나리오**: `xpc_connection_set_peer_code_signing_requirement(_:_:)` (macOS
  12+) 를 사용하면, OS 가 connect 시점에 peer 의 DR 매칭을 native 로
  수행합니다. 미설정 상태이므로, 동일 서비스 이름을 갖는 다른 launchd 등록이
  먼저 우선 선택된 경우 (사용자 LaunchAgent 우선순위, 환경 변수 조작 등)
  탐지가 불가능합니다.
- **영향**: 본 보고서의 다른 항목들과 결합되어, "**플러그인 dylib 의 서명은
  검증했지만, 그 dylib 을 dlopen 하는 host process 가 정말로 우리가 빌드한
  XPC service 인지** 는 검증하지 않음" 이라는 비대칭이 발생합니다. 실제 OS
  레벨에서 이 시나리오가 얼마나 현실적인가는 sandbox / SIP 설정에 따라
  다르지만, 가드 자체가 빠져 있다는 것은 위협 모델 측면에서 기록해 둘 사항.
- **권장 조치**:
  - 권장: Shotoku 에 endpoint 확장 옵션 (`xpc(_:peerRequirement:)`) 을 추가
    제안. underlying `xpc_connection_t` 가 만들어진 직후
    `xpc_connection_set_peer_code_signing_requirement` 를 호출하도록 API 노출.
    Shotoku 가 외부 패키지이므로 PR 또는 fork-and-patch 가 필요.
  - 차선: `XPCLoader` 내부에서 별도의 `xpc_connection_t` 를 직접 생성하고 peer
    requirement 를 건 다음, 그 connection 을 Shotoku 가 wrapping 하도록 분리.
    다만 현재 Shotoku 의 `XPCTransport` 가 connection 생성을 내부에서 하므로
    중간 layer 우회 패턴이 됩니다 — 깔끔하지 않음.
  - 최소: §3.2 의 `authorize:` 헬퍼를 client 측 대신 host 측에서 강하게 수행
    (즉 양방향 중 한쪽만이라도 게이트). 이 경우 server 쪽 위장 시나리오는
    여전히 검증되지 않지만, 본체 → 위장 host 로 전달되는 명령은 위장 host 가
    arbitrary code 를 host process 에 dlopen 할 권한을 얻을 뿐이라
    실효 피해는 §3.1 과 같은 수준에서 머무름.

### 3.4 [MEDIUM] `SecStaticCodeCheckValidity` 의 requirement 가 `nil`

- **위치**: `NoctilucaPluginKitHostCore/security/PluginBundleCodeSigningVerifier.swift:42-46`
  ```swift
  let validityStatus = SecStaticCodeCheckValidity(
      code,
      SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
      nil   // ← requirement
  )
  ```
- **시나리오**: 현재 구현은 (a) 서명 무결성을 통과하면 (b) info dictionary 에서
  `kSecCodeInfoTeamIdentifier` 를 꺼내 Swift 코드로 `XHA76UVA95` 와 문자열
  비교합니다. 이는 다음을 검증하지 않습니다.
  - **Apple anchor** 검증: "anchor apple generic" 를 명시적으로 요구하지
    않으므로, self-signed CA 로 만든 서명도 Team ID 가 같은 문자열이면 통과할
    이론적 여지가 있음. (실제로는 `kSecCodeInfoTeamIdentifier` 가 Apple
    notarization 영역과 결부되어 채워지므로 대부분 차단되지만, "검증의 의도" 가
    코드에 명시되어 있지 않다는 점이 문제.)
  - **세분화된 식별자 매칭**: `identifier "app.noctiluca.plugin.*"` 같이
    bundle identifier 패턴을 DR 에 같이 묶어둘 여지가 사라짐.
- **영향**: 보안적 영향은 상대적으로 작지만, **검증 로직이 "Apple 이 보장하는
  DR 매칭" 이 아니라 "Swift 문자열 비교" 라는 점이 코드 리뷰 / 외부 감사 시
  red flag** 가 됩니다. 또한 향후 third-party Team ID 를 허용하는 정책
  (`allowSigned`) 에서, 진짜 Apple Developer Program 서명인지를 강제할 방법이
  현재 코드 경로에 없습니다.
- **권장 조치**:
  - DR 문자열을 `PluginBundleSecurityPolicy` 별로 상수로 보유.
    - `allowTeamUnstablers`:
      `anchor apple generic and certificate leaf[subject.OU] = "XHA76UVA95"`
    - `allowSigned`: `anchor apple generic and certificate
      1[field.1.2.840.113635.100.6.2.1] exists` (Developer ID Application
      intermediate). 정확한 OID 는 정책 별로 별도 결정.
  - `SecRequirementCreateWithString` 로 빌드한 requirement 를
    `SecStaticCodeCheckValidity` 에 넘기고, Team ID 비교는 진단/로깅 용도로만
    유지.

### 3.5 [MEDIUM] `SecCSFlags` 보강 필요 (`strictValidate`, `enforceRevocationChecks`, `checkNestedCode`)

- **위치**: 같은 라인 (`PluginBundleCodeSigningVerifier.swift:42-46`).
- **시나리오**: 현재 flags 는 `kSecCSCheckAllArchitectures` 단독.
  - `kSecCSStrictValidate` 누락: resource fork / extended attribute 부분에
    예상치 못한 entry 가 있어도 통과. macOS Gatekeeper 가 기본으로 적용하는
    엄격 모드를 우리는 적용하지 않고 있음.
  - `kSecCSEnforceRevocationChecks` 누락: 인증서 폐지 (CRL/OCSP) 가 발생한
    경우에도 통과.
  - `kSecCSCheckNestedCode` 누락: 번들 내부의 framework / dylib 의 서명 무결성
    체크가 누락. 번들이 헬퍼 dylib 을 같이 들고 다닐 경우, 본 번들의 서명만
    유효하면 헬퍼는 검증 없이 통과될 수 있음.
- **영향**: 단독으로는 critical 이 아니지만, §3.4 와 결합되어 "**우리는 SecCS
  를 부르긴 하지만 가장 약한 모드로 부른다**" 라는 인상을 줍니다.
- **권장 조치**:
  ```swift
  let flags: UInt32 =
      kSecCSCheckAllArchitectures |
      kSecCSStrictValidate |
      kSecCSEnforceRevocationChecks |
      kSecCSCheckNestedCode
  ```
  단, `enforceRevocationChecks` 는 오프라인 환경에서 false negative 를 유발할
  수 있으므로, 네트워크 가용성 / 사용자 경험을 고려한 fallback (예: 한 번
  실패하면 cached OCSP 만 신뢰) 을 함께 설계할 것.

### 3.6 [MEDIUM] `bundle.bundleIdentifier` ↔ `manifest.id` 교차 검증 부재

- **위치**: `NoctilucaServer/plugins/bundle-system/PluginBundleRegistry.swift`
  의 `loadBundle(from:)` 경로. `manifest.json` 의 `id` 와 Info.plist 의
  `CFBundleIdentifier` 를 같이 읽지만, **두 값이 일치하는지를 비교하는 분기가
  없습니다.** `HostControlInterfaceImpl.loadBundle(bundlePath:)` 도
  `bundle.bundleIdentifier ?? bundlePath` 를 그대로 bundleId 로 사용하고 manifest
  와 대조하지 않습니다 (`HostControlInterfaceImpl.swift:93` 부근).
- **시나리오**: 공격자가 `BundleA.bundle/Contents/Info.plist` 의
  `CFBundleIdentifier` 를 위조하여 다른 서명된 번들의 정체성을 사칭. 코드
  서명은 (서명자가 다르면) 별개로 잡히지만, 만약 같은 Team ID 안에서의 번들
  간 사칭이라면 §2.1 의 Team ID 게이트로도 잡히지 않음.
- **영향**: 동일 vendor 내부의 번들 간 사칭 → 잘못된 정책 / 잘못된 capability
  적용. 현 시점 외부 third-party 번들 생태계가 없으므로 (`disallowAll` 기본)
  실제 위험은 낮지만, 정책이 `allowSigned` / `allowAll` 로 완화되면 즉시
  문제로 표면화.
- **권장 조치**: `PluginBundleRegistry.loadBundle(from:)` 안에 다음 검증을 추가.
  ```swift
  guard bundle.bundleIdentifier == manifest.id else {
      throw PluginBundleLoadError.identityMismatch(
          manifest: manifest.id,
          bundleIdentifier: bundle.bundleIdentifier
      )
  }
  ```
  비교 시 case-sensitive / trimming 정책을 먼저 결정해 둘 것.

### 3.7 [LOW] Shotoku XPC endpoint 가 underlying connection 접근을 노출하지 않음

- **위치**: `Shotoku/Sources/Shotoku/Public/Endpoint.swift` 와
  `Transport/XPC/XPCTransport.swift`.
- **시나리오**: §3.3 의 권장 조치를 깔끔하게 구현하려면 Shotoku 측에서
  ```swift
  enum RPCXPCEndpointOptions {
      var peerCodeSigningRequirement: String?
      ...
  }
  ```
  같은 옵션을 endpoint 빌더에 노출해야 합니다. 현재는 그러한 hook 이 없음.
- **영향**: NoctilucaServer 단독 PR 로는 §3.3 의 권장 조치를 구현하기 어려움
  (workaround 패턴 필요). 본 보고서의 권장 사항을 실제 코드에 반영하려면
  Shotoku 측 API 확장이 선행 필요.
- **권장 조치**: Shotoku 에 별도 이슈로 등록. (`xpc_connection_set_peer_code_signing_requirement`
  바인딩 추가 + Endpoint API 확장.)

### 3.8 [LOW] 관찰성: peer 정체성 로깅 부재

- **위치**: 같은 경로 — 현재 `RPCListener` accept / `RPCClient` connect 시
  peer 의 pid / Team ID / DR 매칭 결과를 OSLog 에 남기는 코드가 없습니다.
- **시나리오**: §3.1-§3.6 의 가드가 추가되었을 때, **차단된 connection 의
  단서를 사후에 분석** 하려면 최소한 pid + euid + (가능하면) signing identity
  요약이 로그에 남아야 합니다.
- **권장 조치**: `authorize:` 클로저 안에서 `logger.info` 한 줄로 다음을 기록.
  ```
  XPC connect — pid=… euid=… team=… identifier=… result=accepted|denied(reason=…)
  ```
  민감 정보 (audit token 원본) 는 로그에 남기지 말 것.

---

## 4. 우선순위와 제안 작업 순서

본 보고서의 결과를 코드로 반영한다면 다음 순서를 권장합니다.

1. ~~**§3.1 + §3.2 (HIGH)**~~ — **DONE (2026-05-18)**. `NoctilucaPluginKitHost/main.swift`
   에 `authorize:` 클로저 전달 + `NoctilucaPluginKitHostCore/security/
   XPCPeerIdentity` (verify 헬퍼) + `XPCPeerCodeSigningError` 도입. listener
   endpoint 에 `peerCodeSigningRequirement: serverPeerRequirement` 도 함께 설정.
2. **§3.4 + §3.5 (MEDIUM)** — `PluginBundleCodeSigningVerifier.verify(bundleURL:)`
   의 호출에 designated requirement 와 보강된 flags 를 적용. 번들 자체의 검증
   품질을 한 단계 올림.
3. **§3.6 (MEDIUM)** — `manifest.id` ↔ `CFBundleIdentifier` 일치 검증 추가.
   `PluginBundleSecurityPolicy` 가 `allowSigned` / `allowAll` 로 확장되기 전에
   선반영해 둘 것.
4. ~~**§3.7 → §3.3 (LOW → HIGH 의 implementation prerequisite)**~~ —
   **DONE (2026-05-18)**. Shotoku 가 `RPCXPCEndpointOptions.peerCodeSigningRequirement`
   를 추가하여 §3.7 해결, NoctilucaServer 의 `XPCLoader` 는 endpoint 생성 시
   `hostPeerRequirement` 를 옵션으로 전달.
5. **§3.8 (LOW)** — 위 작업이 끝난 뒤 진단/관찰 라인을 보강. 현재 host 의
   `authorize:` 클로저가 accept/reject 시 pid / euid / procedure / reason 한
   줄을 남기지만, server 측 connect 결과 / DR 매칭 실패 상세는 아직 미보강.

---

## 5. 본 보고서가 다루지 않는 항목

- 플러그인 번들이 가져오는 dylib 의 sandbox / entitlement 격리 (별도 작업,
  `docs/plugin-process-isolation.md` 의 향후 sandbox profile 항목).
- `NoctilucaPluginKitHost.xpc` 의 entitlement 자체 검토 (별개 영역).
- launchd plist / `_MultipleInstances=YES` 의 무결성 (OS / 코드 서명으로
  보장되는 영역).
- TCC / Hardened Runtime / Library Validation 의 적용 여부 (역시 별도).
- NoctilucaClient 측 XPC 사용처 (예: AVCaptureSession helper) — 본 보고서는
  *plugin host* XPC 경계로 한정됩니다.
