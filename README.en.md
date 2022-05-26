# omni-plotter




## This Repository
- For developing this App.
- If you have an idea to improve function or code, then Pull-request please.
- Optimizing or new .xml too. (pull-request)
 * But I cannot experiment the console that I don't have...

## Building
- Language: vala 0.54.6
- Main environment: MSYS2 MinGW x64

## Dependencies
- WATCH meson.build. that's all.
- "livechart" is my heavily customized edition.

## What can it do ?
- Receiving the timeline of input data as UDP packet and plot it in realtime.
- Recording the timeline and plot it. You'll be able to get the feedback from it.
- Switching layout if you feel too much series in 1 panel.

## Quick experience.
- Use index.xml inside any directory in "record-sample" directory.

## Easy feature.
(Image)

1. Selector the .xml file specifying the input format/record.
1. Layout. I think that its purpose is for "filtering the input for perform some glitch".
1. Switching the visibility of serie. Default is "show all"

## Further features.
(Image)
1. Plot area. Handling these mouse events.
 * Wheel scroll: Streching the timescale.
 * Mouse over: Showing the reticle and its value.
 * Click: Put a pin on the position of the reticle. And showing the distance between 2 pins.
 * Right-click: Fix the reticle's position.
1. List of legends(series). This also handles these mouse events.
 * Wheel scroll: Scrolling the list of legends.
 * Click: Make the reticle trace the specified serie.
 * Click("\<CLR-DIFF\>"): Delete all pins.

## To run on live.
1. Use the .xml file defined for receiving packets.
 * In "live-sample" directory, there are .xml files for GameCube, Nintendo 64, Nintendo Switch.
1. Use one of the .xml files above on "This App" and "Customized RetroSpy".
 * On Customized RetroSpy, there are a form named "plotter.xml".

## Drawbacks
1. Resolution of time.
 * Fully dependencing on a src machine. I wish if Arduino/Beaglebone can publish the time of input.
1. I'm planning to treat HeartRate meter at other App.

## Remarks
* If you want to know how you write .xml file, then read comment on the sample .xml file.
