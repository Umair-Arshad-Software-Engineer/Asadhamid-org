// pages/batch_management_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../Models/batch_model.dart';

class BatchManagementPage extends StatefulWidget {
  @override
  _BatchManagementPageState createState() => _BatchManagementPageState();
}

class _BatchManagementPageState extends State<BatchManagementPage> {
  List<Batch> _batches = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedItemFilter;
  List<String> _itemNames = [];

  // Summary statistics
  double _totalQuantity    = 0.0;
  double _totalRemaining   = 0.0;
  double _totalValue       = 0.0;
  int    _activeBatchCount = 0;
  int    _emptyBatchCount  = 0;
  int    _lowStockCount    = 0;

  // Low-stock threshold (kg) — adjust as needed
  static const double _lowStockThreshold = 100.0;

  final Color _primary   = const Color(0xFFFF8A65);
  final Color _secondary = const Color(0xFFFFB74D);

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _loadItemNames();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadItemNames() async {
    final snap = await FirebaseDatabase.instance.ref('items').get();
    if (snap.exists) {
      final items = snap.value as Map<dynamic, dynamic>;
      if (mounted) {
        setState(() {
          _itemNames = items.values
              .map((v) => v['itemName']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
        });
      }
    }
  }

  Future<void> _loadBatches() async {
    if (mounted) setState(() => _isLoading = true);

    final snap =
    await FirebaseDatabase.instance.ref('batches').get();

    final List<Batch> batches = [];

    if (snap.exists) {
      final data = snap.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        batches.add(
          Batch.fromMap(Map<String, dynamic>.from(value as Map), key.toString()),
        );
      });
      batches.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    }

