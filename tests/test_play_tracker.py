from play_tracker import PlayTracker


def test_arp_detection():
    t = PlayTracker(arp_window=0.5, arp_min_notes=4)
    changed = False
    for _ in range(4):
        _, c = t.note_on(60)
        changed = changed or c
    assert t.arp_active
    assert changed


def test_hold_root():
    t = PlayTracker()
    t.note_on(48)
    t.note_on(60)
    t.set_hold(True)
    assert t.lowest_active_note() == 48
