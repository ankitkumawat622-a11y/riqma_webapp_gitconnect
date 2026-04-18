import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AuditUiLab extends StatefulWidget {
  const AuditUiLab({super.key});

  @override
  State<AuditUiLab> createState() => _AuditUiLabState();
}

enum LayoutMode { miller, timeline, sticky }

class _AuditUiLabState extends State<AuditUiLab> with TickerProviderStateMixin {
  LayoutMode _currentMode = LayoutMode.miller;
  String _filter = 'all'; // 'all', 'OK', 'Not OK'
  List<Checkpoint> _allCheckpoints = [];
  List<CategoryData> _categories = [];
  
  // Selection state
  Checkpoint? _selectedCheckpoint;
  CategoryData? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _generateMockData();
    if (_categories.isNotEmpty) {
      _selectedCategory = _categories.first;
    }
  }

  void _generateMockData() {
    final random = Random();
    final List<String> catNames = ['Hub', 'Nacelle', 'Tower', 'Basement', 'Blade'];
    final List<String> subCatNames = ['Electrical', 'Mechanical', 'Hydraulic', 'Safety', 'Infrastructural'];
    
    final List<Checkpoint> data = [];
    for (final cat in catNames) {
      for (final sub in subCatNames) {
        final int count = random.nextInt(3) + 2; // 2-4 items per subcat
        for (int i = 0; i < count; i++) {
          final isOk = random.nextDouble() > 0.3; // 70% OK
          data.add(Checkpoint(
            id: 'cp_${cat}_${sub}_$i',
            title: '$cat $sub Task ${i + 1}',
            category: cat,
            subCategory: sub,
            status: isOk ? 'OK' : 'Not OK',
            observation: isOk 
              ? 'Everything looks good and meets quality standards.' 
              : 'Visual crack detected near the mounting bolt. Requires immediate attention.',
          ));
        }
      }
    }
    _allCheckpoints = data;
    _updateCategories();
  }

  void _updateCategories() {
    final Map<String, List<Checkpoint>> grouped = {};
    for (final cp in _allCheckpoints) {
      grouped.putIfAbsent(cp.category, () => []).add(cp);
    }

    _categories = grouped.entries.map((e) {
      final items = e.value;
      return CategoryData(
        name: e.key,
        checkpoints: items,
        okCount: items.where((i) => i.status == 'OK').length,
        notOkCount: items.where((i) => i.status == 'Not OK').length,
      );
    }).toList();
  }

  List<Checkpoint> get _filteredCheckpoints {
    if (_filter == 'all') return _allCheckpoints;
    return _allCheckpoints.where((cp) => cp.status == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          _buildGlobalHeader(),
          _buildFilterBar(),
          Expanded(
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildActiveModeLayout()),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: _buildDetailPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audit UI Lab', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1A1C1E))),
              Text('Prototype & Layout Testing', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
          SegmentedButton<LayoutMode>(
            segments: const [
              ButtonSegment(value: LayoutMode.miller, label: Text('Miller columns'), icon: Icon(Icons.view_column)),
              ButtonSegment(value: LayoutMode.timeline, label: Text('Timeline'), icon: Icon(Icons.timeline)),
              ButtonSegment(value: LayoutMode.sticky, label: Text('Sticky'), icon: Icon(Icons.view_day)),
            ],
            selected: {_currentMode},
            onSelectionChanged: (set) => setState(() => _currentMode = set.first),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final okCount = _allCheckpoints.where((cp) => cp.status == 'OK').length;
    final notOkCount = _allCheckpoints.where((cp) => cp.status == 'Not OK').length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _FilterCard(
            label: 'All',
            count: _allCheckpoints.length,
            isActive: _filter == 'all',
            color: Colors.blue,
            onTap: () => setState(() => _filter = 'all'),
          ),
          const SizedBox(width: 12),
          _FilterCard(
            label: 'OK',
            count: okCount,
            isActive: _filter == 'OK',
            color: Colors.green,
            onTap: () => setState(() => _filter = 'OK'),
          ),
          const SizedBox(width: 12),
          _FilterCard(
            label: 'Not OK',
            count: notOkCount,
            isActive: _filter == 'Not OK',
            color: Colors.red,
            onTap: () => setState(() => _filter = 'Not OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveModeLayout() {
    switch (_currentMode) {
      case LayoutMode.miller:
        return _MillerLayout(
          categories: _categories,
          selectedCategory: _selectedCategory,
          onCategorySelected: (cat) => setState(() => _selectedCategory = cat),
          selectedCheckpoint: _selectedCheckpoint,
          onCheckpointSelected: (cp) => setState(() => _selectedCheckpoint = cp),
          filter: _filter,
        );
      case LayoutMode.timeline:
        return _TimelineLayout(
          checkpoints: _filteredCheckpoints,
          selectedCheckpoint: _selectedCheckpoint,
          onCheckpointSelected: (cp) => setState(() => _selectedCheckpoint = cp),
        );
      case LayoutMode.sticky:
        return _StickyLayout(
          categories: _categories,
          selectedCheckpoint: _selectedCheckpoint,
          onCheckpointSelected: (cp) => setState(() => _selectedCheckpoint = cp),
          filter: _filter,
        );
    }
  }

  Widget _buildDetailPanel() {
    if (_selectedCheckpoint == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Select a checkpoint to view details', style: GoogleFonts.outfit(color: Colors.grey[500])),
          ],
        ),
      );
    }

    final cp = _selectedCheckpoint!;
    final isOk = cp.status == 'OK';

    return Container(
      padding: const EdgeInsets.all(32),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOk ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  cp.status,
                  style: GoogleFonts.outfit(color: isOk ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const Spacer(),
              Text(cp.id, style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 24),
          Text(cp.title, style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${cp.category} > ${cp.subCategory}', style: GoogleFonts.outfit(color: Colors.blue[700])),
          const SizedBox(height: 32),
          Text('Observation', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(cp.observation, style: GoogleFonts.outfit(fontSize: 16, height: 1.5, color: Colors.grey[800])),
        ],
      ),
    );
  }
}

class Checkpoint {
  final String id;
  final String title;
  final String category;
  final String subCategory;
  final String status;
  final String observation;

  Checkpoint({required this.id, required this.title, required this.category, required this.subCategory, required this.status, required this.observation});
}

class CategoryData {
  final String name;
  final List<Checkpoint> checkpoints;
  final int okCount;
  final int notOkCount;

  CategoryData({required this.name, required this.checkpoints, required this.okCount, required this.notOkCount});
}

class _FilterCard extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _FilterCard({required this.label, required this.count, required this.isActive, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? color : Colors.grey[200]!, width: 2),
        ),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: isActive ? color : Colors.grey[600])),
            Text(count.toString(), style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: isActive ? color : Colors.black)),
          ],
        ),
      ),
    );
  }
}

