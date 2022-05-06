# Pulp Mill (Pulp-To-Lua Transpiler)

*Converts [Pulp](https://play.date/pulp/) projects to the Lua SDK for the [Panic Playdate](https://play.date/).*

This transpiler is primarily intended to improve performance of Pulp projects, but you can also use it to extend the project with Lua API functionality not available in Pulp.

[![Buy a coffee](https://www.buymeacoffee.com/assets/img/custom_images/yellow_img.png)](https://www.buymeacoffee.com/NaOH)

## Requirements

You must have [python 3](https://www.python.org/) installed, and the `PIL` or `Pillow` module as well. `python3 -m pip install Pillow` on the command line ought to suffice.

## Usage

From your command line:

`python3 pulplua.py MyPulpProject.json out/`

You can then compile using `pdc` as normal:

```bash
    pdc out MyPulpProject.pdx
    PlaydateSimulator ./MyPulpProject.pdx
```

## Inconsistencies

- The transpilation is likely not perfect. Some behaviour may differ. You are responsible for ensuring that your game performs as intended -- please test it after converting it to Lua! You can help improve pulp-to-lua by reporting behaviourial differences.
- Audio in particular may sound warped. There are a number of reasons for this. In general, you can avoid must or all of the warping by ensuring that notes are held longer than the sum of their instrument's *attack* and *delay* fields. If that's not feasible, you can try changing `FIREFOX_SOUND_COMPAT` to false in `main.lua` after exporting, or modifying the `SOUNDSCALE` table in `pulp.lua`. This is an ongoing field of research, and you're welcome to contribute!
- Some Pulp files, especially ones which have been worked on extensively, contain seemingly-broken entries in their JSON, like booleans in place of an object. These may cause errors, and can probably be resolved by inserting a dummy object in its place, e.g. by copying the previous entry. If you can identify the cause of this problem, please report!
- The wrapping of words in dialogue windows is likely to be subtly different. You are invited to implement a better `paginate()` function (see [pulp.lua](./pulp.lua#paginate))

## Optimization Advice

While `pulp-to-lua` should already significantly improve performance by an order of magnitude at least, there are additional steps you can take to make sure your code runs optimally:

- Avoid using `emit` wherever possible. This function is slow and it is usually preferable to use `call`. Even if you want everything to handle the call, it's still faster to use tell and call manually.
- There is generally no need to replace string literals for tile IDs e.g. `draw "white-tile"` for `draw 0`. The transpiler will do this automatically if it can detect this.
- To improve performance, up to around ~150 variables will be declared as `local` by the transpiler, and it will select the variables that appear most frequently in the code. This is not necessarily the variables which are most frequently used at runtime! Do with this information what you will -- you may wish to reuse variable names where possible.
- `mimic` events can be heavily optimized by the transpiler for events that contain only one line and that line is `mimic` with a static name or id literal.

## Contributions

Contributions are welcome! Ask the author (NaOH#1432 on [discord](https://discord.gg/VNVQHSS49U)) for advice.
