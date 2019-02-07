import unittest
import jstin
import json

template test(x: typed) =
  check(x == fromJson[type(x)](toJson(x)))

test "Roundtrip of simple types":
  test('c')
  test(true)
  test(false)
  test(10)
  test(15'i8)
  test(15'i16)
  test(15'i32)
  test(15'u8)
  test(15'u16)
  test(15'u32)
  test(3.14)
  test(3.14'f32)
  test(3.14'f64)
  test("foobar")
  test([1,2,3])
  test(@[1,2,3])

test "Handling of array & seq":
  let t1 = fromJson[array[3, int]](toJson([1,2,3,4]))
  let t2 = fromJson[array[3, int]](toJson(@[1,2,3,4,5]))
  doAssert(t1 == t2)
  doAssertRaises(IndexError):
    let t3 = fromJson[array[5, int]](toJson([1,2,3,4]))
  let t4 = fromJson[seq[int]](toJson([1,2,3,4]))
  doAssert(t4.len == 4)

test "Roundtrip of objects":
  type
    Bar = object
      a: int
      b: int

    Foo = object
      a: bool
      b: string
      c: float
      d: range[0..1000]
      e: ref Foo
      f: Bar

  test(Foo(a: false, b: "yes", c: 3.14, d: 99, e: nil, f: Bar(a: 1, b: 2)))

test "Roundtrip of tuples":
  test(())
  test((1, ))
  test((1, 2))
  test((1, 2, 3))
  test((1, (1, (1, (1, )))))
  test((foo: "abc", bar: (1,2,3)))

test "Field renaming":
  let jsonData = parseJson("""
  {
    "foo_bar_baz": 123,
    "badname": [false, false]
  }
  """)

  type
    MyObj = object
      someIntField {.serializeAs: "foo_bar_baz".}: int8
      someArrayThing {.serializeAs: "badname".}: seq[bool]

  let des = fromJson[MyObj](jsonData)
  check(des.someIntField == 123)
  check(des.someArrayThing == @[false, false])

type
  MyFoo = object
    x: string

  MyBar = object
    foo: MyFoo

proc fromJson(x: var MyFoo, n: JsonNode) =
  doAssert(n.kind == JString)
  doAssert(n.str[0 .. 2] == "xxx" and n.str[^3 .. ^1] == "xxx")
  x.x = n.str[4 .. ^5]

proc toJson(x: MyFoo): JsonNode =
  result = newJString("xxx " & x.x & " xxx")

test "Custom serializer":
  var obj = MyBar(foo: MyFoo(x: "super"))
  let check = fromJson[MyBar](toJson(obj))
  check(obj == fromJson[MyBar](toJson(obj)))

test "omit annotation":
  type
    Foo1 = object
      a {.serializeAs(omit=JstinOmit.Always).}: string
      b {.serializeAs(omit=JstinOmit.WhenEmpty).}: seq[int]
      c {.serializeAs(omit=JstinOmit.WhenEmpty).}: array[3, int]
      d {.serializeAs(omit=JstinOmit.WhenEmpty).}: ref Foo1
      e: float

  let obj = Foo1(a: "abc", b: @[], c: [1,2,3], d: nil, e: 6.28)
  let rec = fromJson[Foo1](toJson(obj))
  check(rec != obj)
  check(rec.a.len == 0)
  check(rec.b.len == 0)
  check(rec.c.len == 3)
  check(rec.d.isNil)
  check(rec.e == 6.28)
