// Pi Ambient Synth — SuperCollider headless engine (phase 1 fun)
(
var patchParams, morphTime, masterVol, evolveEnabled, evolveRoutine;
var synthGroup, textureSynth, limiterSynth, companionSynth;
var textureRoot, holdLatch, arpActive, duckLevel, weatherAmt, companionOn, clockBpm;
var port, useAlsaSynth, engineTest, bootOk, bootThread;

bootOk = false;

patchParams = IdentityDictionary.new;
morphTime = 6.0;
masterVol = 0.65;
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

port = 57120;
useAlsaSynth = getenv("SC_HEADLESS_ALSA").notNil;
engineTest = getenv("SC_ENGINE_TEST").notNil;
"Pi Ambient Synth engine script loading (build sc313-jackJoin)".postln;
"Booting Pi Ambient Synth engine...".postln;
s = Server.local;
~audioDevice = ~configureServerAudio.(s);
// Pi SC 3.13: s.sync only inside a Routine; Thread:join blocks main (no CPU spin / unixCmd).
bootThread = fork {
	if(useAlsaSynth, {
		if(s.options.respondsTo(\booting), { s.options.booting = false });
		s.sync;
		bootOk = (s.serverRunning == true);
	}, {
		Server.killAll;
		if(s.serverRunning == true, {
			s.quit;
			0.5.wait;
		});
		"Starting scsynth with ALSA device: %".format(~audioDevice).postln;
		s.boot(~audioDevice);
		s.sync;
		bootOk = (s.serverRunning == true);
	});
};
bootThread.join;
if(bootOk == true, {
	if(useAlsaSynth, {
		("scsynth connected (external jackd) — device: %, rate: %".format(
			~audioDevice, s.serverSampleRate
		)).postln;
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

~setParam = { |key, val|
	patchParams[key.asSymbol] = val;
};

~morphParam = { |key, target, time|
	var busKey = ("morph_" ++ key).asSymbol;
	if(~morphBuses.isNil, { ~morphBuses = IdentityDictionary.new });
	if(~morphBuses[busKey].isNil, {
		~morphBuses[busKey] = Bus.control(s, 1).set(patchParams[key] ? 0);
	});
	~morphBuses[busKey].set(patchParams[key] ? 0);
	~morphBuses[busKey].linearRamp(target, time);
	fork {
		time.wait;
		patchParams[key] = target;
	};
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

SynthDef(\piAmbientVoice, {
	|out=0, freq=440, amp=0.3, gate=1, vel=100,
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
	|out=0, root=48, density=0.5, noise=0.05, rev=0.45, duck=1.0, shimmer=0.0, amp=1.0|
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
	sig = sig * LFNoise1.kr(0.02).range(0.4, 1.0) * duck * amp;
	pan = SinOsc.kr(0.03 + (SinOsc.kr(0.01) * 0.02)).range(-0.55, 0.55);
	Out.ar(out, Pan2.ar(sig, pan));
	Out.ar(4, sig * rev * 0.6);
}).add;

SynthDef(\piDelayFx, { |inBus=6, out=0, mix=0.25, dt=0.5|
	var sig = In.ar(inBus, 2);
	sig = CombC.ar(sig, 2.0, dt, 4) * mix + sig * (1 - mix);
	ReplaceOut.ar(out, LeakDC.ar(sig));
}).add;

SynthDef(\piReverbFx, { |inBus=4, out=0, mix=0.45, room=0.8|
	var sig = In.ar(inBus, 2);
	sig = FreeVerb.ar(sig, mix, room, 0.85);
	ReplaceOut.ar(out, LeakDC.ar(sig * 0.95));
}).add;

SynthDef(\piCompanion, {
	|root=48, gate=1, density=0.35|
	var scale, deg, freq, sig, env, interval;
	scale = [0, 2, 3, 5, 7, 9, 10];
	// LFNoise0: SC 3.13 on Pi has no TWhiteNoise (added in later SC)
	interval = LFNoise0.kr(0.08).range(3.5, 14.0);
	deg = Latch.kr(IRand.kr(0, scale.size - 1), Dust.kr(interval));
	freq = (root + scale[deg]).midicps;
	sig = SinOsc.ar(freq) * 0.06;
	env = EnvGen.kr(Env.asr(1.5, 0, 4.0), gate, doneAction: 2);
	Out.ar(4, sig * env * density);
}).add;

SynthDef(\piLimiter, { |in=0, out=0, level=0.9|
	var sig = In.ar(in, 2);
	sig = (sig * (1 / level)).tanh * level;
	ReplaceOut.ar(out, LeakDC.ar(sig));
}).add;

~textureAmp = { |vol|
	if(textureSynth.notNil, {
		textureSynth.set(\amp, (vol ? masterVol) * 1.35);
	});
};

~voices = IdentityDictionary.new;
~noteActivity = 0;

~setDuck = {
		var target = if(arpActive, 0.55, 1.0);
		duckLevel = target;
		if(textureSynth.notNil, { textureSynth.set(\duck, target) });
	};

~playNote = { |note, vel=100|
		var freq = note.midicps;
		var amp = vel.linlin(0, 127, 0.18, 0.42) * masterVol;
		~noteActivity = (~noteActivity + 1).max(0);
		if(textureSynth.notNil, { textureSynth.set(\duck, 0.42) });
		if(limiterSynth.isNil, {
			"playNote: engine not initialized (no limiterSynth)".postln;
			^this;
		});
		if(~voices[note].notNil, { ~voices[note].free });
		~voices[note] = Synth.before(limiterSynth, \piAmbientVoice, [
			\freq, freq, \amp, amp, \gate, 1, \vel, vel,
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

if(s.serverRunning == true, {
	~morphBuses = IdentityDictionary.new;
	synthGroup = Group.tail(s);

	Synth.tail(synthGroup, \piDelayFx, [\inBus, 6, \out, 0, \mix, 0.2, \dt, 0.5]);
	Synth.tail(synthGroup, \piReverbFx, [\inBus, 4, \out, 0, \mix, 0.45, \room, 0.8]);
	limiterSynth = Synth.tail(synthGroup, \piLimiter, [\in, 0, \out, 0, \level, 0.85]);
	textureSynth = Synth.tail(synthGroup, \piTextureDrone, [\root, 48, \density, 0.5, \amp, masterVol * 1.35]);
	"Engine synths started (texture drone + FX chain)".postln;
}, {
	"WARN: scsynth not running — OSC registered but notes will not sound".postln;
});

OSCdef(\piNoteOn, { |msg|
		~playNote.(msg[1].asInteger, msg[2] ? 100);
	}, \pi_synth_note_on);

	OSCdef(\piNoteOff, { |msg|
		~stopNote.(msg[1].asInteger);
	}, \pi_synth_note_off);

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
	}, \pi_synth_set);

OSCdef(\piMorphTime, { |msg|
		morphTime = msg[1] ? 6.0;
	}, \pi_synth_morph_time);

	OSCdef(\piPatchLoaded, { |msg|
		~applyPatch.(morphTime);
	}, \pi_synth_patch_loaded);

	OSCdef(\piReseedTransition, { |msg|
		var dur = msg[1] ? 2.0;
		if(textureSynth.notNil, {
			textureSynth.set(\rev, (patchParams[\reverb_mix] ? 0.45) + 0.15);
			fork {
				dur.wait;
				textureSynth.set(\rev, patchParams[\reverb_mix] ? 0.45);
			};
		});
	}, \pi_synth_reseed_transition);

	OSCdef(\piReseed, { |msg|
		"Reseed: %".format(msg[1]).postln;
	}, \pi_synth_reseed);

	OSCdef(\piTextureRoot, { |msg|
		var n = msg[1].asInteger;
		if(n >= 0, {
			textureRoot = n;
			if(textureSynth.notNil, { textureSynth.set(\root, n) });
		});
	}, \pi_synth_texture_root);

	OSCdef(\piArpActive, { |msg|
		arpActive = msg[1] > 0;
		if(textureSynth.notNil, {
			textureSynth.set(\shimmer, if(arpActive, 0.35, 0.0));
		});
		~setDuck.();
	}, \pi_synth_arp_active);

	OSCdef(\piHold, { |msg|
		holdLatch = msg[1] > 0;
	}, \pi_synth_hold);

	OSCdef(\piEvolve, { |msg|
		evolveEnabled = msg[1] > 0;
		if(evolveEnabled, { ~startEvolve.() }, {
			if(evolveRoutine.notNil, { evolveRoutine.stop; evolveRoutine = nil });
		});
	}, \pi_synth_evolve);

	OSCdef(\piWeather, { |msg|
		var w = msg[1].clip(0, 1);
		weatherAmt = w;
		~morphParam.(\filter_cutoff, 900 + (2800 * (1 - w)), 2);
		~morphParam.(\reverb_size, 0.55 + (0.4 * w), 3);
		~morphParam.(\noise_level, 0.02 + (0.14 * (1 - w)), 2);
	}, \pi_synth_weather);

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
	}, \pi_synth_companion);

	OSCdef(\piAllOff, { ~allOff.() }, \pi_synth_all_notes_off);
	OSCdef(\piPanic, { ~panic.() }, \pi_synth_panic);
	OSCdef(\piPanicBloom, { ~panicBloom.() }, \pi_synth_panic_bloom);

	OSCdef(\piClockBpm, { |msg|
		var bpm = msg[1] ?? 120;
		var beat = 60 / bpm;
		clockBpm = bpm;
		if(textureSynth.notNil, {
			// quantize delay feel to clock
		});
		~morphParam.(\delay_time, (beat * [0.5, 0.75, 1.0, 1.5].choose), 0.5);
	}, \pi_synth_clock_bpm);

	OSCdef(\piTapeGrit, { |msg|
		var amt = msg[1] ?? 0.2;
		var sec = msg[2] ?? 4;
		~morphParam.(\noise_level, amt, 0.5);
		fork {
			sec.wait;
			~morphParam.(\noise_level, patchParams[\noise_level] ? 0.05, 3);
		};
	}, \pi_synth_tape_grit);

OSCdef(\piTestBeep, { |msg|
	var freq = msg[1] ?? 440;
	var amp = msg[2] ?? 0.55;
	if(s.serverRunning != true, {
		"pi_test_beep: scsynth not running".postln;
	}, {
		Synth(\piAmbientVoice, [
			\freq, freq, \amp, amp, \gate, 1, \vel, 110,
			\atk, 0.01, \dec, 0.1, \sus, 0.8, \rel, 0.4,
			\cutoff, 4000, \delayMix, 0, \revMix, 0
		]);
		"pi_test_beep % Hz".format(freq).postln;
	});
}, \pi_synth_test_beep);

NetAddr.localAddr.port = port;
"Pi Ambient Synth listening on OSC port %".format(port).postln;
try {
	PathName("/var/lib/pi-ambient-synth").mkdir;
	File.use("/var/lib/pi-ambient-synth/sc-engine-ready", "w", { |f|
		f.write(Date.getDate.asString);
	});
} { |err|
	("WARN: sc-engine-ready marker: %".format(err)).postln;
};

if(engineTest, {
	if(bootOk != true, {
		"Pi Ambient Synth ENGINE_TEST failed: scsynth not connected".postln;
		0.exit;
	});
	if(s.serverRunning != true, {
		"Pi Ambient Synth ENGINE_TEST failed: server not running".postln;
		0.exit;
	});
	"Pi Ambient Synth ENGINE_TEST ok".postln;
	0.exit;
});
// Keep sclang alive for systemd (Thread:join blocks main without Routine yield).
fork { loop { 1.wait } }.join;
)
