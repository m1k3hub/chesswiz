import sys
from huggingface_hub import InferenceClient
out, seeds = sys.argv[1], [int(s) for s in sys.argv[2].split(",")]
prompt = (
    "A grand medieval scene painted in epic fantasy oil style. In the center a knight in shining "
    "armour rides a white horse rearing up on its hind legs. On either side of the horse stands "
    "a robed cleric with a mitre and crozier. Behind them a king and a queen with golden crowns "
    "stand side by side. The whole group stands between two tall stone watchtowers at the left and "
    "right edges. In the foreground a phalanx of soldiers with tall spears and shields, seen from "
    "behind. Dramatic sky, deep blue and gold palette, detailed, cinematic lighting, no text")
client = InferenceClient()
for seed in seeds:
    img = client.text_to_image(prompt, model="black-forest-labs/FLUX.1-schnell",
                               width=1152, height=864, num_inference_steps=4, seed=seed)
    img.save(f"{out}/splash-{seed}.png"); print("saved", seed, flush=True)
