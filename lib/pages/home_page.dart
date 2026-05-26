import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import '../models/dtr_entry.dart';
import '../services/biometric_parser.dart';
import '../services/dtr_processor.dart';
import '../services/pdf_service.dart';
import '../services/file_text_extractor.dart';
import '../services/storage_service.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<MonthlyDtr> _monthlyDtrs = [];
  bool _isLoading = false;
  String? _fileName;
  MonthlyDtr? _selectedDtr;
  bool _showBulkPreview = false;
  final TextEditingController _inChargeController = TextEditingController(
    text: 'Supervisor Name',
  );
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _filterMonth;
  int? _filterYear;
  List<String> _savedNames = [];
  final Set<MonthlyDtr> _selectedForBulkPreview = {};

  // Official Hours Settings
  final TimeOfDay _amIn = const TimeOfDay(hour: 8, minute: 0);
  final TimeOfDay _amOut = const TimeOfDay(hour: 12, minute: 0);
  final TimeOfDay _pmIn = const TimeOfDay(hour: 13, minute: 0);
  final TimeOfDay _pmOut = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    setState(() => _isLoading = true);
    final saved = await StorageService.loadDtrs();
    final names = await StorageService.loadNames();

    int? latestYear;
    int? latestMonth;
    if (saved.isNotEmpty) {
      latestYear = saved.map((d) => d.year).reduce((a, b) => a > b ? a : b);
      latestMonth = saved
          .where((d) => d.year == latestYear)
          .map((d) => d.month)
          .reduce((a, b) => a > b ? a : b);
    }

    setState(() {
      _monthlyDtrs = saved;
      _savedNames = names;
      if (_filterYear == null && _filterMonth == null) {
        _filterYear = latestYear;
        _filterMonth = latestMonth;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveData() async {
    await StorageService.saveDtrs(_monthlyDtrs);
    await StorageService.saveNames(_savedNames);
  }

  @override
  void dispose() {
    _inChargeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null) {
      setState(() {
        _isLoading = true;
        _fileName = result.files.single.name;
        _selectedDtr = null; // Clear selection on new file
      });

      try {
        final file = File(result.files.single.path!);
        final content = await FileTextExtractor.extractText(file);

        final records = BiometricParser.parseRawFile(content);
        final dtrs = DtrProcessor.processToMonthlyDtr(records);

        setState(() {
          // Add new and deduplicate by name, month, and year
          final Map<String, MonthlyDtr> uniqueMap = {};

          // First add existing to the map
          for (var d in _monthlyDtrs) {
            final key = '${d.name.trim()}-${d.month}-${d.year}';
            uniqueMap[key] = d;
          }

          // Then add/overwrite with new records from file
          for (var d in dtrs) {
            final key = '${d.name.trim()}-${d.month}-${d.year}';
            uniqueMap[key] = d;
          }

          _monthlyDtrs.clear();
          _monthlyDtrs.addAll(uniqueMap.values);

          if (_monthlyDtrs.isNotEmpty) {
            int latestYear = _monthlyDtrs
                .map((d) => d.year)
                .reduce((a, b) => a > b ? a : b);
            int latestMonth = _monthlyDtrs
                .where((d) => d.year == latestYear)
                .map((d) => d.month)
                .reduce((a, b) => a > b ? a : b);
            _filterYear = latestYear;
            _filterMonth = latestMonth;
          }
          _isLoading = false;
        });
        await _saveData();

        if (dtrs.isNotEmpty && mounted) {
          _showBulkEditDialog(dtrs);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error parsing file: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1F36), Color(0xFF0D1117)],
              ),
            ),
            child: Column(
              children: [
                // Branding
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset('assets/logo.png', height: 52),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'DTR FORM',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'CS Form 48 Generator',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Divider(
                    color: Colors.white.withValues(alpha: 0.08),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 24),

                // Upload Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickFile,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.primary,
                              Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.upload_file_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Upload Attendance',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (_fileName != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _fileName!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Bulk Apply Settings
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildActionButton(
                    label: 'Bulk Apply Settings',
                    subtitle: 'Update multiple records',
                    icon: Icons.tune_rounded,
                    onTap: _monthlyDtrs.isEmpty ? null : _showBulkUpdateDialog,
                  ),
                ),

                const Spacer(),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'CS Form 48 Compliance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => exit(0),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.logout_rounded,
                              color: Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Exit Application',
                              style: GoogleFonts.outfit(
                                color: Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _showBulkPreview
                ? _buildBulkPreview()
                : _selectedDtr != null
                ? _buildDtrPreview(_selectedDtr!)
                : _monthlyDtrs.isEmpty
                ? _buildEmptyState()
                : _buildDtrGrid(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showUserGuideDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        tooltip: 'User Guide',
        child: const Icon(Icons.question_mark, color: Colors.white),
      ),
    );
  }

  void _showUserGuideDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Text('User Guide'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How to Use the App:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
              Text('1. Click "Upload Attendance" on the sidebar.'),
              SizedBox(height: 4),
              Text('2. Select a biometric text file or Excel file.'),
              SizedBox(height: 4),
              Text('3. The app will process the data and display the DTR records.'),
              SizedBox(height: 4),
              Text('4. Use the search bar or filters to find specific records.'),
              SizedBox(height: 4),
              Text('5. Click on a record to view its DTR template.'),
              SizedBox(height: 4),
              Text('6. Click "Bulk Apply Settings" to change supervisor or default hours for multiple records.'),
              SizedBox(height: 4),
              Text('7. You can print individual or bulk DTR records using the print buttons.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        _buildHeader('CS Form 48 Template Preview'),
        Expanded(
          child: PdfPreview(
            build: (format) => PdfService.generateForm48(
              MonthlyDtr.template(),
              inCharge: _inChargeController.text,
              singleForm: true,
              amIn: _amIn,
              amOut: _amOut,
              pmIn: _pmIn,
              pmOut: _pmOut,
            ),
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canDebug: false,
            previewPageMargin: const EdgeInsets.all(40),
            pdfFileName: 'CS_Form_48_Template.pdf',
          ),
        ),
      ],
    );
  }

  Widget _buildDtrPreview(MonthlyDtr dtr) {
    Future<Uint8List> pdfBuild(PdfPageFormat format) =>
        PdfService.generateForm48(
          dtr,
          inCharge: _inChargeController.text,
          singleForm: true,
          amIn: _amIn,
          amOut: _amOut,
          pmIn: _pmIn,
          pmOut: _pmOut,
        );

    return Column(
      children: [
        _buildHeader(
          'Preview: ${dtr.name}',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _selectedDtr = null),
          ),
          action: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () async {
                  final bytes = await pdfBuild(PdfPageFormat.a4);
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: 'DTR_${dtr.name}_${dtr.monthName}.pdf',
                  );
                },
                tooltip: 'Share PDF',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final bytes = await pdfBuild(PdfPageFormat.a4);
                  await Printing.layoutPdf(onLayout: (format) => bytes);
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print DTR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: pdfBuild,
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canDebug: false,
            previewPageMargin: const EdgeInsets.all(40),
            pdfFileName: 'DTR_${dtr.name}_${dtr.monthName}.pdf',
          ),
        ),
      ],
    );
  }

  Widget _buildBulkPreview() {
    final targetDtrs = _selectedForBulkPreview.isNotEmpty
        ? _monthlyDtrs
              .where((d) => _selectedForBulkPreview.contains(d))
              .toList()
        : _monthlyDtrs;

    Future<Uint8List> pdfBuild(PdfPageFormat format) =>
        PdfService.generateBulkForm48(
          targetDtrs,
          inCharge: _inChargeController.text,
          amIn: _amIn,
          amOut: _amOut,
          pmIn: _pmIn,
          pmOut: _pmOut,
        );

    return Column(
      children: [
        _buildHeader(
          'Bulk Print (Paper Saver)',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showBulkPreview = false),
          ),
          action: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () async {
                  final bytes = await pdfBuild(PdfPageFormat.a4);
                  await Printing.sharePdf(
                    bytes: bytes,
                    filename: 'All_DTRs_Paper_Saver.pdf',
                  );
                },
                tooltip: 'Share All',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final bytes = await pdfBuild(PdfPageFormat.a4);
                  await Printing.layoutPdf(onLayout: (format) => bytes);
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview(
            build: pdfBuild,
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canDebug: false,
            previewPageMargin: const EdgeInsets.all(40),
            pdfFileName: 'All_DTRs_Paper_Saver.pdf',
          ),
        ),
      ],
    );
  }

  Widget _buildDtrGrid() {
    // Filter and Sort Logic
    List<MonthlyDtr> filteredDtrs = _monthlyDtrs.where((dtr) {
      final query = _searchQuery.toLowerCase();
      final matchesQuery =
          dtr.name.toLowerCase().contains(query) ||
          dtr.userId.toLowerCase().contains(query);
      final matchesMonth = _filterMonth == null || dtr.month == _filterMonth;
      final matchesYear = _filterYear == null || dtr.year == _filterYear;
      return matchesQuery && matchesMonth && matchesYear;
    }).toList();

    // Sort by Year (Descending) then Month (Descending)
    filteredDtrs.sort((a, b) {
      if (a.year != b.year) return b.year.compareTo(a.year);
      return b.month.compareTo(a.month);
    });

    return Column(
      children: [
        _buildHeader(
          'DTR Records',
          action: ElevatedButton.icon(
            onPressed: () => setState(() => _showBulkPreview = true),
            icon: const Icon(Icons.print_outlined),
            label: Text(
              _selectedForBulkPreview.isNotEmpty
                  ? 'Print Selected (${_selectedForBulkPreview.length})'
                  : 'Bulk Print (Paper Saver)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        // Search and Filter Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search by name or ID...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 0,
                          horizontal: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty ||
                      _filterMonth != null ||
                      _filterYear != null) ...[
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          _filterMonth = null;
                          _filterYear = null;
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _filterMonth,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        hintText: 'Filter Month',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 20,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All Months'),
                        ),
                        ...List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(
                              DateFormat('MMMM').format(DateTime(2024, i + 1)),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterMonth = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _filterYear,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        hintText: 'Filter Year',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.history_outlined,
                          size: 20,
                        ),
                      ),
                      items: () {
                        final years = {
                          ..._monthlyDtrs.map((e) => e.year),
                          DateTime.now().year,
                        }.toList();
                        years.sort((a, b) => b.compareTo(a));
                        return [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Years'),
                          ),
                          ...years.map(
                            (y) => DropdownMenuItem(
                              value: y,
                              child: Text(y.toString()),
                            ),
                          ),
                        ];
                      }(),
                      onChanged: (v) => setState(() => _filterYear = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredDtrs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No records found'
                            : 'No matches for "$_searchQuery"',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 10,
                  ),
                  itemCount: filteredDtrs.length,
                  itemBuilder: (context, index) {
                    final dtr = filteredDtrs[index];
                    // Find original index for deletion/renaming if needed,
                    // or just use the dtr object if methods support it.
                    return _DtrCard(
                      dtr: dtr,
                      inCharge: _inChargeController.text,
                      amIn: _amIn,
                      amOut: _amOut,
                      pmIn: _pmIn,
                      pmOut: _pmOut,
                      isSelected: _selectedForBulkPreview.contains(dtr),
                      onSelect: (bool? selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedForBulkPreview.add(dtr);
                          } else {
                            _selectedForBulkPreview.remove(dtr);
                          }
                        });
                      },
                      onTap: () => setState(() => _selectedDtr = dtr),
                      onRename: () {
                        final originalIndex = _monthlyDtrs.indexOf(dtr);
                        if (originalIndex != -1) {
                          _showEditDtrDialog(originalIndex);
                        }
                      },
                      onDelete: () {
                        setState(() {
                          _monthlyDtrs.remove(dtr);
                          _selectedForBulkPreview.remove(dtr);
                        });
                        _saveData();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  TimeOfDay _parseTimeOfDay(String? s, TimeOfDay fallback) {
    if (s == null || !s.contains(':')) return fallback;
    try {
      final parts = s.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return fallback;
    }
  }

  String _formatTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTimePickerRow(
    String label,
    TimeOfDay time,
    Function(TimeOfDay) onSelected,
  ) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onSelected(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[200]!),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.access_time_rounded,
                size: 14,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              time.format(context),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2D3436),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDtrDialog(int index) {
    final dtr = _monthlyDtrs[index];
    final nameController = TextEditingController(
      text: dtr.name == dtr.userId ? '' : dtr.name,
    );
    final supervisorController = TextEditingController(
      text: dtr.supervisor ?? _inChargeController.text,
    );
    int selectedMonth = dtr.month;
    int selectedYear = dtr.year;

    TimeOfDay amIn = _parseTimeOfDay(dtr.amInTime, _amIn);
    TimeOfDay amOut = _parseTimeOfDay(dtr.amOutTime, _amOut);
    TimeOfDay pmIn = _parseTimeOfDay(dtr.pmInTime, _pmIn);
    TimeOfDay pmOut = _parseTimeOfDay(dtr.pmOutTime, _pmOut);

    final currentYear = DateTime.now().year;
    final years = {
      selectedYear,
      ...List.generate(7, (i) => currentYear - 3 + i),
    }.toList()..sort();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool isSupervisorValid = supervisorController.text
              .trim()
              .isNotEmpty;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Edit Record: ${dtr.userId}',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IDENTIFICATION',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Employee Name',
                        hintText: 'Enter full name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: supervisorController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Supervisor / In Charge',
                        hintText: 'Required',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        errorText: supervisorController.text.trim().isEmpty
                            ? 'Supervisor name is required'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 25),

                    Text(
                      'OFFICIAL HOURS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Arrival',
                            amIn,
                            (time) => setDialogState(() => amIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Departure',
                            amOut,
                            (time) => setDialogState(() => amOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Arrival',
                            pmIn,
                            (time) => setDialogState(() => pmIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Departure',
                            pmOut,
                            (time) => setDialogState(() => pmOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    Text(
                      'REPORTING PERIOD',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedMonth,
                            decoration: InputDecoration(
                              labelText: 'Month',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: List.generate(
                              12,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(
                                  DateFormat(
                                    'MMMM',
                                  ).format(DateTime(2024, i + 1)),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            onChanged: (v) =>
                                setDialogState(() => selectedMonth = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedYear,
                            decoration: InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: years
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(
                                      y.toString(),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => selectedYear = v!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton(
                onPressed: isSupervisorValid
                    ? () {
                        setState(() {
                          _monthlyDtrs[index] = dtr.copyWith(
                            name: nameController.text.trim().isEmpty
                                ? dtr.userId
                                : nameController.text.trim(),
                            month: selectedMonth,
                            year: selectedYear,
                            supervisor: supervisorController.text.trim(),
                            amInTime: _formatTimeOfDay(amIn),
                            amOutTime: _formatTimeOfDay(amOut),
                            pmInTime: _formatTimeOfDay(pmIn),
                            pmOutTime: _formatTimeOfDay(pmOut),
                          );
                        });
                        _saveData();
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[200],
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBulkEditDialog(List<MonthlyDtr> newDtrs) {
    final nameController = TextEditingController(
      text: newDtrs.length == 1 ? newDtrs.first.name : '',
    );
    final supervisorController = TextEditingController(
      text: _inChargeController.text,
    );
    int selectedMonth = newDtrs.isNotEmpty
        ? newDtrs.first.month
        : DateTime.now().month;
    int selectedYear = newDtrs.isNotEmpty
        ? newDtrs.first.year
        : DateTime.now().year;

    TimeOfDay amIn = _amIn;
    TimeOfDay amOut = _amOut;
    TimeOfDay pmIn = _pmIn;
    TimeOfDay pmOut = _pmOut;

    final currentYear = DateTime.now().year;
    final years = {
      selectedYear,
      ...List.generate(7, (i) => currentYear - 3 + i),
    }.toList()..sort();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final bool isSupervisorValid = supervisorController.text
              .trim()
              .isNotEmpty;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Import Settings',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data for ${newDtrs.length} records imported. Set common defaults for this batch.',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'IDENTIFICATION',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (newDtrs.length == 1) ...[
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Employee Name',
                          hintText: 'Enter full name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(
                            Icons.badge_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                    ],
                    TextField(
                      controller: supervisorController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Supervisor / In Charge',
                        hintText: 'Required',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        errorText: supervisorController.text.trim().isEmpty
                            ? 'Supervisor name is required'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 25),

                    Text(
                      'OFFICIAL HOURS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Arrival',
                            amIn,
                            (time) => setDialogState(() => amIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Departure',
                            amOut,
                            (time) => setDialogState(() => amOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Arrival',
                            pmIn,
                            (time) => setDialogState(() => pmIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Departure',
                            pmOut,
                            (time) => setDialogState(() => pmOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    Text(
                      'REPORTING PERIOD',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedMonth,
                            decoration: InputDecoration(
                              labelText: 'Month',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: List.generate(
                              12,
                              (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(
                                  DateFormat(
                                    'MMMM',
                                  ).format(DateTime(2024, i + 1)),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            onChanged: (v) =>
                                setDialogState(() => selectedMonth = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedYear,
                            decoration: InputDecoration(
                              labelText: 'Year',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            items: years
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(
                                      y.toString(),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => selectedYear = v!),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Skip for Now',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton(
                onPressed: isSupervisorValid
                    ? () {
                        setState(() {
                          for (var dtr in newDtrs) {
                            final index = _monthlyDtrs.indexOf(dtr);
                            if (index != -1) {
                              _monthlyDtrs[index] = dtr.copyWith(
                                name: nameController.text.trim().isEmpty
                                    ? dtr.name
                                    : nameController.text.trim(),
                                month: selectedMonth,
                                year: selectedYear,
                                supervisor: supervisorController.text.trim(),
                                amInTime: _formatTimeOfDay(amIn),
                                amOutTime: _formatTimeOfDay(amOut),
                                pmInTime: _formatTimeOfDay(pmIn),
                                pmOutTime: _formatTimeOfDay(pmOut),
                              );
                            }
                          }
                        });
                        _saveData();
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[200],
                ),
                child: const Text('Apply & Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(String title, {Widget? leading, Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      color: Colors.white,
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 10),
          ] else
            Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: const Color(0xFF2D3436),
            ),
          ),
          const Spacer(),
          action ?? const SizedBox.shrink(),
        ],
      ),
    );
  }

  void _showBulkUpdateDialog() {
    final supervisorController = TextEditingController(
      text: _inChargeController.text,
    );
    final searchController = TextEditingController();
    TimeOfDay amIn = _amIn;
    TimeOfDay amOut = _amOut;
    TimeOfDay pmIn = _pmIn;
    TimeOfDay pmOut = _pmOut;

    bool applyToAll = true;
    Set<int> selectedIndices = List.generate(
      _monthlyDtrs.length,
      (index) => index,
    ).toSet();
    String dialogSearchQuery = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredRecords = _monthlyDtrs.asMap().entries.where((entry) {
            final query = dialogSearchQuery.toLowerCase();
            return entry.value.name.toLowerCase().contains(query) ||
                entry.value.userId.toLowerCase().contains(query);
          }).toList();

          final bool isSupervisorValid = supervisorController.text
              .trim()
              .isNotEmpty;
          final bool isSelectionValid =
              applyToAll || selectedIndices.isNotEmpty;
          final bool canApply = isSupervisorValid && isSelectionValid;

          final bool allFilteredSelected =
              filteredRecords.isNotEmpty &&
              filteredRecords.every((e) => selectedIndices.contains(e.key));

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Bulk Apply Settings',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Update Supervisor and official hours for multiple records at once.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'SUPERVISOR DETAILS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: supervisorController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Supervisor / In Charge',
                        hintText: 'Required',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        errorText: supervisorController.text.trim().isEmpty
                            ? 'Supervisor name is required'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      'OFFICIAL HOURS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Arrival',
                            amIn,
                            (time) => setDialogState(() => amIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'AM Departure',
                            amOut,
                            (time) => setDialogState(() => amOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Arrival',
                            pmIn,
                            (time) => setDialogState(() => pmIn = time),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTimePickerRow(
                            'PM Departure',
                            pmOut,
                            (time) => setDialogState(() => pmOut = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TARGET RECORDS',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (!applyToAll)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${selectedIndices.length} Selected',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSegmentButton(
                              label: 'Apply to All',
                              isSelected: applyToAll,
                              onTap: () =>
                                  setDialogState(() => applyToAll = true),
                            ),
                          ),
                          Expanded(
                            child: _buildSegmentButton(
                              label: 'Select Specific',
                              isSelected: !applyToAll,
                              onTap: () =>
                                  setDialogState(() => applyToAll = false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!applyToAll) ...[
                      const SizedBox(height: 15),
                      TextField(
                        controller: searchController,
                        onChanged: (v) =>
                            setDialogState(() => dialogSearchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search people by name or ID...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: dialogSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(
                                      () => dialogSearchQuery = '',
                                    );
                                  },
                                )
                              : null,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: allFilteredSelected,
                            tristate:
                                filteredRecords.isNotEmpty &&
                                !allFilteredSelected &&
                                filteredRecords.any(
                                  (e) => selectedIndices.contains(e.key),
                                ),
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
                                  for (var e in filteredRecords) {
                                    selectedIndices.add(e.key);
                                  }
                                } else {
                                  for (var e in filteredRecords) {
                                    selectedIndices.remove(e.key);
                                  }
                                }
                              });
                            },
                          ),
                          Text(
                            allFilteredSelected
                                ? 'Deselect All Visible'
                                : 'Select All Visible',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${filteredRecords.length} visible',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: filteredRecords.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_search_outlined,
                                      color: Colors.grey[300],
                                      size: 40,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No matching records',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: filteredRecords.length,
                                separatorBuilder: (context, index) =>
                                    Divider(height: 1, color: Colors.grey[50]),
                                itemBuilder: (context, index) {
                                  final entry = filteredRecords[index];
                                  final isSelected = selectedIndices.contains(
                                    entry.key,
                                  );
                                  return CheckboxListTile(
                                    title: Text(
                                      entry.value.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'ID: ${entry.value.userId} • ${entry.value.monthName}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    value: isSelected,
                                    onChanged: (v) => setDialogState(() {
                                      if (v!) {
                                        selectedIndices.add(entry.key);
                                      } else {
                                        selectedIndices.remove(entry.key);
                                      }
                                    }),
                                    activeColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    dense: true,
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton(
                onPressed: canApply
                    ? () {
                        setState(() {
                          for (int i = 0; i < _monthlyDtrs.length; i++) {
                            if (applyToAll || selectedIndices.contains(i)) {
                              _monthlyDtrs[i] = _monthlyDtrs[i].copyWith(
                                supervisor: supervisorController.text.trim(),
                                amInTime: _formatTimeOfDay(amIn),
                                amOutTime: _formatTimeOfDay(amOut),
                                pmInTime: _formatTimeOfDay(pmIn),
                                pmOutTime: _formatTimeOfDay(pmOut),
                              );
                            }
                          }
                        });
                        _saveData();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Applied to ${applyToAll ? _monthlyDtrs.length : selectedIndices.length} records',
                                ),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.green[700],
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey[200],
                ),
                child: const Text('Apply Settings'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? primaryColor : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final bool isDisabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDisabled
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            color: isDisabled
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.07),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isDisabled
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDisabled
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: isDisabled ? 0.1 : 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DtrCard extends StatelessWidget {
  final MonthlyDtr dtr;
  final String inCharge;
  final TimeOfDay amIn, amOut, pmIn, pmOut;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool isSelected;
  final ValueChanged<bool?>? onSelect;

  const _DtrCard({
    required this.dtr,
    required this.inCharge,
    required this.amIn,
    required this.amOut,
    required this.pmIn,
    required this.pmOut,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.isSelected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                if (onSelect != null) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: onSelect,
                      activeColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor,
                        primaryColor.withValues(alpha: 0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      dtr.name.isNotEmpty ? dtr.name[0].toUpperCase() : '?',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              dtr.name,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: const Color(0xFF1A1F36),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onRename,
                            child: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _pill(
                            'ID: ${dtr.userId}',
                            Colors.grey.shade100,
                            Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          _pill(
                            '${dtr.monthName} ${dtr.year}',
                            primaryColor.withValues(alpha: 0.08),
                            primaryColor,
                          ),
                        ],
                      ),
                      if (dtr.supervisor != null &&
                          dtr.supervisor!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _pill(
                          '👤 ${dtr.supervisor}',
                          Colors.blue.shade50,
                          Colors.blue.shade700,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Actions
                OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    foregroundColor: const Color(0xFF1A1F36),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Preview',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final pdfData = await PdfService.generateForm48(
                      dtr,
                      inCharge: inCharge,
                      amIn: amIn,
                      amOut: amOut,
                      pmIn: pmIn,
                      pmOut: pmOut,
                    );
                    await Printing.layoutPdf(
                      onLayout: (format) => pdfData,
                      name: 'DTR_${dtr.name}_${dtr.monthName}_${dtr.year}.pdf',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Export',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red.shade300,
                    size: 20,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Delete Record?'),
                        content: Text(
                          'Are you sure you want to delete the DTR for ${dtr.name}?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              onDelete();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
