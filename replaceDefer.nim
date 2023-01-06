import std/macros

const DEBUGMODE = defined(debugDefer)

proc convertToTryFinally(body: NimNode): NimNode {.compileTime.} =
  result = newStmtList()
  var currentBody = result
  if body.kind == nnkProcDef:
    # macro is being used as a pragma
    body[6] = convertToTryFinally(body[6])
    return body
  
  for node in body:
    if node.kind == nnkCall and node[0].kind == nnkIdent and node[0].strVal == "sdefer":
      var newBody = newStmtList()
      currentBody.add(nnkTryStmt.newTree(
        newBody,
        nnkFinally.newTree(
          node[1],
        )
      ))
      currentBody = newBody
    elif node.kind == nnkBlockStmt:
      when DEBUGMODE:
        echo node.astGenRepr()
      var guts = nnkBlockStmt.newTree(
        node[0],
        convertToTryFinally(node[1]),
      )
      currentBody.add(guts)
    else:
      # normal code
      when DEBUGMODE:
        echo "normal code"
      currentBody.add(node)

macro scoper*(body: untyped): untyped =
  when DEBUGMODE:
    echo "--------------------------------------------------"
    echo "RUNNING SCOPER ON", body.toStrLit()
    echo body.astGenRepr
    echo "--------------------------------------------------"
  result = convertToTryFinally(body)
  when DEBUGMODE:
    echo "--------------------------------------------------"
    echo result.toStrLit()


when isMainModule:
  import std/unittest
  proc causeErr = raise newException(ValueError, "foo")

  test "basic":
    var res: seq[int]
    scoper:
      res.add 1
      sdefer: res.add 2
    check res == @[1,2]
  
  test "let variables":
    var res: seq[int]
    scoper:
      let i = 1
      sdefer: res.add(i)
    check res == @[1]

  test "var variables":
    var res: seq[int]
    scoper:
      var i = 1
      sdefer: res.add(i)
      i.inc()
    check res == @[2]
  
  test "multiple":
    var res: seq[int]
    scoper:
      sdefer: res.add(1)
      res.add(2)
      sdefer: res.add(3)
      res.add(4)
    check res == @[2,4,3,1]
  
  test "exception":
    var res: seq[int]
    expect Exception:
      scoper:
        res.add(1)
        sdefer: res.add(2)
        causeErr()
        sdefer: res.add(3)
    check res == @[1,2]
  
  test "nested":
    var res: seq[int]
    scoper:
      res.add(1)
      sdefer: res.add(2)
      scoper:
        res.add(3)
        sdefer: res.add(4)
      res.add(5)
      sdefer: res.add(6)
    check res == @[1,3,4,5,6,2]

  test "block":
    var res: seq[int]
    scoper:
      res.add(1)
      sdefer: res.add(2)
      block:
        res.add(3)
        sdefer: res.add(4)
      res.add(5)
      sdefer: res.add(6)
    check res == @[1,3,4,5,6,2]
  
  test "named block":
    var res: seq[int]
    scoper:
      res.add(1)
      sdefer: res.add(2)
      block foo:
        res.add(3)
        sdefer: res.add(4)
        break foo
      res.add(5)
      sdefer: res.add(6)
    check res == @[1,3,4,5,6,2]

  test "proc":
    proc foo(): seq[int] {.scoper.} =
      result.add(1)
      sdefer: result.add(2)
      block:
        result.add(3)
        sdefer: result.add(4)
      result.add(5)
      sdefer: result.add(6)
    check foo() == @[1,3,4,5,6,2]

  const asyncBackend {.strdefine.} = ""
  when asyncBackend == "chronos":
    import chronos
    test "waitFor":
      var res: seq[int]
      scoper:
        res.add(1)
        waitFor sleepAsync(1.milliseconds)
        sdefer:
          waitFor sleepAsync(1.milliseconds)
          res.add(2)
        res.add(3)
      check res == @[1,3,2]
    
    test "async":
      proc asyncProc(): Future[seq[int]] {.scoper, async.} =
        result.add(1)
        await sleepAsync(1.milliseconds)
        sdefer:
          await sleepAsync(1.milliseconds)
          result.add(2)
        sdefer:
          await sleepAsync(1.milliseconds)
          result.add(3)
        await sleepAsync(1.milliseconds)
        result.add(4)
      check (waitFor asyncProc()) == @[1,4,3,2]
