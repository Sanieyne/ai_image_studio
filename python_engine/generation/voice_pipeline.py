"""Chatterbox TTS voice generation and zero-shot voice cloning pipeline.

Powered by Resemble AI Chatterbox (0.5B Llama backbone) and Chatterbox Multilingual V3.
Supports:
- Text-to-speech synthesis across 23+ languages
- Zero-shot voice cloning via audio reference clip
- Emotion exaggeration control (0.0 to 1.0+) and CFG pacing guidance
- Automatic GPU (CUDA) / CPU detection with seamless Mock mode fallback
"""
from __future__ import annotations

import io
import logging
import math
import os
import random
import struct
import subprocess
import tempfile
import time
import wave
from typing import Optional, Tuple

log = logging.getLogger(__name__)

SUPPORTED_LANGUAGES = {
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "it": "Italian",
    "pt": "Portuguese",
    "zh": "Chinese",
    "ja": "Japanese",
    "ko": "Korean",
    "hi": "Hindi",
    "ar": "Arabic",
    "ru": "Russian",
    "tr": "Turkish",
    "nl": "Dutch",
    "pl": "Polish",
    "sv": "Swedish",
    "da": "Danish",
    "fi": "Finnish",
    "he": "Hebrew",
    "ms": "Malay",
    "no": "Norwegian",
    "sw": "Swahili",
    "el": "Greek",
}


