import os

file_path = r'e:\vc code\.vscode\trash tracker\AIQ_authority app\lib\screens\settings_screen.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '  @override\n  Widget build(BuildContext context) {'

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
                decoration: const InputDecoration(labelText: 'Link Name', labelStyle: TextStyle(color: Colors.white54)),
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
                    url = 'https://';
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

content = content.replace(target, health_methods + target)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Authority App fixed")
