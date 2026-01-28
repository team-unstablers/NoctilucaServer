# 오디오 프로젝션 기능 구현 계획

## 개요
`ProjectionSession` (비디오)를 참고하여 `AudioProjectionSession`을 완성하고, Opus와 PCM(G.711) 오디오 인코딩을 지원하는 기능을 구현한다.

## 현재 상태

### 완료됨
- **SiriusKit/AudioCodec**: OPUS, PCMU, PCMA FourCC 정의
- **AudioProjectionRequest, AudioSessionCreatedEvent 등**: 메시지 정의 완료
- **ScreenCaptureKitAudioRecorder**: CMSampleBuffer로 오디오 프레임 수신 구현
- **ProjectionChannel.handleAudioProjectionRequest()**: 기본 흐름 (스켈레톤)

### 미구현
- **AudioEncoder 프로토콜 및 구현체**: 없음
- **AudioProjectionSession**: encoder 부분 주석 처리 상태
- **ProjectionDataChannel.send(audioFrame:)**: 없음

---

## 구현 항목

### 1단계: 기반 인프라

#### 1.1 AudioEncoder 프로토콜 생성
**파일**: `NoctilucaServer/feature/projection/encoder/AudioEncoder.swift`

```swift
struct AudioEncoderConfiguration {
    let codec: SiriusKit.AudioCodec
    let inputFormatDescription: CMAudioFormatDescription?
}

struct EncodedAudioFrame {
    let header: FrameDataHeader
    let data: Data
}

enum AudioEncoderEvent {
    case frameEncoded(EncodedAudioFrame)
    case errorOccurred(Error)
    case stopped
}

protocol AudioEncoder: AnyObject {
    var events: AsyncStream<AudioEncoderEvent> { get }

    func prepare(with configuration: AudioEncoderConfiguration) throws
    func start() throws
    func encode(sampleBuffer: CMSampleBuffer) throws
    func flush() throws
    func stop() throws
}
```

VideoEncoder와의 차이:
- frameID 자동 생성 (PTS 기반)
- 키프레임 강제 불필요
- Parameter Set 불필요

#### 1.2 ProjectionDataChannel 오디오 전송 메서드
**파일**: `NoctilucaServer/feature/projection/ProjectionDataChannel.swift`

`send(audioFrame:)` 메서드 추가. 비디오와 동일한 와이어 포맷 사용:
```
<headerLen: u32><frameLen: u32><headerBytes><frameBytes>
```
opcode는 기존 `.frameData` 재사용 (채널이 분리되므로 구분 가능)

---

### 2단계: PCM 인코더 (간단한 것 먼저)

#### 2.1 PCMAudioEncoder 구현
**파일**: `NoctilucaServer/feature/projection/encoder/PCMAudioEncoder.swift`

- PCMU (G.711 mu-law), PCMA (G.711 A-law) 지원
- AudioToolbox의 `AudioConverterRef` 사용
- 리샘플링: 48kHz → 8kHz, 스테레오 → 모노 (G.711 요구사항)

---

### 3단계: Opus 인코더

#### 3.1 AVAudioConverter 기반 Opus 인코딩
외부 libopus 의존성 없이 **AVFoundation의 AVAudioConverter**를 사용하여 구현.
- macOS 11.0+에서 `kAudioFormatOpus` 포맷 지원
- `AVAudioConverter`로 PCM → Opus 변환

#### 3.2 OpusAudioEncoder 구현
**파일**: `NoctilucaServer/feature/projection/encoder/OpusAudioEncoder.swift`

구현 방식:
```swift
// 입력 포맷: PCM Float32 (ScreenCaptureKit 출력)
let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: 48000,
                                 channels: 2,
                                 interleaved: false)!

// 출력 포맷: Opus
var outputDesc = AudioStreamBasicDescription(
    mSampleRate: 48000,
    mFormatID: kAudioFormatOpus,
    mFormatFlags: 0,
    mBytesPerPacket: 0,
    mFramesPerPacket: 960,  // 20ms @ 48kHz
    mBytesPerFrame: 0,
    mChannelsPerFrame: 2,
    mBitsPerChannel: 0,
    mReserved: 0
)
let outputFormat = AVAudioFormat(streamDescription: &outputDesc)!

let converter = AVAudioConverter(from: inputFormat, to: outputFormat)!
```

