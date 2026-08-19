import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/models/device_model.dart';
import '../../../data/models/task_model.dart';
import '../../dashboard/presentation/providers/dashboard_providers.dart';

class AddEditDeviceScreen extends ConsumerStatefulWidget {
  final int? deviceId;

  const AddEditDeviceScreen({super.key, this.deviceId});

  @override
  ConsumerState<AddEditDeviceScreen> createState() => _AddEditDeviceScreenState();
}

class _AddEditDeviceScreenState extends ConsumerState<AddEditDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _roomController;
  late TextEditingController _notesController;
  late TextEditingController _serviceInfoController;
  late TextEditingController _warrantyController;
  DateTime? _purchaseDate;
  String? _imagePath;
  
  List<TaskModel> _tasks = [];
  DeviceModel? _existingDevice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _roomController = TextEditingController();
    _notesController = TextEditingController();
    _serviceInfoController = TextEditingController();
    _warrantyController = TextEditingController(text: '24');
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    if (widget.deviceId != null) {
      final isarService = ref.read(isarServiceProvider);
      _existingDevice = await isarService.getDeviceById(widget.deviceId!);
      if (_existingDevice != null) {
        _nameController.text = _existingDevice!.name;
        _roomController.text = _existingDevice!.room;
        _notesController.text = _existingDevice!.notes ?? '';
        _serviceInfoController.text = _existingDevice!.serviceInfo ?? '';
        _warrantyController.text = _existingDevice!.warrantyMonths.toString();
        _purchaseDate = _existingDevice!.purchaseDate;
        _imagePath = _existingDevice!.imagePath;
        
        _tasks = _existingDevice!.tasks.map((t) => TaskModel()
          ..id = t.id
          ..name = t.name
          ..intervalDays = t.intervalDays
          ..lastCompletedAt = t.lastCompletedAt
        ).toList();
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imagePath = pickedFile.path;
      });
    }
  }

  void _addTask() {
    setState(() {
      _tasks.add(TaskModel()..name = ''..intervalDays = 30..lastCompletedAt = DateTime.now());
    });
  }

  void _saveDevice() async {
    if (_formKey.currentState!.validate()) {
      try {
        final isarService = ref.read(isarServiceProvider);
        
        final device = _existingDevice ?? DeviceModel();
        device.name = _nameController.text.trim();
        device.room = _roomController.text.trim();
        device.notes = _notesController.text.trim();
        device.serviceInfo = _serviceInfoController.text.trim();
        device.warrantyMonths = int.tryParse(_warrantyController.text) ?? 24;
        device.purchaseDate = _purchaseDate;
        device.imagePath = _imagePath;

        await isarService.saveDeviceWithTasks(device, _tasks);
        
        if (mounted) {
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kaydedilemedi: $e')),
          );
        }
      }
    }
  }

  Future<void> _selectPurchaseDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _purchaseDate) {
      setState(() {
        _purchaseDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceId == null ? 'Yeni Cihaz Ekle' : 'Cihazı Düzenle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDevice,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 16, 
            right: 16, 
            top: 16, 
            bottom: MediaQuery.of(context).padding.bottom + 100,
          ),
          children: [
            Center(
              child: GestureDetector(
                onTap: () {
                  showModalBottomSheet(context: context, builder: (_) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.camera_alt),
                          title: const Text('Kameradan Çek'),
                          onTap: () {
                            context.pop();
                            _pickImage(ImageSource.camera);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.photo_library),
                          title: const Text('Galeriden Seç'),
                          onTap: () {
                            context.pop();
                            _pickImage(ImageSource.gallery);
                          },
                        ),
                        if (_imagePath != null)
                          ListTile(
                            leading: const Icon(Icons.delete, color: Colors.red),
                            title: const Text('Fotoğrafı Kaldır', style: TextStyle(color: Colors.red)),
                            onTap: () {
                              context.pop();
                              setState(() {
                                _imagePath = null;
                              });
                            },
                          ),
                      ],
                    ),
                  ));
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    image: _imagePath != null ? DecorationImage(
                      image: FileImage(File(_imagePath!)),
                      fit: BoxFit.cover,
                    ) : null,
                  ),
                  child: _imagePath == null 
                    ? const Icon(Icons.add_a_photo, size: 40, color: Colors.grey)
                    : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Cihaz Adı'),
              validator: (val) => val == null || val.isEmpty ? 'Gerekli alan' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _roomController,
              decoration: const InputDecoration(labelText: 'Bulunduğu Oda'),
              validator: (val) => val == null || val.isEmpty ? 'Gerekli alan' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () => _selectPurchaseDate(context),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Satın Alma Tarihi'),
                      child: Text(
                        _purchaseDate == null
                            ? 'Tarih Seçiniz'
                            : DateFormat('dd.MM.yyyy').format(_purchaseDate!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _warrantyController,
                    decoration: const InputDecoration(labelText: 'Garanti (Ay)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _serviceInfoController,
              decoration: const InputDecoration(labelText: 'Yetkili Servis Bilgisi (İletişim vb.)'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notlar (Filtre modeli, seri no vb.)'),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bakım Görevleri', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _addTask,
                  icon: const Icon(Icons.add),
                  label: const Text('Görev Ekle'),
                ),
              ],
            ),
            ..._tasks.asMap().entries.map((entry) {
              int index = entry.key;
              TaskModel task = entry.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: task.name,
                          decoration: const InputDecoration(labelText: 'Görev Adı', isDense: true),
                          onChanged: (val) => task.name = val,
                          validator: (val) => val == null || val.isEmpty ? 'Gerekli' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextFormField(
                          initialValue: task.intervalDays.toString(),
                          decoration: const InputDecoration(labelText: 'Gün', isDense: true),
                          keyboardType: TextInputType.number,
                          onChanged: (val) => task.intervalDays = int.tryParse(val) ?? 30,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _tasks.removeAt(index);
                          });
                        },
                      )
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