// Layout Implementations will follow in Next Steps to keep chunks manageable
class _MillerLayout extends StatelessWidget {
  final List<CategoryData> categories;
  final CategoryData? selectedCategory;
  final ValueChanged<CategoryData> onCategorySelected;
  final Checkpoint? selectedCheckpoint;
  final ValueChanged<Checkpoint> onCheckpointSelected;
  final String filter;

  const _MillerLayout({required this.categories, required this.selectedCategory, required this.onCategorySelected, required this.selectedCheckpoint, required this.onCheckpointSelected, required this.filter});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Column 1: Categories
        SizedBox(
          width: 250,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = selectedCategory?.name == cat.name;
              return ListTile(
                selected: isSelected,
                selectedTileColor: Colors.blue[50],
                title: Text(cat.name, style: GoogleFonts.outfit(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text('OK: ${cat.okCount} | Not OK: ${cat.notOkCount}', style: GoogleFonts.outfit(fontSize: 12)),
                onTap: () => onCategorySelected(cat),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        // Column 2: Checkpoints
        Expanded(
          child: ListView(
            children: (selectedCategory?.checkpoints ?? [])
                .where((cp) => filter == 'all' || cp.status == filter)
                .map((cp) => ListTile(
                  selected: selectedCheckpoint?.id == cp.id,
                  selectedTileColor: Colors.blue[50]?.withValues(alpha: 0.5),
                  leading: Icon(cp.status == 'OK' ? Icons.check_circle : Icons.error, color: cp.status == 'OK' ? Colors.green : Colors.red, size: 16),
                  title: Text(cp.title, style: GoogleFonts.outfit(fontSize: 14)),
                  subtitle: Text(cp.observation, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 12)),
                  onTap: () => onCheckpointSelected(cp),
                ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _TimelineLayout extends StatefulWidget {
  final List<Checkpoint> checkpoints;
  final Checkpoint? selectedCheckpoint;
  final ValueChanged<Checkpoint> onCheckpointSelected;

  const _TimelineLayout({required this.checkpoints, required this.selectedCheckpoint, required this.onCheckpointSelected});

  @override
  State<_TimelineLayout> createState() => _TimelineLayoutState();
}

class _TimelineLayoutState extends State<_TimelineLayout> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      itemCount: widget.checkpoints.length,
      itemBuilder: (context, index) {
        final cp = widget.checkpoints[index];
        final isSelected = widget.selectedCheckpoint?.id == cp.id;
        final isNotOk = cp.status == 'Not OK';

        return IntrinsicHeight(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isNotOk ? Colors.red : Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: isNotOk 
                      ? ScaleTransition(
                          scale: Tween(begin: 1.0, end: 1.5).animate(_pulseController),
                          child: FadeTransition(
                            opacity: Tween(begin: 1.0, end: 0.3).animate(_pulseController),
                            child: Container(decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                          ),
                        )
                      : null,
                  ),
                  if (index < widget.checkpoints.length - 1)
                  Expanded(child: Container(width: 2, color: Colors.grey[200])),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: InkWell(
                    onTap: () => widget.onCheckpointSelected(cp),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? Colors.blue : Colors.transparent),
                        boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)] : [],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cp.category, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blue)),
                          Text(cp.title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                          Text(cp.observation, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StickyLayout extends StatelessWidget {
  final List<CategoryData> categories;
  final Checkpoint? selectedCheckpoint;
  final ValueChanged<Checkpoint> onCheckpointSelected;
  final String filter;

  const _StickyLayout({required this.categories, required this.selectedCheckpoint, required this.onCheckpointSelected, required this.filter});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: categories.expand((cat) {
        final filteredItems = cat.checkpoints.where((cp) => filter == 'all' || cp.status == filter).toList();
        if (filteredItems.isEmpty) return <Widget>[];
        
        return [
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(title: cat.name, count: filteredItems.length),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final cp = filteredItems[index];
                final isNotOk = cp.status == 'Not OK';
                final isSelected = selectedCheckpoint?.id == cp.id;

                return InkWell(
                  onTap: () => onCheckpointSelected(cp),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                      color: isSelected ? Colors.blue[50]?.withValues(alpha: 0.3) : null,
                    ),
                    child: Row(
                      children: [
                        if (isNotOk) Container(width: 4, height: 40, color: Colors.red),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cp.title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            Text(cp.observation, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: filteredItems.length,
            ),
          ),
        ];
      }).toList(),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final int count;

  _StickyHeaderDelegate({required this.title, required this.count});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF1F3F5),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(10)),
            child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 48;
  @override
  double get minExtent => 48;
  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) => oldDelegate.title != title || oldDelegate.count != count;
}
