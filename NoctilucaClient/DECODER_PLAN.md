# Projection VideoDecoder 설계안 (NoctilucaClient)

## 목표
- 서버에서 전달되는 `FrameDataHeader` + 인코딩 바이트(H.264/HEVC, AVCC length-pref) 스트림을 디코드해 화면에 표시할 수 있는 공용 디코더 계층을 정의한다.
- 인터페이스는 서버의 VideoEncoder와 유사한 라이프사이클(`prepare/start/decode/flush/stop`), 옵션 파싱, 델리게이트 기반 콜백을 제공한다.

## 입력/출력 모델
- 입력: `EncodedFrameInput { header: FrameDataHeader, data: Data, formatDescription: CMFormatDescription? }`
  - `header.presentationTimestamp`는 μs 단위 → `CMTime(value: pts, timescale: 1_000_000)`.
  - `header.isKeyFrame` true 시 디코더 재동기화에 사용.
  - `formatDescription`이 없는 경우, 첫 키프레임의 SPS/PPS(VPS)에서 생성한다.
- 출력: `DecodedFrame { pixelBuffer: CVPixelBuffer, pts: CMTime, isKeyFrame: Bool, formatDescription: CMFormatDescription }`
  - 델리게이트가 렌더러(예: Metal 뷰)로 전달.

## 인터페이스 초안
- `VideoDecoderConfiguration`:
  - `codec: Codec` (fourCC, quality, frameRate/width/height, options)
  - `parsedOptions: [String: String]` (`CodecOptionsParser` 재사용; `key: 'value'`만 허용)
  - `preferredOutputPixelFormat: OSType?` (예: 420/444)
- 프로토콜:
  - `prepare(with:)`, `start()`, `decode(_ frame: EncodedFrameInput)`, `flush()`, `stop()`
  - 델리게이트: `didDecode(frame:)`, `didFail(error:)`, `didDrop(frameID:reason:)`
- 상태 관리: prepared → started → decoding, `flush` 시 재정렬 버퍼/세션 리셋, `stop` 시 `VTDecompressionSessionInvalidate`.

## VideoToolbox 디코더 설계
- 코덱 지원: FourCC `AVC1`→H.264, `HVC1`→HEVC. 이외는 prepare 실패.
- 하드웨어 가속: `hardware-acceleration` 옵션을 `kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder`/`AllowHardwareAcceleratedVideoDecoder`에 전달(베스트 에포트).
- 색상 포맷: 기본 `kCVPixelBufferPixelFormatTypeKey=420v`; `color-format=YUV444` 요청 시 `kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange` 시도, 실패 시 420으로 폴백하고 경고.
- 프로파일/레벨: 디코더는 보통 스트림의 SPS/PPS/VPS에 따르므로 옵션은 힌트 수준; 파라미터 세트와 충돌 시 파라미터 세트를 우선. 잘못된 옵션은 무시/로그.
- 포맷 설명 생성:
  - AVCC 길이 프리픽스(1~4바이트) → `CMFormatDescriptionCreate` 시 `kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms` 사용 또는 `CMSampleBufferCreateReady`로 래핑.
  - 포맷 설명 없음 + 키프레임의 SPS/PPS(VPS) 파싱: `CMVideoFormatDescriptionCreateFromH264ParameterSets`/`CreateFromHEVCParameterSets`.
- 세션 생성: `VTDecompressionSessionCreate`에 specification/attributes를 전달하고, 출력 콜백에서 `DecodedFrame` 생성.

## 프레임 처리/버퍼링
- `FrameReorderBuffer`: `frameID`/PTS 기반으로 순서 보정(소량 버퍼) 후 디코더에 순차 입력. 버퍼 초과/역주행 시 드롭·재동기화.
- 타임라인 모드:
  - `sync`: `header.presentationTimestamp` 기준으로 재생(지터 버퍼/슬립은 상위 렌더러 책임).
  - `low-latency`: 도착 즉시 디코드, PTS는 전달하되 재생 지연 최소화.
- 드롭 정책:
  - 포맷 미상태에서 비키프레임 도착 시 드롭 후 키프레임 요청(추후 Projection 제어 채널에 적용).
  - 디코드 실패 반복 시 세션 리셋 후 다음 키프레임 기다림.

## 에러/로깅
- 중요 이벤트 로깅: 세션 생성/실패, 옵션 적용 결과, 색상 포맷 폴백, 하드웨어 가속 사용 여부, 프레임 드롭 사유.
- 오류 유형: unsupported codec, formatDescription missing, invalid NAL/length prefix, VT status 오류, payload 부족.

## 렌더러 연결 포인트
- 델리게이트가 `DecodedFrame`을 받아:
  - Metal/SwiftUI 뷰에 직접 바인딩하거나
  - 프레임 큐로 넘겨 재생 타이밍을 관리.
- 추가 기능: 스냅샷/녹화용으로 `CVPixelBuffer` → `CIImage`/`CGImage` 변환 헬퍼 제공 가능(후속 작업).

## 테스트/검증 계획
- 단위 테스트: options 파서 재사용, H.264/HEVC format description 생성기(SPS/PPS) 입력 시 세션 생성 여부.
- 스모크: 사전 녹화된 AVC1/HVC1 샘플(AVCC)로 디코드 한두 프레임 → 픽셀버퍼 유효성/키프레임 처리 확인.
- 회귀: 색상 포맷 요청(YUV444) 실패 시 420 폴백이 정상 동작하는지 확인. 
