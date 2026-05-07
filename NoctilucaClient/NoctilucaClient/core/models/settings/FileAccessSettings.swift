//
//  FileAccessSettings.swift
//  NoctilucaClient
//
//  fsaccess 기능의 client (navigator, exposing peer) 측 동작 정책.
//

import Foundation

extension AppSettings {
    struct FileAccess: Category {
        /// AppleDouble sidecar (`._<name>`) 를 navigator 측에서 listDirectory
        /// 응답에서 숨기고, 신규 sidecar 생성 요청을 permissionDenied 로 거부.
        ///
        /// macOS host 가 NFS client 로 접근하면 비-HFS 볼륨이라 판단해 모든
        /// 파일 옆에 sidecar 를 적극적으로 만들려 하는데, iOS 측 storage 에
        /// 누적되고 git 등 일부 도구가 깨지는 결과를 낳는다. 이 옵션을 켜면
        /// navigator 가 자기 책임으로 sidecar 를 흡수.
        ///
        /// default: false (opt-in). 토글 변경은 다음 mount session 부터 적용.
        var hideAppleDoubleFiles: Bool = false

        init() {}

        enum CodingKeys: String, CodingKey {
            case hideAppleDoubleFiles
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            self.hideAppleDoubleFiles = container.decodeSafe(
                Bool.self,
                forKey: AppSettings.FileAccess.CodingKeys.hideAppleDoubleFiles,
                default: false
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(hideAppleDoubleFiles, forKey: .hideAppleDoubleFiles)
        }
    }
}
