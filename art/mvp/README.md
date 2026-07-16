# Dungeon Office MVP art pack

This directory contains the first functional art pass for the **Dungeon Delivery Forge** theme. It is intentionally limited to the assets that improve the current R1–R5 graybox playtest.

## Visual contract

- Original casual fantasy workshop, presented as a chunky low-poly 3D render baked into 2D.
- Fixed three-quarter isometric camera, rounded toy-like proportions, warm upper-left forge light, and a cool teal rim.
- Ember orange, honey wood, cream parchment, navy-charcoal metal, muted teal, and enhancement violet.
- Large silhouettes remain readable on a 360×640 logical canvas.
- No runtime `Node3D`, remote download, copyrighted character, copied commercial-game layout, or third-party runtime asset.

## Runtime files

| Group | Files | Runtime size |
|---|---|---:|
| Title art | `backgrounds/bg_title_forge.png` | 720×1080 RGB PNG |
| Facilities | `fac_supply`, `fac_furnace`, `fac_weapon_bench`, `fac_synth_bench`, `fac_enhance_anvil`, `fac_trash`, `fac_delivery` | 384×384 RGBA PNG each |
| Items | `mat_iron_ore`, `mat_wood`, `mat_mana_shard`, `mat_iron_ingot`, `mat_charcoal`, `mat_enhancement_stone`, `eq_dagger`, `eq_iron_sword` | 256×256 RGBA PNG each |

The runtime code resolves textures by content ID. Simulation and content JSON do not contain presentation paths.

## Generation provenance

The images were generated specifically for this project on 2026-07-15 with the built-in OpenAI image generation workflow. No external asset pack was copied into the repository. The generated cutouts were produced on a flat green chroma-key background, processed with the imagegen skill's `remove_chroma_key.py` soft matte and despill workflow, then resized with linear filtering. The title illustration was downscaled without compositing new content.

Shared generation prompt:

> Original casual mobile fantasy blacksmith asset, polished 2D illustration that convincingly looks like a chunky low-poly 3D game render; rounded toy-like proportions, beveled facets, simplified readable materials; fixed three-quarter isometric camera around 30 degrees; warm upper-left key light and cool teal rim; ember orange, honey gold, cream, dark navy-charcoal, muted teal, with violet only for enhancement. No text, logo, watermark, copyrighted character, copied game layout, pixel art, photorealism, clutter, or thin fragile detail.

The transparent cutouts additionally requested a perfectly flat `#00ff00` background with no floor, shadow, reflection, gradient, or use of the key color in the subject. Individual subjects were:

- Open three-cubby supply cabinet containing iron ore, short logs, and small mana shards.
- Compact stone-and-iron furnace with contained fire and ingot ledge.
- Weapon bench with integrated anvil and hammer rack.
- Synthesis bench with mixing basin and two violet crystal sockets.
- Enhancement anvil above a restrained violet crystal core.
- Open scrap barrel with harmless bent metal pieces.
- Delivery counter with parcel crate, blank parchment tag, and brass bell.
- Three iron ore rocks; two tied logs; three small mana shards; one iron ingot; three charcoal pieces; one refined enhancement stone; one iron dagger; one iron sword.

The title prompt requested a cozy dungeon-side service forge with two small goblin apprentices and a three-person adventuring party, leaving clean upper space for native UI title text.

## Replacement rules

- Keep filenames and content-ID mapping stable when iterating.
- Preserve camera, lighting direction, silhouette scale, and semantic colors.
- Test item icons at 24–32 logical pixels and facilities at 48–64 logical pixels.
- Do not add future paid-stage assets before that scope is approved.
- If a third-party asset is introduced later, record its author, source URL, version, license, modification, and attribution obligations before bundling it.
