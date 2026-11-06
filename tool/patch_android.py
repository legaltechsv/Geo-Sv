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

s = re.sub(r'android:label="[^"]*"', 'android:label="GEO CUSCA SUR"', s, count=1)
manifest.write_text(s, encoding="utf-8")
print("AndroidManifest actualizado")

# ── Forzar compileSdk 36 en todas las librerías (plugins) ───────────────────
# Algunos plugins antiguos compilan contra android-33 y las dependencias de
# AndroidX actuales exigen 34+. Se ajusta tras evaluar cada plugin.
MARK = "// geomark: compileSdk de plugins"
kts = pathlib.Path("android/build.gradle.kts")
groovy = pathlib.Path("android/build.gradle")
if kts.exists():
    snippet = f"""{MARK}
subprojects {{
    afterEvaluate {{
        if (plugins.hasPlugin("com.android.library")) {{
            val androidExt = extensions.findByName("android")
            try {{
                androidExt?.javaClass
                    ?.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    ?.invoke(androidExt, 36)
            }} catch (e: Exception) {{
                println("No se pudo ajustar compileSdk en ${{project.name}}: ${{e.message}}")
            }}
        }}
    }}
}}

"""
    target = kts
else:
    snippet = f"""{MARK}
subprojects {{
    afterEvaluate {{ p ->
        if (p.plugins.hasPlugin('com.android.library')) {{
            p.android.compileSdkVersion 36
        }}
    }}
}}

"""
    target = groovy

g = target.read_text(encoding="utf-8")
if MARK not in g:
    # Debe ir ANTES de `evaluationDependsOn(":app")` para registrar afterEvaluate a tiempo.
    i = g.find("subprojects {")
    g = (g[:i] + snippet + g[i:]) if i >= 0 else (g + "\n" + snippet)
    target.write_text(g, encoding="utf-8")
    print(f"compileSdk de plugins forzado en {target}")
