//
//  CodecNegotiationPolicyPicker.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import SwiftUI

struct ScreenRecorderPicker: View {
    var body: some View {
        Picker(selection: .constant(ScreenRecorderType.screenCaptureKit)) {
            ForEach(ScreenRecorderType.allCases, id: \.self) { recorderType in
                VStack(alignment: .leading) {
                    Text(recorderType.displayName)
                    Text(recorderType.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .tag(recorderType)
            }
        } label: {
            Text("화면 레코더 선택")
            
        }
        .pickerStyle(.inline)
        
    }
}
