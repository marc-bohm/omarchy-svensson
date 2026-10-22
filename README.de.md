# Svensson

**Das Handy klingelt. Du sitzt am Schreibtisch, Headset auf. Eine Taste, und du redest.**

Svensson macht deinen Omarchy-Desktop zur Freisprechanlage für dein Handy, so
wie es ein Autoradio tut: Das Handy behält SIM-Karte und Nummer, der PC leiht
ihm Mikrofon, Lautsprecher, Tastatur und einen großen Bildschirm. Anrufe kommen
auf dem Desktop an, du nimmst mit einem Tastendruck ab und wählst aus deinen
Kontakten, ohne das Handy anzufassen.

In der Leiste wohnt Svensson als Volvo 960 von 1991. Wenn jemand anruft, gibt
er Lichthupe.

<!-- screenshot: assets/screenshot.png -->

[English version](README.md)

## Was du bekommst

**Anrufe am Desktop.** Eine Anrufkarte zeigt Name und Foto aus den Kontakten
deines Handys. Annehmen, ablehnen, auflegen: über die Karte, die Leiste oder
ein Tastenkürzel. Ein laufendes Gespräch zeigt seine Dauer in der Leiste.

**Ein richtiges Telefon.** Ziffern tippen wählt, Buchstaben tippen sucht in
den Kontakten, Pfeiltasten und Enter rufen an. Tab wechselt zwischen Kontakten
und Anrufliste. Telefonbuch und Anrufliste kommen über Bluetooth und bleiben
von selbst aktuell.

**Verpasste Anrufe, die du auch siehst.** Eine Benachrichtigung mit Namen.
Ein Klick ruft zurück.

**Gesprächston, der passt.** Über Bluetooth überlässt das Handy die
Echo-Unterdrückung der Freisprechanlage, so wie im Auto. Fehlt sie, hört sich
dein Gegenüber selbst. Svensson schickt den Anruf durch die
Echo-Unterdrückung von PipeWire, und zwar nur den Anruf. Dein Standard-Mikro
bleibt, wie es ist: Discord, Browser und alles andere merken nichts, und du
schaltest nie von Hand um.

**Drängelt sich nicht vor.** Svensson holt dein Handy nie im Hintergrund zu
sich. Hörst du gerade über Autoradio oder Ohrhörer, bleibt das Handy dort.
Verbunden wird, wenn du das Telefon öffnest.

**Skriptbar.** Alles, was die Oberfläche kann, ist ein Befehl:
`svensson dial`, `svensson answer`, `svensson status`, und `svensson watch`
liefert Zustandsänderungen als JSON.

## Installation

```bash
omarchy plugin add https://github.com/marc-bohm/omarchy-svensson.git --enable
~/.config/omarchy/plugins/marc-bohm.svensson/bin/svensson setup
```

`svensson setup` erledigt die Verkabelung einmalig: Es legt `svensson` in den
`PATH`, findet die Soundkarte, an der dein Headset steckt, richtet dafür die
Echo-Unterdrückung ein und prüft zum Schluss, ob der Anruf-Ton wirklich
hindurchläuft. Was schon da ist, lässt es in Ruhe. Mit `--dry-run` zeigt es
vorher, was es tun würde.

Wummert dein Onboard-Sound ein paar Sekunden, wenn das Mikro aufwacht (manche
Realtek-Chips tun das, z. B. der ALC897), nimm `--no-suspend` dazu. Dann
bleibt das Mikro offen und Gespräche starten sauber. Aufgenommen wird nur,
wenn ein Programm das Mikro benutzt.

### Handy koppeln

Koppeln wie jedes andere Gerät über die Bluetooth-Einstellungen des Desktops.
Dann am Handy:

- **iPhone:** Einstellungen → Bluetooth → ⓘ neben dem PC →
  **Kontakte synchronisieren** einschalten.
- **Android:** beim Koppeln den Zugriff auf **Kontakte und Anrufliste**
  erlauben.

Für Kontakte und Anrufliste braucht es `bluez-obex`:

```bash
omarchy pkg add bluez-obex
```

Telefonieren geht auch ohne, nur ohne Namen.

### Tastenkürzel

