#!/usr/bin/env python3
"""Regenerate standalone tray PNG/ICO data from CodexBar's original native-port artwork."""

import base64
import os
import shutil
import subprocess
import tempfile


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT = os.path.join(ROOT, "Sources/CodexBarCross/GeneratedTrayIconData.swift")

# Exact 32 px assets from the original Linux native port. Keeping their source bytes here
# makes the generated Swift standalone while retaining one reproducible source of truth.
PNG_BASE64 = {
    "loading": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAACNUExURQAAAFyo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/1yo/////5hd6dEAAAAtdFJOUwAIZN/gEg6Hhgw/Pv5RQ+I04wMRZeQENeEBiFBFUvzdZooPQf1C+mgNZxM2OP2ih4AAAAABYktHRC5U0xCHAAAAB3RJTUUH6ggODwQw4k0cIwAAAPtJREFUOMutk8kWgjAMRSsCrSAyCCJFBJyn/v/veWzLkAaPG7NKXi5tmgRC/mgzay6U2ZaD0y4VY2MLI+8J03yQtwQ260d+TPidtGTBKqBL8xZXx2GkhSjWiqtiXT9L+iMTpiUZOSqgoGr90frjp9LNNgBI4qHOULq50ZhIqtuPq+ovDKBQb+kBjnpPIVAioITACgE7CFQIqCDAEMAhsEev2PdALb3IAHKp1sOsbdjJjepk83UWqgLhjAM+nFFoqVXhQU8/6+aRh3AfyLFboRMPzhW94L1tJneyGdU0tbVXULWP8p7RmBsH6dYlyJx792/W6YN8sdnTe0HlDaA+SdzEVWZsAAAAAElFTkSuQmCC",
    "quota-green": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAACNUExURQAAAFfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjVfWjf///6/qIPkAAAAtdFJOUwAIZN/gEg6Hhgw/Pv5RQ+I04wMRZeQENeEBiFBFUvzdZooPQf1C+mgNZxM2OP2ih4AAAAABYktHRC5U0xCHAAAAB3RJTUUH6ggODwQw4k0cIwAAAPtJREFUOMutk8kWgjAMRSsCrSAyCCJFBJyn/v/veWzLkAaPG7NKXi5tmgRC/mgzay6U2ZaD0y4VY2MLI+8J03yQtwQ260d+TPidtGTBKqBL8xZXx2GkhSjWiqtiXT9L+iMTpiUZOSqgoGr90frjp9LNNgBI4qHOULq50ZhIqtuPq+ovDKBQb+kBjnpPIVAioITACgE7CFQIqCDAEMAhsEev2PdALb3IAHKp1sOsbdjJjepk83UWqgLhjAM+nFFoqVXhQU8/6+aRh3AfyLFboRMPzhW94L1tJneyGdU0tbVXULWP8p7RmBsH6dYlyJx792/W6YN8sdnTe0HlDaA+SdzEVWZsAAAAAElFTkSuQmCC",
    "quota-amber": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAACNUExURQAAAP+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf+3Tf///x01N/AAAAAtdFJOUwAIZN/gEg6Hhgw/Pv5RQ+I04wMRZeQENeEBiFBFUvzdZooPQf1C+mgNZxM2OP2ih4AAAAABYktHRC5U0xCHAAAAB3RJTUUH6ggODwQw4k0cIwAAAPtJREFUOMutk8kWgjAMRSsCrSAyCCJFBJyn/v/veWzLkAaPG7NKXi5tmgRC/mgzay6U2ZaD0y4VY2MLI+8J03yQtwQ260d+TPidtGTBKqBL8xZXx2GkhSjWiqtiXT9L+iMTpiUZOSqgoGr90frjp9LNNgBI4qHOULq50ZhIqtuPq+ovDKBQb+kBjnpPIVAioITACgE7CFQIqCDAEMAhsEev2PdALb3IAHKp1sOsbdjJjepk83UWqgLhjAM+nFFoqVXhQU8/6+aRh3AfyLFboRMPzhW94L1tJneyGdU0tbVXULWP8p7RmBsH6dYlyJx792/W6YN8sdnTe0HlDaA+SdzEVWZsAAAAAElFTkSuQmCC",
    "quota-red": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAACNUExURQAAAO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUO9TUP///50btxcAAAAtdFJOUwAIZN/gEg6Hhgw/Pv5RQ+I04wMRZeQENeEBiFBFUvzdZooPQf1C+mgNZxM2OP2ih4AAAAABYktHRC5U0xCHAAAAB3RJTUUH6ggODwQw4k0cIwAAAPtJREFUOMutk8kWgjAMRSsCrSAyCCJFBJyn/v/veWzLkAaPG7NKXi5tmgRC/mgzay6U2ZaD0y4VY2MLI+8J03yQtwQ260d+TPidtGTBKqBL8xZXx2GkhSjWiqtiXT9L+iMTpiUZOSqgoGr90frjp9LNNgBI4qHOULq50ZhIqtuPq+ovDKBQb+kBjnpPIVAioITACgE7CFQIqCDAEMAhsEev2PdALb3IAHKp1sOsbdjJjepk83UWqgLhjAM+nFFoqVXhQU8/6+aRh3AfyLFboRMPzhW94L1tJneyGdU0tbVXULWP8p7RmBsH6dYlyJx792/W6YN8sdnTe0HlDaA+SdzEVWZsAAAAAElFTkSuQmCC",
    "error": "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgEAYAAAAj6qa3AAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRP///////wlY99wAAAAHdElNRQfqCA4PBDDiTRwjAAAEF0lEQVRo3u1Ze0hTURzekrCITScUsbTsISWVGWmWZdqLMCI27GX0gt6trq2kHCk9RqmLHm4ZmkEIRVQ6LSQpe/igYmVF9IdGMejh6o/S5ooK0vXHd26xzXXPuXfNoL5/vv3uPfd3ft/HOfeecyaT/ce/DXmgE3Z0ZGRoNKHvEK24DM49Ao5+Ji7rywawcSrYOkKlqqysru5o63UDIFhhR2R4RThVal465OeCD96DIZ9vBc0ACJ/RhKhhenAECyFVCSMaXbRP9BEnfN3ov0s4j4ZO1LfWGnADSGIzorLW3pb6e5zWknqPCbUUnAJIlKJH1HhUWmHdhAtngx98Bzs5sJI0SNoF3r2IlHlYWr8z7mBqNPmMWL8GkJdbPKLOx+I6fr0drH2EAh42sWZAHZPIiKveB448L64eZQ7qcBXyVwSmgOEkaxchevWsIbVFW8LDKyqqqqKOg50GcQXLZOR5OzjyfIhenTqkpihXXDZDX+8rPiMAjqsiELV/oBa+VR2q3mOuUZw1nytO4Bb03CqmVi6Xy+XyF/OF8rndbrfbPeoqoufp3vddq7k8XXvR164iR4tjbVY/NiMiwsg6otPPCFikZkvYNu73wnk8T/cUxi6ch6LcbCyO4IW/ucZWb8ZM/pcfA/IGsSXULAfH1NK19zWCVrgn+P60G9nqzTMKGBB1ky6RuwDcrPAc2qxGzBnDKtyzv+YDpB4z3fNDxwsYQAvTfswlGcdfEWdEXYs44TIZ6X81okInqwKJBtzzuxkRZwS98J5huxtkA1w7hFp4Fj43li3/3FjarwbwiXIKBcyAME6ohefLjXao86hrEfpqeEIxNMgGJGbTCad9ufmD8OcTSDIF2YBdOiycZPXShNNODV8jSP/XEWXHBcgAO+USOCQDPGmK2O845viNVj4WZ0TCWFJPCd3z9joBAw4p2XysNIgT/uvlJnYdAa66w1ZvQYqAAdZktoTDjrpWcCt1j8wXWIV7g9YI1zJugu6M5RKiyMVs9Vbw+3JfA8gmYSRx6hVtyq4Tji8OI7fUlckl6y5asliF0xrhyuSm6S5ZNneVOGIcV7YxCjd9JfoG/OzHX1O8XJSDETnfsnXEo20eWFOKjpuHs2ZAHQlkblvrwVFizwMGkvOA94IGeBaQtgrR7XJxHfPoJsfih8nJku00+CM5Pg9PA08m93eSTVnfTdL6Te1DDkvd3neoT4VhxPp9iE7tlVZQsLDhFISX+d0tMh+Lk1PhRERl93tbYs/YZIHwUsGVqsT/BVK2IWqk3Ib+aaTFQ3jDE9onRK8EySmrBZGCzK2CjuAKNr0GK/Wswnn8of8GVZmIltjAOQvB0YLn9D3DHgXO14CtWghuny213oAbQGdQ6EREcWvA/TeAvz2FMNvkYNXzA9P/92nlts2mAAAAAElFTkSuQmCC",
}

