# Taste

- Wants the assistant to read the project's existing files and understand what the project does and its established conventions before making any edits or integrating new code ("Read the files on the project folder and understand what it does, then integrate these codes also with the project"). Confidence: 0.8
- Writes defensive Bash: `set -euo pipefail`, privilege/root checks (`id -u`), validated input loops, and temp files cleaned up via `trap`. Confidence: 0.6
- Makes destructive operations reversible: timestamped backups of existing state before changes, plus printed rollback instructions. Confidence: 0.6
