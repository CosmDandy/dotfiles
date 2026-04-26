import Foundation
import Carbon

func listSources() {
    guard let list = TISCreateInputSourceList(nil, false)?
        .takeRetainedValue() as? [TISInputSource] else { return }
    for src in list {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        print(id)
    }
}

func switchTo(_ targetID: String) -> Bool {
    let filter = [kTISPropertyInputSourceID: targetID as CFString] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?
        .takeRetainedValue() as? [TISInputSource],
          let src = list.first else { return false }
    return TISSelectInputSource(src) == noErr
}

let args = CommandLine.arguments
if args.count < 2 || args[1] == "-l" {
    listSources()
} else {
    if !switchTo(args[1]) {
        fputs("Not found: \(args[1])\n", stderr)
        exit(1)
    }
}
