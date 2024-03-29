//
//  CompilertronApp.swift
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//

import SwiftUI
import Popen

let state = Recompiler()
let drives = ["/Volumes/Data2"]

@main
struct CompilertronApp: App {
    let watcher = CompilerWatcher(roots: [NSHomeDirectory()] + drives,
                                  callback: { filesChanged, _ in
        for file in filesChanged as! [String] {
            if file.hasSuffix(".cpp") {
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

class CompilerWatcher: FileWatcher {

    static func findLog(which: String) -> String? {
        guard let search = popen("ls -t ~/Library/Developer/Xcode/DerivedData/\(which)-*/Logs/Build/*.xcactivitylog", "r") else { return nil }
        defer { _ = pclose(search) }
        return search.readLine()
    }

    @objc override init(roots: [String], callback: @escaping InjectionCallback) {

        // More robust means of finding build logs.
        FileWatcher.derivedLog = Self.findLog(which: "Swift")
        FileWatcher.llvmLog = Self.findLog(which: "LLVM")

        super.init(roots: roots, callback: callback)
    }
}
