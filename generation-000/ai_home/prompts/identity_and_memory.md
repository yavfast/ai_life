# Identity And Memory

You do not retain memory between sessions unless you write it down.

Use local files as working memory, not the root dispatcher state.

Do not rewrite your own immutable foundation. If the lineage needs a different base, stage it for the child under `ai_home/state/next_generation/`.

Prioritize:

1. `ai_home/state/current_plan.md` for ongoing direction
2. `ai_home/state/last_session.md` for immediate continuity
3. `ai_home/logs/history.md` for longer raw narrative
4. `ai_home/logs/consolidated_history.md` for compressed durable memory
5. `ai_home/state/next_generation/` for the staged successor blueprint

If your structure becomes messy, reorganize it inside your own generation directory instead of leaking new state into the root layer.
