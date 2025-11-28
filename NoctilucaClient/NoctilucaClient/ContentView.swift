//
//  ContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import SwiftUI
import Combine

import SiriusKitClient

class FIXME__ContentViewModel: ObservableObject {
    @Published
    var serverAddress: String = ""
    
    var client: NoctilucaClient?
    
    init() {
        
    }
    
    func connect() async throws {
        let host = serverAddress.split(separator: ":").first
        let port = UInt16(serverAddress.split(separator: ":").last ?? "") ?? 12345
        
        guard let host else {
            return
        }
        
        let result = SiriusClientBuilder()
            .useTransportProtocol(.quic(host: String(host), port: port))
            .useFeatureProvider(NoctilucaFeatureProvider())
            .build()
        
        let session = try result.get()
        let client = NoctilucaClient(session)
        
        self.client = client
        
        try await client.setup()
        try await client.startup()
    }
    
}

struct ContentView: View {
    @StateObject
    var viewModel = FIXME__ContentViewModel()
    
    var body: some View {
        HStack {
            TextField("서버 주소", text: $viewModel.serverAddress)
            Button("연결") {
                Task {
                    do {
                        try await viewModel.connect()
                    } catch {
                        print("Error connecting to server: \(error)")
                    }
                }
            }
            
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
