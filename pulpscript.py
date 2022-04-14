# This file contains the logic for transpiling actual pulpscript code.
# It's more complicated than transpiling the assets, so it gets its own file
# to keep it self-contained.

RELASSIGN = True # allow relative assignment in lua, e.g. `x += 1`

class PulpScriptContext:
    def __init__(self):
        self.indent = 1
        self.errors = []
        self.vars = set()
        self.var_usage = {}
        self.full_mimics = []
        
        # cache these at the start of each function
        self.funccache = []
        
    def push_funccache(self):
        self.funccache.append(set())
    
    def pop_funccache(self):
        self.funccache = self.funccache[:-1]
    
    def get_funccache(self):
        return self.funccache[-1]
        
    def pingvar(self, varname):
        if "." in varname:
            # ignore these.
            return varname
        
        self.vars.add(varname)
        self.var_usage[varname] = self.var_usage.get(varname, 0) + 1
        if varname.startswith("__"):
            # to prevent namespace conflicts, we append additional underscores if the variable name
            # starts with two underscores.
            return "__" + varname
        else:
            return varname
        
    def gi(self):
        return "  "*self.indent
        
compdict = {
    "lt": "<",
    "lte": "<=",
    "gt": ">",
    "gte": ">=",
    "eq": "==",
    "neq": "~=",
}

funclist = [
    "goto",
    "shake",
    "fin",
    "hide",
    "draw",
    "bpm",
    "sound",
    "invert",
    "frame",
    "fill",
    "swap",
    "label",
    "restore",
    "store",
    "toss",
    "wait",
    "say",
    "ask",
    "menu",
    "option",
    "act",
    "loop",
    "once",
    "stop",
    "tell",
    "ignore",
    "listen",
    "log",
    "dump",
    "wait",
    "window",
    "crop",
    "play"
]

exfuncs = [
    "type",
    "solid",
    "frame",
    "floor",
    "round",
    "ceil",
    "invert",
    "name",
    "random",
    "sine",
    "cosine",
    "tangent",
    "degrees",
    "radians",
    "lpad", # args: (string, width, [padsymbol])
    "rpad", # args: (string, width, [padsymbol])
]

inlinefuncs = {
    "__fn_frame": "{0}.frame = {1}",
    "__fn_inc": "{0} += 1",
    "__fn_dec": "{0} -= 1",
    "__fn_log": "__print({0})",
    # OPTIMIZE: we can hardcode in __pix8scale to improve performance. __pix8scale is usually 1!
    # OPTIMIZE: we can probably perform the color decision at compile-time in most cases
    "__fn_fill": "__setcolour(__fillcolours[{4}]); __fillrect({0} * __pix8scale, {1} * __pix8scale, {2} * __pix8scale, {3} * __pix8scale)",
    "__ex_frame": "({0}.frame or 0)",
    "__ex_invert": "(__pulp.invert and 1 or 0)",
    "__ex_degrees": "({0} * 360 / __tau)",
    "__ex_radians": "({0} * __tau / 360)",
}

# specifies the order of the *first* arguments to these functions.
# additional arguments may follow!
funcargs = {
    "frame": ["actor"],
    "goto": ["x", "y"],
    "tell": ["event", "evname", "block"],
    "swap": ["actor"],
    "label": ["x", "y", "len", "lines"],
    "draw": ["x", "y"],
    "solid": ["x", "y"],
    "wait": ["self", "actor", "event", "evname", "block"],
    "say": ["x", "y", "w", "h", "self", "actor", "event", "evname", "block"],
    "ask": ["x", "y", "w", "h", "self", "actor", "event", "evname", "block"],
    "menu": ["x", "y", "w", "h", "self", "actor", "event", "evname", "block"],
    "option": ["self", "actor", "event", "evname", "block"],
    "window": ["x", "y", "w", "h"],
    "fill": ["x", "y", "w", "h"],
    "crop": ["x", "y", "w", "h"],
    "play": ["self", "actor", "event", "evname", "block"]
}

staticfuncs = {
    "floor": "__floor",
    "ceil": "__ceil",
    "round": "__round",
    "sine": "__sin",
    "cosine": "__cos",
    "sine": "__sin",
    "tangent": "__tan",
    "random": "__random",
}

# adds backslashes
def escape_string(s):
    return s.replace("\\","\\\\") \
        .replace("\n", "\\n") \
        .replace("\f", "\\f") \
        .replace("\"", "\\\"")

def istoken(s):
    if type(s) != str:
        return False
    if " " in s:
        return False
    if "-" in s:
        return False
    return True

