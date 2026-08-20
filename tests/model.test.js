// Run with: node tests/model.test.js
// Fixtures are real busctl output captured from a live kdeconnectd (see
// tests/fixtures/). No framework — zero-dependency assert only.
var assert = require("assert")
var fs = require("fs")
var path = require("path")
var M = require("../Model.js")

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
}

// ---- parsing real fixtures ----

var ids = M.parseDeviceIds(fixture("devices.json"))
assert.deepStrictEqual(ids, ["40d6dd619e324d6a9af645c76a2349df"])

var props = M.parseProperties(fixture("device-getall.json"))
assert.strictEqual(props.name, "motorola edge 50 ultra")
assert.strictEqual(props.isPaired, true)
assert.strictEqual(props.isReachable, false)
assert.ok(Array.isArray(props.supportedPlugins))

var loaded = M.parseStringList(fixture("loaded-plugins.json"))
assert.deepStrictEqual(loaded, [])

// ---- malformed input never throws ----

;["", "not json", "{}", '{"data":42}', '{"type":"as"}', "null"].forEach(function (bad) {
  assert.strictEqual(M.parseCallResult(bad), null)
  assert.strictEqual(M.parseProperties(bad), null)
  assert.strictEqual(M.parseDeviceIds(bad), null)
})

// ---- normalization ----

var dev = M.normalizeDevice("40d6dd619e324d6a9af645c76a2349df", props, loaded, null)
assert.strictEqual(dev.connected, false)
assert.strictEqual(dev.paired, true)
assert.strictEqual(dev.pairable, false)
assert.strictEqual(dev.battery.available, false)
assert.strictEqual(dev.caps.ring, false) // capability requires loaded, not just supported

var reachableProps = Object.assign({}, props, { isReachable: true })
var allLoaded = ["kdeconnect_battery", "kdeconnect_findmyphone", "kdeconnect_ping",
  "kdeconnect_clipboard", "kdeconnect_share", "kdeconnect_remotecommands"]
var dev2 = M.normalizeDevice("id2", reachableProps, allLoaded, { charge: 82, isCharging: true })
assert.strictEqual(dev2.connected, true)
assert.deepStrictEqual(dev2.battery, { available: true, percentage: 82, charging: true })
assert.ok(dev2.caps.ring && dev2.caps.ping && dev2.caps.clipboard && dev2.caps.share)

// battery object present but unreported charge (-1) → unavailable
var dev3 = M.normalizeDevice("id3", reachableProps, allLoaded, { charge: -1, isCharging: false })
assert.strictEqual(dev3.battery.available, false)

// normalize survives null/garbage props entirely
var devBad = M.normalizeDevice("x", null, null, null)
assert.strictEqual(devBad.name, "Unknown device")
assert.strictEqual(devBad.connected, false)

// ---- ordering ----

function mini(id, name, connected, paired, reachable) {
  return M.normalizeDevice(id, { name: name, isPaired: paired, isReachable: reachable }, [], null)
}
var ordered = M.orderDevices([
  mini("c", "Zeta offline", false, true, false),
  mini("a", "Beta nearby", false, false, true),
  mini("b", "Alpha connected", true, true, true)
])
assert.deepStrictEqual(ordered.map(function (d) { return d.id }), ["b", "a", "c"])

// ---- primary selection precedence ----

var devs = M.orderDevices([
  mini("conn1", "A", true, true, true),
  mini("conn2", "B", true, true, true),
  mini("off1", "C", false, true, false),
  mini("disc1", "D", false, false, true)
])
assert.strictEqual(M.selectPrimaryId(devs, "conn2", ""), "conn2")   // preferred reachable wins
assert.strictEqual(M.selectPrimaryId(devs, "", "conn2"), "conn2")   // last active next
assert.strictEqual(M.selectPrimaryId(devs, "", ""), "conn1")        // any connected
function byId(id) { return devs.filter(function (d) { return d.id === id })[0] }
assert.strictEqual(M.selectPrimaryId([byId("off1"), byId("disc1")], "off1", ""), "off1") // preferred offline
assert.strictEqual(M.selectPrimaryId([byId("disc1")], "", ""), "disc1")   // discovered unpaired
assert.strictEqual(M.selectPrimaryId([], "x", "y"), "")

// ---- snapshot equality ----

assert.ok(M.snapshotEquals([dev], [M.normalizeDevice(dev.id, props, loaded, null)]))
assert.ok(!M.snapshotEquals([dev], [dev2]))

// ---- monitor filter against real captured stream ----

// The fixture contains ONLY self-inflicted traffic: our own method calls and
// the NameOwnerChanged of our own busctl connection. None of it may be dirty.
var filter = M.makeMonitorFilter()
var dirtyCount = 0
fixture("monitor-sample.txt").split("\n").forEach(function (line) {
  if (filter.feed(line)) dirtyCount++
})
assert.strictEqual(dirtyCount, 0)

// Synthetic daemon signal → dirty
var f2 = M.makeMonitorFilter()
assert.strictEqual(f2.feed("‣ Type=signal  Endian=l  Flags=1 ..."), false)
assert.strictEqual(f2.feed("  Sender=:1.30  Path=/modules/kdeconnect/devices/x  Interface=org.kde.kdeconnect.device  Member=reachableChanged"), true)

// PropertiesChanged on a kdeconnect path → dirty
var f3 = M.makeMonitorFilter()
f3.feed("‣ Type=signal ...")
assert.strictEqual(f3.feed("  Sender=:1.30  Path=/modules/kdeconnect/devices/x/battery  Interface=org.freedesktop.DBus.Properties  Member=PropertiesChanged"), true)

// PropertiesChanged elsewhere → clean
var f4 = M.makeMonitorFilter()
f4.feed("‣ Type=signal ...")
assert.strictEqual(f4.feed("  Sender=:1.9  Path=/org/other  Interface=org.freedesktop.DBus.Properties  Member=PropertiesChanged"), false)

// method_call on kdeconnect interface (our own snapshot) → clean
var f5 = M.makeMonitorFilter()
f5.feed("‣ Type=method_call ...")
assert.strictEqual(f5.feed("  Sender=:1.99  Path=/modules/kdeconnect  Interface=org.kde.kdeconnect.daemon  Member=devices"), false)

// NameOwnerChanged for the daemon name → dirty; for others → clean
var f6 = M.makeMonitorFilter()
f6.feed("‣ Type=signal ...")
assert.strictEqual(f6.feed("  Sender=org.freedesktop.DBus  Path=/org/freedesktop/DBus  Interface=org.freedesktop.DBus  Member=NameOwnerChanged"), false)
assert.strictEqual(f6.feed('          STRING "org.kde.kdeconnect";'), true)
var f7 = M.makeMonitorFilter()
f7.feed("‣ Type=signal ...")
f7.feed("  Sender=org.freedesktop.DBus  Path=/org/freedesktop/DBus  Interface=org.freedesktop.DBus  Member=NameOwnerChanged")
assert.strictEqual(f7.feed('          STRING ":1.113";'), false)

console.log("all model tests passed")
