#!/usr/bin/env swift
import Foundation

// Mirror of TranscriptMerge.isUsable — kept in sync by smoke_check compiling both.
// This file is a standalone red/green loop for the "short speech dropped" bug.

func isUsable(_ piece: String) -> Bool {
    let piece = piece.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !piece.isEmpty else { return false }
    if piece.unicodeScalars.contains(where: { $0.value >= 0x0400 }) {
        return piece.count >= 1
    }
    return piece.count >= 2
}

var failed = 0
func expect(_ name: String, _ cond: Bool) {
    if cond {
        print("ok  \(name)")
    } else {
        print("FAIL \(name)")
        failed += 1
    }
}

// Old bug: piece.count > 2 dropped these
expect("keep 你好", isUsable("你好"))
expect("keep 好的", isUsable("好的"))
expect("keep Hi", isUsable("Hi"))
expect("drop empty", !isUsable("  "))
expect("drop single latin letter", !isUsable("a"))
expect("keep Yes", isUsable("Yes"))

if failed > 0 {
    FileHandle.standardError.write(Data("\(failed) failed\n".utf8))
    exit(1)
}
print("all ok")
