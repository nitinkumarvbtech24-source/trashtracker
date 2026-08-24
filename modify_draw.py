import re

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Add enum MapMode right above class FleetScreen
if 'enum MapMode' not in code:
    code = code.replace('class FleetScreen extends StatefulWidget', 'enum MapMode { view, drawWard, drawZone }\n\nclass FleetScreen extends StatefulWidget')

# 2. Add state variables inside _FleetScreenState
state_vars = '''
  MapMode _currentMode = MapMode.view;
  List<LatLng> _drawingPoints = [];
  String? _editingWardId;
  String? _editingZoneId;
  Ward? _selectedWard;
  Zone? _selectedZone;
'''
if '_currentMode' not in code:
    code = code.replace('  int _bottomNavIndex = 0;', state_vars + '\n  int _bottomNavIndex = 0;')

# 3. Add onTap to MapOptions
on_tap_code = '''
                      onTap: (tapPosition, point) {
                        if (_currentMode != MapMode.view) {
                          setState(() => _drawingPoints.add(point));
                        }
                      },
'''
code = code.replace('initialZoom: 12.0,\n                    ),', 'initialZoom: 12.0,\n' + on_tap_code + '                    ),')

# 4. Add PolygonLayer and MarkerLayer
drawing_layers = '''
                      if (_drawingPoints.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _drawingPoints,
                              color: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple).withValues(alpha: 0.3),
                              borderColor: (_currentMode == MapMode.drawWard ? Colors.blue : Colors.purple),
                              borderStrokeWidth: 2,
                            )
                          ],
                        ),
                      if (_drawingPoints.isNotEmpty)
                        MarkerLayer(
                          markers: _drawingPoints.map((p) => Marker(
                            point: p,
                            width: 10, height: 10,
                            child: const CircleAvatar(backgroundColor: Colors.red, radius: 5),
                          )).toList(),
                        ),
'''
code = code.replace('MarkerLayer(markers: _buildCustomMarkers()),\n                    ],', 'MarkerLayer(markers: _buildCustomMarkers()),\n' + drawing_layers + '                    ],')

# 5. Replace buttons
old_buttons_regex = r"Container\(\s*padding: const EdgeInsets\.symmetric\(horizontal: 12, vertical: 6\),\s*decoration: BoxDecoration\(border: Border\.all\(color: const Color\(0xFFE5E7EB\)\), borderRadius: BorderRadius\.circular\(6\)\),\s*child: Row\(children: \[Text\('All Zones', style: GoogleFonts\.inter\(fontSize: 12\)\), const SizedBox\(width: 16\), const Icon\(Icons\.keyboard_arrow_down, size: 16\)\]\),\s*\),\s*const SizedBox\(width: 12\),\s*Container\(\s*padding: const EdgeInsets\.symmetric\(horizontal: 12, vertical: 6\),\s*decoration: BoxDecoration\(border: Border\.all\(color: const Color\(0xFFE5E7EB\)\), borderRadius: BorderRadius\.circular\(6\)\),\s*child: Row\(children: \[Text\('Live Traffic', style: GoogleFonts\.inter\(fontSize: 12\)\), const SizedBox\(width: 16\), const Icon\(Icons\.keyboard_arrow_down, size: 16\)\]\),\s*\),\s*const SizedBox\(width: 12\),"

new_buttons = '''
                    if (_currentMode != MapMode.view) ...[
                      ElevatedButton(
                        onPressed: () => setState(() { _currentMode = MapMode.view; _drawingPoints.clear(); }),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _currentMode == MapMode.drawWard ? _showNameWardDialog : _showNameZoneDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132)),
                        child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                    ] else ...[
                      InkWell(
                        onTap: () => setState(() { _currentMode = MapMode.drawWard; _drawingPoints.clear(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
                          child: Text('Draw Ward', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => setState(() { _currentMode = MapMode.drawZone; _drawingPoints.clear(); }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
                          child: Text('Draw Zone', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0F5132))),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
'''
code = re.sub(old_buttons_regex, new_buttons, code)

# 6. Append the dialog methods before the last closing brace
with open('extracted_methods.txt', 'r', encoding='utf-8') as f:
    dialog_methods = f.read()

# Make sure we don't duplicate
if '_showNameWardDialog' not in code:
    last_brace_index = code.rfind('}')
    code = code[:last_brace_index] + dialog_methods + '\n' + code[last_brace_index:]

with open('AIQ_authority app/lib/screens/fleet_screen.dart', 'w', encoding='utf-8') as f:
    f.write(code)

print("Modifications done!")
