import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../models/material_model.dart';
import '../../services/material_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_feedback.dart';

typedef MaterialExternalFileOpener =
    Future<ResultType> Function(String filePath, String mimeType);

/// Screen and handler for viewing study materials.
/// - PDF: Rendered in-app with Syncfusion PDF Viewer.
/// - PPTX / DOCX: Rendered in-app via converted preview PDF, with fallback to external device app.
/// - Fallback: In-app text viewer displaying the extracted text when files cannot be loaded or opened.
class MaterialViewerScreen extends StatefulWidget {
  static final Set<String> _openingMaterialIds = <String>{};

  final MaterialModel material;
  final bool initialShowExtractedText;
  final MaterialService? materialService;

  const MaterialViewerScreen({
    super.key,
    required this.material,
    this.initialShowExtractedText = false,
    this.materialService,
  });

  /// Opens the original file using the device's native application (e.g. PowerPoint, Word).
  static Future<void> openExternal({
    required BuildContext context,
    required MaterialModel material,
    MaterialService? materialService,
    MaterialExternalFileOpener? fileOpener,
  }) async {
    if (!_openingMaterialIds.add(material.id)) {
      AppFeedback.info(
        context,
        '${material.fileName} is already being prepared.',
        title: 'Opening file',
      );
      return;
    }

    final service = materialService ?? MaterialService();
    final ext = material.fileType.toLowerCase();
    AppFeedback.info(
      context,
      'Downloading ${material.fileName} securely from storage.',
      title: 'Preparing file',
      duration: const Duration(seconds: 30),
    );

    try {
      final download = await service.prepareMaterialForExternalOpen(material);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!download.isReady || download.file == null) {
        _showDownloadFailure(
          context: context,
          material: material,
          result: download,
          materialService: service,
          fileOpener: fileOpener,
        );
        return;
      }

      final opener =
          fileOpener ??
          (path, mimeType) async {
            final result = await OpenFilex.open(path, type: mimeType);
            return result.type;
          };
      final openResult = await opener(
        download.file!.path,
        material.contentType,
      );
      if (!context.mounted) return;

      switch (openResult) {
        case ResultType.done:
          AppFeedback.success(
            context,
            '${material.fileName} was sent to a compatible app.',
            title: 'File opened',
          );
        case ResultType.noAppToOpen:
          await _showNoCompatibleAppDialog(context, material);
        case ResultType.fileNotFound:
          AppFeedback.error(
            context,
            'The downloaded file is no longer available. Try opening it again.',
            title: 'File not found',
          );
        case ResultType.permissionDenied:
          AppFeedback.error(
            context,
            'Studexa was not allowed to open this file. Check the device permissions and try again.',
            title: 'Permission needed',
          );
        case ResultType.error:
          AppFeedback.error(
            context,
            'The device could not open this ${ext.toUpperCase()} file. Try another compatible app.',
            title: 'Unable to open file',
          );
      }
    } catch (e) {
      if (context.mounted) {
        debugPrint('Failed to open original material: $e');
        AppFeedback.error(
          context,
          'The original file could not be opened. Check your connection and try again.',
          title: 'Unable to open file',
          actionLabel: 'Retry',
          onAction: () => openExternal(
            context: context,
            material: material,
            materialService: service,
            fileOpener: fileOpener,
          ),
        );
      }
    } finally {
      _openingMaterialIds.remove(material.id);
    }
  }

  static void _showDownloadFailure({
    required BuildContext context,
    required MaterialModel material,
    required MaterialDownloadResult result,
    required MaterialService materialService,
    MaterialExternalFileOpener? fileOpener,
  }) {
    final canRetry =
        result.status == MaterialDownloadStatus.uploadInProgress ||
        result.status == MaterialDownloadStatus.unavailable ||
        result.status == MaterialDownloadStatus.failed;
    final title = switch (result.status) {
      MaterialDownloadStatus.uploadInProgress => 'File still uploading',
      MaterialDownloadStatus.uploadFailed => 'Original upload failed',
      MaterialDownloadStatus.unsupportedPlatform => 'Unsupported on web',
      _ => 'Unable to download file',
    };

    AppFeedback.error(
      context,
      result.message,
      title: title,
      actionLabel: canRetry ? 'Retry' : null,
      onAction: canRetry
          ? () => openExternal(
              context: context,
              material: material,
              materialService: materialService,
              fileOpener: fileOpener,
            )
          : null,
    );
  }

  static Future<void> _showNoCompatibleAppDialog(
    BuildContext context,
    MaterialModel material,
  ) async {
    final ext = material.fileType.toUpperCase();
    final hasExtractedText = material.extractedText.trim().isNotEmpty;
    final viewText = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('No app can open $ext'),
        content: Text(
          'Install Microsoft ${ext == 'DOCX' ? 'Word' : 'PowerPoint'}, '
          '${ext == 'DOCX' ? 'Google Docs' : 'Google Slides'}, or WPS Office '
          'to view the original file.'
          '${hasExtractedText ? ' You can view its extracted text instead.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          if (hasExtractedText)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('View Extracted Text'),
            ),
        ],
      ),
    );

    if (viewText == true && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialViewerScreen(
            material: material,
            initialShowExtractedText: true,
          ),
        ),
      );
    }
  }

  /// Static helper to open any material appropriately:
  /// - PDF: Opens in-app PDF viewer directly.
  /// - PPTX / DOCX: If in-app converted PDF is ready or converting, opens in-app preview viewer.
  /// - Fallback: If conversion failed, falls back to openExternal.
  static Future<void> open({
    required BuildContext context,
    required MaterialModel material,
    MaterialService? materialService,
  }) async {
    final ext = material.fileType.toLowerCase();

    // 1. PDF opens directly in-app
    if (ext == 'pdf') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialViewerScreen(material: material),
        ),
      );
      return;
    }

    // 2. PPTX or DOCX with converted preview or converting in background: open in-app preview
    if (material.hasConvertedPdf || material.isConverting) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialViewerScreen(material: material),
        ),
      );
      return;
    }

    // 3. Fallback: if conversion failed or unsupported, attempt opening in device app
    await openExternal(
      context: context,
      material: material,
      materialService: materialService,
    );
  }

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  static const Color _primaryNavy = AppTheme.primaryNavy;
  static const Color _surfaceWhite = AppTheme.surfaceWhite;
  static const Color _textPrimary = AppTheme.textPrimary;
  static const Color _textSecondary = AppTheme.textSecondary;

  late MaterialModel _material;
  late final MaterialService _materialService;
  StreamSubscription<MaterialModel?>? _materialSub;

  late bool _showExtractedText;
  bool _isLoadingPdf = true;
  bool _previewStarted = false;
  String? _pdfLoadError;
  Uint8List? _pdfBytes;

  @override
  void initState() {
    super.initState();
    _material = widget.material;
    _materialService = widget.materialService ?? MaterialService();

    final isNativePdf = _material.fileType.toLowerCase() == 'pdf';
    final hasPreview = _material.hasConvertedPdf;

    _showExtractedText =
        widget.initialShowExtractedText ||
        (!isNativePdf &&
            !hasPreview &&
            !_material.isConverting &&
            !_material.conversionFailed);

    if (_showExtractedText) {
      _isLoadingPdf = false;
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    if (_previewStarted) return;
    _previewStarted = true;
    if (_material.fileType.toLowerCase() == 'pdf' ||
        _material.hasConvertedPdf) {
      _loadPdf();
    } else if (_material.isConverting) {
      _listenForConversion();
    } else {
      _isLoadingPdf = false;
    }
  }

  @override
  void dispose() {
    _materialSub?.cancel();
    super.dispose();
  }

  void _listenForConversion() {
    _materialSub?.cancel();
    _materialSub = _materialService.streamMaterial(_material.id).listen((
      updated,
    ) {
      if (updated == null || !mounted) return;
      setState(() {
        _material = updated;
      });

      if (_material.hasConvertedPdf) {
        _materialSub?.cancel();
        _loadPdf();
      } else if (_material.conversionFailed) {
        _materialSub?.cancel();
        setState(() {
          _isLoadingPdf = false;
        });
      }
    });
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoadingPdf = true;
      _pdfLoadError = null;
    });

    final isNativePdf = _material.fileType.toLowerCase() == 'pdf';

    try {
      final bytes = isNativePdf
          ? await _materialService.getMaterialFileBytes(_material)
          : await _materialService.getConvertedPdfBytes(_material);

      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoadingPdf = false;

          final effectiveUrl = isNativePdf
              ? _material.downloadUrl
              : _material.convertedPdfUrl;

          if (bytes == null && (effectiveUrl == null || effectiveUrl.isEmpty)) {
            _pdfLoadError = isNativePdf
                ? 'Original PDF file is not available in storage. Displaying extracted text fallback.'
                : 'In-app preview PDF is not available in storage. Displaying extracted text fallback.';
            _showExtractedText = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Failed to load document preview: $e');
        setState(() {
          _isLoadingPdf = false;
          _pdfLoadError =
              'The document preview could not be loaded. Showing the extracted text instead.';
          _showExtractedText = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNativePdf = _material.fileType.toLowerCase() == 'pdf';
    final hasPreview = isNativePdf || _material.hasConvertedPdf;

    String subtitleText;
    if (_showExtractedText) {
      subtitleText = 'Extracted Text View';
    } else if (isNativePdf) {
      subtitleText = 'PDF Document View';
    } else if (_material.hasConvertedPdf) {
      subtitleText = '${_material.fileType.toUpperCase()} In-App Preview';
    } else if (_material.isConverting) {
      subtitleText = 'Generating In-App Preview...';
    } else if (_material.conversionFailed) {
      subtitleText = 'Preview Conversion Failed';
    } else {
      subtitleText = '${_material.fileType.toUpperCase()} Document View';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _material.fileName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitleText,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Action for non-PDFs: open the original file in external device app
          if (!isNativePdf)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              tooltip:
                  'Open original ${_material.fileType.toUpperCase()} in device app',
              onPressed: () {
                MaterialViewerScreen.openExternal(
                  context: context,
                  material: _material,
                  materialService: _materialService,
                );
              },
            ),
          // Toggle between preview and extracted text
          if (hasPreview ||
              _material.isConverting ||
              _material.conversionFailed)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  _showExtractedText = !_showExtractedText;
                });
                if (!_showExtractedText) _startPreview();
              },
              icon: Icon(
                _showExtractedText
                    ? (isNativePdf ? Icons.picture_as_pdf : Icons.preview)
                    : Icons.text_snippet,
                size: 18,
              ),
              label: Text(
                _showExtractedText
                    ? (isNativePdf ? 'View PDF' : 'View Preview')
                    : 'View Text',
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_showExtractedText) {
      return _buildExtractedTextView();
    }

    // If converting or conversion failed and preview not ready yet, show in-app status card
    if ((_material.isConverting || _material.conversionFailed) &&
        !_material.hasConvertedPdf) {
      return _buildConvertingView();
    }

    if (_isLoadingPdf) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _primaryNavy),
            SizedBox(height: 16),
            Text(
              'Loading document preview...',
              style: TextStyle(color: _textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_pdfBytes != null) {
      return SfPdfViewer.memory(
        _pdfBytes!,
        onDocumentLoadFailed: (details) {
          if (mounted) {
            setState(() {
              _pdfLoadError = details.description;
              _showExtractedText = true;
            });
          }
        },
      );
    }

    final isNativePdf = _material.fileType.toLowerCase() == 'pdf';
    final effectiveUrl = isNativePdf
        ? _material.downloadUrl
        : _material.convertedPdfUrl;

    if (effectiveUrl != null && effectiveUrl.isNotEmpty) {
      return SfPdfViewer.network(
        effectiveUrl,
        onDocumentLoadFailed: (details) {
          if (mounted) {
            setState(() {
              _pdfLoadError = details.description;
              _showExtractedText = true;
            });
          }
        },
      );
    }

    return _buildExtractedTextView();
  }

  Widget _buildConvertingView() {
    final isFailed = _material.conversionFailed;
    return Container(
      color: _surfaceWhite,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.maxContentWidthMobile,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isFailed
                      ? Colors.amber.shade50
                      : Colors.indigo.shade50,
                  shape: BoxShape.circle,
                ),
                child: isFailed
                    ? Icon(
                        Icons.warning_amber_rounded,
                        size: 40,
                        color: Colors.amber.shade900,
                      )
                    : const CircularProgressIndicator(
                        color: _primaryNavy,
                        strokeWidth: 3,
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                isFailed
                    ? 'Preview Conversion Failed'
                    : 'Generating In-App Preview',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFailed
                    ? 'Could not generate an in-app preview for "${_material.fileName}". You can open the original file with your device\'s app or view the extracted text.'
                    : 'Converting "${_material.fileName}" to a high-fidelity in-app preview PDF. This will take a few seconds.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: _textSecondary),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryNavy,
                      side: const BorderSide(color: _primaryNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      MaterialViewerScreen.openExternal(
                        context: context,
                        material: _material,
                        materialService: _materialService,
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      'Open Original (${_material.fileType.toUpperCase()})',
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _showExtractedText = true;
                      });
                    },
                    icon: const Icon(Icons.text_snippet, size: 18),
                    label: const Text('View Extracted Text'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExtractedTextView() {
    return Container(
      color: _surfaceWhite,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.maxContentWidthTablet,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pdfLoadError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.amber.shade900,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pdfLoadError!,
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  const Icon(Icons.description, color: _primaryNavy, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Extracted Material Text',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.material.fileSizeBytes != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.material.formattedFileSize,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.material.extractedText.isNotEmpty
                        ? widget.material.extractedText
                        : 'No text was extractable from this document.',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