tile_ids = dict() # populated in pulplua.py

def optimize_name_ref(cmd, idx):
    if len(cmd) > idx:
        if type(cmd[idx]) == str and cmd[idx] in tile_ids:
            cmd[idx] = [
                "optimized-id",
                tile_ids[cmd[idx]],
                cmd[idx]
            ]
            return True
    return False
    
def remap_special_varname(varname, ctx):
    # these require special caching behaviour per-function
    # note that they cannot be set (op_set), so we don't need to consider them there.
    if varname == "event.px":
        ctx.get_funccache().add("local __event_px = __pulp.player.x")
        return "__event_px"
    elif varname == "event.py":
        ctx.get_funccache().add("local __event_py = __pulp.player.y")
        return "__event_py"
    elif varname == "event.x":
        ctx.get_funccache().add("local __event_x = __actor.x or 0")
        return "__event_x"
    elif varname == "event.y":
        ctx.get_funccache().add("local __event_y = __actor.y or 0")
        return "__event_y"
    elif varname == "event.tile":
        ctx.get_funccache().add("local __event_tile = __actor.name or 0")
        return "__event_tile"
    elif varname == "event.room":
        return "event.room.name"
    elif varname == "event.player":
        return "__pulp.player.name"
        
    return varname

def ex_get(expression, ctx):
    return remap_special_varname(ctx.pingvar(expression[1]), ctx)
    
    
def ex_format(expression, ctx):
    s = ""
    first = True
    for component in expression[1:]:
        if not first:
            s += " .. "
        first = False
        if type(component) is str:
            s += decode_rvalue(component, ctx)
        else:
            s += "__tostring(" + decode_rvalue(component, ctx) + ")"
            
    return s

def ex_embed(expression, ctx):
    return f"__pulp.__ex_embed({decode_rvalue(expression[1], ctx)})"

def ex_subroutine(expression, ctx):
    s = "function(__self, __actor, event, evname)\n"
    ctx.indent += 2
    s += transpile_commands(ctx.blocks[expression[1]], ctx)
    ctx.indent -= 2
    return s + ctx.gi() + "  end"
    
def ex_name(expression, ctx):
    if type(expression[1]) == list and expression[1][0] == "xy":
        x = decode_rvalue(expression[1][1], ctx)
        y = decode_rvalue(expression[1][2], ctx)
        #return f"(((__roomtiles[{y}] or __pulp.EMPTY)[{x}] or __pulp.EMPTY).tile or __pulp.EMPTY).name or \"\""
        return f"__roomtiles[{y}][{x}].name"
    else:
        return opex_func(expression, "name", "__ex_", ctx)

def decode_rvalue(expression, ctx):
    if type(expression) == str:
        return '"' + escape_string(str(expression)) + '"'
    elif type(expression) == int or type(expression) == float:
        return str(expression)
    elif expression is None:
        return "nil"
    else:
        ex = expression[0]
        if ex == "get":
            return ex_get(expression, ctx)
        elif ex == "optimized-id":
            return f"--[[({expression[2]})]] "+str(expression[1])
        elif ex == "format":
            return ex_format(expression, ctx)
        elif ex == "embed":
            return ex_embed(expression, ctx)
        elif ex == "name":
            return ex_name(expression, ctx)
        elif ex in exfuncs:
            return opex_func(expression, ex, "__ex_", ctx)
        elif ex == "block":
            return ex_subroutine(expression, ctx)
        else:
            ctx.errors += ["unknown expression code: " + ex]
            return f"nil --[[unknown expression code '{ex}']]"

def op_set(cmd, operator, ctx):
    lvalue = cmd[1]
    assert (type(lvalue) == str)
    lvalue = ctx.pingvar(lvalue)
    rvalue = decode_rvalue(cmd[2], ctx)
    if operator == "" or RELASSIGN:
        return f"{lvalue} {operator}= {rvalue}"
    else:
        return f"{lvalue} = {lvalue} {operator} {rvalue}"

