import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../data/models/device_model.dart';
import '../../data/models/settings_model.dart';

class GithubService {
  final String owner = 'ovarthy-bot';
  final String repo = 'homecare';
  
  Future<void> syncDeviceToGithub(DeviceModel device, SettingsModel settings) async {
    final token = settings.githubToken;
    if (token == null || token.isEmpty) return;

    final path = 'docs/data/device_${device.id}.json';
    final url = Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path');
    
    // Convert device to JSON
    final Map<String, dynamic> data = {
      'id': device.id,
      'name': device.name,
      'room': device.room,
      'warranty': device.warrantyMonths,
    };
    if (device.purchaseDate != null) {
      data['purchaseDate'] = device.purchaseDate!.toIso8601String();
    }
    if (device.serviceInfo != null && device.serviceInfo!.isNotEmpty) {
      data['serviceInfo'] = device.serviceInfo;
    }
    if (device.notes != null && device.notes!.isNotEmpty) {
      data['notes'] = device.notes;
    }
    if (device.tasks.isNotEmpty) {
      data['tasks'] = device.tasks.map((t) => {
        'name': t.name,
        'intervalDays': t.intervalDays,
      }).toList();
    }
    
    final jsonString = jsonEncode(data);
    final base64Content = base64Encode(utf8.encode(jsonString));

    try {
      // 1. Check if file exists to get its SHA
      String? sha;
      final getResponse = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (getResponse.statusCode == 200) {
        final getBody = jsonDecode(getResponse.body);
        sha = getBody['sha'];
      }

      // 2. Create or Update file
      final body = {
        'message': 'Sync device ${device.id}',
        'content': base64Content,
      };
      
      if (sha != null) {
        body['sha'] = sha;
      }

      await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      // Fail silently for background sync
      print('GitHub sync failed: $e');
    }
  }

  Future<void> deleteDeviceFromGithub(int deviceId, SettingsModel settings) async {
    final token = settings.githubToken;
    if (token == null || token.isEmpty) return;

    final path = 'docs/data/device_$deviceId.json';
    final url = Uri.parse('https://api.github.com/repos/$owner/$repo/contents/$path');

    try {
      // 1. Get SHA
      final getResponse = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (getResponse.statusCode == 200) {
        final getBody = jsonDecode(getResponse.body);
        final sha = getBody['sha'];

        // 2. Delete file
        await http.delete(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/vnd.github.v3+json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'message': 'Delete device $deviceId',
            'sha': sha,
          }),
        );
      }
    } catch (e) {
      print('GitHub delete failed: $e');
    }
  }
}
