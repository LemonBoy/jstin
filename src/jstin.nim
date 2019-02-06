import json
from macros import hasCustomPragma, getCustomPragmaVal, treeRepr
from strutils import `%`, parseEnum
from typetraits import nil

template staticEcho(args: varargs[untyped]) =
  when defined(jstinLogInvocation):
    static: echo args

template serializeAs*(key: string) {.pragma.} ## \
  ## Serialize the field with ``key`` as name. If an empty string is supplied
  ## the field is not {de,}serialized at all.

template verifyJsonKind(node: JsonNode, kinds: set[JsonNodeKind], destTyp: typedesc) =
  if node.kind notin kinds:
    let msg = "Incorrect JSON kind. Trying to unmarshal `$#` into `$#`." % [
      $node.kind,
      typetraits.`$`(destTyp)
    ]
    raise newException(JsonKindError, msg)

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
    when hasCustomPragma(v, serializeAs):
      const key = getCustomPragmaVal(v, serializeAs)
    else:
      const key = f
    if key.len > 0:
      result[key] = toJson(v)

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
  var dummy {.noinit.}: T
  for f, v in dummy.fieldPairs:
    when hasCustomPragma(v, serializeAs):
      const key = getCustomPragmaVal(v, serializeAs)
    else:
      const key = f
    if key.len > 0:
      fromJson(v, node[key])
  obj = dummy

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
