//
//  Recompiler.swift
//  Compilertron
//
//  Created by John Holdsworth on 20/11/2022.
//
//  Greps the unzipped .xcactivetylog file for
//  the most recent build of `Swift.xcodeproj`
//  located by the FileWatcher. Extracts compile
//  command and executes it and links the object
//  into a dyanic library to load and interpose.
//

import SwiftUI

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
//        print(compilationCommand)

        DispatchQueue.main.sync {
            active = "Compiling \(sourceFile)"
        }
        var errs = popen(compilationCommand+" 2>&1", "r").output()
        guard !errs.contains("error:") else {
            commandCache[sourceFile] = nil
            DispatchQueue.main.sync {
                active? += "\n"+errs
            }
            return
        }
        commandCache[sourceFile] = compilationCommand

        let args = compilationCommand.components(separatedBy: " ")
        guard let objectFile = args.last else { return }
        let clang = args[4]
        var sdk = URL(fileURLWithPath: clang)
        for _ in 0..<5 { sdk.deleteLastPathComponent() }
        sdk.appendPathComponent("Platforms/" +
            "MacOSX.platform/Developer/SDKs/MacOSX.sdk")

        let base = URL(fileURLWithPath: sourceFile)
            .deletingPathExtension().lastPathComponent
        var dylib = URL(fileURLWithPath: COMPILERTRON_PATCHES)
            .deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dylib,
                        withIntermediateDirectories: false)
        dylib.appendPathComponent("\(base).dylib")

        let target = args.indices.first(where: {
            args[$0] == "-target" }) ?? 7
        DispatchQueue.main.sync {
            active? += "\nLinking to \(dylib.path)"
        }
        let link = """
            "\(clang)" \(args[target]) \(args[target+1]) \
            -Xlinker -dylib -isysroot "\(sdk.path)" \
            "\(objectFile)" -o "\(dylib.path)" \
            -undefined dynamic_lookup 2>&1
            """
        errs = popen(link, "r").output()
        DispatchQueue.main.sync {
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
              let compilationCommand = grep.getLine() else {
            DispatchQueue.main.sync {
                active = "Scan failed for \(sourceFile)\n\(unzipLogs)"
            }
            return nil
        }
        pclose(grep)
        return compilationCommand
    }
}

@_silgen_name("popen")
func popen(_: UnsafePointer<CChar>, _: UnsafePointer<CChar>) -> UnsafeMutablePointer<FILE>!
@_silgen_name("pclose")
@discardableResult
func pclose(_: UnsafeMutablePointer<FILE>) -> Int32

// Basic extensions on UnsafeMutablePointer<FILE> to
// read the output of a shell command line by line.
// In conjuntion with popen() this is useful as
// Task/FileHandle does not provide a convenient
// means of reading just a line.
extension UnsafeMutablePointer where Pointee == FILE {
    func getLine() -> String? {
        var count = 10_000, offset = 0
        var buffer = [CChar](repeating: 0, count: count)
        while true {
            guard let line = fgets(&buffer[offset],
                Int32(buffer.count-offset), self) else { return nil }
            offset += strlen(line)
            if buffer[offset-1] == UInt8(ascii: "\n") {
                break
            }
            count *= 2
            var next = [CChar](repeating: 0, count: count)
            strcpy(&next, buffer)
            buffer = next
        }
        buffer[offset-1] = 0
        return String(cString: buffer)
    }
    func output() -> String {
        var out = ""
        while let line = getLine() {
            out += line+"\n"
        }
        pclose(self)
        return out
    }
}
