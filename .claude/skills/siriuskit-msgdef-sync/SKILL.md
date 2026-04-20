# SiriusKit msgdef Sync Skill

libsirius의 자동 생성 Swift msgdef 파일을 SiriusKit 쪽으로 동기화하는 스킬입니다.
`.mdproto.md` 파일이 갱신되면 `NoctilucaClientQt/cmake-build-debug/dependencies/libsirius/msgdef/swift/` 아래에 Swift 코드가 생성되는데, 이 중 일부를 SiriusKit 소스 트리에 손으로 머지하는 절차를 자동화합니다.

## Usage

```
/siriuskit-msgdef-sync [동기화할 범위 설명 — 필수]
```

- 범위는 **반드시** 지정되어야 합니다. 예:
  - `projection/ 아래 가상 디스플레이 관련 파일`
  - `hidio 전체`
  - `clipboard 파일 전송 관련`
- 범위가 지정되지 않았다면 **먼저 사용자에게 물어서 범위를 확정**하세요.

## 중요한 전제

- 자동 생성된 Swift 코드의 퀄리티가 좋지 않습니다. **문법 오류와 버그가 섞여 나옵니다.**
- SiriusKit 쪽 기존 파일에는 **손으로 수정한 부분이 많습니다.** 절대 통째로 덮어쓰지 마세요.
- 이 작업은 shell script로는 불가능합니다. LLM이 diff를 읽고, 의미를 파악해서 머지해야 합니다.
- **실패를 두려워하지 마세요.** 사용자가 복구할 수 있으니 자신 있게 작업하세요. 단, 덮어쓰기 전에 반드시 기존 파일을 먼저 읽어 보세요.

## 절차

### Step 1. msgdef 빌드

아래 명령을 실행해서 최신 Swift 생성본을 만듭니다:

```bash
cd NoctilucaClientQt/cmake-build-debug && ninja sirius_msgdef_swift
```

빌드 후 cwd가 바뀌었을 수 있으니, 이후 단계에서는 **반드시 절대 경로를 사용하거나 repo root로 되돌아오세요** (Step 4-1 참조).

### Step 2. 동기화 대상 결정

#### 2-1. 소스 / 타겟 경로 이해

**소스 (libsirius 자동 생성):**
```
$REPO_ROOT/NoctilucaClientQt/cmake-build-debug/dependencies/libsirius/msgdef/swift/
├── constants/       # constset / optionset 정의 (DisplayKind, DisplayChangeEventType 등)
├── msgdef/          # SwiftProtobuf로 생성된 원본 *.pb.swift
└── siriuskit/       # SiriusMessage 래퍼 (+Sirius.swift)
```

**타겟 (SiriusKit 소스 트리):**
```
$REPO_ROOT/SiriusKit/Sources/SiriusKitCore/
├── autogen/msgdef/                # *.pb.swift 복사본 (통째 교체 OK)
└── channel/msgdef/                # +Constants.swift / +Options.swift / +Sirius.swift (머지 필요)
```

경로 매핑은 대략:
- 소스 `constants/v1/channels/projection/foo+Constants.swift` → 타겟 `channel/msgdef/v1/channels/projection/foo+Constants.swift`
- 소스 `msgdef/v1/channels/projection/foo.pb.swift` → 타겟 `autogen/msgdef/v1/channels/projection/foo.pb.swift`
- 소스 `siriuskit/msgdef/v1/channels/projection/foo+Sirius.swift` → 타겟 `channel/msgdef/v1/channels/projection/foo+Sirius.swift`

#### 2-2. 파일 리스트업

사용자가 요청한 범위에 해당하는 파일을 세 카테고리(`constants/`, `msgdef/`, `siriuskit/`)에서 각각 찾아 열거하세요.

**맥락 파악을 위해 `SiriusProtocol/` 디렉토리의 최근 커밋도 함께 보세요:**
```bash
git -C NoctilucaClientQt/dependencies/libsirius log --oneline -20 -- msgdef/SiriusProtocol
```
(또는 submodule 구조에 맞는 경로)

이걸 보면 어떤 변경이 있었는지 감 잡기 좋습니다.

