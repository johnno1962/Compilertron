//
//  CompilertronApp.swift
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//

import SwiftUI

let state = Recompiler()
let drives = ["/Volumes/Data2"]

@main
struct CompilertronApp: App {
    let watcher = FileWatcher(roots: [NSHomeDirectory()] + drives,
                              callback: { filesChanged, _ in
        for file in filesChanged as! [String] {
            if file.hasSuffix(".cpp") {
                state.log = FileWatcher.derivedLog
                state.queue.async {
                    state.recompile(sourceFile: file)
                }
            }
        }
    })

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
    }
}