주요 포인트:
- Opus 프레임 크기: 20ms @ 48kHz = 960 samples (기본)
- 내부 버퍼링 필요 (SCK 출력 버퍼 크기와 맞지 않을 수 있음)
- 비트레이트 설정: `converter.bitRate` 프로퍼티 사용

---

### 4단계: AudioProjectionSession 완성

**파일**: `NoctilucaServer/feature/projection/AudioProjectionSession.swift`

주요 변경:
1. `var encoder: any AudioEncoder` 프로퍼티 추가
2. `encoderEventLoopTask` 주석 해제 및 구현
3. `prepare()`: 코덱에 따라 인코더 선택
   - `.opus` → `OpusAudioEncoder`
   - `.pcmu`, `.pcma` → `PCMAudioEncoder`
4. `audioRecorder(didCaptureFrame:)`에서 encoder로 전달
5. `stop()`: 정리 로직 주석 해제

---

### 5단계: ProjectionChannel 개선 (선택)

**파일**: `NoctilucaServer/feature/projection/ProjectionChannel.swift`

현재 `handleAudioProjectionRequest()`는 첫 번째 코덱을 그대로 사용. 개선 가능:
- 서버 지원 코덱 목록과 클라이언트 선호 코덱 매칭
- 실패 시 `AudioSessionCreationFailedEvent` 전송

---

## 파일 구조

```
NoctilucaServer/feature/projection/
├── encoder/
│   ├── VideoEncoder.swift (기존)
│   ├── VTVideoEncoder.swift (기존)
│   ├── AudioEncoder.swift (신규)
│   ├── OpusAudioEncoder.swift (신규)
│   └── PCMAudioEncoder.swift (신규)
├── audio-recorder/
│   ├── AudioRecorder.swift (기존)
│   └── ScreenCaptureKitAudioRecorder.swift (기존)
├── ProjectionSession.swift (기존)
├── AudioProjectionSession.swift (수정)
├── ProjectionChannel.swift (수정)
└── ProjectionDataChannel.swift (수정)
```

---

## Critical Files

| 역할 | 경로 |
|------|------|
| AudioEncoder 패턴 참고 | `NoctilucaServer/feature/projection/encoder/VideoEncoder.swift` |
| 완성 대상 | `NoctilucaServer/feature/projection/AudioProjectionSession.swift` |
| 오디오 전송 추가 | `NoctilucaServer/feature/projection/ProjectionDataChannel.swift` |
| 요청 핸들링 | `NoctilucaServer/feature/projection/ProjectionChannel.swift` |
| AudioCodec 정의 | `SiriusKit/channel/msgdef/v1/channels/projection/projection_audio+Sirius.swift` |

---

## 검증 계획

1. **빌드 테스트**: 컴파일 오류 없이 빌드되는지 확인
2. **단위 테스트**: PCMAudioEncoder가 CMSampleBuffer를 올바르게 인코딩하는지
3. **통합 테스트**:
   - 클라이언트에서 AudioProjectionRequest 전송
   - 서버에서 AudioSessionCreatedEvent 수신 확인
   - 오디오 프레임이 DataChannel로 전송되는지 로그 확인
4. **재생 테스트**: 클라이언트에서 오디오 디코딩 후 재생 (클라이언트 구현 필요)

---

## 주의사항

- **프레임 드랍**: 당장은 구현 안 함 (사용자 요청)
- **리샘플링**: G.711은 8kHz 전용이므로 반드시 필요
- **Opus 인코딩**: AVAudioConverter 사용 (외부 의존성 없음, macOS 11.0+)
- **QualityPlanner**: 오디오용은 당장 구현 안 함 (비디오와 달리 단순)