Eine Zeile in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Svensson", "$HOME/.local/bin/svensson toggle")
```

Eine Taste für alles: Klingelt es, nimmt sie ab. Im Gespräch legt sie auf.
Sonst öffnet sie das Telefon.

## Bedienung

| Wo | Was |
|---|---|
| **Leiste** | Linksklick: Anrufkarte oder Telefon. Rechtsklick: annehmen oder auflegen. Mittelklick: auflegen. |
| **Telefon** | Ziffern wählen, Buchstaben suchen, ↑↓ auswählen, Enter ruft an, Tab wechselt Kontakte/Anrufliste, Esc schließt. |
| **Tastenkürzel** | Klingelt → annehmen. Im Gespräch → auflegen. Sonst → Telefon. |

Anrufe, die du am PC annimmst oder wählst, laufen über den PC. Nimmst du am
Handy ab, bleibt der Anruf am Handy; `svensson audio` holt ihn rüber.

Ausprobieren ohne Anruf:

```bash
omarchy-shell svensson demo incoming   # auch: dialing, alerting, active, held
omarchy-shell svensson demo idle       # nur das Telefon
omarchy-shell svensson demo off
```

Der Demo-Modus bringt sein eigenes Telefonbuch mit. So kannst du Screenshots
machen, ohne deine echten Kontakte zu zeigen. Grüß das Fika-Komitee.

## Kommandozeile

```bash
svensson status            # JSON: Verbindung, Zustand, laufende Anrufe
svensson state             # nur der Zustand: offline|idle|incoming|dialing|alerting|active|held
svensson answer
svensson hangup
svensson dial +46701740642
svensson audio             # Gesprächston auf den PC holen
svensson dialer            # Telefon öffnen
svensson selftest          # Echo-Umleitung prüfen, ohne Anruf
svensson setup             # einmalige Einrichtung, siehe oben
svensson-route --check     # im Gespräch: welches Mikro der Anruf benutzt
svensson-contacts sync     # Kontakte und Anrufliste sofort holen
```

## Wenn etwas hakt

**Dein Gegenüber hört sich selbst.** `svensson selftest` ausführen. Es
simuliert einen Anruf und prüft, ob er bei der Echo-Unterdrückung landet,
ganz ohne Telefonat. Während eines echten Anrufs sollte
`svensson-route --check` bei beiden Verbindungen `"ok":true` zeigen. Schlägt
der Selbsttest fehl, `svensson setup` noch einmal laufen lassen.

**Nur in den ersten Sekunden.** Dein Mikro wummert vermutlich beim Aufwachen.
`svensson setup --no-suspend` ausführen.

**Keine Namen, leere Anrufliste.** `bluez-obex` installieren und am Handy die
Kontakt-Synchronisierung erlauben (siehe oben), dann im Telefon auf **Sync**.

**Das Handy verbindet sich nicht.** Telefon öffnen; Svensson verbindet das
gekoppelte Handy beim Öffnen. Es muss in den Bluetooth-Einstellungen gekoppelt
und vertraut sein.

## So funktioniert's

Das Handy ist das Audio-Gateway, der PC die Freisprecheinheit, verbunden über
Bluetooth HFP. Das native HFP-Backend von WirePlumber stellt Anrufe per D-Bus
bereit (`org.pipewire.Telephony`); Svensson beobachtet und steuert diesen
Dienst. Kontakte und Anrufliste kommen über PBAP mit `bluez-obex`.

Im Gespräch erscheint das Handy in PipeWire als zwei Streams: die Stimme
deines Gegenübers (`bluez_input.<adresse>.<n>`) und dein Mikro zum Handy
(`bluez_output.<adresse>.<n>`). `svensson-route` schickt beide durch eine
WebRTC-Echo-Unterdrückung, die an die Soundkarte deines Headsets gebunden ist:
Die Stimme läuft über `echo_cancel_sink`, damit der Filter weiß, wonach er
suchen muss, und dein Mikro kommt aus `echo_cancel_source`, mit diesem Echo
herausgerechnet. Das Handy kann die Streams mitten im Gespräch neu aufbauen,
deshalb prüft Svensson während eines Anrufs laufend nach. Automatische
Lautstärke und Rauschunterdrückung sind im Filter aus; sie lassen Stimmen
pumpen und verschmieren.

| Datei | Aufgabe |
|---|---|
| `bin/svensson` | CLI und Zustands-Watcher, spricht mit `org.pipewire.Telephony` |
| `bin/svensson-route` | Schickt beide Richtungen eines Anrufs durch die Echo-Unterdrückung |
| `bin/svensson-setup` | Einmalige Einrichtung |
| `bin/svensson-reconnect` | Verbindet das gekoppelte Handy, wenn das Telefon geöffnet wird |
| `bin/svensson-contacts` | Telefonbuch und Anrufliste über PBAP |
| `Service.qml` | Hält den Zustand, öffnet Panels, schickt Benachrichtigungen |
| `BarWidget.qml` | Der Volvo in der Leiste |
| `CallPanel.qml` | Anrufkarte und Telefon |
| `assets/` | Die Volvo-Illustration und ihre Scheinwerfer-Ebene (SVG, als PNG gerendert) |

## Gut zu wissen

- Gebaut und getestet mit einem iPhone. Android-Handys sprechen dieselben
  Bluetooth-Profile und sollten funktionieren; Rückmeldungen willkommen.
- Die Oberfläche folgt der Systemsprache: Deutsch auf einem deutschen System,
  sonst Englisch. Weitere Sprachen sind eine kleine Tabelle in `Service.qml`.
- Anrufe über Bluetooth-Kopfhörer gehen noch nicht. Nimm ein kabelgebundenes
  Headset oder Lautsprecher und Mikro.
- Braucht PipeWire mit dem nativen HFP-Backend von WirePlumber, in Omarchy
  Standard. oFono wird nicht gebraucht.

## Entfernen

```bash
omarchy plugin remove marc-bohm.svensson
rm ~/.local/bin/svensson ~/.local/bin/svensson-route
rm ~/.config/pipewire/pipewire.conf.d/90-svensson-echo-cancel.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/90-svensson-mic-no-suspend.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
```

## Warum „Svensson“

Ein schwedischer Name für ein schwedisches Autotelefon. Nur ohne Auto.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
