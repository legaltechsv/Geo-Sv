"""Ajusta el proyecto Android generado por `flutter create` (lo usa GitHub Actions).

- Agrega permisos de cámara, ubicación e internet al AndroidManifest.
- Permite que la app abra enlaces https (Google Maps).
- Cambia el nombre visible de la app.
Es idempotente: se puede ejecutar varias veces sin duplicar nada.
"""
import pathlib
import re

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = manifest.read_text(encoding="utf-8")

perms = [
    "android.permission.CAMERA",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
]
block = "".join(
    f'\n    <uses-permission android:name="{p}" />' for p in perms if p not in s
)
if block:
    s = re.sub(r"(<manifest[^>]*>)", r"\1" + block, s, count=1)

intent = (
    '\n        <intent>\n'
    '            <action android:name="android.intent.action.VIEW" />\n'
    '            <data android:scheme="https" />\n'
    '        </intent>'
)
if 'android:scheme="https"' not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>" + intent, 1)
    else:
        s = s.replace("</manifest>", f"    <queries>{intent}\n    </queries>\n</manifest>")

s = re.sub(r'android:label="[^"]*"', 'android:label="GeoMark"', s, count=1)
manifest.write_text(s, encoding="utf-8")
print("AndroidManifest actualizado")
