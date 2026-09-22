import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/role_service.dart';

class OfficersListScreen extends StatefulWidget {
  const OfficersListScreen({super.key});

  @override
  State<OfficersListScreen> createState() => _OfficersListScreenState();
}

class _OfficersListScreenState extends State<OfficersListScreen> {
  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _roles = RoleService.globalRoles ?? [];
  }

  @override
  Widget build(BuildContext context) {
    if (_roles.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Officers List')),
        body: const Center(child: Text('No roles found. Please initialize roles first.')),
      );
    }

    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          title: const Text('Officers Directory', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            labelColor: const Color(0xFF0F5132),
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: const Color(0xFF0F5132),
            tabs: _roles.map((r) => Tab(text: r['title'])).toList(),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('authority_users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('No users found.'));
            }

            final users = snapshot.data!.docs.map((doc) {
              var data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;
              return data;
            }).toList();

            return TabBarView(
              children: _roles.map((role) {
                final roleUsers = users.where((u) => u['role'] == role['title']).toList();
                if (roleUsers.isEmpty) {
                  return const Center(child: Text('No users found for this role.', style: TextStyle(color: Color(0xFF64748B))));
                }
                return _buildUsersGrid(roleUsers);
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUsersGrid(List<Map<String, dynamic>> users) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 220,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFDCFCE7),
                radius: 24,
                child: Text(
                  (user['name']?.toString().isNotEmpty == true ? user['name'] : 'U').toString().substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(user['email'] ?? 'No email', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, color: Color(0xFF94A3B8), size: 20),
                onSelected: (val) {
                  if (val == 'edit') {
                    _showEditUserDialog(user);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit User')),
                ],
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(LucideIcons.mapPin, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(child: Text('${user['zone'] ?? 'N/A'} - ${user['ward'] ?? 'N/A'}', style: const TextStyle(color: Color(0xFF475569), fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(LucideIcons.phone, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(child: Text(user['phone'] ?? 'N/A', style: const TextStyle(color: Color(0xFF475569), fontSize: 13))),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: user['status'] == 'Active' ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              user['status'] ?? 'Unknown',
              style: TextStyle(
                color: user['status'] == 'Active' ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        ],
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    final phoneController = TextEditingController(text: user['phone']);
    String selectedRole = user['role'] ?? '';
    String selectedZone = user['zone'] ?? '';
    String selectedWard = user['ward'] ?? '';
    String selectedStatus = user['status'] ?? 'Active';

    if (!_roles.any((r) => r['title'] == selectedRole) && _roles.isNotEmpty) {
      selectedRole = _roles.first['title'];
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: const Text('Edit Officer Details', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        dropdownColor: Colors.white,
                        decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                        value: selectedRole,
                        items: _roles.map((r) => DropdownMenuItem(value: r['title'] as String, child: Text(r['title']))).toList(),
                        onChanged: (val) {
                          if (val != null) setStateDialog(() => selectedRole = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        dropdownColor: Colors.white,
                        decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                        value: selectedStatus,
                        items: const [
                          DropdownMenuItem(value: 'Active', child: Text('Active')),
                          DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                        ],
                        onChanged: (val) {
                          if (val != null) setStateDialog(() => selectedStatus = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: TextEditingController(text: selectedZone),
                        decoration: const InputDecoration(labelText: 'Zone (Optional)', border: OutlineInputBorder()),
                        onChanged: (val) => selectedZone = val,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: TextEditingController(text: selectedWard),
                        decoration: const InputDecoration(labelText: 'Ward (Optional)', border: OutlineInputBorder()),
                        onChanged: (val) => selectedWard = val,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132), foregroundColor: Colors.white),
                  onPressed: () async {
                    try {
                      await FirebaseFirestore.instance.collection('authority_users').doc(user['id']).update({
                        'name': nameController.text.trim(),
                        'email': emailController.text.trim(),
                        'phone': phoneController.text.trim(),
                        'role': selectedRole,
                        'zone': selectedZone,
                        'ward': selectedWard,
                        'status': selectedStatus,
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated successfully')));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating user: $e')));
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
