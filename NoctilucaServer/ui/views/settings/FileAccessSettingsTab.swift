//
//  FileAccessSettingsTab.swift
//  NoctilucaServer
//

import AppKit
import SwiftUI
import Inject

import SiriusKit

struct FileAccessSettingsTab: View {
    @ObserveInjection
    var inject

    @Binding
    var settings: AppSettings

    /// `enabled` 토글이 변경되어 사용자 confirm 을 기다리는 중이면 그 목표 값.
    /// nil 이면 alert 미표시.
    @State
    private var pendingEnabledChange: Bool?

    /// "다시 마운트하기" 진행 중 표시 (이중 클릭 방지용).
    @State
    private var isRemounting: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    Text(markdown: String(
                        localized: "settings.file_access.enabled.title",
                        defaultValue: "파일 시스템 액세스 사용하기"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.enabled.description",
                        defaultValue: "클라이언트의 파일 시스템에 액세스하는 `fsaccess` 채널을 켭니다.\n이 기능을 켜면 원격 클라이언트가 가지고 있는 파일을 이 Mac에서 열고, 직접 수정할 수 있습니다."
                    ))
                }
            } header: {
                Text(markdown: String(
                    localized: "settings.file_access.section_general.title",
                    defaultValue: "파일 시스템 액세스"
                ))
                Text(markdown: String(
                    localized: "settings.file_access.section_general.description",
                    defaultValue: "`fsaccess` 채널에 대한 정책을 설정합니다."
                ))
            } footer: {
                Text(markdown: String(
                    localized: "settings.file_access.section_general.footer",
                    defaultValue: "**참고**\n- 이 기능을 켜면 `noctiluca-fsaccess.localhost`라는 **NFS 서버 마운트**가 Finder에 표시됩니다.\n- 이 기능을 켠 채로 Noctiluca Server를 강제 종료하면 **Finder의 응답이 일시적으로 멈출 수 있습니다**."
                ))
            }

            if settings.fileAccess.enabled {
                Section {
                    SettingsEntry(
                        title: String(
                            localized: "settings.file_access.mount_point.title",
                            defaultValue: "마운트포인트"
                        ),
                        subtitle: String(
                            localized: "settings.file_access.mount_point.description",
                            defaultValue: "클라이언트의 원격 파일이 표시될 디렉토리입니다."
                        )
                    ) {
                        VStack(alignment: .trailing) {
                            Text(settings.fileAccess.mountPointPath)

                            HStack {
                                Button {
                                    settings.fileAccess.mountPointPath
                                        = AppSettings.FileAccess.defaultMountPointPath
                                } label: {
                                    Text(String(
                                        localized: "settings.file_access.mount_point.reset",
                                        defaultValue: "기본값으로 복원하기"
                                    ))
                                }
                                .disabled(
                                    settings.fileAccess.mountPointPath
                                        == AppSettings.FileAccess.defaultMountPointPath
                                )

                                Button {
                                    chooseMountPoint()
                                } label: {
                                    Text(String(
                                        localized: "settings.file_access.mount_point.change",
                                        defaultValue: "변경…"
                                    ))
                                }
                            }
                        }
                    }

                    SettingsEntry(
                        title: String(
                            localized: "settings.file_access.mount_point.actions.title",
                            defaultValue: "마운트포인트 관련 동작"
                        ),
                        subtitle: String(
                            localized: "settings.file_access.mount_point.actions.subtitle",
                            defaultValue: "파일 시스템 액세스 기능이 제대로 동작하지 않을 때 조치를 취할 수 있습니다."
                        )
                    ) {
                        Button {
                            Task { await remount() }
                        } label: {
                            Text(String(
                                localized: "settings.file_access.mount_point.remount",
                                defaultValue: "다시 마운트하기"
                            ))
                        }
                        .disabled(isRemounting)
                    }
                } header: {
                    Text(markdown: String(
                        localized: "settings.file_access.section_mount.title",
                        defaultValue: "마운트포인트"
                    ))
                }

                Section {
                    // 일단 constant로 두고, 수동 마운트 UI는 나중에 작업한다
                    Toggle(isOn: .constant(true)) {
                        Text(markdown: String(
                            localized: "settings.file_access.policy.auto_mount.title",
                            defaultValue: "모든 엔트리를 자동으로 마운트"
                        ))
                        Text(markdown: String(
                            localized: "settings.file_access.policy.auto_mount.description",
                            defaultValue: "클라이언트가 노출한 모든 엔트리를 자동으로 마운트합니다.\n클라이언트의 설정에 따라 접속 시마다 확인 다이얼로그가 연속해서 표시되는 경우가 있습니다."
                        ))
                    }
                    .disabled(true)

                    Toggle(isOn: $settings.fileAccess.alwaysReadOnly) {
                        Text(markdown: String(
                            localized: "settings.file_access.policy.read_only.title",
                            defaultValue: "항상 읽기 전용으로 마운트"
                        ))
                        Text(markdown: String(
                            localized: "settings.file_access.policy.read_only.description",
                            defaultValue: "클라이언트 측의 쓰기 허용 여부와 상관 없이 항상 읽기 전용으로 마운트합니다."
                        ))
                    }

                    Toggle(isOn: $settings.fileAccess.useFakeLocks) {
                        Text(markdown: String(
                            localized: "settings.file_access.policy.fake_lock.title",
                            defaultValue: "'가짜' 파일 잠금을 대신 제공하기 **(위험)**"
                        ))
                        Text(markdown: String(
                            localized: "settings.file_access.policy.fake_lock.description",
                            defaultValue: "파일을 실제로 잠궈달라고 클라이언트에게 요청하는 대신, 파일을 잠그는 척만 합니다.\n**exclusive access를 필수로 요구하는 App을 가동한 상태에서 동시 액세스가 일어나면 데이터가 파손될 위험이 있습니다!**"
                        ))
                    }
                    .onChange(of: settings.fileAccess.useFakeLocks) { _, newValue in
                        Task { await NocFSAccessHost.shared.setUseFakeLocks(newValue) }
                    }

                    Toggle(isOn: $settings.fileAccess.enableCompression) {
                        Text(markdown: String(
                            localized: "settings.file_access.policy.compression.title",
                            defaultValue: "데이터 플레인 압축 사용하기 (zstd)"
                        ))
                        Text(markdown: String(
                            localized: "settings.file_access.policy.compression.description",
                            defaultValue: "파일 read/write 페이로드를 zstd 로 압축하여 전송합니다. 클라이언트가 지원하지 않으면 자동으로 비압축으로 fallback 합니다.\n**다음 마운트부터 적용**됩니다."
                        ))
                    }

                    Toggle(isOn: $settings.fileAccess.writeBackCacheEnabled) {
                        Text(markdown: String(
                            localized: "settings.file_access.policy.write_back_cache.title",
                            defaultValue: "Write-back 캐시 사용하기"
                        ))
                        Text(markdown: String(
                            localized: "settings.file_access.policy.write_back_cache.description",
                            defaultValue: "write 작업을 곧바로 전송하지 않고, 모아두었다 한번에 전송합니다.\n특정 패턴의 쓰기 속도가 빨라질 수 있지만, 연결이 불안정한 환경에서 데이터 유실 위험이 있습니다."
                        ))
                    }
                    .onChange(of: settings.fileAccess.writeBackCacheEnabled) { _, newValue in
                        Task { await NocFSAccessHost.shared.setWriteBackCacheEnabled(newValue) }
                    }
                } header: {
                    Text(markdown: String(
                        localized: "settings.file_access.section_policy.title",
                        defaultValue: "정책"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.section_policy.description",
                        defaultValue: "파일 시스템 액세스 기능의 상세 동작에 대한 정책을 설정합니다."
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            enabledAlertTitle,
            isPresented: enabledAlertPresented,
            presenting: pendingEnabledChange,
            actions: { target in
                Button(role: .cancel) {
                    pendingEnabledChange = nil
                } label: {
                    Text(String(
                        localized: "settings.file_access.enabled.alert.cancel",
                        defaultValue: "취소"
                    ))
                }

                Button(role: target ? nil : .destructive) {
                    applyEnabledChange(to: target)
                    pendingEnabledChange = nil
                } label: {
                    Text(target
                         ? String(
                            localized: "settings.file_access.enabled.alert.confirm.on",
                            defaultValue: "켜기")
                         : String(
                            localized: "settings.file_access.enabled.alert.confirm.off",
                            defaultValue: "끄기"))
                }
            },
            message: { target in
                Text(target
                     ? String(
                        localized: "settings.file_access.enabled.alert.message.on",
                        defaultValue: "이 기능을 켜면 NFS 마운트가 \(settings.fileAccess.mountPointPath) 에 생성되고, Finder 에 표시됩니다.")
                     : String(
                        localized: "settings.file_access.enabled.alert.message.off",
                        defaultValue: "이 기능을 끄면 마운트가 즉시 해제됩니다. 현재 진행 중인 파일 작업이 있다면 중단될 수 있습니다."))
            }
        )
        .enableInjection()
    }

    // MARK: - Enabled toggle

    /// `Toggle` 에 직접 `$settings.fileAccess.enabled` 를 연결하면 사용자 confirm
    /// 전에 값이 바뀌어 버리므로, `pendingEnabledChange` 를 거치도록 가짜 binding 사용.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.fileAccess.enabled },
            set: { newValue in
                guard newValue != settings.fileAccess.enabled else { return }
                pendingEnabledChange = newValue
            }
        )
    }

    private var enabledAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingEnabledChange != nil },
            set: { presented in
                if !presented { pendingEnabledChange = nil }
            }
        )
    }

    private var enabledAlertTitle: String {
        switch pendingEnabledChange {
        case true:
            return String(
                localized: "settings.file_access.enabled.alert.title.on",
                defaultValue: "파일 시스템 액세스를 켤까요?"
            )
        case false:
            return String(
                localized: "settings.file_access.enabled.alert.title.off",
                defaultValue: "파일 시스템 액세스를 끌까요?"
            )
        case nil:
            return ""
        }
    }

    private func applyEnabledChange(to target: Bool) {
        settings.fileAccess.enabled = target

        // settings 의 autosave 가 끝나기 전이라도 사용자에게는 즉시 반영되어야 자연스럽다.
        // host actor 자체가 동시 호출 직렬화를 하므로 여기서 await 시도하지 않고 발사.
        let mountPointPath = settings.fileAccess.mountPointPath
        let useFakeLocks = settings.fileAccess.useFakeLocks
        let writeBackCacheEnabled = settings.fileAccess.writeBackCacheEnabled
        Task {
            if target {
                await NocFSAccessHost.shared.startupIfEnabled(
                    enabled: true,
                    mountPointPath: mountPointPath,
                    useFakeLocks: useFakeLocks,
                    writeBackCacheEnabled: writeBackCacheEnabled
                )
            } else {
                await NocFSAccessHost.shared.shutdownAndUnmount()
            }
        }
    }

    // MARK: - Mount point picker

    private func chooseMountPoint() {
        let panel = NSOpenPanel()
        panel.title = String(
            localized: "settings.file_access.mount_point.panel_title",
            defaultValue: "마운트포인트로 사용할 디렉토리 선택"
        )
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: (settings.fileAccess.mountPointPath as NSString).expandingTildeInPath,
            isDirectory: true
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.fileAccess.mountPointPath = Self.shortenedHomePath(of: url)
    }

    /// 사용자 home 하위 경로면 `~/...` 형태로, 아니면 절대 경로 그대로 반환.
    private static func shortenedHomePath(of url: URL) -> String {
        let absolute = url.path
        let home = NSHomeDirectory()
        if absolute == home {
            return "~"
        }
        if absolute.hasPrefix(home + "/") {
            return "~" + absolute.dropFirst(home.count)
        }
        return absolute
    }

    // MARK: - Remount

    private func remount() async {
        guard !isRemounting else { return }
        isRemounting = true
        defer { isRemounting = false }

        let mountPointPath = settings.fileAccess.mountPointPath
        let useFakeLocks = settings.fileAccess.useFakeLocks
        let writeBackCacheEnabled = settings.fileAccess.writeBackCacheEnabled
        await NocFSAccessHost.shared.shutdownAndUnmount()
        await NocFSAccessHost.shared.startupIfEnabled(
            enabled: settings.fileAccess.enabled,
            mountPointPath: mountPointPath,
            useFakeLocks: useFakeLocks,
            writeBackCacheEnabled: writeBackCacheEnabled
        )
    }
}
