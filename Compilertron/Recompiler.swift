//
//  Recompiler.swift
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//
//  Greps the unzipped .xcactivitylog file for
//  the most recent build of `Swift.xcodeproj`
//  located by the FileWatcher. Extracts compile
//  command and executes it and links the object
//  into a dyanic library to load and interpose.
//

import SwiftUI
import Cocoa
import Popen

class Recompiler: ObservableObject {
    @Published var log: String?
    @Published var active: String?
    let objectFile = "/tmp/compilertron.o"
    let diskCache = "/tmp/compilertron.plist"
    lazy var commandCache = NSMutableDictionary(contentsOfFile: diskCache) ??
                            NSMutableDictionary()
    let queue = DispatchQueue(label: "recompilations")
    var lastError: String?

    func recompile(sourceFile: String) {
        guard var compilationCommand =
                commandCache[sourceFile] as? String ??
                FileWatcher.derivedLog.flatMap({
                    findCompile(sourceFile: sourceFile, log: $0) }) ??
                FileWatcher.llvmLog.flatMap({
                    findCompile(sourceFile: sourceFile, log: $0) })
                else { return }

        DispatchQueue.main.sync {
            active = "Compiling \(sourceFile)"
            NSApp.dockTile.badgeLabel = "🍿"
        }

        compilationCommand = compilationCommand
            .replacingOccurrences(
                of: #" -o [^\s\\]*(?:\\.[^\s\\]*)* "#,
                with: " -o \(objectFile) ",
                options: .regularExpression)
            .replacingOccurrences(of: "-fdiagnostics-color", with: "")
        print(compilationCommand)

        let errs = popen(compilationCommand+" 2>&1", "r")
            .readAll(close: true)
        guard !errs.contains("error:") else {
            if lastError == sourceFile {
                commandCache.removeObject(forKey: sourceFile)
                commandCache.write(toFile: diskCache, atomically: true)
            } else {
                lastError = sourceFile
            }
            DispatchQueue.main.sync {
                active? += "\n"+errs
                NSApp.activate(ignoringOtherApps: true)
//                let alert = NSAlert()
//                alert.messageText = "Compilertron"
//                alert.informativeText = """
//                    Compilaton failed. If it fails again, \
//                    the compilation command entry for \
//                    this source file will be removed.
//                    """
//                alert.alertStyle = NSAlert.Style.warning
//                alert.addButton(withTitle: "OK")
//                _ = alert.runModal()
                NSApp.dockTile.badgeLabel = "🤷"
            }
            return
        }
        lastError = nil

        if commandCache[sourceFile] as? String != compilationCommand {
            commandCache[sourceFile] = compilationCommand
            commandCache.write(toFile: diskCache, atomically: true)
        }
        let fileName = URL(fileURLWithPath: sourceFile)
            .deletingPathExtension().lastPathComponent
        linkDylib(named: fileName, compilationCommand)
    }

    func linkDylib(named: String, _ compilationCommand: String) {
        let args = compilationCommand
            .components(separatedBy: ";").last?
            .components(separatedBy: " ") ?? []
        let clangIndex = args.firstIndex(where: {$0.contains("clang")}) ?? 2
        var sdk = URL(fileURLWithPath: args[clangIndex])
        for _ in 0..<5 { sdk.deleteLastPathComponent() }
        sdk.appendPathComponent("Platforms/" +
            "MacOSX.platform/Developer/SDKs/MacOSX.sdk")

        var dylib = URL(fileURLWithPath: COMPILERTRON_PATCHES)
            .deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dylib,
                        withIntermediateDirectories: false)
        dylib.appendPathComponent("\(named).dylib")

        let target = args.firstIndex(where: {$0 == "-target"}) ?? 7
        DispatchQueue.main.sync {
            active? += "\nLinking to \(dylib.path)"
        }

        let linkCommand = """
            "\(args[clangIndex])" \(args[target]) \(args[target+1]) \
            -Xlinker -dylib -isysroot "\(sdk.path)" \
            "\(objectFile)" -o "\(dylib.path)" \
            -undefined dynamic_lookup -Xlinker -interposable 2>&1
            """
        let errs = popen(linkCommand, "r").readAll()
        DispatchQueue.main.sync {
            NSApp.dockTile.badgeLabel = nil
            active? += "\n\(errs)Complete."
            state.log = nil
        }
    }

    func findCompile(sourceFile: String, log: String) -> String? {
        DispatchQueue.main.sync {
            active = "Scanning for \(sourceFile)"
            state.log = log
        }
        let logsDir = URL(fileURLWithPath: log)
            .deletingLastPathComponent().path
        let unzipLogs = """
            cd "\(logsDir)" && for log in `/bin/ls -t *.xcactivitylog`; do \
                if /usr/bin/gunzip <$log | /usr/bin/tr '\\r' '\\n' | \
                    /usr/bin/grep  -E "    cd |    export | -c \(sourceFile)"; \
                then echo $log && exit; fi; done
            """
        let grep = popen(unzipLogs, "r")
        defer { _ = pclose(grep) }

        while true {
            guard var compilationCommand = grep?.readLine() else {
                DispatchQueue.main.sync {
                    active = "Scan failed for \(sourceFile)\n\(unzipLogs)"
                }
                return nil
            }
            if !compilationCommand.contains(sourceFile) {
                continue
            }
            if let preamble = compilationCommand.firstIndex(of: "]") {
                compilationCommand = String(compilationCommand
                    .suffix(from: compilationCommand.index(after: preamble)))
            }

            var environment = ""
            while let line = grep?.readLine(strippingNewline: true) {
                if line.contains("UID") { continue }
                if line.hasPrefix("    cd ") ||
                    line.hasPrefix("    export ") {
                    environment += line+";"
                } else if environment != "" {
                    break
                }
            }

            return environment + compilationCommand
        }
    }
}