### Step 3. 사용자 확인 (AskUserQuestion)

찾은 파일 목록을 카테고리별로 정리해서 `AskUserQuestion` 툴로 사용자에게 확인받으세요.

옵션 예시:
- "전부 동기화해줘 (Recommended)"
- "특정 파일만 골라서"
- "취소"

### Step 4. 동기화 실행

#### 4-1. CWD 복구 (중요)

Step 1에서 `cd`로 cmake-build-debug 안에 들어갔을 수 있습니다. 다음 단계부터는 **반드시** repo root (`$REPO_ROOT/NoctilucaServer`)로 돌아오거나, 모든 명령에 절대 경로를 사용하세요.

#### 4-2. `*.pb.swift` 복사 + 패치

자동 생성된 `.pb.swift`는 **통째 교체**해도 괜찮습니다 (autogen 디렉토리는 손댄 적 없음).

```bash
cp <source>/msgdef/.../foo.pb.swift <target>/autogen/msgdef/.../foo.pb.swift
```

복사 후 **반드시 아래 패치**를 적용하세요 (Swift 6 대응):

```diff
- import SwiftProtobuf
+ internal import SwiftProtobuf
```

#### 4-3. `+Constants.swift` / `+Options.swift` 머지

**절대 덮어쓰지 마세요.** 자동 생성이지만 손수정이 많습니다.

반드시 **기존 파일을 먼저 읽고**, 소스 파일과 `diff`를 확인한 뒤 변경분만 적용하세요.

**보존해야 할 기존 관행:**
- 한국어 주석 (자동 생성은 영어지만, 프로젝트 관행은 한국어)
- `Sendable` 프로토콜 준수 (자동 생성은 빠뜨리는 경우 있음)
- Swift 키워드 충돌 시 `` `internal` `` 같은 backtick escape

**자동 생성 버그:**
- `public static let internal =` ← backtick 빠짐, 수동 추가 필요
- `public struct X: OptionSet { ... }` ← `Sendable` 빠진 경우 추가

**파일 분할/머지 주의:**
- 일부 constset/optionset은 별도 파일이 아니라 `foo+Sirius.swift` 안에 합쳐져 있는 경우가 있습니다. 이 경우 **새 파일을 만들지 말고 기존 Sirius 파일에 머지**하세요.

#### 4-4. `+Sirius.swift` 머지

**절대 덮어쓰지 마세요.** 자동 생성의 퀄리티가 특히 낮은 영역입니다.

반드시 기존 파일을 먼저 읽고, diff 확인 후 변경분만 적용하세요.

**보존해야 할 기존 관행:**
- **Protobuf 타입 이름 케이싱**: 자동 생성은 `Sirius_msgdef_v1_channels_projection_Foo` (전부 lowercase) 로 출력하지만, **실제 SwiftProtobuf가 생성한 타입 이름은 `Sirius_Msgdef_V1_Channels_Projection_Foo`** (PascalCase / UpperCase) 입니다. 반드시 후자로 고치세요.
- **UUID 처리**: 자동 생성은 `SRUUID` 타입과 `try SRUUID(from: ...)` / `.toProtobufMessage()`를 사용하지만, SiriusKit에서는 Foundation `UUID`를 쓰고 `UUID(msgdef: protobufMessage.id)` / `self.id.asMsgDef()` 변환 패턴을 사용합니다.
- **SRSize/SRRect/SRPoint 초기화**: `SRRect(from: pbMessage)` — non-throwing, `try` 없이 호출.
- **`public extension MessageOpcode` 안에서는 `public` 키워드 불필요** (자동 생성은 `public static let ...`을 중복으로 붙임 → redundant 경고/에러, 제거해야 함).
- `import SwiftProtobuf` → `internal import SwiftProtobuf` 패치 필요.
- 파일 헤더 주석: 자동 생성은 `//  msgdef/v1/channels/projection/foo+Sirius.swift` 같은 경로를 넣지만, 프로젝트 관행은 basename만 (`//  foo+Sirius.swift`).
- **옵션 필드 관행**: proto3 optional 필드 (`hasX` 접근자가 있는 경우) 중 "의미상 필수"인 것은 기존 코드에서 Optional이 아닌 non-Optional로 래핑하고 있음. 새 필드를 추가할 때 의미를 판단해서 맞추세요. (예: request ID는 non-Optional, virtual display identifier는 Optional)
- **특수 로직 보존**: 예를 들어 `DisplayInfo.scaleFactor`는 `protobuf.scaleFactor == 0.0 ? 1.0 : protobuf.scaleFactor` 같은 특수 처리가 들어가 있습니다. 이런 로직은 **반드시 유지**하세요.

