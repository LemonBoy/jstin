import macros

export macros except getCustomPragmaVal, hasCustomPragma

const
  nnkCallKinds* = {nnkCall, nnkInfix, nnkPrefix, nnkPostfix, nnkCommand,
                   nnkCallStrLit}
  nnkPragmaCallKinds = {nnkExprColonExpr, nnkCall, nnkCallStrLit}

proc customPragmaNode(n: NimNode): NimNode =
  var n = n
  if n.kind == nnkHiddenDeref:
    n = n[0]
  expectKind(n, {nnkSym, nnkDotExpr, nnkBracketExpr, nnkTypeOfExpr, nnkCheckedFieldExpr})
  let
    typ = n.getTypeInst()

  if typ.kind == nnkBracketExpr and typ.len > 1 and typ[1].kind == nnkProcTy:
    return typ[1][1]
  elif typ.typeKind == ntyTypeDesc:
    let impl = typ[1].getImpl()
    if impl[0].kind == nnkPragmaExpr:
      return impl[0][1]
    else:
      return impl[0] # handle types which don't have macro at all

  if n.kind == nnkSym: # either an variable or a proc
    let impl = n.getImpl()
    if impl.kind in RoutineNodes:
      return impl.pragma
    elif impl.kind == nnkIdentDefs and impl[0].kind == nnkPragmaExpr:
      return impl[0][1]
    else:
      let timpl = typ.getImpl()
      if timpl.len>0 and timpl[0].len>1:
        return timpl[0][1]
      else:
        return timpl

  if n.kind in {nnkDotExpr, nnkCheckedFieldExpr}:
    let name = $(if n.kind == nnkCheckedFieldExpr: n[0][1] else: n[1])
    var typInst = getTypeInst(if n.kind == nnkCheckedFieldExpr or n[0].kind == nnkHiddenDeref: n[0][0] else: n[0])
    if typInst.kind == nnkVarTy: typInst = typInst[0]
    if typInst.kind == nnkBracketExpr: typInst = typInst[0]
    doAssert(typInst.kind == nnkSym)
    var typDef = getImpl(typInst)
    while typDef != nil:
      typDef.expectKind(nnkTypeDef)
      let typ = typDef[2]
      typ.expectKind({nnkRefTy, nnkPtrTy, nnkObjectTy})
      let isRef = typ.kind in {nnkRefTy, nnkPtrTy}
      if isRef and typ[0].kind in {nnkSym, nnkBracketExpr}: # defines ref type for another object(e.g. X = ref X)
        typDef = getImpl(typ[0])
      else: # object definition, maybe an object directly defined as a ref type
        let
          obj = (if isRef: typ[0] else: typ)
        var identDefsStack = newSeq[NimNode](obj[2].len)
        for i in 0..<identDefsStack.len: identDefsStack[i] = obj[2][i]
        while identDefsStack.len > 0:
          var identDefs = identDefsStack.pop()
          if identDefs.kind == nnkRecCase:
            identDefsStack.add(identDefs[0])
            for i in 1..<identDefs.len:
              let varNode = identDefs[i]
              # if it is and empty branch, skip
              if varNode[0].kind == nnkNilLit: continue
              if varNode[1].kind == nnkIdentDefs:
                identDefsStack.add(varNode[1])
              else: # nnkRecList
                for j in 0 ..< varNode[1].len:
                  identDefsStack.add(varNode[1][j])

          else:
            for i in 0 .. identDefs.len - 3:
              let varNode = identDefs[i]
              if varNode.kind == nnkPragmaExpr:
                var varName = varNode[0]
                if varName.kind == nnkPostfix:
                  # This is a public field. We are skipping the postfix *
                  varName = varName[1]
                if eqIdent($varName, name):
                  return varNode[1]

        if obj[1].kind == nnkOfInherit: # explore the parent object
          typDef = getImpl(obj[1][0])
        else:
          typDef = nil

macro hasCustomPragma*(n: typed, cp: typed{nkSym}): untyped =
  ## Expands to `true` if expression `n` which is expected to be `nnkDotExpr`
  ## (if checking a field), a proc or a type has custom pragma `cp`.
  ##
  ## See also `getCustomPragmaVal`.
  ##
  ## .. code-block:: nim
  ##   template myAttr() {.pragma.}
  ##   type
  ##     MyObj = object
  ##       myField {.myAttr.}: int
  ##
  ##   proc myProc() {.myAttr.} = discard
  ##
  ##   var o: MyObj
  ##   assert(o.myField.hasCustomPragma(myAttr))
  ##   assert(myProc.hasCustomPragma(myAttr))
  let pragmaNode = customPragmaNode(n)
  for p in pragmaNode:
    if (p.kind == nnkSym and p == cp) or
        (p.kind in nnkPragmaCallKinds and p.len > 0 and p[0].kind == nnkSym and p[0] == cp):
      return newLit(true)
  return newLit(false)

macro getCustomPragmaVal*(n: typed, cp: typed{nkSym}): untyped =
  ## Expands to value of custom pragma `cp` of expression `n` which is expected
  ## to be `nnkDotExpr`, a proc or a type.
  ##
  ## See also `hasCustomPragma`
  ##
  ## .. code-block:: nim
  ##   template serializationKey(key: string) {.pragma.}
  ##   type
  ##     MyObj {.serializationKey: "mo".} = object
  ##       myField {.serializationKey: "mf".}: int
  ##   var o: MyObj
  ##   assert(o.myField.getCustomPragmaVal(serializationKey) == "mf")
  ##   assert(o.getCustomPragmaVal(serializationKey) == "mo")
  ##   assert(MyObj.getCustomPragmaVal(serializationKey) == "mo")
  let pragmaNode = customPragmaNode(n)
  for p in pragmaNode:
    if p.kind in nnkPragmaCallKinds and p.len > 0 and p[0].kind == nnkSym and p[0] == cp:
      if p.len == 2:
        result = p[1]
      else:
        let def = p[0].getImpl[3]
        result = newTree(nnkPar)
        for i in 1 ..< def.len:
          let key = def[i][0]
          let val = p[i]
          result.add newTree(nnkExprColonExpr, key, val)
      break
  if result.kind == nnkEmpty:
    error(n.repr & " doesn't have a pragma named " & cp.repr()) # returning an empty node results in most cases in a cryptic error,
