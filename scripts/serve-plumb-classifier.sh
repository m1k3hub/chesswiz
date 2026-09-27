#!/bin/sh
# serve-plumb-classifier.sh -- download Plumb-4B from Hugging Face and serve
# the /v1/systemone decision contract on this machine.
#
# Plumb-4B (crh225/plumb-4b, Apache-2.0) is the strongest open System One
# decision model that runs in one pass on an 8 GB card: JevBench v1.4.2.1
# ranks it first of the open systems (65.84, ahead of TypeSafe's hosted Jev).
# The bf16 CUDA runtime needs ~10 GB; this script serves the official Q8_0
# GGUF (4.5 GB, closest to the full model) through llama.cpp, wrapping it in
# the TypeSafe wire contract with scripts/plumb-systemone-server.py.
#
#   scripts/serve-plumb-classifier.sh            # download if needed, serve
#   PLUMB_GPU=3 scripts/serve-plumb-classifier.sh
#   PLUMB_QUANT=Q4_K_M scripts/serve-plumb-classifier.sh   # 2.7 GB instead
#
# Scidb picks the server up as the System One backend "plumb"
# (Extras > AI: Choose Model, or --ai-classifier=plumb):
#   endpoint http://127.0.0.1:8090/v1/systemone, model plumb-4b-v5
#
# Environment:
#   PLUMB_MODEL_DIR    where the GGUF lives and downloads to (~/models/plumb)
#   PLUMB_QUANT        Q8_0 (default, ~4.5 GB) or Q4_K_M (~2.7 GB)
#   PLUMB_GPU          CUDA device index, "auto" (default: the card with the
#                      most free memory), "cpu", or a fixed index
#   PLUMB_PORT         llama-server port (8080)
#   PLUMB_SYSTEMONE_PORT  the /v1/systemone port Scidb talks to (8090)
#   PLUMB_CONTEXT      context window in tokens (8192)

set -eu

REPO="crh225/plumb-4b-GGUF"
MODEL_DIR="${PLUMB_MODEL_DIR:-$HOME/models/plumb}"
QUANT="${PLUMB_QUANT:-Q8_0}"
GPU="${PLUMB_GPU:-auto}"
LLAMA_PORT="${PLUMB_PORT:-8080}"
PORT="${PLUMB_SYSTEMONE_PORT:-8090}"
CONTEXT="${PLUMB_CONTEXT:-8192}"
GGUF="plumb-4b-v5-$QUANT.gguf"
HERE="$(cd "$(dirname "$0")" && pwd)"

download() {
	echo "Downloading $REPO/$GGUF (~$([ "$QUANT" = Q8_0 ] && echo 4.5 || echo 2.7) GB) to $MODEL_DIR ..."
	mkdir -p "$MODEL_DIR"
	if command -v hf >/dev/null 2>&1; then
		hf download "$REPO" "$GGUF" --local-dir "$MODEL_DIR"
	else
		# the same file straight from the CDN, resumed on a repeat run
		curl -L --fail --retry 3 -C - \
			-o "$MODEL_DIR/$GGUF.part" \
			"https://huggingface.co/$REPO/resolve/main/$GGUF" \
			|| { echo "download failed: install huggingface_hub ('hf') or check the network" >&2; exit 1; }
		mv "$MODEL_DIR/$GGUF.part" "$MODEL_DIR/$GGUF"
	fi
}

pick_gpu() {
	# the CUDA device with the most free memory, if any has room
	command -v nvidia-smi >/dev/null 2>&1 || { echo "cpu"; return; }
	nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits 2>/dev/null \
		| sort -t, -k2 -nr | head -1 | cut -d, -f2 -f1 | while read -r free rest; do
			[ "$free" -ge 5500 ] && echo "$rest" && return
			echo "cpu" && return
		done
}

[ -f "$MODEL_DIR/$GGUF" ] || download
echo "Serving $MODEL_DIR/$GGUF"

# the /v1/systemone readout needs jevk5 >= 0.3 for the GGUF knockout path
# (routing questions with more than 16 options; 0.2.x rejects them);
# it is standard library only on this path (no torch)
if ! python3 -c "import jevk5, sys; sys.exit(0 if jevk5.__version__ >= '0.3' else 1)" >/dev/null 2>&1; then
	echo "Installing the jevk5 readout package (standard library only) ..."
	python3 -m pip install --no-deps "jevk5 @ git+https://github.com/allebee/jevk5@v0.3.3"
fi

NGML=99
CUDA_ENV=""
case "$GPU" in
	cpu) NGML=0 ;;
	auto)
		picked="$(pick_gpu)"
		case "$picked" in
			cpu) NGML=0 ;;
			*) GPU="$picked" ;;
		esac
		;;
esac
if [ "$NGML" = 99 ]; then
	CUDA_ENV="CUDA_VISIBLE_DEVICES=$GPU"
	echo "Using GPU $GPU"
else
	echo "Using CPU"
fi

cleanup() {
	[ -n "${LLAMA_PID:-}" ] && kill "$LLAMA_PID" 2>/dev/null || true
	[ -n "${SHIM_PID:-}" ] && kill "$SHIM_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

# shellcheck disable=SC2086
env $CUDA_ENV llama-server -m "$MODEL_DIR/$GGUF" -c "$CONTEXT" -ngl $NGML \
	--port "$LLAMA_PORT" --host 127.0.0.1 &
LLAMA_PID=$!

echo "Waiting for llama-server ..."
i=0
until curl -sf "http://127.0.0.1:$LLAMA_PORT/health" >/dev/null 2>&1; do
	i=$((i + 1))
	if [ "$i" -gt 300 ] || ! kill -0 "$LLAMA_PID" 2>/dev/null; then
		echo "llama-server did not come up" >&2; exit 1
	fi
	sleep 2
done

python3 "$HERE/plumb-systemone-server.py" --llama "http://127.0.0.1:$LLAMA_PORT" --port "$PORT" &
SHIM_PID=$!
echo "Plumb-4B classifier on http://127.0.0.1:$PORT/v1/systemone (Scidb backend: plumb)"

wait