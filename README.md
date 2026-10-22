# Svensson

**Your phone rings. You're at your desk, headset on. You press a key and talk.**

Svensson turns your Omarchy desktop into a hands-free kit for your phone, the
way a car stereo does it: the phone keeps the SIM and the number, the PC
lends it a microphone, speakers, a keyboard and a big screen. Calls come in on
your desktop, you answer with one keystroke, you dial from your contacts
without picking up the phone.

It lives in your bar as a 1991 Volvo 960. When someone calls, the headlights
flash.

<!-- screenshot: assets/screenshot.png -->

[Deutsche Version](README.de.md)

## What you get

**Calls on the desktop.** A call card pops up with the caller's name and
photo from your phone's contacts. Answer, reject, hang up, from the card, the
bar or a shortcut. A running call shows its timer in the bar.

**A real dialer.** Type digits to dial, type letters to search your contacts,
arrow keys and Enter to call. Tab flips between contacts and recent calls.
Your whole phonebook and call history come over Bluetooth and stay in sync on
their own.

**Missed calls you'll actually see.** A notification with the caller's name.
Click it to call back.

**Call audio that sounds right.** Over Bluetooth, the phone leaves echo
cancelling to the hands-free kit, the way a car handles it. Without it, the
other side hears their own voice coming back. Svensson routes
the call through PipeWire's echo canceller, for calls only. Your default
microphone stays exactly as it is, so Discord, browsers and everything else
are untouched, and you never switch devices by hand.

**It stays out of the way.** Svensson never grabs your phone in the
background. If you're listening on your car stereo or earbuds, your phone stays
there. It connects when you open the dialer.

**Scriptable.** Everything the panel does is a command: `svensson dial`,
`svensson answer`, `svensson status`, and `svensson watch` streams state
changes as JSON.

## Install

```bash
omarchy plugin add https://github.com/marc-bohm/omarchy-svensson.git --enable
~/.config/omarchy/plugins/marc-bohm.svensson/bin/svensson setup
```

`svensson setup` does the plumbing once: it puts `svensson` on your `PATH`,
finds the sound card your headset is plugged into and creates the echo
canceller for it, then checks that call audio would actually go through it.
It changes nothing it finds already in place. Run it with `--dry-run` first if
you want to see what it would do.

If your onboard sound thumps for a few seconds when the microphone wakes up
(some Realtek chips do, e.g. the ALC897), add `--no-suspend`. That keeps the
mic open, so calls start clean. Nothing is recorded unless an app uses it.

### Pair your phone

Pair it from the Bluetooth settings on your desktop, as you would with any
device. Then on the phone:

- **iPhone:** Settings → Bluetooth → ⓘ next to your PC → turn on
  **Sync Contacts**.
- **Android:** allow access to **contacts and call history** when pairing
  asks for it.

Contacts and call history need `bluez-obex`:

```bash
omarchy pkg add bluez-obex
```

Calling works without it; you just won't see names.

### A shortcut

Add one line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Svensson", "$HOME/.local/bin/svensson toggle")
```

One key does the right thing: answers when it rings, hangs up during a call,
opens the dialer otherwise.

## Using it

| Where | What |
|---|---|
| **Bar** | Left click: call card or dialer. Right click: answer or hang up. Middle click: hang up. |
| **Dialer** | Digits dial, letters search, ↑↓ pick, Enter calls, Tab switches contacts/recents, Esc closes. |
| **Shortcut** | Ringing → answer. In a call → hang up. Otherwise → dialer. |

Calls you answer or dial on the PC play on the PC. Calls you pick up on the
phone stay on the phone; `svensson audio` brings them over.

Want to see it without a call?

```bash
omarchy-shell svensson demo incoming   # also: dialing, alerting, active, held
omarchy-shell svensson demo off
```

## Command line

```bash
svensson status            # JSON: connection, state, current calls
svensson state             # just the state: offline|idle|incoming|dialing|alerting|active|held
svensson answer
svensson hangup
svensson dial +46701740642
svensson audio             # move call audio to the PC
svensson dialer            # open the dialer
svensson selftest          # check echo cancelling routing, no call needed
svensson setup             # one-time setup, see above
svensson-route --check     # during a call: which mic the call is using
svensson-contacts sync     # pull contacts and call history now
```

## When something's off

**The other side hears themselves.** Run `svensson selftest`. It fakes a
call stream and checks that it lands on the echo canceller, no phone call
needed. During a real call, `svensson-route --check` should show
`echo_cancel_source`. If the selftest fails, run `svensson setup` again.

**They hear themselves for the first few seconds only.** Your microphone
probably thumps on wake-up. Run `svensson setup --no-suspend`.

**No names, empty call history.** Install `bluez-obex` and allow contact
sync on the phone (see above), then press **Sync** in the dialer.

**The phone isn't connecting.** Open the dialer; Svensson reconnects the
paired phone when it's opened. Make sure it's paired and trusted in your
Bluetooth settings.

## How it works

The phone is the audio gateway, the PC is the hands-free unit, connected over
Bluetooth HFP. WirePlumber's native HFP backend exposes calls on D-Bus
(`org.pipewire.Telephony`); Svensson watches that service and drives it.
Contacts and call history come over PBAP via `bluez-obex`.

During a call the phone appears in PipeWire as a capture stream
(`bluez_output.<address>.<n>`) that would normally record from the default
mic. `svensson-route` moves just that stream onto `echo_cancel_source`, a
WebRTC echo canceller bound to your headset's sound card. Gain control and
noise suppression are switched off in it; they make voices pump and smear.

| File | Role |
|---|---|
| `bin/svensson` | CLI and state watcher, talks to `org.pipewire.Telephony` |
| `bin/svensson-route` | Moves call audio onto the echo canceller |
| `bin/svensson-setup` | One-time setup |
| `bin/svensson-reconnect` | Reconnects the paired phone when the dialer opens |
| `bin/svensson-contacts` | Phonebook and call history over PBAP |
| `Service.qml` | Holds state, opens panels, sends notifications |
| `BarWidget.qml` | The Volvo in the bar |
| `CallPanel.qml` | Call card and dialer |
| `assets/` | The Volvo illustration and its headlight layer (SVG, rendered to PNG) |

## Good to know

- Built and tested with an iPhone. Android phones speak the same Bluetooth
  profiles and should work; reports are welcome.
- The interface is in German for now. English strings are next.
- Calls through Bluetooth headphones aren't supported yet. Use a wired
  headset, or speakers and a mic.
- Needs PipeWire with WirePlumber's native HFP backend, which is Omarchy's
  default. oFono isn't needed.

## Remove

```bash
omarchy plugin remove marc-bohm.svensson
rm ~/.local/bin/svensson ~/.local/bin/svensson-route
rm ~/.config/pipewire/pipewire.conf.d/90-svensson-echo-cancel.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/90-svensson-mic-no-suspend.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
```

## Why "Svensson"

A Swedish name for a Swedish car phone. Just without the car.

## License

MIT, see [LICENSE](LICENSE).
