here are some optimizations not yet done.

-- better static inlining of `fill`. can bake in __pix8scale and the colour in most cases.
-- most instances of `pulp.X` can become just `X` if we make `X` local. In particular, `pulp.player`.

here is some incorrect behaviour:

these functions seemingly only execute their block once, not 
once per tile. They even execute the block if the tile does not exist.
Also, they read new value of event.px/event.py/event.x/event.y if it changes.

    tell "tile" to
    tell tile-id to
