import 'package:flutter/material.dart';

import '../../domain/models/stream_option.dart';
import '../controllers/download_folders_controller.dart';

/// Hoja de ajustes: carpetas de descarga de video y audio.
Future<void> showSettingsSheet(BuildContext context, {required DownloadFoldersController folders}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141E),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SettingsSheet(folders: folders),
  );
}

class _SettingsSheet extends StatelessWidget {
  final DownloadFoldersController folders;

  const _SettingsSheet({required this.folders});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Ajustes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 20),
            SettingsSection(
              title: 'Carpetas de descarga',
              children: [
                for (final type in const [StreamType.audioOnly, StreamType.video])
                  ListenableBuilder(
                    listenable: folders,
                    builder: (context, _) => _FolderRow(type: type, folders: folders),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grupo de filas con título, como en los ajustes del sistema.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SettingsSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFFA855F7),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Icono con fondo tonal de las filas de ajustes.
class SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const SettingsIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final StreamType type;
  final DownloadFoldersController folders;

  const _FolderRow({required this.type, required this.folders});

  @override
  Widget build(BuildContext context) {
    final isAudio = type == StreamType.audioOnly;
    final destination = folders.of(type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          SettingsIcon(
            icon: isAudio ? Icons.music_note_rounded : Icons.videocam_rounded,
            color: isAudio ? const Color(0xFF34D399) : const Color(0xFF818CF8),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAudio ? 'Carpeta de audio' : 'Carpeta de video',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  destination?.displayPath ?? '…',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF94A3B8)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir carpeta',
            icon: const Icon(Icons.open_in_new_rounded, size: 20, color: Color(0xFF94A3B8)),
            onPressed: destination == null ? null : () => _open(context),
          ),
          IconButton(
            tooltip: 'Cambiar carpeta',
            icon: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFFA855F7)),
            onPressed: destination == null ? null : () => folders.pick(type),
          ),
          if (destination != null && !folders.isDefault(type))
            IconButton(
              tooltip: 'Usar la carpeta predeterminada',
              icon: const Icon(Icons.restore_rounded, size: 20, color: Color(0xFF94A3B8)),
              onPressed: () => folders.reset(type),
            ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await folders.open(type)) {
      messenger.showSnackBar(const SnackBar(content: Text('No se encontró un explorador de archivos compatible.')));
    }
  }
}
