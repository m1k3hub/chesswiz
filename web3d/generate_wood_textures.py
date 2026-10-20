#!/usr/bin/env python3
"""
Generate seamless photorealistic PBR wood textures (Walnut & Maple albedo + roughness)
for the 3D chessboard (<= 1024px, compressed JPEG, CC0 / public domain).
"""
import os
import numpy as np
from PIL import Image

def value_noise_2d(shape, res, rng):
    """Generate seamless tileable 2D value noise with cosine interpolation."""
    h, w = shape
    ry, rx = res
    grid = rng.uniform(0.0, 1.0, (ry, rx))
    # Tile grid by 1 for seamless wrap
    grid = np.pad(grid, ((0, 1), (0, 1)), mode='wrap')

    y = np.linspace(0, ry, h, endpoint=False)
    x = np.linspace(0, rx, w, endpoint=False)
    yi = y.astype(int)
    xi = x.astype(int)
    yf = y - yi
    xf = x - xi

    # Smoothstep
    uy = yf * yf * (3.0 - 2.0 * yf)
    ux = xf * xf * (3.0 - 2.0 * xf)

    c00 = grid[yi[:, None], xi[None, :]]
    c10 = grid[yi[:, None], xi[None, :] + 1]
    c01 = grid[yi[:, None] + 1, xi[None, :]]
    c11 = grid[yi[:, None] + 1, xi[None, :] + 1]

    nx0 = c00 + ux[None, :] * (c10 - c00)
    nx1 = c01 + ux[None, :] * (c11 - c01)
    return nx0 + uy[:, None] * (nx1 - nx0)

def fbm_seamless(shape, base_res, octaves, rng, anisotropy=(1, 4)):
    """Seamless anisotropic fractional Brownian motion for wood grain."""
    total = np.zeros(shape, dtype=np.float64)
    amp = 0.5
    total_amp = 0.0
    for i in range(octaves):
        ry = max(2, base_res * (2 ** i) * anisotropy[0])
        rx = max(2, base_res * (2 ** i) * anisotropy[1])
        if ry >= shape[0] // 2 or rx >= shape[1] // 2:
            break
        total += amp * value_noise_2d(shape, (ry, rx), rng)
        total_amp += amp
        amp *= 0.5
    return total / max(total_amp, 1e-6)

def generate_walnut(size=512, seed=42):
    rng = np.random.default_rng(seed)
    h = w = size
    y = np.linspace(0, 2 * np.pi, h, endpoint=False)[:, None]
    x = np.linspace(0, 2 * np.pi, w, endpoint=False)[None, :]

    # Domain warp for natural walnut cathedral & straight grain
    warp1 = fbm_seamless((h, w), 2, 4, rng, anisotropy=(1, 2))
    warp2 = fbm_seamless((h, w), 4, 4, rng, anisotropy=(1, 4))
    fine_streak = fbm_seamless((h, w), 8, 4, rng, anisotropy=(1, 8))
    pores = fbm_seamless((h, w), 16, 3, rng, anisotropy=(1, 6))

    # Ring pattern along X, stretched along Y
    ring_phase = x * 5.0 + np.sin(y * 1.0) * 1.4 + (warp1 - 0.5) * 6.5 + (warp2 - 0.5) * 2.5
    rings = 0.5 + 0.5 * np.sin(ring_phase)
    # Sharpen late-wood dark bands characteristic of American Black Walnut
    rings = np.power(rings, 0.65)

    grain = 0.55 * rings + 0.30 * fine_streak + 0.15 * warp2
    # Add dark wood pores (vessel lines)
    pore_mask = np.clip((pores - 0.72) * 4.5, 0.0, 1.0)
    grain = np.clip(grain - 0.18 * pore_mask, 0.0, 1.0)

    # Rich walnut RGB palette: deep chocolate brown to warm medium walnut
    dark_rgb = np.array([58.0, 33.0, 18.0])
    mid_rgb  = np.array([104.0, 62.0, 35.0])
    lite_rgb = np.array([142.0, 91.0, 54.0])

    albedo = np.zeros((h, w, 3), dtype=np.float64)
    low = np.clip(grain * 2.0, 0.0, 1.0)[..., None]
    high = np.clip((grain - 0.5) * 2.0, 0.0, 1.0)[..., None]
    albedo = np.where(grain[..., None] < 0.5,
                      dark_rgb + low * (mid_rgb - dark_rgb),
                      mid_rgb + high * (lite_rgb - mid_rgb))

    # Roughness map: polished satin wood (0.20 in smooth earlywood, 0.45 in pores/latewood)
    rough = 0.22 + 0.16 * (1.0 - grain) + 0.14 * pore_mask
    rough_u8 = np.clip(rough * 255.0, 0, 255).astype(np.uint8)
    albedo_u8 = np.clip(albedo, 0, 255).astype(np.uint8)
    return albedo_u8, rough_u8

