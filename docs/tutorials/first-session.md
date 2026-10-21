# Your first session

By the end you will have connected the panel to a US-16x08, watched a signal on the meters, shaped it with EQ and
compression, and stored the result as a scene. It takes about fifteen minutes. You need the unit connected by USB
and something that makes sound (a microphone or instrument on input 1, or just tap the mic).

## 1. Prepare
1. Quit TASCAM's own Settings Panel if it is running. Two programs polling one unit can make it stop answering.
2. Build and start the app (see [Build and install](../how-to/build-the-app.md)), or run `swift run US16x08Panel`.

## 2. Check you are connected
Look at the left of the title bar. A **green dot and "US-16x08"** means connected. Click it: a small pager shows the device,
sample rate, firmware and the last status message. A red dot means the unit was not found; plug it in and the app reconnects by itself.

On every connect the app sends everything you see on screen to the unit, so the unit matches the panel straight away.

## 3. See a signal
Make some noise into input 1. The LED ladder next to fader 1 moves: green up to −12 dBFS, yellow to −6, red above.
The segment that hangs above the ladder is the peak hold; the small red lamp on top latches if the input clipped. Click a meter to clear its lamp.

## 4. Pull a fader and pan a channel
Drag fader 1 down; the number under it follows. Double-click the fader for 0 dB. Turn the pan knob by dragging it up or down;
double-click it to centre.

## 5. Add EQ
Click channel 1's strip (its outline turns blue) so the docked panel above shows **EQUALIZER · ANALOG 1**.
Switch **On**. Drag the HIGH node on the graph up a few dB, or turn the HIGH GAIN knob. You should hear the top end brighten.
Type `3` into the HIGH GAIN number box and press Return — it snaps to a legal value.

## 6. Add compression
In **COMPRESSOR · ANALOG 1** switch **On**, then lower **THRESHOLD** to about −20 dB and raise **RATIO** to 4:1.
The curve bends at the threshold and the orange bar beside it shows gain reduction when you speak.

## 7. Save it
Open **Scenes** (top segmented control), pick slot 1, press **Store**. Change something, then recall slot 1 from the **Scene** menu in the toolbar: everything returns and is sent to the unit.

## 8. Quit
Closing the window quits the app. Next time it starts, your settings are restored and sent to the unit when it connects.

You now know the main loop. Next: [shape a channel](../how-to/eq-a-channel.md), or read why the panel has to [remember everything itself](../explanation/state-and-sync.md).
