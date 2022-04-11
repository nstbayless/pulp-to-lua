# Pulp-To-Lua

*Converts [Pulp](https://play.date/pulp/) projects to the Lua SDK for the [Panic Playdate](https://play.date/).*

This transpiler is primarily intended to improve performance.

## Requirements

You must have [python 3](https://www.python.org/) installed.

## Usage

From your command line

`python3 pulplua.py MyPulpProject.json out/`

You can then compile using `pdc` as normal:

```bash
    pdc out MyPulpProject.pdx
    PlaydateSimulator ./MyPulpProject.pdx
```

## Optimization Advice

While `pulp-to-lua` should already significantly improve performance by an order of magnitude at least, there are additional steps you can take to make sure your code runs optimally:

    - Avoid using `emit` wherever possible. This function is slow and it is usually preferable to use `call` unless you really do want all actors to respond.

## Contributions

Contributions are welcome! Ask the author (NaOH#1432 on [discord](https://discord.gg/VNVQHSS49U)) for advice.
