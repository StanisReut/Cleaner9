#!/usr/bin/env python3
"""Проверки до сборки: ловим то, из-за чего прогон падает в самом конце.

Каждая проверка стоит секунды, а отказ App Store Connect приходит через
двадцать минут — после архива, экспорта и загрузки. Поэтому всё, что можно
выяснить заранее, выясняем здесь.

Использование: preflight.py <project.xcodeproj> <profiles/manifest.json>
"""

import json
import os
import plistlib
import subprocess
import sys
import time
from datetime import datetime, timezone

problems: list[str] = []
notes: list[str] = []


def fail(msg: str) -> None:
    problems.append(msg)
    print(f"❌ {msg}")


def ok(msg: str) -> None:
    print(f"✅ {msg}")


def warn(msg: str) -> None:
    notes.append(msg)
    print(f"⚠️  {msg}")


# ── Иконка ──────────────────────────────────────────────────────────────────
# Альфа-канал в иконке — отказ стора. Ловится мгновенно, а всплывает последним.
def check_icons(root: str) -> None:
    icons = []
    for base, _, files in os.walk(root):
        if not base.endswith(".appiconset"):
            continue
        icons += [os.path.join(base, f) for f in files if f.lower().endswith(".png")]

    if not icons:
        warn("Иконок не нашлось — пропускаю проверку альфа-канала")
        return

    with_alpha = []
    for path in icons:
        out = subprocess.run(["sips", "-g", "hasAlpha", path],
                             capture_output=True, text=True).stdout
        if "hasAlpha: yes" in out:
            with_alpha.append(os.path.relpath(path, root))

    if with_alpha:
        fail("В иконках есть альфа-канал — App Store такое отклоняет:\n     "
             + "\n     ".join(with_alpha))
    else:
        ok(f"Иконки без альфа-канала ({len(icons)} шт.)")


# ── Info.plist ──────────────────────────────────────────────────────────────
def check_plists(root: str) -> None:
    for base, _, files in os.walk(root):
        if "/Pods/" in base or "/.build/" in base:
            continue
        for name in files:
            if name != "Info.plist":
                continue
            path = os.path.join(base, name)
            try:
                with open(path, "rb") as fh:
                    data = plistlib.load(fh)
            except Exception:
                continue

            empty = [k for k, v in data.items()
                     if k.startswith("NS") and k.endswith("UsageDescription")
                     and isinstance(v, str) and not v.strip()]
            if empty:
                fail(f"{os.path.relpath(path, root)}: пустые тексты разрешений — "
                     f"стор отклонит: {', '.join(empty)}")


# ── Профили ─────────────────────────────────────────────────────────────────
def check_profiles(profiles: list[dict]) -> None:
    now = datetime.now(timezone.utc)
    for p in profiles:
        # В профиле дата без пояса, но всегда в UTC — доставляем его сами,
        # иначе вычитание падает на разнице «наивной» и «осведомлённой» дат.
        expires = datetime.fromisoformat(p["expires"])
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        left = (expires - now).days
        if left < 0:
            fail(f"Профиль '{p['name']}' истёк {abs(left)} дн. назад — перевыпусти и обнови секрет")
        elif left < 14:
            warn(f"Профиль '{p['name']}' истекает через {left} дн.")
        else:
            ok(f"Профиль '{p['name']}' действителен ещё {left} дн.")


# ── Версия ──────────────────────────────────────────────────────────────────
# Номер сборки намеренно НЕ увеличиваем сами: человек должен поднять версию
# осознанно. Наша задача — сказать об этом до сборки, а не после отказа стора.
def check_version(project: str, bundle_id: str, key_id: str, issuer: str, key_path: str) -> None:
    settings = subprocess.run(
        ["xcodebuild", "-project", project, "-showBuildSettings", "-json"],
        capture_output=True, text=True)
    if settings.returncode != 0:
        warn("Не удалось прочитать версию из проекта — пропускаю сверку с App Store Connect")
        return

    try:
        entries = json.loads(settings.stdout)
        build = entries[0]["buildSettings"]
        short = build.get("MARKETING_VERSION", "")
        number = build.get("CURRENT_PROJECT_VERSION", "")
    except Exception:
        warn("Не разобрал настройки сборки — пропускаю сверку версии")
        return

    if not short or not number:
        fail("В проекте не заданы MARKETING_VERSION или CURRENT_PROJECT_VERSION")
        return
    ok(f"Версия в проекте: {short} ({number})")

    token = asc_token(key_id, issuer, key_path)
    if not token:
        warn("Не собрал токен App Store Connect — пропускаю сверку версии")
        return

    app_id = asc_get(token, f"/v1/apps?filter[bundleId]={bundle_id}")
    if not app_id or not app_id.get("data"):
        warn(f"Приложение {bundle_id} в App Store Connect не найдено — первая загрузка?")
        return
    app = app_id["data"][0]["id"]

    builds = asc_get(token, f"/v1/builds?filter[app]={app}"
                            f"&filter[preReleaseVersion.version]={short}"
                            f"&filter[version]={number}&limit=1")
    if builds and builds.get("data"):
        fail(f"Сборка {short} ({number}) уже загружена в App Store Connect.\n"
             f"     Подними версию или номер сборки в проекте и запушь заново.")
    else:
        ok(f"Сборки {short} ({number}) в App Store Connect ещё нет")


def asc_token(key_id: str, issuer: str, key_path: str):
    try:
        import jwt  # PyJWT есть на раннерах GitHub
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "pyjwt[crypto]"],
                       capture_output=True)
        try:
            import jwt
        except ImportError:
            return None
    try:
        with open(key_path) as fh:
            secret = fh.read()
        now = int(time.time())
        return jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                          secret, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
    except Exception:
        return None


def asc_get(token: str, path: str):
    out = subprocess.run(
        ["curl", "-sS", "-H", f"Authorization: Bearer {token}",
         f"https://api.appstoreconnect.apple.com{path}"],
        capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except Exception:
        return None


def main() -> int:
    project, manifest_path = sys.argv[1], sys.argv[2]
    root = os.path.dirname(os.path.abspath(project)) or "."
    profiles = json.load(open(manifest_path))
    main_profile = next((p for p in profiles if p["is_main"]), None)
    if not main_profile:
        print("❌ В манифесте нет основного профиля")
        return 1

    print("── Иконки ──");     check_icons(root)
    print("── Info.plist ──"); check_plists(root)
    print("── Профили ──");    check_profiles(profiles)

    key_id = os.environ.get("API_KEY_ID", "")
    issuer = os.environ.get("API_ISSUER_ID", "")
    key_path = os.path.expanduser(f"~/private_keys/AuthKey_{key_id}.p8")
    print("── Версия ──")
    if key_id and issuer and os.path.exists(key_path):
        check_version(project, main_profile["bundle_id"], key_id, issuer, key_path)
    else:
        warn("Ключ App Store Connect недоступен — пропускаю сверку версии")

    print()
    if problems:
        print(f"❌ Не пройдено проверок: {len(problems)}. Сборку не начинаю.")
        return 1
    if notes:
        print(f"✅ Проверки пройдены, предупреждений: {len(notes)}")
    else:
        print("✅ Все проверки пройдены")
    return 0


if __name__ == "__main__":
    sys.exit(main())
