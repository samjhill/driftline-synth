// Pi Ambient Synth — SuperCollider headless engine (phase 1 fun)
(
var patchParams, morphTime, masterVol, evolveEnabled, evolveRoutine;
var synthGroup, textureSynth, limiterSynth, companionSynth;
var textureRoot, holdLatch, arpActive, duckLevel, weatherAmt, companionOn, clockBpm;
var port, useAlsaSynth, engineTest, bootOk, scPort, tries;

bootOk = false;
port = 57120;

// Pi SC 3.13: entire engine in one Routine (s.sync + 1.wait work; join/hang/sleep/unixCmd do not).
fork {
NetAddr.localAddr.port = port;
("sclang OSC langPort %".format(NetAddr.localAddr.port)).postln;

patchParams = IdentityDictionary.new;
morphTime = 6.0;
masterVol = 1.0;
evolveEnabled = false;
textureRoot = 48;
holdLatch = false;
arpActive = false;
duckLevel = 1.0;
weatherAmt = 0.5;
companionOn = false;
clockBpm = 120.0;

patchParams[\filter_cutoff] = 1400.0;
patchParams[\filter_resonance] = 0.2;
patchParams[\attack] = 0.05;
patchParams[\decay] = 0.8;
patchParams[\sustain] = 0.6;
patchParams[\release] = 2.5;
patchParams[\oscillator_blend] = 0.5;
patchParams[\sub_level] = 0.15;
patchParams[\noise_level] = 0.05;
patchParams[\drift_amount] = 0.008;
patchParams[\lfo_rate] = 0.08;
patchParams[\lfo_depth] = 0.08;
patchParams[\delay_mix] = 0.2;
patchParams[\delay_time] = 0.5;
patchParams[\reverb_mix] = 0.45;
patchParams[\reverb_size] = 0.75;
patchParams[\texture_density] = 0.5;
patchParams[\stereo_width] = 0.7;
patchParams[\brightness] = 0.6;
patchParams[\root_note] = 48;

~configureServerAudio = { |srv|
	var opt = srv.options;
	var env = getenv("SC_AUDIO_DEVICE");
	// hw:0,0 — plughw:0,0 can make JACK report client name '0,0' and break sclang↔scsynth link.
	var dev = "hw:0,0";
	if(env.isNil.not, {
		if(env.size > 0, { dev = env });
	});
	opt.numOutputBusChannels = 2;
	opt.numInputBusChannels = 2;
	// Pi scsynth+JACK often locks to 48000; match to avoid silent or wrong-rate output.
	opt.sampleRate = 48000;
	opt.device = dev;
	"SC_AUDIO_DEVICE=% (jackd ALSA device; scsynth is JACK client)".format(dev).postln;
	dev;
};

useAlsaSynth = getenv("SC_HEADLESS_ALSA").notNil;
engineTest = getenv("SC_ENGINE_TEST").notNil;
"Pi Ambient Synth engine script loading (build sc313-audibleFx)".postln;
"Booting Pi Ambient Synth engine...".postln;
scPort = 57110;
if(getenv("SC_SYNTH_PORT").notNil, {
	if(getenv("SC_SYNTH_PORT").size > 0, { scPort = getenv("SC_SYNTH_PORT").asInteger });
});
s = Server(\piAmbient, NetAddr("127.0.0.1", scPort));
Server.default = s;
~audioDevice = ~configureServerAudio.(s);
if(useAlsaSynth, {
	var scAddr;
	scAddr = NetAddr("127.0.0.1", scPort);
	"Attaching sclang to shell scsynth (port %)".format(scPort).postln;
	~piDoneOSC = OSCFunc({ |msg|
		bootOk = true;
		"scsynth /done: %".format(msg).postln;
	}, "/done");
	~piStatusOSC = OSCFunc({ |msg|
		bootOk = true;
		"scsynth /status.reply: %".format(msg).postln;
	}, "/status.reply");
	tries = 0;
	while { tries < 40 } {
		if(bootOk == true, {
			tries = 40;
		}, {
			scAddr.sendMsg("/notify", 0, port, "127.0.0.1");
			0.15.wait;
			scAddr.sendMsg("/status");
			if(s.serverRunning == true, { bootOk = true });
			tries = tries + 1;
			0.2.wait;
		});
	};
	~piDoneOSC.free;
	~piStatusOSC.free;
	if(bootOk == true, {
		try { s.serverRunning_(true) };
		s.sync;
	});
}, {
	Server.killAll;
	if(s.serverRunning == true, {
		s.quit;
		0.5.wait;
	});
	"Starting scsynth with ALSA device: %".format(~audioDevice).postln;
	s.boot;
	s.sync;
	bootOk = (s.serverRunning == true);
});
if(bootOk == true, {
	if(useAlsaSynth, {
		"scsynth connected (external jackd) — device: %".format(~audioDevice).postln;
	}, {
		("scsynth running — device: %, rate: %, out ch: %".format(
			s.options.device, s.serverSampleRate, s.options.numOutputBusChannels
		)).postln;
	});
}, {
	if(useAlsaSynth, {
		"ERROR: SC_HEADLESS_ALSA set but scsynth not on port 57110 — run start_scsynth_alsa.sh".postln;
	}, {
		"ERROR: sclang not connected to scsynth — pgrep scsynth; SC_AUDIO_DEVICE".postln;
	});
});

if(bootOk != true, {
	if(engineTest, {
		"Pi Ambient Synth ENGINE_TEST failed: scsynth not connected".postln;
		0.exit;
	});
	loop { 1.wait };
});

~setParam = { |key, val|
	patchParams[key.asSymbol] = val;
};

~morphParam = { |key, target, time|
	// Pi SC 3.13: Bus.linearRamp is missing — set target immediately.
	var busKey = ("morph_" ++ key).asSymbol;
	patchParams[key.asSymbol] = target;
	if(~morphBuses.notNil, {
		if(~morphBuses[busKey].notNil, {
			~morphBuses[busKey].set(target);
		});
	});
};

~applyPatch = {
	|time|
	var t = time ? morphTime;
	[
		\filter_cutoff, \filter_resonance, \attack, \decay, \sustain, \release,
		\oscillator_blend, \sub_level, \noise_level, \drift_amount,
		\lfo_rate, \lfo_depth, \delay_mix, \delay_time, \reverb_mix, \reverb_size,
		\texture_density, \stereo_width, \brightness, \root_note
	].do { |k|
		if(patchParams[k].notNil, {
			~morphParam.(k, patchParams[k], t);
		});
	};
	if(textureSynth.notNil, {
		textureRoot = patchParams[\root_note] ? 48;
		textureSynth.set(
			\density, patchParams[\texture_density] ? 0.5,
			\root, textureRoot,
			\noise, patchParams[\noise_level] ? 0.05,
			\rev, patchParams[\reverb_mix] ? 0.45
		);
	});
};

~startEvolve = {
	if(evolveRoutine.notNil, { evolveRoutine.stop });
	evolveRoutine = fork {
		loop {
			8.wait;
			if(evolveEnabled == false, {
				evolveRoutine = nil;
				^this;
			});
			[
				{ ~morphParam.(\filter_cutoff, (patchParams[\filter_cutoff] * rrand(0.88, 1.12)).clip(450, 4200), 6) },
				{ ~morphParam.(\reverb_size, (patchParams[\reverb_size] + rrand(-0.08, 0.12)).clip(0.55, 0.98), 10) },
				{ ~morphParam.(\lfo_depth, (patchParams[\lfo_depth] + rrand(-0.04, 0.06)).clip(0.02, 0.22), 5) },
				{ ~morphParam.(\texture_density, (patchParams[\texture_density] + rrand(-0.1, 0.1)).clip(0.1, 0.9), 8) },
			].choose.value;
		};
	};
};

// Bus 8 = engine submix; bus 0 = hardware (after piLimiter).
SynthDef(\piAmbientVoice, {
	|out=8, freq=440, amp=0.3, gate=1, vel=100,
	oscBlend=0.5, subLevel=0.15, noiseLevel=0.05,
	cutoff=1400, res=0.2, atk=0.05, dec=0.8, sus=0.6, rel=2.5,
	drift=0.008, lfoRate=0.08, lfoDepth=0.08, width=0.7, bright=0.6,
	delayMix=0.2, revMix=0.45|
	var sig, env, sub, noise, lfo, pan, velCut;
	velCut = cutoff * vel.linlin(0, 127, 0.72, 1.18);
	lfo = SinOsc.kr(lfoRate).range(1 - lfoDepth, 1 + lfoDepth);
	sig = Mix([
		LFSaw.ar(freq * lfo * (1 + drift * LFNoise2.kr(0.2)), 0, 0.35 * oscBlend),
		SinOsc.ar(freq * lfo, 0, 0.4 * (1 - oscBlend)),
		LFTri.ar(freq * lfo, 0, 0.25 * oscBlend)
	]);
	sub = SinOsc.ar(freq / 2 * lfo, 0, subLevel * 0.4);
	noise = PinkNoise.ar(noiseLevel * 0.08);
	sig = sig + sub + noise;
	sig = LPF.ar(sig, velCut * bright.linlin(0.2, 0.95, 0.6, 1.2));
	sig = RLPF.ar(sig, velCut, res);
	env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
	pan = SinOsc.kr(0.05 + (width * 0.08)).range(width.neg * 1.2, width * 1.2);
	sig = Pan2.ar(sig * env * amp, pan);
	Out.ar(out, sig);
	Out.ar(6, sig * delayMix);
	Out.ar(4, sig * revMix);
}).add;

SynthDef(\piTextureDrone, {
	|out=8, root=48, density=0.5, noise=0.05, rev=0.45, duck=1.0, shimmer=0.0, amp=1.0|
	var freq, sig, fifth, oct, pan;
	freq = root.midicps;
	fifth = (root + 7).midicps;
	oct = (root + 12).midicps;
	sig = Mix([
		SinOsc.ar(freq * (1 + LFNoise2.kr(0.03).range(0, density * 0.004)), 0, 0.12),
		SinOsc.ar(fifth * (1 + LFNoise2.kr(0.02).range(0, density * 0.003)), 0, 0.08),
		SinOsc.ar(oct, 0, 0.05),
		LPF.ar(PinkNoise.ar(noise * 0.04), 800),
		SinOsc.ar(oct * 2, 0, shimmer * 0.03)
	]);
	sig = sig * LFNoise1.kr(0.02).range(0.55, 1.0) * duck * amp;
	pan = SinOsc.kr(0.03 + (SinOsc.kr(0.01) * 0.02)).range(-0.55, 0.55);
	Out.ar(out, Pan2.ar(sig, pan));
	Out.ar(4, sig * rev * 0.65);
}).add;

SynthDef(\piDelayFx, { |inBus=6, out=8, mix=0.25, dt=0.5|
	var wet = In.ar(inBus, 2);
	wet = CombC.ar(wet, 2.0, dt, 4);
	Out.ar(out, LeakDC.ar(wet * mix));
}).add;

SynthDef(\piReverbFx, { |inBus=4, out=8, mix=0.45, room=0.8|
	var wet = In.ar(inBus, 2);
	wet = FreeVerb.ar(wet, 1.0, room, 0.85);
	Out.ar(out, LeakDC.ar(wet * mix));
}).add;

SynthDef(\piStartupChime, { |out=8, freq=523.25, amp=0.55, gate=1, pan=0|
	var sig = SinOsc.ar(freq) * EnvGen.kr(Env.perc(0.008, 0.38, 1, -4), gate, doneAction: 2);
	Out.ar(out, Pan2.ar(sig * amp, pan));
}).add;

SynthDef(\piCompanion, {
	|root=48, gate=1, density=0.35|
	var scale, idx, deg, freq, sig, env, interval;
	scale = [0, 2, 3, 5, 7, 9, 10];
	interval = LFNoise0.kr(0.08).range(3.5, 14.0);
	// Pi SC 3.13: scale[deg] needs integer index — use Select.kr.
	idx = TRand.kr(0, scale.size, Dust.kr(interval)).floor.clip(0, scale.size - 1);
	deg = Latch.kr(idx, Dust.kr(interval));
	freq = (root + Select.kr(deg, scale)).midicps;
	sig = SinOsc.ar(freq) * 0.06;
	env = EnvGen.kr(Env.asr(1.5, 0, 4.0), gate, doneAction: 2);
	Out.ar(4, sig * env * density);
}).add;

SynthDef(\piLimiter, { |in=8, out=0, level=0.9|
	var sig = In.ar(in, 2);
	// bcm2835 headphone jack is effectively mono — sum L/R so neither channel is silent.
	sig = Mix(sig) ! 2;
	sig = (sig * (1 / level)).tanh * level;
	// Out.ar (not ReplaceOut) so keyboard piRawTone after limiter is not cleared on bus 0.
	Out.ar(out, LeakDC.ar(sig));
}).add;

SynthDef(\piRawTone, { |out=0, freq=440, amp=0.7, dur=0.5|
	var sig = SinOsc.ar(freq) * EnvGen.kr(Env.perc(0.005, dur, 1, -4), doneAction: 2);
	Out.ar(out, (sig ! 2) * amp);
}).add;

~textureAmp = { |vol|
	if(~engineNodeRunning.(textureSynth), {
		textureSynth.set(\amp, (vol ? masterVol) * 1.6);
	});
};

~playStartupChime = {
	if(limiterSynth.isNil, {
		"startup chime skipped (engine not ready)".postln;
		^this;
	});
	"Pi Ambient Synth startup chime".postln;
	[
		[523.25, 0, 0.52],
		[659.25, 0.08, 0.48],
		[783.99, 0.16, 0.44],
		[1046.5, 0.24, 0.5]
	].do { |row|
		var f = row[0], waitT = row[1], a = row[2];
		Synth.before(limiterSynth, \piStartupChime, [\freq, f, \amp, a, \gate, 1, \pan, -0.25]);
		Synth.before(limiterSynth, \piStartupChime, [\freq, f * 1.002, \amp, a * 0.85, \gate, 1, \pan, 0.25]);
		waitT.wait;
	};
};

~voices = IdentityDictionary.new;
~noteActivity = 0;

~setDuck = {
		var target = if(arpActive, 0.55, 1.0);
		duckLevel = target;
		if(~engineNodeRunning.(textureSynth), { textureSynth.set(\duck, target) });
	};

~playKeyboardAudible = { |freq, amp=0.95, dur=0.35|
		var a = amp.clip(0.65, 1.0);
		~ensureEngine.();
		// Tail of root group so tone is last in chain; duplicate to hardware bus 0.
		if(limiterSynth.notNil, {
			Synth.after(limiterSynth, \piRawTone, [\freq, freq, \amp, a, \dur, dur, \out, 0]);
		}, {
			Synth.tail(s, \piRawTone, [\freq, freq, \amp, a, \dur, dur, \out, 0]);
		});
	};

~playNote = { |note, vel=100|
		var freq = note.midicps;
		var v = vel.clip(48, 127);
		var amp = v.linlin(48, 127, 0.55, 1.0) * masterVol.max(0.85);
		var rel = (patchParams[\release] ? 1.2).clip(0.25, 2.5);
		("playNote: midi % vel % (used %) amp %".format(note, vel, v, amp.round(0.001))).postln;
		~playKeyboardAudible.(freq, amp, rel);
		~noteActivity = (~noteActivity + 1).max(0);
		if(~engineNodeRunning.(textureSynth), { textureSynth.set(\duck, 0.42) });
		if(limiterSynth.isNil, {
			"playNote: engine not initialized (no limiterSynth)".postln;
			^this;
		});
		if(~voices[note].notNil, { ~voices[note].free });
		~voices[note] = Synth.before(limiterSynth, \piAmbientVoice, [
			\freq, freq, \amp, amp, \gate, 1, \vel, v,
			\oscBlend, patchParams[\oscillator_blend] ? 0.5,
			\subLevel, patchParams[\sub_level] ? 0.15,
			\noiseLevel, patchParams[\noise_level] ? 0.05,
			\cutoff, patchParams[\filter_cutoff] ? 1400,
			\res, patchParams[\filter_resonance] ? 0.2,
			\atk, patchParams[\attack] ? 0.05,
			\dec, patchParams[\decay] ? 0.8,
			\sus, patchParams[\sustain] ? 0.6,
			\rel, patchParams[\release] ? 2.5,
			\drift, patchParams[\drift_amount] ? 0.008,
			\lfoRate, patchParams[\lfo_rate] ? 0.08,
			\lfoDepth, patchParams[\lfo_depth] ? 0.08,
			\width, patchParams[\stereo_width] ? 0.7,
			\bright, patchParams[\brightness] ? 0.6,
			\delayMix, patchParams[\delay_mix] ? 0.2,
			\revMix, patchParams[\reverb_mix] ? 0.45
		]);
};

~stopNote = { |note|
		if(~voices[note].notNil, {
			~voices[note].set(\gate, 0);
			~voices.removeAt(note);
		});
		~noteActivity = (~noteActivity - 1).max(0);
		if(~noteActivity <= 0, {
			fork {
				1.5.wait;
				if(~noteActivity <= 0, { ~setDuck.() });
			};
		});
};

~allOff = {
		~voices.do(_.set(\gate, 0));
		~voices.clear;
		~noteActivity = 0;
		~setDuck.();
};

~panic = {
	~allOff.();
};

~panicBloom = {
		fork {
			2.5.wait;
			if(textureSynth.notNil, {
				textureSynth.set(\density, (patchParams[\texture_density] ? 0.5) * 0.7);
			});
			masterVol = (masterVol * 0.35).max(0.12);
			3.wait;
			~applyPatch.(5);
			masterVol = 0.65;
		};
};

~engineNodeRunning = { |node|
	if(node.isNil, { ^false });
	try { ^node.isRunning } { ^false };
};

~skipTextureDrone = getenv("PI_SKIP_TEXTURE_DRONE").notNil;

~initEngineSynths = {
	var g, skipTex;
	skipTex = ~skipTextureDrone;
	~voices.do(_.free);
	~voices.clear;
	if(textureSynth.notNil, {
		try { textureSynth.free } {};
		textureSynth = nil;
	});
	if(limiterSynth.notNil, {
		try { limiterSynth.free } {};
		limiterSynth = nil;
	});
	if(synthGroup.notNil, {
		try { synthGroup.freeAll } {};
	});
	s.sync;
	~morphBuses = IdentityDictionary.new;
	g = Group.tail(s);
	synthGroup = g;
	if(skipTex.not, {
		textureSynth = Synth.tail(g, \piTextureDrone, [\root, 48, \density, 0.55, \amp, masterVol * 1.6]);
	});
	Synth.tail(g, \piReverbFx, [\inBus, 4, \out, 8, \mix, 0.42, \room, 0.8]);
	Synth.tail(g, \piDelayFx, [\inBus, 6, \out, 8, \mix, 0.18, \dt, 0.5]);
	limiterSynth = Synth.tail(g, \piLimiter, [\in, 8, \out, 0, \level, 0.92]);
	s.sync;
	if(skipTex, {
		"Engine synths started (keyboard voices + FX; no texture drone)".postln;
	}, {
		"Engine synths started (texture drone + FX chain)".postln;
	});
};

~engineHealthy = {
	~engineNodeRunning.(limiterSynth) and: {
		if(~skipTextureDrone, { true }, { ~engineNodeRunning.(textureSynth) });
	};
};

~ensureEngine = {
	if(~engineHealthy.value.not, {
		"ensureEngine: rebuilding (engine nodes missing or not running)".postln;
		~initEngineSynths.();
	});
};

if(bootOk == true, {
	~initEngineSynths.();
	fork {
		1.2.wait;
		if(useAlsaSynth, {
			var envRoot = getenv("PI_AMBIENT_ROOT");
			var root = if(envRoot.notNil, {
				if(envRoot.size > 0, { envRoot }, { "/home/pi/pi-ambient-synth" })
			}, { "/home/pi/pi-ambient-synth" });
			5.do { |i|
				if(0 < i, { 0.6.wait });
				(root + "/scripts/ensure_jack_playback.sh 2>/dev/null || true").unixCmd;
			};
		});
		~playStartupChime.();
	};
	fork {
		loop {
			15.wait;
			~ensureEngine.();
			if(useAlsaSynth, {
				var envRoot = getenv("PI_AMBIENT_ROOT");
				var root = if(envRoot.notNil, {
					if(envRoot.size > 0, { envRoot }, { "/home/pi/pi-ambient-synth" })
				}, { "/home/pi/pi-ambient-synth" });
				(root + "/scripts/ensure_jack_playback.sh 2>/dev/null || true").unixCmd;
			});
		};
	};
}, {
	"WARN: scsynth not running — OSC registered but notes will not sound".postln;
});

OSCdef(\piNoteOn, { |msg|
		var note = msg[1].asInteger;
		var vel = if(msg[2].notNil, { msg[2].asInteger }, { 100 });
		("OSC note_on % vel %".format(note, vel)).postln;
		~playNote.(note, vel);
	}, "/pi_synth/note_on");

	OSCdef(\piNoteOff, { |msg|
		~stopNote.(msg[1].asInteger);
	}, "/pi_synth/note_off");

OSCdef(\piSet, { |msg|
		var key = msg[1].asString.asSymbol;
		var val = msg[2];
		if(key == \master_volume, {
			masterVol = val;
			~textureAmp.(val);
		}, {
			if(key == \name, {
				// Python patch metadata — not a synth float param
			}, {
				if(key == \scale_name, {
					// Python patch metadata — not a synth float param
				}, {
					if(val.isKindOf(String), { val = val.asString.asFloat });
					~setParam.(key, val);
				});
			});
		});
	}, "/pi_synth/set");

	OSCdef(\piMorphTime, { |msg|
		morphTime = msg[1] ? 6.0;
	}, "/pi_synth/morph_time");

	OSCdef(\piPatchLoaded, { |msg|
		~applyPatch.(morphTime);
	}, "/pi_synth/patch_loaded");

	OSCdef(\piReseedTransition, { |msg|
		var dur = msg[1] ? 2.0;
		if(textureSynth.notNil, {
			textureSynth.set(\rev, (patchParams[\reverb_mix] ? 0.45) + 0.15);
			fork {
				dur.wait;
				textureSynth.set(\rev, patchParams[\reverb_mix] ? 0.45);
			};
		});
	}, "/pi_synth/reseed_transition");

	OSCdef(\piReseed, { |msg|
		"Reseed: %".format(msg[1]).postln;
	}, "/pi_synth/reseed");

	OSCdef(\piTextureRoot, { |msg|
		var n = msg[1].asInteger;
		if(n >= 0, {
			textureRoot = n;
			if(textureSynth.notNil, { textureSynth.set(\root, n) });
		});
	}, "/pi_synth/texture_root");

	OSCdef(\piArpActive, { |msg|
		arpActive = msg[1] > 0;
		if(textureSynth.notNil, {
			textureSynth.set(\shimmer, if(arpActive, 0.35, 0.0));
		});
		~setDuck.();
	}, "/pi_synth/arp_active");

	OSCdef(\piHold, { |msg|
		holdLatch = msg[1] > 0;
	}, "/pi_synth/hold");

	OSCdef(\piEvolve, { |msg|
		evolveEnabled = msg[1] > 0;
		if(evolveEnabled, { ~startEvolve.() }, {
			if(evolveRoutine.notNil, { evolveRoutine.stop; evolveRoutine = nil });
		});
	}, "/pi_synth/evolve");

	OSCdef(\piWeather, { |msg|
		var w = msg[1].clip(0, 1);
		weatherAmt = w;
		~morphParam.(\filter_cutoff, 900 + (2800 * (1 - w)), 2);
		~morphParam.(\reverb_size, 0.55 + (0.4 * w), 3);
		~morphParam.(\noise_level, 0.02 + (0.14 * (1 - w)), 2);
	}, "/pi_synth/weather");

	OSCdef(\piCompanion, { |msg|
		companionOn = msg[1] > 0;
		if(companionOn, {
			if(companionSynth.isNil, {
				companionSynth = Synth.tail(synthGroup, \piCompanion, [
					\root, textureRoot,
					\density, (patchParams[\texture_density] ? 0.5) * 0.4
				]);
			});
		}, {
			if(companionSynth.notNil, {
				companionSynth.set(\gate, 0);
				companionSynth = nil;
			});
		});
	}, "/pi_synth/companion");

	OSCdef(\piAllOff, { ~allOff.() }, "/pi_synth/all_notes_off");
	OSCdef(\piPanic, { ~panic.() }, "/pi_synth/panic");
	OSCdef(\piPanicBloom, { ~panicBloom.() }, "/pi_synth/panic_bloom");

	OSCdef(\piClockBpm, { |msg|
		var bpm = msg[1] ?? 120;
		var beat = 60 / bpm;
		clockBpm = bpm;
		if(textureSynth.notNil, {
			// quantize delay feel to clock
		});
		~morphParam.(\delay_time, (beat * [0.5, 0.75, 1.0, 1.5].choose), 0.5);
	}, "/pi_synth/clock_bpm");

	OSCdef(\piTapeGrit, { |msg|
		var amt = msg[1] ?? 0.2;
		var sec = msg[2] ?? 4;
		~morphParam.(\noise_level, amt, 0.5);
		fork {
			sec.wait;
			~morphParam.(\noise_level, patchParams[\noise_level] ? 0.05, 3);
		};
	}, "/pi_synth/tape_grit");

OSCdef(\piTestBeep, { |msg|
	var freq = msg[1] ?? 440;
	var amp = msg[2] ?? 0.85;
	"pi_test_beep OSC received % Hz".format(freq).postln;
	~playKeyboardAudible.(freq, amp.clip(0.5, 1.0), 0.45);
	if(limiterSynth.isNil, {
		"pi_test_beep: engine not initialized (no limiterSynth)".postln;
	}, {
		Synth.before(limiterSynth, \piAmbientVoice, [
			\freq, freq, \amp, amp, \gate, 1, \vel, 110,
			\atk, 0.01, \dec, 0.12, \sus, 0.85, \rel, 0.35,
			\cutoff, 5200, \delayMix, 0.08, \revMix, 0.12
		]);
		"pi_test_beep % Hz".format(freq).postln;
	});
}, "/pi_synth/test_beep");

"Pi Ambient Synth listening on OSC port %".format(port).postln;
try {
	var f = File("/var/lib/pi-ambient-synth/sc-engine-ready", "w");
	if(f.notNil, {
		f.write("ready");
		f.close;
	});
} { |err|
	("WARN: sc-engine-ready marker: %".format(err)).postln;
};

if(engineTest, {
	if(bootOk != true, {
		"Pi Ambient Synth ENGINE_TEST failed: scsynth not connected".postln;
		0.exit;
	});
	NetAddr("127.0.0.1", port).sendMsg("/pi_synth/test_beep", 440, 0.95);
	0.5.wait;
	"Pi Ambient Synth ENGINE_TEST ok".postln;
	0.exit;
});
loop { 1.wait };
};
)
