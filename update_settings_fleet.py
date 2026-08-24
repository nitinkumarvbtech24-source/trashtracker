import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_Fleet app\lib\ui\settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add state variables
state_vars_old = '''  String _appVersion = 'Loading...';
  Map<String, String> _savedLinks = {};
  String? _selectedLinkKey;'''
state_vars_new = '''  String _appVersion = 'Loading...';
  Map<String, String> _savedLinks = {};
  String? _selectedLinkKey;
  Map<String, String> _savedHealthLinks = {};
  String? _selectedHealthLinkKey;'''
content = content.replace(state_vars_old, state_vars_new)

# 2. Add to initState
init_old = '''    _initPackageInfo();
    _loadSavedLinks();
  }'''
init_new = '''    _initPackageInfo();
    _loadSavedLinks();
    _loadSavedHealthLinks();
  }'''
content = content.replace(init_old, init_new)

# 3. Add health link methods after _showAddLinkDialog()
# Let's find the end of _showAddLinkDialog() 
target_str = '''              TextButton(
                onPressed: () {
                  String name = nameController.text.trim();
                  String url = urlController.text.trim();
                  if (name.isNotEmpty && url.isNotEmpty) {
                    if (!url.startsWith('http://') && !url.startsWith('https://')) {
                      url = 'https://' + url;
                    }
                    _saveLinksAndSet(name, url);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add', style: TextStyle(color: Colors.greenAccent)),
              ),
            ],
          );
        },
      );
    }'''

health_methods = '''

  Future<void> _loadSavedHealthLinks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? linksJson = prefs.getString('saved_tunnels_health');
    
    Map<String, String> links = {};
    if (linksJson != null && linksJson.isNotEmpty) {
      links = Map<String, String>.from(json.decode(linksJson));
    }
    
    if (links.isEmpty) {
      links['Default Ngrok'] = HEALTH_AI_URL;
    }
    
    String activeUrl = HEALTH_AI_URL;
    String? activeKey;
    
    links.forEach((key, value) {
      if (value == activeUrl) {
        activeKey = key;
      }
    });
    
    if (activeKey == null) {
      activeKey = 'Custom Local';
      links[activeKey!] = activeUrl;
    }

    setState(() {
      _savedHealthLinks = links;
      _selectedHealthLinkKey = activeKey;
    });
  }

  Future<void> _saveHealthLinksAndSet(String name, String url) async {
    final prefs = await SharedPreferences.getInstance();
    _savedHealthLinks[name] = url;
    await prefs.setString('saved_tunnels_health', json.encode(_savedHealthLinks));
    await prefs.setString('health_ai_url', url);
    HEALTH_AI_URL = url;
    
    setState(() {
      _selectedHealthLinkKey = name;
    });
  }

  void _showAddHealthLinkDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Add Health Tunnel Link', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Link Name (e.g. WiFi 1)', labelStyle: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'URL', labelStyle: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                String name = nameController.text.trim();
                String url = urlController.text.trim();
                if (name.isNotEmpty && url.isNotEmpty) {
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://' + url;
                  }
                  _saveHealthLinksAndSet(name, url);
                  Navigator.pop(context);
                }
              },
              child: const Text('Add', style: TextStyle(color: Colors.greenAccent)),
            ),
          ],
        );
      },
    );
  }
'''
content = content.replace(target_str, target_str + health_methods)

# 4. UI changes
ui_old = '''                      Text('Active Tunnel Server', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),'''
ui_new = '''                      Text('Active Garbage AI Tunnel', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),'''
content = content.replace(ui_old, ui_new)

add_link_old = '''                      SizedBox(
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

health_ui_block = '''                      SizedBox(
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
content = content.replace(add_link_old, health_ui_block)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fleet App Settings UI overhauled")
