#!/usr/bin/env python3
"""
把 Swift 源文件加入 EUM.xcodeproj（本机未安装 xcodegen 时使用）。

用法：
    python3 tools/xcode_add_sources.py EUM/Core/Models+Business.swift [更多文件...]

每个文件完成四处改动：
  1. PBXFileReference 段新增文件引用
  2. PBXBuildFile 段新增编译单元
  3. 父 PBXGroup 的 children 追加（按文件名排序，父目录缺失时自动建 group）
  4. PBXSourcesBuildPhase.files 追加（按文件名排序）
"""
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "EUM.xcodeproj", "project.pbxproj")
SOURCE_ROOT_NAME = "EUM"

GROUP_RE = re.compile(
    r"([0-9A-F]{24}) /\* ([^\n]+?) \*/ = \{\s*isa = PBXGroup;(.*?)\n\t\t\};", re.S
)


def new_id(existing: set) -> str:
    while True:
        value = "".join(random.choice("0123456789ABCDEF") for _ in range(24))
        if value not in existing:
            existing.add(value)
            return value


def quote(name: str) -> str:
    """Xcode 要求含特殊字符的路径加引号"""
    return name if re.fullmatch(r"[A-Za-z0-9._-]+", name) else '"%s"' % name


def parse_groups(text):
    """gid -> (comment_name, path_or_name, children_ids, start, end)"""
    groups = {}
    for m in GROUP_RE.finditer(text):
        gid, comment, body = m.group(1), m.group(2), m.group(3)
        children = re.findall(r"([0-9A-F]{24}) /\* ", re.search(r"children = \((.*?)\);", body, re.S).group(1))
        path_m = re.search(r'path = "?([^";]+?)"?;', body)
        path = path_m.group(1) if path_m else comment
        groups[gid] = (comment, path, children, m.start(), m.end())
    return groups


def find_root(groups):
    for gid, (comment, path, _children, _s, _e) in groups.items():
        if comment == SOURCE_ROOT_NAME:
            return gid
    raise SystemExit("✗ 未找到根 group：%s" % SOURCE_ROOT_NAME)


def group_id_for_dir(text, existing_ids, rel_dir, root_id):
    """按逐级路径定位 group；缺失的中间层自动创建，返回 (text, group_id)"""
    parts = [p for p in rel_dir.split("/") if p and p != SOURCE_ROOT_NAME]
    current = root_id
    for part in parts:
        groups = parse_groups(text)
        children = groups[current][2]
        target = None
        for cid in children:
            if cid in groups and groups[cid][1] == part:
                target = cid
                break
        if target is None:
            text, target = create_group(text, existing_ids, current, part)
        current = target
    return text, current


def group_children_span(text, gid):
    """在 gid 所在块内精确定位 children = ( ... ) 的区间，返回 (start, end, inner_text)"""
    groups = parse_groups(text)
    if gid not in groups:
        raise SystemExit("✗ group 不存在：%s" % gid)
    start, end = groups[gid][3], groups[gid][4]
    block = text[start:end]
    m = re.search(r"children = \(\n(.*?)\n?\t\t\t\);", block, re.S)
    if not m:
        raise SystemExit("✗ children 定位失败：%s" % gid)
    return (start + m.start(1), start + m.end(1), m.group(1))


def set_group_children(text, gid, new_children_text):
    s, e, _ = group_children_span(text, gid)
    return text[:s] + new_children_text + text[e:]


def insert_sorted(block: str, line: str, key: str) -> str:
    lines = block.split("\n")
    idx = len(lines)
    for i, existing in enumerate(lines):
        m = re.search(r"/\* ([^\n]+?) \*/[,$]", existing)
        if m and m.group(1).lower() > key.lower():
            idx = i
            break
    lines.insert(idx, line)
    return "\n".join(lines)


def create_group(text, existing_ids, parent_gid, name):
    groups = parse_groups(text)
    parent = groups[parent_gid]
    gid = new_id(existing_ids)
    entry = (
        "\t\t%s /* %s */ = {\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        "\t\t\t);\n"
        "\t\t\tpath = %s;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};" % (gid, name, name)
    )
    text = text[: parent[4]] + "\n" + entry + text[parent[4]:]
    # 挂到父 group children（按名称排序插入）
    _, _, inner = group_children_span(text, parent_gid)
    text = set_group_children(text, parent_gid, insert_sorted(inner, "\t\t\t\t%s /* %s */," % (gid, name), name))
    return text, gid


def main(paths) -> int:
    text = open(PBX, encoding="utf-8").read()
    existing_ids = set(re.findall(r"([0-9A-F]{24})", text))
    groups = parse_groups(text)
    root_id = find_root(groups)
    changed = False

    for raw in paths:
        rel = raw.replace(ROOT + "/", "").lstrip("./")
        parts = rel.split("/")
        filename = parts[-1]
        if not filename.endswith(".swift"):
            print("跳过非 Swift 文件：%s" % rel)
            continue
        if re.search(r"/\* %s \*/" % re.escape(filename), text):
            print("已跳过（已存在）：%s" % rel)
            continue

        rel_dir = "/".join(parts[:-1])
        text, gid = group_id_for_dir(text, existing_ids, rel_dir, root_id)

        file_id = new_id(existing_ids)
        build_id = new_id(existing_ids)
        token = quote(filename)

        text = text.replace(
            "/* End PBXFileReference section */",
            "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            "path = %s; sourceTree = \"<group>\"; };\n/* End PBXFileReference section */" % (file_id, filename, token),
            1,
        )
        text = text.replace(
            "/* End PBXBuildFile section */",
            "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
            "/* End PBXBuildFile section */" % (build_id, filename, file_id, filename),
            1,
        )

        # 父 group children
        _, _, inner = group_children_span(text, gid)
        text = set_group_children(
            text, gid, insert_sorted(inner, "\t\t\t\t%s /* %s */," % (file_id, filename), filename)
        )

        # Sources 编译阶段
        sm = re.search(
            r"(/\* Begin PBXSourcesBuildPhase section \*/.*?files = \(\n)(.*?)(\n\t\t\t\);"
            r".*?/\* End PBXSourcesBuildPhase section \*/)",
            text,
            re.S,
        )
        if not sm:
            print("✗ 未找到 PBXSourcesBuildPhase")
            return 1
        text = (
            text[: sm.start()]
            + sm.group(1)
            + insert_sorted(sm.group(2), "\t\t\t\t%s /* %s in Sources */," % (build_id, filename), filename + " in Sources")
            + sm.group(3)
            + text[sm.end():]
        )

        print("✓ 已加入 target：%s" % rel)
        changed = True

    if changed:
        open(PBX, "w", encoding="utf-8").write(text)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    sys.exit(main(sys.argv[1:]))
