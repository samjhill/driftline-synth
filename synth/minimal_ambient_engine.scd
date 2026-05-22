// V1 minimal production engine — warm poly pad → hardware bus 0 only.
// No FX buses, texture, Flues, ALSA fallback, or limiter chain.
(
var patchParams, port, scPort, bootOk, tries, voices, masterVol;

fork {
port = 57120;
NetAddr.localAddr.port = port;
("minimal_ambient_engine OSC langPort %".format(port)).postln;

patchParams = IdentityDictionary[
	\filter_cutoff -> 1600.0,
	\filter_resonance -> 0.22,
	\attack -> 0.06,
	\decay -> 0.9,
	\sustain -> 0.65,
	\release -> 2.2,
	\oscillator_blend -> 0.55,
	\sub_level -> 0.12,
	\brightness -> 0.62,
	\stereo_width -> 0.5
];
masterVol = 1.0;
voices = IdentityDictionary.new;
bootOk = false;
scPort = 57110;
if (getenv("SC_SYNTH_PORT").notNil, {
	if (getenv("SC_SYNTH_PORT").size > 0, { scPort = getenv("SC_SYNTH_PORT").asInteger });
});

s = Server(\piMinimal, NetAddr("127.0.0.1", scPort));
Server.default = s;
"minimal_ambient_engine: attach scsynth port %".format(scPort).postln;

tries = 0;
while { tries < 50 } {
	NetAddr("127.0.0.1", scPort).sendMsg("/status");
	if (s.serverRunning == true, { bootOk = true; tries = 50 }, {
		0.2.wait;
		tries = tries + 1;
	});
};

if (bootOk.not, {
	"ERROR: minimal engine — scsynth not on port %".format(scPort).postln;
	loop { 1.wait };
});

s.sync;

SynthDef(\piWarmPad, {
	|out = 0, freq = 440, amp = 0.32, gate = 1, vel = 100,
	oscBlend = 0.55, subLevel = 0.12,
	cutoff = 1600, res = 0.22, atk = 0.06, dec = 0.9, sus = 0.65, rel = 2.2,
	width = 0.5, bright = 0.62|
	var sig, env, sub, lfo, velCut, pan;
	velCut = cutoff * vel.linlin(0, 127, 0.75, 1.15);
	lfo = SinOsc.kr(0.07).range(0.97, 1.03);
	sig = Mix([
		LFSaw.ar(freq * lfo, 0, 0.38 * oscBlend),
		SinOsc.ar(freq * lfo, 0, 0.42 * (1 - oscBlend))
	]);
	sub = SinOsc.ar(freq / 2 * lfo, 0, subLevel * 0.35);
	sig = LPF.ar(sig + sub, velCut * bright.linlin(0.2, 0.95, 0.65, 1.15));
	sig = RLPF.ar(sig, velCut, res);
	env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
	pan = SinOsc.kr(0.04).range(width.neg, width);
	Out.ar(out, Pan2.ar(sig * env * amp * masterVol, pan));
}).add;

s.sync;
"minimal_ambient_engine: piWarmPad → bus 0".postln;

~spawnPad = { |note, vel = 100|
	var freq = note.midicps;
	var v = vel.clip(48, 127);
	var amp = v.linlin(48, 127, 0.28, 0.42);
	if (voices[note].notNil, { voices[note].free });
	voices[note] = Synth(\piWarmPad, [
		\out, 0,
		\freq, freq, \amp, amp, \gate, 1, \vel, v,
		\oscBlend, patchParams[\oscillator_blend],
		\subLevel, patchParams[\sub_level],
		\cutoff, patchParams[\filter_cutoff],
		\res, patchParams[\filter_resonance],
		\atk, patchParams[\attack],
		\dec, patchParams[\decay],
		\sus, patchParams[\sustain],
		\rel, patchParams[\release],
		\width, patchParams[\stereo_width],
		\bright, patchParams[\brightness]
	]);
};

~stopPad = { |note|
	if (voices[note].notNil, {
		voices[note].set(\gate, 0);
		voices.removeAt(note);
	});
};

~allOff = {
	voices.do(_.set(\gate, 0));
	voices.clear;
};

~applyPatchParam = { |key, val|
	if (val.isKindOf(String), { val = val.asString.asFloat });
	patchParams[key.asSymbol] = val;
};

~playProofChord = {
	~allOff.();
	"proof_note: chord [60,64,67] piWarmPad bus 0".postln;
	[60, 64, 67].do { |n| ~spawnPad.(n, 110) };
	fork {
		2.5.wait;
		[60, 64, 67].do { |n| ~stopPad.(n) };
	};
};

OSCdef(\minNoteOn, { |msg|
	var note = msg[1].asInteger;
	var vel = if (msg[2].notNil, { msg[2].asInteger }, { 100 });
	("note_on % vel %".format(note, vel)).postln;
	~spawnPad.(note, vel);
}, "/pi_synth/note_on");

OSCdef(\minNoteOff, { |msg|
	~stopPad.(msg[1].asInteger);
}, "/pi_synth/note_off");

OSCdef(\minProof, {
	~playProofChord.();
}, "/pi_synth/proof_note");

OSCdef(\minSetPatch, { |msg|
	var key = msg[1].asString.asSymbol;
	var val = msg[2];
	~applyPatchParam.(key, val);
	("set_patch % = %".format(key, val)).postln;
}, "/pi_synth/set_patch");

OSCdef(\minSetLegacy, { |msg|
	~applyPatchParam.(msg[1], msg[2]);
}, "/pi_synth/set");

OSCdef(\minAllOff, { ~allOff.() }, "/pi_synth/all_notes_off");
OSCdef(\minPanic, { ~allOff.() }, "/pi_synth/panic");

try {
	var f = File("/var/lib/pi-ambient-synth/sc-engine-ready", "w");
	if (f.notNil, { f.write("minimal"); f.close });
} { |err| ("WARN sc-engine-ready: %".format(err)).postln };

// One-shot JACK link after voices register (no ensure_jack_playback.sh).
fork {
	var root = getenv("PI_AMBIENT_ROOT");
	if (root.isNil or: { root.size == 0 }, { root = "/home/pi/pi-ambient-synth" });
	6.do { |i|
		("bash -c 'command -v jack_connect >/dev/null && OUT=$(jack_lsp 2>/dev/null | grep -E \"SuperCollider:out_1$\" | head -1); "
		 ++ "[ -n \"$OUT\" ] && jack_connect \"$OUT\" system:playback_1 2>/dev/null; "
		 ++ "[ -n \"$OUT\" ] && jack_connect \"$OUT\" system:playback_2 2>/dev/null; true'").unixCmd;
		if (i < 5, { 2.wait });
	};
};

"minimal_ambient_engine listening OSC % (proof_note note_on note_off set_patch)".format(port).postln;
loop { 1.wait };
};
)
