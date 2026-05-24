//
//  FSAccessIOSDocumentsProvider.swift
//  NoctilucaClient
//
//  iOS 전용: 앱 컨테이너 `Documents/fsaccess` 디렉토리를 단일 fsaccess entry 로 노출.
//  Files.app 'Noctiluca Navigator' 아래에서 사용자가 직접 파일을 넣고 뺄 수 있고,
//  원격 호스트는 같은 디렉토리에 NFS 로 마운트해 접근한다.
//

#if os(iOS)
import Foundation

enum FSAccessIOSDocumentsProvider {
    /// 호스트 측 mount session 에서 표시될 entry 이름.
    static let entryName = "Noctiluca Navigator"

    /// 토글 ON/OFF 와 관계없이 동일 path 에 대해 일관된 entryId 를 부여하기 위한 deterministic UUID.
    static let stableEntryId: UUID = UUID(uuidString: "F5ACCE55-1057-4F1E-9DC0-DEBADF00DDAD")!

    /// `<Documents>/fsaccess` 경로. Documents 컨테이너 자체를 못 얻으면 nil.
    static var directoryURL: URL? {
        guard let docs = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return docs.appendingPathComponent("fsaccess", isDirectory: true)
    }

    /// 디렉토리가 없으면 생성하고 URL 을 반환. 실패하면 nil.
    @discardableResult
    static func ensureDirectory() -> URL? {
        guard let url = directoryURL else { return nil }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// 앱 시작 시 호출. fsaccess 디렉토리를 보장하고 안내용 README 를 한 번 작성한다.
    /// (Files.app 의 'On My iPhone' 위치는 Documents 가 비어있으면 표시되지 않음)
    static func bootstrap() {
        guard let dir = ensureDirectory() else { return }
        let readme = dir.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let body = """
            이 폴더는 Noctiluca Navigator 의 fsaccess 노출 디렉토리입니다.

            세션 설정에서 '이 기기의 파일 노출하기' 가 켜진 동안, 이 폴더의
            파일이 원격 호스트에서 접근 가능한 상태가 됩니다.

            노출하지 않을 파일은 다른 폴더에 보관해 주세요.
            """
            try? body.data(using: .utf8)?.write(to: readme, options: [.atomic])
        }
    }

    /// 토글 + ACL 을 반영한 단일 FSAllowedEntry. 토글 OFF 거나 디렉토리 부트스트랩 실패 시 nil.
    static func currentEntry(settings: SessionSettings) -> SessionSettings.FSAllowedEntry? {
        guard settings.transfer.fsExposeIOSDocuments else { return nil }
        guard let url = ensureDirectory() else { return nil }
        return SessionSettings.FSAllowedEntry(
            id: stableEntryId,
            name: entryName,
            path: url.path,
            acl: settings.transfer.fsIOSDocumentsACL
        )
    }
}
#endif