**자동 생성 버그 체크리스트:**
1. **중복 oneof/optional 필드**: proto3 optional 필드를 자동 생성기가 잘못 해석해서 `let foo: Type?`과 `enum Foo { case foo(Type); case none }`을 **둘 다 선언**하는 경우가 있음. pb.swift 쪽에 `hasFoo`만 있고 `OneOf_`가 없으면 **진짜 optional**입니다. 중복된 enum 버전은 삭제하고 optional만 남기세요.
2. **진짜 oneof 처리**: pb.swift에 `enum OneOf_Foo: Equatable, Sendable { ... }`이 있는 경우에만 Swift 쪽에도 `public enum OneOf_Foo: Sendable { case ...; case none }`으로 만듭니다. 패턴은 기존 `projection_source+Sirius.swift`의 `ProjectionSource.OneOf_Value` 참고.
3. **`public` accessor 누락**: SiriusKit 바깥으로 export 되어야 하는 struct 필드는 `public let` 이어야 합니다. 자동 생성이 빠뜨리는 경우 추가하세요.
4. **Opcode 할당 오류**: 자동 생성된 opcode 값이 mdproto의 `@opcode:` annotation과 일치하는지 pb.swift에서 확인하세요.

**컨테이너 분리 규칙:**
- 메시지(opcode가 있는 것)는 해당 파일의 opcode와 같이 배치합니다.
- 단순 struct (메시지가 아닌 공유 타입, 예: `DisplaySpec`)는 메시지 컨테이너 파일에 포함할지, 아니면 별도 파일로 분리할지 **기존 배치를 보고 판단**하세요. 예: `SRRect`, `SRPoint`, `SRSize`는 `SRRect.swift`로 분리되어 있음.
- `foo_manip.proto` 같은 별도 proto는 보통 `foo_manip+Sirius.swift`로 분리 (예: `winman_manip+Sirius.swift`).

### Step 5. 빌드 검증

**반드시 `SiriusKit` 디렉토리에서 `swift build`로 검증하세요.** `xcodebuild`로 NoctilucaServer 타겟을 빌드하면 broke된 호출처 때문에 실패합니다 (breaking change 있는 경우). SiriusKit 라이브러리 자체의 컴파일 성공만 먼저 확인하고, 호출처 수정은 사용자가 원하면 별도 요청으로 진행합니다.

```bash
cd $REPO_ROOT/SiriusKit && swift build
```

`Build complete!`가 나오면 동기화 1차 완료입니다.

빌드 에러가 있으면:
- 에러 메시지를 읽고 자동 생성 버그 패턴 중 하나인지 먼저 확인
- Protobuf 타입 이름, UUID 처리, public accessor, import 문 등을 재점검

### Step 6. 완료 보고

사용자에게 다음을 보고하세요:
- 복사/머지한 파일 목록
- 신규 추가된 타입 / 변경된 필드 / 삭제된 필드
- 자동 생성 버그 중 어떤 것들을 수정했는지
- 빌드 결과

## Reference (자주 참조하는 기존 파일)

- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/SRRect.swift` — 기본 지오메트리 타입 컨벤션
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/projection_source+Sirius.swift` — oneof 처리 패턴 (`OneOf_Value`)
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/general+Sirius.swift` — UUID 변환 패턴 (`UUID(msgdef:)`, `.asMsgDef()`)
- `SiriusKit/Sources/SiriusKitCore/channel/msgdef/v1/channels/projection/projection_session+Sirius.swift` — 일반적인 메시지 컨테이너 구조
