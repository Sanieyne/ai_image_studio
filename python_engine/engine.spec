# -*- mode: python ; coding: utf-8 -*-
import os
import sys
from PyInstaller.utils.hooks import collect_data_files, collect_submodules, copy_metadata

block_cipher = None

# Collect submodules
hiddenimports = [
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.lifespan',
    'uvicorn.lifespan.on',
    'fastapi',
    'pydantic',
    'app',
    'api.routes',
    'api.schemas',
    'generation.device',
    'generation.model_registry',
    'generation.pipeline',
    'generation.prompt_enhancer',
    'generation.tryon_pipeline',
    'generation.video_pipeline',
    'generation.voice_pipeline',
]

hiddenimports += collect_submodules('uvicorn')
hiddenimports += collect_submodules('starlette')
hiddenimports += collect_submodules('fastapi')

datas = [
    ('api', 'api'),
    ('generation', 'generation'),
]

# Collect dist-info metadata for runtime dependency checks (e.g. diffusers, transformers)
metadata_packages = [
    'requests',
    'diffusers',
    'transformers',
    'torch',
    'torchaudio',
    'torchvision',
    'accelerate',
    'safetensors',
    'huggingface_hub',
    'tokenizers',
    'timm',
    'packaging',
    'filelock',
    'numpy',
    'pillow',
]

for pkg in metadata_packages:
    try:
        datas += copy_metadata(pkg)
    except Exception:
        pass

a = Analysis(
    ['launcher.py'],
    pathex=['.'],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'IPython'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='engine',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='engine',
)