    if (mounted) {
      setState(() {
        _batches = batches;
        _calculateStats();
        _isLoading = false;
      });
    }
  }

  void _calculateStats() {
    _totalQuantity  = _batches.fold(0.0, (s, b) => s + b.quantity);
    _totalRemaining = _batches.fold(0.0, (s, b) => s + b.remainingQty);
    _totalValue     = _batches.fold(0.0, (s, b) => s + b.remainingQty * b.purchasePrice);
    _activeBatchCount = _batches.where((b) => b.remainingQty > 0).length;
    _emptyBatchCount  = _batches.where((b) => b.remainingQty <= 0).length;
    _lowStockCount    = _batches.where(
            (b) => b.remainingQty > 0 && b.remainingQty < _lowStockThreshold).length;
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<Batch> get _filteredBatches {
    return _batches.where((b) {
      if (_selectedItemFilter != null && _selectedItemFilter!.isNotEmpty) {
        if (b.itemName != _selectedItemFilter) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return b.batchNumber.toLowerCase().contains(q) ||
            b.itemName.toLowerCase().contains(q)        ||
            b.vendorName.toLowerCase().contains(q)      ||
            b.length.toLowerCase().contains(q)          ||
            b.bodyType.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showBatchDetails(Batch batch) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final used    = batch.usedQty;
    final pctUsed = batch.quantity > 0 ? used / batch.quantity : 0.0;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: _primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                batch.batchNumber,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Combination badge ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: _primary.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.itemName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _primary,
                          fontSize: 15,
                        ),
                      ),
                      if (batch.length.isNotEmpty || batch.bodyType.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              if (batch.length.isNotEmpty) ...[
                                const Icon(Icons.straighten,
                                    size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(batch.length,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey)),
                                const SizedBox(width: 12),
                              ],
                              if (batch.bodyType.isNotEmpty) ...[
                                const Icon(Icons.category,
                                    size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(batch.bodyType,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey)),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Quantity progress ──────────────────────────────────────
                _buildDetailRow('Original Qty',
                    '${batch.quantity.toStringAsFixed(2)} kg'),
                _buildDetailRow('Remaining Qty',
                    '${batch.remainingQty.toStringAsFixed(2)} kg',
                    color: batch.remainingQty <= 0
                        ? Colors.red
                        : batch.remainingQty < _lowStockThreshold
                        ? Colors.orange
                        : Colors.green),
                _buildDetailRow('Used Qty',
                    '${used.toStringAsFixed(2)} kg',
                    color: Colors.blueGrey),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pctUsed,
                    minHeight: 8,
                    backgroundColor: Colors.green[100],
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.green[700]!),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(pctUsed * 100).toStringAsFixed(1)}% consumed',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                _buildDetailRow('Rate (Cost/kg)',
                    '${batch.purchasePrice.toStringAsFixed(2)} PKR'),
                _buildDetailRow('Remaining Value',
                    '${(batch.remainingQty * batch.purchasePrice).toStringAsFixed(2)} PKR'),
                _buildDetailRow('Vendor',   batch.vendorName),
                _buildDetailRow('Purchase Date',
                    fmt.format(batch.purchaseDate)),
                if (batch.purchaseId.isNotEmpty)
                  _buildDetailRow('Purchase ID', batch.purchaseId),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Batch Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primary, _secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBatches,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search + filter ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText:
                    'Search by batch, item, vendor, length, body…',
                    prefixIcon:
                    const Icon(Icons.search, color: Color(0xFFFF8A65)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                      const BorderSide(color: Color(0xFFFF8A65), width: 2),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedItemFilter,
                  hint: const Text('Filter by Item (all)'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Items')),
                    ..._itemNames.map((n) =>
                        DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedItemFilter = v),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),

          // ── Stats bar ─────────────────────────────────────────────────────
          Container(
            margin:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade50, Colors.amber.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatTile('Total Batches',
                        _batches.length.toString(), Colors.blue,
                        icon: Icons.inventory_2),
                    _buildStatTile('Active',
                        _activeBatchCount.toString(), Colors.green,
                        icon: Icons.check_circle),
                    _buildStatTile('Empty',
                        _emptyBatchCount.toString(), Colors.grey,
                        icon: Icons.remove_circle_outline),
                    _buildStatTile('Low Stock',
                        _lowStockCount.toString(), Colors.orange,
                        icon: Icons.warning_amber),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatTile(
                        'Total Qty',
                        '${_totalQuantity.toStringAsFixed(0)} kg',
                        Colors.purple,
                        icon: Icons.scale),
                    _buildStatTile(
                        'Remaining',
                        '${_totalRemaining.toStringAsFixed(0)} kg',
                        Colors.teal,
                        icon: Icons.inbox),
                    _buildStatTile(
                        'Stock Value',
                        '${_totalValue.toStringAsFixed(0)} PKR',
                        const Color(0xFFE65100),
                        icon: Icons.attach_money),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Batch list ────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBatches.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2,
                      size: 64,
                      color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No batches found',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16)),
                ],
              ),
            )
                : ListView.builder(
              padding:
              const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredBatches.length,
              itemBuilder: (_, i) =>
                  _buildBatchCard(_filteredBatches[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Batch card ────────────────────────────────────────────────────────────

  Widget _buildBatchCard(Batch batch) {
    final isEmpty   = batch.remainingQty <= 0;
    final isLow     = !isEmpty && batch.remainingQty < _lowStockThreshold;
    final pctRemain =
    batch.quantity > 0 ? batch.remainingQty / batch.quantity : 0.0;

    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle;
    String statusLabel = 'Active';

    if (isEmpty) {
      statusColor = Colors.grey;
      statusIcon  = Icons.remove_circle_outline;
      statusLabel = 'Empty';
    } else if (isLow) {
      statusColor = Colors.orange;
      statusIcon  = Icons.warning_amber_rounded;
      statusLabel = 'Low Stock';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showBatchDetails(batch),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row ─────────────────────────────────────────────────
              Row(
                children: [
                  // Status icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon,
                        color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 10),

                  // Item + combination
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.itemName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        // ── COMBINATION row ──────────────────────────────
                        if (batch.length.isNotEmpty ||
                            batch.bodyType.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                if (batch.length.isNotEmpty) ...[
                                  Container(
                                    padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius:
                                      BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.blue[100]!),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.straighten,
                                            size: 11,
                                            color: Colors.blue[700]),
                                        const SizedBox(width: 3),
                                        Text(
                                          batch.length,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue[700],
                                              fontWeight:
                                              FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                if (batch.bodyType.isNotEmpty)
                                  Container(
                                    padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[50],
                                      borderRadius:
                                      BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.purple[100]!),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.category,
                                            size: 11,
                                            color: Colors.purple[700]),
                                        const SizedBox(width: 3),
                                        Text(
                                          batch.bodyType,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.purple[700],
                                              fontWeight:
                                              FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Remaining qty badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: statusColor.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              batch.remainingQty.toStringAsFixed(2),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: statusColor,
                              ),
                            ),
                            Text('kg',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Progress bar ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pctRemain,
                            minHeight: 6,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                statusColor),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${batch.remainingQty.toStringAsFixed(1)} / '
                              '${batch.quantity.toStringAsFixed(1)} kg remaining '
                              '(${(pctRemain * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Meta row ─────────────────────────────────────────────────
              Row(
                children: [
                  _metaChip(Icons.attach_money,
                      '${batch.purchasePrice.toStringAsFixed(2)} PKR/kg',
                      Colors.green),
                  const SizedBox(width: 6),
                  _metaChip(Icons.store, batch.vendorName, Colors.blue),
                  const SizedBox(width: 6),
                  _metaChip(
                    Icons.calendar_today,
                    DateFormat('dd MMM yy').format(batch.purchaseDate),
                    Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _metaChip(IconData icon, String label, Color color) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withOpacity(0.8)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String title, String value, Color color,
      {IconData? icon}) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 2,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
          ],
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(title,
              style: TextStyle(
                  fontSize: 9, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const Text(': ',
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}