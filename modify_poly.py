import re

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

old_poly = '''                      if (_drawingPoints.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _drawingPoints,
                              color: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple).withValues(alpha: 0.3),
                              borderColor: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple),
                              borderStrokeWidth: 2,
                            )
                          ],
                        ),'''

new_poly = '''                      PolygonLayer(
                        polygons: [
                          ..._wards.where((w) => w.boundary.isNotEmpty).map((w) => Polygon(
                            points: w.boundary,
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderColor: Colors.blue.withValues(alpha: 0.8),
                            borderStrokeWidth: 2,
                          )),
                          ..._zones.where((z) => z.boundary.isNotEmpty).map((z) => Polygon(
                            points: z.boundary,
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderColor: Colors.purple.withValues(alpha: 0.8),
                            borderStrokeWidth: 2,
                          )),
                          if (_drawingPoints.isNotEmpty)
                            Polygon(
                              points: _drawingPoints,
                              color: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple).withValues(alpha: 0.3),
                              borderColor: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple),
                              borderStrokeWidth: 2,
                            )
                        ],
                      ),'''

code = code.replace(old_poly, new_poly)

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Modified polygons!")
