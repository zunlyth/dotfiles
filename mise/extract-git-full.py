"""Extract a Git for Windows .tar.bz2 on Windows without symlink privileges.

Windows refuses CreateSymbolicLink without admin or Developer Mode (os error 1314),
which is why mise's own tar extraction fails. This script extracts regular files
first, then materializes every symlink/hardlink as a real copy of its target.
"""
import os
import shutil
import sys
import tarfile

src, dst = sys.argv[1], sys.argv[2]

if os.path.exists(dst):
    shutil.rmtree(dst)
os.makedirs(dst, exist_ok=True)


def native(name):
    return os.path.join(dst, name.replace("/", os.sep))


with tarfile.open(src, "r:bz2") as tf:
    members = tf.getmembers()
    links = [m for m in members if m.issym() or m.islnk()]
    print(f"total members       : {len(members)}")
    print(f"symlink/hardlink    : {len(links)}")
    for m in links[:12]:
        print(f"   {m.name}  ->  {m.linkname}")

    # Pass 1: real directories and files.
    files = 0
    for m in members:
        if m.issym() or m.islnk():
            continue
        target = native(m.name)
        if m.isdir():
            os.makedirs(target, exist_ok=True)
        elif m.isfile():
            os.makedirs(os.path.dirname(target), exist_ok=True)
            fh = tf.extractfile(m)
            if fh is None:
                continue
            with open(target, "wb") as out:
                shutil.copyfileobj(fh, out)
            try:
                os.chmod(target, m.mode)
            except OSError:
                pass
            files += 1
    print(f"regular files       : {files}")

    # Pass 2: materialize links as copies (targets now exist on disk).
    ok = failed = 0
    failures = []
    for m in links:
        target = native(m.name)
        if m.issym() and not os.path.isabs(m.linkname):
            resolved = os.path.normpath(
                os.path.join(os.path.dirname(m.name), m.linkname)
            )
        else:
            resolved = m.linkname.lstrip("/\\")
        link_src = native(resolved)
        try:
            if os.path.isdir(link_src):
                shutil.copytree(link_src, target, dirs_exist_ok=True)
            elif os.path.isfile(link_src):
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copy2(link_src, target)
            else:
                failed += 1
                failures.append((m.name, m.linkname, "target missing"))
                continue
            ok += 1
        except OSError as exc:
            failed += 1
            failures.append((m.name, m.linkname, str(exc)))

    print(f"materialized copies : {ok}")
    print(f"unresolved links    : {failed}")
    for name, tgt, why in failures[:10]:
        print(f"   UNRESOLVED {name} -> {tgt} ({why})")

print("done")
