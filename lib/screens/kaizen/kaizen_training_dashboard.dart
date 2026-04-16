import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riqma_webapp/screens/kaizen/tabs/kaizen_proposals_tab.dart';
import 'package:riqma_webapp/screens/kaizen/tabs/training_materials_tab.dart';

class KaizenTrainingDashboard extends StatefulWidget {
  final int initialIndex;
  const KaizenTrainingDashboard({super.key, this.initialIndex = 0});

  @override
  State<KaizenTrainingDashboard> createState() => _KaizenTrainingDashboardState();
}

class _KaizenTrainingDashboardState extends State<KaizenTrainingDashboard> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      initialIndex: widget.initialIndex,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Kaizen & Training Center',
            style: GoogleFonts.outfit(
              color: const Color(0xFF1A1F36),
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A1F36)),
            onPressed: () => Navigator.pop(context),
          ),
          bottom: TabBar(
            labelColor: const Color(0xFF1A1F36),
            unselectedLabelColor: Colors.grey,
            labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            indicatorColor: const Color(0xFF1A1F36),
            tabs: const [
              Tab(text: 'Training Materials'),
              Tab(text: 'Kaizen Proposals'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            TrainingMaterialsTab(),
            KaizenProposalsTab(),
          ],
        ),
      ),
    );
  }
}