# The four palette-only PNGs share one repeated color-table entry. Keep this
# repair explicit so the text form stays reviewable and decodes byte-for-byte
# to the former checked-in binary assets.
PNG_BASE64["loading"] = PNG_BASE64["loading"].replace("1yo/////5", "1yo/1yo/////5")
PNG_BASE64["quota-green"] = PNG_BASE64["quota-green"].replace("VfWjf///6", "VfWjVfWjf///6")
PNG_BASE64["quota-amber"] = PNG_BASE64["quota-amber"].replace("+3Tf///x", "+3Tf+3Tf///x")
PNG_BASE64["quota-red"] = PNG_BASE64["quota-red"].replace("O9TUP///5", "O9TUO9TUP///5")


def main() -> None:
    executable = shutil.which("magick") or shutil.which("convert")
    if executable is None:
        raise SystemExit("ImageMagick is required to regenerate Windows ICO tray artwork")

    ico_by_name = {}
    for name, encoded in PNG_BASE64.items():
        with tempfile.NamedTemporaryFile(suffix=".png") as png, tempfile.NamedTemporaryFile(suffix=".ico") as ico:
            png.write(base64.b64decode(encoded))
            png.flush()
            try:
                subprocess.run(
                    [executable, png.name, "-define", "icon:auto-resize=32,24,16", f"ICO:{ico.name}"],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                )
            except subprocess.CalledProcessError as error:
                detail = error.stderr.decode("utf-8", errors="replace") if error.stderr else ""
                raise SystemExit(f"failed to generate {name}.ico: {detail}") from error
            ico.seek(0)
            ico_by_name[name] = base64.b64encode(ico.read()).decode("ascii")

    lines = [
        "// Generated from the original native-port tray artwork - do not edit by hand.",
        "// Regenerate with: python3 Scripts/generate_cross_tray_icons.py",
        "// swiftlint:disable line_length",
        "",
        "enum GeneratedTrayIconData {",
        "    static let pngBase64ByName: [String: String] = [",
    ]
    for name, encoded in PNG_BASE64.items():
        lines.append(f'        "{name}": "{encoded}",')
    lines.extend(["    ]", "", "    static let icoBase64ByName: [String: String] = ["])
    for name, encoded in ico_by_name.items():
        lines.append(f'        "{name}": "{encoded}",')
    lines.extend(["    ]", "}", "", "// swiftlint:enable line_length"])
    with open(OUTPUT, "w", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")
    print(f"generated {len(PNG_BASE64)} tray icons")


if __name__ == "__main__":
    main()
