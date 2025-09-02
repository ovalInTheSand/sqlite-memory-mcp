import os, re, zipfile, sys, subprocess, pathlib, json
import pytest

from backend import PACKAGE_VERSION

@pytest.mark.build
def test_build_wheel_and_sdist(tmp_path):
    """Build sdist & wheel; validate filenames and wheel METADATA version without installing.
    Skips if 'build' module absent to avoid hard dependency in minimal env.
    """
    build = pytest.importorskip('build')  # noqa: F841
    project_root = pathlib.Path(__file__).resolve().parents[1]
    dist_dir = tmp_path / 'dist'
    dist_dir.mkdir()
    # Run build via subprocess for isolation
    cmd = [sys.executable, '-m', 'build', '--wheel', '--sdist', '--outdir', str(dist_dir)]
    proc = subprocess.run(cmd, capture_output=True, text=True, cwd=project_root)
    assert proc.returncode == 0, f"build failed: {proc.stdout}\n{proc.stderr}"
    wheels = list(dist_dir.glob('sqlite_memory_mcp-*-py3-none-any.whl'))
    assert wheels, f"No wheel produced. Contents: {[p.name for p in dist_dir.iterdir()]}"
    wheel = wheels[0]
    assert f"-{PACKAGE_VERSION}-" in wheel.name.replace('_', '-'), f"Wheel filename version mismatch: {wheel.name} vs {PACKAGE_VERSION}"
    # Inspect METADATA inside wheel
    with zipfile.ZipFile(wheel, 'r') as zf:
        meta_path = [n for n in zf.namelist() if n.endswith('METADATA')][0]
        meta = zf.read(meta_path).decode('utf-8', errors='replace')
    m = re.search(r'^Version: (.+)$', meta, re.MULTILINE)
    assert m and m.group(1).strip() == PACKAGE_VERSION, f"Wheel METADATA version mismatch: {m and m.group(1)} != {PACKAGE_VERSION}"
    # Basic sanity: no runtime dependencies (extra dependencies like dev are OK)
    runtime_deps = [line for line in meta.split('\n') if line.startswith('Requires-Dist:') and 'extra ==' not in line]
    assert not runtime_deps, f'Unexpected runtime dependencies declared: {runtime_deps}'
    # sdist present - match both hyphenated and underscored package names
    sdists = list(dist_dir.glob('sqlite*memory*mcp-*.tar.gz'))
    assert sdists, 'No sdist produced'
