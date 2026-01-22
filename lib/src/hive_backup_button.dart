import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart' as material;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

class HiveBackupButton extends StatefulWidget {
  const HiveBackupButton({
    super.key,
    required this.permission,

    /// folder where backups will be written
    this.backupPath = '/storage/emulated/0/makeit_app_backup',

    /// Provide ALL files you want to backup (Hive + Drift + anything else)
    required this.getBackupFiles,

    /// Called before copying files (close drift db, close hive boxes, etc.)
    required this.prepareForBackup,

    /// Called after copying files (re-open db, re-open boxes, reconnect locator etc.)
    required this.afterBackup,
  });
  final Future<bool> permission;
  final String backupPath;

  final Future<List<File>> Function() getBackupFiles;
  final Future<void> Function() prepareForBackup;
  final Future<void> Function() afterBackup;

  @override
  State<HiveBackupButton> createState() => _HiveBackupButtonState();
}

class _HiveBackupButtonState extends State<HiveBackupButton> {
  Future<void> _copyIfExists(File src, String dstPath) async {
    if (await src.exists()) {
      final dst = File(dstPath);
      if (await dst.exists()) await dst.delete();
      await src.copy(dst.path);
    }
  }

  Future<void> backupDatabase() async {
    if (!await widget.permission) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        const SnackBar(content: Text('Permission denied for backup!')),
      );
      return;
    }
    Get.defaultDialog(
      title: "Data Backup Alert",
      middleText: "Do you want to Backup the App Data?",
      textConfirm: "Yes",
      textCancel: "No",
      confirm: material.FilledButton(
        onPressed: () async {
          try {
            // Permission
            if (!await Permission.manageExternalStorage.request().isGranted) {
              ScaffoldMessenger.of(Get.context!).showSnackBar(
                const SnackBar(content: Text('Storage permission not granted')),
              );
              Get.back();
              return;
            }

            final backupDir = Directory(widget.backupPath);

            // -------------------- (A) HIVE BACKUP (your existing folder copy) --------------------
          
            String hivePath = (await getApplicationSupportDirectory()).path;

            final Directory hiveDir = Directory(hivePath);
            if (await Permission.manageExternalStorage.request().isGranted) {
              if (await hiveDir.exists()) {
                if (!await backupDir.exists()) {
                  await backupDir.create(recursive: true);
                }

                // Get all files in the backup directory
                List<FileSystemEntity> backupFiles = hiveDir.listSync();

                // Copy each file from backup to the Hive directory
                for (FileSystemEntity entity in backupFiles) {
                  if (entity is File) {
                    final String fileName = entity.uri.pathSegments.last;
                    final File destinationFile = File('${widget.backupPath}/$fileName');
                    if (await destinationFile.exists()) {
                      await destinationFile
                          .delete(); // Remove the old file if necessary
                    }
                    await entity.copy(destinationFile.path);
                  }
                }
              }
            }

            // -------------------- (B) DRIFT BACKUP (SQLite + wal/shm) --------------------

            // Ensure backup folder exists
            if (!await backupDir.exists()) {
              await backupDir.create(recursive: true);
            }

            // Close DB/boxes etc (main app defines this)
            await widget.prepareForBackup();

            // Ask main app for list of files to back up
            final files = await widget.getBackupFiles();

            // Copy files
            for (final file in files) {
              final name = p.basename(file.path);
              await _copyIfExists(file, p.join(widget.backupPath, name));
            }

            // Reopen / reconnect (main app defines this)
            await widget.afterBackup();

            ScaffoldMessenger.of(Get.context!).showSnackBar(
              const SnackBar(content: Text('Backup completed successfully!')),
            );
          } catch (e) {
            // Try to recover by calling afterBackup
            try {
              await widget.afterBackup();
            } catch (_) {}

            ScaffoldMessenger.of(Get.context!).showSnackBar(
              SnackBar(content: Text('Backup failed: $e')),
            );
          } finally {
            Get.back();
          }
        },
        child: const material.Text('Yes'),
      ),
      cancel: material.FilledButton(
        onPressed: () {
          Get.back();
        },
        child: const material.Text('No'),
      ),
      backgroundColor: Get.theme.colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        await backupDatabase();
      },
      child: const Text("Backup Data",
          style: TextStyle(color: Colors.black, fontSize: 19)),
    );
  }
}