def op_block(cmd, statement, follow, end, ctx):
    condition = cmd[1]
    comparison = condition[0]
    assert comparison in compdict, f"unrecognized comparison operator '{comparison}'"
    compsym = compdict[comparison]
    if istoken(condition[1]):
        compl = condition[1]
        compl = remap_special_varname(ctx.pingvar(compl), ctx)
    else:
        compl = decode_rvalue(condition[1], ctx)
    compr = decode_rvalue(condition[2], ctx)
    block = cmd[2]
    assert(block[0] == "block")
    s = f"{statement} {compl} {compsym} {compr} {follow}\n"
    ctx.indent += 1
    s += transpile_commands(ctx.blocks[block[1]], ctx)
    ctx.indent -= 1
    
    for sub in cmd[3:]:
        if sub[0] == "elseif":
            s += ctx.gi() + op_block(sub, "elseif", "then", None, ctx)
        elif sub[0] == "else":
            s += ctx.gi() + "else\n"
            ctx.indent += 1
            block = sub[1]
            assert(block[0] == "block")
            s += transpile_commands(ctx.blocks[block[1]], ctx)
            ctx.indent -= 1
            pass
        else:
            assert False, f"unrecognized block followup '{sub[0]}'"
    if end:
        s += ctx.gi() + end
    return s

def op_call(cmd, ctx):
    global EVNAMECOUNTER
    if istoken(cmd[1]):
        fnstr = f"\"{cmd[1]}\""
        callfn = f"__self.{cmd[1]}"
    else:
        fnstr = decode_rvalue(cmd[1], ctx)
        callfn = f"__self[{fnstr}]"
    return f";({callfn} or __self.any)(__self, __actor, event, {fnstr}) -- call {fnstr}"
        
def op_emit(cmd, ctx):
    return f"__pulp:emit({decode_rvalue(cmd[1], ctx)}, event)"
    
def op_mimic(cmd, ctx):
    if optimize_name_ref(cmd, 1) or type(cmd[1]) == int:
        s = f"do -- (mimic)\n"
        ctx.indent += 1
        s += ctx.gi() + f"local __mimic_target__ = (__pulp.tiles[{decode_rvalue(cmd[1], ctx)}] or __pulp.EMPTY).script or __pulp.EMPTY;\n"
        s += ctx.gi() + "(__mimic_target__[__evname] or __mimic_target__.any)(__self, __actor, event, __evname)\n"
        ctx.indent -= 1
        s += ctx.gi() + "end"
        return s
    else:
        s = f"__pulp:getScriptEventByName({decode_rvalue(cmd[1], ctx)}, __evname)"
        return s + "(__self, __actor, event, __evname) -- (mimic)"
    
def op_tell(cmd, ctx):
    if type(cmd[1]) == list and cmd[1][0] == "xy":
        # inline version of 'tell x,y to'
        s = "do --tell x,y to\n"
        ctx.indent += 1
        assert cmd[2][0] == "block"
        s += ctx.gi() + f"local __actor = __roomtiles[{decode_rvalue(cmd[1][2], ctx)}][{decode_rvalue(cmd[1][1], ctx)}]\n"
        s += ctx.gi() + f"if __actor and __actor.tile then\n"
        ctx.indent += 1
        s += ctx.gi() + f"local __self = __actor.script or __pulp.EMPTY\n"
        s += transpile_commands(ctx.blocks[cmd[2][1]], ctx)
        ctx.indent -= 1
        s += ctx.gi() + f"end\n"
        ctx.indent -= 1
        s += ctx.gi() + "end\n"
        return s
    elif type(cmd[1]) == list and cmd[1][0] == "get" and cmd[1][1] in ["event.room", "event.game", "event.player"]:
        # inline version of 'tell event.X to'
        target = cmd[1][1]
        if target == "event.player":
            target = "__pulp.player"
        s = f"do --tell {target} to\n"
        ctx.indent += 1
        assert cmd[2][0] == "block"
        s += ctx.gi() + f"local __actor = {target}\n"
        s += ctx.gi() + f"if __actor then\n"
        ctx.indent += 1
        s += ctx.gi() + f"local __self = __actor.script or __pulp.EMPTY\n"
        s += transpile_commands(ctx.blocks[cmd[2][1]], ctx)
        ctx.indent -= 1
        s += ctx.gi() + f"end\n"
        ctx.indent -= 1
        s += ctx.gi() + "end\n"
        return s
    else:
        optimize_name_ref(cmd, 1)
        return opex_func(cmd, "tell", "__fn_", ctx)
    
