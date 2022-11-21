//
//  FileWatcher.swift
//  InjectionIII
//
//  Created by John Holdsworth on 08/03/2015.
//  Copyright (c) 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/HotReloading/FileWatcher.swift#36 $
//
//  Started out as an abstraction to watch files under a directory.
//  "Enhanced" to extract the last modified build log directory by
//  backdating the event stream to just before the app launched.
//

import Foundation

public class FileWatcher: NSObject {
    public typealias InjectionCallback = (
        _ filesChanged: NSArray, _ ideProcPath: String) -> Void
    static var INJECTABLE_PATTERN = try! NSRegularExpression(
        pattern: "[^~]\\.(mm?|cpp|swift|storyboard|xib)$")
    let a = 1
    static let logsPref = "HotReloadingBuildLogsDir"
    static var derivedLog =
        UserDefaults.standard.string(forKey: logsPref) {
        didSet {
            UserDefaults.standard.set(derivedLog, forKey: logsPref)
        }
    }
    static let llvmPref = "HotReloadingBuildLLVMDir"
    static var llvmLog =
        UserDefaults.standard.string(forKey: llvmPref) {
        didSet {
            UserDefaults.standard.set(derivedLog, forKey: llvmPref)
        }
    }

    var initStream: ((FSEventStreamEventId) -> Void)!
    var eventsStart =
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
    var eventsToBackdate: UInt64 = 20_00000

    var fileEvents: FSEventStreamRef! = nil
    var callback: InjectionCallback
    var context = FSEventStreamContext()

    @objc public init(roots: [String], callback: @escaping InjectionCallback) {
        self.callback = callback
        super.init()
        context.info = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        initStream = { [weak self] since in
            guard let self = self else { return }
            let fileEvents = FSEventStreamCreate(kCFAllocatorDefault,
             { (streamRef: FSEventStreamRef,
                clientCallBackInfo: UnsafeMutableRawPointer?,
                numEvents: Int, eventPaths: UnsafeMutableRawPointer,
                eventFlags: UnsafePointer<FSEventStreamEventFlags>,
                eventIds: UnsafePointer<FSEventStreamEventId>) in
                 let watcher = unsafeBitCast(clientCallBackInfo, to: FileWatcher.self)
                 // Check that the event flags include an item renamed flag, this helps avoid
                 // unnecessary injection, such as triggering injection when switching between
                 // files in Xcode.
                 for i in 0 ..< numEvents {
                     let flag = Int(eventFlags[i])
                     if (flag & (kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified)) != 0 {
                        let changes = unsafeBitCast(eventPaths, to: NSArray.self)
                         DispatchQueue.main.async {
                             watcher.filesChanged(changes: changes)
                         }
                         return
                     }
                 }
             },
             &self.context, roots as CFArray, since, 0.1,
             FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents))!
        FSEventStreamScheduleWithRunLoop(fileEvents, CFRunLoopGetMain(),
                                         "kCFRunLoopDefaultMode" as CFString)
        _ = FSEventStreamStart(fileEvents)
        self.fileEvents = fileEvents
        }
        initStream(eventsStart)
    }

    func filesChanged(changes: NSArray) {
        var changed = Set<String>()
        let eventId = FSEventStreamGetLatestEventId(fileEvents)
        if eventId != kFSEventStreamEventIdSinceNow &&
            eventsStart == kFSEventStreamEventIdSinceNow {
            eventsStart = eventId
            FSEventStreamStop(fileEvents)
            initStream(max(0, eventsStart-eventsToBackdate))
            return
        }

        for path in changes {
            guard let path = path as? String else { continue }
            if path.hasSuffix(".xcactivitylog") &&
                path.contains("/Logs/Build/") {
                if path.contains("/Swift-") {
                    Self.derivedLog = path
                } else if path.contains("/LLVM-") {
                    Self.llvmLog = path
                }
            }
            if eventId < eventsStart { continue }

            if Self.INJECTABLE_PATTERN.firstMatch(in: path,
                range: NSMakeRange(0, path.utf16.count)) != nil &&
                path.range(of: "DerivedData/|InjectionProject/|.DocumentRevisions-|main.mm?$",
                            options:.regularExpression) == nil &&
                FileManager.default.fileExists(atPath: path as String) {
                changed.insert(path)
            }
        }

        if changed.count != 0 {
            let path = ""
            callback(Array(changed) as NSArray, path)
        }
    }

    deinit {
        FSEventStreamStop(fileEvents)
        FSEventStreamInvalidate(fileEvents)
        FSEventStreamRelease(fileEvents)
    }
}
