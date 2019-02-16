import json
import strutils
from typetraits import nil

# This module contains a couple of patched routines that are needed in order to
# support multi-value pragmas.
from jstin/macros_compat import hasCustomPragma, getCustomPragmaVal, treeRepr

template staticEcho(args: varargs[untyped]) =
  when defined(jstinLogInvocation):
    static: echo args

type
  JstinOmit* = enum ## \
    ## When deserialized, missing fields marked with the ``Never`` tag or with
    ## the ``WhenEmpty`` tag are initialized to their default (zero) value.
    ##
    ## A field is considered empty if:
    ## - It is convertible to a ``bool`` and its value is ``false``;
    ## - ``isNil(field)`` returns true;
    ## - Its length, evaluated as ``len(field)``, is zero.
    Never     ## Always serialize/deserialize the field.
    WhenEmpty ## Do not deserialize the field if empty.
    Always    ## Never serialize the field.

  JstinRenameRule* = enum ## \
    ## These rules are used to rename all the objects field names using the
    ## selected case convention.
    NoRename    ## No conversion is done.
    LowerCase   ## "lowercase"
    UpperCase   ## "UPPERCASE"
    CapitalCase ## "Capitalcase"
    CamelCase   ## "camelCase"
    SnakeCase   ## "snake_case"

  JstinDeserializeError* = object of CatchableError

template objTag*(renameAll: JstinRenameRule) {.pragma.} ## \
  ## Use this to tag an object type.

template fieldTag*(rename = ""; omit = JstinOmit.Never) {.pragma.} ## \
  ## Use this to tag an object field.

template raiseDesError(msg: string) =
  raise newException(JstinDeserializeError, msg)

template verifyJsonKind(node: JsonNode, kinds: set[JsonNodeKind], destTyp: typedesc) =
  if node.kind notin kinds:
    let msg = "Incorrect JSON kind. Trying to unmarshal `$#` into `$#`." % [
      $node.kind,
      typetraits.`$`(destTyp)
    ]
    raise newException(JsonKindError, msg)

proc renameIdent(custom, name: string, rule: JstinRenameRule):
  string {.compiletime.} =
  # Prefer the custom tag, if supplied
  if custom.len != 0:
    return custom

  case rule
  of NoRename:
    result = name
  of LowerCase:
    result = name.toLowerAscii()
  of UpperCase:
    result = name.toUpperAscii()
  of CapitalCase:
    result = name.capitalizeAscii()
  of CamelCase:
    # Convert snake_case to camelCase
    for i, ch in name:
      if ch != '_':
        if i > 0 and name[i - 1] == '_':
          result.add(ch.toUpperAscii())
        else:
          result.add(ch.toLowerAscii())
  of SnakeCase:
    # Convert camelCase to snake_case
    for ch in name:
      if ch in {'A' .. 'Z'}:
        if result.len > 0: result.add('_')
      result.add(ch.toLowerAscii())

template getFieldOpts(name, sym, rule: untyped): untyped =
  # Given the field name `name`, its symbol `sym` and the rename rule `rule` we
  # shall figure out what to do with this field.
  when hasCustomPragma(sym, fieldTag):
    const tag = getCustomPragmaVal(sym, fieldTag)
    (key: renameIdent(tag.rename, name, rule), omit: tag.omit)
  else:
    (key: renameIdent("", name, rule), omit: Never)

template emptyCheck(x: untyped): bool =
  # Try to determine if a given field is empty, for some definition of empty.
  when compiles(bool(x)):  bool(x)
  elif compiles(isNil(x)): isNil(x)
  elif compiles(len(x)):   len(x) == 0
  else:
    {.error: "Cannot determine if this type is empty or not!".}

template default[T](t: typedesc[T]): T =
  var v: T
  v

{.push inline.}

proc toJson*[T: SomeInteger|char](val: T): JsonNode =
  staticEcho "toJson(integer) ", typetraits.name(type(T))
  result = newJInt(BiggestInt(val))

proc toJson*[T: enum](val: T): JsonNode =
  staticEcho "toJson(enum) ", typetraits.name(type(T))
  result = newJString($val)

proc toJson*[T: SomeFloat](val: T): JsonNode =
  staticEcho "toJson(float) ", typetraits.name(type(T))
  result = newJFloat(val)

proc toJson*[T: string](val: T): JsonNode =
  staticEcho "toJson(string) ", typetraits.name(type(T))
  result = newJString(val)

proc toJson*[T: bool](val: T): JsonNode =
  staticEcho "toJson(bool) ", typetraits.name(type(T))
  result = newJBool(val)

proc toJson*[T: array|seq](val: T): JsonNode =
  staticEcho "toJson(array or seq) ", typetraits.name(type(T))
  result = newJArray()
  for x in val: result.add(toJson(x))

