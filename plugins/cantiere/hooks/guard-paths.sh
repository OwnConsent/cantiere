#!/usr/bin/env bash
# PreToolUse su Bash. Il tool Read è già confinato alla cartella di progetto:
# la via d'uscita è la shell. Questo hook la chiude.
exec python3 "$(dirname "$0")/guard-paths.py"
