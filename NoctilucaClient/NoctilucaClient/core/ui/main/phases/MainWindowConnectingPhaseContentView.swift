//
//  MainWindowConnectingPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MainWindowConnectingPhaseContentView: View {
    @EnvironmentObject
    var viewModel: SessionWindowViewModel

    @State
    var isLogAreaVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading) {

                Spacer()

                HStack(spacing: 0) {
                    Text("연결 중")
                        .font(.largeTitle)
                        .fontWeight(.light)
                }
                .padding(.bottom, 2)

                Text("\(self.viewModel.endpointURL)에 연결하고 있습니다...")
                    .padding(.bottom, 32)

                Spacer()


                VStack {
                }
                .frame(maxWidth: .infinity)
            }


            /*
                Text(
                    self.viewModel.connectionLog.joined(separator: "\n")
                )
                .font(.system(size: 12).monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
#if os(macOS)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(NSColor.windowBackgroundColor),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(isLogAreaVisible ? 0.0 : 1.0)
                }
#endif
                .onHover { hoverState in
                    if hoverState {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = true
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = false
                        }
                    }

                }
             */
        }
        .padding(24)
    }
}

#Preview("ConnectingPhase") {
    let viewModel = SessionWindowViewModel()

    MainWindowConnectingPhaseContentView()
        .environmentObject(viewModel)
        .frame(minWidth: 640, minHeight: 480)
}
