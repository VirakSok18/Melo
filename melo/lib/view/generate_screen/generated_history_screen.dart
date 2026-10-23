import 'package:flutter/material.dart';
import '../../services/generated_history_service.dart';
import '../../widgets/cached_image.dart';
import 'generated_playlist_screen.dart';

class GeneratedHistoryScreen extends StatefulWidget {
  final ValueChanged<ChatSession>? onRestoreSession;

  const GeneratedHistoryScreen({super.key, this.onRestoreSession});

  @override
  State<GeneratedHistoryScreen> createState() => _GeneratedHistoryScreenState();
}

class _GeneratedHistoryScreenState extends State<GeneratedHistoryScreen> {
  static const Color _accent = Color(0xFF514AED);
  int _selectedTab = 0; // 0 = Playlists, 1 = Chat History

  @override
  void initState() {
    super.initState();
    GeneratedHistoryService.init();
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _confirmClearCurrentTab() {
    final isChatTab = _selectedTab == 1;
    final titleText = isChatTab ? 'Clear Chat History' : 'Clear Playlists';
    final msgText = isChatTab
        ? 'Are you sure you want to clear all your saved chat conversations?'
        : 'Are you sure you want to clear your generated playlist history?';
    final successToast =
        isChatTab ? 'Chat history cleared' : 'Generated playlists cleared';

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF18181D),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                msgText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (isChatTab) {
                            GeneratedHistoryService.clearAllChatSessions();
                          } else {
                            GeneratedHistoryService.clearAll();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(successToast),
                              backgroundColor: const Color(0xFF333333),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                        ),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverArt(List<Map<String, dynamic>> songs) {
    final images = songs
        .map((s) => s['image']?.toString() ?? '')
        .where((img) => img.isNotEmpty)
        .take(4)
        .toList();

    if (images.isEmpty) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          color: _accent,
          size: 24,
        ),
      );
    }

    if (images.length < 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedImage(
          images.first,
          width: 54,
          height: 54,
          fit: BoxFit.cover,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 54,
        height: 54,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CachedImage(
                      images[0],
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: CachedImage(
                      images[1],
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: CachedImage(
                      images[2],
                      fit: BoxFit.cover,
                    ),
                  ),
                  Expanded(
                    child: CachedImage(
                      images[3],
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      appBar: AppBar(
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Generation History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            fontFamily: 'Poppins',
          ),
        ),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: GeneratedHistoryService.onUpdate,
            builder: (context, _, __) {
              final hasItems = _selectedTab == 0
                  ? GeneratedHistoryService.history.isNotEmpty
                  : GeneratedHistoryService.chatSessions.isNotEmpty;
              if (!hasItems) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.white70, size: 22),
                tooltip: _selectedTab == 0
                    ? 'Clear playlists'
                    : 'Clear chat history',
                onPressed: _confirmClearCurrentTab,
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: GeneratedHistoryService.onUpdate,
        builder: (context, _, __) {
          final history = GeneratedHistoryService.history;
          final chatSessions = GeneratedHistoryService.chatSessions;

          return Column(
            children: [
              // Segmented Tab Selector
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222226),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0
                                  ? const Color(0xFF33333A)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text(
                                'Playlists (${history.length})',
                                style: TextStyle(
                                  color: _selectedTab == 0
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 12.5,
                                  fontWeight: _selectedTab == 0
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1
                                  ? const Color(0xFF33333A)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text(
                                'Chat History (${chatSessions.length})',
                                style: TextStyle(
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : Colors.white54,
                                  fontSize: 12.5,
                                  fontWeight: _selectedTab == 1
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Tab Content
              Expanded(
                child: _selectedTab == 0
                    ? _buildPlaylistsTab(history)
                    : _buildChatHistoryTab(chatSessions),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlaylistsTab(List<GeneratedHistoryItem> history) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.queue_music_rounded,
                color: Colors.white.withValues(alpha: 0.3),
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'No generated playlists',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Playlists you generate will appear here for 7 days.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];

        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFFF5252),
              size: 22,
            ),
          ),
          onDismissed: (_) {
            GeneratedHistoryService.deleteHistory(item.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${item.title}"'),
                backgroundColor: const Color(0xFF2A2A2A),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GeneratedPlaylistScreen(
                      mood: item.mood,
                      title: item.title,
                      description: item.description,
                      songs: item.songs,
                      historyId: item.id,
                      savedPlaylistId: item.savedPlaylistId,
                    ),
                  ),
                );
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    _buildCoverArt(item.songs),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Poppins',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${item.songs.length} songs · ${_formatTimeAgo(item.createdAt)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontFamily: 'Poppins',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.savedPlaylistId != null &&
                              item.savedPlaylistId!.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Text(
                                'In Library',
                                style: TextStyle(
                                  color: Color(0xFF9B96FF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 20,
                      ),
                      onPressed: () => _showPlaylistItemOptions(context, item),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPlaylistItemOptions(
      BuildContext context, GeneratedHistoryItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.play_arrow_rounded, color: Colors.white),
                title: const Text('Open Playlist',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GeneratedPlaylistScreen(
                        mood: item.mood,
                        title: item.title,
                        description: item.description,
                        songs: item.songs,
                        historyId: item.id,
                        savedPlaylistId: item.savedPlaylistId,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF5252)),
                title: const Text('Delete',
                    style: TextStyle(
                        color: Color(0xFFFF5252), fontFamily: 'Poppins')),
                onTap: () {
                  Navigator.pop(ctx);
                  GeneratedHistoryService.deleteHistory(item.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatHistoryTab(List<ChatSession> sessions) {
    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white.withValues(alpha: 0.3),
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'No chat history',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Past conversations will appear here so you can continue them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  fontFamily: 'Poppins',
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];

        return Dismissible(
          key: ValueKey(session.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFFF5252),
              size: 22,
            ),
          ),
          onDismissed: (_) {
            GeneratedHistoryService.deleteChatSession(session.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed chat "${session.title}"'),
                backgroundColor: const Color(0xFF2A2A2A),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                widget.onRestoreSession?.call(session);
                Navigator.pop(context);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'Poppins',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${session.messageCount} messages · ${_formatTimeAgo(session.createdAt)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11.5,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 19,
                      ),
                      onPressed: () {
                        GeneratedHistoryService.deleteChatSession(session.id);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
