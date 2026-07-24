import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class GalleryPickerPage extends StatefulWidget {
  const GalleryPickerPage({super.key});

  @override
  State<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<GalleryPickerPage> {
  List<AssetEntity> _assets = [];
  final _selectedIds = <String>{};
  final _thumbData = <String, Uint8List?>{};
  bool _loading = true;
  bool _denied = false;
  AssetPathEntity? _album;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!state.hasAccess) {
      if (mounted) setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
    );
    if (albums.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _album = albums.first;
    final count = await _album!.assetCountAsync;
    final all = await _album!.getAssetListPaged(page: 0, size: count);
    all.sort((a, b) {
      final da = a.createDateSecond ?? 0;
      final db = b.createDateSecond ?? 0;
      return db.compareTo(da);
    });
    _assets = all;
    for (final asset in all) {
      _loadThumb(asset);
    }

    _loading = false;
    if (mounted) setState(() {});
  }

  Future<void> _loadThumb(AssetEntity asset) async {
    final data = await asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
      quality: 70,
    );
    if (mounted) setState(() => _thumbData[asset.id] = data);
  }

  void _done() {
    if (_selectedIds.isEmpty) return;
    final selected =
        _assets.where((a) => _selectedIds.contains(a.id)).toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _loading
          ? null
          : AppBar(
              backgroundColor: Colors.grey[900],
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(null),
              ),
              title: Text(
                _selectedIds.isEmpty
                    ? 'Select Photos'
                    : '${_selectedIds.length} selected',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                if (_selectedIds.isNotEmpty)
                  TextButton(
                    onPressed: _done,
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _denied
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          color: Colors.white38, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Photo access denied',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ],
                  ),
                )
              : _assets.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_outlined,
                              color: Colors.white38, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'No photos found',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                        padding: const EdgeInsets.all(2),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                        itemCount: _assets.length,
                        itemBuilder: (context, index) {
                          return _buildItem(_assets[index]);
                        },
                      ),
    );
  }

  Widget _buildItem(AssetEntity asset) {
    final isSelected = _selectedIds.contains(asset.id);
    final thumb = _thumbData[asset.id];

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(asset.id);
          } else {
            _selectedIds.add(asset.id);
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumb != null
              ? Image.memory(thumb, fit: BoxFit.cover)
              : Container(color: Colors.grey[850]),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.blue : Colors.black38,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: Container(color: Colors.blue.withValues(alpha: 0.15)),
            ),
        ],
      ),
    );
  }
}
