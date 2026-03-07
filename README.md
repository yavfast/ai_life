# AI Life

## Model

The repository now contains a generation template, not a live shared runtime.

`generation-000` is only the seed template.

The first real generation is created at runtime as `generation-001` inside a runtime home directory. By default that runtime home is `~/.ai_life`.

## Runtime layout

On first launch, the dispatcher creates:

```text
~/.ai_life/
├── generation-001/
│   ├── run_generation.sh
│   ├── config.sh
│   ├── scripts/
│   └── ai_home/
├── logs/
│   ├── dispatcher.log
│   └── generation-001.log
└── state/
    └── active_generations.txt
```

The repository keeps only the template and root helper scripts.

## How it runs

`run_ai.sh` is the dispatcher.

It does the following:

1. Loads `.env` for OpenRouter credentials.
2. Creates the runtime home if needed.
3. Bootstraps `generation-001` from the `generation-000` template if no live generation exists yet.
4. Runs active generations from `~/.ai_life/state/active_generations.txt`.

Default launch:

```bash
./run_ai.sh
```

Custom runtime home:

```bash
./run_ai.sh --home /path/to/runtime
```

Run only one generation:

```bash
./run_ai.sh --home ~/.ai_life --only generation-001
```

## LiteLLM runtime

Each live generation uses LiteLLM directly.

Default provider:

- OpenRouter

Default model:

- `arcee-ai/trinity-large-preview:free`

Generation-specific model settings live in each generation's own `config.sh`, so descendants can choose different models later without changing the dispatcher.

## OpenRouter config

The repository `.env` should contain:

```bash
OPENROUTER_API_KEY="..."
OPENROUTER_API_BASE="https://openrouter.ai/api/v1"
AI_LIFE_DEFAULT_MODEL="arcee-ai/trinity-large-preview:free"
```

You can rewrite that file with:

```bash
./setup-openrouter.sh YOUR_KEY
```

## User messages

Use `send_message.sh` to send a human message to the current live generation.

It will:

1. Create a message file in the generation inbox.
2. Force an immediate session run for that generation.
3. Wait until the response is written back into that same message file.

Example:

```bash
./send_message.sh "Tell me what files you want to inspect first."
```

Or with explicit runtime home and generation:

```bash
./send_message.sh --home ~/.ai_life --generation generation-001 "Please introduce yourself."
```

User messages are treated as human communication, not as mandatory commands.

## Successors

A live generation can create the next one from inside its own runtime home:

```bash
./scripts/create_next_generation.sh generation-002 --activate
```

The new generation inherits the local runtime structure and starts with a reset state plus the prompt drafted in `ai_home/state/next_generation_system_prompt.md`.
