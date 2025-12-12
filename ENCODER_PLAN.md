# VideoEncoder / VTVideoEncoder 설계 계획

## 목표
- Sirius `Projection` 메시지(`Codec`, `FrameDataHeader`)를 준수하는 인코더 계층을 정의하고, macOS VideoToolbox 기반 `VTVideoEncoder`를 설계한다.
- 인코더는 입력 `CMSampleBuffer`를 받아 인코딩된 바이트와 헤더 메타(`frameID`, `PTS`, `isKeyFrame`, 길이)를 상위에 전달하며, 전송은 상위 계층이 담당한다.

## 인터페이스 설계
- 구성체: `VideoEncoderConfiguration`에 Sirius `Codec`(fourCC, quality oneof, frameRate/width/height, options), 입력 포맷(`CMFormatDescription?`), 타임스탬프 기준(PTS μs 변환), frameID 시퀀서(호출자 책임)를 포함.
- 출력: `EncodedFrame { header: FrameDataHeader, data: Data, formatDescription: CMFormatDescription? }`.
- 라이프사이클: `prepare(config) -> start() -> encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) -> stop()/flush()`.
- 델리게이트/콜백: 인코딩 성공 시 `EncodedFrame` 전달, 실패 시 오류 콜백. 상태/재진입 보호를 내부 큐로 보장.

## options 파서
- 입력 문자열을 `;`로 split 후 `key: 'value'` 패턴만 허용. key/value 앞뒤 공백 제거, value의 작은따옴표 제거. 나머지 패턴은 무시/경고.
- 결과는 `[String: String]` 딕셔너리로 반환. 지원 키: `color-format`, `hardware-acceleration`, `profile`, `level`(대소문자 구분 없이 처리). 알 수 없는 키는 저장만 하고 적용은 보류.

## VTVideoEncoder 설계
- fourCC 매핑: `AVC1`→H.264, `HVC1`→HEVC. 그 외는 미지원 오류.
- 하드웨어 가속: `hardware-acceleration`이 `true`/`false`면 `kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder`에 전달(실제 보장은 VideoToolbox 의존). 소프트웨어 강제는 베스트 에포트.
- 색상 포맷: 기본 `YUV420`→`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`. `YUV444` 요청 시 `kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange` 시도, 실패 시 `420`으로 폴백하며 경고.
- 프로파일/레벨:
  - H.264: `profile`=`baseline|main|high` 등 → `kVTProfileLevel_H264_*`; `level`이 주어지면 조합, 없으면 AutoLevel. 잘못된 값은 오류/무시 후 기본.
  - HEVC: `profile`=`main|main10|mainStill` 등 → `kVTProfileLevel_HEVC_*`; `level` 문자열을 조합해 설정, 부정확 시 경고 후 기본.
- 품질(oneof)→VTCompressionProperty:
  - ConstantBitrate: `AverageBitRate`=`bitrateKbps * 1000`, `DataRateLimits`.
  - VariableBitrate: target→`AverageBitRate`, max→`DataRateLimits`.
  - FixedQuality: `Quality` 사용, 필요 시 `ExpectedFrameRate`.
  - Lossless: 가능한 경우 무손실 프리셋 시도(`AllowOpenGOP` off, 프로파일/레벨 무손실 친화 설정, 필요 시 `EntropyMode` 등).
  - AutoQuality: 초기에는 기본 설정으로 두고 확장 포인트로 남김.
- 해상도/프레임레이트: `Codec`의 width/height/frameRate가 있으면 설정, 없으면 입력 `CMSampleBuffer` 포맷 사용. 프레임레이트 누락 시 VBR/CBR data rate 설정 시 합리적 기본값 적용.
- 인코딩 처리: VT 콜백에서 NAL/ES 바이트 추출, 키프레임 여부 판정, `CMSampleBuffer.presentationTimeStamp`→μs 변환해 `FrameDataHeader.presentationTimestamp`에 기록, 길이는 payload 길이. `frameID`는 호출자가 전달한 값을 그대로 사용.
- 오류 처리: 미지원 fourCC, 잘못된 profile/level/format 시 `prepare` 실패; 런타임 인코딩 실패는 델리게이트 오류 콜백 및 스트림 중단/리셋 정책 정의.

## 테스트/검증 계획
- 단위 테스트: options 파서(`key: 'value'` 패턴, 공백/따옴표 처리, 알 수 없는 키 보존), profile/level 문자열 매핑 검증(유효/무효 케이스).
- 스모크: 샘플 `CMSampleBuffer`로 H.264/HEVC 세션 생성 후 1~2프레임 인코딩이 성공하고 `FrameDataHeader` 필드(PTS μs, 길이) 일관성 확인.
- 로깅: 옵션 적용 결과, 하드웨어 가속 사용 여부, 포맷 폴백(YUV444→420) 등을 경고/정보 레벨로 기록.
