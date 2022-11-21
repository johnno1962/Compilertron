//
//  ContentView.swift
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var state: Recompiler
    var foreground: Color { state.log != nil ? .black : .blue }
    init(state: Recompiler) {
        self.state = state
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let active = state.active {
                Text(active)
            } else {
                Text("Hello, world!")
                    .foregroundColor(.black)
            }
            if let log = state.log {
                Text("Log: \(log)")
            }
        }
        .padding()
        .textSelection(.enabled)
        .foregroundColor(foreground)
        .frame(width: 800, height: 150, alignment: .top)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(state: Recompiler())
    }
}
