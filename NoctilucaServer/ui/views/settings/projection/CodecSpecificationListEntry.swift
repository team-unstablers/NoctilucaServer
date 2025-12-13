//
//  AuthMethodEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SwiftUI

import UniformTypeIdentifiers // UTType을 쓰기 위해 필요

struct CodecSpecificationListEntry: View {
    let specification: CodecSpecification
    
    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading) {
                HStack {
                    Text(specification.displayTitle)
                        .font(.headline)
                    /*
                    Text("(\(metadata.id))")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                     */
                }
                .lineLimit(1)
                Text(specification.description)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            
            /*
            Spacer()
            
            Toggle(isOn: .constant(true)) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
             */
        }
        
    }
}