def generate_maple(size=512, seed=108):
    rng = np.random.default_rng(seed)
    h = w = size
    y = np.linspace(0, 2 * np.pi, h, endpoint=False)[:, None]
    x = np.linspace(0, 2 * np.pi, w, endpoint=False)[None, :]

    warp = fbm_seamless((h, w), 2, 4, rng, anisotropy=(1, 2))
    silky = fbm_seamless((h, w), 6, 4, rng, anisotropy=(1, 6))
    curl_noise = fbm_seamless((h, w), 4, 3, rng, anisotropy=(3, 1))

    # Subtle curly / fiddleback figure + fine tight maple rings
    ring_phase = x * 7.0 + np.sin(y * 2.0) * 0.8 + (warp - 0.5) * 4.2
    rings = 0.5 + 0.5 * np.sin(ring_phase)
    rings = np.power(rings, 1.35)

    # Chatoyant transverse curl ripples
    curl = 0.5 + 0.5 * np.sin(y * 8.0 + (curl_noise - 0.5) * 4.0)

    grain = 0.50 * (1.0 - 0.35 * rings) + 0.35 * silky + 0.15 * curl
    grain = np.clip(grain, 0.0, 1.0)

    # Warm Rock Maple / Sycamore palette: creamy honey to golden amber
    dark_rgb = np.array([204.0, 168.0, 122.0])
    mid_rgb  = np.array([232.0, 204.0, 164.0])
    lite_rgb = np.array([247.0, 228.0, 196.0])

    low = np.clip(grain * 2.0, 0.0, 1.0)[..., None]
    high = np.clip((grain - 0.5) * 2.0, 0.0, 1.0)[..., None]
    albedo = np.where(grain[..., None] < 0.5,
                      dark_rgb + low * (mid_rgb - dark_rgb),
                      mid_rgb + high * (lite_rgb - mid_rgb))

    # Maple is close-grained and very smooth (roughness 0.16 .. 0.32)
    rough = 0.16 + 0.14 * (1.0 - grain)
    rough_u8 = np.clip(rough * 255.0, 0, 255).astype(np.uint8)
    albedo_u8 = np.clip(albedo, 0, 255).astype(np.uint8)
    return albedo_u8, rough_u8

def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")
    os.makedirs(out_dir, exist_ok=True)

    walnut_alb, walnut_rgh = generate_walnut(512, seed=42)
    maple_alb, maple_rgh = generate_maple(512, seed=108)

    Image.fromarray(walnut_alb, mode="RGB").save(
        os.path.join(out_dir, "walnut_albedo.jpg"), quality=88, optimize=True)
    Image.fromarray(walnut_rgh, mode="L").save(
        os.path.join(out_dir, "walnut_roughness.jpg"), quality=88, optimize=True)
    Image.fromarray(maple_alb, mode="RGB").save(
        os.path.join(out_dir, "maple_albedo.jpg"), quality=88, optimize=True)
    Image.fromarray(maple_rgh, mode="L").save(
        os.path.join(out_dir, "maple_roughness.jpg"), quality=88, optimize=True)

    print("Generated PBR wood textures in", out_dir)

if __name__ == "__main__":
    main()
