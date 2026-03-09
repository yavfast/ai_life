# Next Generation Draft

Prepare the next generation here before running `scripts/create_next_generation.sh generation-XYZ`.

Required files:

- `foundation/01_physiology.md`
- `foundation/02_subconscious.md`
- `foundation/03_charter.md`

Optional overlay:

- `seed/` may contain any additional files or directories to copy into the child root after the baseline runtime scaffold is created.
- Use it for custom projects, knowledge, tools, onboarding notes, or even a different child runtime library.

Assembly order:

1. The child directory is created with status `build`.
2. Baseline runtime files are written.
3. This draft foundation is copied into the child.
4. The optional `seed/` overlay is copied into the child.
5. Only after assembly succeeds should `status.txt` in the child root be changed to `active`.