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
    'generation.enhancer_pipeline',
    'generation.model_status',
    'generation.model_paths',
    'generation.camera_service',
    'cv2',
    'insightface',
    'onnxruntime',
    'download_model',
    'self_test',
    'failure_server',
]

hiddenimports += collect_submodules('uvicorn')
hiddenimports += collect_submodules('starlette')
hiddenimports += collect_submodules('fastapi')

# diffusers, transformers and chatterbox import most classes lazily, which
# PyInstaller cannot see; collect them so `engine.exe --self-test` passes.
def _safe_submodules(package, exclude=()):
    try:
        return [m for m in collect_submodules(package) if not any(x in m for x in exclude)]
    except Exception as e:  # package missing: the self-test will report it
        print(f'[engine.spec] skipping {package}: {e}')
        return []

hiddenimports += _safe_submodules('diffusers', exclude=('.tests', 'commands', '.experimental'))
hiddenimports += _safe_submodules('transformers', exclude=('.tests', '.commands', 'convert_', '_tf_', '_flax_', 'modeling_tf_', 'modeling_flax_'))
hiddenimports += _safe_submodules('chatterbox')
hiddenimports += _safe_submodules('perth')
hiddenimports += _safe_submodules('s3tokenizer')

datas = [
    ('api', 'api'),
    ('generation', 'generation'),
]

# Data files read at run time (tokenizer tables, dictionaries, small model assets).
for pkg in ('diffusers', 'transformers', 'chatterbox', 'perth', 's3tokenizer', 'pykakasi', 'spacy_pkuseg', 'librosa'):
    try:
        datas += collect_data_files(pkg)
    except Exception as e:
        print(f'[engine.spec] no data files for {pkg}: {e}')

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
    'peft',
    'sentencepiece',
    'tokenizers',
    'librosa',
    'chatterbox-tts',
    'resemble-perth',
    's3tokenizer',
    'conformer',
    'omegaconf',
    'regex',
    'tqdm',
    'imageio',
    'imageio-ffmpeg',
    'soundfile',
    'pyloudnorm',
    'pykakasi',
    'fastapi',
    'uvicorn',
    'pydantic',
    'huggingface-hub',
    'insightface',
    'onnxruntime',
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
    # TorchScript (@torch.jit.script at import time, e.g. diffusers' Kolors text
    # encoder) needs the original .py source next to the bytecode.
    module_collection_mode={
        'diffusers': 'pyz+py',
        'transformers': 'pyz+py',
        'chatterbox': 'pyz+py',
        's3tokenizer': 'pyz+py',
        'perth': 'pyz+py',
    },
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
