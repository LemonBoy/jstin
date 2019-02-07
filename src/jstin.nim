import json
from strutils import `%`, parseEnum
from typetraits import nil

# This module contains a couple of patched routines that are needed in order to
# support multi-value pragmas.
from jstin/macros_compat import hasCustomPragma, getCustomPragmaVal, treeRepr

template staticEcho(args: varargs[untyped]) =
  when defined(jstinLogInvocation):
    static: echo args

type
  JstinOmit* = enum
    Never ## \
      ## Always serialize/deserialize the field.
    WhenEmpty ## \
      ## Do not deserialize the field if it's ``len()`` returns zero or
      ## ``isNil`` returns ``true``. When deserialized a missing field marked
      ## with this tag is initialized to its default (zero) value.
    Always ## \
      ## Never serialize this field. When deserialized a field marked with this
      ## tag is initialized to its default (zero) value.

template serializeAs*(key=""; omit=JstinOmit.Never) {.pragma.} ## \
  ## Serialize the field with ``key`` as name.
  ##
  ## The ``omit`` parameter allows the user to decide when the field should not
  ## be serialized/deserialized.

template verifyJsonKind(node: JsonNode, kinds: set[JsonNodeKind], destTyp: typedesc) =
  if node.kind notin kinds:
    let msg = "Incorrect JSON kind. Trying to unmarshal `$#` into `$#`." % [
      $node.kind,
      typetraits.`$`(destTyp)
    ]
    raise newException(JsonKindError, msg)

template getFieldOpts(f, v: untyped): untyped =
  when hasCustomPragma(v, serializeAs):
    const o = getCustomPragmaVal(v, serializeAs)
    # If the specified key is empty use the field name
    when o.key.len > 0: o
    else: (key: f, omit: o.omit)
  else:
    (key: f, omit: JstinOmit.Never)

template emptyCheck(x: untyped): bool =
  when compiles(len(x)): len(x) == 0
  elif compiles(isNil(x)): isNil(x)
  else:
    {.error: "Cannot determine if this type is empty or not!".}

template default[T](): T =
  var x: T
  x

{.push inline.}

proc toJson*[T: SomeInteger|char](obj: T): JsonNode =
  staticEcho "toJson(integer) ", typetraits.name(type(T))
  result = newJInt(BiggestInt(obj))

proc toJson*[T: enum](obj: T): JsonNode =
  staticEcho "toJson(enum) ", typetraits.name(type(T))
  result = newJString($obj)

proc toJson*[T: SomeFloat](obj: T): JsonNode =
  staticEcho "toJson(float) ", typetraits.name(type(T))
  result = newJFloat(obj)

proc toJson*[T: string](obj: T): JsonNode =
  staticEcho "toJson(string) ", typetraits.name(type(T))
  result = newJString(obj)

proc toJson*[T: bool](obj: T): JsonNode =
  staticEcho "toJson(bool) ", typetraits.name(type(T))
  result = newJBool(obj)

proc toJson*[T: array|seq](obj: T): JsonNode =
  staticEcho "toJson(array or seq) ", typetraits.name(type(T))
  result = newJArray()
  for x in obj: result.add(toJson(x))

proc toJson*[T: JsonNode](obj: T): JsonNode =
  staticEcho "toJson(JsonNode)"
  result = obj

proc toJson*[T: ref object](obj: T): JsonNode =
  staticEcho "toJson(ref object) ", typetraits.name(type(T))
  if obj == nil: result = newJNull()
  else: result = toJson(obj[])

proc toJson*[T: object](obj: T): JsonNode =
  staticEcho "toJson(obj) ", typetraits.name(type(T))
  result = newJObject()
  for f, v in obj.fieldPairs:
    const opts = getFieldOpts(f, v)
    staticEcho: opts
    when opts.omit == Never: result[opts.key] = toJson(v)
    elif opts.omit == WhenEmpty:
      if not emptyCheck(v): result[opts.key] = toJson(v)

proc toJson*[T: tuple](obj: T): JsonNode =
  staticEcho "toJson(tuple) ", typetraits.name(type(T))
  result = newJObject()
  for f, v in obj.fieldPairs:
    result[f] = toJson(v)

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
  for i, val in mpairs(obj):
    val.fromJson(node[i])

proc fromJson*[T: seq](obj: var T; node: JsonNode) =
  staticEcho "fromJson(seq) ", typetraits.name(type(T))
  verifyJsonKind(node, {JArray}, T)
  # Initialize the seq here as the object may not have been initialized at all
  obj = newSeq[type(obj[0])](node.len)
  for i, val in mpairs(obj):
    val.fromJson(node[i])

proc fromJson*[T: ref object](obj: var T; node: JsonNode) =
  staticEcho "fromJson(ref obj) ", typetraits.name(type(T))
  verifyJsonKind(node, {JNull, JObject}, T)
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
  # Iterate over a dummy variable and then copy it over `obj` in order to work
  # around a bug in `hasCustomPragma`
  for f, v in obj.fieldPairs:
    const opts = getFieldOpts(f, v)
    when opts.omit == Never: fromJson(v, node[opts.key])
    elif opts.omit == WhenEmpty:
      if opts.key in node: fromJson(v, node[opts.key])
      else: v = default(type(v))

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
