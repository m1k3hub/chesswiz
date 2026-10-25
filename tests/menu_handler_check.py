#!/usr/bin/env python3
"""Lex literal Tcl calls without evaluating substitutions. Used by the app audit.

Reads a Tcl procedure body on stdin, emits {command argc expanded} records.
Walks braced scripts and bracket substitutions (including catch bodies).
Dynamic command names and {*} argument lists cannot be statically resolved.
"""
import sys


def scan(s):
    s = s.replace("\\\n", " ")
    calls = []
    words = []
    i = 0
    def finish():
        if words and words[0].startswith('::') and not any(c in words[0] for c in '$[\\'):
            calls.append((words[0], len(words)-1, int(any(w.startswith('{*}') for w in words))))
        words.clear()
    while i < len(s):
        if s[i] in ' \t\r':
            i += 1
            continue
        if s[i] in '\n;':
            finish()
            i += 1
            continue
        if s[i] == '#' and not words:
            end = s.find('\n', i)
            i = len(s) if end < 0 else end
            continue
        start = i
        if s[i] == '{':
            depth = 1
            i += 1
            inner = i
            while i < len(s) and depth:
                if s[i] == '\\':
                    i += 2
                    continue
                depth += (s[i] == '{') - (s[i] == '}')
                i += 1
            calls.extend(scan(s[inner:i-1]))
        else:
            quoted = s[i] == '"'
            if quoted:
                i += 1
            while i < len(s):
                if s[i] == '\\':
                    i += 2
                    continue
                if s[i] == '[':
                    depth = 1
                    i += 1
                    inner = i
                    braces = 0
                    while i < len(s) and depth:
                        if s[i] == '\\':
                            i += 2
                            continue
                        braces += (s[i] == '{') - (s[i] == '}')
                        if not braces:
                            depth += (s[i] == '[') - (s[i] == ']')
                        i += 1
                    calls.extend(scan(s[inner:i-1]))
                    continue
                if quoted and s[i] == '"':
                    i += 1
                    break
                if not quoted and s[i] in ' \t\r\n;':
                    break
                i += 1
        words.append(s[start:i])
    finish()
    return calls

if __name__ == '__main__':
    for name, argc, expanded in sorted(set(scan(sys.stdin.read()))):
        print('{%s %d %d}' % (name, argc, expanded))
