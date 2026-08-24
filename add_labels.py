import re

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

labels_layer = '''                      MarkerLayer(
                        markers: [
                          ..._wards.where((w) => w.boundary.isNotEmpty).map((w) {
                            double cLat = 0, cLng = 0;
                            for (var p in w.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            LatLng centroid = LatLng(cLat / w.boundary.length, cLng / w.boundary.length);
                            return Marker(
                              point: centroid,
                              width: 120, height: 30,
                              child: Center(
                                child: Text(
                                  w.name,
                                  style: const TextStyle(
                                    color: Colors.blue, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 14,
                                    shadows: [
                                      Shadow(offset: Offset(-1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, 1), color: Colors.white),
                                      Shadow(offset: Offset(-1, 1), color: Colors.white),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                          ..._zones.where((z) => z.boundary.isNotEmpty).map((z) {
                            double cLat = 0, cLng = 0;
                            for (var p in z.boundary) { cLat += p.latitude; cLng += p.longitude; }
                            LatLng centroid = LatLng(cLat / z.boundary.length, cLng / z.boundary.length);
                            return Marker(
                              point: centroid,
                              width: 120, height: 30,
                              child: Center(
                                child: Text(
                                  z.name,
                                  style: const TextStyle(
                                    color: Colors.purpleAccent, 
                                    fontWeight: FontWeight.w900, 
                                    fontSize: 16,
                                    shadows: [
                                      Shadow(offset: Offset(-1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, -1), color: Colors.white),
                                      Shadow(offset: Offset(1, 1), color: Colors.white),
                                      Shadow(offset: Offset(-1, 1), color: Colors.white),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),'''

# Insert it right after the PolygonLayer we added previously
polygon_layer_end = '''                              borderColor: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple),
                              borderStrokeWidth: 2,
                            )
                        ],
                      ),'''

if labels_layer not in code:
    code = code.replace(polygon_layer_end, polygon_layer_end + '\\n' + labels_layer)

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Added text labels layer!")
