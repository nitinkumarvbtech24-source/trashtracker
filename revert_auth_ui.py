import os
import re

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove health UI block
health_ui_block = '''                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showAddLinkDialog,
                        icon: const Icon(Icons.add_link_rounded, color: Colors.greenAccent),
                        label: const Text('Add Garbage Link', style: TextStyle(color: Colors.greenAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.greenAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Active Road Health AI Tunnel', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 8),
                    if (_savedHealthLinks.isNotEmpty)
                      DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF1E293B),
                        value: _selectedHealthLinkKey,
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                        items: _savedHealthLinks.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(' ()', overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _saveHealthLinksAndSet(val, _savedHealthLinks[val]!);
                          }
                        },
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showAddHealthLinkDialog,
                        icon: const Icon(Icons.add_link_rounded, color: Colors.greenAccent),
                        label: const Text('Add Health Link', style: TextStyle(color: Colors.greenAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.greenAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),'''

target = '''                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showAddLinkDialog,
                        icon: const Icon(Icons.add_link_rounded, color: Colors.greenAccent),
                        label: const Text('Add New Link', style: TextStyle(color: Colors.greenAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.greenAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),'''
content = content.replace(health_ui_block, target)

# 2. Fix the label
ui_old = '''                    Text('Active Garbage AI Tunnel', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),'''
ui_new = '''                    Text('Active Tunnel Server', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),'''
content = content.replace(ui_old, ui_new)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
