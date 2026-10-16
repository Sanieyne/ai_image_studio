#!/usr/bin/env python3
"""AI Image Studio - Synthetic Female Voice Generation Worker for Vast.ai GPU.

Generates 3 distinct synthetic female voice clips for Breeze-TTS-2 and
3 distinct synthetic female voice clips for Chatterbox-TTS (plus default comparison),
converts to MP3 + WAV, and uploads to R2 under audio-templates/.
"""

import os
import sys
import time
import json
import subprocess
from pathlib import Path

def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S UTC')}] {msg}", flush=True)

def run_cmd(cmd, check=True):
    log(f"Running: {cmd}")
    res = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if res.stdout:
        print(res.stdout, flush=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed with code {res.returncode}: {cmd}")
    return res.returncode, res.stdout

def main():
    log("==========================================================")
    log("Starting Synthetic Female Reference Voice Generation Worker")
    log("==========================================================")

    import torch
    log(f"PyTorch version: {torch.__version__}, CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        log(f"GPU device: {torch.cuda.get_device_name(0)}, VRAM: {round(torch.cuda.get_device_properties(0).total_memory / (1024**3), 2)} GB")

    workspace = Path("/workspace")
    output_dir = workspace / "outputs" / "audio-templates"
    breeze_out_dir = output_dir / "breeze-tts-2"
    chatterbox_out_dir = output_dir / "chatterbox-tts"
    breeze_out_dir.mkdir(parents=True, exist_ok=True)
    chatterbox_out_dir.mkdir(parents=True, exist_ok=True)

    # Marketing lines
    lines = [
        "Cosmic-Gen AI runs right on your desktop, with no GPU required for most models.",
        "Create unlimited high-quality images and audio locally, or tap into cloud GPU power whenever you need it.",
        "Bring your creative ideas to life in seconds with fast, private AI generation."
    ]

    metadata = {
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu",
        "models": {}
    }

    # =========================================================================
    # PART 1: Breeze-TTS-2 Generation
    # =========================================================================
    log("\n--- [PART 1/2] Generating Breeze-TTS-2 Reference Clips ---")
    breeze_repo_dir = workspace / "breeze-tts"
    breeze_model_dir = workspace / "models" / "breeze-tts-2"

    if not breeze_repo_dir.exists():
        log("Cloning breeze-tts repo...")
        run_cmd(f"git clone https://github.com/breezeblue-ai/breeze-tts.git {breeze_repo_dir}")

    sys.path.insert(0, str(breeze_repo_dir))

    # Test breeze-tts import
    try:
        from breeze_infer.runtime import (
            load_runtime,
            resolve_device,
            update_generation_config_for_breeze,
            set_all_seeds
        )
        from breeze_infer.templates import get_template, prepare_inputs, select_template_name
        breeze_configs = [
            {
                "index": 1,
                "text": lines[0],
                "instruction": "A young, energetic and cheerful female speaker with an upbeat, friendly, and bright tone.",
                "persona": "Young & Cheerful Female",
                "seed": 101,
            },
            {
                "index": 2,
                "text": lines[1],
                "instruction": "A calm, gentle and soothing female narrator speaking softly, warm and reassuring.",
                "persona": "Calm & Soothing Female Narrator",
                "seed": 202,
            },
            {
                "index": 3,
                "text": lines[2],
                "instruction": "A confident, articulate, and professional female corporate presenter speaking with clear, polished, and dynamic delivery.",
                "persona": "Confident Professional Female",
                "seed": 303,
            },
        ]

        metadata["models"]["breeze-tts-2"] = []

        breeze_complete = all((breeze_out_dir / f"{i}.wav").exists() and (breeze_out_dir / f"{i}.mp3").exists() for i in [1, 2, 3])
        if breeze_complete:
            log("All 3 Breeze-TTS-2 clips already exist! Skipping Breeze re-generation.")
            for item in breeze_configs:
                idx = item["index"]
                wav_path = breeze_out_dir / f"{idx}.wav"
                mp3_path = breeze_out_dir / f"{idx}.mp3"
                metadata["models"]["breeze-tts-2"].append({
                    "index": idx,
                    "persona": item["persona"],
                    "instruction": item["instruction"],
                    "text": item["text"],
                    "sample_rate": 24000,
                    "wav_bytes": wav_path.stat().st_size,
                    "mp3_bytes": mp3_path.stat().st_size,
                    "key_mp3": f"audio-templates/breeze-tts-2/{idx}.mp3",
                    "key_wav": f"audio-templates/breeze-tts-2/{idx}.wav",
                })
        else:
            log(f"Loading Breeze-TTS-2 runtime from {breeze_model_dir}...")
            device = resolve_device() if torch.cuda.is_available() else "cpu"
            tokenizer, model, audio_tokenizer = load_runtime(
                breeze_model_dir,
                device=device,
                attn_implementation="eager"
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
            log("Breeze-TTS-2 runtime loaded successfully.")

        if not breeze_complete:
            for item in breeze_configs:
                idx = item["index"]
                prompt_text = item["text"]
                inst = item["instruction"]
                seed = item["seed"]
                log(f"\nGenerating Breeze-TTS-2 Clip #{idx}: {item['persona']}")
                log(f"  Instruction: {inst}")
                log(f"  Text: {prompt_text}")

                req = {
                    "id": f"req-{idx}-{seed}",
                    "text": prompt_text,
                    "speaker": "S0",
                    "instruction": inst
                }
                template_name = select_template_name(req)
                set_all_seeds(seed)
                inputs = prepare_inputs(
                    tokenizer,
                    audio_tokenizer,
                    model,
                    [req],
                    get_template(template_name),
                    guidance_scale=4.0,
                    guidance_scale_ref=None,
                    guidance_scale_ins=None,
                )

                chunks = []
                for chunk in runtime.iter_audio_chunks(inputs, request_id=f"req-{idx}-{seed}", seed=seed):
                    chunks.append(chunk.audio)

                if chunks:
                    audio_np = np.concatenate(chunks)
                else:
                    raise RuntimeError(f"No audio produced for Breeze clip #{idx}")

                wav_path = breeze_out_dir / f"{idx}.wav"
                mp3_path = breeze_out_dir / f"{idx}.mp3"
                sf.write(str(wav_path), audio_np, runtime.sample_rate, subtype="PCM_16", format="WAV")
                log(f"  WAV saved: {wav_path} ({wav_path.stat().st_size} bytes)")

                # Convert to MP3
                run_cmd(f"ffmpeg -y -i {wav_path} -b:a 192k {mp3_path}")
                log(f"  MP3 converted: {mp3_path} ({mp3_path.stat().st_size} bytes)")

                dur = len(audio_np) / float(runtime.sample_rate)
                metadata["models"]["breeze-tts-2"].append({
                    "index": idx,
                    "persona": item["persona"],
                    "instruction": inst,
                    "text": prompt_text,
                    "duration_seconds": round(dur, 2),
                    "sample_rate": runtime.sample_rate,
                    "wav_bytes": wav_path.stat().st_size,
                    "mp3_bytes": mp3_path.stat().st_size,
                    "key_mp3": f"audio-templates/breeze-tts-2/{idx}.mp3",
                    "key_wav": f"audio-templates/breeze-tts-2/{idx}.wav",
                })

    except Exception as e:
        log(f"ERROR in Breeze-TTS-2 generation: {e}")
        import traceback
        traceback.print_exc()
        raise

    # =========================================================================
    # PART 2: Chatterbox-TTS Generation
    # =========================================================================
    log("\n--- [PART 2/2] Generating Chatterbox-TTS Reference Clips ---")
    chatterbox_model_dir = workspace / "models" / "chatterbox-tts"

    try:
        from chatterbox.tts import ChatterboxTTS
        import soundfile as sf
        import torchaudio

        log(f"Loading Chatterbox-TTS from {chatterbox_model_dir} (device=cuda)...")
        cb_device = "cuda" if torch.cuda.is_available() else "cpu"
        try:
            cb_model = ChatterboxTTS.from_local(str(chatterbox_model_dir), device=cb_device)
        except Exception as e:
            log(f"Chatterbox from_local warning: {e}. Trying ChatterboxTTS.from_pretrained(device={cb_device})...")
            cb_model = ChatterboxTTS.from_pretrained(device=cb_device)
        log(f"Chatterbox-TTS loaded. Sample rate: {cb_model.sr}")

        metadata["models"]["chatterbox-tts"] = []

        # First, generate default unconditioned voice to compare & document
        log("\nGenerating Chatterbox default unconditioned speaker voice...")
        def_wav = cb_model.generate(lines[0], exaggeration=0.5, cfg_weight=0.5)
        def_wav_path = chatterbox_out_dir / "default.wav"
        def_mp3_path = chatterbox_out_dir / "default.mp3"
        torchaudio.save(str(def_wav_path), def_wav.cpu() if hasattr(def_wav, 'cpu') else torch.tensor(def_wav), cb_model.sr)
        run_cmd(f"ffmpeg -y -i {def_wav_path} -b:a 192k {def_mp3_path}")
        log(f"  Default speaker saved: {def_mp3_path} ({def_mp3_path.stat().st_size} bytes)")
        metadata["models"]["chatterbox-tts_default"] = {
            "persona": "Chatterbox Default Unconditioned Speaker",
            "text": lines[0],
            "key_mp3": "audio-templates/chatterbox-tts/default.mp3",
            "mp3_bytes": def_mp3_path.stat().st_size,
        }

        # Now generate the 3 distinct female cloned clips using the Breeze female reference audio!
        chatterbox_configs = [
            {
                "index": 1,
                "ref_audio": str(breeze_out_dir / "1.wav"),
                "text": lines[0],
                "persona": "Young & Cheerful Female (Cloned from Breeze Voice 1)",
                "exaggeration": 0.6,
                "cfg_weight": 0.5,
            },
            {
                "index": 2,
                "ref_audio": str(breeze_out_dir / "2.wav"),
                "text": lines[1],
                "persona": "Calm & Soothing Female (Cloned from Breeze Voice 2)",
                "exaggeration": 0.4,
                "cfg_weight": 0.6,
            },
            {
                "index": 3,
                "ref_audio": str(breeze_out_dir / "3.wav"),
                "text": lines[2],
                "persona": "Confident Professional Female (Cloned from Breeze Voice 3)",
                "exaggeration": 0.7,
                "cfg_weight": 0.5,
            },
        ]

        for item in chatterbox_configs:
            idx = item["index"]
            prompt_text = item["text"]
            ref_path = item["ref_audio"]
            exag = item["exaggeration"]
            cfg_w = item["cfg_weight"]

            log(f"\nGenerating Chatterbox Clip #{idx}: {item['persona']}")
            log(f"  Reference audio prompt: {ref_path}")
            log(f"  Text: {prompt_text}")

            cb_wav = cb_model.generate(
                prompt_text,
                audio_prompt_path=ref_path,
                exaggeration=exag,
                cfg_weight=cfg_w
            )

            wav_path = chatterbox_out_dir / f"{idx}.wav"
            mp3_path = chatterbox_out_dir / f"{idx}.mp3"

            tensor_wav = cb_wav.cpu() if hasattr(cb_wav, 'cpu') else torch.tensor(cb_wav)
            if tensor_wav.ndim == 1:
                tensor_wav = tensor_wav.unsqueeze(0)
            torchaudio.save(str(wav_path), tensor_wav, cb_model.sr)
            log(f"  WAV saved: {wav_path} ({wav_path.stat().st_size} bytes)")

            run_cmd(f"ffmpeg -y -i {wav_path} -b:a 192k {mp3_path}")
            log(f"  MP3 converted: {mp3_path} ({mp3_path.stat().st_size} bytes)")

            dur = tensor_wav.shape[-1] / float(cb_model.sr)
            metadata["models"]["chatterbox-tts"].append({
                "index": idx,
                "persona": item["persona"],
                "cloned_from": f"breeze-tts-2/{idx}.wav",
                "text": prompt_text,
                "duration_seconds": round(dur, 2),
                "sample_rate": cb_model.sr,
                "wav_bytes": wav_path.stat().st_size,
                "mp3_bytes": mp3_path.stat().st_size,
                "key_mp3": f"audio-templates/chatterbox-tts/{idx}.mp3",
                "key_wav": f"audio-templates/chatterbox-tts/{idx}.wav",
            })

    except Exception as e:
        log(f"ERROR in Chatterbox-TTS generation: {e}")
        import traceback
        traceback.print_exc()
        raise

    # Write metadata JSON
    meta_path = output_dir / "metadata.json"
    with open(meta_path, "w") as f:
        json.dump(metadata, f, indent=2)
    log(f"\nWrote generation metadata to {meta_path}")

    log("==========================================================")
    log("All 6 Synthetic Reference Voice Clips Generated Successfully!")
    log("==========================================================")

if __name__ == "__main__":
    main()
