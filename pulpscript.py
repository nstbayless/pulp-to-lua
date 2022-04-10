from cmath import exp
from re import S

RELASSIGN = True

class PulpScriptContext:
    def __init__(self):
        self.indent = 1
        self.errors = []
        self.vars = set()
        
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
    "frame",
    "label",
    "restore",
    "store",
    "toss",
    "wait",
    "say",
    "ask",
    "act",
    "loop",
    "once",
    "stop",
    "tell",
    "ignore",
    "listen",
    "log",
    "dump",
]

exfuncs = [
    "frame",
    "name",
    "floor",
    "round",
    "ceil",
    "invert",
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
    "__ex_frame": "({0}.frame or 0)",
}

funcargs = {
    "frame": ["actor"],
    "tell": ["x", "y", "block"],
    "goto": ["actor", "x", "y"],
    "tell": ["x", "y", "event", "block"],
    "swap": ["actor"],
    "name": ["actor"]
}

staticfuncs = {
    "floor": "__floor",
    "ceil": "__ceil",
    "round": "__round",
    "sine": "__sin",
    "cosine": "__cos",
    "sine": "__sin",
    "tangent": "__tan",
    "random": "__random"
}

def istoken(s):
    if type(s) != str:
        return False
    if " " in s:
        return False
    if "-" in s:
        return False
    return True

def ex_get(expression, ctx):
    ctx.vars.add(expression[1])
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
            args.append(component)
    
    ctx.format_embeds = []
    if subnewline:
        s = 'string.format([[' + s + ']]'
    else:
        s = 'string.format("' + s + '"'
    for arg in args:
        if type(arg) == list and arg[0] == "embed":
            pass
        else:
            s += f", tostring({decode_rvalue(arg, ctx)})"
    s += ")"
    return s

def ex_embed(expression, ctx):
    return f"__pulp.__ex_embed({decode_rvalue(expression[1], ctx)})"

def ex_subroutine(expression, ctx):
    s = "function(self, __actor, event)\n"
    ctx.indent += 2
    s += transpile_commands(ctx.blocks[expression[1]], ctx)
    ctx.indent -= 2
    return s + ctx.gi() + "  end"

def decode_rvalue(expression, ctx):
    if type(expression) == str:
        return '"' + str(expression).replace("\n", "\\n") + '"'
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
            return opex_func(expression, ex, "__ex_", ctx)
        elif ex == "block":
            return ex_subroutine(expression, ctx)
        else:
            ctx.errors += ["unknown expression code: " + ex]
            return f"nil --[[unknown expression code '{ex}']]"

def op_set(cmd, operator, ctx):
    lvalue = cmd[1]
    assert (type(lvalue) == str)
    ctx.vars.add(lvalue)
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
            s += op_block(sub, "elseif", "then", None, ctx)
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
    if istoken(cmd[1]):
        callfn = f"self.{cmd[1]}"
    else:
        callfn = f"self[{decode_rvalue(cmd[1], ctx)}]"
    return f"if {callfn} or self.any then ({callfn} or self.any)(self, __actor, event) end"
        
def op_emit(cmd, ctx):
    return f"__pulp:emit({decode_rvalue(cmd[1], ctx)}, __actor, event)"
    
def op_mimic(cmd, ctx):
    s = f"__pulp:getScriptEventByName({decode_rvalue(cmd[1], ctx)}, event.__name)"
    return s + "(self, __actor, event) -- (Mimic)"
    
def op_tell(cmd, ctx):
    if type(cmd[1]) == list and cmd[1][1] == "xy":
        pass
    else:
        return opex_func(cmd, "tell", "__fn_", ctx)
    
def opex_func(cmd, op, prefix, ctx):
    mainargs = []
    setargs = {
        "actor": "__actor",
        "event": "event"
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
    _evobj = evobj
    if not istoken(evobj):
        _evobj = f"__pulp:getScript(\"{evobj}\")"
    if istoken(evname) and istoken(evobj):
        s = f"function {_evobj}:{evname}(__actor, event)\n"
    else:
        s = f"{_evobj}[\"{evname}\"] = function(self, __actor, event)\n"
        
    s += transpile_commands(ctx.blocks[blockidx], ctx)
    s += "end\n"
    return s