// Brutally direct headphone test — no project engine, no OSC, no MIDI.
// scripts/sc_direct_headphone_smoke_test.sh runs this in background and waits ~12s for audio.
(
fork {
	var port, bootOk, tries, scAddr, langPort, doneOSC, statusOSC;

	port = 57110;
	langPort = 57120;
	NetAddr.localAddr.port = langPort;
	if (getenv("SC_SYNTH_PORT").notNil, {
		if (getenv("SC_SYNTH_PORT").size > 0, { port = getenv("SC_SYNTH_PORT").asInteger });
	});

	"sc_direct_smoke: attaching to scsynth port %".format(port).postln;
	s = Server(\directSmoke, NetAddr("127.0.0.1", port));
	Server.default = s;
	scAddr = NetAddr("127.0.0.1", port);
	bootOk = false;
	doneOSC = OSCFunc({ |msg|
		bootOk = true;
		"scsynth /done: %".format(msg).postln;
	}, "/done");
	statusOSC = OSCFunc({ |msg|
		bootOk = true;
	}, "/status.reply");
	tries = 0;
	while { bootOk.not and: { tries < 40 } } {
		scAddr.sendMsg("/notify", 0, langPort, "127.0.0.1");
		scAddr.sendMsg("/status");
		if (s.serverRunning == true, { bootOk = true });
		tries = tries + 1;
		0.2.wait;
	};
	doneOSC.free;
	statusOSC.free;
	if (bootOk.not, {
		"sc_direct_smoke FAIL: cannot attach to scsynth on port %".format(port).postln;
		^this;
	});
	s.sync;

	SynthDef(\directTone, {
		var sig = SinOsc.ar(440) * EnvGen.kr(Env.perc(0.02, 1.96, 1, -4), doneAction: 2);
		Out.ar(0, (sig ! 2) * 0.35);
	}).add;

	SynthDef(\directPad, { |freq = 440, amp = 0.22|
		var sig = Mix([
			Saw.ar(freq) * 0.5,
			SinOsc.ar(freq) * 0.5
		]) * EnvGen.kr(Env.asr(0.08, 0.35, 0.55, 2.5), doneAction: 2);
		Out.ar(0, (sig * amp ! 2));
	}).add;

	s.sync;
	0.5.wait;

	"sc_direct_smoke: 440 Hz tone 2s".postln;
	Synth(\directTone);
	2.wait;

	"sc_direct_smoke: pad chord [60,64,67] 4s".postln;
	[60, 64, 67].do { |n|
		Synth(\directPad, [\freq, n.midicps, \amp, 0.2]);
	};
	4.wait;

	"sc_direct_smoke: done".postln;
};
)
