import QtQuick

// 1991 Volvo 960 sedan, side view, drawn on the same square-block grid the
// Omarchy logo uses. Front faces left: long flat hood, upright glasshouse,
// flat trunk, black side molding.
//
// Legend: # body · s side molding · o tyre · L headlight · T tail light
Canvas {
  id: root

  property bool mini: false
  property int pixel: 4
  property color bodyColor: "white"
  property color stripColor: Qt.darker(bodyColor, 1.8)
  property color lightColor: bodyColor
  property color tailColor: bodyColor
  property bool lightsOn: false

  readonly property var sedan: [
    "..................#################.............",
    ".................##......##.......##............",
    "................##.......##........##...........",
    "...............##........##.........##..........",
    ".##############################################.",
    "LL############################################TT",
    "LL############################################TT",
    "#ssssssssssssssssssssssssssssssssssssssssssssss#",
    "################################################",
    "#####........####################........#######",
    "#####..oooo..####################..oooo..#######",
    "......oo..oo......................oo..oo........",
    "......oo..oo......................oo..oo........",
    ".......oooo........................oooo........."
  ]

  readonly property var badge: [
    "......########......",
    ".....##..##..##.....",
    "L##################T",
    "####################",
    "##.oo.########.oo.##",
    "..oooo........oooo..",
    "...oo..........oo..."
  ]

  readonly property var grid: mini ? badge : sedan
  readonly property int columns: grid[0].length
  readonly property int rows: grid.length

  implicitWidth: columns * pixel
  implicitHeight: rows * pixel
  width: implicitWidth
  height: implicitHeight

  function colorFor(ch) {
    switch (ch) {
    case "#": return root.bodyColor
    case "s": return root.stripColor
    case "o": return root.bodyColor
    case "L": return root.lightsOn ? root.lightColor : root.stripColor
    case "T": return root.lightsOn ? root.tailColor : root.stripColor
    default: return null
    }
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    for (var y = 0; y < rows; y++) {
      var line = grid[y]
      for (var x = 0; x < line.length; x++) {
        var c = colorFor(line.charAt(x))
        if (c === null) continue
        ctx.fillStyle = c
        ctx.fillRect(x * pixel, y * pixel, pixel, pixel)
      }
    }
  }

  onBodyColorChanged: requestPaint()
  onStripColorChanged: requestPaint()
  onLightColorChanged: requestPaint()
  onTailColorChanged: requestPaint()
  onLightsOnChanged: requestPaint()
  onPixelChanged: requestPaint()
  onMiniChanged: requestPaint()
}
