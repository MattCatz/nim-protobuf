# Uses a message exported from another module with exportMessage, checking
# that the accessors, presence procs, reader, and writer all cross the module
# boundary.
import exportdefs
import streams, tables

var p = initPerson(name = "test", id = 4'i32)
assert p.has(name, id)
assert not p.has(emails)
p.name = "changed"
p.emails = @["a@example.com"]
p.emails.add "b@example.com"
p.attributes = {"role": "admin"}.toTable

var ss = newStringStream()
ss.write p
ss.setPosition(0)
var q = ss.readPerson()

assert q.name == "changed"
assert q.id == 4
assert q.emails == @["a@example.com", "b@example.com"]
assert q.attributes["role"] == "admin"


q.reset(id)
assert not q.has(id)

echo "All good!"
