# SnapFlex

Manual-control camera app for iOS 18+. ProRAW / Bayer RAW / HEIF capture with
full manual exposure, focus, white balance, focus peaking, zebra, live
histogram, bracketing and self-timer. Photos save straight to the library.

## Build

Requires Xcode 26+, XcodeGen, and an iPhone running iOS 18+ (the camera does
not work in the simulator).

    xcodegen generate
    open SnapFlex.xcodeproj    # select a device, set your signing team, Run

## Tests

    cd Core && swift test      # pure logic
    xcodebuild test -project SnapFlex.xcodeproj -scheme SnapFlex \
      -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

## Manual on-device QA checklist

- [ ] First launch asks for camera permission; denying shows the Settings screen
- [ ] Viewfinder runs; lens chips switch between available lenses
- [ ] ISO/shutter dials move exposure visibly; tapping the active tile reverts to AUTO
- [ ] Manual focus dial sweeps near→far; peaking highlights in-focus edges
- [ ] WB dial warms/cools the image; AWB restores auto
- [ ] Lens switch with manual ISO 3000+ set: value clamps but stays manual
- [ ] ProRAW capture on a Pro device produces a DNG in Photos (check via share sheet)
- [ ] RAW (Bayer) + HEIF companion saves one asset with both resources
- [ ] Bracketing 3/5 produces the right number of photos, dark→bright
- [ ] Zebra stripes appear on blown highlights; histogram tracks the scene
- [ ] Grid + level display; level turns green when the phone is level
- [ ] Timer 3s/10s counts down; tapping again cancels
- [ ] Volume button fires the shutter
- [ ] Photos permission denied: captures spool, banner-free but nothing lost;
      granting later flushes them to the library on next foreground
- [ ] Phone call during preview shows "Camera paused", resumes after
- [ ] LONG ND 5s on running water produces silk effect; live preview builds up
- [ ] LONG TRAILS on moving lights produces trails
- [ ] BULB: starts on tap, stops+saves on second tap; auto-stops at 5 min
- [ ] Preset tap-to-cancel discards (nothing saved to Photos)
- [ ] Backgrounding mid-exposure saves the partial result (if ≥ 1s)
- [ ] Shake warning appears handheld, absent on tripod
- [ ] AE stays locked during the exposure (no brightness pumping in preview)
- [ ] PROC 0AI vs MAX on a detailed scene shows visibly different processing
- [ ] RAW + HEIF companion honors the PROC level on the companion
- [ ] PROC level survives lens switches
- [ ] PROC persistence across app restarts NOT required (resets to STD)
- [ ] Chrome fades out after 4s idle; tap reveals with a bounce
- [ ] Chrome never hides while dial open, LONG running, or countdown active
- [ ] Minimal HUD readout matches active settings (e.g. "ISO 200 · 1/120 · ND 15s")
- [ ] Dial has momentum and snaps to stops with tick haptics
- [ ] Values morph digits; selection capsule slides between tiles
- [ ] Shutter press bounces; capture and LONG-complete haptics fire
- [ ] Reduce Motion ON: crossfades instead of springs, auto-hide still works
- [ ] Dial momentum feels right on hardware (friction/stop threshold tuning)
- [ ] Selection capsule and thumbnail pop behave correctly under device rotation and with Reduce Motion ON
- [ ] Segmented rail legible over bright scenes; active cells green with underline
- [ ] Statusline shows pipeline summary and battery; assist menu opens from top-right
- [ ] Ruler ticks scroll under the fixed needle and settle on detents
- [ ] EV arc sweeps clockwise for +, mirrored for −; label appears only when EV ≠ 0
- [ ] Aspect picker in the assist menu renders usably (not a buried submenu)
- [ ] Ruler value label has no vertical clipping at 9pt
