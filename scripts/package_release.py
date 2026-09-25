#!/usr/bin/env python3
"""Create a source deployment archive from an explicit allowlist, without local data."""
import hashlib
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ['Dockerfile', 'compose.yaml', '.env.example', '.dockerignore',
         'mix.exs', 'mix.lock', 'README.md', 'AGENTS.md']
TREES = ['lib', 'config', 'priv', 'docs']
FILES += ['renderer/Dockerfile', 'renderer/package.json', 'renderer/package-lock.json', 'renderer/server.mjs']
FILES += ['scripts/generate_env.py', 'scripts/preflight.py', 'scripts/backup.sh']

if __name__ == '__main__':
    destination = ROOT / 'dist/trmnl-calendar.tar.gz'
    destination.parent.mkdir(exist_ok=True)
    sources = [ROOT / f for f in FILES]
    sources += [p for tree in TREES for p in (ROOT / tree).rglob('*') if p.is_file() and not p.is_symlink()]
    with tarfile.open(destination, 'w:gz') as archive:
        for path in sorted(set(sources)):
            if path.is_symlink():
                raise ValueError('Symlinks are not permitted in the deployment archive')
            archive.add(path, arcname='trmnl-calendar/' + str(path.relative_to(ROOT)), recursive=False)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(destination.suffix + '.sha256').write_text(f'{digest}  {destination.name}\n')
    print(f'Created {destination.name} and SHA-256 checksum ({len(sources)} files).')
