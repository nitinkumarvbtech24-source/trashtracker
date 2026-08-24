import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\fleet_screen.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add _editingWardId state variable
state_pattern = r'  List<LatLng> _drawingPoints = \[\];'
state_replacement = r'  List<LatLng> _drawingPoints = [];\n  String? _editingWardId;'
if state_pattern in content:
    content = content.replace(state_pattern, state_replacement)
    print("Added _editingWardId")
else:
    print("Could not find state_pattern")

# 2. Update Draw New Ward button logic
draw_btn_pattern = '''            onPressed: () {
              setState(() {
                _selectedVehicle = null;
                _selectedWard = null;
                _currentMode = MapMode.drawWard;
                _drawingPoints.clear();
              });
            },'''
draw_btn_replacement = '''            onPressed: () {
              setState(() {
                _selectedVehicle = null;
                _selectedWard = null;
                _currentMode = MapMode.drawWard;
                _drawingPoints.clear();
                _editingWardId = null;
              });
            },'''
if draw_btn_pattern in content:
    content = content.replace(draw_btn_pattern, draw_btn_replacement)
    print("Updated Draw New Ward logic")
else:
    print("Could not find draw_btn_pattern")

# 3. Add _editWard and _deleteWard methods and update _showNameWardDialog
old_dialog = '''  void _showNameWardDialog() {
    if (_drawingPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A ward must have at least 3 points.')));
      return;
    }

    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: const Text('Save Ward', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Ward Name',
            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final newWard = Ward(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  boundary: List.from(_drawingPoints),
                );
                
                try {
                  await FirebaseFirestore.instance.collection('wards').doc(newWard.id).set(newWard.toJson());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ward saved successfully!')));
                    setState(() {
                      _currentMode = MapMode.view;
                      _drawingPoints.clear();
                      _selectedWard = newWard;
                    });
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Ward: ')));
                }
              }
            },
            child: const Text('Save'),
          )
        ],
      )
    );
  }'''

new_dialog = '''  void _editWard(Ward ward) {
    setState(() {
      _selectedVehicle = null;
      _selectedWard = null;
      _editingWardId = ward.id;
      _currentMode = MapMode.drawWard;
      _drawingPoints = List.from(ward.boundary);
    });
    if (ward.boundary.isNotEmpty) {
      _mapController.move(ward.boundary.first, 14.0);
    }
  }

  void _deleteWard(Ward ward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: const Text('Delete Ward', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete ?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance.collection('wards').doc(ward.id).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ward deleted successfully!')));
                  setState(() {
                    if (_selectedWard?.id == ward.id) _selectedWard = null;
                  });
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete Ward: ')));
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  void _showNameWardDialog() {
    if (_drawingPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A ward must have at least 3 points.')));
      return;
    }

    final nameController = TextEditingController();
    if (_editingWardId != null) {
      final existingWard = _wards.where((w) => w.id == _editingWardId).firstOrNull;
      if (existingWard != null) {
        nameController.text = existingWard.name;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: Text(_editingWardId != null ? 'Update Ward' : 'Save Ward', style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Ward Name',
            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final newWard = Ward(
                  id: _editingWardId ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  boundary: List.from(_drawingPoints),
                );
                
                try {
                  await FirebaseFirestore.instance.collection('wards').doc(newWard.id).set(newWard.toJson());
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_editingWardId != null ? 'Ward updated successfully!' : 'Ward saved successfully!')));
                    setState(() {
                      _currentMode = MapMode.view;
                      _drawingPoints.clear();
                      _selectedWard = newWard;
                      _editingWardId = null;
                    });
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Ward: ')));
                }
              }
            },
            child: Text(_editingWardId != null ? 'Update' : 'Save'),
          )
        ],
      )
    );
  }'''
if old_dialog in content:
    content = content.replace(old_dialog, new_dialog)
    print("Updated _showNameWardDialog")
else:
    print("Could not find _showNameWardDialog")

# 4. Add PopupMenu to Ward item
old_ward_item = '''                                  if (ward.routeDistanceKm == null)
                                    const Text('No optimized route', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),'''

new_ward_item = '''                                  if (ward.routeDistanceKm == null)
                                    const Text('No optimized route', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Color(0xFF94A3B8)),
                              color: const Color(0xFF1E293B),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editWard(ward);
                                } else if (value == 'delete') {
                                  _deleteWard(ward);
                                }
                              },
                              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Edit / Redraw', style: TextStyle(color: Colors.white)),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('Delete Ward', style: TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          ],
                        ),'''
if old_ward_item in content:
    content = content.replace(old_ward_item, new_ward_item)
    print("Updated ward item")
else:
    print("Could not find ward item")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
