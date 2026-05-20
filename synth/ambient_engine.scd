// Pi Ambient Synth — SuperCollider headless engine
(
var patchParams, morphTime, masterVol, evolveEnabled;
var synthGroup, textureSynth, limiterSynth;
var delayBus, reverbBus;

patchParams = IdentityDictionary.new;
morphTime = 6.0;
masterVol = 0.65;
evolveEnabled = false;

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

~setParam = { |key, val|
	var numKey = key.asSymbol;
	if(patchParams.keys.includes(numKey), {
		patchParams[numKey] = val;
	}, {
		patchParams[numKey] = val;
	});
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
		textureSynth.set(
			\density, patchParams[\texture_density] ? 0.5,
			\root, patchParams[\root_note] ? 48,
			\noise, patchParams[\noise_level] ? 0.05,
			\rev, patchParams[\reverb_mix] ? 0.45
		);
	});
};

SynthDef(\piAmbientVoice, {
	|out=0, freq=440, amp=0.3, gate=1,
	oscBlend=0.5, subLevel=0.15, noiseLevel=0.05,
	cutoff=1400, res=0.2, atk=0.05, dec=0.8, sus=0.6, rel=2.5,
	drift=0.008, lfoRate=0.08, lfoDepth=0.08, width=0.7, bright=0.6,
	delayMix=0.2, revMix=0.45|
	var sig, env, sub, noise, lfo, pan;
	lfo = SinOsc.kr(lfoRate).range(1 - lfoDepth, 1 + lfoDepth);
	sig = Mix([
		LFSaw.ar(freq * lfo * (1 + drift * LFNoise2.kr(0.2)), 0, 0.35 * oscBlend),
		SinOsc.ar(freq * lfo, 0, 0.4 * (1 - oscBlend)),
		LFTri.ar(freq * lfo, 0, 0.25 * oscBlend)
	]);
	sub = SinOsc.ar(freq / 2 * lfo, 0, subLevel * 0.4);
	noise = PinkNoise.ar(noiseLevel * 0.08);
	sig = sig + sub + noise;
	sig = LPF.ar(sig, cutoff * bright.linlin(0.2, 0.95, 0.6, 1.2));
	sig = RLPF.ar(sig, cutoff, res);
	env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), gate, doneAction: 2);
	pan = SinOsc.kr(0.07).range(width.neg, width);
	sig = Pan2.ar(sig * env * amp, pan);
	Out.ar(out, sig);
	Out.ar(6, sig * delayMix);
	Out.ar(4, sig * revMix);
}).add;

SynthDef(\piTextureDrone, {
	|out=0, root=48, density=0.5, noise=0.05, rev=0.45|
	var freq, sig, fifth, oct;
	freq = root.midicps;
	fifth = (root + 7).midicps;
	oct = (root + 12).midicps;
	sig = Mix([
		SinOsc.ar(freq * (1 + LFNoise2.kr(0.03).range(0, density * 0.004)), 0, 0.12),
		SinOsc.ar(fifth * (1 + LFNoise2.kr(0.02).range(0, density * 0.003)), 0, 0.08),
		SinOsc.ar(oct, 0, 0.05),
		LPF.ar(PinkNoise.ar(noise * 0.04), 800)
	]);
	sig = sig * LFNoise1.kr(0.02).range(0.4, 1.0);
	Out.ar(out, Pan2.ar(sig, 0));
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

SynthDef(\piLimiter, { |in=0, out=0, level=0.9|
	var sig = In.ar(in, 2);
	sig = (sig * (1 / level)).tanh * level;
	ReplaceOut.ar(out, LeakDC.ar(sig));
}).add;

fork {
	var port = 57120;
	"Booting Pi Ambient Synth engine...".postln;
	s = Server.local;
	if(s.serverRunning.not, { s.boot; 0.5.wait });
	s.sync;

	delayBus = Bus.audio(s, 2);
	reverbBus = Bus.audio(s, 2);

	~morphBuses = IdentityDictionary.new;
	synthGroup = Group.tail(s);

	Synth.tail(synthGroup, \piDelayFx, [\inBus, 6, \out, 0, \mix, 0.2, \dt, 0.5]);
	Synth.tail(synthGroup, \piReverbFx, [\inBus, 4, \out, 0, \mix, 0.45, \room, 0.8]);
	limiterSynth = Synth.tail(synthGroup, \piLimiter, [\in, 0, \out, 0, \level, 0.85]);
	textureSynth = Synth.tail(synthGroup, \piTextureDrone, [\root, 48, \density, 0.5]);

	~voices = IdentityDictionary.new;

	~playNote = { |note, vel=100|
		var freq = note.midicps;
		var amp = vel / 127.0 * 0.35 * masterVol;
		if(~voices[note].notNil, { ~voices[note].free });
		~voices[note] = Synth.before(limiterSynth, \piAmbientVoice, [
			\freq, freq, \amp, amp, \gate, 1,
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
	};

	~allOff = {
		~voices.do(_.set(\gate, 0));
		~voices.clear;
	};

	~panic = {
		~allOff.();
		if(textureSynth.notNil, { textureSynth.set(\noise, 0) });
	};

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
		}, {
			if(val.isKindOf(String), {
				val = val.asFloat;
			});
			~setParam.(key, val);
		});
	}, \pi_synth_set);

	OSCdef(\piMorphTime, { |msg|
		morphTime = msg[1] ? 6.0;
	}, \pi_synth_morph_time);

	OSCdef(\piPatchLoaded, { |msg|
		~applyPatch.(morphTime);
	}, \pi_synth_patch_loaded);

	OSCdef(\piReseed, { |msg|
		"Reseed signal: %".format(msg[1]).postln;
	}, \pi_synth_reseed);

	OSCdef(\piEvolve, { |msg|
		evolveEnabled = msg[1] > 0;
		if(evolveEnabled, {
			fork {
				loop {
					3.wait;
					if(evolveEnabled, {
						var k = [\lfo_depth, \filter_cutoff, \texture_density].choose;
						var cur = patchParams[k] ? 0.5;
						var delta = rrand(-0.03, 0.03);
						~morphParam.(k, (cur + delta).clip(0.01, 1.0), 4);
					});
				};
			};
		});
	}, \pi_synth_evolve);

	OSCdef(\piAllOff, { ~allOff.() }, \pi_synth_all_notes_off);
	OSCdef(\piPanic, { ~panic.() }, \pi_synth_panic);

	NetAddr.localAddr.port = port;
	"Pi Ambient Synth listening on OSC port %".format(port).postln;
};
)
