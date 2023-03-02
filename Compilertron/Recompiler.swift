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
    var commandCache = [String: String]()
    let queue = DispatchQueue(label: "recompilations")

    func recompile(sourceFile: String) {
        guard let compilationCommand = commandCache[sourceFile] ??
                FileWatcher.derivedLog.flatMap({
                    findCompile(sourceFile: sourceFile, log: $0) }) ??
                FileWatcher.llvmLog.flatMap({
                    findCompile(sourceFile: sourceFile, log: $0) })
                else { return }

        DispatchQueue.main.sync {
            active = "Compiling \(sourceFile)"
            NSApp.dockTile.badgeLabel = "🍿"
        }
        let errs = popen(compilationCommand+" 2>&1", "r").readAll()
        guard !errs.contains("error:") else {
            commandCache[sourceFile] = nil
            DispatchQueue.main.sync {
                NSApp.dockTile.badgeLabel = "🤷"
                active? += "\n"+errs
            }
            return
        }
        commandCache[sourceFile] = compilationCommand

        let fileName = URL(fileURLWithPath: sourceFile)
            .deletingPathExtension().lastPathComponent
        linkDylib(named: fileName, compilationCommand)
    }

    func linkDylib(named: String, _ compilationCommand: String) {
        let args = compilationCommand.components(separatedBy: " ")
        guard let objectFile = args.last else { return }

        let clang = args[4]
        var sdk = URL(fileURLWithPath: clang)
        for _ in 0..<5 { sdk.deleteLastPathComponent() }
        sdk.appendPathComponent("Platforms/" +
            "MacOSX.platform/Developer/SDKs/MacOSX.sdk")

        var dylib = URL(fileURLWithPath: COMPILERTRON_PATCHES)
            .deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dylib,
                        withIntermediateDirectories: false)
        dylib.appendPathComponent("\(named).dylib")

        let target = args.indices.first(where: {
            args[$0] == "-target" }) ?? 7
        DispatchQueue.main.sync {
            active? += "\nLinking to \(dylib.path)"
        }

        let linkCommand = """
            "\(clang)" \(args[target]) \(args[target+1]) \
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
        let unzipLogs = """
            gunzip <\(log) | tr '\\r' '\\n' | grep ' -c \(sourceFile) '
            """
        guard let grep = popen(unzipLogs, "r"),
              let compilationCommand = grep.readLine() else {
            DispatchQueue.main.sync {
                active = "Scan failed for \(sourceFile)\n\(unzipLogs)"
            }
            return nil
        }
        pclose(grep)
        return compilationCommand
    }
}
