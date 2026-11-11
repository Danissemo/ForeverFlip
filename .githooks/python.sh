# Finds a Python 3 for the hooks: $FF_PYTHON, the project's local tools, then python3 / python.
# (On Windows "python" may be the Microsoft Store stub, which is skipped.)
for PY in "$FF_PYTHON" "C:/FF/.tools/python/Scripts/python.exe" python3 python; do
    [ -n "$PY" ] || continue
    if "$PY" -c "import sys; sys.exit(sys.version_info < (3, 10))" >/dev/null 2>&1; then
        break
    fi
    PY=""
done
if [ -z "$PY" ]; then
    echo "[devflow] Python 3.10+ not found: set FF_PYTHON" >&2
    exit 1
fi