proc toJson*[T: JsonNode](val: T): JsonNode =
  staticEcho "toJson(JsonNode)"
  result = val

proc toJson*[T: ref](val: T): JsonNode =
  staticEcho "toJson(ref) ", typetraits.name(type(T))
  if val == nil: result = newJNull()
  else: result = toJson(val[])

proc toJson*[T: object](val: T): JsonNode =
  staticEcho "toJson(obj) ", typetraits.name(type(T))
  when hasCustomPragma(val, objTag):
    const renameAll = getCustomPragmaVal(val, objTag)
  else:
    const renameAll = NoRename
  result = newJObject()
  for name, sym in val.fieldPairs:
    const opts = getFieldOpts(name, sym, renameAll)
    when opts.omit == Never:
      result[opts.key] = toJson(sym)
    elif opts.omit == WhenEmpty:
      if not emptyCheck(sym): result[opts.key] = toJson(sym)

proc toJson*[T: tuple](val: T): JsonNode =
  staticEcho "toJson(tuple) ", typetraits.name(type(T))
  result = newJObject()
  for name, sym in val.fieldPairs:
    result[name] = toJson(sym)

proc fromJson*[T: SomeInteger|char](obj: var T; node: JsonNode) =
  staticEcho "fromJson(integer) ", typetraits.name(type(T))
  verifyJsonKind(node, {JInt}, T)
  obj = type(obj)(node.num)

proc fromJson*[T: enum](obj: var T; node: JsonNode) =
  staticEcho "fromJson(enum) ", typetraits.name(type(T))
  verifyJsonKind(node, {JString}, T)
  obj = parseEnum[T](node.str)

proc fromJson*[T: SomeFloat](obj: var T; node: JsonNode) =
  staticEcho "fromJson(float) ", typetraits.name(type(T))
  verifyJsonKind(node, {JFloat}, T)
  obj = type(obj)(node.fnum)

proc fromJson*[T: string](obj: var T; node: JsonNode) =
  staticEcho "fromJson(string) ", typetraits.name(type(T))
  verifyJsonKind(node, {JString}, T)
  obj = node.str

proc fromJson*[T: bool](obj: var T; node: JsonNode) =
  staticEcho "fromJson(bool) ", typetraits.name(type(T))
  verifyJsonKind(node, {JBool}, T)
  obj = node.bval

proc fromJson*[T: array](obj: var T; node: JsonNode) =
  staticEcho "fromJson(array) ", typetraits.name(type(T))
  verifyJsonKind(node, {JArray}, T)
  if node.len != obj.len:
    raiseDesError("Array size mismatch, got $1 elements but expected $2" %
      [$node.len, $obj.len])
  for i, val in mpairs(obj):
    val.fromJson(node[i])

proc fromJson*[T: seq](obj: var T; node: JsonNode) =
  staticEcho "fromJson(seq) ", typetraits.name(type(T))
  verifyJsonKind(node, {JArray}, T)
  # Initialize the seq here as the object may not have been initialized at all
  obj = newSeq[type(obj[0])](node.len)
  for i, val in mpairs(obj):
    val.fromJson(node[i])

proc fromJson*[T: ref](obj: var T; node: JsonNode) =
  staticEcho "fromJson(ref) ", typetraits.name(type(T))
  if node.kind == JNull: obj = nil
  else:
    new(obj)
    (obj[]).fromJson(node)

proc fromJson*[T: JsonNode](obj: var T; node: JsonNode) =
  staticEcho "fromJson(JsonNode)"
  if node.kind == JNull: obj = nil
  else: obj = node.copy()

proc fromJson*[T: object](obj: var T; node: JsonNode) =
  staticEcho "fromJson(obj) ", typetraits.name(type(T))
  verifyJsonKind(node, {JObject}, T)
  when hasCustomPragma(obj, objTag):
    const renameAll = getCustomPragmaVal(obj, objTag)
  else:
    const renameAll = NoRename
  for name, sym in obj.fieldPairs:
    const opts = getFieldOpts(name, sym, renameAll)
    when opts.omit == Never:
      fromJson(sym, node[opts.key])
    elif opts.omit == WhenEmpty:
      if opts.key in node: fromJson(sym, node[opts.key])
      else: sym = default(type(sym))

proc fromJson*[T: tuple](obj: var T; node: JsonNode) =
  staticEcho "fromJson(tuple) ", typetraits.name(type(T))
  verifyJsonKind(node, {JObject}, T)
  for f, v in obj.fieldPairs:
    v.fromJson(node[f])

{.pop.}

proc fromJson*[T](node: JsonNode): T =
  ## Convenience function to deserialize the object ``node`` in a fresh
  ## variable of type ``T``.
  fromJson(result, node)
