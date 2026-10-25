# Swipe Switcher

Windows-style three-finger swipe between the windows on your current workspace, for Omarchy.

Put three fingers on the touchpad and slide left or right. A row of live window previews appears as soon as you start moving, the highlight follows your fingers one window at a time, and lifting your fingers focuses the highlighted window.

- **Follows your fingers.** Hyprland's own gesture actions only fire after you lift your fingers. This plugin reads the touchpad directly, so the highlight moves while you slide.
- **Spatial order.** By default windows are shown left to right as they sit on screen and the highlight stops at the ends, so swiping right never lands on a window to the left. Order and wrapping can be changed in the settings.
- **Live previews.** Windows that are off screen (for example scrolled away on the scrolling layout) get no frames from Hyprland, so their tile shows the last frame the switcher saw, or the app icon.
- **Optional Alt+Tab** with the same previews, most recently used first, released on Alt (see below).
- Click a preview or press Enter to pick it now. Escape or a click outside cancels.

Only three-finger horizontal swipes are taken. Vertical three-finger swipes and every other gesture are left to Hyprland.

## Requirements

- Omarchy with the Quickshell-based Omarchy shell and Hyprland's Lua config (tested on Omarchy 4.5.0rc1, Hyprland 0.56)
- `setpriv` (util-linux, installed on every Arch system)
- A touchpad
- `libinput-tools`, for `libinput debug-events`:

  ```bash
  omarchy pkg add libinput-tools
  ```

- Your user in the `input` group, so the plugin can read touchpad events. Check with `id -nG | grep -w input`. If it is missing, add it and log out and back in:

  ```bash
  sudo usermod -aG input "$USER"
  ```

  Membership in `input` lets your user's programs read all input devices, including the keyboard. Only add it if you are comfortable with that.

## Install

```bash
omarchy plugin add https://github.com/vekhyat/omarchy-swipe-switcher --enable
```

Then turn off any three-finger horizontal gesture of your own in `~/.config/hypr/input.lua`, or both will react to the same swipe. Omarchy ships these lines commented out, so a stock install needs nothing. Look for lines like:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

and comment them out, then run `hyprctl reload`.

## Alt+Tab with previews (optional)

The plugin registers three Hyprland global shortcuts and binds no keys on its own: `swipe-switcher:next`, `swipe-switcher:prev` and `swipe-switcher:pick`. To use them, add one of these to `~/.config/hypr/bindings.lua`.

Previews only while an app is full screen, normal Omarchy Alt+Tab otherwise:

```lua
local function alt_tab(forward)
  return function()
    local window = hl.get_active_window()
    if window and (window.fullscreen or 0) >= 2 then
      hl.dispatch(hl.dsp.global(forward and "swipe-switcher:next" or "swipe-switcher:prev"))
    else
      hl.dispatch(hl.dsp.window.cycle_next({ next = forward }))
      hl.dispatch(hl.dsp.window.bring_to_top())
    end
  end
end
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Next window", alt_tab(true), { repeating = true })
o.bind("ALT + SHIFT + TAB", "Previous window", alt_tab(false), { repeating = true })
o.bind("Alt_L", "Window switcher: pick", hl.dsp.global("swipe-switcher:pick"),
  { release = true, transparent = true, ignore_mods = true, non_consuming = true })
```

Previews always:

```lua
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Next window", hl.dsp.global("swipe-switcher:next"), { repeating = true })
o.bind("ALT + SHIFT + TAB", "Previous window", hl.dsp.global("swipe-switcher:prev"), { repeating = true })
o.bind("Alt_L", "Window switcher: pick", hl.dsp.global("swipe-switcher:pick"),
  { release = true, transparent = true, ignore_mods = true, non_consuming = true })
```

Run `hyprctl reload` afterwards. Hold Alt, tap Tab to move, release Alt to switch.

## Settings

Open the settings window:

```bash
omarchy-shell shell toggle io.github.vekhyat.swipe-switcher
```

To open it with a key, add a line like this to `~/.config/hypr/bindings.lua`. `SUPER + CTRL + ALT + J` is free on a stock Omarchy; check yours with `omarchy menu keybindings --print` first:

```lua
o.bind("SUPER + CTRL + ALT + J", "Swipe Switcher settings", { panel = "io.github.vekhyat.swipe-switcher" })
```

Changes apply as you make them:

| Setting | Default | What it does |
| --- | --- | --- |
| Switch windows with a swipe | on | Turns the touchpad reader on or off. Shows whether the touchpad is being read, and why not if it isn't. |
| Fingers | 3 | Three- or four-finger swipe |
| Finger travel per window | 105 | Libinput units per window step (a full slide is about 400). Lower is faster. |
| Reverse direction | off | Swipe right to move the highlight left |
| Order | Where windows sit | Left to right on screen, or most recently used first |
| Wrap around at the ends | off | Off: the highlight stops at the first and last window |
| Preview height | 170 | Height of each preview, in pixels |

The window also has a button that copies the Alt+Tab setup lines from the section above.

Settings are saved in this plugin's entry in `~/.config/omarchy/shell.json`.

## Remove

```bash
omarchy plugin remove io.github.vekhyat.swipe-switcher
```

If you added the Alt+Tab lines, delete them from `~/.config/hypr/bindings.lua` and run `hyprctl reload` to get Omarchy's default Alt+Tab back.

## How it works

The plugin is a shell service. It runs `libinput debug-events` for the touchpad, keeps only swipe events, and follows the three-finger horizontal ones as the fingers move. When it opens, it reads the windows on the focused workspace with `hyprctl clients -j`, shows a `ScreencopyView` preview for each, and on pick sends Hyprland a focus and raise for the chosen window.

## License

MIT. See [LICENSE](LICENSE).
