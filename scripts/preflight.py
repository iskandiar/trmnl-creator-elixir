#!/usr/bin/env python3
"""Validate deployment settings without printing secret values or changing services."""
import argparse
import base64
import re
from pathlib import Path
from urllib.parse import urlsplit


def validate(values):
    errors = []
    for name, minimum in [('ADMIN_PASSWORD', 16), ('SECRET_KEY_BASE', 64),
                          ('POSTGRES_PASSWORD', 16), ('RENDERER_SECRET', 32)]:
        if len(values.get(name, '')) < minimum:
            errors.append(f'{name}: wymagane minimum {minimum} znaków')
    if not re.fullmatch(r'[A-Za-z0-9._~-]+', values.get('POSTGRES_PASSWORD', '')):
        errors.append('POSTGRES_PASSWORD: użyj znaków bezpiecznych w adresie URL (generator tworzy właściwe hasło)')
    try:
        if len(base64.b64decode(values.get('TOKEN_ENCRYPTION_KEY', ''), validate=True)) != 32:
            raise ValueError()
    except (ValueError, TypeError):
        errors.append('TOKEN_ENCRYPTION_KEY: wymagane 32 bajty zakodowane base64')
    for name in ['PUBLIC_URL', 'GOOGLE_BROWSER_ORIGIN']:
        try:
            url = urlsplit(values.get(name, ''))
            _ = url.port
            if url.scheme not in ['http', 'https'] or not url.hostname or url.path not in ['', '/'] or url.query or url.fragment or url.username:
                raise ValueError()
        except ValueError:
            errors.append(f'{name}: wymagany adres http(s) bez ścieżki, hasła i parametrów')
    if bool(values.get('GOOGLE_CLIENT_ID')) != bool(values.get('GOOGLE_CLIENT_SECRET')):
        errors.append('Google OAuth: ustaw jednocześnie GOOGLE_CLIENT_ID i GOOGLE_CLIENT_SECRET')
    if values.get('GOOGLE_CLIENT_ID'):
        callback = values.get('GOOGLE_BROWSER_ORIGIN', '').rstrip('/') + '/oauth/callback'
        if values.get('GOOGLE_REDIRECT_URI') != callback:
            errors.append('GOOGLE_REDIRECT_URI: musi odpowiadać GOOGLE_BROWSER_ORIGIN + /oauth/callback')
    try:
        if not 1 <= int(values.get('PORT', '4000')) <= 65535:
            raise ValueError()
    except ValueError:
        errors.append('PORT: wymagany numer 1–65535')
    return errors


def read_env(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            values[key.strip()] = value.strip().strip('\"\'')
    return values


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('env_file', nargs='?', default='.env')
    args = parser.parse_args()
    try:
        values = read_env(args.env_file)
    except OSError:
        parser.exit(1, 'Nie można odczytać konfiguracji. Uruchom scripts/generate_env.py.\n')
    errors = validate(values)
    if errors:
        parser.exit(1, '\n'.join(errors) + '\n')
    print('Konfiguracja poprawna. Sekrety nie zostały wypisane.')
    print('Google OAuth: ' + ('skonfigurowany; zgoda konta wymaga sprawdzenia' if values.get('GOOGLE_CLIENT_ID') else 'nieustawiony; dostępne moduły lokalne'))
    print('Przed startem potwierdź, że PUBLIC_URL wskazuje adres LAN osiągalny z telefonu i TRMNL.')
