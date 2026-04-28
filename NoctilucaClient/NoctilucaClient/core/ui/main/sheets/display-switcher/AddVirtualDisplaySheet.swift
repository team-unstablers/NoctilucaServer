//
//  AddVirtualDisplaySheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation

import SwiftUI

struct VirtualDisplaySpec {
    var width: Int
    var height: Int
    var refreshRate: Double
    var isHiDPI: Bool
}

struct AddVirtualDisplaySheet: View {
    @Environment(\.dismiss)
    var dismiss

    var onSubmit: (VirtualDisplaySpec) async throws -> Void

    @State
    var width: Int = 1920

    @State
    var height: Int = 1080

    @State
    var refreshRate: Double = 60.0

    @State
    var isHiDPI: Bool = false

    @State
    var isSubmitting: Bool = false

    @State
    var submissionErrorMessage: String? = nil

    var isHiDPICapable: Bool {
        width * height <= 1920 * 1080
    }

    var isSafeResolution: Bool {
        width * height <= 3840 * 2160
    }

    private var isErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { submissionErrorMessage != nil },
            set: { if !$0 { submissionErrorMessage = nil } }
        )
    }

    @ViewBuilder
    private var previewSection: some View {
        let scale: Double = min(
            240.0 / Double(width),
            240.0 / Double(height)
        )
        let scaledWidth: Double = Double(width) * scale
        let scaledHeight: Double = Double(height) * scale

        VStack {
            Spacer()
            Group {
                Text("\(String(width))x\(String(height))@\(String(refreshRate))Hz")

                if isHiDPI {
                    Text("(2x HiDPI)")
                }
            }
            .bold()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: scaledWidth, height: scaledHeight)
        .background(.white)
        .border(.black)
    }

#if os(iOS)
    @ViewBuilder
    private var quickResolutionButtons: some View {
        HStack {
            let mainScreen = UIScreen.main

            Button(String(localized: "main.display_switcher.add_virtual.fit_to_device", defaultValue: "이 기기에 맞춤")) {
                let mainSize = mainScreen.bounds.size
                width = Int(mainSize.width)
                height = Int(mainSize.height)
            }

            Button("1920x1080") {
                width = 1920
                height = 1080
            }

            Button("1366x768") {
                width = 1366
                height = 768
            }
        }
        .padding(.bottom)
    }
#endif

    @ViewBuilder
    private func numericTextField(_ value: Binding<Int>, placeholder: String) -> some View {
        let field = TextField(value: value, format: .number) {
            Text(placeholder)
        }
        .multilineTextAlignment(.trailing)
#if os(iOS)
        field.keyboardType(.numberPad)
#else
        field
#endif
    }

    @ViewBuilder
    private var specForm: some View {
        Form {
            Section {
                LabeledContent("너비") {
                    numericTextField($width, placeholder: "e.g.) 1920")
                }
                .onChange(of: width) { _, _ in
                    if !isHiDPICapable {
                        isHiDPI = false
                    }
                }
                LabeledContent("높이") {
                    numericTextField($height, placeholder: "e.g.) 1080")
                }
                .onChange(of: height) { _, _ in
                    if !isHiDPICapable {
                        isHiDPI = false
                    }
                }

                Picker(String(localized: "main.display_switcher.add_virtual.refresh_rate", defaultValue: "리프레시 레이트"), selection: $refreshRate) {
                    Text("60.0hz").tag(60.0)
                    Text("30.0hz").tag(30.0)
                    Divider()
                    Text("59.94hz").tag(59.94)
                    Text("29.97hz").tag(29.97)
                    Divider()
                    Text("48.0hz").tag(48.0)
                    Text("24.0hz").tag(24.0)
                }

                Toggle(isOn: $isHiDPI) {
                    Text("HiDPI (Retina) 켜기")
                }
                .disabled(!isHiDPICapable)
            } header: {
                Text(String(localized: "main.display_switcher.add_virtual.spec_section", defaultValue: "디스플레이 스펙"))
            } footer: {
                specFormFooter
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var specFormFooter: some View {
        if isSafeResolution {
            VStack(alignment: .leading) {
                Text(String(localized: "main.display_switcher.add_virtual.footer.note", defaultValue: "서버 상황에 따라 지정한 디스플레이 스펙이 완전히 지켜지지 않을 수 있습니다."))
                Text(String(localized: "main.display_switcher.add_virtual.footer.cleanup_note", defaultValue: "또한, 여기서 생성한 가상 디스플레이는 원격 세션 종료 이후 자동으로 제거됩니다."))
            }
        } else {
            Text(String(localized: "main.display_switcher.add_virtual.footer.over_4k_warning", defaultValue: "희망 해상도가 4K (3840 x 2160)를 초과합니다. 가상 디스플레이 생성에 실패할 수 있습니다."))
                .bold()
                .foregroundStyle(.red)
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Text("취소")
            }
            .disabled(isSubmitting)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task {
                    await submit()
                }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("생성")
                }
            }
            .disabled(isSubmitting)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                previewSection
                    .padding(.bottom)

#if os(iOS)
                quickResolutionButtons
#endif

                specForm
            }
            .padding()
            .navigationTitle(String(localized: "main.display_switcher.add_virtual.title", defaultValue: "새 가상 디스플레이"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                sheetToolbar
            }
            .alert(
                String(localized: "main.display_switcher.add_virtual.error.title", defaultValue: "가상 디스플레이 생성 실패"),
                isPresented: isErrorAlertPresented,
                presenting: submissionErrorMessage
            ) { _ in
                Button("확인", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let spec = VirtualDisplaySpec(
            width: width,
            height: height,
            refreshRate: refreshRate,
            isHiDPI: isHiDPI
        )

        do {
            try await onSubmit(spec)
            dismiss()
        } catch {
            submissionErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    @Previewable
    @State
    var shouldPresentSheet: Bool = true
    
    VStack {
        
    }
    .sheet(isPresented: $shouldPresentSheet) {
        AddVirtualDisplaySheet { spec in
            try await Task.sleep(for: .seconds(2))
            print("created virtual display: \(spec)")
        }
    }
}
