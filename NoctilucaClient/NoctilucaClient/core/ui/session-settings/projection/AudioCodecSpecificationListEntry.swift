//
//  AudioCodecSpecificationListEntry.swift
//  NoctilucaClient
//
//  Created by Codex on 1/30/26.
//

import Foundation
import SwiftUI

struct AudioCodecSpecificationListEntry: View {
    let specification: AudioCodecSpecification
    
    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: "waveform")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                HStack {
                    Text(specification.displayTitle)
                        .font(.headline)
                }
                .lineLimit(1)
                Text(specification.description)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
    }
}
