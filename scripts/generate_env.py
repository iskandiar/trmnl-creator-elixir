#!/usr/bin/env python3
import base64, secrets, os
from pathlib import Path
values = Path('.env.example').read_text()
for key, size in [('POSTGRES_PASSWORD',32),('ADMIN_PASSWORD',24),('SECRET_KEY_BASE',64),('TOKEN_ENCRYPTION_KEY',32),('RENDERER_SECRET',32)]:
    token = base64.b64encode(secrets.token_bytes(size)).decode() if key == 'TOKEN_ENCRYPTION_KEY' else secrets.token_hex(size)
    values = values.replace(key+'=\n', key+'='+token+'\n')
fd = os.open('.env', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as f: f.write(values)
print('Created .env with restrictive permissions. Edit PUBLIC_URL before starting.')
