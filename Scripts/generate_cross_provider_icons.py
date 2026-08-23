#!/usr/bin/env python3
"""Generate compact PNG provider artwork for the standalone cross-platform app.

The canonical SVGs remain the source of truth. CodexBarCross embeds PNGs because
SwiftCrossUI accepts raster images on every backend and the Linux installer ships
one executable without a neighboring SwiftPM resource bundle.
"""

import base64
import glob
import os
import re
import shutil
import struct
import subprocess
import tempfile


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT = os.path.join(ROOT, "Sources/CodexBarCross/GeneratedProviderIconData.swift")


def remove_volatile_png_chunks(data: bytes) -> bytes:
    """Drop ImageMagick's write-time metadata without touching pixel chunks."""
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        raise ValueError("renderer did not return a PNG")
    output = bytearray(signature)
    offset = len(signature)
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("renderer returned a truncated PNG chunk")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError("renderer returned an invalid PNG chunk length")
        chunk_type = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        volatile_text = chunk_type in (b"tEXt", b"zTXt", b"iTXt") and payload.startswith(b"date:")
        if chunk_type != b"tIME" and not volatile_text:
            output.extend(data[offset:end])
        offset = end
    return bytes(output)


def renderer() -> str:
    executable = shutil.which("magick") or shutil.which("convert")
    if executable is None:
        raise SystemExit("ImageMagick is required to regenerate cross-platform provider icons")
    return executable


def render_icon(executable: str, source: str) -> bytes:
    try:
        return render_normalized_icon(executable, source)
    except subprocess.CalledProcessError:
        pass

    thumbnailer = shutil.which("gdk-pixbuf-thumbnailer")
    if thumbnailer is not None:
        with tempfile.NamedTemporaryFile(suffix=".png") as rasterized:
            subprocess.run(
                [thumbnailer, "-s", "64", source, rasterized.name],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
            )
            return whiten_rasterized_icon(executable, rasterized.name)

    with open(source, "r", encoding="utf-8") as source_file:
        svg = source_file.read()
    # ImageMagick's SVG path parser rejects adjacent fractional arc arguments
    # accepted by browsers and AppKit (for example `a.215.215`). Preserve the
    # canonical SVG and normalize only the temporary renderer input.
    def normalize_path(match: re.Match[str]) -> str:
        path = match.group(1)
        path = re.sub(r"([A-Za-z])", r" \1 ", path)
        path = re.sub(r"(\.\d+)(?=\.)", r"\1 ", path)
        path = re.sub(r"(?<=\s)([01])([01])(?=\.)", r"\1 \2 ", path)
        return f'd="{path}"'

    svg = re.sub(r'd="([^"]+)"', normalize_path, svg)
    with tempfile.NamedTemporaryFile(suffix=".svg", mode="w", encoding="utf-8") as normalized:
        normalized.write(svg)
        normalized.flush()
        return render_normalized_icon(executable, normalized.name)


def render_normalized_icon(executable: str, source: str) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".png") as temporary:
        command = [
            executable,
            "-background",
            "none",
            source,
            "-resize",
            "56x56",
            "-gravity",
            "center",
            "-extent",
            "64x64",
            "-channel",
            "RGB",
            "-evaluate",
            "set",
            "100%",
            "+channel",
            "-strip",
            "-define",
            "png:exclude-chunk=date,time,text",
            f"PNG32:{temporary.name}",
        ]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        temporary.seek(0)
        return remove_volatile_png_chunks(temporary.read())


def whiten_rasterized_icon(executable: str, source: str) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".png") as temporary:
        subprocess.run(
            [
                executable,
                source,
                "-channel",
                "RGB",
                "-evaluate",
                "set",
                "100%",
                "+channel",
                "-strip",
                "-define",
                "png:exclude-chunk=date,time,text",
                f"PNG32:{temporary.name}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        temporary.seek(0)
        return remove_volatile_png_chunks(temporary.read())


def main() -> None:
    os.chdir(ROOT)
    executable = renderer()
    sources = sorted(glob.glob("Sources/CodexBar/Resources/ProviderIcon-*.svg"))
    lines = [
        "// Generated from Sources/CodexBar/Resources/ProviderIcon-*.svg - do not edit by hand.",
        "// Regenerate with: python3 Scripts/generate_cross_provider_icons.py",
        "// swiftlint:disable line_length",
        "",
        "enum GeneratedProviderIconData {",
        "    static let pngBase64ByResourceName: [String: String] = [",
    ]
    for source in sources:
        name = os.path.splitext(os.path.basename(source))[0]
        try:
            rendered = render_icon(executable, source)
        except subprocess.CalledProcessError as error:
            detail = error.stderr.decode("utf-8", errors="replace") if error.stderr else ""
            raise SystemExit(f"failed to render {source}: {detail}") from error
        encoded = base64.b64encode(rendered).decode("ascii")
        lines.append(f'        "{name}": "{encoded}",')
    lines.extend([
        "    ]",
        "}",
        "",
        "// swiftlint:enable line_length",
    ])
    with open(OUTPUT, "w", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")
    print(f"generated {len(sources)} cross-platform provider icons")


if __name__ == "__main__":
    main()
