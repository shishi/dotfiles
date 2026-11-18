import Carbon

// Selects the enabled macOS input source with the given ID.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: select-input-source <input source ID>\n".data(using: .utf8)!)
    exit(64)
}
let filter = [kTISPropertyInputSourceID as String: CommandLine.arguments[1]] as CFDictionary
guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
      let source = sources.first else {
    FileHandle.standardError.write("select-input-source: input source is not enabled\n".data(using: .utf8)!)
    exit(1)
}
exit(TISSelectInputSource(source) == noErr ? 0 : 1)
