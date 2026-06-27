import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final double aspectRatio;
  final int maxDimension;

  const CropDialog({
    super.key,
    required this.imageBytes,
    required this.aspectRatio,
    this.maxDimension = 1024,
  });

  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required double aspectRatio,
    int maxDimension = 1024,
  }) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CropDialog(
          imageBytes: imageBytes,
          aspectRatio: aspectRatio,
          maxDimension: maxDimension,
        ),
      ),
    );
  }

  @override
  State<CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<CropDialog> {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _cropKey = GlobalKey();
  ui.Image? _image;
  Size _imageSize = Size.zero;
  Size _cropViewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    _image = frame.image;
    _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final m = _transformController.value;
    final s = m.getMaxScaleOnAxis();
    if (s <= 0 || !s.isFinite) return;
    final ns = (s * 1.4).clamp(1.0, 20.0);
    if (ns == s) return;
    _applyZoom(m, s, ns);
  }

  void _zoomOut() {
    final m = _transformController.value;
    final s = m.getMaxScaleOnAxis();
    if (s <= 0 || !s.isFinite) return;
    final ns = (s / 1.4).clamp(1.0, 20.0);
    if (ns == s) return;
    _applyZoom(m, s, ns);
  }

  void _applyZoom(Matrix4 current, double oldScale, double newScale) {
    final ratio = newScale / oldScale;
    final cx = _cropViewport.width / 2;
    final cy = _cropViewport.height / 2;
    _transformController.value =
        Matrix4(
          ratio,
          0,
          0,
          0,
          0,
          ratio,
          0,
          0,
          0,
          0,
          1,
          0,
          cx * (1 - ratio),
          cy * (1 - ratio),
          0,
          1,
        ) *
        current;
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  Rect _cropRect(Size viewport) {
    if (_imageSize == Size.zero || viewport == Size.zero) return Rect.zero;

    // BoxFit.contain: scale the image to fit within the viewport
    final s = min(viewport.width / _imageSize.width, viewport.height / _imageSize.height);
    final ox = (viewport.width - _imageSize.width * s) / 2;
    final oy = (viewport.height - _imageSize.height * s) / 2;

    // Manual 2D affine inverse of the zoom/pan transform
    final m = _transformController.value;
    final a = m.entry(0, 0);
    final b = m.entry(0, 1);
    final tx = m.entry(0, 3);
    final c = m.entry(1, 0);
    final d = m.entry(1, 1);
    final ty = m.entry(1, 3);
    final det = a * d - b * c;
    if (det.abs() < 1e-10) return Rect.zero;

    final invDet = 1.0 / det;
    final invA = d * invDet;
    final invB = -b * invDet;
    final invC = -c * invDet;
    final invD = a * invDet;
    final invTx = (b * ty - d * tx) * invDet;
    final invTy = (c * tx - a * ty) * invDet;

    // Map viewport corners -> child space via inverse transform
    final tlX = invTx;
    final tlY = invTy;
    final brX = invA * viewport.width + invB * viewport.height + invTx;
    final brY = invC * viewport.width + invD * viewport.height + invTy;

    // Map child space -> image space (undo BoxFit.contain)
    final left = (tlX - ox) / s;
    final top = (tlY - oy) / s;
    final right = (brX - ox) / s;
    final bottom = (brY - oy) / s;

    return Rect.fromLTRB(
      left.clamp(0, _imageSize.width),
      top.clamp(0, _imageSize.height),
      right.clamp(0, _imageSize.width),
      bottom.clamp(0, _imageSize.height),
    );
  }

  Future<Uint8List> _crop(Size viewport) async {
    final rect = _cropRect(viewport);

    final isGif =
        widget.imageBytes.length >= 6 &&
        widget.imageBytes[0] == 0x47 &&
        widget.imageBytes[1] == 0x49 &&
        widget.imageBytes[2] == 0x46 &&
        widget.imageBytes[3] == 0x38;

    if (isGif) {
      return _cropGif(rect);
    }

    final original = img.decodeImage(widget.imageBytes);
    if (original == null) {
      throw Exception('Failed to decode image');
    }

    final x = rect.left.round().clamp(0, original.width - 1);
    final y = rect.top.round().clamp(0, original.height - 1);
    final w = rect.width.round().clamp(1, original.width - x);
    final h = rect.height.round().clamp(1, original.height - y);

    final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);
    final maxDim = widget.maxDimension;
    final resized = cropped.width > cropped.height
        ? img.copyResize(cropped, width: min(cropped.width, maxDim))
        : img.copyResize(cropped, height: min(cropped.height, maxDim));

    return Uint8List.fromList(img.encodePng(resized));
  }

  Future<Uint8List> _cropGif(Rect rect) async {
    final original = img.decodeGif(widget.imageBytes);
    if (original == null) {
      throw Exception('Failed to decode GIF');
    }

    final x = rect.left.round().clamp(0, original.width - 1);
    final y = rect.top.round().clamp(0, original.height - 1);
    final w = rect.width.round().clamp(1, original.width - x);
    final h = rect.height.round().clamp(1, original.height - y);

    final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);
    final maxDim = widget.maxDimension;
    final resized = cropped.width > cropped.height
        ? img.copyResize(cropped, width: min(cropped.width, maxDim))
        : img.copyResize(cropped, height: min(cropped.height, maxDim));

    // copyCrop/copyResize don't preserve per-frame durations
    if (original.hasAnimation && resized.hasAnimation) {
      final srcFrames = original.frames;
      final dstFrames = resized.frames;
      for (var i = 0; i < dstFrames.length && i < srcFrames.length; i++) {
        dstFrames[i].frameDuration = srcFrames[i].frameDuration;
      }
      resized.loopCount = original.loopCount;
    }

    return Uint8List.fromList(img.encodeGif(resized));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.aspectRatio == 1.0 ? 'Crop Avatar' : 'Crop Banner',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _image == null ? null : () => _onCrop(),
            child: const Text('Crop', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                var cropW = constraints.maxWidth - 32;
                var cropH = cropW / widget.aspectRatio;
                if (cropH > constraints.maxHeight - 140) {
                  cropH = constraints.maxHeight - 140;
                  cropW = cropH * widget.aspectRatio;
                }
                _cropViewport = Size(cropW, cropH);

                return Stack(
                  children: [
                    Center(
                      child: Container(
                        key: _cropKey,
                        width: cropW,
                        height: cropH,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 1.0,
                          maxScale: 20.0,
                          child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlayPainter(
                            cropRect: Rect.fromLTWH(
                              (constraints.maxWidth - cropW) / 2,
                              (constraints.maxHeight - cropH) / 2,
                              cropW,
                              cropH,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _zoomButton(Icons.add, _zoomIn),
                          const SizedBox(height: 8),
                          _zoomButton(Icons.remove, _zoomOut),
                          const SizedBox(height: 8),
                          _zoomButton(Icons.fit_screen, _resetZoom),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Future<void> _onCrop() async {
    try {
      final box = _cropKey.currentContext?.findRenderObject() as RenderBox?;
      final viewport = box?.size;
      if (viewport == null || viewport == Size.zero) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Crop area not ready, try again')));
        }
        return;
      }
      final cropped = await _crop(viewport);
      if (cropped.isNotEmpty && mounted) {
        Navigator.of(context).pop(cropped);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Crop failed: $e')));
      }
    }
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(8))),
      ),
      Paint()..color = Colors.black54,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect, const Radius.circular(8)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => cropRect != oldDelegate.cropRect;
}
