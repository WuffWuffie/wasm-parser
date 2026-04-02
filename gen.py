from pathlib import Path
from io import StringIO
import re

def pascal_to_snake(s):
    s = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', s)
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s)
    return s.lower()

def iter_ranges(ops):
    start = prev = ops[0]

    for op in ops[1:]:
        if op[0] != prev[0] + 1:
            yield (start, prev)
            start = op
        prev = op

    yield (start, prev)

def replace_between_markers(text, new_content, start_marker, end_marker):
    lines = text.splitlines(keepends=True)
    result = ""
    out = []
    inside = False

    for line in lines:
        if start_marker in line:
            result += line
            result += new_content
            inside = True
            continue

        if end_marker in line:
            inside = False
            result += line
            continue

        if not inside:
            result += line

    return result

path = Path("wabt/include/wabt/opcode.def")
data = path.read_text()

base = []
extra = [[], [], []]

for line in data.splitlines():
    if line.startswith("WABT_OPCODE"):
        parts = list(re.findall("[^ ,()]+", line))
        a = int(parts[7], 16)
        b = int(parts[8], 16)
        first = a if a != 0 else b
        second = b if a != 0 else 0
        field_name = pascal_to_snake(parts[9])
        name = parts[10]
        if field_name in ["unreachable", "if", "else", "try", "catch", "return"]:
            field_name = f"@\"{field_name}\""
        if first >= 0xFC and first <= 0xFE:
            extra[first - 0xFC].append((second, field_name, name))
        else:
            base.append((first, field_name, name))

base.sort(key=lambda x: x[0])
for ops in extra:
    ops.sort(key=lambda x: x[0])

fields = {}

def create_offset(op):
    offset = fields[start[1]] - start[0]
    if offset == 0:
        return ""
    elif offset < 0:
        return f" - {-offset}"
    elif offset > 0:
        return f" + {offset}"

out = StringIO()


print(file=out)
print("pub const Opcode = enum(u32) {", file=out)
idx = 0
for op in base:
    fields[op[1]] = idx
    idx += 1
    print(f"    {op[1]},", file=out)
for ops in extra:
    for op in ops:
        fields[op[1]] = idx
        idx += 1
        print(f"    {op[1]},", file=out)
print("    _,", file=out)
print(file=out)
print("    pub fn name(self: Opcode) []const u8 {", file=out)
print("        return ([_][]const u8{", file=out)
for op in base:
    print(f"            {op[2]},", file=out)
for i, ops in enumerate(extra):
    for op in ops:
        print(f"            {op[2]},", file=out)
print("        })[@intFromEnum(self)];", file=out)
print("    }", file=out)
print("};", file=out)
print(file=out)
print("pub fn opcode(reader: *Io.Reader) !Opcode {", file=out)
print("    const op: u32 = try reader.takeByte();", file=out)
print("    if (op >= 252 and op <= 254) {", file=out)
print("        @branchHint(.unlikely);", file=out)
print("        const op2 = try reader.takeLeb128(u32);", file=out)
print("        return @enumFromInt(switch (op) {", file=out)
for i, ops in enumerate(extra):
    print(f"            {i + 252} => switch (op2) {{", file=out)
    for start, end in iter_ranges(ops):
        print(f"                {start[0]}...{end[0]} => op2{create_offset(start)},", file=out)
    print(f"                else => return error.InvalidOpcode,", file=out)
    print("             },", file=out)
print("            else => unreachable,", file=out)
print("        });", file=out)
print("    }", file=out)
print("    return @enumFromInt(switch (op) {", file=out)
for start, end in iter_ranges(base):
    print(f"        {start[0]}...{end[0]} => op{create_offset(start)},", file=out)
print(f"        else => return error.InvalidOpcode,", file=out)
print("    });", file=out)
print("}", file=out)
print(file=out)

source_path = Path("src/root.zig")
source = source_path.read_text()
result = out.getvalue()
result = replace_between_markers(
    source,
    result,
    "// Codegen start",
    "// Codegen end",
)
source_path.write_text(result)
