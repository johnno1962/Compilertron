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

public class CompilerWatcher: FileWatcher {

    static func findLog(which: String) -> String? {
        guard let search = popen("ls -rt ~/Library/Developer/Xcode/DerivedData/\(which)-*/Logs/Build/*.xcactivitylog", "r") else { return nil }
        defer { pclose(search) }
        return search.getLine()
    }

    @objc public override init(roots: [String], callback: @escaping InjectionCallback) {

        FileWatcher.derivedLog = Self.findLog(which: "Swift")
        FileWatcher.llvmLog = Self.findLog(which: "LLVM")

        super.init(roots: roots, callback: callback)
    }
}
