# Patch genres (monitor)

The LAN monitor **Sound** tab includes a **Genre** section that controls how **reseed** (new random patch) behaves.

## Genres

| Genre | Character |
|-------|-----------|
| **Chill** (default) | Soft, foggy, long releases — good starting point if the sound felt too bright |
| **Gentle** | Even quieter and warmer |
| **Ambient** | Spacious, reverb-heavy |
| **Deep** | Low and subdued |
| **Bright** | Glassy, more air |
| **Pulse** | More motion, still not a hard techno lead |
| **All styles** | No genre bias (full archetype range) |

Prefs are stored on the Pi at `/var/lib/pi-ambient-synth/patch-prefs.json`.

## Reseed scope

- **Reseed within genre** — random patch uses only archetypes for the selected genre, then applies genre “softening” rules.
- **Reseed across all genres** — any archetype; no genre post-processing (wilder variety).

Applies to monitor **New patch**, PiSugar button, and MIDI bridge reseed. Defaults in `config/default.yaml`: `patch.default_genre: chill`, `patch.default_reseed_scope: genre`.

## Flues timbre

In **Flues** mode, intensity and filter feedback are derived from the patch (lower brightness → softer Flues intensity). Chill/gentle genres push those values down further at generation time.
