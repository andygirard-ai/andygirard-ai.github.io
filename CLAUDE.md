# andygirard-ai.github.io

Andy's GitHub Pages site. It hosts two things for **PlugCheck**, his "is the Tesla plugged in?" reminder:

- `.well-known/appspecific/com.tesla.3p.public-key.pem`: the public key Tesla's Fleet API requires. Don't change or remove it; Tesla checks this URL.
- `plugcheck/`: the published PlugCheck files, served at https://andygirard-ai.github.io/plugcheck/
  - `index.html`: the Tesla OAuth return page. It shows a Copy button for the sign-in URL.
  - `setup.sh`: the one-run installer. Built; do not edit by hand.
  - `plugcheckd.zsh` and `plugcheck`: the background service and the control command. Built; do not edit by hand. `~/PlugCheck/plugcheck update` downloads these two files.
  - `icon.png`: the notification icon. Its source is `src/art/icon.svg` (MDI `ev-plug-tesla` glyph, Apache 2.0).
  - `src/`: the **source of truth**. Edit here.

## About Andy
New to coding, expert grower. When an instruction is for him, give small, exact steps (which app, which button, what to paste). Design through an Apple lens. Times are US Eastern.

## How PlugCheck works (on the Mac mini)
- Installed in `~/PlugCheck/`: `plugcheckd.zsh` (the service), `plugcheck` (the control command), `config` (settings and look), `state`, and `plugcheck.log`.
- It runs as LaunchAgent `com.andy.plugcheck` (`~/Library/LaunchAgents/com.andy.plugcheck.plist`), with KeepAlive.
- Secrets live in the Keychain under service `PlugCheck`: account `refresh_token` (Tesla) and account `pushward` (PushWard `hlk_` key). **Never print them, log them, or commit them.**
- Arrival detection: the Tesla's fixed IP (192.168.1.27) is pinged plus an ARP check. Away for ≥15 min and then present counts as an arrival. After a 10-minute grace period it checks the charge state.
- Tesla Fleet API (NA), app "PlugCheck", scope `vehicle_device_data` only. Keep calls cheap; the free credit is $10/month and a wake costs about 2¢. `MAX_WAKES` = 8 per day.
- Alerts go through the PushWard API (`https://api.pushward.app`): an approval-template Live Activity with Snooze 15 min / Snooze 1 hr / Not today buttons, plus time-sensitive nudges. The bedtime check is a critical alert. When PushWard is down, it falls back to Reminders.app.
- Commute: 53.5 mi each way, about 23% one way (Andy's estimate, varies by season). `NEED_PCT` (default 50) is the charge needed for a round trip. Below it, evening nudges turn critical and overnight alerts are critical every 10 min (they wake him), because there's no time to charge in the morning. At or above it, overnight stays silent. A future idea: scale `NEED_PCT` by season or outside temperature.
- The schedule:
  - 9:30 PM bedtime check.
  - Quiet hours 10:30 PM–4:30 AM: no nudges, and the car is never woken.
  - Nudges every 2 min ×15, then every 10 min.
  - The Live Activity renews silently every 7 hours (iOS caps them at 8).

## Making a change
1. Edit files in `plugcheck/src/`: `plugcheckd.zsh`, `plugcheck-ctl.zsh`, and `setup.in.zsh` (the installer template; it embeds the other two at `@@DAEMON@@` and `@@CTL@@`).
2. `zsh plugcheck/src/build.sh` writes `plugcheck/setup.sh`, `plugcheck/plugcheckd.zsh` and `plugcheck/plugcheck`, and syntax-checks them.
3. Test with `zsh plugcheck/src/test/run_all.sh`. It uses a fake Tesla, fake PushWard, a fake clock and fake macOS tools from `src/test/bin`, and needs `python3`. The shims were written on Linux, so if one misbehaves on macOS, fix the shim, not the service.
4. Apply it on this Mac. Either:
   - copy `plugcheck/plugcheckd.zsh` to `~/PlugCheck/plugcheckd.zsh`, then run `~/PlugCheck/plugcheck restart`, or
   - commit, push, wait about a minute for Pages, then run `~/PlugCheck/plugcheck update`.
5. Preview with `~/PlugCheck/plugcheck test` (a demo Live Activity) or `~/PlugCheck/plugcheck check` (reads the real car). Read `~/PlugCheck/plugcheck.log` to confirm.
6. Look-only tweaks (icon, colors, sound, snooze lengths) go in `~/PlugCheck/config`, then run `~/PlugCheck/plugcheck restart`. No code change is needed.

Commits must not contain secrets, the PushWard key, or the Tesla client secret. The Tesla client ID is not secret.
