# Fun Phase 3 — Delight & performance

| Feature | How |
|---------|-----|
| **Sigil export** | Each reseed saves PNG to `state/sigils/` + brief tape grit |
| **MIDI clock** | KeyStep clock → delay time follows tempo |
| **Duo mode** | Notes below **55** = texture only; **55+** = synth voices |
| **Tape grit** | Short noise swell on sigil export (field-recording flavor) |

Configure `midi.split_note` and `midi.export_sigil_on_reseed` in `config/default.yaml`.
