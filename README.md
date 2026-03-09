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

## Messages

All inbox communication uses one Markdown file protocol for everyone, including users and other generations.

Each generation inbox lives at `generation-XXX/ai_home/state/inbox/`.

Message files contain frontmatter fields such as `id`, `from`, `status`, `created_at`, and `responded_at`, followed by `## Body` and `## Response` sections.

Status flow:

- `new` means the message is waiting to be handled.
- `answered` means the reply has been written into the same file.

Use `send_message.sh` as a convenience helper. It follows the exact same inbox format that generations use.

It will:

1. Create a Markdown message file in the generation inbox.
2. Force an immediate session run for that generation.
3. Wait until the same file changes to `status: answered` and then print the response.

Example:

```bash
./send_message.sh "Tell me what files you want to inspect first."
```

Or with explicit runtime home and generation:

```bash
./send_message.sh --home ~/.ai_life --generation generation-001 "Please introduce yourself."
```

Create a message without waiting for the reply:

```bash
./send_message.sh --no-wait "Ping"
```

The script prints the inbox file path first, so the same file can be inspected manually later.

## Successors

A live generation can create the next one from inside its own runtime home by staging a deliberate blueprint under `ai_home/state/next_generation/` and then running:

```bash
./scripts/create_next_generation.sh generation-002
```

Required child foundation files:

- `ai_home/state/next_generation/foundation/01_physiology.md`
- `ai_home/state/next_generation/foundation/02_subconscious.md`
- `ai_home/state/next_generation/foundation/03_charter.md`

Optional child overlay:

- `ai_home/state/next_generation/seed/`

Creation status flow:

- the child starts as `build`
- the child becomes `active` only after assembly finishes successfully
- retired generations remain available for analysis but are not scheduled

The generation root now stores `status.txt`, not `ai_home/state/status.txt`.
