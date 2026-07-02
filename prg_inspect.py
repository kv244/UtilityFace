"""
Structural parser for Garmin Connect IQ .PRG files (compiled Monkey C apps).

disasm.py only does a raw ASCII-strings scan over the whole file, so it mixes
real symbol-table names with incidental byte noise and can't tell you what
kind of app this is, what permissions/entry points it declares, etc.

A .PRG is a flat sequence of top-level TLV (tag:4BE, length:4BE, data) blocks.
Section tags/layouts below are taken from the public reverse-engineering of
the format (pzl/ciqdb, Atredis Partners' Garmin VM research) -- not guessed.

This does NOT decode Monkey C VM opcodes inside the Code section: the exact
numeric opcode encoding for the ~53/55 TVM instructions isn't reliably public
(Ghidra/Kaitai processors for it exist but aren't vendored here), so the code
section is reported as a raw blob (offset/size) rather than fabricated
mnemonics.
"""
import struct
import sys

SEC_NAMES = {
    0xD000D000: "Head",
    0x6060C0DE: "EntryPoints",
    0xDA7ABABE: "Data",
    0xC0DEBABE: "Code",
    0xC0DE7AB1: "CodeTable (PC->line)",
    0xC1A557B1: "ClassTable (imports)",
    0xF00D600D: "Resources",
    0x6000DB01: "Permissions",
    0x0ECE7105: "Exceptions",
    0x5717B015: "Symbols",
    0x5E771465: "Settings",
    0xE1C0DE12: "DeveloperSignature",
    0xD011AAA5: "AppUnlock/Trial",
    0x00020833: "AppStoreSignature",
    0x00000000: "End",
}

APP_TYPES = ["WatchFace", "App", "DataField", "Widget", "BackgroundApp", "AudioProvider"]


def u16(b, o): return struct.unpack_from(">H", b, o)[0]
def u32(b, o): return struct.unpack_from(">I", b, o)[0]


def read_sections(data):
    sections = []
    i = 0
    while i + 8 <= len(data):
        tag = u32(data, i)
        length = u32(data, i + 4)
        body = data[i + 8: i + 8 + length]
        sections.append((tag, body))
        i += 8 + length
        if tag == 0:
            break
    return sections


def parse_head(body):
    ver = f"{body[1]}.{body[2]}.{body[3]}"
    out = {"ciq_api_version": ver}
    if len(body) > 12:
        out["app_trial_enabled"] = body[12] == 1
    return out


def parse_symbols(body):
    n = u16(body, 0)
    table = {}
    for i in range(n):
        off = 2 + i * 8
        sid = u32(body, off)
        soff = u32(body, off + 4)
        slen = u16(body, soff + 1)
        s = body[soff + 3: soff + 3 + slen].decode("utf-8", "replace")
        table[sid] = s
    return table


def parse_entries(body, symtab):
    n = u16(body, 0)
    out = []
    for i in range(n):
        o = 2 + i * 36
        e = body[o:o + 36]
        uuid = e[0:16].hex()
        module, symbol, label, icon, apptype = struct.unpack(">IIIII", e[16:36])
        out.append({
            "uuid": uuid,
            "type": APP_TYPES[apptype] if apptype < len(APP_TYPES) else apptype,
            "label_symbol": symtab.get(label, f"sym#{label}"),
            "entry_symbol": symtab.get(symbol, f"sym#{symbol}"),
            "module_symbol": symtab.get(module, f"sym#{module}"),
        })
    return out


def parse_permissions(body, symtab):
    n = u16(body, 0)
    out = []
    for i in range(n):
        pid = u32(body, 2 + i * 4)
        out.append(symtab.get(pid, f"perm#{pid}"))
    return out


def parse_settings(body):
    strs = {}
    vals = []
    i = 0
    while i < len(body):
        subsec = body[i:i + 4]
        i += 4
        sublen = u32(body, i)
        i += 4
        chunk = body[i:i + sublen]
        if subsec == b"\xab\xcd\xab\xcd":
            j = 0
            while j < len(chunk):
                length = u16(chunk, j)
                name = chunk[j + 2:j + 2 + length - 1].decode("utf-8", "replace")
                strs[j] = name
                j += 2 + length
        elif subsec == b"\xda\x7a\xda\x7a":
            k = 5
            while k < len(chunk):
                k += 1
                offset = u32(chunk, k)
                dt = chunk[k + 4]
                n = 1 if dt == 9 else 4
                value = chunk[k + 5:k + 5 + n]
                vals.append((offset, dt, value))
                k += 5 + n
        i += sublen
    return strs, vals


def parse_data_strings(body):
    """Walk the Data section for the 0x01 <len:u16> <bytes> string-literal
    encoding (same encoding used by the optional Symbols section)."""
    out = []
    i = 0
    n = len(body)
    while i < n - 3:
        if body[i] == 0x01:
            slen = u16(body, i + 1)
            end = i + 3 + slen
            if 0 < slen <= 4096 and end <= n:
                chunk = body[i + 3:end]
                try:
                    s = chunk.decode("utf-8")
                    if s.isprintable() and len(s.strip()) > 0:
                        out.append((i, s))
                        i = end
                        continue
                except UnicodeDecodeError:
                    pass
        i += 1
    return out


def main(path):
    with open(path, "rb") as f:
        data = f.read()

    print(f"--- {path} ({len(data)} bytes) ---\n")
    sections = read_sections(data)

    symtab = {}
    for tag, body in sections:
        if tag == 0x5717B015:
            symtab = parse_symbols(body)

    print("Section layout:")
    for tag, body in sections:
        name = SEC_NAMES.get(tag, f"UNKNOWN(0x{tag:08x})")
        print(f"  0x{tag:08x}  {name:<24} {len(body):>7} bytes")
    print()

    for tag, body in sections:
        if tag == 0xD000D000:
            print("Head:", parse_head(body))
        elif tag == 0x6060C0DE:
            print("\nEntry points:")
            for e in parse_entries(body, symtab):
                print(" ", e)
        elif tag == 0x6000DB01:
            print("\nDeclared permissions:", parse_permissions(body, symtab))
        elif tag == 0x5E771465:
            strs, vals = parse_settings(body)
            print("\nSettings string pool:", list(strs.values()))
            print("Settings values (offset,type,raw):", vals)

    if symtab:
        print(f"\nFull symbol table ({len(symtab)} entries):")
        for sid in sorted(symtab):
            print(f"  {sid:>6}: {symtab[sid]}")
    else:
        print("\n[No Symbols section present -- this is a stripped/release build; "
              "entry points, permission IDs and class-table refs above are raw "
              "numeric local symbol IDs, not resolvable to names.]")

    for tag, body in sections:
        if tag == 0xDA7ABABE:
            lits = parse_data_strings(body)
            print(f"\nString literals recovered from Data section ({len(lits)}):")
            for off, s in lits:
                print(f"  [+0x{off:04x}] {s!r}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "E6672407.PRG")
