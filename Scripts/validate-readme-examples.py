#!/usr/bin/env python3
"""Compile and run the README's marked Swift examples as an external consumer."""

import argparse
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    parser.add_argument("--disable-runtime", action="store_true")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    readme = (root / "README.md").read_text()
    blocks = re.findall(
        r"<!-- readme-example: (\w+) -->\n```swift\n(.*?)\n```\n<!-- /readme-example -->",
        readme,
        re.DOTALL,
    )
    expected = {"ProtocolExample", "ClientExample", "PortableTarget", "PortableExample"}
    if len(blocks) != len(expected) or {name for name, _ in blocks} != expected:
        parser.error("README must contain exactly one marked Swift block for each quick-start example")
    examples = dict(blocks)

    mode = "compiled" if args.disable_runtime else "runtime"
    package = root / ".build" / "readme-examples" / mode
    package.mkdir(parents=True, exist_ok=True)
    names = ["ClientExample", "PortableExample"]
    if not args.disable_runtime:
        names.append("ProtocolExample")

    targets = []
    for name in names:
        directory = package / "Tests" / name
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "Example.swift").write_text(examples[name] + "\n")
        if name == "PortableExample":
            # Exercise the documented plugin configuration verbatim as well.
            targets.append(examples["PortableTarget"])
        else:
            targets.append(
                f'.testTarget(name: "{name}", dependencies: ['
                '.product(name: "TestDoubles", package: "swift-test-doubles")])'
            )

    traits = ", traits: []" if args.disable_runtime else ""
    target_list = ",\n".join(targets)
    (package / "Package.swift").write_text(
        f'''// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ReadmeExamples",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: {json.dumps(str(root))}{traits})],
    targets: [
{target_list}
    ]
)
'''
    )
    subprocess.run(
        ["swift", "test", "--package-path", str(package), "--configuration", args.configuration],
        check=True,
    )


if __name__ == "__main__":
    main()
