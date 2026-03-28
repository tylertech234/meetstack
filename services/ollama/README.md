# Ollama — bind-mount config directory

Place any files here that you want available inside the Ollama container at
`/etc/ollama`. Examples:

| File / folder | Purpose |
|---|---|
| `Modelfile` | Custom Modelfile to derive a fine-tuned variant |
| `config.json` | Ollama server config overrides (if supported by your version) |

## Recommended models

Pick a model based on your deployment hardware:

| Model | Params | RAM needed | Best for |
|---|---|---|---|
| `phi3:mini` | 3.8 B | ~4 GB | **Default** — best quality/size for 8 GB SBC |
| `tinyllama` | 1.1 B | ~1 GB | Minimal SBC, fastest response |
| `gemma:2b` | 2 B | ~2 GB | Good middle ground |
| `qwen2:1.5b` | 1.5 B | ~2 GB | Strong multilingual |
| `llama3` | 8 B | ~8 GB | Best quality, needs 16 GB+ laptop/desktop |

Set your choice in `.env` as `OLLAMA_MODEL=<name>`.

## Pulling a model on first run

After `docker compose up -d`, pull a model interactively:

```bash
docker exec -it ollama ollama pull phi3:mini
```

Or use the helper script:

```bash
bash scripts/pull-model.sh
```

## Custom Modelfile example

You can create a `Modelfile` here to derive a model with a baked-in system
prompt tailored to your organisation:

```dockerfile
FROM phi3:mini

SYSTEM """
You are MeetBot, an AI assistant for your team.
You help with meeting minutes, FAQs, and scheduling.
Be professional, concise, and never fabricate information.
"""
```

Build it with:

```bash
docker exec -it ollama ollama create meetbot -f /etc/ollama/Modelfile
```

## GPU notes

See the [GPU Passthrough section in the root README](../../README.md#gpu-passthrough--ollama--nvidia-gpu)
to enable NVIDIA GPU acceleration.
