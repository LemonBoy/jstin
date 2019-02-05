jstin
=====

JSON {de,}serialization for the working men.

## Why? ##

- Automagic: compile-time magic makes sure your data is correctly mapped into
  appropriate json objects.
- Simple: a set of procedures that know how to handle a particular kind of data
  are gracefully composed toghether behind your back.
- Extensible: if you ever need to write your own serializer/deserializer you can
  do so in a few lines of code.

## Quickstart ##

Let's start with a simple yet complete example.

You've got a bunch of data from a REST API and now you want to wrap it in a neat
data structure. Some fields have horrendous and non-descriptive names and
there's a timestamp serialized as a string you'd like to turn into a `DateTime`
object but fear not, we'll put an end to this madness very soon.

```nim
import jstin
import json
import times

type
  Person = object
    name {.serializeAs: "falafel".}: string
    surname {.serializeAs: "kebab".}: string
    birthDate {.serializeAs: "dob".}: DateTime

proc fromJson(x: var DateTime, n: JsonNode) =
  # Decode the timestamp string
  x = n.getStr().parse("dd-MM-yyyy")

proc toJson(x: DateTime): JsonNode =
  # Encode the timestamp as string
  result = newJString(x.format("dd-MM-yyyy"))

const myData = """
[
 { "falafel": "Mark", "kebab": "Twain", "dob": "30-11-1835" },
 { "falafel": "Pafnutij L'vovič", "kebab": "Čebyšëv", "dob": "16-05-1821" },
 { "falafel": "Harry", "kebab": "Nyquist", "dob": "07-02-1889" }
]
"""

let parsed = parseJson(myData)
# Et-voilá!
let asObj = fromJson[seq[Person]](parsed)
# Let's show that the serialization + deserialization are idempotent
doAssert(parsed == toJson(asObj))
```

## FAQ

### I get a few `ProveInit` warnings, is that normal?

Those warnings are shown because the compiler doesn't understand the explicit
`noinit` tag, a patch about this has already been submitted upstream. The whole
temporary variable is only needed in order to work-around a bug in the
`hasCustomPragma` implementation and, again, a patch has been submitted
upstream.
