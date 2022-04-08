from cmath import exp
from re import S


class PulpScriptContext:
    def __init__(self):
        self.indent = 1
        self.errors = []
        self.evname = None
        
    def gi(self):
        return "  "*self.indent
        
compdict = {
    "lt": "<",
    "lte": ">=",
    "gt": ">",
    "gte": "<=",
    "eq": "==",
    "neq": "~=",
}

funclist = [
    "goto",
    "shake",
    "fin",
    "hide",
    "bpm",
    "draw",
    "sound",
    "round",
    "invert",
    "frame",
    "restore",
    "floor",
    "fill",
    "swap",
    "frame",
    "label",
    "store",
    "wait",
    "say",
    "loop",
    "once",
    "tell"
]

exfuncs = [
    "frame",
    "name",
    "round",
    "floor",
    "invert",
    "random",
    "lpad", # args: (string, width, padsymbol)
    "rpad", # args: (string, width, padsymbol)
]

def istoken(s):
    if type(s) != str:
        return False
    if " " in s:
        return False
    if "-" in s:
        return False
    return True

def ex_get(expression, ctx):
    return expression[1]
    
def ex_format(expression, ctx):
    s = ""
    args = []
    subnewline = False
    for component in expression[1:]:
        if type(component) == str:
            s += component
            if "\n" in s:
                subnewline = True
        else:
            s += '%s'
            args.append(component)
            
    if subnewline:
        s = 'string.format([[' + s + ']]'
    else:
        s = 'string.format("' + s + '"'
    for arg in args:
        s += f", tostring({decode_rvalue(arg, ctx)})"
    s += ")"
    return s

def ex_embed(expression, ctx):
    return f"__pulp:__ex_embed({decode_rvalue(expression[1], ctx)})"

def ex_subroutine(expression, ctx):
    s = "function()"
    ctx.indent += 2
    s += transpile_commands(ctx.blocks[expression[1]], ctx)
    ctx.indent -= 2
    return s + ctx.gi() + "  end"

def decode_rvalue(expression, ctx):
    if type(expression) == str:
        return str(expression)
    elif type(expression) == int or type(expression) == float:
        return str(expression)
    else:
        ex = expression[0]
        if ex == "get":
            return ex_get(expression, ctx)
        elif ex == "format":
            return ex_format(expression, ctx)
        elif ex == "embed":
            return ex_embed(expression, ctx)
        elif ex in exfuncs:
            return opex_func(expression, "__ex_" + ex, ctx)
        elif ex == "block":
            return ex_subroutine(expression, ctx)
        else:
            ctx.errors += ["unknown expression code: " + ex]
            return f"nil --[[unknown expression code '{ex}']]"

def op_set(cmd, operator, ctx):
    lvalue = cmd[1]
    assert (type(lvalue) == str)
    rvalue = decode_rvalue(cmd[2], ctx)
    return f"{lvalue} {operator} {rvalue}"
    pass

def op_block(cmd, statement, follow, ctx):
    condition = cmd[1]
    comparison = condition[0]
    assert comparison in compdict, f"unrecognized comparison operator '{comparison}'"
    compsym = compdict[comparison]
    compl = decode_rvalue(condition[1], ctx)
    compr = decode_rvalue(condition[2], ctx)
    block = cmd[2]
    assert(block[0] == "block")
    s = f"{statement} {compl} {compsym} {compr} {follow}"
    ctx.indent += 1
    s += transpile_commands(ctx.blocks[block[1]], ctx)
    ctx.indent -= 1
    s += ctx.gi() + "end"
    return s
    
def op_call(cmd, ctx):
    if istoken(cmd[1]):
        return f"self:{cmd[1]}()"
    else:
        return f"self[{decode_rvalue(cmd[1], ctx)}]()"
        
def op_emit(cmd, ctx):
    return f"__pulp:emit({decode_rvalue(cmd[1], ctx)})"
    
def op_mimic(cmd, ctx):
    s = f"__pulp:getScript({decode_rvalue(cmd[1], ctx)})"
    if istoken(ctx.evname):
        s += f".{ctx.evname}"
    else:
        s += f"[{decode_rvalue(cmd[1])}]"
    return s + "(self, event) -- (Mimic)"
    
def opex_func(cmd, op, ctx):
    mainargs = []
    setargs = {}
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
    _pre_mainarg = "{"
    first = True
    for sarg in setargs:
        if first:
            first = False
        else:
            _pre_mainarg += ", "
        _pre_mainarg += sarg + " = " + setargs[sarg]
    _pre_mainarg += "}"
    mainargs = [_pre_mainarg] + mainargs
    
    s = f"__pulp:{op}("
    first = True
    for arg in mainargs:
        if first:
            first = False
        else:
            s += ", "
        s += arg
    return s + ")"

def transpile_command(cmd, ctx):
    op = cmd[0]
    
    if op == "_":
        return ctx.gi() + "\n"
    elif op == "set":
        return ctx.gi() + op_set(cmd, "=", ctx) + "\n"
    elif op == "add":
        return ctx.gi() + op_set(cmd, "+=", ctx) + "\n"
    elif op == "sub":
        return ctx.gi() + op_set(cmd, "-=", ctx) + "\n"
    elif op == "div":
        return ctx.gi() + op_set(cmd, "/=", ctx) + "\n"
    elif op == "mul":
        return ctx.gi() + op_set(cmd, "*=", ctx) + "\n"
    elif op == "if":
        return ctx.gi() + op_block(cmd, "if", "then", ctx) + "\n"
    elif op == "while":
        return ctx.gi() + op_block(cmd, "while", "do", ctx) + "\n"
    elif op == "call":
        return ctx.gi() + op_call(cmd, ctx) + "\n"
    elif op == "emit":
        return ctx.gi() + op_emit(cmd, ctx) + "\n"
    elif op == "mimic":
        return ctx.gi() + op_mimic(cmd, ctx) + "\n"
    elif op in funclist:
        return ctx.gi() + opex_func(cmd, "__fn_" + op, ctx) + "\n"
    elif op == "#":
        return f"{ctx.gi()}--(comment omitted)\n"
    elif op == "#$":
        return f"{ctx.gi()}--[[(multiline comment omitted)]]\n"
    else:
        ctx.errors += ["unknown command code: " + op]
        return ctx.gi() + f"--unknown command code '{op}'\n"

def transpile_commands(commands, ctx):
    s = ""
    for command in commands:
        if type(command) == list:
            s += transpile_command(command, ctx)
    return s
        
def transpile_event(evobj, evname, ctx, blockidx):
    ctx.evname = evname
    _evobj = evobj
    if not istoken(evobj):
        _evobj = f"__pulp:getScript(\"{evobj}\")"
    if istoken(evname) and istoken(evobj):
        s = f"function {_evobj}:{evname}(event)"
    else:
        s = f"{_evobj}[\"{evname}\"] = function(self, event)"
        
    s += transpile_commands(ctx.blocks[blockidx], ctx)
    s += "end"
    ctx.evname = None
    return s