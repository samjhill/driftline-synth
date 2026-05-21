// Loaded with: sclang -l synth/pi_bind_port.scd synth/ambient_engine.scd
// Binds sclang OSC to 57120 before class-library compile so /notify → /done works.
57120.asString.postln;
NetAddr.localAddr.port = 57120;
