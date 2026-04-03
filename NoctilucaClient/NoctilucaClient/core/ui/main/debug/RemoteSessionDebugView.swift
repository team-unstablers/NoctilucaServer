//
//  RemoteSessionDebugView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

struct RemoteSessionDebugView: View {
    @ObservedObject var viewModel: RemoteSessionDebugViewModel

    var body: some View {
        TabView {
            ChannelsDebugTab(viewModel: viewModel)
                .tabItem { Label("Channels", systemImage: "point.3.connected.trianglepath.dotted") }

            ProjectionDebugTab(viewModel: viewModel)
                .tabItem { Label("Projection", systemImage: "play.rectangle") }

            HIDIODebugTab(viewModel: viewModel)
                .tabItem { Label("HIDIO", systemImage: "keyboard") }
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}
