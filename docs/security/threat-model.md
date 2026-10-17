# Glasspad threat model

This page says what Glasspad protects, from whom, and where the protection stops. It is written for users who want to know what they are trusting, and for anyone reviewing the code. The wire details are in [protocol.md](protocol.md). How to report a problem is in [SECURITY.md](../../SECURITY.md).

Short version:

- A paired iPhone can do anything a keyboard and mouse plugged into your Mac can do. Pair only your own phone, and use Forget on the Mac for any phone you no longer have.
- Someone else on your Wi-Fi cannot send input to your Mac, read what you type, or replay what they captured. They can see that a Glasspad Mac and phone are there, and they can interrupt the connection.
- The pairing code (the QR code, or the link from Copy Link or Share) works once, for 5 minutes, and only after you click Allow on the Mac. Once your phone has paired, the code is useless: the phone and Mac agree a new key that the code does not reveal.
- The installer downloads code from GitHub and builds it on your Mac. You are trusting GitHub, the Glasspad repository, and Apple's tools.

## What Glasspad is

Two apps and a few scripts:

- **Mac app** (menu bar). Listens on the local network, accepts one paired iPhone at a time, and turns what the phone sends into pointer moves, clicks, keys, and actions. It holds macOS's Accessibility permission, and optionally Automation (for Spotify and Music) and Screen Recording (for screenshot buttons).
- **iPhone app.** Finds the Mac with Bonjour (Apple's way of announcing services on a local network), connects, and sends touches and commands.
- **Installer** (`install.sh`). Builds both apps from source with Xcode and a free Apple ID, installs them, and sets up a background job on the Mac (a LaunchAgent, which macOS runs on a schedule) that reinstalls the iPhone app before Apple's 7-day limit for free accounts runs out.

There is no server and no account. Nothing between the phone and the Mac leaves your network.

## What is worth protecting

| Asset | Why it matters |
| --- | --- |
| Control of the Mac | A paired phone types and clicks as you. Whoever controls it can open Terminal and run anything you can. |
| The pair key | 32 bytes shared by one phone and one Mac, agreed on the first connection (protocol 2). Whoever holds it, plus that phone's ID, can act as that phone. |
| What you type on the phone | Passwords typed through the phone keyboard travel over the network. |
| The Mac's clipboard | The phone can ask for it, and it may hold a password copied from a password manager. |
| Your build and install | The installer runs code from the internet with your user account, and asks for your password once (for Xcode's license). |

## Who might attack, and what they can do

### 1. Someone on the same Wi-Fi (a café, an office, a shared flat)

They can see and send any network traffic, but they have never seen your pairing code.

What stops them:

- Every message after the two opening "hello" messages is encrypted and signed with ChaCha20-Poly1305 (a standard cipher that also detects any change to the data). The key for each connection is made fresh from the pair key, a new X25519 key exchange, and two random values, one from each side (HKDF-SHA256, a standard way to turn one secret into another).
- Before the Mac accepts a phone, the phone must prove it holds the key, and the Mac then proves it too. A guess fails, and a failed proof closes the connection.
- Each encrypted message carries a counter. The Mac drops a message whose counter it has already seen (on the touch channel it keeps a window of the last 64), so a recorded message cannot be sent again. A recorded connection cannot be replayed either: the Mac picks a new random value each time, so the old messages do not fit the new key.
- Touch packets that do not decrypt are dropped and counted. They never move the pointer.

What they can still do:

- **See that you use Glasspad.** The Mac announces itself by name on the network (for example "Soham's MacBook Pro") with a Glasspad service. The phone's first message is not encrypted and carries the phone's name and a fixed phone ID, which is the same for every Mac the phone pairs with. This lets someone recognize your phone on any network where it connects.
- **Interrupt the connection.** Anyone on the network can cut a TCP connection or flood the Mac. The Mac allows 8 unfinished handshakes at a time and closes each after 5 seconds. Someone who has seen your phone's ID can keep those slots full and stop your phone from connecting while they keep it up. Nothing they do this way gets in.
- **Pretend to be your Mac.** They can announce a fake Mac with the same name. Your phone will try to connect, but the fake Mac cannot prove it holds the key, so the phone closes the connection before sending any touches or keys.

### 2. Someone who sees your pairing code

The code holds the Mac's ID and the pair key. It is shown while you pair, and can be copied as a link or shared with AirDrop or Messages.

- **While the code is valid (5 minutes)** they can try to pair their own phone. The Mac asks "Allow *phone name* to control this Mac?" first, and the code works for one phone only. Click Don't Allow for any phone that is not yours. No answer within 30 seconds counts as Don't Allow.
- **After your phone has paired** the code is worthless. On that first connection the phone and Mac run a key exchange (X25519) and mix it with the code's key, so the key they keep cannot be worked out from the code, a screenshot, or a copied link.
- **Phones paired by 0.2.x** still use the code's key until their next connection with an updated phone and Mac, which replaces it the same way. An old phone that is not updated keeps the code's key until you pair it again.

Pairing links that arrive from outside the iPhone app (a web page, a message, the Camera) always ask "Pair with *name*?" first. The name comes from the link itself, so a link can claim any Mac name.

### 3. A paired phone, or someone holding your unlocked phone

A paired phone is trusted like a keyboard and mouse. It can type into any app, including Terminal, so it can run commands on the Mac whatever the settings below say.

Glasspad still adds limits, to stop accidents and to keep the riskiest things on the Mac:

- The phone can edit Actions buttons but can never add or change a **shell command button**. Shell buttons are written on the Mac, in `~/Library/Application Support/Glasspad/deck.json`, and run only after "Allow shell command buttons" is turned on in the Mac's Settings > Advanced. They run with `/bin/zsh -c`, as your user, for at most 30 seconds.
- **Macros** with shell or AppleScript steps run only when that macro has "allow scripts" set, which is done on the Mac. The phone can run a macro by its ID but cannot create or edit one.
- **Open Link** buttons refuse `file:`, `x-man-page:` and `help:` links. Other link types open in whatever app claims them.
- **Open File** buttons refuse scripts, programs, installers and link files (`.command`, `.pkg`, `.webloc` and more); they open documents, folders and apps.
- **Shortcuts** buttons run an Apple Shortcut by name, passed as one argument (never through a shell).
- A button saved by a newer Glasspad that this Mac cannot read is never run or changed.

Anyone who can unlock your iPhone and open Glasspad has the same power. Use a passcode.

### 4. Other software on your Mac, running as you

Code that already runs under your account can do most of what Glasspad does. Two things are worth knowing:

- **Glasspad's permissions carry over to what it starts.** macOS counts a shell command button, a macro script, and the now-playing helper as Glasspad's own work, so they get Glasspad's Accessibility, Automation and Screen Recording permission. Other software that can edit `deck.json`, the macros, or the state files in `~/Library/Application Support/Glasspad` could use that to borrow those permissions. Shell buttons stay off until you turn them on, which limits this.
- **The clipboard.** Copy Link marks the link private and short-lived (`org.nspasteboard.ConcealedType` and `TransientType`), so clipboard history apps skip it, and clears it when pairing ends. It still reaches your iPhone through Universal Clipboard, which is how Paste the Link Instead works. When the phone asks for the Mac's clipboard, anything a password manager marked private is not sent.
- **The renewal job runs a script from your Glasspad folder every hour** (`~/Projects/glasspad/scripts/refresh-phone.sh` by default) and reads its saved settings by running `phone-install.env` as shell code. Anything that can change those files runs code at that time. Do not keep the Glasspad folder somewhere other people or devices can write, such as a shared or synced folder.

The pair keys are in the Keychain on both devices, marked "this device only, after first unlock", so they are not copied into backups or iCloud Keychain.

### 5. The internet: websites, GitHub, downloads

- **Website buttons.** When you add a Website button, the iPhone fetches that site's page and logo. It uses HTTPS only, sends no cookies, reads at most 400 KB of the page, and refuses logos and redirects that point at local network addresses (such as `192.168.1.1`, `printer.local` or `localhost`) unless the link you typed is that device. A site whose public name points at a local address could get past the name check, but the request still has to pass HTTPS certificate checks, which home devices almost never do. Logos are redrawn as plain images before they are kept.
- **Album artwork.** For Spotify, the Mac downloads the artwork link that Spotify reports, over HTTPS only, at most 2 MB, and never from an address on the local network.
- **The installer.** See the next section.

### 6. The install and update path

`curl ... | bash` runs a script straight from GitHub. What the installer does to make that safer:

- Everything sits inside one `main` function that is called only on the last line. If the download stops partway, bash reads an unfinished function and runs nothing. The test suite checks this by running cut-off copies.
- The source is cloned over HTTPS. `GLASSPAD_REPO_URL` must start with `https://` (or be a folder on the Mac); `http://` and `git://` are refused.
- XcodeGen, the one outside build tool, is a fixed version, downloaded over HTTPS only (also after GitHub's redirect), and checked against its published SHA-256 checksum before it is unpacked. If the check fails it is thrown away; the installer then tries Homebrew, which checks its own downloads.
- `GLASSPAD_REF=v0.3.0` builds that release tag instead of the newest code on `main`. Later runs stay on that tag until you name another one.

What you still trust:

- **GitHub and the repository owner.** Without `GLASSPAD_REF`, the installer builds whatever is newest on `main`. Releases are tagged, but tags are not signed, so a tag proves only that it came from the repository, not from a particular person.
- **The script you pipe in.** The short command fetches `install.sh` from `main`. For a fixed script too, fetch it from the tag: `https://raw.githubusercontent.com/Soham109/glasspad/v0.3.0/install.sh`.
- **Apple's tools.** The build runs Xcode and asks for your Mac password once, only to accept Xcode's license and finish its first-run setup.
- **Updates** happen only when you run the installer again. The renewal job reinstalls the exact commit you last installed and never downloads new code.

## Private macOS features

Some features use parts of macOS that Apple does not document: bringing a window to the front (SkyLight), the window ID of an accessibility element, now playing information (MediaRemote, read by a small helper library run under `/usr/bin/perl`), display brightness (DisplayServices), Night Shift (CoreBrightness), and Mission Control and the desktop (a Dock notification). None of these grants Glasspad any permission it does not already have. The risk is that a macOS update changes them; each one is looked up at run time and has a fallback or turns the feature off when it is missing.

## Out of scope

- A Mac or iPhone that is already compromised (malware running as you, or with admin rights).
- Someone with your unlocked Mac, or your unlocked phone with Glasspad paired.
- Apple's own platform: the Keychain, code signing, Xcode, iOS and macOS.
- Attacks that need Glasspad to be built from a modified copy of the source.

## Known gaps and planned fixes

These are open. Earlier gaps (the code as the long-term key, no Allow step, the clipboard) were fixed in 0.3.0.

1. The phone ID and phone name are sent unencrypted. Plan: send them inside the encrypted channel, or use a per-Mac ID.
2. A 0.2.x phone that was paired before keeps the code's key until it is updated or paired again.
3. Between the Mac saving a new phone's key and the phone confirming its own save, the code's key can still be used once to agree a new key, without asking Allow. This normally lasts one round trip.
4. The name in the Allow question is the one the phone sends, so a stranger's phone can use your phone's name. Pair only while you hold your phone.

This project has not had an independent security audit.