def _create_mock_wav(
    text: str,
    language: str = "en",
    sample_rate: int = 24000,
    duration_secs: float = 2.0,
) -> bytes:
    """Generate a clean synthetic speech-like tone sequence for mock mode."""
    buf = io.BytesIO()
    total_samples = int(sample_rate * max(1.0, min(duration_secs, 5.0)))
    num_channels = 1
    sample_width = 2  # 16-bit PCM

    with wave.open(buf, "wb") as wf:
        wf.setnchannels(num_channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(sample_rate)

        # Base speech fundamental frequency ~ 180Hz - 240Hz
        base_freq = 220.0
        frames = bytearray()
        for i in range(total_samples):
            t = float(i) / sample_rate
            # Syllabic envelope modulation (~4-5 syllables per sec)
            env = 0.5 * (1.0 + math.sin(2.0 * math.pi * 4.5 * t))
            # Smooth fade in/out
            if t < 0.05:
                env *= t / 0.05
            elif t > duration_secs - 0.05:
                env *= max(0.0, (duration_secs - t) / 0.05)

            # Harmonic resonance
            f1 = base_freq + 20.0 * math.sin(2.0 * math.pi * 2.0 * t)
            f2 = f1 * 1.5
            val = env * (0.6 * math.sin(2.0 * math.pi * f1 * t) + 0.3 * math.sin(2.0 * math.pi * f2 * t))
            int_sample = int(max(-1.0, min(1.0, val)) * 32767.0)
            frames.extend(struct.pack("<h", int_sample))

        wf.writeframes(frames)

    return buf.getvalue()


def _normalize_reference_audio(raw_bytes: bytes, target_wav_path: str) -> bool:
    """Normalize any input audio format (mp3, m4a, ogg, webm, flac, wav) to 24kHz 16-bit mono WAV using ffmpeg."""
    raw_in = target_wav_path + ".raw_in"
    try:
        with open(raw_in, "wb") as f:
            f.write(raw_bytes)
        # Use ffmpeg to convert to standard 24kHz 16-bit mono PCM WAV
        cmd = [
            "ffmpeg", "-y", "-i", raw_in,
            "-ar", "24000",
            "-ac", "1",
            "-sample_fmt", "s16",
            "-f", "wav",
            target_wav_path,
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        if res.returncode == 0 and os.path.exists(target_wav_path) and os.path.getsize(target_wav_path) > 44:
            log.info("[*] Normalized reference audio via ffmpeg: %d bytes (24kHz 16-bit mono WAV)",
                     os.path.getsize(target_wav_path))
            return True
        else:
            log.warning("[!] ffmpeg normalization failed (code %d): %s", res.returncode, res.stderr.decode(errors="ignore")[:250])
    except Exception as e:
        log.warning("[!] ffmpeg error during reference audio normalization: %s", e)
    finally:
        if os.path.exists(raw_in):
            try:
                os.remove(raw_in)
            except Exception:
                pass

    # Fallback to direct write if ffmpeg was unavailable
    try:
        with open(target_wav_path, "wb") as f:
            f.write(raw_bytes)
        return True
    except Exception as e:
        log.error("[!] Failed fallback writing reference audio: %s", e)
        return False



def _chatterbox_dir():
    """The downloaded Chatterbox folder (holds the English and multilingual weights).

    Raises when it is missing and the Hugging Face hub may not be used, so the
    caller reports it instead of downloading.
    """
    from generation.model_paths import ModelNotDownloadedError, hub_downloads_allowed, model_dir

    local = model_dir("chatterbox-tts")
    if local is None and not hub_downloads_allowed():
        raise ModelNotDownloadedError("Chatterbox is not downloaded. Download it from the Voice tab.")
    return local

class ChatterboxVoiceEngine:
    """Chatterbox TTS & Multilingual Voice Engine."""

    def __init__(self):
        self.mock_mode = os.getenv("AI_STUDIO_MOCK", "0") == "1"
        self.device = "cuda"
        self._en_model = None
        self._mtl_model = None
        self._breeze_runtime = None
        self._check_environment()

    def _check_environment(self):
        try:
            import torch
            self.device = "cuda" if torch.cuda.is_available() else "cpu"
        except Exception:
            self.device = "cpu"
            self.mock_mode = True

    @property
    def loaded(self) -> bool:
        return (self._en_model is not None or self._mtl_model is not None or self._breeze_runtime is not None) and not self.mock_mode

    def _get_breeze_runtime(self):
        """Lazy load Breeze-TTS-2 model & audio tokenizer."""
        if self._breeze_runtime is None:
            log.info("[*] Loading Breeze-TTS-2 on %s...", self.device)
            try:
                import sys
                from pathlib import Path

                # Search paths for breeze-tts package
                possible_repo_dirs = [
                    os.getenv("BREEZE_REPO_DIR", "/root/ai_image_studio/breeze-tts"),
                    os.path.expanduser("~/ai_image_studio/breeze-tts"),
                    "/root/breeze-tts",
                ]
                for d in possible_repo_dirs:
                    if os.path.exists(d) and d not in sys.path:
                        sys.path.insert(0, d)

                from breeze_infer.runtime import (
                    load_runtime,
                    resolve_device,
                    update_generation_config_for_breeze,
                )
                from models.fast_streaming import FastBreezeStreamingRuntime, FastStreamingConfig

                from generation.model_paths import model_dir as _model_dir

                possible_model_dirs = [
                    Path(os.getenv("BREEZE_MODEL_DIR", "/root/models/breeze-tts-2")),
                    *([_model_dir("breeze-tts-2")] if _model_dir("breeze-tts-2") else []),
                    Path(os.path.expanduser("~/models/breeze-tts-2")),
                    Path("/root/ai_image_studio/models/breeze-tts-2"),
                    Path("BreezeBlue/Breeze-TTS-2"),
                ]
                model_path = next((p for p in possible_model_dirs if p.exists()), Path("BreezeBlue/Breeze-TTS-2"))
                log.info("[*] Breeze-TTS-2 using checkpoint: %s", model_path)

                device = resolve_device() if self.device.startswith("cuda") else "cpu"
                tokenizer, model, audio_tokenizer = load_runtime(
                    model_path,
                    device=device,
                    attn_implementation="eager",
                )
                update_generation_config_for_breeze(model)
                config = FastStreamingConfig(
                    max_new_tokens=1500,
                    max_seq_len=2048,
                    repetition_penalty=1.1,
                )
                runtime = FastBreezeStreamingRuntime(
                    model, audio_tokenizer, config, tokenizer=tokenizer
                )
                self._breeze_runtime = (runtime, tokenizer, model, audio_tokenizer)
                log.info("[OK] Breeze-TTS-2 loaded successfully.")
            except Exception as e:
                log.error("[!] Failed loading Breeze-TTS-2: %s", e, exc_info=True)
                return None
        return self._breeze_runtime

    def _generate_breeze_audio(
        self,
        prompt: str,
        audio_ref_path: Optional[str] = None,
        instruction: Optional[str] = None,
        ref_text: Optional[str] = None,
        cfg_scale: float = 4.0,
        seed: int = 42,
    ) -> Tuple[bytes, int, int]:
        breeze_data = self._get_breeze_runtime()
        if breeze_data is None:
            raise RuntimeError("Breeze-TTS-2 model failed to load.")

        runtime, tokenizer, model, audio_tokenizer = breeze_data
        import numpy as np
        from breeze_infer.runtime import set_all_seeds
        from breeze_infer.templates import get_template, prepare_inputs, select_template_name

        req = {
            "id": f"req-{seed}",
            "text": prompt,
            "speaker": "S0",
        }
        if instruction and instruction.strip():
            req["instruction"] = instruction.strip()

        if audio_ref_path:
            req["ref_audio_path"] = str(audio_ref_path)
            req["ref_text"] = ref_text.strip() if (ref_text and ref_text.strip()) else "Voice reference sample."

        template_name = select_template_name(req)
        set_all_seeds(seed)

        scale = max(1.0, float(cfg_scale))
        inputs = prepare_inputs(
            tokenizer,
            audio_tokenizer,
            model,
            [req],
            get_template(template_name),
            guidance_scale=scale,
            guidance_scale_ref=None,
            guidance_scale_ins=None,
        )

        chunks = []
        for chunk in runtime.iter_audio_chunks(inputs, request_id=f"req-{seed}", seed=seed):
            chunks.append(chunk.audio)

        if chunks:
            audio_np = np.concatenate(chunks)
        else:
            audio_np = np.zeros((runtime.sample_rate,), dtype=np.float32)

        import soundfile as sf
        buf = io.BytesIO()
        sf.write(buf, audio_np, runtime.sample_rate, subtype="PCM_16", format="WAV")
        return buf.getvalue(), runtime.sample_rate, seed

    def _get_model(self, language: str = "en", model_name: Optional[str] = None):
        lang = language.lower().strip() if language else "en"
        use_mtl = (lang not in ("", "en")) or (model_name is not None and "multilingual" in model_name.lower())
        if not use_mtl:
            if self._en_model is None:
                log.info("[*] Loading Chatterbox English TTS on %s...", self.device)
                try:
                    from chatterbox.tts import ChatterboxTTS
                    local = _chatterbox_dir()
                    self._en_model = (
                        ChatterboxTTS.from_local(str(local), self.device)
                        if local
                        else ChatterboxTTS.from_pretrained(device=self.device)
                    )
                    log.info("[OK] Chatterbox English TTS ready.")
                except Exception as e:
                    log.warning("[!] Could not load ChatterboxTTS (%s). Falling back to mock.", e)
                    self.mock_mode = True
                    return None
            return self._en_model
        else:
            if self._mtl_model is None:
                log.info("[*] Loading Chatterbox Multilingual V3 on %s...", self.device)
                try:
                    from chatterbox.mtl_tts import ChatterboxMultilingualTTS
                    local = _chatterbox_dir()
                    self._mtl_model = (
                        ChatterboxMultilingualTTS.from_local(str(local), self.device)
                        if local
                        else ChatterboxMultilingualTTS.from_pretrained(device=self.device)
                    )
                    log.info("[OK] Chatterbox Multilingual V3 ready.")
                except Exception as e:
                    log.warning("[!] Could not load ChatterboxMultilingualTTS (%s). Falling back to mock.", e)
                    self.mock_mode = True
                    return None
            return self._mtl_model

    def generate_audio(
        self,
        prompt: str,
        language: str = "en",
        model_name: Optional[str] = None,
        audio_prompt_bytes: Optional[bytes] = None,
        exaggeration: float = 0.5,
        cfg_weight: float = 0.5,
        seed: int = -1,
        instruction: Optional[str] = None,
        ref_text: Optional[str] = None,
    ) -> Tuple[bytes, int, int]:
        """Generate speech WAV bytes.

        Returns (wav_bytes, sample_rate, seed_used).
        """
        t0 = time.perf_counter()
        if seed == -1:
            seed = random.randint(0, 2**31 - 1)

        # Mock fallback when requested or when libraries are absent
        if self.mock_mode:
            log.info("[*] [MOCK] Generating voice for: %.60s (lang=%s, model=%s)", prompt, language, model_name)
            est_duration = max(1.5, len(prompt.split()) * 0.35)
            wav_bytes = _create_mock_wav(prompt, language=language, sample_rate=24000, duration_secs=est_duration)
            return wav_bytes, 24000, seed

        try:
            import torch
            if torch.cuda.is_available():
                torch.manual_seed(seed)
        except Exception:
            pass

        # Branch to Breeze-TTS-2 when requested
        if model_name and "breeze" in model_name.lower():
            log.info("[*] Using Breeze-TTS-2 for speech synthesis (prompt: %.50s...)", prompt)
            audio_ref_path = None
            tmp_dir = None
            try:
                if audio_prompt_bytes:
                    tmp_dir = tempfile.mkdtemp(prefix="breeze_voice_ref_")
                    audio_ref_path = os.path.join(tmp_dir, "reference.wav")
                    if not _normalize_reference_audio(audio_prompt_bytes, audio_ref_path):
                        audio_ref_path = None

                effective_cfg = cfg_weight if cfg_weight > 1.0 else (4.0 if (instruction or audio_ref_path) else 1.0)
                wav_bytes, sample_rate, seed_used = self._generate_breeze_audio(
                    prompt=prompt,
                    audio_ref_path=audio_ref_path,
                    instruction=instruction,
                    ref_text=ref_text,
                    cfg_scale=effective_cfg,
                    seed=seed,
                )
                elapsed_ms = int((time.perf_counter() - t0) * 1000)
                log.info("[OK] Breeze-TTS-2 voice generated: %d bytes in %dms (seed=%d)", len(wav_bytes), elapsed_ms, seed_used)
                return wav_bytes, sample_rate, seed_used
            finally:
                if tmp_dir and os.path.exists(tmp_dir):
                    import shutil
                    shutil.rmtree(tmp_dir, ignore_errors=True)

        lang = language.lower().strip() if language else "en"
        model = self._get_model(lang, model_name=model_name)
        if model is None:
            # Fallback to mock tone
            est_duration = max(1.5, len(prompt.split()) * 0.35)
            wav_bytes = _create_mock_wav(prompt, language=lang, sample_rate=24000, duration_secs=est_duration)
            return wav_bytes, 24000, seed

        audio_ref_path = None
        tmp_dir = None
        try:
            if audio_prompt_bytes:
                log.info("[*] Processing reference audio (%d bytes) for voice cloning...", len(audio_prompt_bytes))
                try:
                    import soundfile as sf
                    info = sf.info(io.BytesIO(audio_prompt_bytes))
                    log.info("[*] Reference audio: %.2fs, %d Hz, %d channel(s), format: %s",
                             info.duration, info.samplerate, info.channels, info.format)
                except Exception as e:
                    log.warning("[!] Soundfile info warning: %s (will still attempt decoding)", e)

                try:
                    tmp_dir = tempfile.mkdtemp(prefix="cb_voice_ref_")
                    audio_ref_path = os.path.join(tmp_dir, "reference.wav")
                    if _normalize_reference_audio(audio_prompt_bytes, audio_ref_path):
                        log.info("[*] Voice cloning active with normalized reference: %s", audio_ref_path)
                    else:
                        log.warning("[!] Could not normalize reference audio. Proceeding with default voice.")
                        audio_ref_path = None
                except Exception as e:
                    log.warning("[!] Failed preparing reference audio (%s). Using default voice.", e)
                    audio_ref_path = None
            else:
                log.info("[*] No reference audio attached - synthesizing with default speaker voice.")

            gen_kwargs = {
                "exaggeration": max(0.0, min(float(exaggeration), 2.0)),
                "cfg_weight": max(0.0, min(float(cfg_weight), 2.0)),
            }
            if audio_ref_path:
                gen_kwargs["audio_prompt_path"] = audio_ref_path

            try:
                if lang not in ("", "en") and hasattr(model, "generate"):
                    # Multilingual generate
                    wav = model.generate(prompt, language_id=lang, **gen_kwargs)
                else:
                    wav = model.generate(prompt, **gen_kwargs)
            except Exception as gen_err:
                if audio_ref_path:
                    log.warning("[!] Generation with reference audio failed (%s). Retrying with default speaker...", gen_err)
                    gen_kwargs.pop("audio_prompt_path", None)
                    if lang not in ("", "en") and hasattr(model, "generate"):
                        wav = model.generate(prompt, language_id=lang, **gen_kwargs)
                    else:
                        wav = model.generate(prompt, **gen_kwargs)
                else:
                    raise gen_err

            sample_rate = getattr(model, "sr", 24000)

            # Convert tensor or array to 1D float numpy array, then write WAV
            if hasattr(wav, "squeeze"):
                wav = wav.squeeze()
            if hasattr(wav, "cpu"):
                wav = wav.cpu().numpy()

            import soundfile as sf
            buf = io.BytesIO()
            sf.write(buf, wav, sample_rate, format="WAV")
            wav_bytes = buf.getvalue()

            elapsed_ms = int((time.perf_counter() - t0) * 1000)
            log.info("[OK] Voice generated: %d bytes in %dms (lang=%s, seed=%d)", len(wav_bytes), elapsed_ms, lang, seed)
            return wav_bytes, sample_rate, seed

        finally:
            if tmp_dir and os.path.exists(tmp_dir):
                import shutil
                shutil.rmtree(tmp_dir, ignore_errors=True)


_voice_engine: Optional[ChatterboxVoiceEngine] = None


def get_voice_engine() -> ChatterboxVoiceEngine:
    global _voice_engine
    if _voice_engine is None:
        _voice_engine = ChatterboxVoiceEngine()
    return _voice_engine