def opex_func(cmd, op, prefix, ctx):
    mainargs = []
    setargs = {
        "self": "__self",
        "actor": "__actor",
        "event": "event",
        "evname": "__evname",
    }
        
    for arg in cmd[1:]:
        if type(arg) == list:
            if arg[0] == "xy":
                setargs["x"] = decode_rvalue(arg[1], ctx)
                setargs["y"] = decode_rvalue(arg[2], ctx)
            elif arg[0] == "rect":
                setargs["x"] = decode_rvalue(arg[1], ctx)
                setargs["y"] = decode_rvalue(arg[2], ctx)
                setargs["w"] = decode_rvalue(arg[3], ctx)
                setargs["h"] = decode_rvalue(arg[4], ctx)
            elif arg[0] == "block":
                # e.g. "then" or "to"
                setargs["block"] = decode_rvalue(arg, ctx)
            else:
                mainargs.append(decode_rvalue(arg, ctx))
        else:
            mainargs.append(decode_rvalue(arg, ctx))
    
    if op in funcargs:
        for argname in funcargs[op][::-1]:
            if argname in setargs:
                mainargs = [setargs[argname]] + mainargs
            else:
                mainargs = ["nil"] + mainargs
    
    if prefix + op in inlinefuncs:
        s = inlinefuncs[prefix + op]
        for i in range(len(mainargs)):
            s = s.replace("{" + str(i) + "}", mainargs[i])
        return s
    elif op in staticfuncs:
        s = staticfuncs[op] + "("
    else:
        s = f"__pulp.{prefix}{op}("
    first = True
    for arg in mainargs:
        if first:
            first = False
        else:
            s += ", "
        s += arg
    return s + ")"

def op_inc(cmd, operator, ctx):
    return cmd[1] + operator

def transpile_command(cmd, ctx):
    op = cmd[0]
    
    if op == "_":
        return "" # ctx.gi() + "\n"
    elif op == "set":
        return ctx.gi() + op_set(cmd, "", ctx) + "\n"
    elif op == "add":
        return ctx.gi() + op_set(cmd, "+", ctx) + "\n"
    elif op == "sub":
        return ctx.gi() + op_set(cmd, "-", ctx) + "\n"
    elif op == "div":
        return ctx.gi() + op_set(cmd, "/", ctx) + "\n"
    elif op == "mul":
        return ctx.gi() + op_set(cmd, "*", ctx) + "\n"
    elif op == "inc":
        return ctx.gi() + op_inc(cmd, "+=1", ctx) + "\n"
    elif op == "dec":
        return ctx.gi() + op_inc(cmd, "-=1", ctx) + "\n"
    elif op == "if":
        return ctx.gi() + op_block(cmd, "if", "then", "end", ctx) + "\n"
    elif op == "while":
        return ctx.gi() + op_block(cmd, "while", "do", "end", ctx) + "\n"
    elif op == "call":
        return ctx.gi() + op_call(cmd, ctx) + "\n"
    elif op == "emit":
        return ctx.gi() + op_emit(cmd, ctx) + "\n"
    elif op == "mimic":
        return ctx.gi() + op_mimic(cmd, ctx) + "\n"
    elif op == "tell":
        return ctx.gi() + op_tell(cmd, ctx) + "\n"
    elif op in funclist:
        return ctx.gi() + opex_func(cmd, op, "__fn_", ctx) + "\n"
    elif op == "#":
        return f"{ctx.gi()}--(comment omitted)\n"
    elif op == "#$":
        return f"{ctx.gi()}--(previous-line comment omitted)\n"
    else:
        ctx.errors += ["unknown command code: " + op]
        return ctx.gi() + f"--unknown command code '{op}'\n"

def transpile_commands(commands, ctx, has_funccache=False):
    if has_funccache:
        ctx.push_funccache()
    s = ""
    for command in commands:
        if type(command) == list:
            s += transpile_command(command, ctx)
    if has_funccache:
        for cached in sorted(list(ctx.get_funccache())):
            s = ctx.gi() + cached + "\n" + s
        ctx.pop_funccache()
    return s
        
def transpile_event(evobj, evname, ctx, blockidx):
    _evobj = f"__pulp:getScript(\"{evobj}\")"
    if istoken(evname):
        s = f"{_evobj}.{evname} = function(__self, __actor, event, __evname)\n"
    else:
        s = f"{_evobj}[\"{evname}\"] = function(__self, __actor, event, __evname)\n"
    
    block = ctx.blocks[blockidx]
    
    cmdstr = transpile_commands(ctx.blocks[blockidx], ctx, True)
    
    s += cmdstr
    s += "end\n"
    
    #optimization for one-line-only mimics
    undecorated_block = list(filter(lambda x: type(x) == list and x[0] not in ["_", "#", "#$"], block))
    if len(undecorated_block) == 1 and undecorated_block[0][0] == "mimic":
        mimic = undecorated_block[0]
        # TODO: if int instead of optimized-id
        if type(mimic[1]) == list and mimic[1][0] == "optimized-id":
            mimic[1][2]
            ctx.full_mimics.append((evobj, evname, mimic[1][2]))
    
    return s